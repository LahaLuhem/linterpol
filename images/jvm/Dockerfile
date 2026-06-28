# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
#
# Linterpol JVM: the JVM-stack lint variant, published to ghcr.io/lahaluhem/linterpol-jvm:latest
# by build_and_push.yml; built locally as linterpol-jvm:local by ./scripts/build.sh.
#
# This is a *sibling* of the lean linterpol image, not a superset: it carries a JRE + JVM linters
# only (no hadolint/actionlint/shellcheck/ruff/...). A JRE is heavy (the Temurin base alone, ~340 MB,
# rivals the entire lean image), and lean's consumers don't lint JVM languages, so that cost is
# isolated to this separate tag. A repo that lints both its Dockerfiles/workflows and its Kotlin runs
# both images.
#
# Lanes mean the same thing as in the lean image (images/lean/Dockerfile): how a tool is
# distributed. ktlint is a Lane-2 downloaded artifact, like swiftlint / container-structure-test
# there. What's new here is the *base*: a JVM runtime, which is the whole reason this is a
# separate image.

# --- Base + ktlint download. ---
# Base is a multi-arch Temurin JRE, digest-pinned like any FROM (Renovate bumps it). 21-jre is the
# conservative current LTS and ships linux/amd64 + linux/arm64; ktlint 1.8.0 runs on it.
#
# ktlint's release is a self-executing fat JAR (#!/bin/sh launcher + the jar), which is pure JVM
# bytecode and therefore architecture-independent. So unlike the lean image's per-arch binary
# downloads we fetch and verify it ONCE on the build host's native arch (--platform=$BUILDPLATFORM,
# no QEMU) and COPY the same jar into the per-arch final image below; the only emulated step left in
# a cross-arch build is the one-line useradd, same as the lean image.
#
# Verification is "run it and assert the pinned version": the release ships no checksums.txt (so the
# container-structure-test model doesn't apply) and the #!/bin/sh preamble makes `unzip -t` warn
# (so the swiftlint CRC model doesn't either), but executing it on the JRE proves integrity and the
# version in one step and keeps a Renovate bump a one-liner. The ARG is the single source of version
# truth: gen-linters.sh reads it for LINTERS.md and Renovate bumps it (custom.regex manager,
# .github/renovate.jsonc). See APPENDIX#jvm-variant.
FROM --platform=$BUILDPLATFORM eclipse-temurin:21-jre@sha256:8ec353b20d3aab0758572236b81b967c7077c40c4d0819ce97f9a1329d684603 AS ktlint-dl
# linter: tool: ktlint | lane: 2 | lints: Kotlin | repo: https://github.com/ktlint/ktlint
# renovate: datasource=github-releases depName=ktlint/ktlint
ARG KTLINT_VERSION=1.8.0
ADD https://github.com/ktlint/ktlint/releases/download/${KTLINT_VERSION}/ktlint /usr/local/bin/ktlint
RUN set -eux; \
    chmod 0755 /usr/local/bin/ktlint; \
    ktlint --version >/tmp/ktlint.version 2>&1; \
    grep -qF "ktlint version ${KTLINT_VERSION}" /tmp/ktlint.version

# --- Assembled image ---
FROM eclipse-temurin:21-jre@sha256:8ec353b20d3aab0758572236b81b967c7077c40c4d0819ce97f9a1329d684603

LABEL org.opencontainers.image.title="Linterpol JVM" \
      org.opencontainers.image.description="JVM-stack CI lint tools: ktlint." \
      org.opencontainers.image.licenses="MIT"

# Lane 2 downloaded artifact, fetched/verified in the ktlint-dl stage above (arch-independent jar).
COPY --from=ktlint-dl /usr/local/bin/ktlint /usr/local/bin/ktlint

# Lint tools only read the mounted sources, so run unprivileged. Same contract as the lean image
# (non-root lint user, /work workdir, no entrypoint) so consumers invoke both images identically.
RUN useradd --create-home --uid 10001 lint
USER lint
WORKDIR /work

# Temurin ships an ENTRYPOINT (/__cacert_entrypoint.sh) that would wrap every `docker run <img>
# <tool> <args>`. Clear it so this image matches the lean image's contract (no entrypoint; the args
# ARE the command). ktlint lints local files, so the entrypoint's runtime CA-cert import isn't needed.
ENTRYPOINT []

# No args -> self-check (prove the tools run). Override with the tool you want:
#   docker run --rm -v "$PWD:/work:ro" linterpol-jvm:local ktlint --relative
CMD ["sh", "-c", "java -version && ktlint --version"]
