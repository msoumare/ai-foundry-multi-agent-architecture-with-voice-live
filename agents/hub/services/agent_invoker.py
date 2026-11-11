"""Downstream domain-agent invocation via FoundryAgent."""

from __future__ import annotations

import asyncio
import json
import time
from collections.abc import AsyncIterable, AsyncIterator
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from agent_framework import Content, Message
from agent_framework.foundry import FoundryAgent
from azure.identity import DefaultAzureCredential

from config import AgentConfig, DOMAIN_AGENT_REGISTRY, HubAgentConfig
from models.roles import Role
from models.query_request import QueryRequest
from models.query_response import QueryResponse

# Must match the key domain agents use for their trailing reasoning item.
DOMAIN_METADATA_KEY = "domain_metadata"


class AgentInvoker:
    """Registry-based invoker that dispatches requests to downstream agents."""

    def __init__(self) -> None:
        self._registry: dict[str, AgentConfig] = {
            cfg.agent_name: cfg for cfg in DOMAIN_AGENT_REGISTRY if cfg.enabled
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

    async def invoke_stream(
        self,
        *,
        agent_id: str,
        request: QueryRequest,
        history: list[Message] | None = None,
        timeout_seconds: float | None = None,
    ) -> AsyncIterator[str | QueryResponse]:
        """Stream the domain agent's answer.

        Yields answer text chunks as they arrive, then exactly one final
        ``QueryResponse`` carrying the full text and the domain metadata.
        """
        config = self._registry.get(agent_id)
        if config is None:
            available = ", ".join(self._registry) or "<none>"
            raise KeyError(
                f"Unknown or disabled domain agent '{agent_id}'. Available: {available}"
            )

        effective_timeout = timeout_seconds if timeout_seconds is not None else config.timeout_seconds
        if self._forward_mode == "local":
            # Local forwarding uses the non-streaming Responses call.
            response = await self._invoke_local(config=config, request=request, timeout_seconds=effective_timeout)
            if response.response:
                yield response.response
            yield response
            return

        agent = self._build_foundry_agent(config)
        updates = agent.run(
            self._outbound_messages(request),
            stream=True,
            # Bounds connecting and each read; consume_stream bounds the total duration.
            client_kwargs={"timeout": effective_timeout},
        )
        async for item in self.consume_stream(
            updates,
            agent_name=config.agent_name,
            session_id=request.session_id or "",
            timeout_seconds=effective_timeout,
        ):
            yield item

    @classmethod
    async def consume_stream(
        cls,
        updates: AsyncIterable[Any],
        *,
        agent_name: str,
        session_id: str,
        timeout_seconds: float,
    ) -> AsyncIterator[str | QueryResponse]:
        """Split a domain Responses stream into spoken text and trailing metadata."""
        deadline = time.monotonic() + timeout_seconds
        chunks: list[str] = []
        reasoning: list[str] = []
        # Domains not yet redeployed still send one QueryResponse JSON document as text;
        # hold JSON-looking output so it is never forwarded to speech verbatim.
        buffering_json: bool | None = None

        async for update in updates:
            for content in update.contents:
                if content.type == "text" and content.text:
                    chunks.append(content.text)
                    if buffering_json is None:
                        stripped = "".join(chunks).lstrip()
                        if not stripped:
                            continue
                        buffering_json = stripped.startswith("{")
                        if not buffering_json:
                            yield "".join(chunks)
                    elif not buffering_json:
                        yield content.text
                elif content.type == "text_reasoning" and content.text:
                    reasoning.append(content.text)
            if time.monotonic() > deadline:
                raise TimeoutError(f"Domain agent '{agent_name}' exceeded {timeout_seconds}s.")

        full_text = "".join(chunks)
        if buffering_json:
            legacy = cls._try_parse_query_response(full_text)
            if legacy is not None:
                if legacy.response:
                    yield legacy.response
                yield legacy
                return
            yield full_text

        metadata = cls._parse_domain_metadata("".join(reasoning))
        yield QueryResponse(
            response=full_text,
            session_id=metadata.get("session_id") or session_id,
            agent=metadata.get("agent") or agent_name,
            confidence=metadata.get("confidence"),
            tool_results=metadata.get("tool_results") or [],
            token_usage=metadata.get("token_usage"),
        )

    @staticmethod
    def _parse_domain_metadata(text: str) -> dict[str, Any]:
        try:
            payload = json.loads(text)
        except (json.JSONDecodeError, TypeError):
            return {}
        metadata = payload.get(DOMAIN_METADATA_KEY) if isinstance(payload, dict) else None
        return metadata if isinstance(metadata, dict) else {}

    @staticmethod
    def _outbound_messages(request: QueryRequest) -> list[Message]:
        return [
            Message(
                role=Role.USER,
                contents=[Content.from_text(json.dumps(request.model_dump(mode="json")))],
            )
        ]

    @staticmethod
    def _build_foundry_agent(config: AgentConfig) -> FoundryAgent:
        model = HubAgentConfig.SERVICE_MODEL_DEPLOYMENT
        if not model:
            raise RuntimeError(
                "SERVICE_MODEL_DEPLOYMENT is required when FORWARD_MODE=foundry."
            )
        # allow_preview=True routes to the agent's specific endpoint:
        # {project_endpoint}/agents/{agent_name}/endpoint/protocols/openai
        # Without it, the call goes to /openai/v1 which returns 403 for hosted agents.
        return FoundryAgent(
            project_endpoint=HubAgentConfig.SERVICE_PROJECT_ENDPOINT,
            agent_name=config.agent_name,
            credential=DefaultAzureCredential(),
            default_options={"model": model},
            allow_preview=True,
        )

    async def _invoke_foundry(
        self,
        *,
        config: AgentConfig,
        request: QueryRequest,
        timeout_seconds: float,
    ) -> QueryResponse:
        agent = self._build_foundry_agent(config)
        response = await asyncio.wait_for(
            agent.run(self._outbound_messages(request)),
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
            agent=config.agent_name,
        )

    async def _invoke_local(
        self,
        *,
        config: AgentConfig,
        request: QueryRequest,
        timeout_seconds: float,
    ) -> QueryResponse:
        if not config.local_url:
            env_var = config.agent_name.upper().replace("-", "_") + "_URL"
            raise RuntimeError(
                f"Local forwarding URL is missing for agent '{config.agent_name}'. "
                f"Set {env_var} in .env."
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
            agent=config.agent_name,
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
