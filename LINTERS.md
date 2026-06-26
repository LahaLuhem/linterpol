# Bundled linters

The canonical list of what's in the image. One row per tool. Keep it in sync with the
`Dockerfile` (the `FROM`/`COPY` lines for Lane 1, the install block for Lane 2).

| Tool | Version | Lane | Lints | Upstream image |
| --- | --- | --- | --- | --- |
| [hadolint](https://github.com/hadolint/hadolint) | v2.14.0 | 1 (static) | Dockerfiles | `hadolint/hadolint:v2.14.0-alpine` |
| [actionlint](https://github.com/rhysd/actionlint) | 1.7.12 | 1 (static) | GitHub Actions workflows | `rhysd/actionlint:1.7.12` |
| [shellcheck](https://github.com/koalaman/shellcheck) | v0.11.0 | 1 (static) | shell scripts | `koalaman/shellcheck:v0.11.0` |

> actionlint also runs shellcheck on `run:` blocks on its own, since shellcheck is on
> PATH in the same image.

## Adding a linter

**Lane 1 (a static Go/Rust/Haskell binary with an official image)** is the cheap path:

1. Add a stage: `FROM <official-image>:<tag> AS <name>`
2. Add a copy: `COPY --from=<name> <path-in-image> /usr/local/bin/<name>`
3. Add a row to the table above.

Confirm the upstream image ships both `linux/arm64` and `linux/amd64` first, so the
combined image stays multi-arch:

```bash
docker manifest inspect <official-image>:<tag> | grep -i architecture
```

**Lane 2 (npm/pip/apt tool)** goes in the install block in the `Dockerfile`, then a row
above. If Lane 2 ever grows to many heterogeneous tools, that's the cue to switch its
runner to [pre-commit](https://pre-commit.com).
