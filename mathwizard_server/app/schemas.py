from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class SolveRequest(BaseModel):
    latex: str = Field(min_length=1)


class OcrResponse(BaseModel):
    latex: str
    problem_text: str
    success: bool = True
    error: str | None = None


class ToolCall(BaseModel):
    name: str
    arguments: dict[str, Any] = Field(default_factory=dict)


class ToolResult(BaseModel):
    name: str
    ok: bool
    result: Any | None = None
    error: str | None = None


class VisionParse(BaseModel):
    problem_text: str
    normalized_latex: str = ""
    problem_type: Literal[
        "arithmetic",
        "algebra",
        "equation",
        "system",
        "geometry",
        "calculus",
        "statistics",
        "word_problem",
        "unknown",
    ] = "unknown"
    needs_tools: bool = True
    tool_calls: list[ToolCall] = Field(default_factory=list)


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


class ToolPlan(BaseModel):
    tool_calls: list[ToolCall] = Field(default_factory=list)


class HealthResponse(BaseModel):
    status: Literal["ok"]
    backend: str
    model_id: str
