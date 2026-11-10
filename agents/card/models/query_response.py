from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class QueryResponse(BaseModel):
    """Banking query response model."""

    response: str = Field(..., description="Agent response to the query")
    session_id: str = Field(..., description="Session identifier")
    agent: str | None = Field(default=None, description="Agent that processed the query")
    message_count: int = Field(default=0, description="Number of messages in session")
    confidence: str | None = Field(default=None, description="CardAgent confidence score for processing")
    card_agent_response_time: float | None = Field(default=None, description="Response time of card agent")
    processing_time: float = Field(default=0.0, description="Total request processing time")
    tool_results: list[dict[str, Any]] = Field(default_factory=list, description="Results from called tools")
    token_usage: dict[str, int] | None = Field(default=None, description="Token usage statistics")
