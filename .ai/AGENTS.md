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
(shell), **ruff** (Python lint + format), **container-structure-test** (container image
structure). Full list: [`LINTERS.md`](./LINTERS.md).

## Scope — what this repo is and is NOT

- **In scope:** building and publishing the combined tools image (the Dockerfile, the
  build/publish workflow, the bundled-tool manifest).
- **Out of scope (by design):** *how or where* the image is consumed. It is a plain OCI image:
  any CI, any runtime, run against any repo. **Do not bake in consumer-specific logic** (no
  assumptions about which repo runs it, no project-specific entrypoints).

## Stack

- **Docker Buildx** — multi-platform builds. The publish path is a **single-job** multi-arch
  build (`buildx --platform linux/amd64,linux/arm64 --push`), not a native-runner matrix: the
  image only lands prebuilt per-arch binaries (a `COPY --from` for Lane 1, a verified download for
  Lane 2), so there is no native compilation and the QEMU penalty is negligible. See
  [`APPENDIX.md#single-job-buildx`](./APPENDIX.md#single-job-buildx).
- **Two-lane architecture** — static-binary tools with an official image (Lane 1) vs
  downloaded-binary / package-manager tools (Lane 2). See [`LINTERS.md`](./LINTERS.md) and
  [`APPENDIX.md#two-lane-architecture`](./APPENDIX.md#two-lane-architecture).
- **GitHub Actions** — `.github/workflows/`: `test.yml` self-test, `build_and_push.yml` publish,
  `regen-linters.yml` LINTERS.md regen (any Dockerfile change).
- **GHCR** — `ghcr.io/lahaluhem` (lowercase; GHCR namespaces are lowercase).
- **Renovate** — version tracking (`.github/renovate.jsonc`): `config:best-practices` digest-pins
  and bumps the `FROM`s and SHA-pins the workflow actions; a `custom.regex` manager bumps the
  `container-structure-test` binary version. Weekly. See
  [`APPENDIX.md#reproducibility-renovate`](./APPENDIX.md#reproducibility-renovate).
- **Bash** — `scripts/build.sh` (local build + self-check) and `scripts/gen-linters.sh`.

## Repo layout

```
linterpol/
├── images/
│   └── lean/Dockerfile     lean tools image (linterpol:latest); two lanes, FROMs pinned tag@digest
├── scripts/
│   ├── build.sh            local host-arch build + self-check (tags linterpol:local)
│   └── gen-linters.sh      regenerate the LINTERS.md table from the Dockerfile (+ --check)
├── tests/
│   └── image-structure.yaml  container-structure-test spec (PATH + image-contract checks)
├── .dockerignore
├── LINTERS.md              bundled-tools manifest; the table is generated from the Dockerfile
├── README.md               what it is, usage, architecture
├── APPENDIX.md             design rationale (anchor-keyed)
├── .github/
│   ├── renovate.jsonc      config:best-practices + a custom manager for c-s-t; weekly
│   └── workflows/
│       ├── test.yml             self-test / dogfood (structure test + lint + LINTERS.md drift check)
│       ├── build_and_push.yml   single-job multi-arch publish (gated)
│       └── regen-linters.yml    regenerate LINTERS.md on any Dockerfile change
└── .ai/                    AGENTS.md + CLAUDE.md (symlinked at root, gitignored)
```

## Hard rules

1. **Scope is build + publish the tools image.** Don't add consumer-specific logic; consumption
   is portable and out of scope.
2. **Registry is `ghcr.io/lahaluhem`** (lowercase).
3. **Two lanes; one tool = one unit of change.** A static binary with an official image goes in
   **Lane 1** (a `# linter:` annotation + `FROM <img>:<tag>@<digest> AS <name>` + `COPY --from=<name> …`);
   a tool with no usable official image goes in **Lane 2** (a package-manager install block, or a
   prebuilt binary downloaded and checksum-verified in a stage then `COPY`d in), with a
   self-contained `# linter:` annotation. Every bundled tool gets a row in [`LINTERS.md`](./LINTERS.md),
   whose table is **generated** from the Dockerfile; CI (`regen-linters.yml`) regenerates and commits it
   on any Dockerfile change, so don't hand-edit or commit it (run `./scripts/gen-linters.sh` locally only
   to preview). See
   [`APPENDIX.md#two-lane-architecture`](./APPENDIX.md#two-lane-architecture) and
   [`APPENDIX.md#generated-manifest`](./APPENDIX.md#generated-manifest).
4. **Multi-arch (`amd64` + `arm64`).** Before adding a Lane-1 tool, confirm its upstream image
   ships both arches: `docker buildx imagetools inspect <ref>` should show an image index with
   both platforms. (All current tools do, natively.)
5. **Pin upstreams by digest** (`tag@sha256:…`: the tag is the readable version, the digest makes
   the build reproducible). The one exception is `container-structure-test`, which has no usable
   image and is a version-pinned, checksum-verified downloaded binary (its version lives in the
   `CST_VERSION` ARG). Don't hand-edit a digest or that version except when adding/removing a tool;
   **Renovate owns the bumps**. See
   [`APPENDIX.md#reproducibility-renovate`](./APPENDIX.md#reproducibility-renovate).
6. **Publishing is outward-facing, so confirm-first**, and gated to `main` pushes + manual
   `workflow_dispatch`; pull requests build-validate without pushing. See
   [`APPENDIX.md#publish-gating`](./APPENDIX.md#publish-gating).
7. **Verify versions/digests against registries before pinning** — never from memory.
8. **Never claim a multi-arch publish succeeded** without `docker manifest inspect <ref>` showing
   **both** `linux/amd64` and `linux/arm64`.

## Build & test flow

1. `./scripts/build.sh` builds `linterpol:local` for the host arch and self-checks (prints each tool's
   version).
2. `test.yml` builds the image and **dogfoods** it: structure-tests the image with its own
   `container-structure-test` (tar driver, no socket) against `tests/image-structure.yaml`, lints
   this repo's own Dockerfile / workflows / shell scripts with the image it just built, and runs
   `./scripts/gen-linters.sh --check` to fail if `LINTERS.md` has drifted from the Dockerfile.
3. `build_and_push.yml` does the single-job multi-arch build and pushes to
   `ghcr.io/lahaluhem/linterpol`, gated to `main` + dispatch; PRs build-validate both arches.
4. Renovate bumps the `FROM` digests, action pins, and the `container-structure-test` version weekly.
5. On any Dockerfile change (a Renovate or manual PR, or a push to `main`), `regen-linters.yml`
   regenerates `LINTERS.md` and commits it back via the lahaluhem-ci-bot App token, so `test.yml`'s
   drift check clears automatically. (Don't commit `LINTERS.md` by hand; CI owns it.)

## Testing

- `./scripts/build.sh` runs locally (host arch), no CI round-trip.
- To add a tool: add it to its lane (with its `# linter:` annotation), build locally, confirm it
  runs on this arch, and (Lane 1) confirm the upstream ships `arm64`. Leave [`LINTERS.md`](./LINTERS.md)
  to CI (`regen-linters.yml`); run `./scripts/gen-linters.sh` locally only to preview the table.

## Code style (no separate CODESTYLE.md yet)

The surface is small (one Dockerfile, a couple of shell scripts, soon some workflow YAML), so:

- **Dockerfile:** two lanes; one `FROM` + one `COPY` per Lane-1 tool, each with a `# linter:`
  annotation above its `FROM` (feeds `LINTERS.md`); pin `tag@digest`; in Lane 2 clean apt lists in
  the same layer (`rm -rf /var/lib/apt/lists/*`). The image runs as the non-root `lint` user and
  expects the repo mounted read-only at `/work`.
- **Workflow YAML:** 2-space indent; pin actions by **SHA + a version comment** (so Renovate
  tracks them); keep `run:` blocks `actionlint`/shellcheck-clean.
- **Bash:** `set -euo pipefail`; quote expansions.

## Status & remaining polish (as of 2026-06-26; prune as done)

The image (now including container-structure-test), `scripts/build.sh`, digest pins, and Renovate
are in place and verified. To finish the standalone setup:

- [x] **Pick the final name** (`Linterpol`); renamed across the image `LABEL`s, `README`, the
      local tag, and chrysalis's `LINTERPOL_IMAGE` default.
- [x] **`README.md` finalized** (usage, architecture, roadmap).
- [x] **`LICENSE` added** (MIT, matching chrysalis).
- [x] **`test.yml`**: self-test / dogfood workflow (build + lint this repo with the image; also runs
      `./scripts/gen-linters.sh --check`).
- [x] **`build_and_push.yml`**: single-job buildx multi-arch publish, gated to main + dispatch.
- [x] **`container-structure-test` added** (Lane-2 downloaded binary; both arches verified, in
      `LINTERS.md`).
- [x] **Migrated Dependabot → Renovate** (`.github/renovate.jsonc` + `regen-linters.yml`; tracks the
      `FROM`s, action SHAs, and the c-s-t version).
- [x] **First GHCR publish** done and verified: `ghcr.io/lahaluhem/linterpol:latest` is a multi-arch
      manifest (linux/amd64 + linux/arm64), and chrysalis pins a digest of it.
- [ ] **Republish with `container-structure-test`** (outward-facing, so confirm-first), then verify
      both arches via `docker manifest inspect`.
- [ ] Back in chrysalis: bump the pinned `linterpol` digest to the c-s-t-carrying image (Renovate
      handles this once it's republished).
