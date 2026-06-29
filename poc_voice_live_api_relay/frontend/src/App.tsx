import { useRef, useState } from 'react';

type HubAgentResponse = {
  trace_id: string;
  source: string;
  result: string;
  processed_text: string;
  metadata: Record<string, unknown>;
};

const defaultVoiceLiveWs =
  import.meta.env.VITE_VOICE_LIVE_ENDPOINT ??
  'wss://ai-rtag-agenthubspoke-dev-sdc.services.ai.azure.com/voice-live/realtime';
const defaultHubAgentWs =
  import.meta.env.VITE_HUB_AGENT_WS_URL ?? 'ws://localhost:8000/ws/hub-agent';

type TransportMode = 'text' | 'speech';

type SpeechRecognitionAlternativeLike = {
  transcript: string;
};

type SpeechRecognitionResultLike = {
  isFinal: boolean;
  0: SpeechRecognitionAlternativeLike;
};

type SpeechRecognitionEventLike = {
  resultIndex: number;
  results: ArrayLike<SpeechRecognitionResultLike>;
};

type SpeechRecognitionLike = {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  onresult: ((event: SpeechRecognitionEventLike) => void) | null;
  onerror: ((event: { error?: string }) => void) | null;
  onend: (() => void) | null;
  start: () => void;
  stop: () => void;
};

type SpeechRecognitionConstructor = new () => SpeechRecognitionLike;

