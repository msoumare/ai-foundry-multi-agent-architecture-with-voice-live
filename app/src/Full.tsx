import React, { useCallback, useRef, useState } from "react";
import { VoiceLiveClient } from "@azure/ai-voicelive";
import type { AccessToken, TokenCredential } from "@azure/core-auth";

const DEFAULT_VOICE_LIVE_ENDPOINT = import.meta.env.VITE_VOICE_LIVE_ENDPOINT;
const DEFAULT_API_VERSION = import.meta.env.VITE_VOICE_LIVE_API_VERSION;
const DEFAULT_PROJECT_ENDPOINT = import.meta.env.VITE_FOUNDRY_PROJECT_ENDPOINT;
const DEFAULT_RESOURCE_OVERRIDE = import.meta.env.VITE_FOUNDRY_RESOURCE_OVERRIDE_DEFAULT;
const DEFAULT_AGENT_NAME = import.meta.env.VITE_EXPECTED_AGENT_NAME;
const DEFAULT_TOKEN_TTL_MS = Number(import.meta.env.VITE_TOKEN_TIMEOUT_SECONDS ?? "3600") * 1000;
const TURN_TIMEOUT_MS = 45_000;
const PCM_SAMPLE_RATE = 24_000;

type ConnectionStatus = "idle" | "connecting" | "connected";
type LogDirection = "in" | "out" | "sys";

type LogEntry = {
  ts: string;
  dir: LogDirection;
  text: string;
};

type ActiveRun = {
  runId: number;
  streamed: string;
  resolve: (value: string) => void;
  reject: (error: Error) => void;
  timeoutHandle: ReturnType<typeof setTimeout>;
  settled: boolean;
};

type ControlInvocation = {
  action: string;
  body: Record<string, unknown>;
  logLabel: string;
};

type AssistantBindGate = {
  pending: boolean;
  seenAssistantItemIds: Set<string>;
};

class StaticTokenCredential implements TokenCredential {
  constructor(
    private readonly token: string,
    private readonly ttlMs: number,
  ) {}

  async getToken(): Promise<AccessToken> {
    return {
      token: this.token,
      expiresOnTimestamp: Date.now() + this.ttlMs,
    };
  }
}

function normalizeBearerToken(value: string): string {
  return value.replace(/^Bearer\s+/i, "").trim();
}

function normalizeEndpoint(value: string): string {
  const normalized = value.trim().replace(/^wss:/i, "https:");
  const url = new URL(normalized);
  return `${url.protocol}//${url.host}`;
}

function extractProjectName(projectEndpoint: string): string {
  const url = new URL(projectEndpoint);
  const parts = url.pathname.split("/").filter(Boolean);
  const index = parts.indexOf("projects");
  if (index < 0 || !parts[index + 1]) {
    throw new Error("Project endpoint must contain /projects/{projectName}.");
  }
  return parts[index + 1];
}

function now(): string {
  return new Date().toLocaleTimeString("en-US", { hour12: false });
}

function formatTimeWithMs(epochMs: number): string {
  const date = new Date(epochMs);
  const hh = String(date.getHours()).padStart(2, "0");
  const mm = String(date.getMinutes()).padStart(2, "0");
  const ss = String(date.getSeconds()).padStart(2, "0");
  const mmm = String(date.getMilliseconds()).padStart(3, "0");
  return `${hh}:${mm}:${ss}.${mmm}`;
}

function parseMetadata(raw: unknown): unknown {
  if (typeof raw !== "string") return raw;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  try {
    return JSON.parse(trimmed);
  } catch {
    return trimmed;
  }
}

function normalizeInvocationDelta(
  delta: unknown,
): Record<string, unknown> | null {
  if (delta && typeof delta === "object") {
    return delta as Record<string, unknown>;
  }
  if (typeof delta === "string") {
    let cleaned = delta.trim();
    if (cleaned.startsWith("data: ")) cleaned = cleaned.slice(6).trim();
    if (!cleaned || cleaned === "[DONE]") return null;
    try {
      return JSON.parse(cleaned) as Record<string, unknown>;
    } catch {
      return null;
    }
  }
  return null;
}

