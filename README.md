# Linterpol

[![Build & Publish](https://github.com/LahaLuhem/linterpol/actions/workflows/build_and_push.yml/badge.svg?branch=main)](https://github.com/LahaLuhem/linterpol/actions/workflows/build_and_push.yml)
[![Test](https://github.com/LahaLuhem/linterpol/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/LahaLuhem/linterpol/actions/workflows/test.yml)
[![OCI compliant](https://img.shields.io/badge/OCI-compliant-2496ED)](./APPENDIX.md#oci-metadata)
![multi-arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2496ED)
[![ghcr.io](https://img.shields.io/badge/ghcr.io-lahaluhem%2Flinterpol-2496ED?logo=docker&logoColor=white)](https://github.com/LahaLuhem/linterpol/pkgs/container/linterpol)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/LahaLuhem/linterpol/pulls)

Small, multi-arch, OCI-compliant images with the CLI linters I reuse across my repos. Lint any
checkout with one `docker run`, no installing tools by hand. They're plain OCI images, so they run
anywhere that speaks OCI, not just Docker: Podman, containerd, nerdctl, your CI runner. Three images:

- **`linterpol`** (lean): static-binary linters for the common stack (hadolint, shellcheck, ...).
- **`linterpol-jvm`**: a JRE plus JVM-language linters (ktlint). Kept separate so the lean image
  stays JVM-free for the repos that pin it and don't lint JVM languages.
- **`linterpol-dotnet`**: the .NET runtime plus C# linters (CSharpier). Separate for the same
  reason, so the lean image stays .NET-free.

```bash
docker pull ghcr.io/lahaluhem/linterpol:latest
docker pull ghcr.io/lahaluhem/linterpol-jvm:latest
docker pull ghcr.io/lahaluhem/linterpol-dotnet:latest
```

All three publish to GHCR as OCI images for `linux/amd64` and `linux/arm64`, so they run native on
Apple Silicon and on the usual x86 CI runners. In CI, pin a version rather than `latest` (see
[Versions](#versions)).

## What's inside

- **`linterpol`**: hadolint, actionlint, shellcheck, ruff,
  biome (JSON/JSONC plus JS/TS/CSS/GraphQL), buf (Protobuf), swiftlint, rumdl, ryl,
  container-structure-test, and shellspec (shell BDD tests).
- **`linterpol-jvm`**: ktlint (Kotlin), with more JVM-language linters to come.
- **`linterpol-dotnet`**: CSharpier (C#), a file-level formatter run in its read-only `check` mode.

Full list with versions in [LINTERS.md](./LINTERS.md).

## Use

Mount your checkout read-only at `/work` and point a tool at it:

```bash
img=ghcr.io/lahaluhem/linterpol:latest
docker run --rm -v "$PWD:/work:ro" "$img" hadolint Dockerfile
docker run --rm -v "$PWD:/work:ro" "$img" shellcheck scripts/*.sh
docker run --rm -v "$PWD:/work:ro" "$img" sh -c 'actionlint .github/workflows/*.yml'
docker run --rm -v "$PWD:/work:ro" "$img" ruff check .
docker run --rm -v "$PWD:/work:ro" "$img" biome check .
docker run --rm -v "$PWD:/work:ro" "$img" buf lint
docker run --rm -v "$PWD:/work:ro" "$img" ryl .
docker run --rm -v "$PWD:/work:ro" "$img" swiftlint lint
docker run --rm -v "$PWD:/work:ro" "$img" shellspec
```

The jvm image follows the same contract (non-root `lint`, `/work`, no entrypoint), so swap the tag
and run its tools:

```bash
jvm=ghcr.io/lahaluhem/linterpol-jvm:latest
docker run --rm -v "$PWD:/work:ro" "$jvm" ktlint
```

Same contract again for the dotnet image. CSharpier is a formatter, so in CI use its read-only
`check` mode: it reports unformatted files and exits non-zero, and never writes to your mount.

```bash
dotnet=ghcr.io/lahaluhem/linterpol-dotnet:latest
docker run --rm -v "$PWD:/work:ro" "$dotnet" csharpier check .
```

Run any image with no args and it self-checks, printing its tools' versions (the lean image's full set;
the jvm image's `java` + `ktlint`; the dotnet image's `dotnet` + `csharpier`).

It runs as a non-root user (`lint`), so it reads world-readable repo files (the usual case)
and never writes to your mount.

Three tools need more than pointing them at the mount: `container-structure-test` inspects a built
image, `shellspec` runs a `spec/` suite, and `buf breaking` needs a baseline it can reach. Each is
written up in [LINTERS.md#caveats](./LINTERS.md#caveats).

## Versions

Every release publishes four tags per image, all pointing at the same multi-arch index:

| Tag | Moves? | Reach for it when |
|---|---|---|
| `1.2.3` | never | you're in CI. Pin this, or its digest, and nothing shifts under you. |
| `1.2` | on each patch | you want to track a minor line |
| `1` | on each minor or patch | you want to track a major line |
| `latest` | every release | you're trying things out locally |

Only a release publishes. Pushes to `main` build-validate both arches without pushing anything, so
`latest` means "latest release", not "tip of main".

### What a bump level means

The levels describe what happened to **this image's interface**: which images exist, which tools are
on `PATH`, and the runtime contract (non-root `lint`, `/work`, no entrypoint, both arches).

| Bump | The interface | Typical triggers |
|---|---|---|
| **major** | **breaks.** Your existing `docker run` needs changing. | a tool removed or replaced; an image renamed or dropped; the `/work` or non-root `lint` contract changed; an entrypoint added; an arch dropped |
| **minor** | **grows**, or a tool's own rules shift under you. | a tool added; a new variant image; an arch added; a bundled tool's own **major** bump (stricter defaults, renamed config keys) |
| **patch** | **unchanged.** | tool patch and minor bumps (most of Renovate's traffic); base-image digest bumps; build internals; docs |

> **No level promises your lint run still passes.** Even a patch can carry a rule addition that flags
> code which was clean yesterday. That's the nature of bundling linters: what the levels promise is
> that on a patch or minor, your existing `docker run …` invocation keeps working unchanged.

That's why a bundled tool's own major bump is only a **minor** here. ktlint 1.x → 2.x may fail your
build with stricter rules, but it doesn't change how you invoke this image, and upstream majors are
frequent enough that spending our major on them would leave nothing to signal a real contract break.

Releases are cut by hand from the **Release** workflow (Actions → Release → Run workflow), picking
the bump level. Why it works this way, including why the level isn't inferred from commit messages,
is in [APPENDIX.md#versioning-releases](./APPENDIX.md#versioning-releases).

> GHCR can't enforce tag immutability, so `1.2.3` is immutable by convention here rather than by
> guarantee. Pin the digest if you want the stronger promise.

## Build it yourself

You don't need to, but if you want the image from source:

```bash
./scripts/build.sh          # builds every variant (linterpol, linterpol-jvm, linterpol-dotnet) + self-checks
./scripts/build.sh jvm      # or just one variant
```

Then swap `linterpol:local` (or the `-jvm` / `-dotnet` variant) in for the `ghcr.io/...` tag above.

## Architecture

Each image is one `images/<variant>/Dockerfile`. The lean `linterpol`, the `linterpol-jvm` sibling,
and the `linterpol-dotnet` sibling are independent: the JVM and .NET images each carry a runtime the
lean image's consumers shouldn't have to pull. Another heavy-runtime stack would be one more sibling.
See [APPENDIX.md#jvm-variant](./APPENDIX.md#jvm-variant) and
[APPENDIX.md#dotnet-variant](./APPENDIX.md#dotnet-variant).

Within an image, tools come in two lanes, picked by how a tool ships:

- **Lane 1, static binaries** (Go/Rust/Haskell): one build stage per tool, then `COPY` the
  binary into the final image. Tiny and natively multi-arch. Most modern linters land here.
- **Lane 2, tools with no usable static image**: an npm/pip/apt/NuGet install block, or a single
  prebuilt binary downloaded and verified (swiftlint, container-structure-test, rumdl, ktlint, csharpier).

Adding a linter touches just its lane, plus a row in [LINTERS.md](./LINTERS.md), where the
steps live.

<details>
<summary>Why not super-linter or MegaLinter?</summary>

Both are solid, but they're amd64-only today (super-linter's arm64 PR is still a draft,
MegaLinter's arm64 issue is open) and both run multi-GB, so on Apple Silicon they fall back
to emulation. The lean image is a handful of static binaries: natively multi-arch and tiny.
MegaLinter is also AGPL-3.0, which I'd rather not take on. The catch is that I curate the
linter list myself, but that's the whole point here.

</details>

## Roadmap

All three images publish multi-arch; `linterpol-dotnet` (CSharpier) is the newest sibling. More
JVM-language linters (detekt and others) can still follow in the jvm image. Beyond that it's keeping
the tool set current (Renovate handles the bumps) and adding tools, or new stack siblings, as I reach
for them in other repos.

On registry hygiene: releases carry immutable version tags, so every published digest stays anchored
by a tag ([#15](https://github.com/LahaLuhem/linterpol/issues/15)). The weekly prune
([`cleanup-packages.yml`](.github/workflows/cleanup-packages.yml)) is now just "keep the last 10
tagged releases, drop the rest", with no age window to guess at.
