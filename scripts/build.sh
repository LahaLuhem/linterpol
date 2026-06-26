#!/usr/bin/env bash
#
# Build the Linterpol lint image locally (host arch).
#
#   ./scripts/build.sh         build + self-check  linterpol:local
#
# Multi-arch builds and a registry push come when this repo is published. For now
# consumers (e.g. another repo's test script) run against this local tag.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

image="${LINTERPOL_IMAGE:-linterpol:local}"

echo "building $image (host arch)"
docker buildx build --load -t "$image" .

echo "self-check:"
docker run --rm "$image"
