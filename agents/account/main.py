from __future__ import annotations

import logging
from pathlib import Path

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import AzureCliCredential, ChainedTokenCredential, DefaultAzureCredential
from dotenv import load_dotenv

from account_agent import AccountAgent
from config import AccountAgentConfig
from services.telemetry import telemetry

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env", override=False)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)


def _read_instructions() -> str:
    prompt_path = ROOT / "prompts" / "account_prompt.txt"
    if prompt_path.exists():
        return prompt_path.read_text(encoding="utf-8").strip()
    return (
        "You are the Account domain agent for a retail bank. "
        "Help customers with: profile updates, address changes, contact details, "
        "account status, account opening/closing, statements, limits, and general account enquiries."
    )


def main() -> None:
    telemetry.initialize()
    if telemetry.is_enabled():
        print(f"[telemetry] enabled for service '{AccountAgentConfig.SERVICE_NAME}'")
    else:
        reason = telemetry.last_error or "missing APPLICATIONINSIGHTS_CONNECTION_STRING"
        print(f"[telemetry] disabled: {reason}")

    project_endpoint = AccountAgentConfig.SERVICE_PROJECT_ENDPOINT
    model = AccountAgentConfig.SERVICE_MODEL_DEPLOYMENT

    if not project_endpoint:
        raise RuntimeError("SERVICE_PROJECT_ENDPOINT is required.")

    credential = ChainedTokenCredential(
        AzureCliCredential(),
        DefaultAzureCredential(exclude_cli_credential=True),
    )

    client = FoundryChatClient(
        project_endpoint=project_endpoint,
        model=model,
        credential=credential,
    )

    domain_agent = Agent(
        client=client,
        name=AccountAgentConfig.SERVICE_NAME,
        instructions=_read_instructions(),
        default_options={"store": False},
    )

    app_agent = AccountAgent(account_agent=domain_agent)
    server = ResponsesHostServer(app_agent)
    print(f"[account-agent] Starting responses-hosted agent on port {AccountAgentConfig.SERVICE_PORT}")
    server.run(host=AccountAgentConfig.SERVICE_HOST, port=AccountAgentConfig.SERVICE_PORT)


if __name__ == "__main__":
    main()

