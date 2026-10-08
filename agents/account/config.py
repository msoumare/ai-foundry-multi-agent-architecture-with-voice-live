"""Configuration for the account hosted agent runtime."""

from __future__ import annotations

import os

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


def _forward_mode() -> str:
    value = (os.getenv("FORWARD_MODE", "foundry") or "foundry").strip().lower()
    if value not in {"foundry", "local"}:
        raise ValueError("FORWARD_MODE must be one of: foundry, local")
    return value


class AccountAgentConfig:
    SERVICE_NAME = os.getenv("SERVICE_NAME", "account-agent")
    SERVICE_HOST = os.getenv("SERVICE_HOST", "0.0.0.0")
    SERVICE_PORT = _as_int(os.getenv("SERVICE_PORT"), default=8090)
    FORWARD_MODE = _forward_mode()

    SERVICE_PROJECT_ENDPOINT = (
        os.getenv("SERVICE_PROJECT_ENDPOINT")
        or os.getenv("AZURE_AI_PROJECT_ENDPOINT", "")
    )
    SERVICE_MODEL_DEPLOYMENT = (
        os.getenv("SERVICE_MODEL_DEPLOYMENT")
        or os.getenv("AGENTHUB_MODEL_DEPLOYMENT")
        or os.getenv("DEFAULT_MODEL_DEPLOYMENT")
        or os.getenv("AZURE_AI_MODEL_DEPLOYMENT_NAME", "")
    )

    APPLICATIONINSIGHTS_CONNECTION_STRING = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
    APPLICATIONINSIGHTS_USE_AAD_AUTH = _as_bool(os.getenv("APPLICATIONINSIGHTS_USE_AAD_AUTH"), default=False)
    AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED = _as_bool(
        os.getenv("AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED"), default=False
    )
