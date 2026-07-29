from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class QueryRequest(BaseModel):
    query: str = Field(..., min_length=1)
    session_id: str | None = None
    user_id: str = "demo-user"
    body: dict[str, Any] | None = None
    context: dict[str, Any] = Field(default_factory=dict)
    history: list[dict[str, Any]] = Field(default_factory=list)
    history_summary: str | None = None
    route_chain: list[str] = Field(default_factory=list)
    request_id: str | None = None
    access_token: str = ""
