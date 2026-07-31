# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
#
# Linterpol JVM: the JVM-stack lint variant. Published to ghcr.io/lahaluhem/linterpol-jvm:latest by
# build_and_push.yml; built locally as linterpol-jvm:local by ./scripts/build.sh.
#
# A sibling of the lean image, not a superset: a JRE + JVM linters only, so lean's consumers don't
# carry a JRE. Same lanes and run contract as lean; the new thing is the base. See APPENDIX#jvm-variant.

# --- Base (multi-arch Temurin JRE, digest-pinned) + ktlint download. ---
# ktlint is a self-executing fat JAR (pure bytecode), so fetch it once on $BUILDPLATFORM and COPY the
# one jar in. Its sh preamble defeats `unzip -t`, so integrity is run-it-and-assert. See APPENDIX#jvm-variant.
FROM --platform=$BUILDPLATFORM eclipse-temurin:25.0.3_9-jre@sha256:7ea65de6187ad8fbcc0ad155950c38664a7371148bb3ccf1ec1e1b286b44ad08 AS ktlint-dl
# linter: tool: ktlint | lane: 2 | lints: Kotlin | repo: https://github.com/ktlint/ktlint
# renovate: datasource=github-releases depName=ktlint/ktlint
ARG KTLINT_VERSION=1.8.0
ADD https://github.com/ktlint/ktlint/releases/download/${KTLINT_VERSION}/ktlint /usr/local/bin/ktlint
RUN set -eux; \
    chmod 0755 /usr/local/bin/ktlint; \
    ktlint --version >/tmp/ktlint.version 2>&1; \
    grep -qF "ktlint version ${KTLINT_VERSION}" /tmp/ktlint.version

# --- Assembled image ---
FROM eclipse-temurin:25.0.3_9-jre@sha256:7ea65de6187ad8fbcc0ad155950c38664a7371148bb3ccf1ec1e1b286b44ad08

# Lane 2 downloaded artifact, fetched/verified in the ktlint-dl stage above (arch-independent jar).
COPY --from=ktlint-dl /usr/local/bin/ktlint /usr/local/bin/ktlint

# Non-root user; same run contract as lean (non-root lint, /work, no entrypoint). Tools only read
# the mount.
RUN useradd --create-home --uid 10001 lint
USER lint
WORKDIR /work

# Temurin sets a CA-cert-importer ENTRYPOINT that would wrap the tool args; clear it so
# `docker run <img> <tool> <args>` matches lean. ktlint lints local files, so the import isn't needed.
ENTRYPOINT []

# No args -> self-check (prove the tools run). Override with the tool you want:
#   docker run --rm -v "$PWD:/work:ro" linterpol-jvm:local ktlint --relative
CMD ["sh", "-c", "java -version && ktlint --version"]
