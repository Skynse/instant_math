from __future__ import annotations

import base64
import io
import json
import logging
from abc import ABC, abstractmethod
from typing import Any

from PIL import Image
from pydantic import ValidationError

from .config import settings
from .schemas import SolvedResponse, ToolCall, ToolPlan, ToolResult, VisionParse

logger = logging.getLogger(__name__)


class GemmaClient(ABC):
    @abstractmethod
    def analyze_image(self, image_bytes: bytes) -> VisionParse:
        raise NotImplementedError

    @abstractmethod
    def plan_tools(self, problem_text: str, normalized_latex: str) -> list[ToolCall]:
        raise NotImplementedError

    @abstractmethod
    def synthesize_solution(
        self,
        parse: VisionParse,
        tool_results: list[ToolResult],
    ) -> SolvedResponse:
        raise NotImplementedError


class StubGemmaClient(GemmaClient):
    def analyze_image(self, image_bytes: bytes) -> VisionParse:
        raise RuntimeError(
            "Image solving requires a real Gemma backend. Set MW_BACKEND=ollama "
            "and MW_GEMMA_MODEL_ID to a local Ollama tag such as gemma4:e2b."
        )

    def plan_tools(self, problem_text: str, normalized_latex: str) -> list[ToolCall]:
        text = normalized_latex or problem_text
        if "=" in text and "^2" in text:
            return []
        return []

    def synthesize_solution(
        self,
        parse: VisionParse,
        tool_results: list[ToolResult],
    ) -> SolvedResponse:
        raise RuntimeError("Stub backend cannot synthesize image solutions.")


