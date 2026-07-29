from __future__ import annotations

import asyncio
import os
from pathlib import Path

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from azure.ai.agentserver.agentframework import from_agent_framework
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env", override=False)


def _read_instructions() -> str:
    prompt_path = ROOT / "prompts" / "payment_prompt.txt"
    if prompt_path.exists():
        return prompt_path.read_text(encoding="utf-8").strip()
    return "You are the Payment hosted agent. Help users with transfers, payment status, disputes, and payment troubleshooting."


async def main() -> None:
    project_endpoint = (
        os.getenv("FOUNDRY_PROJECT_ENDPOINT")
        or os.getenv("AZURE_AI_PROJECT_ENDPOINT", "")
    ).strip().strip('"')
    model = (
        os.getenv("FOUNDRY_MODEL_DEPLOYMENT")
        or os.getenv("DEFAULT_MODEL_DEPLOYMENT")
        or os.getenv("FOUNDRY_MODEL_DEPLOYMENT_NAME")
        or os.getenv("AGENTHUB_MODEL_DEPLOYMENT")
        or "gpt-4.1-mini"
    ).strip().strip('"')
    agent_name = os.getenv("SERVICE_NAME", "payment-agent")

    if not project_endpoint:
        raise RuntimeError("FOUNDRY_PROJECT_ENDPOINT is required.")

    credential = DefaultAzureCredential()
    client = FoundryChatClient(
        project_endpoint=project_endpoint,
        model=model,
        credential=credential,
    )

    async with Agent(client=client, name=agent_name, instructions=_read_instructions()) as agent:
        await from_agent_framework(agent).run_async()

    if hasattr(credential, "close"):
        credential.close()


if __name__ == "__main__":
    asyncio.run(main())
