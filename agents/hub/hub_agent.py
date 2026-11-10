from __future__ import annotations

import asyncio
import json
import time
import uuid
from collections.abc import AsyncIterable
from typing import Any

from agent_framework import Agent, AgentResponse, AgentResponseUpdate, Content, Message
from opentelemetry import trace

from config import HubAgentResponseMessages
from models.query_request import QueryRequest
from models.query_response import QueryResponse
from models.roles import Role
from services.agent_invoker import AgentInvoker
from services.telemetry import log_attributes, log_orchestration_attributes, log_status_error, telemetry


class HubAgent:
    """
    Intent-recognition hub agent.

    Responsibilities (only):
      1. Parse incoming QueryRequest.
      2. Ask the hub agent which domain agent should handle the query.
      3. Forward the original query to that domain agent via AgentInvoker.
      4. Return the domain agent's response wrapped in QueryResponse.
    """

    _MAX_HISTORY = 10

    @staticmethod
    def _normalize_agent_id(value: str) -> str:
        return "".join(ch for ch in value.lower() if ch.isalnum())

    def __init__(self, hub_agent: Agent) -> None:
        self.hub_agent = hub_agent
        self.agent_invoker = AgentInvoker()
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
        try:
            request = self._build_request(messages)
        except ValueError as exc:
            # Return a structured response instead of raising, so protocol callers
            # get a model response payload instead of HTTP 500.
            fallback_response = QueryResponse(
                response=str(exc),
                session_id=f"hub-{uuid.uuid4().hex}",
                agent="hub-agent",
            )
            if stream:
                return self._build_error_response_stream(fallback_response)
            return self._build_error_response(fallback_response)

        if stream:
            return self._build_response_stream(request=request, **kwargs)
        return self._build_response(request=request, **kwargs)

    # ------------------------------------------------------------------
    # Request Parsing
    # ------------------------------------------------------------------

    def _build_request(self, messages: str | Message | list[str] | list[Message] | None) -> QueryRequest:
        try:
            if messages is None:
                raise ValueError(HubAgentResponseMessages.EMPTY_MESSAGE)

            current: str | Message
            if isinstance(messages, list):
                if not messages:
                    raise ValueError(HubAgentResponseMessages.EMPTY_MESSAGE)
                current = messages[-1]
            else:
                current = messages

            if isinstance(current, str):
                raw_text = current.strip()
            elif isinstance(current, Message):
                raw_text = (current.text or "").strip()
                if not raw_text:
                    for content in getattr(current, "contents", []):
                        text = getattr(content, "text", None)
                        if text:
                            raw_text = text.strip()
                            break
                        model_dump = getattr(content, "model_dump", None)
                        if callable(model_dump):
                            dumped = model_dump(mode="json")
                            if isinstance(dumped, dict):
                                candidate = dumped.get("text")
                                if isinstance(candidate, str) and candidate.strip():
                                    raw_text = candidate.strip()
                                    break
            else:
                raise ValueError("Messages must be strings or Message instances.")

            if not raw_text:
                raise ValueError(HubAgentResponseMessages.EMPTY_MESSAGE)

            if raw_text.startswith("{"):
                try:
                    parsed = json.loads(raw_text)
                    request = QueryRequest.model_validate(parsed)
                except Exception as exc:
                    raise ValueError(HubAgentResponseMessages.INVALID_REQUEST) from exc
            else:
                request = QueryRequest(query=raw_text)

            if not request.session_id:
                request.session_id = request.request_id or uuid.uuid4().hex

            return request
        except ValueError:
            raise
        except Exception as exc:
            raise ValueError(HubAgentResponseMessages.INVALID_REQUEST) from exc

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
            author_name="hub-agent",
        )

    # ------------------------------------------------------------------
    # Error Handling
    # ------------------------------------------------------------------

    async def _build_error_response(self, query_response: QueryResponse) -> AgentResponse:
        payload = query_response.model_dump_json()
        return AgentResponse(
            messages=[
                Message(
                    role=Role.ASSISTANT,
                    contents=[Content.from_text(payload)],
                )
            ],
        )

    async def _build_error_response_stream(
        self,
        query_response: QueryResponse,
    ) -> AsyncIterable[AgentResponseUpdate]:
        payload = query_response.model_dump_json()
        yield AgentResponseUpdate(
            contents=[Content.from_text(payload)],
            role=Role.ASSISTANT,
            author_name="hub-agent",
        )

    # ------------------------------------------------------------------
    # Execution Pipeline
    # ------------------------------------------------------------------

    @telemetry.trace_function(span_name="HubAgent._execute")
    async def _execute(
        self,
        *,
        request: QueryRequest,
    ) -> QueryResponse:
        span = trace.get_current_span()
        start_time = time.perf_counter()
        session_id = request.session_id

        try:
            history = self._history_from_request(request=request, session_id=session_id)

            log_attributes(
                span,
                {
                    "agent.name": "hub-agent",
                    "session.id": session_id,
                    "user.id": request.user_id,
                    "query.length": len(request.query),
                },
            )

            # Step 1 — classify intent
            hub_agent_start = time.perf_counter()
            hub_agent_response = await self._process_query(request, history)
            hub_agent_duration = time.perf_counter() - hub_agent_start

            agent_id = hub_agent_response.get("agent_id")
            confidence = hub_agent_response.get("confidence")
            hub_token_usage = hub_agent_response.get("token_usage")

            log_attributes(
                span,
                {
                    "hub_agent_duration": hub_agent_duration,
                    "hub_agent_response": hub_agent_response,
                    "hub_agent_token_usage": hub_token_usage,
                },
            )

            # # Step 2 — forward to domain agent; follow suggested_next_agent hints (hub decides)
            # domain_agent_start = time.perf_counter()
            # domain_agent_response = await self.agent_invoker.invoke(
            #     agent_id=agent_id,
            #     request=request,
            #     history=history,
            # )

            # domain_agent_duration = time.perf_counter() - domain_agent_start
            # domain_token_usage = domain_agent_response.token_usage
            # total_token_usage = self._combine_token_usage(hub_token_usage, domain_token_usage)

            # log_attributes(
            #     span,
            #     {
            #         "domain_agent_duration": domain_agent_duration,
            #         "domain_agent_response": domain_agent_response,
            #         "domain_agent_token_usage": domain_token_usage,
            #         "total_token_usage": total_token_usage,
            #     },
            # )

            updated_history = history + [
                Message(role=Role.USER, contents=[Content.from_text(request.query)]),
                Message(role=Role.ASSISTANT, contents=[Content.from_text(hub_agent_response.response)]),
            ]
            self._history[session_id] = updated_history[-(self._MAX_HISTORY * 2):]

            return QueryResponse(
                response=hub_agent_response.response,
                session_id=session_id,
                agent=hub_agent_response.agent or agent_id,
                confidence=hub_agent_response.confidence or confidence, 
                message_count=len(self._history[session_id]),
                hub_agent_duration=hub_agent_duration,
                domain_agent_duration=hub_agent_duration,
                processing_time=time.perf_counter() - start_time,
                tool_results=hub_agent_response.tool_results,
                token_usage=total_token_usage,
            )
        except Exception as exc:
            log_status_error(span, exc)
            response_text = (
                str(exc)
                if isinstance(exc, ValueError)
                else HubAgentResponseMessages.PROCESSING_ERROR
            )
            return QueryResponse(
                response=response_text,
                session_id=session_id,
                agent="hub-agent",
                processing_time=time.perf_counter() - start_time,
            )

    # ------------------------------------------------------------------
    # Query Processing
    # ------------------------------------------------------------------

    async def _process_query(self, request: QueryRequest, history: list[Message]) -> dict[str, Any]:
        """
        Ask the HubAgent which domain agent owns this query.

        Returns a dictionary with hub_agent_result, agent_id, confidence, reason, token_usage.
        Falls back to the first known agent when parsing fails.
        """
        messages = self._build_prompt_history(request, history)
        response = await self.hub_agent.run(messages)
        raw = (getattr(response, "text", "") or "").strip()

        usage_details = getattr(response, "usage_details", None)
        token_usage = (
            {
                "input_tokens": usage_details.get("input_token_count", 0),
                "output_tokens": usage_details.get("output_token_count", 0),
                "total_tokens": usage_details.get("total_token_count", 0),
            }
            if isinstance(usage_details, dict)
            else None
        )

        agent_registry = self.agent_invoker.get_agent_registry()
        normalized_registry = {
            self._normalize_agent_id(route_id): route_id
            for route_id in agent_registry
        }
        fallback = "CognigyAgent" if "CognigyAgent" in agent_registry else (agent_registry[0] if agent_registry else "unknown")

        try:
            payload = json.loads(raw)
            selected_target = str(payload.get("target_agent", fallback) or fallback)
            agent_id = normalized_registry.get(
                self._normalize_agent_id(selected_target),
                fallback,
            )
            confidence = payload.get("confidence", "low")
            reason = payload.get("reason")
            if agent_id not in agent_registry:
                agent_id = fallback
                confidence = "low"
                reason = reason or "unknown_target_agent"
        except (json.JSONDecodeError, AttributeError):
            agent_id = fallback
            confidence = "low"
            reason = "parse_failure"

        span = trace.get_current_span()
        log_orchestration_attributes(
            span,
            source_agent="hub-agent",
            target_agent=agent_id,
            routing_reason=reason,
            confidence=confidence,
        )

        return {
            "hub_agent_result": raw,
            "agent_id": agent_id,
            "confidence": confidence,
            "reason": reason,
            "token_usage": token_usage,
        }

    # ------------------------------------------------------------------
    # Token Usage 
    # ------------------------------------------------------------------

    @staticmethod
    def _combine_token_usage(
        hub_usage: dict[str, int] | None,
        domain_usage: dict[str, int] | None,
    ) -> dict[str, int] | None:
        """
        Merge token usage from hub classification and domain agent response.

        In multi-hop scenarios, both the hub (for intent classification)
        and the domain agent (for query response) consume tokens. This helper
        consolidates observability by summing input, output, and total tokens
        from both hops for accurate cost tracking.

        Args:
            hub_usage: Token counts from hub agent classification (or None).
            domain_usage: Token counts from domain agent response (or None).

        Returns:
            Dictionary with summed input_tokens, output_tokens, total_tokens,
            or None if both inputs are None.
        """
        if not hub_usage and not domain_usage:
            return None

        return {
            "input_tokens": (hub_usage or {}).get("input_tokens", 0) + (domain_usage or {}).get("input_tokens", 0),
            "output_tokens": (hub_usage or {}).get("output_tokens", 0) + (domain_usage or {}).get("output_tokens", 0),
            "total_tokens": (hub_usage or {}).get("total_tokens", 0) + (domain_usage or {}).get("total_tokens", 0),
        }

    # ------------------------------------------------------------------
    # Message Helpers
    # ------------------------------------------------------------------

    def _history_from_request(self, *, request: QueryRequest, session_id: str) -> list[Message]:
        """Merge upstream request history with in-memory session history."""
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

    def _build_prompt_history(self, request: QueryRequest, history: list[Message]) -> list[Message]:
        """Build the message list to forward verbatim to the domain agent."""
        messages: list[Message] = []
        if request.context:
            context_text = "\n".join(f"{k}: {v}" for k, v in request.context.items())
            messages.append(Message(role=Role.SYSTEM, contents=[Content.from_text(context_text)]))
        if history:
            messages.extend(history[-self._MAX_HISTORY:])
        messages.append(Message(role=Role.USER, contents=[Content.from_text(request.query)]))
        return messages
