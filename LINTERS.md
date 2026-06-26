# Bundled linters

The canonical list of what's in the image, one row per tool.

> **Generated.** The table below is produced from the `Dockerfile` by
> [`gen-linters.sh`](./gen-linters.sh). Don't hand-edit it: change the `Dockerfile` (the
> `FROM` line and its `# linter:` annotation), then run `./gen-linters.sh`.

<!-- linters:start -->
| Tool | Version | Lane | Lints | Upstream image |
| --- | --- | --- | --- | --- |
| [hadolint](https://github.com/hadolint/hadolint) | v2.14.0-alpine | 1 (static) | Dockerfiles | `hadolint/hadolint:v2.14.0-alpine` |
| [actionlint](https://github.com/rhysd/actionlint) | 1.7.12 | 1 (static) | GitHub Actions workflows | `rhysd/actionlint:1.7.12` |
| [shellcheck](https://github.com/koalaman/shellcheck) | v0.11.0 | 1 (static) | shell scripts | `koalaman/shellcheck:v0.11.0` |
<!-- linters:end -->

> actionlint also runs shellcheck on `run:` blocks on its own, since shellcheck is on
> PATH in the same image.

## Adding a linter

**Lane 1 (a static Go/Rust/Haskell binary with an official image)** is the cheap path:

1. Add the stage with its annotation: a `# linter: lints: <what> | repo: <url>` line, then
   `FROM <official-image>:<tag>@<digest> AS <name>`.
2. Add a copy: `COPY --from=<name> <path-in-image> /usr/local/bin/<name>`.
3. Run `./gen-linters.sh` to refresh the table above.

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

then run `./gen-linters.sh`. If Lane 2 ever grows to many heterogeneous tools, that's the
cue to switch its runner to [pre-commit](https://pre-commit.com).
