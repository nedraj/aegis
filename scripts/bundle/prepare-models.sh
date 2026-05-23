#!/usr/bin/env bash
# prepare-models.sh
# Downloads the Phi-3 weights for the chosen inference engine (ollama or vllm).
# Phase 5: supports both backends.
#   ENGINE=ollama (default): uses Ollama blob layout (~2.2GB quantized, easy)
#   ENGINE=vllm: uses huggingface_hub to fetch full HF snapshot (larger, ~7GB+)

set -euo pipefail

STAGING_DIR="${1:-./staging}"
ENGINE="${ENGINE:-ollama}"
MODEL_DIR="${STAGING_DIR}/models"

mkdir -p "${MODEL_DIR}"

echo "==> Preparing model for air-gap bundle (engine=${ENGINE})..."
echo "    Target: ${MODEL_DIR}"

if [ "${ENGINE}" = "vllm" ]; then
  # vLLM / HF path (Phase 5)
  MODEL_ID="${VLLM_MODEL_ID:-microsoft/Phi-3-mini-4k-instruct}"
  TARGET_DIR="${MODEL_DIR}/phi-3-mini-4k-instruct"

  echo "    vLLM: downloading ${MODEL_ID} (HF snapshot) to ${TARGET_DIR}"
  echo "    WARNING: Full precision Phi-3-mini is ~7.6 GB. On T4 (16GB VRAM) consider"
  echo "             using a quantized variant (AWQ/GPTQ) or --max-model-len 2048."
  mkdir -p "${TARGET_DIR}"

  # Ensure huggingface_hub is available
  if ! python3 -c "import huggingface_hub" 2>/dev/null; then
    echo "    Installing huggingface_hub (required for vLLM model download)..."
    python3 -m pip install --quiet --upgrade huggingface_hub
  fi

  VLLM_MODEL_ID="${MODEL_ID}" TARGET_DIR="${TARGET_DIR}" python3 -c '
import os
from huggingface_hub import snapshot_download
model_id = os.environ.get("VLLM_MODEL_ID", "microsoft/Phi-3-mini-4k-instruct")
target = os.environ.get("TARGET_DIR", "/tmp/phi3")
print(f"HF snapshot_download: {model_id} -> {target}")
snapshot_download(
    repo_id=model_id,
    local_dir=target,
    local_dir_use_symlinks=False,
    ignore_patterns=["*.msgpack", "*.h5", "*.mlmodel", "tf_model*", "*.onnx", "*.tflite"]
)
print("vLLM model snapshot ready.")
' 

  echo "==> vLLM HF snapshot contents (first 10):"
  ls -la "${TARGET_DIR}" | head -12
else
  # Ollama path (original)
  MODEL="phi3:mini"
  echo "    Ollama: pulling ${MODEL} (Ollama blob layout, ~2.2GB)"

  docker run --rm \
    -v "${MODEL_DIR}:/root/.ollama" \
    -e OLLAMA_MODELS=/root/.ollama/models \
    ollama/ollama:latest \
    ollama pull "${MODEL}"

  echo "==> Ollama model downloaded. Contents:"
  du -sh "${MODEL_DIR}"
  find "${MODEL_DIR}" -type f | head -20
fi

# Checksum (best effort)
(cd "${MODEL_DIR}" && find . -type f -exec sha256sum {} + > ../models.sha256 2>/dev/null || true)
echo "==> Model checksums written to ${STAGING_DIR}/models.sha256"
