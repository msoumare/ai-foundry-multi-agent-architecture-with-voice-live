from __future__ import annotations

from pathlib import Path

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

from config import PaymentAgentConfig
from structured_spoke_agent import StructuredSpokeAgent

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env", override=False)


def _read_instructions() -> str:
    return (ROOT / "prompts" / "payment_prompt.txt").read_text(encoding="utf-8").strip()


def main() -> None:
    project_endpoint = PaymentAgentConfig.AZURE_AI_PROJECT_ENDPOINT
    model = PaymentAgentConfig.FOUNDRY_MODEL_DEPLOYMENT
    agent_name = PaymentAgentConfig.SERVICE_NAME

    if not project_endpoint:
        raise RuntimeError("AZURE_AI_PROJECT_ENDPOINT is required.")

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
    app_agent = StructuredSpokeAgent(domain_agent=domain_agent, agent_name=agent_name)

    server = ResponsesHostServer(app_agent)
    server.run(host=PaymentAgentConfig.HOST, port=PaymentAgentConfig.PORT)


if __name__ == "__main__":
    main()
