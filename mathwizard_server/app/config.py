from __future__ import annotations

from dataclasses import dataclass
import os


@dataclass(frozen=True)
class Settings:
    request_timeout_seconds: int = int(
        os.getenv("MW_REQUEST_TIMEOUT_SECONDS", "180").strip()
    )


settings = Settings()
