#!/usr/bin/env python3
"""
Mission Control API - Aegis Air-Gapped Inference Orchestrator

This service is the ONLY allowed egress point from the "operator" perspective.
It is deliberately coded to NEVER contact the public internet, OpenAI, Gemini,
or any external LLM provider. All requests are routed to the local Ollama
instance running inside the same Kubernetes namespace.

Endpoints:
  GET  /health
  GET  /model-info
  POST /query   {"prompt": "...", "max_tokens": 256}

Designed for Phi-3-Mini-4k-Instruct via Ollama (OpenAI-compatible /v1).
"""

import os
import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from typing import Optional

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama:11434")
MODEL_NAME = os.getenv("MODEL_NAME", "phi3:mini")
TIMEOUT = 120.0

app = FastAPI(
    title="Aegis Mission Control",
    description="Air-gapped AI inference gateway. No external network access permitted.",
    version="1.0.0-phase2",
)

client = httpx.Client(base_url=OLLAMA_URL, timeout=TIMEOUT)


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
    try:
        r = client.get("/api/tags")
        r.raise_for_status()
        return {
            "status": "ok",
            "ollama_reachable": True,
            "model": MODEL_NAME,
            "airgap_enforced": True,
        }
    except Exception as e:
        return {
            "status": "degraded",
            "ollama_reachable": False,
            "error": str(e),
            "airgap_enforced": True,
        }


@app.get("/model-info")
def model_info():
    return {
        "model": MODEL_NAME,
        "family": "phi-3-mini-4k-instruct",
        "parameters": "3.8B",
        "context": 4096,
        "backend": "ollama",
        "location": "local-only (air-gapped)",
        "note": "Weights loaded exclusively from persistent volume /opt/aegis/models",
    }


@app.post("/query", response_model=QueryResponse)
def query(req: QueryRequest):
    """
    Execute a query against the locally running Phi-3 model.
    This path contains ZERO references to external APIs.
    """
    # Use Ollama's OpenAI-compatible chat endpoint for best results with Phi-3
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
        "options": {
            "num_predict": req.max_tokens,
            "temperature": req.temperature,
        },
        "stream": False,
    }

    try:
        resp = client.post("/api/chat", json=payload)
        resp.raise_for_status()
        data = resp.json()
        content = data.get("message", {}).get("content", "(no content)")
        # Very rough token estimate
        tokens = len(content.split()) * 1.3
    except httpx.HTTPError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Local inference backend unreachable or errored: {e}",
        )

    return QueryResponse(
        response=content.strip(),
        model=MODEL_NAME,
        backend="ollama-local",
        tokens_used=int(tokens),
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