class OllamaGemmaClient(GemmaClient):
    def __init__(self) -> None:
        try:
            import httpx
        except ImportError as exc:
            raise RuntimeError("httpx is required for the Ollama backend.") from exc
        self._httpx = httpx
        self._base_url = settings.ollama_base_url
        self._model = settings.gemma_model_id

    def _preprocess_image(self, image_bytes: bytes) -> bytes:
        """Resize and pad image for optimal vision model performance."""
        img = Image.open(io.BytesIO(image_bytes))

        # Convert to RGB if necessary
        if img.mode != "RGB":
            img = img.convert("RGB")

        # Target size for vision models (Gemma3 expects 896x896 optimally)
        target_size = (896, 896)

        # Calculate scaling to fit within target while maintaining aspect ratio
        img.thumbnail(target_size, Image.Resampling.LANCZOS)

        # Create new image with padding to make it square
        new_img = Image.new("RGB", target_size, (255, 255, 255))  # White background

        # Paste resized image centered
        offset = ((target_size[0] - img.width) // 2, (target_size[1] - img.height) // 2)
        new_img.paste(img, offset)

        # Convert back to bytes
        buffer = io.BytesIO()
        new_img.save(buffer, format="PNG")
        return buffer.getvalue()

    def analyze_image(self, image_bytes: bytes) -> VisionParse:
        prompt = """
You are extracting a math problem from an image for a local solver.

Return JSON only. No markdown. No commentary. No prose before or after the JSON.

Schema:
{
  "problem_text": "string",
  "normalized_latex": "string",
  "problem_type": "arithmetic|algebra|equation|system|geometry|calculus|statistics|word_problem|unknown",
  "needs_tools": true,
  "tool_calls": []
}

Rules:
- Read exactly what is visible in the image.
- If the image contains a single equation or expression, put it in normalized_latex.
- Use plain ASCII operators when possible, for example x^2 instead of Unicode superscripts.
- Do not solve the problem in this step.
- Do not guess values that are not visible.
- Leave tool_calls empty in this step.
""".strip()
        # Preprocess image before sending to Ollama
        processed_bytes = self._preprocess_image(image_bytes)
        return self._generate_typed_json(
            prompt=prompt,
            schema_type=VisionParse,
            image_bytes=processed_bytes,
        )

    def plan_tools(self, problem_text: str, normalized_latex: str) -> list[ToolCall]:
        prompt = f"""
You are planning internal math tool calls for a local solver.

Return JSON only. No markdown. No commentary.

Allowed tool names:
- evaluate_expression
- simplify_expression
- factor_expression
- solve_linear
- solve_equation
- solve_quadratic
- solve_system

Schema:
{{
  "tool_calls": [
    {{"name": "tool_name", "arguments": {{}}}}
  ]
}}

Rules:
- Use the smallest number of tool calls needed.
- Prefer solve_quadratic only when coefficients a, b, c are obvious.
- Prefer solve_system only for explicit multi-equation systems.
- Prefer solve_equation for a single symbolic equation.
- If no tool is needed, return {{"tool_calls": []}}.
- Do not invent tool names.

problem_text: {problem_text}
normalized_latex: {normalized_latex}
""".strip()
        plan = self._generate_typed_json(prompt=prompt, schema_type=ToolPlan)
        return plan.tool_calls

    def synthesize_solution(
        self,
        parse: VisionParse,
        tool_results: list[ToolResult],
    ) -> SolvedResponse:
        prompt = f"""
You are producing the final structured math solution for the app.

Return JSON only. No markdown. No prose outside the JSON.

Schema:
{{
  "success": true,
  "latex": "string",
  "answer": "string",
  "finalAnswer": "string",
  "method": "string",
  "problem_type": "string",
  "steps": [
    {{
      "number": 1,
      "title": "short title",
      "description": "what happened",
      "formula": "$$optional latex$$",
      "explanation": "optional extra explanation"
    }}
  ],
  "error": null
}}

Rules:
- Use the verified tool results as ground truth for calculations.
- Keep steps short and concrete.
- finalAnswer must match answer.
- latex should be parse.normalized_latex when available.
- If a tool failed and no valid answer exists, set success to false and explain the error.
- Do not invent numeric results that are absent from tool_results.

parse: {parse.model_dump_json()}
tool_results: {[result.model_dump() for result in tool_results]}
""".strip()
        return self._generate_typed_json(prompt=prompt, schema_type=SolvedResponse)

    def _generate_typed_json(
        self,
        prompt: str,
        schema_type: type[Any],
        image_bytes: bytes | None = None,
    ) -> Any:
        last_error: Exception | None = None
        response_text = ""
        for attempt in range(2):
            response_text = self._generate_text(
                prompt=prompt
                if attempt == 0
                else self._repair_prompt(prompt, response_text, last_error),
                image_bytes=image_bytes if attempt == 0 else None,
            )
            try:
                payload = self._parse_json(response_text)
                return schema_type.model_validate(payload)
            except (json.JSONDecodeError, ValidationError, ValueError) as exc:
                last_error = exc
        raise RuntimeError(
            f"Ollama Gemma response could not be validated: {last_error}"
        )

    def _generate_text(self, prompt: str, image_bytes: bytes | None = None) -> str:
        messages: list[dict[str, Any]] = [
            {
                "role": "user",
                "content": prompt,
            }
        ]

        if image_bytes is not None:
            # Replace content with array format for multimodal
            encoded = base64.b64encode(image_bytes).decode("ascii")
            messages[0]["content"] = prompt
            messages[0]["images"] = [encoded]

        payload: dict[str, Any] = {
            "model": self._model,
            "stream": False,
            "format": "json",
            "messages": messages,
            "options": {
                "temperature": 0,
                "num_predict": 2048,
            },
        }

        logger.info(f"Sending request to Ollama with model: {self._model}")

        with self._httpx.Client(timeout=settings.request_timeout_seconds) as client:
            response = client.post(f"{self._base_url}/api/chat", json=payload)
            logger.info(f"Ollama response status: {response.status_code}")
            logger.debug(f"Ollama response body: {response.text[:500]}")
            response.raise_for_status()
            data = response.json()

        text = data.get("message", {}).get("content", "")
        if not isinstance(text, str) or not text.strip():
            raise RuntimeError(f"Ollama returned an empty response: {data}")
        return text

    @staticmethod
    def _repair_prompt(
        original_prompt: str, bad_response: str, error: Exception | None
    ) -> str:
        return f"""
The previous response was invalid.

Validation error:
{error}

Previous response:
{bad_response}

Repeat the task and return corrected JSON only.

Original task:
{original_prompt}
""".strip()

    @staticmethod
    def _parse_json(raw: str) -> dict[str, Any]:
        cleaned = raw.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.strip("`")
            if cleaned.startswith("json"):
                cleaned = cleaned[4:].strip()
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise ValueError(f"Model did not return JSON: {raw[:500]}")
        return json.loads(cleaned[start : end + 1])


class TransformersGemmaClient(GemmaClient):
    def __init__(self) -> None:
        try:
            from transformers import (  # type: ignore
                AutoModelForMultimodalLM,
                AutoProcessor,
            )
            import torch  # type: ignore
        except ImportError as exc:
            raise RuntimeError(
                "Transformers backend is not installed. Run pip install -e .[transformers]."
            ) from exc

        self._torch = torch
        model_kwargs: dict[str, Any] = {}
        if settings.gemma_dtype != "auto":
            dtype_name = settings.gemma_dtype
            if not hasattr(torch, dtype_name):
                raise RuntimeError(f"Unsupported MW_GEMMA_DTYPE: {dtype_name}")
            model_kwargs["dtype"] = getattr(torch, dtype_name)

        self._processor = AutoProcessor.from_pretrained(settings.gemma_model_id)
        if settings.gemma_device == "auto":
            model_kwargs["device_map"] = "auto"
            self._model = AutoModelForMultimodalLM.from_pretrained(
                settings.gemma_model_id,
                **model_kwargs,
            )
            self._runtime_device = None
        else:
            self._model = AutoModelForMultimodalLM.from_pretrained(
                settings.gemma_model_id,
                **model_kwargs,
            )
            self._runtime_device = settings.gemma_device
            self._model.to(self._runtime_device)

    def analyze_image(self, image_bytes: bytes) -> VisionParse:
        prompt = """
You are extracting a math problem from an image for a local solver.

Return JSON only. No markdown. No commentary. No prose before or after the JSON.

Schema:
{
  "problem_text": "string",
  "normalized_latex": "string",
  "problem_type": "arithmetic|algebra|equation|system|geometry|calculus|statistics|word_problem|unknown",
  "needs_tools": true,
  "tool_calls": []
}

Rules:
- Read exactly what is visible in the image.
- If the image contains a single equation or expression, put it in normalized_latex.
- Use plain ASCII operators when possible, for example x^2 instead of Unicode superscripts.
- Do not solve the problem in this step.
- Do not guess values that are not visible.
- Leave tool_calls empty in this step.
""".strip()
        return self._generate_typed_json(
            prompt=prompt,
            schema_type=VisionParse,
            image_bytes=image_bytes,
        )

    def plan_tools(self, problem_text: str, normalized_latex: str) -> list[ToolCall]:
        prompt = f"""
You are planning internal math tool calls for a local solver.

Return JSON only. No markdown. No commentary.

Allowed tool names:
- evaluate_expression
- simplify_expression
- factor_expression
- solve_linear
- solve_equation
- solve_quadratic
- solve_system

Schema:
{{
  "tool_calls": [
    {{"name": "tool_name", "arguments": {{}}}}
  ]
}}

Rules:
- Use the smallest number of tool calls needed.
- Prefer solve_quadratic only when coefficients a, b, c are obvious.
- Prefer solve_system only for explicit multi-equation systems.
- Prefer solve_equation for a single symbolic equation.
- If no tool is needed, return {{"tool_calls": []}}.
- Do not invent tool names.

problem_text: {problem_text}
normalized_latex: {normalized_latex}
""".strip()
        plan = self._generate_typed_json(prompt=prompt, schema_type=ToolPlan)
        return plan.tool_calls

    def synthesize_solution(
        self,
        parse: VisionParse,
        tool_results: list[ToolResult],
    ) -> SolvedResponse:
        prompt = f"""
You are producing the final structured math solution for the app.

Return JSON only. No markdown. No prose outside the JSON.

Schema:
{{
  "success": true,
  "latex": "string",
  "answer": "string",
  "finalAnswer": "string",
  "method": "string",
  "problem_type": "string",
  "steps": [
    {{
      "number": 1,
      "title": "short title",
      "description": "what happened",
      "formula": "$$optional latex$$",
      "explanation": "optional extra explanation"
    }}
  ],
  "error": null
}}

Rules:
- Use the verified tool results as ground truth for calculations.
- Keep steps short and concrete.
- finalAnswer must match answer.
- latex should be parse.normalized_latex when available.
- If a tool failed and no valid answer exists, set success to false and explain the error.
- Do not invent numeric results that are absent from tool_results.

parse: {parse.model_dump_json()}
tool_results: {[result.model_dump() for result in tool_results]}
""".strip()
        return self._generate_typed_json(prompt=prompt, schema_type=SolvedResponse)

    def _generate_typed_json(
        self,
        prompt: str,
        schema_type: type[Any],
        image_bytes: bytes | None = None,
    ) -> Any:
        last_error: Exception | None = None
        response_text = ""
        for attempt in range(2):
            response_text = self._generate_text(
                prompt=prompt
                if attempt == 0
                else self._repair_prompt(prompt, response_text, last_error),
                image_bytes=image_bytes if attempt == 0 else None,
            )
            try:
                payload = self._parse_json(response_text)
                return schema_type.model_validate(payload)
            except (json.JSONDecodeError, ValidationError, ValueError) as exc:
                last_error = exc
        raise RuntimeError(f"Gemma response could not be validated: {last_error}")

    def _generate_text(self, prompt: str, image_bytes: bytes | None = None) -> str:
        if image_bytes is None:
            messages = [
                {
                    "role": "system",
                    "content": "You are a careful math parsing and tool-planning assistant. Output valid JSON only.",
                },
                {"role": "user", "content": prompt},
            ]
            text = self._processor.apply_chat_template(
                messages,
                tokenize=False,
                add_generation_prompt=True,
                enable_thinking=False,
            )
            inputs = self._processor(text=text, return_tensors="pt")
            if self._runtime_device is not None:
                inputs = inputs.to(self._runtime_device)
            input_len = inputs["input_ids"].shape[-1]
            outputs = self._model.generate(**inputs, max_new_tokens=1024)
            response = self._processor.decode(
                outputs[0][input_len:],
                skip_special_tokens=False,
            )
            parsed = self._processor.parse_response(response)
            return str(
                parsed.get("text", response) if isinstance(parsed, dict) else response
            )

        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "image", "image": image},
                    {"type": "text", "text": prompt},
                ],
            }
        ]
        inputs = self._processor.apply_chat_template(
            messages,
            tokenize=True,
            return_dict=True,
            return_tensors="pt",
            add_generation_prompt=True,
        )
        if self._runtime_device is not None:
            inputs = inputs.to(self._runtime_device)
        input_len = inputs["input_ids"].shape[-1]
        outputs = self._model.generate(**inputs, max_new_tokens=1024)
        response = self._processor.decode(
            outputs[0][input_len:],
            skip_special_tokens=False,
        )
        parsed = self._processor.parse_response(response)
        return str(
            parsed.get("text", response) if isinstance(parsed, dict) else response
        )

    @staticmethod
    def _repair_prompt(
        original_prompt: str, bad_response: str, error: Exception | None
    ) -> str:
        return f"""
The previous response was invalid.

Validation error:
{error}

Previous response:
{bad_response}

Repeat the task and return corrected JSON only.

Original task:
{original_prompt}
""".strip()

    @staticmethod
    def _parse_json(raw: str) -> dict[str, Any]:
        cleaned = raw.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.strip("`")
            if cleaned.startswith("json"):
                cleaned = cleaned[4:].strip()
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise ValueError(f"Model did not return JSON: {raw[:500]}")
        return json.loads(cleaned[start : end + 1])


def create_gemma_client() -> GemmaClient:
    if settings.backend == "ollama":
        return OllamaGemmaClient()
    if settings.backend == "transformers":
        return TransformersGemmaClient()
    return StubGemmaClient()
