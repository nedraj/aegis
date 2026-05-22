#!/usr/bin/env bash
# prepare-models.sh
# Downloads the Phi-3 weights via Ollama into a local directory that can be tar'ed
# into the bundle. The resulting directory is mounted into the Ollama container at runtime.

set -euo pipefail

STAGING_DIR="${1:-./staging}"
MODEL_DIR="${STAGING_DIR}/models"

mkdir -p "${MODEL_DIR}"

MODEL="phi3:mini"

echo "==> Preparing Phi-3 mini model for air-gap bundle (this will download ~2.2 GB)..."
echo "    Target: ${MODEL_DIR}"

# Use a throwaway container so we don't pollute the host's ollama install (if any)
docker run --rm \
  -v "${MODEL_DIR}:/root/.ollama" \
  -e OLLAMA_MODELS=/root/.ollama/models \
  ollama/ollama:latest \
  ollama pull "${MODEL}"

echo "==> Model downloaded. Contents:"
du -sh "${MODEL_DIR}"
find "${MODEL_DIR}" -type f | head -20

# Create a checksum manifest of the model files
(cd "${MODEL_DIR}" && find . -type f -exec sha256sum {} + > ../models.sha256)
echo "==> Model checksums written to ${STAGING_DIR}/models.sha256"
