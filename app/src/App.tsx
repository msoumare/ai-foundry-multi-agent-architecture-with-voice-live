import React, { useCallback, useRef, useState } from "react";
import { VoiceLiveClient } from "@azure/ai-voicelive";
import type { AccessToken, TokenCredential } from "@azure/core-auth";

const DEFAULT_VOICE_LIVE_ENDPOINT = import.meta.env.VITE_VOICE_LIVE_ENDPOINT;
const DEFAULT_API_VERSION = import.meta.env.VITE_VOICE_LIVE_API_VERSION ?? "2026-04-10";
const DEFAULT_PROJECT_ENDPOINT = import.meta.env.VITE_FOUNDRY_PROJECT_ENDPOINT ;
const DEFAULT_RESOURCE_OVERRIDE = import.meta.env.VITE_FOUNDRY_RESOURCE_OVERRIDE_DEFAULT;
const DEFAULT_AGENT_NAME = import.meta.env.VITE_EXPECTED_AGENT_NAME;
const DEFAULT_TOKEN_TTL_MS = Number(import.meta.env.VITE_TOKEN_TIMEOUT_SECONDS ?? "3600") * 1000;
const PCM_SAMPLE_RATE = 24_000;

type ConnectionStatus = "idle" | "connecting" | "connected";
type LogDirection = "in" | "out" | "sys";

