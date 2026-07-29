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


class AccountAgentConfig:
    SERVICE_NAME = os.getenv("SERVICE_NAME", "account-agent")
    APP_ENV = os.getenv("APP_ENV", "ENV_LCL")
    HOST = os.getenv("HOST", "0.0.0.0")
    PORT = _as_int(os.getenv("PORT"), default=8090)

    FOUNDRY_PROJECT_ENDPOINT = (
        os.getenv("FOUNDRY_PROJECT_ENDPOINT")
        or os.getenv("AZURE_AI_PROJECT_ENDPOINT", "")
    )
    FOUNDRY_MODEL_DEPLOYMENT = (
        os.getenv("FOUNDRY_MODEL_DEPLOYMENT")
        or os.getenv("AGENTHUB_MODEL_DEPLOYMENT")
        or os.getenv("DEFAULT_MODEL_DEPLOYMENT")
        or os.getenv("AZURE_AI_MODEL_DEPLOYMENT_NAME", "")
    )

    APPLICATIONINSIGHTS_CONNECTION_STRING = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
    APPLICATIONINSIGHTS_USE_AAD_AUTH = _as_bool(os.getenv("APPLICATIONINSIGHTS_USE_AAD_AUTH"), default=False)
    AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED = _as_bool(
        os.getenv("AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED"), default=False
    )
