from __future__ import annotations

from pathlib import Path

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

from config import PaymentAgentConfig

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env", override=False)


def _read_instructions() -> str:
    prompt_path = ROOT / "prompts" / "payment_prompt.txt"
    if prompt_path.exists():
        return prompt_path.read_text(encoding="utf-8").strip()
    return "You are the Payment hosted agent. Help users with transfers, payment status, disputes, and payment troubleshooting."


def main() -> None:
    project_endpoint = PaymentAgentConfig.SERVICE_PROJECT_ENDPOINT
    model = PaymentAgentConfig.SERVICE_MODEL_DEPLOYMENT
    agent_name = PaymentAgentConfig.SERVICE_NAME

    if not project_endpoint:
        raise RuntimeError("SERVICE_PROJECT_ENDPOINT is required.")

    client = FoundryChatClient(
        project_endpoint=project_endpoint,
        model=model,
        credential=DefaultAzureCredential(),
    )

    agent = Agent(
        client=client,
        name=agent_name,
        instructions=_read_instructions(),
        default_options={"store": False},
    )

    server = ResponsesHostServer(agent)
    server.run(host=PaymentAgentConfig.SERVICE_HOST, port=PaymentAgentConfig.SERVICE_PORT)


if __name__ == "__main__":
    main()
