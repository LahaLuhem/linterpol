# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
#
# Linterpol: a small, multi-arch combined image of CI lint tools.
# Published to ghcr.io/lahaluhem/linterpol:latest (multi-arch) by build_and_push.yml; built
# locally as linterpol:local by ./scripts/build.sh.
#
# Architecture: two lanes, chosen by how a tool is distributed.
#   Lane 1  static-binary linters (Go/Rust/Haskell) with an official multi-arch image: one
#           stage per tool, COPY the binary out. Cheap, tiny, natively multi-arch.
#   Lane 2  tools with no usable multi-arch image: an apt/pip/npm install block, or (for a
#           single prebuilt binary, e.g. container-structure-test) a download-and-verify
#           stage we COPY the binary out of.
# Adding a linter touches only its lane (plus a row in LINTERS.md). Nothing else changes.

# --- Lane 1: static-binary linters. Version + digest pinned at the FROM line. ---
# The tag is the readable version; the digest makes the build reproducible. Renovate
# (.github/renovate.jsonc) bumps both. Each tag is a multi-arch index, so the digest
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
# linter: lints: Python (lint + format) | repo: https://github.com/astral-sh/ruff
FROM ghcr.io/astral-sh/ruff:0.15.20@sha256:03cc33c3f7f31ba53040fb1f1b8744a03a777033650f543d689d1ed98298f14b AS ruff
# biome is a whole web-stack toolchain; we add it for JSON/JSONC but it lints+formats JS/TS/CSS/
# GraphQL too, so those come for free (see APPENDIX#json-biome). Static binary, official multi-arch
# image -> a plain Lane-1 COPY like ruff above.
# linter: lints: JSON / JSONC, JavaScript / TypeScript (incl. JSX), CSS, GraphQL | repo: https://github.com/biomejs/biome
FROM ghcr.io/biomejs/biome:2.5.1@sha256:14977977824e1a38e526083999c28c6cdeb6b120af22b16b3e596d8f5df6ea49 AS biome

# --- Lane 2: tools with no usable multi-arch image. ---
# container-structure-test ships no usable multi-arch image (gcr.io/gcp-runtimes is amd64-only
# and last built 2023), so fetch the per-arch release binary in this throwaway stage, verify it
# against the release's own checksums.txt, and COPY just the binary into the final image below.
# The ARG is the single source of version truth: gen-linters.sh reads it for LINTERS.md and
# Renovate bumps it (custom.regex manager, .github/renovate.jsonc). See
# APPENDIX#two-lane-architecture.
FROM debian:stable-slim@sha256:328d16499860ae6cb9b345e2e4cebca08c2a36e4f7278482c7bd1f39d71e5bfd AS cst-dl
# linter: tool: container-structure-test | lane: 2 | lints: container image structure & metadata | repo: https://github.com/GoogleContainerTools/container-structure-test
# renovate: datasource=github-releases depName=GoogleContainerTools/container-structure-test
ARG CST_VERSION=v1.22.1
ARG TARGETARCH
ADD https://github.com/GoogleContainerTools/container-structure-test/releases/download/${CST_VERSION}/container-structure-test-linux-${TARGETARCH} /usr/local/bin/container-structure-test
ADD https://github.com/GoogleContainerTools/container-structure-test/releases/download/${CST_VERSION}/checksums.txt /tmp/checksums.txt
RUN set -eux; \
    sed -n "s|^\([0-9a-f]\{64\}\)  container-structure-test-linux-${TARGETARCH}\$|\1  /usr/local/bin/container-structure-test|p" /tmp/checksums.txt > /tmp/cst.sha256; \
    test -s /tmp/cst.sha256; \
    sha256sum -c /tmp/cst.sha256; \
    chmod 0755 /usr/local/bin/container-structure-test

