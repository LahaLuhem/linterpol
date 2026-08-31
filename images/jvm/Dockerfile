# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
#
# Linterpol JVM: the JVM-stack lint variant. Published to ghcr.io/lahaluhem/linterpol-jvm:latest by
# build_and_push.yml; built locally as linterpol-jvm:local by ./scripts/build.sh.
#
# A sibling of the lean image, not a superset: a JRE + JVM linters only, so lean's consumers don't
# carry a JRE. Same lanes and run contract as lean; the new thing is the base. See APPENDIX#jvm-variant.

# --- Base (multi-arch Temurin JRE, digest-pinned) + ktlint download. ---
# ktlint is a self-executing fat JAR (pure bytecode), so fetch it once on $BUILDPLATFORM and COPY the
# one jar in. Its sh preamble defeats `unzip -t`, so integrity is run-it-and-assert. See APPENDIX#jvm-variant.
FROM --platform=$BUILDPLATFORM eclipse-temurin:25.0.3_9-jre@sha256:7c1c6297dc3a3ff947922f3ab14ecd326e29083b9edaa8dbff3b94fef1688311 AS ktlint-dl
# linter: tool: ktlint | lane: 2 | lints: Kotlin | repo: https://github.com/ktlint/ktlint
# renovate: datasource=github-releases depName=ktlint/ktlint
ARG KTLINT_VERSION=1.8.0
ADD https://github.com/ktlint/ktlint/releases/download/${KTLINT_VERSION}/ktlint /usr/local/bin/ktlint
RUN set -eux; \
    chmod 0755 /usr/local/bin/ktlint; \
    ktlint --version >/tmp/ktlint.version 2>&1; \
    grep -qF "ktlint version ${KTLINT_VERSION}" /tmp/ktlint.version

# --- Assembled image ---
FROM eclipse-temurin:25.0.3_9-jre@sha256:7c1c6297dc3a3ff947922f3ab14ecd326e29083b9edaa8dbff3b94fef1688311

# Lane 2 downloaded artifact, fetched/verified in the ktlint-dl stage above (arch-independent jar).
COPY --from=ktlint-dl /usr/local/bin/ktlint /usr/local/bin/ktlint

# Non-root user; same run contract as lean (non-root lint, /work, no entrypoint). Tools only read
# the mount.
RUN useradd --create-home --uid 10001 lint
USER 10001
WORKDIR /work

# Temurin sets a CA-cert-importer ENTRYPOINT that would wrap the tool args; clear it so
# `docker run <img> <tool> <args>` matches lean. ktlint lints local files, so the import isn't needed.
ENTRYPOINT []

# No args -> self-check (prove the tools run). Override with the tool you want:
#   docker run --rm -v "$PWD:/work:ro" linterpol-jvm:local ktlint --relative
CMD ["sh", "-c", "java -version && ktlint --version"]
