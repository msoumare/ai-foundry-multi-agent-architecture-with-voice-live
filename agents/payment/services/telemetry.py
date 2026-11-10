"""Lightweight application logging for the payment agent (routes the telemetry singleton and log_* helpers to stdlib logging; the leading span arg is ignored)."""

from __future__ import annotations

import inspect
import json
import logging
import threading
import time
from collections.abc import Callable
from functools import wraps
from typing import Any

from config import PaymentAgentConfig

logger = logging.getLogger("payment-agent")


class TelemetryManager:
    """Routes application telemetry to the standard library logger."""

    _instance: TelemetryManager | None = None
    _initialized = False
    _lock = threading.Lock()

    def __new__(cls) -> TelemetryManager:
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self) -> None:
        if not getattr(self, "_instance_ready", False):
            self.service_name: str | None = None
            self.content_recording_enabled = False
            self.last_error: str | None = None
            self._instance_ready = True

    def initialize(self) -> None:
        if self._initialized:
            return

        self.service_name = getattr(PaymentAgentConfig, "SERVICE_NAME", "payment-agent")

        self.content_recording_enabled = bool(
            getattr(PaymentAgentConfig, "AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED", False)
        )

        if not logging.getLogger().handlers:
            logging.basicConfig(
                level=logging.INFO,
                format="%(asctime)s %(levelname)s %(name)s %(message)s",
            )

        # agent_framework logs the full system prompt and every chat message at
        # INFO on each run, flooding stderr with prompt dumps. Raise its level so
        # only warnings/errors surface.
        logging.getLogger("agent_framework").setLevel(logging.WARNING)

        self.last_error = None
        self._initialized = True
        logger.info("telemetry using raw Python logging (service=%s)", self.service_name)

    def is_enabled(self) -> bool:
        return self._initialized

    def get_tracer(self, name: str | None = None) -> Any:
        return None

    def trace_function(
        self,
        span_name: str | None = None,
        attributes: dict[str, Any] | None = None,
    ) -> Callable:
        def decorator(func: Callable) -> Callable:
            name = span_name or f"{func.__module__}.{func.__name__}"

            @wraps(func)
            async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
                start = time.perf_counter()
                try:
                    result = await func(*args, **kwargs)
                    logger.debug("%s ok (%.1f ms)", name, (time.perf_counter() - start) * 1000)
                    return result
                except Exception:
                    logger.exception("%s failed", name)
                    raise

            @wraps(func)
            def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
                start = time.perf_counter()
                try:
                    result = func(*args, **kwargs)
                    logger.debug("%s ok (%.1f ms)", name, (time.perf_counter() - start) * 1000)
                    return result
                except Exception:
                    logger.exception("%s failed", name)
                    raise

            return async_wrapper if inspect.iscoroutinefunction(func) else sync_wrapper

        return decorator


telemetry = TelemetryManager()


def _coerce(value: Any) -> Any:
    if value is None or isinstance(value, (bool, str, int, float)):
        return value
    if isinstance(value, (list, tuple, dict)):
        try:
            return json.dumps(value, ensure_ascii=True, default=str)
        except Exception:
            return str(value)
    return str(value)


def _render(attributes: dict[str, Any] | None) -> str:
    if not attributes:
        return ""
    return " ".join(f"{key}={_coerce(value)}" for key, value in attributes.items() if value is not None)


def log_attribute(span: Any, key: str, value: Any) -> None:
    if value is not None:
        logger.info("%s=%s", key, _coerce(value))


def log_attributes(span: Any = None, attributes: dict[str, Any] | None = None) -> None:
    rendered = _render(attributes)
    if rendered:
        logger.info(rendered)


def log_event(span: Any, name: str, attributes: dict[str, Any] | None = None) -> None:
    rendered = _render(attributes)
    if rendered:
        logger.info("event %s %s", name, rendered)
    else:
        logger.info("event %s", name)


def log_agent_attributes(span: Any, agent_name: str, agent_id: str, model: str | None = None) -> None:
    logger.info("agent name=%s id=%s model=%s", agent_name, agent_id, model or "")


def log_response_attributes(span: Any, response: Any, max_payload_length: int = 2000) -> None:
    logger.info("response type=%s", response.__class__.__name__)
    if telemetry.content_recording_enabled:
        logger.info("response payload=%s", str(response)[:max_payload_length])


def log_query_attributes(span: Any, query: str, session_id: str, user_id: str | None = None) -> None:
    logger.info("query session=%s user=%s", session_id, user_id or "")
    if telemetry.content_recording_enabled:
        logger.info("query text=%s", query[:500])


def log_tool_attributes(
    span: Any,
    tool_name: str,
    tool_args: dict[str, Any] | None = None,
    tool_result: Any = None,
) -> None:
    logger.info("tool name=%s", tool_name)
    if telemetry.content_recording_enabled and tool_args:
        logger.info("tool args=%s", str(tool_args)[:500])
    if telemetry.content_recording_enabled and tool_result is not None:
        logger.info("tool result=%s", str(tool_result)[:500])


def log_orchestration_attributes(
    span: Any,
    source_agent: str,
    target_agent: str,
    routing_reason: str | None = None,
    confidence: str | None = None,
) -> None:
    logger.info(
        "orchestration source=%s target=%s reason=%s confidence=%s",
        source_agent,
        target_agent,
        routing_reason or "",
        confidence or "",
    )


def log_performance_attributes(
    span: Any,
    duration_ms: float,
    input_tokens: int | None = None,
    output_tokens: int | None = None,
    total_tokens: int | None = None,
) -> None:
    logger.info(
        "perf duration_ms=%.1f input=%s output=%s total=%s",
        duration_ms,
        input_tokens,
        output_tokens,
        total_tokens,
    )


def log_status_ok(span: Any = None) -> None:
    return None


def log_status_error(span: Any, exc: Exception | None = None) -> None:
    if exc is None and isinstance(span, BaseException):
        exc = span
    logger.error("error: %s", exc, exc_info=exc if isinstance(exc, BaseException) else None)
