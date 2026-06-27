# Bundled linters

The canonical list of what's in the image, one row per tool.

> **Generated.** The table below is produced from the `Dockerfile` by
> [`gen-linters.sh`](./scripts/gen-linters.sh), which CI runs on any `Dockerfile` change
> (`regen-linters.yml`) and commits back. Don't hand-edit or commit it: change the `Dockerfile`
> (the `FROM` line and its `# linter:` annotation); run `./scripts/gen-linters.sh` locally to preview.

<!-- linters:start -->
| Tool | Version | Lane | Lints | Upstream image |
| --- | --- | --- | --- | --- |
| [hadolint](https://github.com/hadolint/hadolint) | v2.14.0-alpine | 1 (static) | Dockerfiles | `hadolint/hadolint:v2.14.0-alpine` |
| [actionlint](https://github.com/rhysd/actionlint) | 1.7.12 | 1 (static) | GitHub Actions workflows | `rhysd/actionlint:1.7.12` |
| [shellcheck](https://github.com/koalaman/shellcheck) | v0.11.0 | 1 (static) | shell scripts | `koalaman/shellcheck:v0.11.0` |
| [ruff](https://github.com/astral-sh/ruff) | 0.15.20 | 1 (static) | Python (lint + format) | `ghcr.io/astral-sh/ruff:0.15.20` |
| [container-structure-test](https://github.com/GoogleContainerTools/container-structure-test) | v1.22.1 | 2 | container image structure & metadata | n/a |
| [swiftlint](https://github.com/realm/SwiftLint) | 0.65.0 | 2 | Swift | n/a |
<!-- linters:end -->

> actionlint also runs shellcheck on `run:` blocks on its own, since shellcheck is on
> PATH in the same image.

## Adding a linter

**Lane 1 (a static Go/Rust/Haskell binary with an official image)** is the cheap path:

1. Add the stage with its annotation: a `# linter: lints: <what> | repo: <url>` line, then
   `FROM <official-image>:<tag>@<digest> AS <name>`.
2. Add a copy: `COPY --from=<name> <path-in-image> /usr/local/bin/<name>`.
3. That's it. CI regenerates the table above on the `Dockerfile` change; run `./scripts/gen-linters.sh` locally to preview.

Confirm the upstream image ships both `linux/arm64` and `linux/amd64` first, so the
combined image stays multi-arch:

```bash
docker manifest inspect <official-image>:<tag> | grep -i architecture
```

**Lane 2 (npm/pip/apt tool)** goes in the install block in the `Dockerfile`, with a
self-contained annotation that carries its own name and version:

```dockerfile
# linter: tool: <name> | version: <x.y.z> | lane: 2 | lints: <what> | repo: <url>
```

CI then regenerates the table (run `./scripts/gen-linters.sh` locally to preview). If Lane 2 ever grows to many heterogeneous tools, that's the
cue to switch its runner to [pre-commit](https://pre-commit.com).
