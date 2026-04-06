from __future__ import annotations

from dataclasses import dataclass
import os


@dataclass(frozen=True)
class Settings:
    backend: str = os.getenv("MW_BACKEND", "ollama").strip().lower()
    gemma_model_id: str = os.getenv("MW_GEMMA_MODEL_ID", "gemma3:4b").strip()
    gemma_device: str = os.getenv("MW_GEMMA_DEVICE", "cuda").strip().lower()
    gemma_dtype: str = os.getenv("MW_GEMMA_DTYPE", "auto").strip().lower()
    request_timeout_seconds: int = int(
        os.getenv("MW_REQUEST_TIMEOUT_SECONDS", "180").strip()
    )
    ollama_base_url: str = (
        os.getenv("MW_OLLAMA_BASE_URL", "http://127.0.0.1:11434").strip().rstrip("/")
    )


settings = Settings()
