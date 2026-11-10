"""Payment Agent — core logic for payment and transfer queries."""

from __future__ import annotations

import asyncio
import json
import time
from collections.abc import AsyncIterable
from typing import Any

from agent_framework import Agent, AgentResponse, AgentResponseUpdate, Content, Message
from opentelemetry import trace

from config import PaymentAgentConfig
from models.query_request import QueryRequest
from models.query_response import QueryResponse
from models.roles import Role
from services.telemetry import log_attributes, log_event, log_status_error, telemetry


class PaymentAgent:
    """Payment domain agent: handles transfers, standing orders, direct debits, and payment history."""

    _MAX_HISTORY = 10

    def __init__(self, *, payment_agent: Agent, fallback_session_id: str = "local-session") -> None:
        self.payment_agent = payment_agent
        self.fallback_session_id = fallback_session_id
        self._history: dict[str, list[Message]] = {}

    def run(
        self,
        messages: str | Message | list[str] | list[Message] | None = None,
        *,
        stream: bool = False,
        session: Any | None = None,
        **kwargs: Any,
    ) -> AsyncIterable[AgentResponseUpdate] | asyncio.Future[AgentResponse]:
        request = self._build_request(messages=messages, session=session)
        if stream:
            return self._build_response_stream(request=request, **kwargs)
        return self._build_response(request=request, **kwargs)

    def _build_request(self, messages, session) -> QueryRequest:
        if messages is None:
            raise ValueError("Please send a message.")
        current = messages[-1] if isinstance(messages, list) else messages
        if isinstance(current, str):
            raw_text = current.strip()
        elif isinstance(current, Message):
            raw_text = (current.text or "").strip()
            if not raw_text:
                raw_text = "\n".join(
                    getattr(c, "text", "") for c in getattr(current, "contents", []) if getattr(c, "text", "")
                ).strip()
        else:
            raise ValueError("Messages must be strings or Message instances.")
        if not raw_text:
            raise ValueError("Please send a message.")
        try:
            request = (
                QueryRequest.model_validate(json.loads(raw_text))
                if raw_text.startswith("{")
                else QueryRequest(query=raw_text)
            )
        except Exception as exc:
            raise ValueError("Invalid request format.") from exc
        if not request.session_id:
            request.session_id = str(session.id) if session and getattr(session, "id", None) else self.fallback_session_id
        return request

    async def _build_response(self, request: QueryRequest, **kwargs: Any) -> AgentResponse:
        query_response = await self._execute(request=request)
        return AgentResponse(
            messages=[Message(role=Role.ASSISTANT, contents=[Content.from_text(query_response.model_dump_json())])]
        )

    async def _build_response_stream(self, request: QueryRequest, **kwargs: Any) -> AsyncIterable[AgentResponseUpdate]:
        query_response = await self._execute(request=request)
        yield AgentResponseUpdate(
            contents=[Content.from_text(query_response.model_dump_json())],
            role=Role.ASSISTANT,
            author_name="payment-agent",
        )

    @telemetry.trace_function(span_name="PaymentAgent._execute")
    async def _execute(self, *, request: QueryRequest) -> QueryResponse:
        start_time = time.perf_counter()
        session_id = request.session_id or self.fallback_session_id
        history = self._history_from_request(request=request, session_id=session_id)
        span = trace.get_current_span()
        log_attributes(span, {"agent.name": "payment-agent", "session.id": session_id, "query.length": len(request.query)})

        try:
            messages = [*history, Message(role=Role.USER, contents=[Content.from_text(request.query)])]
            agent_start = time.perf_counter()
            result = await asyncio.wait_for(
                self.payment_agent.run(
                    messages=messages,
                    client_kwargs={"timeout": PaymentAgentConfig.A2A_AGENT_TIMEOUT},
                ),
                timeout=PaymentAgentConfig.A2A_AGENT_TIMEOUT,
            )
            agent_time = time.perf_counter() - agent_start

            response_text = getattr(result, "text", "") or ""
            token_usage = None
            if hasattr(result, "token_usage") and result.token_usage:
                token_usage = {
                    "prompt_tokens": getattr(result.token_usage, "prompt_tokens", 0),
                    "completion_tokens": getattr(result.token_usage, "completion_tokens", 0),
                    "total_tokens": getattr(result.token_usage, "total_tokens", 0),
                }

            if not request.history:
                self._store_turn(session_id=session_id, query=request.query, answer=response_text)

            return QueryResponse(
                response=response_text,
                session_id=session_id,
                agent="payment-agent",
                message_count=len(self._history.get(session_id, [])),
                confidence="high",
                payment_agent_response_time=agent_time,
                processing_time=time.perf_counter() - start_time,
                token_usage=token_usage,
            )
        except Exception as exc:
            log_status_error(span, exc)
            log_event(span, "payment.processing.failed", {"session.id": session_id})
            return QueryResponse(
                response="I encountered an error processing your payment request. Please try again.",
                session_id=session_id,
                agent="payment-agent",
                processing_time=time.perf_counter() - start_time,
            )

    def _history_from_request(self, *, request: QueryRequest, session_id: str) -> list[Message]:
        session_history = self._history.get(session_id, [])
        if not request.history:
            return session_history
        incoming = [
            Message(role=t.get("role", "user"), contents=[Content.from_text(t.get("content") or t.get("text", ""))])
            for t in request.history if t.get("content") or t.get("text")
        ]
        return ([*incoming, *session_history])[-self._MAX_HISTORY:]

    def _store_turn(self, *, session_id: str, query: str, answer: str) -> None:
        history = self._history.setdefault(session_id, [])
        history.extend([
            Message(role=Role.USER, contents=[Content.from_text(query)]),
            Message(role=Role.ASSISTANT, contents=[Content.from_text(answer)]),
        ])
        self._history[session_id] = history[-self._MAX_HISTORY:]
