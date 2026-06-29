import os
import json
from datetime import datetime, timezone
from typing import Any, Dict, TypedDict
from uuid import uuid4

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()


class HubAgentRequest(TypedDict):
    query: str
    context: Dict[str, Any]


class HubAgentResponse(TypedDict):
    trace_id: str
    source: str
    result: str
    processed_text: str
    metadata: Dict[str, Any]


app = FastAPI(title="Voice Live Hub-Agent PoC", version="0.2.0")

frontend_origin = os.getenv("FRONTEND_ORIGIN", "http://localhost:5173")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[frontend_origin],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}


def process_query(query: str) -> str:
    normalized = " ".join(query.strip().split())
    return normalized.upper()


def parse_voice_live_event(event: Dict[str, Any]) -> HubAgentRequest:
    """
    Minimal Voice Live event parser with a couple of common payload shapes.
    Supported query sources:
      - event.query
      - event.text
      - event.message.text
      - event.input.text
    """
    query: Any = event.get("query") or event.get("text")

    if not query:
        message_obj = event.get("message")
        if isinstance(message_obj, dict):
            query = message_obj.get("text")

    if not query:
        input_obj = event.get("input")
        if isinstance(input_obj, dict):
            query = input_obj.get("text")

    if not query or not isinstance(query, str) or not query.strip():
        raise HTTPException(
            status_code=400,
            detail="Unable to parse Voice Live payload: expected non-empty query/text/message.text/input.text",
        )

    context: Dict[str, Any] = {}
    raw_context = event.get("context")
    if isinstance(raw_context, dict):
        context.update(raw_context)

    for key in ["type", "session_id", "conversation_id", "message_id", "timestamp"]:
        if key in event:
            context[f"voice_live_{key}"] = event[key]

    return {
        "query": query,
        "context": context,
    }


def build_hub_agent_response(request: HubAgentRequest) -> HubAgentResponse:
    trace_id = str(uuid4())
    processed_text = process_query(request["query"])
    timestamp = datetime.now(timezone.utc).isoformat()
    voice_live_endpoint = os.getenv(
        "VOICE_LIVE_ENDPOINT",
        "wss://ai-rtag-agenthubspoke-dev-sdc.services.ai.azure.com/voice-live/realtime",
    )
    voice_live_api_version = os.getenv("VOICE_LIVE_API_VERSION", "2025-10-01")
    token_timeout_seconds = int(os.getenv("TOKEN_TIMEOUT_SECONDS", "60"))

    return {
        "trace_id": trace_id,
        "source": "hub-agent",
        "result": "Hub-agent received and processed Voice Live request.",
        "processed_text": processed_text,
        "metadata": {
            "processed_at_utc": timestamp,
            "context_keys": sorted(request["context"].keys()),
            "voice_live_endpoint": voice_live_endpoint,
            "voice_live_api_version": voice_live_api_version,
            "token_timeout_seconds": token_timeout_seconds,
        },
    }


@app.websocket("/ws/hub-agent")
async def hub_agent_ws(websocket: WebSocket) -> None:
    await websocket.accept()

    try:
        while True:
            raw_message = await websocket.receive_text()

            try:
                payload = json.loads(raw_message)
            except json.JSONDecodeError:
                payload = {"text": raw_message}

            if not isinstance(payload, dict):
                await websocket.send_json({"error": "Expected JSON object or plain text message"})
                continue

            request = parse_voice_live_event(payload)
            response = build_hub_agent_response(request)
            await websocket.send_json(response)
    except WebSocketDisconnect:
        return
