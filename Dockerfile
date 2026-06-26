# syntax=docker/dockerfile:1
#
# Linterpol: a small, multi-arch combined image of CI lint tools.
# Staged locally, not yet published. Built by ./scripts/build.sh as linterpol:local.
#
# Architecture: two lanes, chosen by how a tool is distributed.
#   Lane 1  static-binary linters (Go/Rust/Haskell): one stage per tool, COPY the
#           binary out. Cheap, tiny, natively multi-arch. Most modern linters fit here.
#   Lane 2  package-manager linters (npm/pip/apt): a clearly separated install block.
# Adding a linter touches only its lane (plus a row in LINTERS.md). Nothing else changes.

# --- Lane 1: static-binary linters. Version + digest pinned at the FROM line. ---
# The tag is the readable version; the digest makes the build reproducible. Dependabot
# (.github/dependabot.yml) bumps both. Each tag is a multi-arch index, so the digest
# pin stays multi-arch.
#
# The `# linter:` line above each FROM feeds LINTERS.md (run ./scripts/gen-linters.sh): version
# and image come from the FROM, the `lints:` / `repo:` fields from the annotation.
# linter: lints: Dockerfiles | repo: https://github.com/hadolint/hadolint
FROM hadolint/hadolint:v2.14.0-alpine@sha256:7aba693c1442eb31c0b015c129697cb3b6cb7da589d85c7562f9deb435a6657c AS hadolint
# linter: lints: GitHub Actions workflows | repo: https://github.com/rhysd/actionlint
FROM rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 AS actionlint
# linter: lints: shell scripts | repo: https://github.com/koalaman/shellcheck
FROM koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d AS shellcheck

# --- Assembled image ---
FROM debian:stable-slim@sha256:ee12ffb55625b99d62837a72f037d9b2f18fd0c787a89c2b9a4f09666c48776c

LABEL org.opencontainers.image.title="Linterpol" \
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
#   docker run --rm -v "$PWD:/work:ro" linterpol:local hadolint Dockerfile
CMD ["sh", "-c", "hadolint --version && actionlint --version && shellcheck --version"]
