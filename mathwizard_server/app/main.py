from __future__ import annotations

import asyncio

from fastapi import FastAPI, File, HTTPException, UploadFile

from .config import settings
from .gemma_client import create_gemma_client
from .ocr_client import create_ocr_client
from .orchestrator import SolveOrchestrator
from .schemas import HealthResponse, OcrResponse, SolveRequest, SolvedResponse
from .tools import MathToolRegistry


app = FastAPI(title="MathWizard Server", version="0.1.0")

_orchestrator = SolveOrchestrator(
    ocr_client=create_ocr_client(),
    gemma_client=create_gemma_client() if settings.backend != "stub" else None,
    tool_registry=MathToolRegistry(),
)


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        status="ok",
        backend=settings.backend,
        model_id=settings.gemma_model_id,
    )


@app.post("/ocr", response_model=OcrResponse)
async def ocr(file: UploadFile = File(...)) -> OcrResponse:
    try:
        data = await file.read()
        # Run blocking Ollama call in thread pool to avoid blocking event loop
        return await asyncio.to_thread(_orchestrator.ocr_image, data)
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/solve", response_model=SolvedResponse)
def solve(payload: SolveRequest) -> SolvedResponse:
    try:
        return _orchestrator.solve_from_text(payload.latex)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/ocr-and-solve", response_model=SolvedResponse)
async def ocr_and_solve(file: UploadFile = File(...)) -> SolvedResponse:
    try:
        data = await file.read()
        # Run blocking Ollama call in thread pool to avoid blocking event loop
        return await asyncio.to_thread(_orchestrator.solve_from_image, data)
    except Exception as exc:
        import traceback

        error_detail = f"{str(exc)}\n\n{traceback.format_exc()}"
        print(f"Error in ocr_and_solve: {error_detail}")  # Server logs
        raise HTTPException(status_code=503, detail=str(exc)) from exc
