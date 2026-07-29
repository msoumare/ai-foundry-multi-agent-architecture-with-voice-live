from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class QueryRequest(BaseModel):
    """Banking query request model."""

    query: str = Field(..., min_length=1, description="Customer message or question")
    session_id: str | None = Field(default=None, description="Existing session identifier")
    user_id: str = Field(default="demo-user", description="User identifier for the sample scaffold")
    body: dict[str, Any] | None = Field(default=None, description="Optional adaptive-card or structured payload")
    context: dict[str, Any] = Field(default_factory=dict, description="Additional request context")
    history: list[dict[str, Any]] = Field(default_factory=list, description="Bounded upstream conversation history")
    history_summary: str | None = Field(default=None, description="Optional rolling summary of earlier turns")
    route_chain: list[str] = Field(default_factory=list, description="Ordered list of agents that handled the request")
    request_id: str | None = Field(default=None, description="Cross-agent request identifier")
    access_token: str = Field(default="", description="Optional access token for authentication")
