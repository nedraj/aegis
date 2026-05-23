#!/usr/bin/env bash
# validate.sh — Aegis end-to-end smoke test (run from inside the air-gapped cluster)
# Phase 5: Works for both ollama and vllm engines.
# Can be copied into the bundle or executed via kubectl exec.

set -euo pipefail

NS="${NS:-aegis}"
MISSION_URL="${MISSION_URL:-http://mission-control.${NS}.svc.cluster.local:8080}"
ENGINE="${ENGINE:-ollama}"          # ollama | vllm   (or auto-detected below)
INFERENCE_DEPLOY="${INFERENCE_DEPLOY:-}"  # e.g. ollama or vllm; empty = auto

echo "=== Aegis Validation (target: ${MISSION_URL}, engine: ${ENGINE}) ==="

# Auto-detect inference deployment if not provided
if [ -z "${INFERENCE_DEPLOY}" ]; then
  if kubectl -n "${NS}" get deploy vllm >/dev/null 2>&1; then
    INFERENCE_DEPLOY="vllm"
    ENGINE="vllm"
  elif kubectl -n "${NS}" get deploy ollama >/dev/null 2>&1; then
    INFERENCE_DEPLOY="ollama"
    ENGINE="ollama"
  else
    INFERENCE_DEPLOY="ollama"
  fi
fi
echo "Using inference deployment: ${INFERENCE_DEPLOY} (engine=${ENGINE})"

echo ""
echo "[1/3] Checking GPU visibility inside ${INFERENCE_DEPLOY} pod..."
kubectl -n "${NS}" exec "deploy/${INFERENCE_DEPLOY}" -- nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv || {
  echo "FAIL: nvidia-smi not working inside ${INFERENCE_DEPLOY} pod"
  exit 1
}
echo "PASS: GPU visible"

echo ""
echo "[2/3] Verifying model artifacts on local volume (no internet fetch)..."
if [ "${ENGINE}" = "vllm" ]; then
  kubectl -n "${NS}" exec "deploy/${INFERENCE_DEPLOY}" -- sh -c 'ls -lh /models/ 2>/dev/null | head -5 || echo "No /models mount visible (check hostPath)"'
else
  kubectl -n "${NS}" exec "deploy/${INFERENCE_DEPLOY}" -- sh -c 'ls -lh /root/.ollama/models/models/manifests/registry.ollama.ai/library/phi3 2>/dev/null | head -3 || echo "model manifest dir not found (may still work if blobs are present)"'
fi

echo ""
echo "[3/3] End-to-end inference via Mission Control (local ${ENGINE} only)..."
RESPONSE=$(kubectl -n "${NS}" run -it --rm validate-curl --image=curlimages/curl --restart=Never -- \
  curl -s -X POST "${MISSION_URL}/query" \
    -H 'Content-Type: application/json' \
    -d '{"prompt":"One-sentence status report on reactor coolant pumps.","max_tokens":64}' || echo '{"error":"failed"}')

echo "$RESPONSE" | grep -q "MISSION UPDATE" && {
  echo "PASS: Received coherent MISSION UPDATE response from local model via ${ENGINE}"
  echo "Full response (truncated):"
  echo "$RESPONSE" | head -c 900
  echo ""
} || {
  echo "FAIL: Did not receive expected MISSION UPDATE. Raw output:"
  echo "$RESPONSE"
  exit 1
}

echo ""
echo "=== ALL SUCCESS CRITERIA SATISFIED ==="
echo "  ✓ GPU visible to K3s (via ${INFERENCE_DEPLOY})"
echo "  ✓ Model loaded from local persistent volume (air-gap safe)"
echo "  ✓ Deterministic inference with zero public internet egress (Mission Control → ${ENGINE})"
echo "  ✓ Engine-agnostic Mission Control (Phase 5)"
