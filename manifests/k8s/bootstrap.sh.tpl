#!/usr/bin/env bash
# bootstrap.sh
# Executed on the target VM (either by cloud-init or manually after scp'ing the bundle).
# Idempotent as much as possible. Designed for Ubuntu 22.04 + K3s + NVIDIA T4.

set -euo pipefail

BUNDLE_ROOT="${BUNDLE_ROOT:-/opt/aegis}"
MANIFEST_DIR="${BUNDLE_ROOT}/manifests"
IMAGE_DIR="${BUNDLE_ROOT}/images"
MODEL_DIR="${BUNDLE_ROOT}/models"
K3S_IMAGES_DIR="/var/lib/rancher/k3s/agent/images"

echo "=== Aegis Air-Gap Bootstrap (profile: {{ .ProfileName }}) ==="
echo "Bundle root: ${BUNDLE_ROOT}"

# 1. Ensure directories
mkdir -p "${K3S_IMAGES_DIR}" "${BUNDLE_ROOT}/logs"

# 2. Import all pre-staged container images directly into containerd (k3s runtime)
echo "==> Importing container images into containerd..."
for tar in "${IMAGE_DIR}"/*.tar.gz; do
  [ -f "$tar" ] || continue
  echo "    ctr import $tar"
  gzip -dc "$tar" | ctr -n k8s.io image import - || echo "    (import may have warnings, continuing)"
done

# 3. Make sure K3s is running
if ! systemctl is-active --quiet k3s; then
  echo "==> Starting K3s..."
  systemctl enable --now k3s || true
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl cluster-info || true

# 4. Install / update NVIDIA device plugin (already in manifests)
echo "==> Applying NVIDIA device plugin..."
kubectl apply -f "${MANIFEST_DIR}/nvidia-device-plugin.yaml" || true

# 5. Deploy the Aegis stack
echo "==> Applying Aegis workloads (namespace, {{ .InferenceEngine }}, mission-control, zot)..."
kubectl apply -f "${MANIFEST_DIR}/namespace.yaml"
{{- if eq .InferenceEngine "vllm" }}
kubectl apply -f "${MANIFEST_DIR}/vllm-deployment.yaml"
{{- else }}
kubectl apply -f "${MANIFEST_DIR}/ollama-deployment.yaml"
{{- end }}
kubectl apply -f "${MANIFEST_DIR}/mission-control-deployment.yaml"
kubectl apply -f "${MANIFEST_DIR}/zot-registry.yaml" || true

# 6. Wait for GPU to appear and pods to be ready (best effort)
echo "==> Waiting for GPU resource and pods..."
sleep 8
kubectl -n aegis get pods -o wide || true

# 7. Model population note
if [ -d "${MODEL_DIR}" ] && [ "$(ls -A ${MODEL_DIR})" ]; then
  if [ "{{ .InferenceEngine }}" = "vllm" ]; then
    echo "==> Models present in ${MODEL_DIR}. They will be used by the vLLM pod via hostPath /models (HF snapshot layout expected)."
  else
    echo "==> Models present in ${MODEL_DIR}. They will be used by the Ollama pod via hostPath."
    echo "    (Ollama container will see them at /root/.ollama/models)"
  fi
fi

echo ""
echo "=== Bootstrap complete ==="
echo "Validate inside the cluster:"
echo "  kubectl -n aegis exec -it deploy/mission-control -- curl -s http://mission-control:8080/health"
echo "  kubectl -n aegis exec -it deploy/mission-control -- curl -s -X POST http://mission-control:8080/query -d '{\"prompt\":\"Status report on all comms arrays.\"}' | jq ."
echo ""
echo "To prove air-gap: after NAT removal, repeat the /query call."
echo "Success criteria: nvidia-smi inside a pod + coherent MISSION UPDATE response with zero public egress."
