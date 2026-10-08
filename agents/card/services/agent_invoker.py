"""Optional downstream agent invocation for CardAgent with envelope preservation."""

from __future__ import annotations

import asyncio
import json
import re
import uuid

from agent_framework import Agent, Content, Message
from azure.identity import DefaultAzureCredential

from config import AgentConfig, CARD_DOWNSTREAM_REGISTRY, CardAgentConfig
from models.query_request import QueryRequest
from models.query_response import QueryResponse
from models.roles import Role


class AgentInvoker:
    """Registry-based invoker supporting envelope-preserving delegation for 3+ agent chains."""

    def __init__(self) -> None:
        self._registry: dict[str, AgentConfig] = {
            cfg.route_id: cfg for cfg in CARD_DOWNSTREAM_REGISTRY if cfg.enabled
        }

    def known_routes(self) -> list[str]:
        return list(self._registry.keys())

    def has_route(self, route_id: str) -> bool:
        return route_id in self._registry

    async def invoke(
        self,
        *,
        route_id: str,
        request: QueryRequest,
        history: list[Message] | None = None,
        timeout_seconds: float | None = None,
    ) -> QueryResponse:
        """
        Forward QueryRequest to downstream agent with full envelope preservation.
        
        Enriches context with delegation metadata and appends to route_chain.
        Supports nested chains (card → account → etc.) with maintained context/history.
        """
        config = self._registry.get(route_id)
        if config is None:
            available = ", ".join(self._registry) or "<none>"
            raise KeyError(f"Unknown card downstream route '{route_id}'. Available: {available}")

        delegated_request = self._build_delegated_request(
            request=request,
            history=history or [],
            target_agent=route_id,
        )

        effective_timeout = timeout_seconds if timeout_seconds is not None else config.timeout_seconds
        project_endpoint = CardAgentConfig.SERVICE_PROJECT_ENDPOINT

        try:
            from agent_framework.foundry import AzureAIAgentClient
        except ImportError:
            from agent_framework.foundry import FoundryAgent as AzureAIAgentClient

        async with AzureAIAgentClient(
            project_endpoint=project_endpoint,
            agent_name=config.agent_name,
            credential=DefaultAzureCredential(),
            **({"agent_id": config.agent_id} if self._is_legacy_guid(config.agent_id) else {}),
        ) as client:
            agent = Agent(client=client, name=config.route_id)
            outbound_messages = [
                Message(
                    role=Role.USER,
                    contents=[Content.from_text(json.dumps(delegated_request.model_dump(mode="json")))],
                )
            ]
            response = await asyncio.wait_for(agent.run(outbound_messages), timeout=effective_timeout)

        query_response = self._extract_query_response(response)
        if query_response is not None:
            return query_response

        return QueryResponse(
            response=self._extract_response_text(response),
            session_id=request.session_id or "",
            agent=config.route_id,
        )

    @staticmethod
    def _extract_response_text(response: object) -> str:
        text = getattr(response, "text", None)
        if text is None and hasattr(response, "messages"):
            for msg in reversed(getattr(response, "messages", [])):
                for content in getattr(msg, "contents", []):
                    candidate = getattr(content, "text", None)
                    if candidate:
                        text = candidate
                        break
                if text:
                    break

        return (text or "").strip()

    @staticmethod
    def _extract_query_response(response: object) -> QueryResponse | None:
        text_payload = AgentInvoker._extract_response_text(response)
        if not text_payload:
            return None

        try:
            parsed_payload = json.loads(text_payload)
        except json.JSONDecodeError:
            return None

        if not isinstance(parsed_payload, dict):
            return None

        try:
            return QueryResponse.model_validate(parsed_payload)
        except Exception:
            return None

    @staticmethod
    def _build_delegated_request(
        *,
        request: QueryRequest,
        history: list[Message],
        target_agent: str,
    ) -> QueryRequest:
        route_chain = list(request.route_chain)
        if not route_chain:
            route_chain = ["card-agent"]
        if route_chain[-1] != target_agent:
            route_chain.append(target_agent)

        delegated_context = dict(request.context)
        delegated_context.update(
            {
                "origin_agent": delegated_context.get("origin_agent", "card-agent"),
                "current_agent": target_agent,
                "delegated_by": "card-agent",
            }
        )

        return QueryRequest(
            query=request.query,
            session_id=request.session_id,
            user_id=request.user_id,
            body=request.body,
            context=delegated_context,
            history=AgentInvoker._serialize_history(history),
            history_summary=request.history_summary,
            route_chain=route_chain,
            request_id=request.request_id or uuid.uuid4().hex,
            access_token=request.access_token,
        )

    @staticmethod
    def _serialize_history(history: list[Message]) -> list[dict[str, str]]:
        serialized: list[dict[str, str]] = []
        for message in history:
            text = (message.text or "").strip()
            if not text:
                for content in getattr(message, "contents", []):
                    candidate = getattr(content, "text", None)
                    if candidate:
                        text = candidate.strip()
                        break
            if text:
                serialized.append({"role": str(message.role), "text": text})

        return serialized

    @staticmethod
    def _is_legacy_guid(value: str) -> bool:
        if not value:
            return False
        return bool(re.fullmatch(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}", value.strip()))
