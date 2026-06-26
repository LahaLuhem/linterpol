# AGENTS.md — `Linterpol`

Tool-agnostic brief for any coding agent (Claude Code, Copilot, Cursor, Codex, ...) working
in this repo. Claude-Code-specific guidance lives in [CLAUDE.md](./CLAUDE.md); design
rationale and rejected paths live in [`APPENDIX.md`](./APPENDIX.md) (anchor-keyed). Read this
first.

## Project goal

`Linterpol` builds and publishes one small, **multi-arch (`linux/amd64` + `linux/arm64`)**
Docker image bundling the CI lint/check tools used across the author's repos, published to
**GHCR under `ghcr.io/lahaluhem`**. The point: a checkout can be linted with `docker run`
instead of every contributor installing the tools by hand.

Bundled today: **hadolint** (Dockerfiles), **actionlint** (GitHub workflows), **shellcheck**
(shell). Planned: **container-structure-test**. Full list: [`LINTERS.md`](./LINTERS.md).

## Scope — what this repo is and is NOT

- **In scope:** building and publishing the combined tools image (the Dockerfile, the
  build/publish workflow, the bundled-tool manifest).
- **Out of scope (by design):** *how or where* the image is consumed. It is a plain OCI image:
  any CI, any runtime, run against any repo. **Do not bake in consumer-specific logic** (no
  assumptions about which repo runs it, no project-specific entrypoints).

## Stack

