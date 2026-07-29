from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class QueryResponse(BaseModel):
    response: str
    session_id: str
    agent: str | None = None
    message_count: int = 0
    confidence: str | None = None
    agent_response_time: float | None = None
    domain_agent_response_time: float | None = None
    processing_time: float = 0.0
    tool_results: list[dict[str, Any]] = Field(default_factory=list)
    token_usage: dict[str, int] | None = None
