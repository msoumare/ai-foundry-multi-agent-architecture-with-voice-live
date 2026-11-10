"""Configuration for the card hosted agent runtime."""

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


def _as_float(value: str | None, *, default: float) -> float:
	if value is None:
		return default
	try:
		return float(value)
	except ValueError:
		return default


class CardAgentConfig:
	SERVICE_NAME = os.getenv("SERVICE_NAME", "card-agent")
	APP_ENV = os.getenv("APP_ENV", "local")
	HOST = os.getenv("HOST", "0.0.0.0")
	PORT = _as_int(os.getenv("PORT"), default=8088)

	AZURE_AI_PROJECT_ENDPOINT = os.getenv("AZURE_AI_PROJECT_ENDPOINT", "")
	FOUNDRY_MODEL_DEPLOYMENT = (
		os.getenv("FOUNDRY_MODEL_DEPLOYMENT")
		or os.getenv("AGENTHUB_MODEL_DEPLOYMENT")
		or os.getenv("DEFAULT_MODEL_DEPLOYMENT")
		or os.getenv("AZURE_AI_MODEL_DEPLOYMENT_NAME")
		or "gpt-4.1-mini"
	)

	APPLICATIONINSIGHTS_CONNECTION_STRING = (
		os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
		or os.getenv("APPINSIGHTS_CONNECTION_STRING")
	)
	AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED = _as_bool(
		os.getenv("AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED"), default=False
	)

	DOWNSTREAM_AGENT_TIMEOUT = _as_float(os.getenv("DOWNSTREAM_AGENT_TIMEOUT"), default=30.0)


@dataclass
class AgentConfig:
	"""Registry entry for optional card downstream delegation targets."""

	route_id: str
	agent_name: str
	agent_id: str = ""
	timeout_seconds: float = field(default_factory=lambda: CardAgentConfig.DOWNSTREAM_AGENT_TIMEOUT)
	enabled: bool = True


CARD_DOWNSTREAM_REGISTRY: list[AgentConfig] = [
	AgentConfig(
		route_id="account",
		agent_name=os.getenv("ACCOUNT_AGENT_NAME", "account-agent"),
		agent_id=os.getenv("ACCOUNT_AGENT_ID", ""),
	),
	AgentConfig(
		route_id="payment",
		agent_name=os.getenv("PAYMENT_AGENT_NAME", "payment-agent"),
		agent_id=os.getenv("PAYMENT_AGENT_ID", ""),
	),
]

