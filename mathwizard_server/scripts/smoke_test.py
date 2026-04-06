from __future__ import annotations

import os

from fastapi.testclient import TestClient

from app.main import app


def main() -> None:
    client = TestClient(app)

    health = client.get("/health")
    print("GET /health", health.status_code, health.json())

    solve = client.post("/solve", json={"latex": "x^2 - 5*x + 6 = 0"})
    print("POST /solve", solve.status_code, solve.json())

    if os.getenv("MW_BACKEND", "stub").strip().lower() == "transformers":
        print("Skipping /ocr-and-solve smoke test because it requires a real image and model load.")


if __name__ == "__main__":
    main()
