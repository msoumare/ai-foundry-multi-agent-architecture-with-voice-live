from __future__ import annotations

from pathlib import Path

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

from config import HubAgentConfig
from hub_agent import HubAgent
from services.telemetry import telemetry

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env", override=False)


def _read_instructions() -> str:
    return (ROOT / "prompts" / "hub_prompt.txt").read_text(encoding="utf-8").strip()


def main() -> None:
    telemetry.initialize()
    if telemetry.is_enabled():
        print(f"[telemetry] enabled for service '{HubAgentConfig.SERVICE_NAME}'")
    else:
        reason = telemetry.last_error or "missing APPLICATIONINSIGHTS_CONNECTION_STRING (Foundry reserved keyword)"
        print(f"[telemetry] disabled: {reason}")

    project_endpoint = HubAgentConfig.SERVICE_PROJECT_ENDPOINT
    model = HubAgentConfig.SERVICE_MODEL_DEPLOYMENT

    if not project_endpoint:
        raise RuntimeError("SERVICE_PROJECT_ENDPOINT is required.")

    credential = DefaultAzureCredential()

    client = FoundryChatClient(
        project_endpoint=project_endpoint,
        model=model,
        credential=credential,
    )

    agent = Agent(
        client=client,
        name="hub-agent",
        instructions=_read_instructions(),
        default_options={"store": False},
    )

    hub_agent = HubAgent(agent)

    server = ResponsesHostServer(hub_agent)    
    server.run(host=HubAgentConfig.SERVICE_HOST, port=HubAgentConfig.SERVICE_PORT)


if __name__ == "__main__":
    main()
