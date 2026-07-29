"""Configuration for the hub agent runtime."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv


load_dotenv(".env")


def _as_bool(value: str | None, *, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _as_int(value: str | None, *, default: int) -> int:
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def _env_non_empty(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name)
        if value is not None:
            value = value.strip()
            if value:
                return value
    return default


class HubAgentConfig:
    SERVICE_NAME = os.getenv("SERVICE_NAME", "hub-agent")
    APP_ENV = os.getenv("APP_ENV", "local")
    HOST = os.getenv("HOST", "0.0.0.0")
    PORT = _as_int(os.getenv("PORT"), default=8089)
    FORWARD_MODE = (os.getenv("FORWARD_MODE", "foundry") or "foundry").strip().lower()

    # Support both local (.env) and azd-provided cloud names.
    FOUNDRY_PROJECT_ENDPOINT = (
        os.getenv("FOUNDRY_PROJECT_ENDPOINT")
        or os.getenv("AZURE_AI_PROJECT_ENDPOINT")
        or ""
    )
    FOUNDRY_MODEL_DEPLOYMENT = (
        os.getenv("FOUNDRY_MODEL_DEPLOYMENT")
        or os.getenv("AGENTHUB_MODEL_DEPLOYMENT")
        or os.getenv("DEFAULT_MODEL_DEPLOYMENT")
        or "gpt-4.1-mini"
    )

    APPLICATIONINSIGHTS_CONNECTION_STRING = (
        os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
        or os.getenv("APPINSIGHTS_CONNECTION_STRING")
    )
    AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED = _as_bool(
        os.getenv("AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED"), default=False
    )

    # Timeout applied per downstream domain agent invocation (seconds)
    DOMAIN_AGENT_TIMEOUT = float(os.getenv("DOMAIN_AGENT_TIMEOUT", "30"))


class HubAgentResponseMessages:
    """Standard user-facing response messages for the hub agent."""

    EMPTY_MESSAGE = "Please send a message."
    INVALID_REQUEST = "Request must be valid JSON for QueryRequest or plain text query."
    MISSING_SESSION_ID = "session_id is required in the request."
    PROCESSING_ERROR = "I could not route or process the request right now. Please try again."


@dataclass
class AgentConfig:
    """Registry entry for a downstream domain agent."""

    route_id: str
    agent_name: str
    agent_id: str = ""
    local_url: str = ""
    timeout_seconds: float = field(default_factory=lambda: HubAgentConfig.DOMAIN_AGENT_TIMEOUT)
    enabled: bool = True


# ---------------------------------------------------------------------------
# Domain-agent registry
# One entry per spoke agent.  Add / remove entries here as the system grows.
# ---------------------------------------------------------------------------
DOMAIN_AGENT_REGISTRY: list[AgentConfig] = [
    AgentConfig(
        route_id="CardAgent",
        agent_name=os.getenv("CARD_AGENT_NAME", "card-agent"),
        # In new Foundry, agent identity is name/version based. Keep legacy GUID override support.
        agent_id=_env_non_empty("CARD_AGENT_ID", "CARD_AGENT_NAME", default="card-agent"),
        local_url=os.getenv("CARD_AGENT_URL", "http://localhost:8088/responses"),
    ),
    AgentConfig(
        route_id="AccountAgent",
        agent_name=os.getenv("ACCOUNT_AGENT_NAME", "account-agent"),
        agent_id=_env_non_empty("ACCOUNT_AGENT_ID", "ACCOUNT_AGENT_NAME", default="account-agent"),
        local_url=os.getenv("ACCOUNT_AGENT_URL", ""),
    ),
    AgentConfig(
        route_id="PaymentAgent",
        agent_name=os.getenv("PAYMENT_AGENT_NAME", "payment-agent"),
        agent_id=_env_non_empty("PAYMENT_AGENT_ID", "PAYMENT_AGENT_NAME", default="payment-agent"),
        local_url=os.getenv("PAYMENT_AGENT_URL", ""),
    ),
    AgentConfig(
        route_id="RAGAgent",
        agent_name=os.getenv("RAG_AGENT_NAME", "rag-agent"),
        agent_id=_env_non_empty("RAG_AGENT_ID", "RAG_AGENT_NAME", default="rag-agent"),
        local_url=os.getenv("RAG_AGENT_URL", ""),
    ),
    AgentConfig(
        route_id="CognigyAgent",
        agent_name=os.getenv("COGNIGY_AGENT_NAME", "cognigy-agent"),
        agent_id=_env_non_empty("COGNIGY_AGENT_ID", "COGNIGY_AGENT_NAME", default="cognigy-agent"),
        local_url=os.getenv("COGNIGY_AGENT_URL", ""),
    ),
]
