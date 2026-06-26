# ci-tools (working name)

A small, multi-arch Docker image bundling the CLI linters I use across my repos, so a
checkout can be linted with `docker run` instead of everyone installing the tools by hand.

> **Status:** staged locally, not published yet. Name, branding, and the published
> registry path are still TODO. Built and used as the local tag `ci-tools:local`.

## What's inside

hadolint, actionlint, shellcheck. Full list with versions: [LINTERS.md](./LINTERS.md).

## Build

```bash
./build.sh          # builds ci-tools:local for the host arch, then prints tool versions
```

## Use

Lint a checkout by mounting it read-only at `/work`:

```bash
docker run --rm -v "$PWD:/work:ro" ci-tools:local hadolint Dockerfile
docker run --rm -v "$PWD:/work:ro" ci-tools:local shellcheck scripts/*.sh
docker run --rm -v "$PWD:/work:ro" ci-tools:local sh -c 'actionlint .github/workflows/*.yml'
```

No args runs a self-check that prints all three tool versions.

The image runs as a non-root user (`lint`), so it reads world-readable repo files (the
normal case) and never writes to the mount.

## Architecture

Two lanes, picked by how a tool is distributed:

- **Lane 1, static binaries** (Go/Rust/Haskell): one build stage per tool, `COPY` the
  binary into the final image. Tiny and natively multi-arch. Most modern linters fit here.
- **Lane 2, package-manager tools** (npm/pip/apt): a separate install block in the
  `Dockerfile`.

Adding a linter touches only its lane, plus a row in [LINTERS.md](./LINTERS.md), which has
the steps.

<details>
<summary>Why not super-linter or MegaLinter?</summary>

Both are good, but amd64-only today (super-linter's arm64 PR is still a draft; MegaLinter's
arm64 issue is open), and both are multi-GB. On Apple Silicon they run under emulation.
This image is a handful of static binaries, so it's natively multi-arch and tiny.
MegaLinter is also AGPL-3.0, which I'd rather not take on. The tradeoff is that I curate
the linter list myself, which is the whole point here.

</details>

## Roadmap

- Publish multi-arch (`linux/amd64` + `linux/arm64`) to a registry.
- Pin upstreams by digest and let Renovate bump them.
- Pick a real name and write proper docs.