# SwiftLint ships no lightweight image (ghcr.io/realm/swiftlint carries the full Swift runtime,
# ~185 MB), but its Linux release zip bundles a fully static `swiftlint-static` that runs on bare
# debian, so it's a Lane-2 download like c-s-t above: fetch the per-arch zip, extract just that
# binary, COPY it into the final image. No upstream checksums.txt covers these zips, so integrity
# rests on the pinned version fetched over HTTPS from the immutable release tag plus a zip CRC check
# (unzip -t); that keeps a Renovate version bump a one-liner. The static build has no SourceKit, so a
# few SourceKit-only rules are skipped with a warning while the SwiftSyntax majority run. See
# APPENDIX#two-lane-architecture.
FROM debian:stable-slim@sha256:328d16499860ae6cb9b345e2e4cebca08c2a36e4f7278482c7bd1f39d71e5bfd AS swiftlint-dl
# linter: tool: swiftlint | lane: 2 | lints: Swift | repo: https://github.com/realm/SwiftLint
# renovate: datasource=github-releases depName=realm/SwiftLint
ARG SWIFTLINT_VERSION=0.65.0
ARG TARGETARCH
ADD https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_${TARGETARCH}.zip /tmp/swiftlint.zip
# unzip lives only in this throwaway stage; a Debian point-release version pin is brittle and
# Renovate can't track an apt pin, so DL3008 is intentionally ignored here.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends unzip; \
    rm -rf /var/lib/apt/lists/*; \
    unzip -t /tmp/swiftlint.zip; \
    unzip -p /tmp/swiftlint.zip swiftlint-static > /usr/local/bin/swiftlint; \
    chmod 0755 /usr/local/bin/swiftlint

# rumdl has no official image (it's distributed as per-arch release tarballs), so it's a Lane-2
# download like c-s-t and swiftlint above: fetch the per-arch musl tarball (fully static, runs on
# bare debian), verify it against the release's own per-asset .sha256, extract the single `rumdl`
# binary, then COPY it into the final image. Unlike c-s-t/swiftlint, rumdl names its assets by Rust
# target triple (aarch64/x86_64), not Docker's arm64/amd64, so map TARGETARCH and fetch with curl in
# this throwaway stage (ADD can't remap the arch into its URL). The ARG is the single source of
# version truth: gen-linters.sh reads it for LINTERS.md and Renovate bumps it (custom.regex manager,
# .github/renovate.jsonc). See APPENDIX#two-lane-architecture.
FROM debian:stable-slim@sha256:328d16499860ae6cb9b345e2e4cebca08c2a36e4f7278482c7bd1f39d71e5bfd AS rumdl-dl
# linter: tool: rumdl | lane: 2 | lints: Markdown | repo: https://github.com/rvben/rumdl
# renovate: datasource=github-releases depName=rvben/rumdl
ARG RUMDL_VERSION=v0.2.26
ARG TARGETARCH
# curl + ca-certificates live only in this throwaway stage; a Debian point-release pin is brittle and
# Renovate can't track an apt pin, so DL3008 is intentionally ignored here.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    case "${TARGETARCH}" in \
      amd64) rarch=x86_64 ;; \
      arm64) rarch=aarch64 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    asset="rumdl-${RUMDL_VERSION}-${rarch}-unknown-linux-musl.tar.gz"; \
    base="https://github.com/rvben/rumdl/releases/download/${RUMDL_VERSION}"; \
    curl -fsSL -o "/tmp/${asset}" "${base}/${asset}"; \
    curl -fsSL -o "/tmp/${asset}.sha256" "${base}/${asset}.sha256"; \
    checksum="$(awk '{print $1}' "/tmp/${asset}.sha256")"; \
    test -n "${checksum}"; \
    echo "${checksum}  /tmp/${asset}" > /tmp/rumdl.sha256; \
    sha256sum -c /tmp/rumdl.sha256; \
    tar -xzf "/tmp/${asset}" -C /usr/local/bin rumdl; \
    chmod 0755 /usr/local/bin/rumdl

# ryl (a yamllint reimplementation in Rust) has no official image either, distributed as per-arch
# musl release tarballs like rumdl, so it's another Lane-2 download. The one difference from rumdl:
# ryl publishes a single SHA256SUMS file for the whole release (c-s-t's model) rather than a per-asset
# .sha256, so pull the one matching line out of it to verify. Assets are named by Rust target triple
# (aarch64/x86_64), so map TARGETARCH and fetch with curl in this throwaway stage. The ARG is the
# single source of version truth: gen-linters.sh reads it for LINTERS.md and Renovate bumps it
# (custom.regex manager, .github/renovate.jsonc). See APPENDIX#yaml-ryl and #two-lane-architecture.
FROM debian:stable-slim@sha256:328d16499860ae6cb9b345e2e4cebca08c2a36e4f7278482c7bd1f39d71e5bfd AS ryl-dl
# linter: tool: ryl | lane: 2 | lints: YAML | repo: https://github.com/owenlamont/ryl
# renovate: datasource=github-releases depName=owenlamont/ryl
ARG RYL_VERSION=v0.21.0
ARG TARGETARCH
# curl + ca-certificates live only in this throwaway stage; a Debian point-release pin is brittle and
# Renovate can't track an apt pin, so DL3008 is intentionally ignored here.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    case "${TARGETARCH}" in \
      amd64) rarch=x86_64 ;; \
      arm64) rarch=aarch64 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    asset="ryl-${rarch}-unknown-linux-musl.tar.gz"; \
    base="https://github.com/owenlamont/ryl/releases/download/${RYL_VERSION}"; \
    curl -fsSL -o "/tmp/${asset}" "${base}/${asset}"; \
    curl -fsSL -o /tmp/SHA256SUMS "${base}/SHA256SUMS"; \
    checksum="$(awk -v a="${asset}" '$2==a {print $1}' /tmp/SHA256SUMS)"; \
    test -n "${checksum}"; \
    echo "${checksum}  /tmp/${asset}" > /tmp/ryl.sha256; \
    sha256sum -c /tmp/ryl.sha256; \
    tar -xzf "/tmp/${asset}" -C /usr/local/bin ryl; \
    chmod 0755 /usr/local/bin/ryl

# --- Assembled image ---
FROM debian:stable-slim@sha256:328d16499860ae6cb9b345e2e4cebca08c2a36e4f7278482c7bd1f39d71e5bfd

# Lane 1 binaries. All statically linked, so they run on any base.
COPY --from=hadolint   /bin/hadolint             /usr/local/bin/hadolint
COPY --from=actionlint /usr/local/bin/actionlint /usr/local/bin/actionlint
COPY --from=shellcheck /bin/shellcheck           /usr/local/bin/shellcheck
COPY --from=ruff       /ruff                      /usr/local/bin/ruff
COPY --from=biome      /usr/local/bin/biome       /usr/local/bin/biome

# Lane 2 downloaded binaries, extracted/verified in the *-dl stages above (also statically linked).
COPY --from=cst-dl      /usr/local/bin/container-structure-test /usr/local/bin/container-structure-test
COPY --from=swiftlint-dl /usr/local/bin/swiftlint               /usr/local/bin/swiftlint
COPY --from=rumdl-dl     /usr/local/bin/rumdl                    /usr/local/bin/rumdl
COPY --from=ryl-dl       /usr/local/bin/ryl                      /usr/local/bin/ryl

# --- Lane 2: package-manager installs would go here, in the final image. None yet. Example:
#   RUN apt-get update \
#     && apt-get install -y --no-install-recommends <pkg> \
#     && rm -rf /var/lib/apt/lists/*

# Lint tools only read the mounted sources, so run unprivileged.
RUN useradd --create-home --uid 10001 lint
USER lint
WORKDIR /work

# No args -> self-check (prove the tools run). Override with the tool you want:
#   docker run --rm -v "$PWD:/work:ro" linterpol:local hadolint Dockerfile
CMD ["sh", "-c", "hadolint --version && actionlint --version && shellcheck --version && ruff --version && biome --version && swiftlint version && rumdl --version && ryl --version && container-structure-test version"]
