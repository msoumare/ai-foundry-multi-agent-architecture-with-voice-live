from __future__ import annotations

import asyncio
import json
import time
from collections.abc import AsyncIterable
from typing import Any

from agent_framework import Agent, AgentResponse, AgentResponseUpdate, Content, Message
from opentelemetry import trace

from models.query_request import QueryRequest
from models.query_response import QueryResponse
from models.roles import Role
from services.telemetry import log_attributes, log_event, log_status_error, telemetry


class CardAgent:
    """Lean card agent: parse request, process card intent, optionally delegate, return response."""

    _MAX_HISTORY = 10

    def __init__(
        self,
        *,
        card_agent: Agent | None = None,
        domain_agent: Agent | None = None,
        fallback_session_id: str = "local-session",
    ) -> None:
        self.card_agent = card_agent or domain_agent
        if self.card_agent is None:
            raise ValueError("CardAgent requires card_agent (or domain_agent) to be provided.")

        self.fallback_session_id = fallback_session_id
        self._history: dict[str, list[Message]] = {}

    # ------------------------------------------------------------------
    # Agent framework interface
    # ------------------------------------------------------------------

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

    # ------------------------------------------------------------------
    # Request Parsing
    # ------------------------------------------------------------------

    def _build_request(
        self,
        messages: str | Message | list[str] | list[Message] | None,
        session: Any | None,
    ) -> QueryRequest:
        if messages is None:
            raise ValueError("Please send a message.")

        current: str | Message
        if isinstance(messages, list):
            if not messages:
                raise ValueError("Please send a message.")
            current = messages[-1]
        else:
            current = messages

        if isinstance(current, str):
            raw_text = current.strip()
        elif isinstance(current, Message):
            raw_text = (current.text or "").strip()
            if not raw_text:
                parts: list[str] = []
                for content in getattr(current, "contents", []):
                    value = getattr(content, "text", None)
                    if value:
                        parts.append(value)
                raw_text = "\n".join(parts).strip()
        else:
            raise ValueError("Messages must be strings or Message instances.")

        if not raw_text:
            raise ValueError("Please send a message.")

        try:
            request = QueryRequest.model_validate(json.loads(raw_text)) if raw_text.startswith("{") else QueryRequest(query=raw_text)
        except Exception as exc:
            raise ValueError("Request must be valid JSON for QueryRequest or plain text query.") from exc

        if not request.session_id:
            if session is not None and getattr(session, "id", None):
                request.session_id = str(session.id)
            else:
                request.session_id = self.fallback_session_id

        return request

    # ------------------------------------------------------------------
    # Response Construction
    # ------------------------------------------------------------------

    async def _build_response(
        self,
        request: QueryRequest,
        **kwargs: Any,
    ) -> AgentResponse:
        query_response = await self._execute(request=request)
        payload = query_response.model_dump_json()
        return AgentResponse(
            messages=[
                Message(
                    role=Role.ASSISTANT,
                    contents=[Content.from_text(payload)],
                )
            ],
        )

    async def _build_response_stream(
        self,
        request: QueryRequest,
        **kwargs: Any,
    ) -> AsyncIterable[AgentResponseUpdate]:
        query_response = await self._execute(request=request)
        payload = query_response.model_dump_json()
        yield AgentResponseUpdate(
            contents=[Content.from_text(payload)],
            role=Role.ASSISTANT,
            author_name="card-agent",
        )

    # ------------------------------------------------------------------
    # Execution Pipeline
    # ------------------------------------------------------------------

    @telemetry.trace_function(span_name="CardAgent._execute")
    async def _execute(
        self,
        *,
        request: QueryRequest,
    ) -> QueryResponse:
        start_time = time.perf_counter()
        session_id = request.session_id
        history = self._history_from_request(request=request, session_id=session_id)
        span = trace.get_current_span()
        log_attributes(
            span,
            {
                "agent.name": "card-agent",
                "session.id": session_id,
                "user.id": request.user_id,
                "query.length": len(request.query),
            },
        )

        try:
            result = await self._process_query(request=request, history=history)

            final_text = result["response"]
            handled_by = result["agent"]
            confidence = result["confidence"]
            token_usage = result["token_usage"]
            card_time = result["card_agent_response_time"]
            suggested_next_agent = result.get("suggested_next_agent")

            if not request.history:
                self._store_turn(session_id=session_id, query=request.query, answer=final_text)

            return QueryResponse(
                response=final_text,
                session_id=session_id,
                agent=handled_by,
                message_count=len(self._history.get(session_id, [])),
                confidence=confidence,
                card_agent_response_time=card_time,
                processing_time=time.perf_counter() - start_time,
                tool_results=[],
                token_usage=token_usage,
                suggested_next_agent=suggested_next_agent,
            )
        except Exception as exc:
            log_status_error(span, exc)
            log_event(span, "card.processing.failed", {"session.id": session_id, "agent.name": "card-agent"})
            return self._build_error_response(session_id=session_id, started_at=start_time)

    # ------------------------------------------------------------------
    # Session History Helpers
    # ------------------------------------------------------------------

    def _history_from_request(self, *, request: QueryRequest, session_id: str) -> list[Message]:
        """Merge incoming request history with in-memory session history."""
        session_history = self._history.get(session_id, [])
        if not request.history:
            return session_history

        request_messages: list[Message] = []
        for item in request.history[-(self._MAX_HISTORY * 2):]:
            role = item.get("role", Role.USER)
            text = item.get("text", "")
            if text:
                request_messages.append(Message(role=role, contents=[Content.from_text(text)]))

        if not request_messages:
            return session_history

        merged = [*request_messages, *session_history]
        return merged[-(self._MAX_HISTORY * 2):]

    def _store_turn(self, *, session_id: str, query: str, answer: str) -> None:
        history = self._history.setdefault(session_id, [])
        history.append(Message(role=Role.USER, contents=[Content.from_text(query)]))
        history.append(Message(role=Role.ASSISTANT, contents=[Content.from_text(answer)]))

        if len(history) > self._MAX_HISTORY * 2:
            del history[: -(self._MAX_HISTORY * 2)]

    # ------------------------------------------------------------------
    # Query Processing
    # ------------------------------------------------------------------

    async def _process_query(self, *, request: QueryRequest, history: list[Message]) -> dict[str, Any]:
        card_messages = self._build_prompt_history(request=request, history=history)

        card_started = time.perf_counter()
        card_response = await self.card_agent.run(card_messages)
        card_duration = time.perf_counter() - card_started

        card_output = (getattr(card_response, "text", "") or "").strip()
        if not card_output and card_response.messages:
            parts: list[str] = []
            for content in card_response.messages[-1].contents:
                value = getattr(content, "text", None)
                if value:
                    parts.append(value)
            card_output = "\n".join(parts).strip()

        usage = getattr(card_response, "usage_details", None)
        if isinstance(usage, dict):
            token_usage = {
                "input_tokens": usage.get("input_token_count", 0),
                "output_tokens": usage.get("output_token_count", 0),
                "total_tokens": usage.get("total_token_count", 0),
            }
        else:
            if usage is None:
                usage = getattr(card_response, "usage", None)

            if usage is None:
                token_usage = None
            else:
                result: dict[str, int] = {}
                input_tokens = getattr(usage, "input_tokens", None)
                output_tokens = getattr(usage, "output_tokens", None)
                total_tokens = getattr(usage, "total_tokens", None)

                if isinstance(input_tokens, int):
                    result["input_tokens"] = input_tokens
                if isinstance(output_tokens, int):
                    result["output_tokens"] = output_tokens
                if isinstance(total_tokens, int):
                    result["total_tokens"] = total_tokens

                token_usage = result or None

        # Signal the hub about a possible next routing hop — hub decides whether to act on it.
        # Card never forwards directly; cross-domain routing is exclusively the hub's responsibility.
        suggested_next_agent: str | None = None
        if isinstance(request.context, dict):
            candidate = request.context.get("delegate_to")
            if isinstance(candidate, str) and candidate.strip():
                suggested_next_agent = candidate.strip().lower()
        if suggested_next_agent is None and isinstance(request.body, dict):
            candidate = request.body.get("delegate_to")
            if isinstance(candidate, str) and candidate.strip():
                suggested_next_agent = candidate.strip().lower()

        return {
            "response": card_output,
            "agent": "card-agent",
            "confidence": "high",
            "token_usage": token_usage,
            "suggested_next_agent": suggested_next_agent,
            "card_agent_response_time": card_duration,
        }

    def _build_prompt_history(self, *, request: QueryRequest, history: list[Message]) -> list[Message]:
        messages: list[Message] = []
        if request.context:
            context_text = "\n".join(f"{k}: {v}" for k, v in request.context.items())
            messages.append(Message(role=Role.SYSTEM, contents=[Content.from_text(context_text)]))
        if request.history_summary:
            messages.append(Message(role=Role.SYSTEM, contents=[Content.from_text(f"history_summary: {request.history_summary}")]))
        if history:
            messages.extend(history[-self._MAX_HISTORY :])
        messages.append(Message(role=Role.USER, contents=[Content.from_text(request.query)]))
        return messages

    # ------------------------------------------------------------------
    # Error Handling
    # ------------------------------------------------------------------

    def _build_error_response(
        self,
        *,
        session_id: str,
        started_at: float,
        message: str = "I could not process the request right now. Please try again.",
    ) -> QueryResponse:
        return QueryResponse(
            response=message,
            session_id=session_id,
            agent="card-agent",
            processing_time=time.perf_counter() - started_at,
            tool_results=[],
        )