export default function App() {
  const [voiceLiveWsUrl, setVoiceLiveWsUrl] = useState(defaultVoiceLiveWs);
  const [hubAgentWsUrl, setHubAgentWsUrl] = useState(defaultHubAgentWs);
  const [transportMode, setTransportMode] = useState<TransportMode>('text');
  const [query, setQuery] = useState('check order status 12345');
  const [speechTranscript, setSpeechTranscript] = useState('');
  const [speechListening, setSpeechListening] = useState(false);
  const [contextJson, setContextJson] = useState('{"channel":"web","session_id":"demo-001"}');
  const [hubAgentResponse, setHubAgentResponse] = useState<HubAgentResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  const voiceLiveRef = useRef<WebSocket | null>(null);
  const hubAgentRef = useRef<WebSocket | null>(null);
  const speechRef = useRef<SpeechRecognitionLike | null>(null);
  const [voiceLiveState, setVoiceLiveState] = useState<'closed' | 'open'>('closed');
  const [hubAgentState, setHubAgentState] = useState<'closed' | 'open'>('closed');
  const [wsMessages, setWsMessages] = useState<string[]>([]);

  const speechCtor =
    (window as unknown as { SpeechRecognition?: SpeechRecognitionConstructor; webkitSpeechRecognition?: SpeechRecognitionConstructor })
      .SpeechRecognition ||
    (window as unknown as { webkitSpeechRecognition?: SpeechRecognitionConstructor }).webkitSpeechRecognition;
  const speechSupported = Boolean(speechCtor);

  const parseContext = (): Record<string, unknown> => {
    try {
      const parsed = JSON.parse(contextJson);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
      throw new Error('Context must be a JSON object');
    } catch (e) {
      throw new Error(`Invalid context JSON: ${(e as Error).message}`);
    }
  };

  const connectVoiceLive = () => {
    if (voiceLiveRef.current) {
      voiceLiveRef.current.close();
    }

    const ws = new WebSocket(voiceLiveWsUrl);

    ws.onopen = () => {
      setVoiceLiveState('open');
      setWsMessages((prev) => [...prev, '[voice-live connected]']);
    };

    ws.onmessage = (event) => {
      setWsMessages((prev) => [...prev, `[voice-live recv] ${String(event.data)}`]);
    };

    ws.onerror = () => {
      setWsMessages((prev) => [...prev, '[voice-live error] websocket error']);
    };

    ws.onclose = () => {
      setVoiceLiveState('closed');
      setWsMessages((prev) => [...prev, '[voice-live closed]']);
      voiceLiveRef.current = null;
    };

    voiceLiveRef.current = ws;
  };

  const connectHubAgent = () => {
    if (hubAgentRef.current) {
      hubAgentRef.current.close();
    }

    const ws = new WebSocket(hubAgentWsUrl);

    ws.onopen = () => {
      setHubAgentState('open');
      setWsMessages((prev) => [...prev, '[hub-agent connected]']);
    };

    ws.onmessage = (event) => {
      try {
        const parsed = JSON.parse(String(event.data)) as HubAgentResponse;
        if (parsed && parsed.trace_id) {
          setHubAgentResponse(parsed);
        }
      } catch {
        // Keep raw log even when payload is non-JSON.
      }
      setWsMessages((prev) => [...prev, `[hub-agent recv] ${String(event.data)}`]);
    };

    ws.onerror = () => {
      setWsMessages((prev) => [...prev, '[hub-agent error] websocket error']);
    };

    ws.onclose = () => {
      setHubAgentState('closed');
      setWsMessages((prev) => [...prev, '[hub-agent closed]']);
      hubAgentRef.current = null;
    };

    hubAgentRef.current = ws;
  };

  const connectSockets = () => {
    connectVoiceLive();
    connectHubAgent();
  };

  const disconnectSockets = () => {
    voiceLiveRef.current?.close();
    voiceLiveRef.current = null;
    setVoiceLiveState('closed');

    hubAgentRef.current?.close();
    hubAgentRef.current = null;
    setHubAgentState('closed');
  };

  const sendToHubAgent = (text: string, mode: TransportMode) => {
    if (!voiceLiveRef.current || voiceLiveState !== 'open') {
      setWsMessages((prev) => [...prev, '[warn] voice-live websocket is not connected']);
      return;
    }

    try {
      const context = parseContext();
      const payload = {
        type: mode === 'speech' ? 'speech_message' : 'user_message',
        text,
        context,
      };

      const serialized = JSON.stringify(payload);
      voiceLiveRef.current.send(serialized);
      setWsMessages((prev) => [...prev, `[voice-live sent] ${serialized}`]);

      if (hubAgentRef.current && hubAgentState === 'open') {
        hubAgentRef.current.send(serialized);
        setWsMessages((prev) => [...prev, `[hub-agent mirror sent] ${serialized}`]);
      } else {
        setWsMessages((prev) => [...prev, '[warn] hub-agent websocket not connected for mirror']);
      }

      setError(null);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  const sendTextMode = () => {
    const outbound = query.trim();
    if (!outbound) {
      setError('Text message cannot be empty');
      return;
    }

    sendToHubAgent(outbound, 'text');
  };

  const startSpeech = () => {
    if (!speechSupported || !speechCtor) {
      setError('Speech recognition is not supported in this browser.');
      return;
    }

    if (speechRef.current) {
      speechRef.current.stop();
      speechRef.current = null;
    }

    const recognition = new speechCtor();
    recognition.lang = 'en-US';
    recognition.continuous = true;
    recognition.interimResults = true;

    recognition.onresult = (event) => {
      let finalText = '';
      let interimText = '';

      for (let i = event.resultIndex; i < event.results.length; i += 1) {
        const item = event.results[i];
        const text = item[0]?.transcript ?? '';
        if (item.isFinal) {
          finalText += text;
        } else {
          interimText += text;
        }
      }

      const merged = `${finalText} ${interimText}`.trim();
      if (merged) {
        setSpeechTranscript(merged);
      }
    };

    recognition.onerror = (event) => {
      setError(`Speech recognition error: ${event.error ?? 'unknown'}`);
    };

    recognition.onend = () => {
      setSpeechListening(false);
      speechRef.current = null;
    };

    recognition.start();
    speechRef.current = recognition;
    setSpeechListening(true);
    setError(null);
  };

  const stopSpeech = () => {
    speechRef.current?.stop();
    speechRef.current = null;
    setSpeechListening(false);
  };

  const sendSpeechMode = () => {
    const outbound = speechTranscript.trim();
    if (!outbound) {
      setError('Speech transcript is empty. Speak first, then send.');
      return;
    }

    sendToHubAgent(outbound, 'speech');
  };

  return (
    <main className="page">
      <h1>Frontend to Voice Live + Hub-Agent Mirror</h1>

      <section className="card">
        <h2>1) WebSocket Connectivity</h2>
        <label>
          Voice Live WS URL
          <input value={voiceLiveWsUrl} onChange={(e) => setVoiceLiveWsUrl(e.target.value)} />
        </label>
        <label>
          Hub-Agent WS URL
          <input value={hubAgentWsUrl} onChange={(e) => setHubAgentWsUrl(e.target.value)} />
        </label>
        <div className="row">
          <button onClick={connectSockets} disabled={voiceLiveState === 'open' && hubAgentState === 'open'}>
            Connect Both
          </button>
          <button onClick={disconnectSockets} disabled={voiceLiveState !== 'open' && hubAgentState !== 'open'}>
            Disconnect Both
          </button>
          <span>Voice Live: {voiceLiveState}</span>
          <span>Hub-Agent Mirror: {hubAgentState}</span>
        </div>
        <pre className="log">{wsMessages.join('\n')}</pre>
      </section>

      <section className="card">
        <h2>2) Transport Mode</h2>
        <div className="row">
          <label>
            <input
              type="radio"
              name="transport-mode"
              checked={transportMode === 'text'}
              onChange={() => setTransportMode('text')}
            />
            Text
          </label>
          <label>
            <input
              type="radio"
              name="transport-mode"
              checked={transportMode === 'speech'}
              onChange={() => setTransportMode('speech')}
            />
            Speech
          </label>
        </div>

        {transportMode === 'text' && (
          <>
            <label>
              Text message
              <input value={query} onChange={(e) => setQuery(e.target.value)} />
            </label>
            <button onClick={sendTextMode} disabled={voiceLiveState !== 'open'}>
              Send Text Over WS
            </button>
          </>
        )}

        {transportMode === 'speech' && (
          <>
            <div className="row">
              <button onClick={startSpeech} disabled={!speechSupported || speechListening}>
                Start Mic
              </button>
              <button onClick={stopSpeech} disabled={!speechListening}>
                Stop Mic
              </button>
              <button onClick={sendSpeechMode} disabled={voiceLiveState !== 'open'}>
                Send Speech Over WS
              </button>
              <span>{speechSupported ? (speechListening ? 'Listening...' : 'Mic idle') : 'Speech unsupported'}</span>
            </div>
            <label>
              Speech transcript
              <textarea value={speechTranscript} onChange={(e) => setSpeechTranscript(e.target.value)} rows={4} />
            </label>
          </>
        )}

        <label>
          Context JSON
          <textarea value={contextJson} onChange={(e) => setContextJson(e.target.value)} rows={4} />
        </label>
        <p>Primary route: {voiceLiveWsUrl}</p>
        <p>Mirror route: {hubAgentWsUrl}</p>

        {error && <p className="error">{error}</p>}
        {hubAgentResponse && <pre className="log">{JSON.stringify(hubAgentResponse, null, 2)}</pre>}
      </section>
    </main>
  );
}
