# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
#
# Linterpol: a small, multi-arch image of CI lint tools. Published to
# ghcr.io/lahaluhem/linterpol:latest by build_and_push.yml; built locally as linterpol:local by
# ./scripts/build.sh.
#
# Two lanes, by how a tool ships: Lane 1 = a static binary COPYd from an official image; Lane 2 = no
# usable image, so a download-and-verify (or package install). See APPENDIX#two-lane-architecture.

# --- Lane 1: static-binary linters, pinned tag@digest (Renovate bumps both; the index digest
# keeps the pin multi-arch). The `# linter:` line above each FROM feeds LINTERS.md. ---
# linter: lints: Dockerfiles | repo: https://github.com/hadolint/hadolint
FROM hadolint/hadolint:v2.14.0-alpine@sha256:7aba693c1442eb31c0b015c129697cb3b6cb7da589d85c7562f9deb435a6657c AS hadolint
# linter: lints: GitHub Actions workflows | repo: https://github.com/rhysd/actionlint
FROM rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 AS actionlint
# linter: lints: shell scripts | repo: https://github.com/koalaman/shellcheck
FROM koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d AS shellcheck
# linter: lints: Python (lint + format) | repo: https://github.com/astral-sh/ruff
FROM ghcr.io/astral-sh/ruff:0.15.20@sha256:03cc33c3f7f31ba53040fb1f1b8744a03a777033650f543d689d1ed98298f14b AS ruff
# biome: added for JSON/JSONC, but it lints+formats JS/TS/CSS/GraphQL too, for free. A plain Lane-1
# static binary like ruff. See APPENDIX#json-biome.
# linter: lints: JSON / JSONC, JavaScript / TypeScript (incl. JSX), CSS, GraphQL | repo: https://github.com/biomejs/biome
FROM ghcr.io/biomejs/biome:2.5.1@sha256:14977977824e1a38e526083999c28c6cdeb6b120af22b16b3e596d8f5df6ea49 AS biome
# buf: Protobuf lint, with `breaking` and `format` along for the ride. Its git-input baseline needs a
# git binary, which this image doesn't ship: see LINTERS.md#caveats.
# linter: lints: Protocol Buffers | repo: https://github.com/bufbuild/buf
FROM bufbuild/buf:1.72.0@sha256:65bd496a89c762ad7151ca9e7d885a45dacb3671a8e8ec39738b9f844d3405ea AS buf

# --- Lane 2: no usable multi-arch image. Each pins its version in an ARG (the single source of
# truth: Renovate bumps it, gen-linters.sh reads it) and verifies its download at build. ---
# container-structure-test: no usable image (gcr.io/gcp-runtimes is amd64-only, last built 2023),
# so fetch the per-arch binary here and verify it against the release's checksums.txt.
FROM debian:stable-slim@sha256:0d97731c59efdde181e19c4a5ec22d16e9eefcb73175598b9b7bae712c7214eb AS cst-dl
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

# SwiftLint's only image carries the whole Swift runtime, so extract the static `swiftlint-static`
# from the release zip instead; no checksums.txt, hence `unzip -t`. See APPENDIX#two-lane-architecture.
FROM debian:stable-slim@sha256:0d97731c59efdde181e19c4a5ec22d16e9eefcb73175598b9b7bae712c7214eb AS swiftlint-dl
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

# rumdl: no official image, so verify the per-arch musl tarball against its .sha256. Assets are named
# by Rust target triple, so remap TARGETARCH and use curl (ADD can't remap the arch into its URL).
FROM debian:stable-slim@sha256:0d97731c59efdde181e19c4a5ec22d16e9eefcb73175598b9b7bae712c7214eb AS rumdl-dl
# linter: tool: rumdl | lane: 2 | lints: Markdown | repo: https://github.com/rvben/rumdl
# renovate: datasource=github-releases depName=rvben/rumdl
ARG RUMDL_VERSION=v0.2.26
ARG TARGETARCH
# Throwaway stage again, and Renovate can't track an apt pin, so DL3008 is ignored (see swiftlint-dl).
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

