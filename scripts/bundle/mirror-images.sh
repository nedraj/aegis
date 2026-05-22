#!/usr/bin/env bash
# mirror-images.sh
# Pulls the required container images and exports them as tarballs for air-gap transfer.
# Run this from a machine with Docker + internet (the "staging" workstation).

set -euo pipefail

STAGING_DIR="${1:-./staging}"
IMAGES_DIR="${STAGING_DIR}/images"

mkdir -p "${IMAGES_DIR}"

IMAGES=(
  "ollama/ollama:latest"
  "ghcr.io/project-zot/zot:latest"
  "nvcr.io/nvidia/k8s-device-plugin:v0.15.0"
  # Add any other images your manifests reference (pause, etc. if needed)
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
