#!/usr/bin/env bash
#
# Linterpol's test suite. CI runs this same script, so local and CI checks can't drift.
#
#   lint        gen-linters.sh --check, then the lean image's own linters over this repo
#   structure   container-structure-test each image (specs in tests/)
#   oci         the lean image builds with OCI media types (build_and_push.yml checks the pushed one)
#   all         everything above (default)
#
# Usage: scripts/test.sh [lint|structure|oci|all]
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Colour, but only on a terminal (keeps CI logs clean).
if [ -t 1 ]; then
  bold=$'\033[1m'; red=$'\033[31m'; grn=$'\033[32m'; rst=$'\033[0m'
else
  bold=''; red=''; grn=''; rst=''
fi

failures=0
section() { printf '\n%s==> %s%s\n' "$bold" "$1" "$rst"; }
ok()      { printf '%s ok %s  %s\n' "$grn" "$rst" "$1"; }
bad()     { printf '%sFAIL%s  %s\n' "$red" "$rst" "$1"; failures=$((failures + 1)); }

LINTERPOL_IMAGE='linterpol:local'
JVM_IMAGE='linterpol-jvm:local'
DOTNET_IMAGE='linterpol-dotnet:local'

need_docker() {
  command -v docker >/dev/null 2>&1 && return 0
  printf '%smissing tool:%s docker is required (start OrbStack / Docker Desktop)\n' "$red" "$rst"
  exit 2
}

# Build at most once per run. build.sh also runs each image's self-check.
lean_built='' all_built=''

ensure_lean() {
  [ -n "$lean_built" ] && return 0
  local log; log="$(mktemp)"
  section 'build lean image'
  if ./scripts/build.sh lean >"$log" 2>&1; then
    ok 'built linterpol:local'; lean_built=1; rm -f "$log"; return 0
  fi
  bad 'lean build'; tail -n 30 "$log"; rm -f "$log"; return 1
}

ensure_all() {
  [ -n "$all_built" ] && return 0
  local log; log="$(mktemp)"
  section 'build images (lean + jvm + dotnet)'
  if ./scripts/build.sh >"$log" 2>&1; then
    ok 'built all variants'; all_built=1; lean_built=1; rm -f "$log"; return 0
  fi
  bad 'image build'; tail -n 30 "$log"; rm -f "$log"; return 1
}

# The freshly built image runs the linters, so the host needs none and versions match what ships.
lint_tool() { docker run --rm -v "$repo_root:/work:ro" -w /work "$LINTERPOL_IMAGE" "$@"; }

# Tar driver, so no Docker socket. It can't run commands, and the specs don't need it to.
structure_test() {
  local image="$1" cfg="$2" td rc=0
  td="$(mktemp -d)"
  docker save "$image" -o "$td/image.tar"
  chmod 0644 "$td/image.tar"
  docker run --rm -v "$td/image.tar:/img/image.tar:ro" -v "$repo_root:/work:ro" "$LINTERPOL_IMAGE" \
    container-structure-test test --driver tar -i /img/image.tar -c "/work/$cfg" || rc=$?
  rm -rf "$td"
  return "$rc"
}

run_lint() {
  need_docker
  ensure_lean || return 0

  section 'LINTERS.md is generated from the Dockerfiles'
  if ./scripts/gen-linters.sh --check; then ok 'LINTERS.md in sync'; else bad 'LINTERS.md drift (run scripts/gen-linters.sh)'; fi

  section 'hadolint (Dockerfiles)'
  if lint_tool hadolint images/*/Dockerfile; then ok 'Dockerfiles clean'; else bad 'hadolint'; fi

  section 'shellcheck (shell scripts)'
  # Every tracked script, wherever it lives, so a new one can't skip the check.
  local sh_files=() f
  while IFS= read -r f; do sh_files+=("$f"); done < <(git ls-files '*.sh')
  if lint_tool shellcheck "${sh_files[@]}"; then ok 'scripts clean'; else bad 'shellcheck'; fi

  section 'actionlint (workflows)'
  if lint_tool actionlint; then ok 'workflows clean'; else bad 'actionlint'; fi

  section 'rumdl (Markdown)'
  if lint_tool rumdl check .; then ok 'Markdown clean'; else bad 'rumdl'; fi

  section 'biome (JSON/JSONC)'
  if lint_tool biome check .; then ok 'JSON/JSONC clean'; else bad 'biome'; fi

  section 'ryl (YAML)'
  if lint_tool ryl .; then ok 'YAML clean'; else bad 'ryl'; fi
}

run_structure() {
  need_docker
  ensure_all || return 0

  section 'container-structure-test: lean'
  if structure_test "$LINTERPOL_IMAGE" tests/image-structure.yaml; then ok 'lean structure'; else bad 'lean structure'; fi

  section 'container-structure-test: jvm (via lean image)'
  if structure_test "$JVM_IMAGE" tests/image-structure-jvm.yaml; then ok 'jvm structure'; else bad 'jvm structure'; fi

  section 'container-structure-test: dotnet (via lean image)'
  if structure_test "$DOTNET_IMAGE" tests/image-structure-dotnet.yaml; then ok 'dotnet structure'; else bad 'dotnet structure'; fi
}

run_oci() {
  need_docker
  local builder='linterpol-ocicheck' dest log
  dest="$(mktemp -d)"; log="$(mktemp)"

  section 'build lean to an OCI layout (host arch)'
  docker buildx rm "$builder" >/dev/null 2>&1 || true
  if ! docker buildx create --name "$builder" --driver docker-container >/dev/null 2>&1; then
    bad 'could not create a docker-container builder'; rm -rf "$dest" "$log"; return 0
  fi
  if docker buildx build --builder "$builder" --provenance=false \
       --output "type=oci,oci-mediatypes=true,tar=false,dest=$dest" \
       -f images/lean/Dockerfile . >"$log" 2>&1; then
    ok 'built OCI layout'
    section 'assert OCI media types'
    if ./scripts/assert_oci_layout.sh "$dest"; then ok 'OCI media types'; else bad 'OCI media types'; fi
  else
    bad 'OCI layout build'; tail -n 30 "$log"
  fi
  docker buildx rm "$builder" >/dev/null 2>&1 || true
  rm -rf "$dest" "$log"
}

main() {
  local cmd="${1:-all}"
  case "$cmd" in
    lint)      run_lint ;;
    structure) run_structure ;;
    oci)       run_oci ;;
    all)       run_lint; run_structure; run_oci ;;
    *) printf 'usage: %s [lint|structure|oci|all]\n' "$0"; exit 2 ;;
  esac

  echo
  if [ "$failures" -gt 0 ]; then
    printf '%s%d check(s) failed%s\n' "$red" "$failures" "$rst"; exit 1
  fi
  printf '%sall checks passed%s\n' "$grn" "$rst"
}

main "$@"
