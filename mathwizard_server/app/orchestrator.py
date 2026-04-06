from __future__ import annotations

from .gemma_client import GemmaClient
from .ocr_client import SuryaOcrClient
from .schemas import (
    OcrResponse,
    SolvedResponse,
    SolutionStep,
    ToolCall,
    ToolResult,
    VisionParse,
)
from .tools import MathToolRegistry


class SolveOrchestrator:
    def __init__(
        self,
        ocr_client: SuryaOcrClient,
        gemma_client: GemmaClient | None,
        tool_registry: MathToolRegistry,
    ) -> None:
        self._ocr = ocr_client
        self._gemma = gemma_client
        self._tools = tool_registry

    def ocr_image(self, image_bytes: bytes) -> OcrResponse:
        text = self._ocr.extract_text(image_bytes)
        return OcrResponse(
            latex=text,
            problem_text=text,
        )

    def solve_from_image(self, image_bytes: bytes) -> SolvedResponse:
        # Step 1: OCR with surya
        text = self._ocr.extract_text(image_bytes)

        if not text:
            return SolvedResponse(
                success=False,
                latex="",
                answer="",
                finalAnswer="",
                method="ocr_failed",
                problem_type="unknown",
                steps=[],
                error="Could not extract text from image",
            )

        # Step 2: Solve using tools
        return self.solve_from_text(text)

    def solve_from_text(self, text: str) -> SolvedResponse:
        # Determine problem type and create tool calls
        tool_calls = self._plan_text_tools(text)

        # Execute tools
        tool_results = self._execute_tool_calls(tool_calls)

        # If we have tool results, use them
        primary = next((result for result in tool_results if result.ok), None)

        if primary:
            answer = self._render_answer(primary.result)

            # If Gemma is available, use it to synthesize a nice solution
            if self._gemma:
                parse = VisionParse(
                    problem_text=text,
                    normalized_latex=text,
                    problem_type="equation" if "=" in text else "arithmetic",
                    needs_tools=True,
                    tool_calls=tool_calls,
                )
                return self._gemma.synthesize_solution(
                    parse=parse, tool_results=tool_results
                )

            # Otherwise return basic response
            return SolvedResponse(
                success=True,
                latex=text,
                answer=answer,
                finalAnswer=answer,
                method=tool_calls[0].name if tool_calls else "direct",
                problem_type="equation" if "=" in text else "arithmetic",
                steps=self._tool_results_to_steps(tool_results),
                error=None,
            )

        # No tool succeeded
        return SolvedResponse(
            success=False,
            latex=text,
            answer="",
            finalAnswer="",
            method="tool_failed",
            problem_type="equation" if "=" in text else "arithmetic",
            steps=self._tool_results_to_steps(tool_results),
            error="No tool execution succeeded",
        )

    def _plan_text_tools(self, text: str) -> list[ToolCall]:
        compact = text.replace(" ", "")
        if "=" in compact:
            return [ToolCall(name="solve_equation", arguments={"equation": text})]
        return [ToolCall(name="evaluate_expression", arguments={"expression": text})]

    def _execute_tool_calls(self, tool_calls: list[ToolCall]) -> list[ToolResult]:
        results: list[ToolResult] = []
        for call in tool_calls:
            try:
                payload = self._tools.execute(call.name, call.arguments)
                results.append(ToolResult(name=call.name, ok=True, result=payload))
            except Exception as exc:
                results.append(ToolResult(name=call.name, ok=False, error=str(exc)))
        return results

    @staticmethod
    def _render_answer(result: object | None) -> str:
        if isinstance(result, dict):
            if "solutions" in result:
                solutions = result["solutions"]
                if isinstance(solutions, list):
                    return " or ".join(str(item) for item in solutions)
            if "value" in result:
                return str(result["value"])
            if "simplified" in result:
                return str(result["simplified"])
        return str(result) if result is not None else "Unable to solve"

    @staticmethod
    def _tool_results_to_steps(tool_results: list[ToolResult]) -> list[SolutionStep]:
        steps: list[SolutionStep] = []
        for index, result in enumerate(tool_results, start=1):
            payload = result.result if isinstance(result.result, dict) else {}
            formula = payload.get("latex", "") if isinstance(payload, dict) else ""
            description = (
                f"Executed {result.name} successfully."
                if result.ok
                else f"{result.name} failed: {result.error}"
            )
            steps.append(
                SolutionStep(
                    number=index,
                    title=result.name.replace("_", " ").title(),
                    description=description,
                    formula=formula,
                    explanation=None if result.ok else result.error,
                )
            )
        return steps
