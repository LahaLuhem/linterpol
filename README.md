# Linterpol

[![Build & Publish](https://github.com/LahaLuhem/linterpol/actions/workflows/build_and_push.yml/badge.svg?branch=main)](https://github.com/LahaLuhem/linterpol/actions/workflows/build_and_push.yml)
[![Test](https://github.com/LahaLuhem/linterpol/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/LahaLuhem/linterpol/actions/workflows/test.yml)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/LahaLuhem/linterpol/pulls)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![GitHub issues](https://img.shields.io/github/issues/LahaLuhem/linterpol.svg)](https://github.com/LahaLuhem/linterpol/issues)
[![GitHub closed issues](https://img.shields.io/github/issues-closed/LahaLuhem/linterpol.svg)](https://github.com/LahaLuhem/linterpol/issues?q=is%3Aissue+is%3Aclosed)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/LahaLuhem/linterpol.svg)](https://github.com/LahaLuhem/linterpol/pulls)
[![GitHub closed pull requests](https://img.shields.io/github/issues-pr-closed/LahaLuhem/linterpol.svg)](https://github.com/LahaLuhem/linterpol/pulls?q=is%3Apr+is%3Aclosed)

Small, multi-arch Docker images with the CLI linters I reuse across my repos. Lint any
checkout with `docker run`, no installing tools by hand. Two images:

- **`linterpol`** (lean): static-binary linters for the common stack (hadolint, shellcheck, ...).
- **`linterpol-jvm`**: a JRE plus JVM-language linters (ktlint). Kept separate so the lean image
  stays JVM-free for the repos that pin it and don't lint JVM languages.

```bash
docker pull ghcr.io/lahaluhem/linterpol:latest
docker pull ghcr.io/lahaluhem/linterpol-jvm:latest
```

Both are published to GHCR for `linux/amd64` and `linux/arm64`, so they run native on Apple
Silicon and on the usual x86 CI runners.

## What's inside

- **`linterpol`**: hadolint, actionlint, shellcheck, ruff, swiftlint, and container-structure-test.
- **`linterpol-jvm`**: ktlint (Kotlin), with more JVM-language linters to come.

Full list with versions in [LINTERS.md](./LINTERS.md).

## Use

Mount your checkout read-only at `/work` and point a tool at it:

```bash
img=ghcr.io/lahaluhem/linterpol:latest
docker run --rm -v "$PWD:/work:ro" "$img" hadolint Dockerfile
docker run --rm -v "$PWD:/work:ro" "$img" shellcheck scripts/*.sh
docker run --rm -v "$PWD:/work:ro" "$img" sh -c 'actionlint .github/workflows/*.yml'
docker run --rm -v "$PWD:/work:ro" "$img" ruff check .
docker run --rm -v "$PWD:/work:ro" "$img" swiftlint lint
```

The jvm image follows the same contract (non-root `lint`, `/work`, no entrypoint), so swap the tag
and run its tools:

```bash
jvm=ghcr.io/lahaluhem/linterpol-jvm:latest
docker run --rm -v "$PWD:/work:ro" "$jvm" ktlint
```

Run either image with no args and it self-checks, printing its tools' versions (the lean image's
six; the jvm image's `java` + `ktlint`).

It runs as a non-root user (`lint`), so it reads world-readable repo files (the usual case)
and never writes to your mount.

`container-structure-test` is the odd one out: it inspects a built image rather than files in your
checkout, so instead of a `:ro` source mount it needs the Docker socket mounted (or an image tarball
via `--driver tar`). See the
[upstream docs](https://github.com/GoogleContainerTools/container-structure-test) for the spec
format and drivers.

## Build it yourself

You don't need to, but if you want the image from source:

```bash
./scripts/build.sh          # builds every variant (linterpol:local, linterpol-jvm:local) + self-checks
./scripts/build.sh jvm      # or just one variant
```

Then swap `linterpol:local` (or `linterpol-jvm:local`) in for the `ghcr.io/...` tag above.

## Architecture

Each image is one `images/<variant>/Dockerfile`. The lean `linterpol` and the `linterpol-jvm`
sibling are independent: the JVM image carries a JRE that the lean image's consumers shouldn't have
to pull. A new heavy-runtime stack (say `linterpol-dotnet`) would be another sibling. See
[APPENDIX.md#jvm-variant](./APPENDIX.md#jvm-variant).

Within an image, tools come in two lanes, picked by how a tool ships:

- **Lane 1, static binaries** (Go/Rust/Haskell): one build stage per tool, then `COPY` the
  binary into the final image. Tiny and natively multi-arch. Most modern linters land here.
- **Lane 2, tools with no usable static image**: an npm/pip/apt install block, or a single
  prebuilt binary downloaded and verified (swiftlint, container-structure-test, ktlint).

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

The lean image publishes multi-arch. The `linterpol-jvm` sibling (ktlint) is the newest piece;
detekt and more JVM-language linters can follow in that image. Beyond that it's keeping the tool set
current (Renovate handles the bumps) and adding tools, or new stack siblings, as I reach for them in
other repos.
