from __future__ import annotations

from typing import Any

from pydantic import BaseModel


class QueryResponse(BaseModel):
    response: str
    session_id: str
    agent: str | None = None
    message_count: int = 0
    confidence: str | None = None
    hub_agent_duration: float | None = None
    domain_agent_duration: float | None = None
    processing_time: float = 0.0
    tool_results: list[dict[str, Any]] = []
    token_usage: dict[str, int] | None = None
    suggested_next_agent: str | None = None
