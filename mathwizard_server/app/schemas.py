from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class SolveRequest(BaseModel):
    latex: str = Field(min_length=1)
    mode: str = "auto"  # auto | solve | expand | simplify | differentiate | integrate | factor


class OcrResponse(BaseModel):
    latex: str
    problem_text: str
    success: bool = True
    error: str | None = None


class SolutionStep(BaseModel):
    number: int
    title: str
    description: str
    formula: str = ""
    explanation: str | None = None


class SolvedResponse(BaseModel):
    success: bool
    latex: str
    answer: str
    finalAnswer: str
    method: str
    problem_type: str
    steps: list[SolutionStep] = Field(default_factory=list)
    error: str | None = None


class HealthResponse(BaseModel):
    status: Literal["ok"]
    backend: str
    model_id: str
