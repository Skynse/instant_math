$ErrorActionPreference = "Stop"

if (-not $env:MW_BACKEND) {
    $env:MW_BACKEND = "ollama"
}

if (-not $env:MW_GEMMA_MODEL_ID) {
    $env:MW_GEMMA_MODEL_ID = "gemma4:e2b"
}

if (-not $env:MW_GEMMA_DEVICE) {
    $env:MW_GEMMA_DEVICE = "cuda"
}

python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000
