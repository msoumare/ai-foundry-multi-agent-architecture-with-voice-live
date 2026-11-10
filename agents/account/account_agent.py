"""Account Agent — core logic for account-related banking queries.

Handles: profile updates, account access, account status, limits,
statements, and general account enquiries.
"""

from __future__ import annotations

import asyncio
import json
import time
import uuid
from collections.abc import AsyncIterable
from typing import Any

from agent_framework import Agent, AgentResponse, AgentResponseUpdate, Content, Message
from opentelemetry import trace

from config import AccountAgentConfig
from models.query_request import QueryRequest
from models.query_response import QueryResponse
from models.roles import Role
from services.telemetry import log_attributes, log_event, log_status_error, telemetry


class AccountAgent:
    """Account domain agent: processes account-related banking queries."""

    _MAX_HISTORY = 10

    def __init__(
        self,
        *,
        account_agent: Agent | None = None,
        fallback_session_id: str = "local-session",
    ) -> None:
        self.account_agent = account_agent
        if self.account_agent is None:
            raise ValueError("AccountAgent requires account_agent to be provided.")
        self.fallback_session_id = fallback_session_id
        self._history: dict[str, list[Message]] = {}

    # Agent framework interface

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

    # Request parsing

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
            request = (
                QueryRequest.model_validate(json.loads(raw_text))
                if raw_text.startswith("{")
                else QueryRequest(query=raw_text)
            )
        except Exception as exc:
            raise ValueError("Request must be valid JSON for QueryRequest or plain text.") from exc

        if not request.session_id:
            if session is not None and getattr(session, "id", None):
                request.session_id = str(session.id)
            else:
                request.session_id = self.fallback_session_id

        return request

    # Response construction

    async def _build_response(self, request: QueryRequest, **kwargs: Any) -> AgentResponse:
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
            author_name="account-agent",
        )

    # Execution pipeline

    @telemetry.trace_function(span_name="AccountAgent._execute")
    async def _execute(self, *, request: QueryRequest) -> QueryResponse:
        start_time = time.perf_counter()
        session_id = request.session_id or self.fallback_session_id
        history = self._history_from_request(request=request, session_id=session_id)
        span = trace.get_current_span()
        log_attributes(
            span,
            {
                "agent.name": "account-agent",
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
            agent_time = result["account_agent_response_time"]

            if not request.history:
                self._store_turn(session_id=session_id, query=request.query, answer=final_text)

            return QueryResponse(
                response=final_text,
                session_id=session_id,
                agent=handled_by,
                message_count=len(self._history.get(session_id, [])),
                confidence=confidence,
                account_agent_response_time=agent_time,
                processing_time=time.perf_counter() - start_time,
                token_usage=token_usage,
            )
        except Exception as exc:
            log_status_error(span, exc)
            log_event(span, "account.processing.failed", {"session.id": session_id})
            return self._build_error_response(session_id=session_id, started_at=start_time)

    async def _process_query(
        self,
        *,
        request: QueryRequest,
        history: list[Message],
    ) -> dict[str, Any]:
        messages = [*history, Message(role=Role.USER, contents=[Content.from_text(request.query)])]
        agent_start = time.perf_counter()
        result = await asyncio.wait_for(
            self.account_agent.run(
                messages=messages,
                client_kwargs={"timeout": AccountAgentConfig.A2A_AGENT_TIMEOUT},
            ),
            timeout=AccountAgentConfig.A2A_AGENT_TIMEOUT,
        )
        agent_time = time.perf_counter() - agent_start

        response_text = ""
        token_usage: dict[str, int] | None = None

        if hasattr(result, "text"):
            response_text = result.text or ""
        if hasattr(result, "token_usage") and result.token_usage:
            token_usage = {
                "prompt_tokens": getattr(result.token_usage, "prompt_tokens", 0),
                "completion_tokens": getattr(result.token_usage, "completion_tokens", 0),
                "total_tokens": getattr(result.token_usage, "total_tokens", 0),
            }

        return {
            "response": response_text,
            "agent": "account-agent",
            "confidence": "high",
            "token_usage": token_usage,
            "account_agent_response_time": agent_time,
        }

    # Session history helpers

    def _history_from_request(self, *, request: QueryRequest, session_id: str) -> list[Message]:
        session_history = self._history.get(session_id, [])
        if not request.history:
            return session_history

        incoming: list[Message] = []
        for turn in request.history:
            role = turn.get("role", "user")
            text = turn.get("content") or turn.get("text", "")
            if text:
                incoming.append(Message(role=role, contents=[Content.from_text(text)]))

        combined = [*incoming, *session_history]
        return combined[-self._MAX_HISTORY :]

    def _store_turn(self, *, session_id: str, query: str, answer: str) -> None:
        history = self._history.setdefault(session_id, [])
        history.append(Message(role=Role.USER, contents=[Content.from_text(query)]))
        history.append(Message(role=Role.ASSISTANT, contents=[Content.from_text(answer)]))
        self._history[session_id] = history[-self._MAX_HISTORY :]

    def _build_error_response(self, *, session_id: str, started_at: float) -> QueryResponse:
        return QueryResponse(
            response="I encountered an error processing your account request. Please try again.",
            session_id=session_id,
            agent="account-agent",
            processing_time=time.perf_counter() - started_at,
        )
