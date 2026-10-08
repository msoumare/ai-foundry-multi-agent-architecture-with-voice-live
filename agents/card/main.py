from __future__ import annotations

from pathlib import Path

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

from card_agent import CardAgent
from config import CardAgentConfig
from services.telemetry import telemetry

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env", override=False)


def _read_instructions() -> str:
    prompt_path = ROOT / "prompts" / "card_prompt.txt"
    if prompt_path.exists():
        return prompt_path.read_text(encoding="utf-8").strip()
    return "You are the Card hosted agent. Help users with card activation, card limits, PIN, and card transaction issues."


def main() -> None:
    telemetry.initialize()
    if telemetry.is_enabled():
        print(f"[telemetry] enabled for service '{CardAgentConfig.SERVICE_NAME}'")
    else:
        reason = telemetry.last_error or "missing APPLICATIONINSIGHTS_CONNECTION_STRING (Foundry reserved keyword)"
        print(f"[telemetry] disabled: {reason}")

    project_endpoint = CardAgentConfig.SERVICE_PROJECT_ENDPOINT
    model = CardAgentConfig.SERVICE_MODEL_DEPLOYMENT
    agent_name = CardAgentConfig.SERVICE_NAME

    if not project_endpoint:
        raise RuntimeError("SERVICE_PROJECT_ENDPOINT is required.")

    client = FoundryChatClient(
        project_endpoint=project_endpoint,
        model=model,
        credential=DefaultAzureCredential(),
    )

    domain_agent = Agent(
        client=client,
        name=agent_name,
        instructions=_read_instructions(),
        default_options={"store": False},
    )

    app_agent = CardAgent(
        card_agent=domain_agent,
    )

    server = ResponsesHostServer(app_agent)
    server.run(host=CardAgentConfig.SERVICE_HOST, port=CardAgentConfig.SERVICE_PORT)


if __name__ == "__main__":
    main()
