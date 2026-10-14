from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    done: bool | None = None


class TaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str | None
    done: bool
    created_at: datetime


class ChaosConfig(BaseModel):
    error_rate: float = Field(default=0.0, ge=0.0, le=1.0, description="proportion de réponses 500 sur /api/*")
    latency_ms: int = Field(default=0, ge=0, le=10_000, description="latence ajoutée sur /api/*")
