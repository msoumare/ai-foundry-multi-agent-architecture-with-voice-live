"""OpenTelemetry tracing and observability configuration for the hub agent."""

from __future__ import annotations

import inspect
import json
import os
import threading
from collections.abc import Callable
from functools import wraps
from typing import Any

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.trace import Span, Status, StatusCode, Tracer

from config import HubAgentConfig


class TelemetryManager:
    """Manages OpenTelemetry configuration and tracer instances."""

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
            self.tracer: Tracer | None = None
            self.connection_string: str | None = None
            self.service_name: str | None = None
            self.content_recording_enabled = False
            self.last_error: str | None = None
            self._instance_ready = True

    @staticmethod
    def _normalize_connection_string(connection_string: str) -> str:
        """Normalize Azure Monitor connection strings for exporter compatibility."""
        cleaned_parts: list[str] = []
        unsupported_keys = {"applicationid"}

        for part in connection_string.split(";"):
            part = part.strip()
            if not part or "=" not in part:
                continue

            key, value = part.split("=", 1)
            key = key.strip()
            value = value.strip()
            if not key or not value:
                continue
            if key.lower() in unsupported_keys:
                continue

            cleaned_parts.append(f"{key}={value}")

        return ";".join(cleaned_parts)

    def initialize(
        self,
        connection_string: str | None = None,
        service_name: str | None = None,
        content_recording_enabled: bool | None = None,
        console_export: bool | None = None,
    ) -> None:
        if self._initialized:
            return

        raw_connection_string = connection_string or HubAgentConfig.SERVICE_TELEMETRY
        self.connection_string = (
            self._normalize_connection_string(raw_connection_string)
            if raw_connection_string
            else None
        )
        self.service_name = service_name or HubAgentConfig.SERVICE_NAME

        if content_recording_enabled is None:
            self.content_recording_enabled = HubAgentConfig.AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED
        else:
            self.content_recording_enabled = content_recording_enabled

        if not self.connection_string:
            self._initialized = True
            return

        # In hosted environments, tracing is often configured before app code runs.
        # Reconfiguring providers triggers noisy warnings and should be avoided.
        provider = trace.get_tracer_provider()
        if provider.__class__.__name__ != "ProxyTracerProvider":
            self.tracer = trace.get_tracer(__name__)
            self._initialized = True
            self.last_error = None
            return

        try:
            os.environ.setdefault("OTEL_SERVICE_NAME", self.service_name)

            # Prefer distro helper when available; some environments only have
            # azure-monitor-opentelemetry-exporter installed.
            try:
                from azure.monitor.opentelemetry import configure_azure_monitor
            except Exception:
                configure_azure_monitor = None  # type: ignore[assignment]

            if configure_azure_monitor is not None:
                configure_kwargs: dict[str, Any] = {
                    "connection_string": self.connection_string,
                    "disable_logging": True,
                    "disable_metrics": True,
                    "enable_live_metrics": False,
                    "enable_performance_counters": False,
                }

                configure_azure_monitor(**configure_kwargs)
            else:
                from azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter

                provider = trace.get_tracer_provider()
                if not isinstance(provider, TracerProvider):
                    provider = TracerProvider()
                    trace.set_tracer_provider(provider)

                exporter = AzureMonitorTraceExporter(connection_string=self.connection_string)
                provider.add_span_processor(BatchSpanProcessor(exporter))

            if console_export:
                provider = trace.get_tracer_provider()
                if isinstance(provider, TracerProvider):
                    provider.add_span_processor(BatchSpanProcessor(ConsoleSpanExporter()))

            self.tracer = trace.get_tracer(__name__)

            if self.content_recording_enabled:
                HubAgentConfig.AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED = True

            self._initialized = True
            self.last_error = None
        except Exception as exc:
            self._initialized = True
            self.last_error = str(exc)
            print(f"[telemetry] initialization failed for {self.service_name}: {self.last_error}")

    def get_tracer(self, name: str | None = None) -> Any:
        if not self._initialized:
            self.initialize()

        if self.tracer is not None:
            return self.tracer

        return trace.get_tracer(name or __name__)

    def is_enabled(self) -> bool:
        return self._initialized and self.tracer is not None

    def trace_function(
        self,
        span_name: str | None = None,
        attributes: dict[str, Any] | None = None,
    ) -> Callable:
        def decorator(func: Callable) -> Callable:
            @wraps(func)
            async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
                if not self.is_enabled():
                    return await func(*args, **kwargs)

                tracer = self.get_tracer()
                name = span_name or f"{func.__module__}.{func.__name__}"

                with tracer.start_as_current_span(name) as span:
                    try:
                        if attributes:
                            for key, value in attributes.items():
                                span.set_attribute(key, str(value))
                        result = await func(*args, **kwargs)
                        span.set_status(Status(StatusCode.OK))
                        return result
                    except Exception as exc:
                        span.set_status(Status(StatusCode.ERROR, str(exc)))
                        span.record_exception(exc)
                        raise

            @wraps(func)
            def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
                if not self.is_enabled():
                    return func(*args, **kwargs)

                tracer = self.get_tracer()
                name = span_name or f"{func.__module__}.{func.__name__}"

                with tracer.start_as_current_span(name) as span:
                    try:
                        if attributes:
                            for key, value in attributes.items():
                                span.set_attribute(key, str(value))
                        result = func(*args, **kwargs)
                        span.set_status(Status(StatusCode.OK))
                        return result
                    except Exception as exc:
                        span.set_status(Status(StatusCode.ERROR, str(exc)))
                        span.record_exception(exc)
                        raise

            if inspect.iscoroutinefunction(func):
                return async_wrapper
            return sync_wrapper

        return decorator