type LogEntry = {
  ts: string;
  dir: LogDirection;
  text: string;
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

function formatDurationMs(durationMs: number | null): string {
  if (durationMs === null) return "n/a";
  const totalMs = Math.max(0, durationMs);
  const hours = Math.floor(totalMs / 3_600_000);
  const minutes = Math.floor((totalMs % 3_600_000) / 60_000);
  const seconds = Math.floor((totalMs % 60_000) / 1000);
  const milliseconds = totalMs % 1000;
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}.${String(milliseconds).padStart(3, "0")}`;
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

function float32ToPcm16Bytes(samples: Float32Array): Uint8Array {
  const output = new Int16Array(samples.length);
  for (let index = 0; index < samples.length; index += 1) {
    const sample = Math.max(-1, Math.min(1, samples[index]));
    output[index] = sample < 0 ? sample * 32768 : sample * 32767;
  }
  return new Uint8Array(output.buffer);
}

export function App() {
  const [voiceLiveEndpoint, setVoiceLiveEndpoint] = useState(
    DEFAULT_VOICE_LIVE_ENDPOINT,
  );
  const [projectEndpoint, setProjectEndpoint] = useState(
    DEFAULT_PROJECT_ENDPOINT,
  );
  const [resourceOverride, setResourceOverride] = useState(
    DEFAULT_RESOURCE_OVERRIDE,
  );
  const [bearerToken, setBearerToken] = useState("");
  const [messageInput, setMessageInput] = useState("");
  const [status, setStatus] = useState<ConnectionStatus>("idle");
  const [micActive, setMicActive] = useState(false);
  const [userTranscript, setUserTranscript] = useState("");
  const [agentTranscript, setAgentTranscript] = useState("");
  const [streamedTextEvents, setStreamedTextEvents] = useState<string[]>([]);
  const [agentMetadata, setAgentMetadata] = useState<unknown>(null);
  const [latestTiming, setLatestTiming] = useState<{
    requestedAt: string;
    firstResponseAt: string | null;
    completedAt: string | null;
  } | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const logRef             = useRef<HTMLPreElement>(null);
  const sessionRef = useRef<any>(null);
  const subscriptionRef = useRef<any>(null);
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
  const assistantTranscriptRef = useRef<string>("");
  const scheduledAudioMsRef = useRef<number>(0);
  const playbackSourcesRef = useRef<AudioBufferSourceNode[]>([]);
  const responseActiveRef = useRef(false);
  const pendingControlInvocationsRef = useRef<ControlInvocation[]>([]);
  const flushingControlInvocationsRef = useRef(false);
  const assistantBindGateRef = useRef<AssistantBindGate>({
    pending: false,
    seenAssistantItemIds: new Set<string>(),
  });

  const addLog = useCallback((dir: LogDirection, text: string) => {
    setLogs((previous) => [
      ...previous.slice(-299),
      { ts: now(), dir, text },
    ]);
    requestAnimationFrame(() => {
      if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
    });    
  }, []);

  const addStreamedTextEvent = useCallback((text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;
    setStreamedTextEvents((previous) => [...previous.slice(-19), trimmed]);
  }, []);

  const sendControlInvocationNow = useCallback(
    async (control: ControlInvocation) => {
      const session = sessionRef.current;
      if (!session) return;

      const invokeInput = { action: control.action, ...control.body };
      if (control.action === "interruption") {
        addLog("sys", `Interruption send started: ${JSON.stringify(invokeInput)}`);
      }
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
      if (control.action === "interruption") {
        addLog("sys", "Interruption send completed");
      }
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
          const message =
            error instanceof Error ? error.message : String(error);
          if (message.includes("conversation_already_has_active_response")) {
            addLog("sys", "Control invocation deferred: active response");
            return;
          }
          addLog(
            "sys",
            `Control invocation failed (${next.action}): ${message}`,
          );
          pendingControlInvocationsRef.current.shift();
        }
      }
    } finally {
      flushingControlInvocationsRef.current = false;
    }
  }, [addLog, sendControlInvocationNow]);

  const enqueueControlInvocation = useCallback(
    async (control: ControlInvocation) => {
      if (control.action === "interruption") {
        addLog("sys", `Interruption enqueued: ${JSON.stringify(control.body)}`);
      }
      pendingControlInvocationsRef.current.push(control);
      await flushControlInvocations();
    },
    [addLog, flushControlInvocations],
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

      let interruption = buildInterruption(event);
      if (!interruption && responseStartRef.current !== null) {
        const elapsedMs = Math.round(performance.now() - responseStartRef.current);
        const totalChars = assistantTranscriptRef.current.length || null;
        interruption = {
          itemId: event?.itemId ?? event?.item_id ?? null,
          audioEndMs: Number(event?.audioEndInMs ?? event?.audio_end_ms ?? 0) || null,
          spokenChars: totalChars,
          totalChars,
          audioFirstMs:
            firstAudioAtRef.current !== null
              ? Math.round(firstAudioAtRef.current - responseStartRef.current)
              : null,
          elapsedMs,
        };
        addLog("sys", "Interruption fallback payload synthesized (truncated)");
      }

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
    [
      addLog,
      buildInterruption,
      clearResponseTracking,
      enqueueControlInvocation,
      stopPlayback,
    ],
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
    subscriptionRef.current?.unsubscribe?.();
    subscriptionRef.current = null;
    try {
      await sessionRef.current?.dispose?.();
    } catch {
      // Ignore close errors.
    }
    sessionRef.current = null;
    await playbackContextRef.current?.close();
    playbackContextRef.current = null;
    nextPlaybackTimeRef.current = 0;
    responseActiveRef.current = false;
    pendingControlInvocationsRef.current = [];
    assistantBindGateRef.current.pending = false;
    assistantBindGateRef.current.seenAssistantItemIds.clear();
    setStatus("idle");
    setAgentTranscript("");
    setStreamedTextEvents([]);
    setAgentMetadata(null);
    addLog("sys", "Disconnected");
  }, [addLog, stopMicrophone]);

  const connect = useCallback(async () => {
    const token = normalizeBearerToken(bearerToken);
    if (!token) {
      addLog("sys", "Paste a bearer token before connecting.");
      return;
    }

    setStatus("connecting");
    addLog("sys", "Connecting...");

    try {
      const client = new VoiceLiveClient(
        normalizeEndpoint(voiceLiveEndpoint),
        new StaticTokenCredential(token, DEFAULT_TOKEN_TTL_MS),
        { apiVersion: DEFAULT_API_VERSION },
      );

      const agent: Record<string, string> = {
        agentName: DEFAULT_AGENT_NAME,
        projectName: extractProjectName(projectEndpoint),
      };
      if (resourceOverride.trim()) {
        agent.foundryResourceOverride = resourceOverride.trim();
      }

      playbackContextRef.current = new AudioContext({
        sampleRate: PCM_SAMPLE_RATE,
      });

      const sessionHandlers = {
        onSessionCreated: async (event: any) => {
          setStatus("connected");
          addLog("sys", `Session created: ${event?.session?.id ?? "unknown"}`);
        },
        onSessionUpdated: async (event: any) => {
          addLog("sys", `Session updated: ${event?.session?.id ?? "unknown"}`);
        },
        onConversationItemCreated: async (event: any) => {
          // In text-driven shifts, the item often carries the active conversation context
          const conversationId = event.item?.conversationId || event.item?.conversation_id;
          if (conversationId) {
            addLog("sys", `Active Conversation: ${conversationId}`);
          }

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

        onResponseCreated: async (event: any) => {
          responseActiveRef.current = true;
          responseStartRef.current = performance.now();
          if (
            requestSentAtRef.current !== null &&
            firstResponseAtRef.current === null
          ) {
            firstResponseAtRef.current = performance.now();
          }
          firstAudioAtRef.current = null;
          assistantTranscriptRef.current = "";
          scheduledAudioMsRef.current = 0;
          const conversationId = event.response?.conversationId;             
          if (conversationId) {
            console.log("Verified Conversation ID:", conversationId);
          } else {
            console.log("Response created, checking raw schema...", event);
          }
        },
        onResponseDone: async (event: any) => {
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
            setLatestTiming({
              requestedAt: formatTimeWithMs(sentWallClock ?? Date.now()),
              firstResponseAt,
              completedAt: formatTimeWithMs(doneAtClock),
            });
            addLog(
              "sys",
              `Timing: requested_at ${formatTimeWithMs(sentWallClock ?? Date.now())}, first_response ${firstResponseAt ?? "n/a"}, completed ${formatTimeWithMs(doneAtClock)}`,
            );
          }

          responseActiveRef.current = false;
          requestSentAtRef.current = null;
          requestSentWallClockRef.current = null;
          firstResponseAtRef.current = null;
          await new Promise((resolve) => setTimeout(resolve, 50));
          await flushControlInvocations();
          const conversationId = event.response?.conversationId;
          console.log("Finished Turn for Conversation:", conversationId);
        },
        onConversationItemTruncated: async (event: any) => {
          await reportInterruption(event);
        },
        onConversationItemInputAudioTranscriptionCompleted: async (
          event: any,
        ) => {
          const text = String(event?.transcript ?? "").trim();
          if (text) {
            requestSentAtRef.current = performance.now();
            requestSentWallClockRef.current = Date.now();
            firstResponseAtRef.current = null;
            assistantBindGateRef.current.pending = true;
            setUserTranscript(text);
            addLog("out", `You (voice): ${text}`);
          }
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
            // Mirror into a ref so total spoken length is known at barge-in time.
            assistantTranscriptRef.current += delta;
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
          if (delta) {
            setAgentTranscript((previous) => previous + delta);
            addLog("in", `Agent : ${delta}`);
          }
        },
        onResponseTextDone: async (event: any) => {
          const text = String(event?.text ?? "").trim();
          if (text) {
            addStreamedTextEvent(text);
          }
          setAgentTranscript("");
        },
        onResponseAudioDelta: async (event: any) => {
          const context = playbackContextRef.current;
          if (!context || !event?.delta) return;

          // First audio of this turn: mark the moment for audioFirstMs.
          if (firstAudioAtRef.current === null) {
            firstAudioAtRef.current = performance.now();
          }

          const samples = base64Pcm16ToFloat32(String(event.delta));
          const buffer = context.createBuffer(
            1,
            samples.length,
            PCM_SAMPLE_RATE,
          );
          buffer.copyToChannel(Float32Array.from(samples), 0);
          const source = context.createBufferSource();
          source.buffer = buffer;
          source.connect(context.destination);

          const startAt = Math.max(
            context.currentTime,
            nextPlaybackTimeRef.current,
          );
          source.start(startAt);
          nextPlaybackTimeRef.current = startAt + buffer.duration;

          // Track scheduled audio so a barge-in can estimate how much was heard,
          // and keep a handle so playback can be stopped instantly on truncation.
          scheduledAudioMsRef.current += buffer.duration * 1000;
          playbackSourcesRef.current.push(source);
          source.onended = () => {
            playbackSourcesRef.current = playbackSourcesRef.current.filter(
              (candidate) => candidate !== source,
            );
          };
        },
        onServerError: async (event: any) => {
          addLog("sys", `Server error: ${JSON.stringify(event)}`);
        },
        onError: async (event: any) => {
          addLog("sys", `Error: ${JSON.stringify(event)}`);
        },
        onServerEvent: async (event: any) => {
          const eventType = String(event?.type ?? "unknown");
    
          if (eventType === "response.invocation.delta") {
            const inner = normalizeInvocationDelta(event?.delta);
            
            if (inner && (inner.type === "hubagent.metadata")) {
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
      };

      const session = await client.startSession(
        { agent } as any,
        { sessionHandlers } as any,
      );
      sessionRef.current = session;

      await session.updateSession({
        modalities: ['text', 'audio'],        
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
    } catch (error) {
      setStatus("idle");
      addLog(
        "sys",
        `Connect failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }, [
    addLog,
    addStreamedTextEvent,
    bearerToken,
    flushControlInvocations,
    projectEndpoint,
    reportInterruption,
    resourceOverride,
    voiceLiveEndpoint,
  ]);

  const toggleMicrophone = useCallback(async () => {
    const session = sessionRef.current;
    if (!session) return;

    if (micActive) {
      await stopMicrophone();
      addLog("sys", "Microphone stopped");
      return;
    }

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
  }, [addLog, micActive, stopMicrophone]);

  const sendMessage = useCallback(async () => {
    const session = sessionRef.current;
    const text = messageInput.trim();
    if (!session || !text) return;

    assistantBindGateRef.current.pending = true;
    setUserTranscript(text);
    setMessageInput("");
    addLog("out", `You (text): ${text}`);

    try {
      //   await session.addConversationItem({
      //   type: "message",
      //   role: "user",
      //   content: [
      //     {
      //         type: "input_text",
      //         text: `{ "action": "chat_message", "data": "${text}" }`,
      //       },
      //   ]
      // } as any);

      await session.addConversationItem({
        type: "message",
        role: "user",
        metadata: {
          expected_agent_name: DEFAULT_AGENT_NAME,
          resource_override: resourceOverride,
        },
        content: [
          {
            type: "input_text",
            text,
          },
        ],
      } as any);

      // Per Voice Live protocol, addConversationItem only stages the turn —
      // response.create is always required to ask the model to respond.
      requestSentAtRef.current = performance.now();
      requestSentWallClockRef.current = Date.now();
      firstResponseAtRef.current = null;
      await session.sendEvent({ type: "response.create", response: {modalities: ['text']},} as any);
     
      // await session.sendEvent({
      //   "type": "response.create",
      //   "response": {
      //     "invoke_input": {
      //       "type": "button.click",
      //       "action": "confirm_booking"
      //     }
      //   }
      // });         
    
    } catch (error) {
      requestSentAtRef.current = null;
      requestSentWallClockRef.current = null;
      firstResponseAtRef.current = null;
      addLog(
        "sys",
        `Send failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }, [addLog, messageInput, resourceOverride]);

  const connected = status === "connected";

  return (
    <div className="app">
      <h1>Hub Agent Voice Live</h1>
      <p className="subtitle">
        Voice path: input_audio.transcription | Text path: response.create
      </p>

      <div className="card card-config">
        <label>
          Voice Live endpoint
          <input
            value={voiceLiveEndpoint}
            onChange={(event) => setVoiceLiveEndpoint(event.target.value)}
            disabled={connected}
          />
        </label>
        <label>
          Foundry project endpoint
          <input
            value={projectEndpoint}
            onChange={(event) => setProjectEndpoint(event.target.value)}
            disabled={connected}
          />
        </label>
        <label>
          Resource override
          <input
            value={resourceOverride}
            onChange={(event) => setResourceOverride(event.target.value)}
            disabled={connected}
          />
        </label>
        <label>
          Bearer token
          <textarea
            value={bearerToken}
            onChange={(event) => setBearerToken(event.target.value)}
            disabled={connected}
            rows={3}
          />
        </label>
      </div>

      <div className="card card-controls">
        <div className="row">     
          <button
            onClick={status === "idle" ? connect : disconnect}
            disabled={status === "connecting"}
          >
            {status === "idle"
              ? "Connect"
              : status === "connecting"
                ? "Connecting..."
                : "Disconnect"}
          </button>
          <button onClick={toggleMicrophone} disabled={!connected}>
            {micActive ? "Stop microphone" : "Start microphone"}
          </button>
          <span className={`status-pill status-${status}`}>
            ● {status}
          </span>
        </div>
      </div>

      <div className="card card-message">
        <div className="row">
          <input
            value={messageInput}
            onChange={(event) => setMessageInput(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter" && !event.shiftKey) {
                event.preventDefault();
                void sendMessage();
              }
            }}
            placeholder="Type a message"
            disabled={!connected}
          />
          <button
            onClick={() => void sendMessage()}
            disabled={!connected || !messageInput.trim()}
          >
            Send response.create
          </button>
        </div>
      </div>

      {(connected || userTranscript || agentTranscript || streamedTextEvents.length > 0 || agentMetadata !== null) && (
        <div className="card card-live">
          {userTranscript && (
            <div>
              <strong>You:</strong> {userTranscript}
            </div>
          )}
          <div style={{ marginTop: "0.6rem" }}>
            <div className="metadata-label">Streamed Text Events</div>
            {agentTranscript && (
              <div className="live-inline-text">
                <strong>Live:</strong> {agentTranscript}
              </div>
            )}
            {streamedTextEvents.length === 0 ? (
              <div className="live-empty">No streamed text events yet.</div>
            ) : (
              <pre className="metadata-json">{streamedTextEvents.map((eventText, index) => `${index + 1}. ${eventText}`).join("\n\n")}</pre>
            )}
          </div>
          <div style={{ marginTop: "0.6rem" }}>
            <div className="metadata-label">HubAgent Metadata</div>
            {agentMetadata === null ? (
              <div className="live-empty">Waiting for metadata...</div>
            ) : (
              <pre className="metadata-json">{JSON.stringify(agentMetadata, null, 2)}</pre>
            )}
          </div>
          <div style={{ marginTop: "0.6rem" }}>
            <div className="metadata-label">Latest Timing</div>
            {latestTiming === null ? (
              <div className="live-empty">No completed request yet.</div>
            ) : (
              <pre className="metadata-json">{[
                `requested_at: ${latestTiming.requestedAt}`,
                `first_response: ${latestTiming.firstResponseAt ?? "n/a"}`,
                `completed: ${latestTiming.completedAt ?? "n/a"}`,
              ].join("\n")}</pre>
            )}
          </div>
        </div>
      )}

      {/* ── Event Log ── */}
      <div className="card card-log">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.4rem" }}>
          <strong>Event Log</strong>
          <button className="btn-ghost" style={{ fontSize: "0.8rem", padding: "0.2rem 0.5rem" }} onClick={() => setLogs([])}>
            Clear
          </button>
        </div>
        <pre ref={logRef} className="log">
          {logs.length === 0
            ? <span style={{ color: "#6b7280" }}>No events yet.</span>
            : logs.map((e, i) => (
                <div key={i} style={{ color: e.dir === "in" ? "#6ee7b7" : e.dir === "out" ? "#93c5fd" : "#d1d5db" }}>
                  [{e.ts}] {e.dir.toUpperCase().padEnd(3)} {e.text}
                </div>
              ))
          }
        </pre>
      </div>
    </div>
  );
}
