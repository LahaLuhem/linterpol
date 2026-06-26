# syntax=docker/dockerfile:1
#
# ci-tools: a small, multi-arch combined image of CI lint tools.
# Staged locally, not yet published. Built by ./build.sh as ci-tools:local.
#
# Architecture: two lanes, chosen by how a tool is distributed.
#   Lane 1  static-binary linters (Go/Rust/Haskell): one stage per tool, COPY the
#           binary out. Cheap, tiny, natively multi-arch. Most modern linters fit here.
#   Lane 2  package-manager linters (npm/pip/apt): a clearly separated install block.
# Adding a linter touches only its lane (plus a row in LINTERS.md). Nothing else changes.

# --- Lane 1: static-binary linters. Version is pinned at the FROM line. ---
# Pinned by tag for now; switch to digest + Renovate when this repo is published.
FROM hadolint/hadolint:v2.14.0-alpine AS hadolint
FROM rhysd/actionlint:1.7.12          AS actionlint
FROM koalaman/shellcheck:v0.11.0      AS shellcheck

# --- Assembled image ---
FROM debian:stable-slim

LABEL org.opencontainers.image.title="ci-tools" \
      org.opencontainers.image.description="Combined CI lint tools: hadolint, actionlint, shellcheck." \
      org.opencontainers.image.licenses="MIT"

# Lane 1 binaries. All three are statically linked, so they run on any base.
COPY --from=hadolint   /bin/hadolint             /usr/local/bin/hadolint
COPY --from=actionlint /usr/local/bin/actionlint /usr/local/bin/actionlint
COPY --from=shellcheck /bin/shellcheck           /usr/local/bin/shellcheck

# --- Lane 2: package-manager linters. Empty for now; obvious home when needed. ---
# Example:
#   RUN apt-get update \
#     && apt-get install -y --no-install-recommends <pkg> \
#     && rm -rf /var/lib/apt/lists/*

# Lint tools only read the mounted sources, so run unprivileged.
RUN useradd --create-home --uid 10001 lint
USER lint
WORKDIR /work

# No args -> self-check (prove the tools run). Override with the tool you want:
#   docker run --rm -v "$PWD:/work:ro" ci-tools:local hadolint Dockerfile
CMD ["sh", "-c", "hadolint --version && actionlint --version && shellcheck --version"]