telemetry = TelemetryManager()


def _to_otel_attribute(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (bool, str, bytes, int, float)):
        return value
    if isinstance(value, (list, tuple)):
        if all(isinstance(item, (bool, str, bytes, int, float)) for item in value):
            return list(value)
        return json.dumps(value, ensure_ascii=True, default=str)
    if isinstance(value, dict):
        return json.dumps(value, ensure_ascii=True, default=str)
    return str(value)


def log_attribute(span: Span, key: str, value: Any) -> None:
    encoded = _to_otel_attribute(value)
    if encoded is not None:
        span.set_attribute(key, encoded)


def log_attributes(span: Span, attributes: dict[str, Any] | None = None) -> None:
    if not attributes:
        return
    for key, value in attributes.items():
        encoded = _to_otel_attribute(value)
        if encoded is not None:
            span.set_attribute(key, encoded)


def log_agent_attributes(span: Span, agent_name: str, agent_id: str, model: str | None = None) -> None:
    span.set_attribute("gen_ai.agent.name", agent_name)
    span.set_attribute("gen_ai.agent.id", agent_id)
    if model:
        span.set_attribute("gen_ai.request.model", model)


def log_response_attributes(span: Span, response: Any, max_payload_length: int = 2000) -> None:
    span.set_attribute("gen_ai.response.type", response.__class__.__name__)
    if not telemetry.content_recording_enabled:
        return

    payload = str(response)
    span.set_attribute("gen_ai.response.payload", payload[:max_payload_length])


def log_query_attributes(span: Span, query: str, session_id: str, user_id: str | None = None) -> None:
    span.set_attribute("session.id", session_id)
    if user_id:
        span.set_attribute("user.id", user_id)

    if telemetry.content_recording_enabled:
        span.set_attribute("gen_ai.user.query", query[:500])


def log_tool_attributes(
    span: Span,
    tool_name: str,
    tool_args: dict[str, Any] | None = None,
    tool_result: Any = None,
) -> None:
    span.set_attribute("gen_ai.tool.name", tool_name)

    if tool_args and telemetry.content_recording_enabled:
        span.set_attribute("gen_ai.tool.arguments", str(tool_args)[:500])

    if tool_result is not None and telemetry.content_recording_enabled:
        span.set_attribute("gen_ai.tool.result", str(tool_result)[:500])


def log_orchestration_attributes(
    span: Span,
    source_agent: str,
    target_agent: str,
    routing_reason: str | None = None,
    confidence: str | None = None,
) -> None:
    span.set_attribute("gen_ai.orchestration.source_agent", source_agent)
    span.set_attribute("gen_ai.orchestration.target_agent", target_agent)
    if routing_reason:
        span.set_attribute("gen_ai.orchestration.routing_reason", routing_reason)
    if confidence:
        span.set_attribute("gen_ai.orchestration.confidence", confidence)


def log_performance_attributes(
    span: Span,
    duration_ms: float,
    input_tokens: int | None = None,
    output_tokens: int | None = None,
    total_tokens: int | None = None,
) -> None:
    span.set_attribute("gen_ai.response.duration_ms", duration_ms)

    if input_tokens is not None:
        span.set_attribute("gen_ai.usage.input_tokens", input_tokens)

    if output_tokens is not None:
        span.set_attribute("gen_ai.usage.output_tokens", output_tokens)

    if total_tokens is not None:
        span.set_attribute("gen_ai.usage.total_tokens", total_tokens)
    elif input_tokens is not None and output_tokens is not None:
        span.set_attribute("gen_ai.usage.total_tokens", input_tokens + output_tokens)


def log_status_ok(span: Span) -> None:
    span.set_status(Status(StatusCode.OK))


def log_status_error(span: Span, exc: Exception) -> None:
    span.set_status(Status(StatusCode.ERROR, str(exc)))
    span.record_exception(exc)


def log_event(span: Span, name: str, attributes: dict[str, Any] | None = None) -> None:
    span.add_event(name, attributes or {})
