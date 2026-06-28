# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
#
# Linterpol .NET: the .NET-stack lint variant, published to ghcr.io/lahaluhem/linterpol-dotnet:latest
# by build_and_push.yml; built locally as linterpol-dotnet:local by ./scripts/build.sh.
#
# This is a *sibling* of the lean linterpol image, not a superset: it carries the .NET runtime + C#
# linters only (no hadolint/actionlint/shellcheck/ruff/...). The .NET runtime base is heavy relative
# to the lean image, and lean's consumers don't lint C#, so that cost is isolated to this separate
# tag. A repo that lints both its Dockerfiles/workflows and its C# runs both images.
#
# Lanes mean the same thing as in the lean image (images/lean/Dockerfile): how a tool is
# distributed. CSharpier is a Lane-2 install (a NuGet `dotnet tool`), the same way swiftlint / ktlint
# / container-structure-test are Lane-2 elsewhere. What's new here is the *base*: a .NET runtime,
# which is the whole reason this is a separate image.
#
# CSharpier is read-only by contract: `csharpier check <path>` parses and reprints C# in memory and
# only reports the diff (non-zero exit), it never writes the mount. There is deliberately NO build /
# restore / .sln tooling here (and no SDK in the final image): this image lints a read-only mount
# like every other linterpol image. See APPENDIX#dotnet-variant.

# --- Base + CSharpier install. ---
# CSharpier ships only as a NuGet `dotnet tool` (no native binary), so it needs the .NET runtime.
# A dotnet tool's launcher shim is arch-specific, but the tool's payload DLLs are architecture-
# independent IL (they live under tools/<tfm>/any/). So we install ONCE on the build host's native
# arch (--platform=$BUILDPLATFORM, no QEMU) with the SDK, copy just the net10.0 payload (it targets
# Microsoft.NETCore.App 10.0.0, an exact match for the runtime base below), and further down put our
# own tiny wrapper on PATH that runs the DLL via the dotnet host instead of the arch-specific shim.
# The only emulated step left in a cross-arch build is the one-line useradd, same as the lean image.
#
# Verification is "run it and assert the pinned version": CSharpier ships no checksums.txt, but
# `dotnet tool install` validates the package signature and then running the DLL proves integrity and
# the version in one step (the net10.0 payload's runtimeconfig sets rollForward=Major, so it also
# runs on a newer runtime). The ARG is the single source of version truth: gen-linters.sh reads it
# for LINTERS.md and Renovate bumps it (custom.regex manager, .github/renovate.jsonc). See
# APPENDIX#dotnet-variant.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0@sha256:ea8bde36c11b6e7eec2656d0e59101d4462f6bd630730f2c8201ed0572b295d5 AS csharpier-dl
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1
# linter: tool: csharpier | lane: 2 | lints: C# | repo: https://github.com/belav/csharpier
# renovate: datasource=nuget depName=CSharpier
ARG CSHARPIER_VERSION=1.3.0
RUN set -eux; \
    dotnet tool install --tool-path /tmp/tool CSharpier --version "${CSHARPIER_VERSION}"; \
    cp -r "/tmp/tool/.store/csharpier/${CSHARPIER_VERSION}/csharpier/${CSHARPIER_VERSION}/tools/net10.0/any" /opt/csharpier; \
    test "$(dotnet /opt/csharpier/CSharpier.dll --version)" = "${CSHARPIER_VERSION}"; \
    printf '#!/bin/sh\nexec dotnet /opt/csharpier/CSharpier.dll "$@"\n' > /usr/local/bin/csharpier; \
    chmod 0755 /usr/local/bin/csharpier

# --- Assembled image ---
FROM mcr.microsoft.com/dotnet/runtime:10.0@sha256:6a40d375e9c8432fcf4adebae05d7e0a276e9a90dd01174df6709a090771bebc

LABEL org.opencontainers.image.title="Linterpol .NET" \
      org.opencontainers.image.description=".NET-stack CI lint tools: CSharpier." \
      org.opencontainers.image.licenses="MIT"

# CSharpier's net10.0 payload (architecture-independent IL) plus the wrapper that runs it through the
# dotnet host, both assembled and verified in the csharpier-dl stage above.
COPY --from=csharpier-dl /opt/csharpier             /opt/csharpier
COPY --from=csharpier-dl /usr/local/bin/csharpier   /usr/local/bin/csharpier

# Lint tools only read the mounted sources, so run unprivileged. Same contract as the lean image
# (non-root lint user, /work workdir, no entrypoint) so consumers invoke every image identically.
# Unlike the Temurin-based jvm image, the .NET runtime base sets no ENTRYPOINT, so none to clear.
RUN useradd --create-home --uid 10001 lint
USER lint
WORKDIR /work

# No args -> self-check (prove the tools run). Override with the tool you want:
#   docker run --rm -v "$PWD:/work:ro" linterpol-dotnet:local csharpier check .
CMD ["sh", "-c", "dotnet --info && csharpier --version"]
