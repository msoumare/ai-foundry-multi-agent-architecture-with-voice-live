"""Foundry-hosted HTTP invocations entry point for the Voice Live hub agent."""

from __future__ import annotations

import json
import logging
from collections.abc import AsyncIterator
from pathlib import Path

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from azure.ai.agentserver.invocations import InvocationAgentServerHost
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv
from starlette.requests import Request
from starlette.responses import JSONResponse, Response, StreamingResponse

from config import HubAgentConfig
from hub_agent import HubAgent
from services.telemetry import telemetry

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env", override=False)
logger = logging.getLogger("hub_agent.main")

app = InvocationAgentServerHost()


def _read_instructions() -> str:
    return (ROOT / "prompts" / "hub_prompt.txt").read_text(encoding="utf-8").strip()


def _build_hub_agent() -> HubAgent:
    if not HubAgentConfig.SERVICE_PROJECT_ENDPOINT:
        raise RuntimeError("SERVICE_PROJECT_ENDPOINT is required.")

    client = FoundryChatClient(
        project_endpoint=HubAgentConfig.SERVICE_PROJECT_ENDPOINT,
        model=HubAgentConfig.SERVICE_MODEL_DEPLOYMENT,
        credential=DefaultAzureCredential(),
    )
    agent = Agent(
        client=client,
        name="hub-agent",
        instructions=_read_instructions(),
        default_options={"store": False},
    )
    return HubAgent(agent)


# Built once at startup
_hub_agent = _build_hub_agent()


def _rejected(message: str) -> JSONResponse:
    return JSONResponse({"type": "hubagent.event.rejected", "message": message}, status_code=400)


@app.invoke_handler
async def handle_invocation(request: Request) -> Response:
    try:
        event = await request.json()
    except (json.JSONDecodeError, UnicodeDecodeError):
        logger.warning("hub_agent.handle_invocation.invalid_json")
        return _rejected("Request must be valid JSON.")
    if not isinstance(event, dict):
        logger.warning("hub_agent.handle_invocation.expected_object")
        return _rejected("Request must be a JSON object.")

    session_id = request.state.session_id

    async def stream_events() -> AsyncIterator[str]:
        async for stream_event in _hub_agent.process_event(event, session_id):
            yield f"data: {json.dumps(stream_event, ensure_ascii=False)}\n\n"

    return StreamingResponse(
        stream_events(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


if __name__ == "__main__":
    telemetry.initialize()
    if telemetry.is_enabled():
        print(f"[telemetry] enabled for service '{HubAgentConfig.SERVICE_NAME}'")
    else:
        reason = telemetry.last_error or "missing APPLICATIONINSIGHTS_CONNECTION_STRING (Foundry reserved keyword)"
        print(f"[telemetry] disabled: {reason}")

    logger.info("hub_agent.starting")
    app.run(host=HubAgentConfig.SERVICE_HOST, port=HubAgentConfig.SERVICE_PORT)
