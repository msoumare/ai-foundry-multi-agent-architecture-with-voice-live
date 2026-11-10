"""Configuration for the hub agent runtime."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv


load_dotenv(".env")


class HubAgentConfig:
    SERVICE_NAME = os.getenv("SERVICE_NAME")
    SERVICE_HOST = os.getenv("SERVICE_HOST")
    SERVICE_PORT = int(os.getenv("PORT", "8088"))
    SERVICE_PROJECT_ENDPOINT = os.getenv("SERVICE_PROJECT_ENDPOINT")
    SERVICE_MODEL_DEPLOYMENT = os.getenv("SERVICE_MODEL_DEPLOYMENT")
    SERVICE_TELEMETRY = os.getenv("SERVICE_TELEMETRY")
    FORWARD_MODE = os.getenv("FORWARD_MODE") 
    AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED = (
        os.getenv("AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED") or ""
    ).strip().lower() in {"1", "true", "yes", "on"}

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

    agent_name: str
    local_url: str = ""
    timeout_seconds: float = field(default_factory=lambda: HubAgentConfig.DOMAIN_AGENT_TIMEOUT)
    enabled: bool = True


# ---------------------------------------------------------------------------
# Domain-agent registry
# One entry per spoke agent.  Add / remove entries here as the system grows.
# ---------------------------------------------------------------------------
DOMAIN_AGENT_REGISTRY: list[AgentConfig] = [
    AgentConfig(
        agent_name=os.getenv("CARD_AGENT_NAME", "card-agent"),
        local_url=os.getenv("CARD_AGENT_URL", "http://localhost:8081/responses"),
    ),
    AgentConfig(
        agent_name=os.getenv("ACCOUNT_AGENT_NAME", "account-agent"),
        local_url=os.getenv("ACCOUNT_AGENT_URL", "http://localhost:8080/responses"),
    ),
    AgentConfig(
        agent_name=os.getenv("PAYMENT_AGENT_NAME", "payment-agent"),
        local_url=os.getenv("PAYMENT_AGENT_URL", "http://localhost:8082/responses"),
    )
]
