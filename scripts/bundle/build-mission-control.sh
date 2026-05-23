#!/usr/bin/env bash
# build-mission-control.sh
#
# Builds the custom Mission Control image and exports it as a tarball
# so it can be included in the Aegis bundle.
#
# This is required because every profile references `aegis/mission-control:latest`,
# but the image is never published publicly.

set -euo pipefail

STAGING_DIR="${1:-./staging}"
IMAGES_DIR="${STAGING_DIR}/images"

mkdir -p "${IMAGES_DIR}"

IMAGE_NAME="aegis/mission-control:latest"
OUTPUT_FILE="${IMAGES_DIR}/aegis-mission-control.tar.gz"

echo "==> Building Mission Control image: ${IMAGE_NAME}"
echo "    Context: ./mission-control"

docker build \
  -t "${IMAGE_NAME}" \
  -f ./mission-control/Dockerfile \
  ./mission-control

echo "==> Saving image to ${OUTPUT_FILE}..."
docker save "${IMAGE_NAME}" | gzip > "${OUTPUT_FILE}"

echo "==> Generating checksum..."
sha256sum "${OUTPUT_FILE}" > "${OUTPUT_FILE}.sha256"

echo "==> Done. Mission Control image ready for bundling:"
ls -lh "${OUTPUT_FILE}"*
