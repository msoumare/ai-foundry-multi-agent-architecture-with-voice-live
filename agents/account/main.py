from __future__ import annotations

from pathlib import Path

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

from config import AccountAgentConfig

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env", override=False)


def _read_instructions() -> str:
    prompt_path = ROOT / "prompts" / "account_prompt.txt"
    if prompt_path.exists():
        return prompt_path.read_text(encoding="utf-8").strip()
    return "You are the Account hosted agent. Help users with profile updates, account access, and account status checks."


def main() -> None:
    project_endpoint = AccountAgentConfig.SERVICE_PROJECT_ENDPOINT
    model = AccountAgentConfig.SERVICE_MODEL_DEPLOYMENT
    agent_name = AccountAgentConfig.SERVICE_NAME

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
    server.run(host=AccountAgentConfig.SERVICE_HOST, port=AccountAgentConfig.SERVICE_PORT)


if __name__ == "__main__":
    main()
