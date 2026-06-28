#!/usr/bin/env bash
#
# Build Linterpol lint image(s) locally (host arch) and self-check each.
#
#   ./scripts/build.sh             build + self-check every variant under images/*/
#   ./scripts/build.sh jvm         build + self-check just the jvm image
#   ./scripts/build.sh lean jvm    ... or any subset
#
# Variant <v> builds images/<v>/Dockerfile and tags it linterpol-<v>:local, except lean which
# has no suffix (linterpol:local). CI calls this with the one variant it needs; the multi-arch
# registry push is build_and_push.yml's job, not this script's.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Local tag for a variant: lean is the unsuffixed default image, others get a -<v> suffix.
tag_for() {
  case "$1" in
    lean) printf 'linterpol:local' ;;
    *)    printf 'linterpol-%s:local' "$1" ;;
  esac
}

# With args, build exactly those variants; with none, every variant that has a Dockerfile.
variants=()
if [ "$#" -gt 0 ]; then
  variants=("$@")
else
  for d in images/*/; do
    [ -f "${d}Dockerfile" ] && variants+=("$(basename "$d")")
  done
fi
if [ "${#variants[@]}" -eq 0 ]; then
  echo "error: no variant to build (pass a name, or add images/<variant>/Dockerfile)" >&2
  exit 2
fi

for v in "${variants[@]}"; do
  dockerfile="images/$v/Dockerfile"
  if [ ! -f "$dockerfile" ]; then
    echo "error: unknown variant '$v' (no $dockerfile)" >&2
    exit 2
  fi
  image="$(tag_for "$v")"
  echo "==> building $image from $dockerfile (host arch)"
  docker buildx build --load -t "$image" -f "$dockerfile" .
  echo "==> self-check $image:"
  docker run --rm "$image"
done
