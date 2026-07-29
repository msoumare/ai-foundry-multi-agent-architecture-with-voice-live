from __future__ import annotations

import asyncio
import json
import time
from collections.abc import AsyncIterable
from typing import Any

from agent_framework import Agent, AgentResponse, AgentResponseUpdate, Content, Message

from models.query_request import QueryRequest
from models.query_response import QueryResponse


class StructuredSpokeAgent:
    def __init__(self, *, domain_agent: Agent, agent_name: str, history_limit: int = 10) -> None:
        self.domain_agent = domain_agent
        self.agent_name = agent_name
        self.history_limit = max(1, history_limit)
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

    async def _build_response(self, request: QueryRequest, **kwargs: Any) -> AgentResponse:
        query_response = await self._execute(request=request)
        return AgentResponse(
            messages=[Message(role="assistant", contents=[Content.from_text(query_response.response)])],
            additional_properties={
                "query_response": query_response.model_dump(mode="json"),
                "session_id": query_response.session_id,
                "agent": query_response.agent,
                "message_count": query_response.message_count,
                "processing_time": query_response.processing_time,
                "confidence": query_response.confidence,
                "agent_response_time": query_response.agent_response_time,
                "domain_agent_response_time": query_response.domain_agent_response_time,
                "tool_results": query_response.tool_results,
                "token_usage": query_response.token_usage,
            },
        )

    async def _build_response_stream(self, request: QueryRequest, **kwargs: Any) -> AsyncIterable[AgentResponseUpdate]:
        query_response = await self._execute(request=request)
        yield AgentResponseUpdate(
            contents=[Content.from_text(query_response.response)],
            role="assistant",
            author_name=self.agent_name,
            additional_properties={"query_response": query_response.model_dump(mode="json")},
        )

    async def _execute(self, *, request: QueryRequest) -> QueryResponse:
        start_time = time.perf_counter()
        session_id = request.session_id or "local-session"
        history = self._history_from_request(request=request, session_id=session_id)
        outbound_messages = self._build_prompt_history(request=request, history=history)

        agent_started = time.perf_counter()
        response = await self.domain_agent.run(outbound_messages)
        agent_duration = time.perf_counter() - agent_started
        response_text = self._extract_response_text(response)
        token_usage = self._extract_token_usage(response)

        if not request.history:
            self._store_turn(session_id=session_id, query=request.query, answer=response_text)

        return QueryResponse(
            response=response_text,
            session_id=session_id,
            agent=self.agent_name,
            message_count=len(self._history.get(session_id, [])),
            confidence="high",
            agent_response_time=agent_duration,
            domain_agent_response_time=agent_duration,
            processing_time=time.perf_counter() - start_time,
            tool_results=[],
            token_usage=token_usage,
        )

    def _history_from_request(self, *, request: QueryRequest, session_id: str) -> list[Message]:
        if request.history:
            messages: list[Message] = []
            for item in request.history[-(self.history_limit * 2):]:
                role = item.get("role", "user")
                text = item.get("text", "")
                if text:
                    messages.append(Message(role=role, contents=[Content.from_text(text)]))
            return messages
        return self._history.get(session_id, [])

    def _build_prompt_history(self, *, request: QueryRequest, history: list[Message]) -> list[Message]:
        messages: list[Message] = []
        if request.context:
            context_text = "\n".join(f"{k}: {v}" for k, v in request.context.items())
            messages.append(Message(role="system", contents=[Content.from_text(context_text)]))
        if request.history_summary:
            messages.append(Message(role="system", contents=[Content.from_text(f"history_summary: {request.history_summary}")]))
        if history:
            messages.extend(history[-self.history_limit:])
        messages.append(Message(role="user", contents=[Content.from_text(request.query)]))
        return messages

    def _build_request(
        self,
        *,
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
            session_id = getattr(session, "id", None) if session is not None else None
            request.session_id = str(session_id) if session_id else "local-session"

        return request

    def _store_turn(self, *, session_id: str, query: str, answer: str) -> None:
        history = self._history.setdefault(session_id, [])
        history.append(Message(role="user", contents=[Content.from_text(query)]))
        history.append(Message(role="assistant", contents=[Content.from_text(answer)]))
        if len(history) > self.history_limit * 2:
            del history[: -(self.history_limit * 2)]

    @staticmethod
    def _extract_response_text(response: AgentResponse) -> str:
        text = (getattr(response, "text", "") or "").strip()
        if text:
            return text

        parts: list[str] = []
        for message in getattr(response, "messages", []):
            for content in getattr(message, "contents", []):
                value = getattr(content, "text", None)
                if value:
                    parts.append(value)
        return "\n".join(parts).strip()

    @staticmethod
    def _extract_token_usage(response: AgentResponse) -> dict[str, int] | None:
        usage = getattr(response, "usage_details", None)
        if isinstance(usage, dict):
            return {
                "input_tokens": usage.get("input_token_count", 0),
                "output_tokens": usage.get("output_token_count", 0),
                "total_tokens": usage.get("total_token_count", 0),
            }
        if usage is None:
            usage = getattr(response, "usage", None)
        if usage is None:
            return None

        result: dict[str, int] = {}
        for key in ("input_tokens", "output_tokens", "total_tokens"):
            value = getattr(usage, key, None)
            if isinstance(value, int):
                result[key] = value
        return result or None
