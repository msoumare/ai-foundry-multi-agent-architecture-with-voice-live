"""Configuration for the account agent runtime."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv


load_dotenv(".env")


def _as_bool(value: str | None, *, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}

def _as_float(value: str | None, *, default: float) -> float:
    if value is None:
        return default
    try:
        return float(value)
    except ValueError:
        return default


class AccountAgentConfig:
    SERVICE_NAME = os.getenv("SERVICE_NAME")
    SERVICE_HOST = os.getenv("SERVICE_HOST")
    # Foundry Hosted injects PORT and probes readiness on it; prefer it.
    SERVICE_PORT = int(os.getenv("PORT") or os.getenv("SERVICE_PORT") or 8088)
    SERVICE_PROJECT_ENDPOINT = os.getenv("SERVICE_PROJECT_ENDPOINT")
    SERVICE_MODEL_DEPLOYMENT = os.getenv("SERVICE_MODEL_DEPLOYMENT")
    AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED = os.getenv('AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED') 

    # A2A Agent Timeout
    A2A_AGENT_TIMEOUT = _as_float(os.getenv("A2A_AGENT_TIMEOUT"), default=30.0)


@dataclass
class A2AAgentConfig:
    """Registry entry for an agent accessible via A2A HTTP."""

    route_id: str
    agent_name: str
    url: str
    timeout_seconds: float = field(default_factory=lambda: AccountAgentConfig.A2A_AGENT_TIMEOUT)
    enabled: bool = True


# Account A2A registry: agents this agent can call directly via A2A (see docs/A2A-ARCHITECTURE.md).
ACCOUNT_A2A_REGISTRY: list[A2AAgentConfig] = [
    A2AAgentConfig(
        route_id="hub",
        agent_name=os.getenv("HUB_AGENT_NAME", "hub-agent"),
        url=os.getenv("HUB_AGENT_URL", "http://localhost:8082/responses"),
    ),
]