# ryl (a Rust yamllint): same shape as rumdl, except it ships one SHA256SUMS for the release rather
# than a per-asset .sha256, so pull the matching line out to verify. See APPENDIX#yaml-ryl.
FROM debian:stable-slim@sha256:0d97731c59efdde181e19c4a5ec22d16e9eefcb73175598b9b7bae712c7214eb AS ryl-dl
# linter: tool: ryl | lane: 2 | lints: YAML | repo: https://github.com/owenlamont/ryl
# renovate: datasource=github-releases depName=owenlamont/ryl
ARG RYL_VERSION=v0.21.0
ARG TARGETARCH
# Throwaway stage again, and Renovate can't track an apt pin, so DL3008 is ignored (see swiftlint-dl).
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

# shellspec: pure shell, so one arch-independent asset; no checksums.txt, hence `tar -tzf`. A tree
# (executable + lib/), not one binary, so extract the dir. See APPENDIX#shellspec-test-framework.
FROM debian:stable-slim@sha256:0d97731c59efdde181e19c4a5ec22d16e9eefcb73175598b9b7bae712c7214eb AS shellspec-dl
# linter: tool: shellspec | lane: 2 | lints: shell scripts (BDD tests) | repo: https://github.com/shellspec/shellspec
# renovate: datasource=github-releases depName=shellspec/shellspec
ARG SHELLSPEC_VERSION=0.28.1
ADD https://github.com/shellspec/shellspec/releases/download/${SHELLSPEC_VERSION}/shellspec-dist.tar.gz /tmp/shellspec-dist.tar.gz
RUN set -eux; \
    tar -tzf /tmp/shellspec-dist.tar.gz >/dev/null; \
    mkdir -p /opt; \
    tar -xzf /tmp/shellspec-dist.tar.gz -C /opt; \
    test -x /opt/shellspec/shellspec

# --- Assembled image ---
FROM debian:stable-slim@sha256:0d97731c59efdde181e19c4a5ec22d16e9eefcb73175598b9b7bae712c7214eb

# Lane 1 binaries. All statically linked, so they run on any base.
COPY --from=hadolint   /bin/hadolint             /usr/local/bin/hadolint
COPY --from=actionlint /usr/local/bin/actionlint /usr/local/bin/actionlint
COPY --from=shellcheck /bin/shellcheck           /usr/local/bin/shellcheck
COPY --from=ruff       /ruff                      /usr/local/bin/ruff
COPY --from=biome      /usr/local/bin/biome       /usr/local/bin/biome
COPY --from=buf        /usr/local/bin/buf         /usr/local/bin/buf

# Lane 2 downloaded binaries, extracted/verified in the *-dl stages above (also statically linked).
COPY --from=cst-dl      /usr/local/bin/container-structure-test /usr/local/bin/container-structure-test
COPY --from=swiftlint-dl /usr/local/bin/swiftlint               /usr/local/bin/swiftlint
COPY --from=rumdl-dl     /usr/local/bin/rumdl                    /usr/local/bin/rumdl
COPY --from=ryl-dl       /usr/local/bin/ryl                      /usr/local/bin/ryl

# shellspec is a tree, so COPY the whole dir. Its executable is symlinked onto PATH in the final RUN
# (a COPYd symlink gets dereferenced, severing it from its lib/, so make the link in the final image).
COPY --from=shellspec-dl /opt/shellspec                          /opt/shellspec

# --- Lane 2: package-manager installs would go here, in the final image. None yet. Example:
#   RUN apt-get update \
#     && apt-get install -y --no-install-recommends <pkg> \
#     && rm -rf /var/lib/apt/lists/*

# Final assembly: symlink shellspec onto PATH (a symlink keeps it tied to its lib/) and add the
# non-root user (tools only read the mount). One RUN so the two don't trip hadolint's DL3059.
RUN ln -s /opt/shellspec/shellspec /usr/local/bin/shellspec \
 && useradd --create-home --uid 10001 lint
USER lint
WORKDIR /work

# No args -> self-check (prove the tools run). Override with the tool you want:
#   docker run --rm -v "$PWD:/work:ro" linterpol:local hadolint Dockerfile
CMD ["sh", "-c", "hadolint --version && actionlint --version && shellcheck --version && ruff --version && biome --version && buf --version && swiftlint version && rumdl --version && ryl --version && container-structure-test version && shellspec --version"]
