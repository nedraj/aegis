#!/usr/bin/env bash
# mirror-images.sh
# Pulls the required container images and exports them as tarballs for air-gap transfer.
# Run this from a machine with Docker + internet (the "staging" workstation).

set -euo pipefail

STAGING_DIR="${1:-./staging}"
IMAGES_DIR="${STAGING_DIR}/images"

mkdir -p "${IMAGES_DIR}"

IMAGES=(
  # Pinned versions recommended for reproducibility in air-gap bundles.
  # Update these when you validate new releases.
  "ollama/ollama:v0.1.42"                    # or latest stable you have tested
  "vllm/vllm-openai:v0.5.0"                # or latest stable you have tested
  "ghcr.io/project-zot/zot:v2.0.0"         # or latest stable
  "nvcr.io/nvidia/k8s-device-plugin:v0.15.0"
)

echo "==> Mirroring images for Aegis air-gap bundle..."
for img in "${IMAGES[@]}"; do
  safe_name=$(echo "$img" | tr '/:' '_')
  out="${IMAGES_DIR}/${safe_name}.tar.gz"
  echo "  Pulling ${img}..."
  docker pull "${img}"
  echo "  Saving to ${out}..."
  docker save "${img}" | gzip > "${out}"
  sha256sum "${out}" > "${out}.sha256"
done

echo "==> All images exported to ${IMAGES_DIR}"
ls -lh "${IMAGES_DIR}"

# Generate a simple image manifest with digests for reproducibility tracking
MANIFEST="${IMAGES_DIR}/images-manifest.txt"
echo "# Aegis Image Manifest - $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MANIFEST"
echo "# Format: image|digest|tar.gz" >> "$MANIFEST"
for img in "${IMAGES[@]}"; do
  safe_name=$(echo "$img" | tr '/:' '_')
  tarfile="${IMAGES_DIR}/${safe_name}.tar.gz"
  if [ -f "$tarfile" ]; then
    digest=$(sha256sum "$tarfile" | cut -d' ' -f1)
    echo "${img}|sha256:${digest}|${safe_name}.tar.gz" >> "$MANIFEST"
  fi
done
echo "==> Image manifest written to ${MANIFEST}"
