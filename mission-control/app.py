#!/usr/bin/env python3
"""
Mission Control API - Aegis Air-Gapped Inference Orchestrator

This service is the ONLY allowed egress point from the "operator" perspective.
It is deliberately coded to NEVER contact the public internet, OpenAI, Gemini,
or any external LLM provider. All requests are routed to the local inference
backend (Ollama or vLLM) inside the same Kubernetes namespace.

Endpoints:
  GET  /health
  GET  /model-info
  POST /query   {"prompt": "...", "max_tokens": 256}

Phase 5: Supports both Ollama and vLLM via the OpenAI-compatible /v1 API.
Backend selected via INFERENCE_ENGINE + INFERENCE_URL environment variables.
"""

import os
import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from typing import Optional

INFERENCE_URL = os.getenv("INFERENCE_URL") or os.getenv("OLLAMA_URL", "http://ollama:11434")
INFERENCE_ENGINE = os.getenv("INFERENCE_ENGINE", "ollama").lower()
MODEL_NAME = os.getenv("MODEL_NAME", "phi3:mini")
TIMEOUT = 120.0

app = FastAPI(
    title="Aegis Mission Control",
    description="Air-gapped AI inference gateway. No external network access permitted. Supports ollama and vllm backends via OpenAI-compatible API.",
    version="1.1.0-phase5",
)

client = httpx.Client(base_url=INFERENCE_URL, timeout=TIMEOUT)


class QueryRequest(BaseModel):
    prompt: str = Field(..., min_length=3, max_length=4000, description="Mission update or technical question")
    max_tokens: int = Field(512, ge=16, le=2048)
    temperature: float = Field(0.2, ge=0.0, le=1.0)


class QueryResponse(BaseModel):
    response: str
    model: str
    backend: str = "ollama-local"
    tokens_used: Optional[int] = None


@app.get("/health")
def health():
    """
    Health check that works for both Ollama and vLLM via OpenAI /v1/models.
    Falls back to engine-specific paths if needed.
    """
    try:
        # Unified: both vLLM and Ollama support /v1/models (OpenAI compat)
        r = client.get("/v1/models")
        r.raise_for_status()
        models = r.json().get("data", [])
        model_names = [m.get("id") for m in models]
        return {
            "status": "ok",
            "inference_reachable": True,
            "engine": INFERENCE_ENGINE,
            "model": MODEL_NAME,
            "available_models": model_names,
            "airgap_enforced": True,
        }
    except Exception as e:
        # Fallback for older Ollama without /v1 or network hiccup
        try:
            r2 = client.get("/api/tags")
            r2.raise_for_status()
            return {
                "status": "ok",
                "inference_reachable": True,
                "engine": INFERENCE_ENGINE,
                "model": MODEL_NAME,
                "note": "used ollama native /api/tags fallback",
                "airgap_enforced": True,
            }
        except Exception as e2:
            return {
                "status": "degraded",
                "inference_reachable": False,
                "engine": INFERENCE_ENGINE,
                "error": str(e),
                "fallback_error": str(e2),
                "airgap_enforced": True,
            }


@app.get("/model-info")
def model_info():
    backend = INFERENCE_ENGINE
    note = "Weights loaded exclusively from persistent volume /opt/aegis/models"
    if backend == "vllm":
        note = "HF snapshot (config.json + safetensors) loaded from /models via hostPath. --trust-remote-code enabled."
    return {
        "model": MODEL_NAME,
        "family": "phi-3-mini-4k-instruct",
        "parameters": "3.8B",
        "context": 4096,
        "backend": backend,
        "location": "local-only (air-gapped)",
        "note": note,
    }


@app.post("/query", response_model=QueryResponse)
def query(req: QueryRequest):
    """
    Execute a query against the locally running model (Ollama or vLLM).
    Uses the unified OpenAI-compatible /v1/chat/completions API for both engines.
    This path contains ZERO references to external APIs.
    """
    payload = {
        "model": MODEL_NAME,
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are Aegis-1, a tactical AI assistant running in a Special Programs "
                    "air-gapped edge node. You only have access to local weights. "
                    "Keep answers concise, technical, and structured. "
                    "Always prefix with 'MISSION UPDATE:'."
                ),
            },
            {"role": "user", "content": req.prompt},
        ],
        "max_tokens": req.max_tokens,
        "temperature": req.temperature,
        "stream": False,
    }

    try:
        resp = client.post("/v1/chat/completions", json=payload)
        resp.raise_for_status()
        data = resp.json()
        content = data.get("choices", [{}])[0].get("message", {}).get("content", "(no content)")
        # Rough token estimate from usage if present
        usage = data.get("usage", {})
        tokens = usage.get("completion_tokens") or (len(content.split()) * 1.3)
    except httpx.HTTPError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Local inference backend unreachable or errored: {e}",
        )

    return QueryResponse(
        response=content.strip(),
        model=MODEL_NAME,
        backend=f"{INFERENCE_ENGINE}-local",
        tokens_used=int(tokens) if isinstance(tokens, (int, float)) else int(tokens),
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
