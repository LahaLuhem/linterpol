#!/usr/bin/env bash
#
# Build the ci-tools lint image locally (host arch).
#
#   ./build.sh         build + self-check  ci-tools:local
#
# Multi-arch builds and a registry push come when this repo is published. For now
# consumers (e.g. another repo's test script) run against this local tag.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

image="${CI_TOOLS_IMAGE:-ci-tools:local}"

echo "building $image (host arch)"
docker buildx build --load -t "$image" .

echo "self-check:"
docker run --rm "$image"
