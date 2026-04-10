from __future__ import annotations

import asyncio

from fastapi import FastAPI, File, HTTPException, UploadFile

from .config import settings
from .ocr_client import create_ocr_client
from .orchestrator import SolveOrchestrator
from .schemas import HealthResponse, OcrResponse, SolveRequest, SolvedResponse


app = FastAPI(title="MathWizard Server", version="0.2.0")

_orchestrator = SolveOrchestrator(ocr_client=create_ocr_client())


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", backend="surya+sympy", model_id="deterministic")


@app.post("/ocr", response_model=OcrResponse)
async def ocr(file: UploadFile = File(...)) -> OcrResponse:
    try:
        data = await file.read()
        return await asyncio.to_thread(_orchestrator.ocr_image, data)
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/solve", response_model=SolvedResponse)
def solve(payload: SolveRequest) -> SolvedResponse:
    try:
        return _orchestrator.solve_from_text(payload.latex, mode=payload.mode)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/ocr-and-solve", response_model=SolvedResponse)
async def ocr_and_solve(file: UploadFile = File(...)) -> SolvedResponse:
    try:
        data = await file.read()
        return await asyncio.to_thread(_orchestrator.solve_from_image, data)
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
