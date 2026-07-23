# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
#
# Linterpol .NET: the .NET-stack lint variant. Published to ghcr.io/lahaluhem/linterpol-dotnet:latest
# by build_and_push.yml; built locally as linterpol-dotnet:local by ./scripts/build.sh.
#
# A sibling of the lean image, not a superset: the .NET runtime + C# linters only, so lean's
# consumers don't carry a runtime they don't need. Same lanes and run contract as lean; the new
# thing is the .NET base. CSharpier is file-level and read-only (`csharpier check` reports the diff,
# never writes); there is deliberately no SDK or build/restore/.sln tooling. See APPENDIX#dotnet-variant.

# --- Base (SDK, to install the tool) + CSharpier. ---
# CSharpier ships only as a NuGet `dotnet tool`. Its launcher shim is arch-specific but the payload
# DLLs are architecture-independent IL, so install once on the build-host arch (--platform=
# $BUILDPLATFORM, no QEMU) with the SDK, copy the net10.0 payload into the runtime-only final image,
# and run it via a tiny `dotnet`-host wrapper (below) instead of the arch-specific shim. No
# checksums.txt, but `dotnet tool install` validates the package signature and running the DLL
# asserts the version. The ARG is the version source (Renovate bumps it). See APPENDIX#dotnet-variant.
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

# CSharpier's net10.0 payload (architecture-independent IL) plus the wrapper that runs it through the
# dotnet host, both assembled and verified in the csharpier-dl stage above.
COPY --from=csharpier-dl /opt/csharpier             /opt/csharpier
COPY --from=csharpier-dl /usr/local/bin/csharpier   /usr/local/bin/csharpier

# Non-root user; same run contract as lean (non-root lint, /work, no entrypoint). Tools only read
# the mount. Unlike the jvm image's Temurin base, the .NET runtime sets no ENTRYPOINT to clear.
RUN useradd --create-home --uid 10001 lint
USER lint
WORKDIR /work

# No args -> self-check (prove the tools run). Override with the tool you want:
#   docker run --rm -v "$PWD:/work:ro" linterpol-dotnet:local csharpier check .
CMD ["sh", "-c", "dotnet --info && csharpier --version"]
