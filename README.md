# Linterpol

[![Build & Publish](https://github.com/LahaLuhem/linterpol/actions/workflows/build_and_push.yml/badge.svg?branch=main)](https://github.com/LahaLuhem/linterpol/actions/workflows/build_and_push.yml)
[![Test](https://github.com/LahaLuhem/linterpol/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/LahaLuhem/linterpol/actions/workflows/test.yml)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/LahaLuhem/linterpol/pulls)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![GitHub issues](https://img.shields.io/github/issues/LahaLuhem/linterpol.svg)](https://github.com/LahaLuhem/linterpol/issues)
[![GitHub closed issues](https://img.shields.io/github/issues-closed/LahaLuhem/linterpol.svg)](https://github.com/LahaLuhem/linterpol/issues?q=is%3Aissue+is%3Aclosed)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/LahaLuhem/linterpol.svg)](https://github.com/LahaLuhem/linterpol/pulls)
[![GitHub closed pull requests](https://img.shields.io/github/issues-pr-closed/LahaLuhem/linterpol.svg)](https://github.com/LahaLuhem/linterpol/pulls?q=is%3Apr+is%3Aclosed)

One small, multi-arch Docker image with the CLI linters I reuse across my repos. Lint any
checkout with `docker run`, no installing tools by hand.

```bash
docker pull ghcr.io/lahaluhem/linterpol:latest
```

Published to GHCR for both `linux/amd64` and `linux/arm64`, so it runs native on Apple
Silicon and on the usual x86 CI runners.

## What's inside

hadolint, actionlint, shellcheck, ruff, and container-structure-test. Full list with versions in
[LINTERS.md](./LINTERS.md).

## Use

Mount your checkout read-only at `/work` and point a tool at it:

```bash
img=ghcr.io/lahaluhem/linterpol:latest
docker run --rm -v "$PWD:/work:ro" "$img" hadolint Dockerfile
docker run --rm -v "$PWD:/work:ro" "$img" shellcheck scripts/*.sh
docker run --rm -v "$PWD:/work:ro" "$img" sh -c 'actionlint .github/workflows/*.yml'
docker run --rm -v "$PWD:/work:ro" "$img" ruff check .
```

Run it with no args and it self-checks, printing all five tool versions.

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
./scripts/build.sh          # builds linterpol:local for your host arch, then prints tool versions
```

Then swap `linterpol:local` in for the `ghcr.io/...` tag above.

## Architecture

Two lanes, picked by how a tool ships:

- **Lane 1, static binaries** (Go/Rust/Haskell): one build stage per tool, then `COPY` the
  binary into the final image. Tiny and natively multi-arch. Most modern linters land here.
- **Lane 2, package-manager tools** (npm/pip/apt): a separate install block in the
  `Dockerfile`.

Adding a linter touches just its lane, plus a row in [LINTERS.md](./LINTERS.md), where the
steps live.

<details>
<summary>Why not super-linter or MegaLinter?</summary>

Both are solid, but they're amd64-only today (super-linter's arm64 PR is still a draft,
MegaLinter's arm64 issue is open) and both run multi-GB, so on Apple Silicon they fall back
to emulation. This image is a handful of static binaries: natively multi-arch and tiny.
MegaLinter is also AGPL-3.0, which I'd rather not take on. The catch is that I curate the
linter list myself, but that's the whole point here.

</details>

## Roadmap

First multi-arch publish is done. Next is a republish that adds container-structure-test; from
there it's mostly keeping the tool set current (Renovate handles the bumps) and adding tools as I
reach for them in other repos.
