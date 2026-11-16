# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# Linterpol JVM: a JRE plus JVM linters, kept out of the lean image so its users don't carry a JRE.
# Same lanes and run contract as lean. See APPENDIX#jvm-variant.

# --- Base (multi-arch Temurin JRE, digest-pinned) + ktlint download. ---
# ktlint is a self-executing fat JAR (pure bytecode), so fetch it once on $BUILDPLATFORM and COPY the
# one jar in. Its sh preamble defeats `unzip -t`, so integrity is run-it-and-assert.
FROM --platform=$BUILDPLATFORM eclipse-temurin:25.0.3_9-jre@sha256:7c1c6297dc3a3ff947922f3ab14ecd326e29083b9edaa8dbff3b94fef1688311 AS ktlint-dl
# linter: tool: ktlint | lints: Kotlin | repo: https://github.com/ktlint/ktlint
# renovate: datasource=github-releases depName=ktlint/ktlint
ARG KTLINT_VERSION=1.8.0
ADD https://github.com/ktlint/ktlint/releases/download/${KTLINT_VERSION}/ktlint /usr/local/bin/ktlint
# `--version` never loads the Kotlin parser, so also lint a file with one known finding. ktlint exits
# 1 on a finding and on a crash alike, so the grep is the check.
RUN set -eux; \
    chmod 0755 /usr/local/bin/ktlint; \
    ktlint --version >/tmp/ktlint.version 2>&1; \
    grep -qF "ktlint version ${KTLINT_VERSION}" /tmp/ktlint.version; \
    printf 'fun probe() = 1;\n' >/tmp/Probe.kt; \
    ktlint /tmp/Probe.kt >/tmp/ktlint.out 2>&1 || true; \
    grep -qF '(standard:no-semi)' /tmp/ktlint.out

# --- detekt download, checked through its wrapper. ---
# Same fetch-once pattern as ktlint. A plain jar, so images/jvm/detekt.sh launches it.
FROM --platform=$BUILDPLATFORM eclipse-temurin:25.0.3_9-jre@sha256:7c1c6297dc3a3ff947922f3ab14ecd326e29083b9edaa8dbff3b94fef1688311 AS detekt-dl
# linter: tool: detekt | lints: Kotlin (code smells) | repo: https://github.com/detekt/detekt
# renovate: datasource=github-releases depName=detekt/detekt
ARG DETEKT_VERSION=v1.23.8
ADD https://github.com/detekt/detekt/releases/download/${DETEKT_VERSION}/detekt-cli-${DETEKT_VERSION#v}-all.jar /opt/detekt/detekt-cli.jar
COPY --chmod=0755 images/jvm/detekt.sh /usr/local/bin/detekt
# URL downloads land as 0600, and `ADD --chmod` would lock the new folder too, so chmod here.
# Then the same parser check as ktlint-dl, through the wrapper.
RUN set -eux; \
    chmod 0644 /opt/detekt/detekt-cli.jar; \
    detekt --version >/tmp/detekt.version; \
    grep -qxF "${DETEKT_VERSION#v}" /tmp/detekt.version; \
    printf 'fun probe() {\n}\n' >/tmp/Probe.kt; \
    detekt --input /tmp/Probe.kt --max-issues 1 >/tmp/detekt.out; \
    grep -qF '[EmptyFunctionBlock]' /tmp/detekt.out

# --- Assembled image ---
FROM eclipse-temurin:25.0.3_9-jre@sha256:7c1c6297dc3a3ff947922f3ab14ecd326e29083b9edaa8dbff3b94fef1688311

# Lane 2 downloads, fetched and checked in the -dl stages above (arch-independent jars).
COPY --from=ktlint-dl /usr/local/bin/ktlint /usr/local/bin/ktlint
COPY --from=detekt-dl /opt/detekt/detekt-cli.jar /opt/detekt/detekt-cli.jar
COPY --from=detekt-dl /usr/local/bin/detekt /usr/local/bin/detekt

# Same run contract as lean: non-root, from /work, no entrypoint. Tools only read the mount.
RUN useradd --create-home --uid 10001 lint
USER 10001
WORKDIR /work

# Temurin's ENTRYPOINT imports CA certs and would wrap the tool's args. The linters only read local
# files, so clear it and `docker run <img> <tool> <args>` works like lean.
ENTRYPOINT []

# No args -> self-check (proves the tools start). Override with the tool you want:
#   docker run --rm -v "$PWD:/work:ro" linterpol-jvm:local ktlint --relative
CMD ["sh", "-c", "java -version && ktlint --version && detekt --version"]
