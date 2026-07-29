"""Downstream domain-agent invocation via FoundryAgent."""

from __future__ import annotations

import asyncio
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from agent_framework import Content, Message
from agent_framework.foundry import FoundryAgent
from azure.identity import DefaultAzureCredential

from config import AgentConfig, DOMAIN_AGENT_REGISTRY, HubAgentConfig
from models.roles import Role
from models.query_request import QueryRequest
from models.query_response import QueryResponse


class AgentInvoker:
    """Registry-based invoker that dispatches requests to downstream agents."""

    def __init__(self) -> None:
        self._registry: dict[str, AgentConfig] = {
            cfg.route_id: cfg for cfg in DOMAIN_AGENT_REGISTRY if cfg.enabled
        }
        self._forward_mode = HubAgentConfig.FORWARD_MODE
        if self._forward_mode not in {"foundry", "local"}:
            raise ValueError("FORWARD_MODE must be one of: foundry, local")

    def get_agent_registry(self) -> list[str]:
        return list(self._registry.keys())

    async def invoke(
        self,
        *,
        agent_id: str,
        request: QueryRequest,
        history: list[Message] | None = None,
        timeout_seconds: float | None = None,
    ) -> QueryResponse:
        """
        Forward *request* to the domain agent identified by *agent_id*.

        Returns the downstream QueryResponse when available.
        Raises KeyError if the route is unknown or disabled.
        Raises asyncio.TimeoutError if the agent exceeds its timeout.
        """
        config = self._registry.get(agent_id)
        if config is None:
            available = ", ".join(self._registry) or "<none>"
            raise KeyError(
                f"Unknown or disabled domain agent '{agent_id}'. Available: {available}"
            )

        # Hub is the orchestration boundary; forward the request payload as-is.
        delegated_request = request

        effective_timeout = timeout_seconds if timeout_seconds is not None else config.timeout_seconds
        if self._forward_mode == "local":
            return await self._invoke_local(config=config, request=delegated_request, timeout_seconds=effective_timeout)

        return await self._invoke_foundry(config=config, request=delegated_request, timeout_seconds=effective_timeout)

    async def _invoke_foundry(
        self,
        *,
        config: AgentConfig,
        request: QueryRequest,
        timeout_seconds: float,
    ) -> QueryResponse:
        project_endpoint = HubAgentConfig.FOUNDRY_PROJECT_ENDPOINT
        model = HubAgentConfig.FOUNDRY_MODEL_DEPLOYMENT
        if not model:
            raise RuntimeError(
                "FOUNDRY_MODEL_DEPLOYMENT is required when FORWARD_MODE=foundry."
            )

        agent_kwargs: dict[str, object] = {
            "project_endpoint": project_endpoint,
            "agent_name": config.agent_name,
            "credential": DefaultAzureCredential(),
            "default_options": {"model": model},
        }
        # allow_preview=True routes to the agent's specific endpoint:
        # {project_endpoint}/agents/{agent_name}/endpoint/protocols/openai
        # Without it, the call goes to /openai/v1 which returns 403 for hosted agents.
        agent_kwargs["allow_preview"] = True

        agent = FoundryAgent(
            **agent_kwargs,
        )
        outbound_messages = [
            Message(
                role=Role.USER,
                contents=[Content.from_text(json.dumps(request.model_dump(mode="json")))],
            )
        ]
        response = await asyncio.wait_for(
            agent.run(outbound_messages),
            timeout=timeout_seconds,
        )

        response_text = (getattr(response, "text", None) or "").strip()
        if not response_text and hasattr(response, "messages"):
            for msg in reversed(getattr(response, "messages", [])):
                for content in getattr(msg, "contents", []):
                    candidate = getattr(content, "text", None)
                    if candidate:
                        response_text = candidate.strip()
                        break
                if response_text:
                    break

        query_response = self._try_parse_query_response(response_text) if response_text else None
        if query_response is not None:
            return query_response

        return QueryResponse(
            response=response_text,
            session_id=request.session_id or "",
            agent=config.route_id,
        )

    async def _invoke_local(
        self,
        *,
        config: AgentConfig,
        request: QueryRequest,
        timeout_seconds: float,
    ) -> QueryResponse:
        if not config.local_url:
            raise RuntimeError(
                f"Local forwarding URL is missing for agent '{config.route_id}'. "
                f"Set {config.route_id.upper()}_AGENT_URL in .env."
            )

        request_payload = {
            "input": json.dumps(request.model_dump(mode="json")),
            "stream": False,
        }

        response_payload = await asyncio.to_thread(
            self._post_json,
            config.local_url,
            request_payload,
            timeout_seconds,
        )

        response_chunks = self._iter_output_text(response_payload)
        query_response = None
        for text in response_chunks:
            query_response = self._try_parse_query_response(text)
            if query_response is not None:
                break
        if query_response is not None:
            return query_response

        return QueryResponse(
            response="\n".join(response_chunks).strip(),
            session_id=request.session_id or "",
            agent=config.route_id,
        )

    @staticmethod
    def _try_parse_query_response(text: str) -> QueryResponse | None:
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            return None

        if not isinstance(payload, dict):
            return None

        try:
            return QueryResponse.model_validate(payload)
        except Exception:
            return None

    @staticmethod
    def _iter_output_text(payload: dict[str, object]) -> list[str]:
        output_items = payload.get("output")
        if not isinstance(output_items, list):
            return []

        chunks: list[str] = []
        for item in output_items:
            if not isinstance(item, dict):
                continue
            content_items = item.get("content")
            if not isinstance(content_items, list):
                continue
            for content in content_items:
                if not isinstance(content, dict):
                    continue
                text = content.get("text")
                if isinstance(text, str) and text.strip():
                    chunks.append(text)
        return chunks

    @staticmethod
    def _post_json(url: str, payload: dict[str, object], timeout_seconds: float) -> dict[str, object]:
        body = json.dumps(payload).encode("utf-8")
        request = Request(
            url,
            data=body,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
            method="POST",
        )
        try:
            with urlopen(request, timeout=timeout_seconds) as response:
                raw = response.read().decode("utf-8")
        except HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="ignore")
            raise RuntimeError(f"Local agent call failed ({exc.code}): {detail}") from exc
        except URLError as exc:
            raise RuntimeError(f"Local agent call failed: {exc}") from exc

        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            return {
                "output": [
                    {
                        "type": "message",
                        "content": [{"type": "output_text", "text": raw}],
                    }
                ]
            }

        if isinstance(parsed, dict):
            return parsed
        return {"output": parsed}
