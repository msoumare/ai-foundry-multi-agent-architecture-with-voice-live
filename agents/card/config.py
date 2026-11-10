"""Configuration for the card agent runtime."""

from __future__ import annotations

import os

from dotenv import load_dotenv


load_dotenv(".env")


def _as_float(value: str | None, *, default: float) -> float:
	if value is None:
		return default
	try:
		return float(value)
	except ValueError:
		return default


class CardAgentConfig:
	SERVICE_NAME = os.getenv("SERVICE_NAME")
	SERVICE_HOST = os.getenv("SERVICE_HOST")
	# Foundry Hosted injects PORT and probes readiness on it; prefer it.
	SERVICE_PORT = int(os.getenv("PORT") or os.getenv("SERVICE_PORT") or 8088)
	SERVICE_PROJECT_ENDPOINT = os.getenv("SERVICE_PROJECT_ENDPOINT")
	SERVICE_MODEL_DEPLOYMENT = os.getenv("SERVICE_MODEL_DEPLOYMENT")
	AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED = os.getenv('AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED')
	A2A_AGENT_TIMEOUT = _as_float(os.getenv("A2A_AGENT_TIMEOUT"), default=30.0)