- **Docker Buildx** — multi-platform builds. The publish path is a **single-job** multi-arch
  build (`buildx --platform linux/amd64,linux/arm64 --push`), not a native-runner matrix: the
  image only `COPY`s prebuilt per-arch binaries, so there is no native compilation and the QEMU
  penalty is negligible. See [`APPENDIX.md#single-job-buildx`](./APPENDIX.md#single-job-buildx).
- **Two-lane architecture** — static-binary tools vs package-manager tools. See
  [`LINTERS.md`](./LINTERS.md) and [`APPENDIX.md#two-lane-architecture`](./APPENDIX.md#two-lane-architecture).
- **GitHub Actions** — `.github/workflows/` (planned: `test.yml` self-test, `build_and_push.yml` publish).
- **GHCR** — `ghcr.io/lahaluhem` (lowercase; GHCR namespaces are lowercase).
- **Dependabot** — version tracking (`.github/dependabot.yml`): the `docker` ecosystem bumps the
  digest-pinned `FROM`s, `github-actions` bumps the workflow pins. Weekly, grouped. See
  [`APPENDIX.md#digest-pins-dependabot`](./APPENDIX.md#digest-pins-dependabot).
- **Bash** — `build.sh` (local host-arch build + self-check).

## Repo layout

```
linterpol/
├── Dockerfile              two-lane combined tools image; FROMs pinned tag@digest
├── build.sh                local host-arch build + self-check (tags linterpol:local)
├── gen-linters.sh          regenerate the LINTERS.md table from the Dockerfile (+ --check)
├── .dockerignore
├── LINTERS.md              bundled-tools manifest; the table is generated from the Dockerfile
├── README.md               what it is, usage, architecture
├── APPENDIX.md             design rationale (anchor-keyed)
├── .github/
│   ├── dependabot.yml      docker + github-actions, weekly, grouped
│   └── workflows/          PLANNED: test.yml (self-test), build_and_push.yml (publish)
└── .ai/                    AGENTS.md + CLAUDE.md (symlinked at root, gitignored)
```

## Hard rules

1. **Scope is build + publish the tools image.** Don't add consumer-specific logic; consumption
   is portable and out of scope.
2. **Registry is `ghcr.io/lahaluhem`** (lowercase).
3. **Two lanes; one tool = one unit of change.** A static binary with an official image goes in
   **Lane 1** (a `# linter:` annotation + `FROM <img>:<tag>@<digest> AS <name>` + `COPY --from=<name> …`);
   a tool that needs a runtime / package manager goes in **Lane 2** (the install block, with a
   self-contained `# linter:` annotation). Every bundled tool gets a row in [`LINTERS.md`](./LINTERS.md),
   whose table is **generated** from the Dockerfile by `./gen-linters.sh` (run it after adding or
   removing a tool; never hand-edit the table). See
   [`APPENDIX.md#two-lane-architecture`](./APPENDIX.md#two-lane-architecture) and
   [`APPENDIX.md#generated-manifest`](./APPENDIX.md#generated-manifest).
4. **Multi-arch (`amd64` + `arm64`).** Before adding a Lane-1 tool, confirm its upstream image
   ships both arches: `docker buildx imagetools inspect <ref>` should show an image index with
   both platforms. (All current tools do, natively.)
5. **Pin upstreams by digest** (`tag@sha256:…`: the tag is the readable version, the digest makes
   the build reproducible). Don't hand-edit a digest except when adding/removing a tool;
   **Dependabot owns the bumps**. See
   [`APPENDIX.md#digest-pins-dependabot`](./APPENDIX.md#digest-pins-dependabot).
6. **Publishing is outward-facing, so confirm-first**, and gated to `master` pushes + manual
   `workflow_dispatch`; pull requests build-validate without pushing. See
   [`APPENDIX.md#publish-gating`](./APPENDIX.md#publish-gating).
7. **Verify versions/digests against registries before pinning** — never from memory.
8. **Never claim a multi-arch publish succeeded** without `docker manifest inspect <ref>` showing
   **both** `linux/amd64` and `linux/arm64`.

## Build & test flow

1. `./build.sh` builds `linterpol:local` for the host arch and self-checks (prints each tool's
   version).
2. *(planned)* `test.yml` builds the image and **dogfoods** it: lints this repo's own Dockerfile
   / workflows / shell scripts with the image it just built, and runs `./gen-linters.sh --check`
   to fail if `LINTERS.md` has drifted from the Dockerfile.
3. *(planned)* `build_and_push.yml` does the single-job multi-arch build and pushes to
   `ghcr.io/lahaluhem/linterpol`, gated to `master` + dispatch.
4. Dependabot bumps the `FROM` digests and action pins weekly.

## Testing

- `./build.sh` runs locally (host arch), no CI round-trip.
- To add a tool: add it to its lane (with its `# linter:` annotation), build locally, confirm it
  runs on this arch, and (Lane 1) confirm the upstream ships `arm64`. Run `./gen-linters.sh` to
  refresh [`LINTERS.md`](./LINTERS.md).

## Code style (no separate CODESTYLE.md yet)

The surface is small (one Dockerfile, a couple of shell scripts, soon some workflow YAML), so:

- **Dockerfile:** two lanes; one `FROM` + one `COPY` per Lane-1 tool, each with a `# linter:`
  annotation above its `FROM` (feeds `LINTERS.md`); pin `tag@digest`; in Lane 2 clean apt lists in
  the same layer (`rm -rf /var/lib/apt/lists/*`). The image runs as the non-root `lint` user and
  expects the repo mounted read-only at `/work`.
- **Workflow YAML:** 2-space indent; pin actions by **SHA + a version comment** (so Dependabot
  tracks them); keep `run:` blocks `actionlint`/shellcheck-clean.
- **Bash:** `set -euo pipefail`; quote expansions.

## Status & remaining polish (as of 2026-06-26; prune as done)

The image, `build.sh`, digest pins, and Dependabot are in place and verified. To finish the
standalone setup:

- [x] **Pick the final name** (`Linterpol`); renamed across the image `LABEL`s, `README`, the
      local tag, and chrysalis's `LINTERPOL_IMAGE` default.
- [ ] **Finalize `README.md`** (its Roadmap still says "Renovate" and lists digest-pinning as a
      TODO; both are now done/changed) and **add a `LICENSE`** (MIT, matching chrysalis).
- [ ] **`test.yml`**: self-test / dogfood workflow (build + lint this repo with the image; also run
      `./gen-linters.sh --check`).
- [ ] **`build_and_push.yml`**: single-job buildx multi-arch publish, gated to master + dispatch.
- [ ] **First GHCR publish** (outward-facing, so confirm-first), then verify both arches via
      `docker manifest inspect`.
- [ ] Back in chrysalis: repoint `LINTERPOL_IMAGE`'s default from `linterpol:local` to the published
      ref.