function float32ToPcm16Bytes(samples: Float32Array): Uint8Array {
  const output = new Int16Array(samples.length);
  for (let index = 0; index < samples.length; index += 1) {
    const sample = Math.max(-1, Math.min(1, samples[index]));
    output[index] = sample < 0 ? sample * 32768 : sample * 32767;
  }
  return new Uint8Array(output.buffer);
}

function base64Pcm16ToFloat32(value: string): Float32Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const samples = new Float32Array(Math.floor(bytes.byteLength / 2));
  for (let index = 0; index < samples.length; index += 1) {
    samples[index] = view.getInt16(index * 2, true) / 32768;
  }
  return samples;
}

export function Full() {
  const [entraIdToken, setEntraIdToken] = useState("");
  const [messageInput, setMessageInput] = useState("");
  const [status, setStatus] = useState<ConnectionStatus>("idle");
  const [isRunning, setIsRunning] = useState(false);
  const [micActive, setMicActive] = useState(false);
  const [responseText, setResponseText] = useState("");
  const [liveText, setLiveText] = useState("");
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [userTranscript, setUserTranscript] = useState("");
  const [agentTranscript, setAgentTranscript] = useState("");
  const [streamedTextEvents, setStreamedTextEvents] = useState<string[]>([]);
  const [agentMetadata, setAgentMetadata] = useState<unknown>(null);

  const runRef = useRef(0);
  const logRef = useRef<HTMLPreElement>(null);
  const sessionRef = useRef<any>(null);
  const captureContextRef = useRef<AudioContext | null>(null);
  const playbackContextRef = useRef<AudioContext | null>(null);
  const micStreamRef = useRef<MediaStream | null>(null);
  const micSourceRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const processorRef = useRef<ScriptProcessorNode | null>(null);
  const muteGainRef = useRef<GainNode | null>(null);
  const nextPlaybackTimeRef = useRef(0);
  const responseStartRef = useRef<number | null>(null);
  const requestSentAtRef = useRef<number | null>(null);
  const requestSentWallClockRef = useRef<number | null>(null);
  const firstResponseAtRef = useRef<number | null>(null);
  const firstAudioAtRef = useRef<number | null>(null);
  const assistantTranscriptRef = useRef("");
  const scheduledAudioMsRef = useRef(0);
  const playbackSourcesRef = useRef<AudioBufferSourceNode[]>([]);
  const activeRunRef = useRef<ActiveRun | null>(null);
  const latestAssistantBufferRef = useRef("");
  const responseActiveRef = useRef(false);
  const pendingControlInvocationsRef = useRef<ControlInvocation[]>([]);
  const flushingControlInvocationsRef = useRef(false);
  const assistantBindGateRef = useRef<AssistantBindGate>({
    pending: false,
    seenAssistantItemIds: new Set<string>(),
  });

  const addLog = useCallback((dir: LogDirection, text: string) => {
    setLogs((previous) => [...previous.slice(-299), { ts: now(), dir, text }]);
    requestAnimationFrame(() => {
      if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
    });
  }, []);

  const addStreamedTextEvent = useCallback((text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;
    setStreamedTextEvents((previous) => [...previous.slice(-19), trimmed]);
  }, []);

  const clearActiveRun = useCallback(() => {
    const current = activeRunRef.current;
    if (!current) return;
    clearTimeout(current.timeoutHandle);
    activeRunRef.current = null;
  }, []);

  const settleActiveRun = useCallback((finalText: string) => {
    const current = activeRunRef.current;
    if (!current || current.settled) return;
    current.settled = true;
    clearTimeout(current.timeoutHandle);
    current.resolve(finalText);
    activeRunRef.current = null;
  }, []);

  const rejectActiveRun = useCallback((error: Error) => {
    const current = activeRunRef.current;
    if (!current || current.settled) return;
    current.settled = true;
    clearTimeout(current.timeoutHandle);
    current.reject(error);
    activeRunRef.current = null;
  }, []);

  const sendControlInvocationNow = useCallback(
    async (control: ControlInvocation) => {
      const session = sessionRef.current;
      if (!session) return;

      const invokeInput = { action: control.action, ...control.body };
      await session.addConversationItem({
        type: "message",
        role: "user",
        content: [{ type: "input_text", text: JSON.stringify(invokeInput) }],
      } as any);
      await session.sendEvent({
        type: "response.create",
        response: {
          invokeInput,
        },
      } as any);
      addLog("out", `${control.logLabel}: ${JSON.stringify(control.body)}`);
    },
    [addLog],
  );

  const flushControlInvocations = useCallback(async () => {
    if (flushingControlInvocationsRef.current) return;
    if (responseActiveRef.current) return;
    if (!sessionRef.current) return;

    flushingControlInvocationsRef.current = true;
    try {
      while (
        pendingControlInvocationsRef.current.length > 0 &&
        !responseActiveRef.current
      ) {
        const next = pendingControlInvocationsRef.current[0];
        try {
          await sendControlInvocationNow(next);
          pendingControlInvocationsRef.current.shift();
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          if (message.includes("conversation_already_has_active_response")) {
            addLog("sys", "Control invocation deferred: active response");
            return;
          }
          addLog("sys", `Control invocation failed (${next.action}): ${message}`);
          pendingControlInvocationsRef.current.shift();
        }
      }
    } finally {
      flushingControlInvocationsRef.current = false;
    }
  }, [addLog, sendControlInvocationNow]);

  const enqueueControlInvocation = useCallback(
    async (control: ControlInvocation) => {
      pendingControlInvocationsRef.current.push(control);
      await flushControlInvocations();
    },
    [flushControlInvocations],
  );

  const stopPlayback = useCallback(() => {
    for (const source of playbackSourcesRef.current) {
      try {
        source.stop();
      } catch {
        // Source may have already ended; ignore.
      }
    }
    playbackSourcesRef.current = [];
    if (playbackContextRef.current) {
      nextPlaybackTimeRef.current = playbackContextRef.current.currentTime;
    }
    setAgentTranscript("");
  }, []);

  const clearResponseTracking = useCallback(() => {
    responseStartRef.current = null;
    requestSentAtRef.current = null;
    requestSentWallClockRef.current = null;
    firstResponseAtRef.current = null;
    firstAudioAtRef.current = null;
    assistantTranscriptRef.current = "";
    scheduledAudioMsRef.current = 0;
  }, []);

  const buildInterruption = useCallback((event: any) => {
    const totalChars = assistantTranscriptRef.current.length;
    const scheduledMs = scheduledAudioMsRef.current;
    const start = responseStartRef.current;
    if (start === null || (totalChars === 0 && scheduledMs === 0)) {
      return null;
    }

    const audioEndMs = Number(event?.audioEndInMs ?? event?.audio_end_ms ?? 0);
    const spokenChars =
      totalChars > 0 && scheduledMs > 0
        ? Math.min(
            totalChars,
            Math.round(totalChars * Math.min(1, audioEndMs / scheduledMs)),
          )
        : null;

    return {
      itemId: event?.itemId ?? event?.item_id ?? null,
      audioEndMs: audioEndMs || null,
      spokenChars,
      totalChars: totalChars || null,
      audioFirstMs:
        firstAudioAtRef.current !== null
          ? Math.round(firstAudioAtRef.current - start)
          : null,
      elapsedMs: Math.round(performance.now() - start),
    };
  }, []);

  const reportInterruption = useCallback(
    async (event: any) => {
      addLog(
        "sys",
        `Barge-in: item=${event?.itemId ?? "unknown"} content_index=${event?.contentIndex ?? 0}`,
      );

      stopPlayback();

      const interruption = buildInterruption(event);
      if (!interruption) {
        addLog("sys", "Barge-in ignored (truncated): no assistant turn was playing");
        return;
      }

      clearResponseTracking();
      await enqueueControlInvocation({
        action: "interruption",
        body: { interruption },
        logLabel: "Barge-in reported",
      });
    },
    [addLog, buildInterruption, clearResponseTracking, enqueueControlInvocation, stopPlayback],
  );

  const stopMicrophone = useCallback(async () => {
    if (processorRef.current) {
      processorRef.current.onaudioprocess = null;
      processorRef.current.disconnect();
    }
    micSourceRef.current?.disconnect();
    muteGainRef.current?.disconnect();
    micStreamRef.current?.getTracks().forEach((track) => track.stop());
    await captureContextRef.current?.close();

    processorRef.current = null;
    micSourceRef.current = null;
    muteGainRef.current = null;
    micStreamRef.current = null;
    captureContextRef.current = null;
    setMicActive(false);
  }, []);

  const disconnect = useCallback(async () => {
    await stopMicrophone();
    stopPlayback();
    clearActiveRun();
    try {
      const s = sessionRef.current;
      if (s?.dispose) {
        await s.dispose();
      }
    } catch {
      addLog("sys", "Session dispose failed (ignored).");
    }
    await playbackContextRef.current?.close();
    playbackContextRef.current = null;
    nextPlaybackTimeRef.current = 0;
    sessionRef.current = null;
    setStatus("idle");
    setIsRunning(false);
    responseActiveRef.current = false;
    pendingControlInvocationsRef.current = [];
    assistantBindGateRef.current.pending = false;
    assistantBindGateRef.current.seenAssistantItemIds.clear();
    clearResponseTracking();
    addLog("sys", "Disconnected");
  }, [addLog, clearActiveRun, clearResponseTracking, stopMicrophone, stopPlayback]);

  const connect = useCallback(async () => {
    if (sessionRef.current) return sessionRef.current;

    const token = normalizeBearerToken(entraIdToken);
    if (!token) {
      addLog("sys", "Missing Entra ID token.");
      return null;
    }

    setStatus("connecting");
    addLog("sys", "Connecting...");

    try {
      const client = new VoiceLiveClient(
        normalizeEndpoint(DEFAULT_VOICE_LIVE_ENDPOINT),
        new StaticTokenCredential(token, DEFAULT_TOKEN_TTL_MS),
        { apiVersion: DEFAULT_API_VERSION },
      );

      const agent: Record<string, string> = {
        agentName: DEFAULT_AGENT_NAME,
        projectName: extractProjectName(DEFAULT_PROJECT_ENDPOINT),
      };

      if (DEFAULT_RESOURCE_OVERRIDE.trim()) {
        agent.foundryResourceOverride = DEFAULT_RESOURCE_OVERRIDE.trim();
      }

      playbackContextRef.current = new AudioContext({
        sampleRate: PCM_SAMPLE_RATE,
      });

      const sessionHandlers = {
        onSessionCreated: async (event: any) => {
          addLog("sys", `Session created: ${event?.session?.id ?? "unknown"}`);
        },
        onSessionUpdated: async (event: any) => {
          addLog("sys", `Session updated: ${event?.session?.id ?? "unknown"}`);
        },
        onConversationItemCreated: async (event: any) => {
          const conversationId = event?.item?.conversationId || event?.item?.conversation_id;
          if (conversationId) addLog("sys", `Active Conversation: ${conversationId}`);

          const item = event?.item;
          const role = typeof item?.role === "string" ? item.role : "";
          const itemIdRaw = item?.id ?? item?.itemId ?? item?.item_id;
          const itemId = typeof itemIdRaw === "string" ? itemIdRaw.trim() : "";

          if (
            role === "assistant" &&
            itemId &&
            assistantBindGateRef.current.pending &&
            !assistantBindGateRef.current.seenAssistantItemIds.has(itemId)
          ) {
            assistantBindGateRef.current.pending = false;
            assistantBindGateRef.current.seenAssistantItemIds.add(itemId);
            await enqueueControlInvocation({
              action: "assistant_item_bind",
              body: { assistantItem: { itemId } },
              logLabel: "Assistant item bound",
            });
          }
        },
        onConversationItemInputAudioTranscriptionCompleted: async (event: any) => {
          const transcript = String(event?.transcript ?? "").trim();
          if (!transcript) return;
          requestSentAtRef.current = performance.now();
          requestSentWallClockRef.current = Date.now();
          firstResponseAtRef.current = null;
          assistantBindGateRef.current.pending = true;
          setUserTranscript(transcript);
          addLog("out", `You (voice): ${transcript}`);
        },
        onResponseCreated: async (_event: any) => {
          responseActiveRef.current = true;
          responseStartRef.current = performance.now();
          if (
            requestSentAtRef.current !== null &&
            firstResponseAtRef.current === null
          ) {
            firstResponseAtRef.current = performance.now();
          }
          firstAudioAtRef.current = null;
          scheduledAudioMsRef.current = 0;
          assistantTranscriptRef.current = "";
          latestAssistantBufferRef.current = "";
          setAgentTranscript("");
          addLog("sys", "Response created.");
        },
        onResponseAudioTranscriptDelta: async (event: any) => {
          if (
            requestSentAtRef.current !== null &&
            firstResponseAtRef.current === null
          ) {
            firstResponseAtRef.current = performance.now();
          }
          const delta = String(event?.delta ?? "");
          if (delta) {
            assistantTranscriptRef.current += delta;
            latestAssistantBufferRef.current += delta;
            setAgentTranscript((previous) => previous + delta);
            addLog("in", `Agent (response.audio_transcript.delta): ${delta}`);
          }
        },
        onResponseAudioTranscriptDone: async (event: any) => {
          const clean = String(event?.transcript ?? event?.text ?? "").trim();
          if (clean) {
            addLog("in", `Agent audio transcript complete (${clean.length} chars)`);
            addStreamedTextEvent(clean);
          }
          setAgentTranscript("");
        },
        onResponseTextDelta: async (event: any) => {
          if (
            requestSentAtRef.current !== null &&
            firstResponseAtRef.current === null
          ) {
            firstResponseAtRef.current = performance.now();
          }
          const delta = String(event?.delta ?? "");
          if (!delta) return;

          latestAssistantBufferRef.current += delta;
          setAgentTranscript((previous) => previous + delta);
          addLog("in", `Agent : ${delta}`);

          const run = activeRunRef.current;
          if (run) {
            run.streamed += delta;
            if (runRef.current === run.runId) {
              setLiveText(run.streamed);
            }
          }
        },
        onResponseTextDone: async (event: any) => {
          const final = String(event?.text ?? "").trim();
          if (final) {
            latestAssistantBufferRef.current = final;
            addStreamedTextEvent(final);
            const run = activeRunRef.current;
            if (run) run.streamed = final;
          }
          setAgentTranscript("");
        },
        onResponseDone: async () => {
          const doneAtClock = Date.now();
          const sentAt = requestSentAtRef.current;
          const sentWallClock = requestSentWallClockRef.current;
          const firstAt = firstResponseAtRef.current;
          if (sentAt !== null) {
            const firstResponseMs =
              firstAt !== null ? Math.round(firstAt - sentAt) : null;
            const firstResponseAt =
              sentWallClock !== null && firstResponseMs !== null
                ? formatTimeWithMs(sentWallClock + firstResponseMs)
                : null;
            addLog(
              "sys",
              `Timing: requested_at ${formatTimeWithMs(sentWallClock ?? Date.now())}, first_response ${firstResponseAt ?? "n/a"}, completed ${formatTimeWithMs(doneAtClock)}`,
            );
          }
          addLog("sys", "Response done.");
          const run = activeRunRef.current;
          const finalText =
            (run?.streamed ?? "").trim() ||
            latestAssistantBufferRef.current.trim() ||
            "(empty response)";
          setResponseText(finalText);
          setLiveText("");
          responseActiveRef.current = false;
          requestSentAtRef.current = null;
          requestSentWallClockRef.current = null;
          firstResponseAtRef.current = null;
          await new Promise((resolve) => setTimeout(resolve, 50));
          await flushControlInvocations();
          settleActiveRun(finalText);
        },
        onConversationItemTruncated: async (event: any) => {
          await reportInterruption(event);
        },
        onResponseAudioDelta: async (event: any) => {
          const context = playbackContextRef.current;
          if (!context || !event?.delta) return;

          if (firstAudioAtRef.current === null) {
            firstAudioAtRef.current = performance.now();
          }

          const samples = base64Pcm16ToFloat32(String(event.delta));
          const buffer = context.createBuffer(1, samples.length, PCM_SAMPLE_RATE);
          buffer.copyToChannel(Float32Array.from(samples), 0);
          const source = context.createBufferSource();
          source.buffer = buffer;
          source.connect(context.destination);

          const startAt = Math.max(context.currentTime, nextPlaybackTimeRef.current);
          source.start(startAt);
          nextPlaybackTimeRef.current = startAt + buffer.duration;

          scheduledAudioMsRef.current += buffer.duration * 1000;
          playbackSourcesRef.current.push(source);
          source.onended = () => {
            playbackSourcesRef.current = playbackSourcesRef.current.filter(
              (candidate) => candidate !== source,
            );
          };
        },
        onServerEvent: async (event: any) => {
          const eventType = String(event?.type ?? "unknown");

          if (eventType === "response.invocation.delta") {
            const inner = normalizeInvocationDelta(event?.delta);

            if (inner && inner.type === "hubagent.metadata") {
              const data = parseMetadata(inner.data) ?? null;
              setAgentMetadata(data);
              addLog("in", `HubAgent metadata: ${JSON.stringify(data)}`);
            }

            if (inner && inner.type === "hubagent.conversation") {
              addLog("in", `HubAgent conversation: ${JSON.stringify(inner.data)}`);
            }
            return;
          }

          addLog("sys", `Server event: ${eventType} ${JSON.stringify(event)}`);
        },
        onServerError: async (event: any) => {
          const error = new Error(`Server error: ${JSON.stringify(event)}`);
          rejectActiveRun(error);
          addLog("sys", error.message);
        },
        onError: async (event: any) => {
          const error = new Error(`Client error: ${JSON.stringify(event)}`);
          rejectActiveRun(error);
          addLog("sys", error.message);
        },
      };

      const session = await client.startSession({ agent } as any, { sessionHandlers } as any);
      sessionRef.current = session;

      await session.updateSession({
        modalities: ["text", "audio"],
        turnDetection: {
          type: "azure_semantic_vad",
          interruptResponse: true,
          autoTruncate: true,
        },
        metadata: {
          debug_logging: "true",
          token_timeout_seconds: "60",
        },
      });

      setStatus("connected");
      addLog("sys", "Connected - ready");
      return session;
    } catch (error) {
      setStatus("idle");
      addLog(
        "sys",
        `Connect failed: ${error instanceof Error ? error.message : String(error)}`,
      );
      return null;
    }
  }, [
    addLog,
    addStreamedTextEvent,
    enqueueControlInvocation,
    entraIdToken,
    flushControlInvocations,
    reportInterruption,
    rejectActiveRun,
    settleActiveRun,
  ]);

  const toggleMicrophone = useCallback(async () => {
    if (micActive) {
      await stopMicrophone();
      addLog("sys", "Microphone stopped");
      return;
    }

    const session = sessionRef.current ?? (await connect());
    if (!session) return;

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          sampleRate: PCM_SAMPLE_RATE,
        },
        video: false,
      });

      const context = new AudioContext({ sampleRate: PCM_SAMPLE_RATE });
      await context.resume();
      const source = context.createMediaStreamSource(stream);
      const processor = context.createScriptProcessor(2048, 1, 1);
      const muteGain = context.createGain();
      muteGain.gain.value = 0;

      processor.onaudioprocess = (event) => {
        const activeSession = sessionRef.current;
        if (!activeSession) return;
        const samples = event.inputBuffer.getChannelData(0);
        const bytes = float32ToPcm16Bytes(samples);
        Promise.resolve(activeSession.sendAudio(bytes)).catch((error) => {
          addLog(
            "sys",
            `sendAudio failed: ${error instanceof Error ? error.message : String(error)}`,
          );
        });
      };

      source.connect(processor);
      processor.connect(muteGain);
      muteGain.connect(context.destination);

      micStreamRef.current = stream;
      captureContextRef.current = context;
      micSourceRef.current = source;
      processorRef.current = processor;
      muteGainRef.current = muteGain;
      setMicActive(true);
      addLog("sys", "Microphone started - speak now");
    } catch (error) {
      addLog(
        "sys",
        `Microphone error: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }, [addLog, connect, micActive, stopMicrophone]);

  const runSingleTurn = useCallback(async () => {
    const text = messageInput.trim();
    if (!text) {
      addLog("sys", "Message cannot be empty.");
      return;
    }

    if (activeRunRef.current) {
      addLog("sys", "A request is already in progress.");
      return;
    }

    setIsRunning(true);
    const session = await connect();
    if (!session) {
      setIsRunning(false);
      return;
    }

    const runId = Date.now();
    runRef.current = runId;
    setResponseText("");
    setLiveText("");
    setUserTranscript(text);
    setAgentTranscript("");
    setStreamedTextEvents([]);
    setAgentMetadata(null);
    requestSentAtRef.current = performance.now();
    requestSentWallClockRef.current = Date.now();
    firstResponseAtRef.current = null;
    assistantBindGateRef.current.pending = true;
    addLog("sys", "Starting one-click flow: session create, update, send, receive.");
    addLog("out", `You (text): ${text}`);

    try {
      const finalResponsePromise = new Promise<string>((resolve, reject) => {
        const timeoutHandle = setTimeout(() => {
          rejectActiveRun(new Error("Timed out waiting for response.done."));
        }, TURN_TIMEOUT_MS);

        activeRunRef.current = {
          runId,
          streamed: "",
          resolve,
          reject,
          timeoutHandle,
          settled: false,
        };
      });

      await session.addConversationItem({
        type: "message",
        role: "user",
        metadata: {
          expected_agent_name: DEFAULT_AGENT_NAME,
          resource_override: DEFAULT_RESOURCE_OVERRIDE,
        },
        content: [{ type: "input_text", text }],
      } as any);

      await session.sendEvent({
        type: "response.create",
        response: { modalities: ["text"] },
      } as any);

      addLog("out", "Conversation item sent. Waiting for response...");

      const finalResponse = await finalResponsePromise;
      if (runRef.current === runId) {
        setResponseText(finalResponse || "(empty response)");
        setLiveText("");
      }
      addLog("sys", "Flow completed successfully.");
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      addLog("sys", `Flow failed: ${message}`);
      clearActiveRun();
    } finally {
      if (runRef.current === runId) {
        setIsRunning(false);
      }
    }
  }, [addLog, clearActiveRun, connect, messageInput, rejectActiveRun]);

  const connected = status === "connected";

  return (
    <div className="app">
      <h1>Hub Agent Full One-Click</h1>
      <p className="subtitle">
        One click can create/update session and send text. You can also use live microphone input.
      </p>

      <div className="card card-config">
        <label>
          Entra ID token (Bearer token or raw JWT)
          <textarea
            value={entraIdToken}
            onChange={(event) => setEntraIdToken(event.target.value)}
            rows={4}
            disabled={connected || isRunning}
            placeholder="Paste Entra ID access token"
          />
        </label>
      </div>

      <div className="card card-controls">
        <div className="row">
          <button
            onClick={() => void toggleMicrophone()}
            disabled={status === "connecting" || isRunning || !entraIdToken.trim()}
          >
            {micActive ? "Stop Microphone (Speech)" : "Connect + Microphone (Speech)"}
          </button>
          <span className={`status-pill status-${status}`}>
            ● {status}
          </span>
        </div>
      </div>

      <div className="card card-message">
        <label>
          Message text
          <textarea
            value={messageInput}
            onChange={(event) => setMessageInput(event.target.value)}
            rows={3}
            disabled={isRunning}
            placeholder="Type the user message"
          />
        </label>

        <div className="row" style={{ marginTop: "0.6rem" }}>
          <button
            onClick={() => void runSingleTurn()}
            disabled={
              isRunning ||
              (!connected && !entraIdToken.trim()) ||
              !messageInput.trim()
            }
          >
            {isRunning ? "Running..." : "Connect + Send Message (Text)"}
          </button>
        </div>
      </div>

      <div className="card card-live">
        {userTranscript && (
          <div>
            <strong>You:</strong> {userTranscript}
          </div>
        )}

        {agentTranscript && (
          <div className="live-inline-text" style={{ marginTop: "0.35rem" }}>
            <strong>Live:</strong> {agentTranscript}
          </div>
        )}

        <div className="metadata-label">Live streamed text</div>
        {liveText ? (
          <pre className="metadata-json">{liveText}</pre>
        ) : (
          <div className="live-empty">No streamed text yet.</div>
        )}

        <div style={{ marginTop: "0.6rem" }} className="metadata-label">
          Streamed Text Events
        </div>
        {streamedTextEvents.length === 0 ? (
          <div className="live-empty">No streamed text events yet.</div>
        ) : (
          <pre className="metadata-json">
            {streamedTextEvents
              .map((eventText, index) => `${index + 1}. ${eventText}`)
              .join("\n\n")}
          </pre>
        )}

        <div style={{ marginTop: "0.6rem" }} className="metadata-label">
          HubAgent Metadata
        </div>
        {agentMetadata === null ? (
          <div className="live-empty">Waiting for metadata...</div>
        ) : (
          <pre className="metadata-json">{JSON.stringify(agentMetadata, null, 2)}</pre>
        )}

        <div style={{ marginTop: "0.6rem" }} className="metadata-label">
          Final response
        </div>
        {responseText ? (
          <pre className="metadata-json">{responseText}</pre>
        ) : (
          <div className="live-empty">No response yet.</div>
        )}
      </div>

      <div className="card card-log">
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            marginBottom: "0.4rem",
          }}
        >
          <strong>Event Log</strong>
          <button
            className="btn-ghost"
            style={{ fontSize: "0.8rem", padding: "0.2rem 0.5rem" }}
            onClick={() => setLogs([])}
          >
            Clear
          </button>
        </div>
        <pre ref={logRef} className="log">
          {logs.length === 0
            ? <span style={{ color: "#6b7280" }}>No events yet.</span>
            : logs.map((entry, index) => (
                <div
                  key={index}
                  style={{
                    color:
                      entry.dir === "in"
                        ? "#6ee7b7"
                        : entry.dir === "out"
                          ? "#93c5fd"
                          : "#d1d5db",
                  }}
                >
                  [{entry.ts}] {entry.dir.toUpperCase().padEnd(3)} {entry.text}
                </div>
              ))}
        </pre>
      </div>
    </div>
  );
}
