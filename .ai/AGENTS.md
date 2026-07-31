# AGENTS.md — `Linterpol`

Tool-agnostic brief for any coding agent (Claude Code, Copilot, Cursor, Codex, ...) working
in this repo. Claude-Code-specific guidance lives in [CLAUDE.md](./CLAUDE.md); design
rationale and rejected paths live in [`APPENDIX.md`](./APPENDIX.md) (anchor-keyed). Read this
first.

## Project goal

`Linterpol` builds and publishes small, **multi-arch (`linux/amd64` + `linux/arm64`)** Docker
images bundling the CI lint, check, and test tools used across the author's repos, published to
**GHCR under `ghcr.io/lahaluhem`**. The point: a checkout can be linted with `docker run` instead of every
contributor installing the tools by hand.

Three images today, one per `images/<variant>/Dockerfile`:

- **`linterpol`** (lean): **hadolint** (Dockerfiles), **actionlint** (GitHub workflows),
  **shellcheck** (shell), **ruff** (Python lint + format),
  **biome** (JSON/JSONC + JS/TS/CSS/GraphQL), **swiftlint** (Swift),
  **rumdl** (Markdown), **ryl** (YAML), **container-structure-test** (container image structure),
  **shellspec** (shell BDD tests, [the first test tool, not a linter](./APPENDIX.md#shellspec-test-framework)).
- **`linterpol-jvm`** (sibling): a JRE plus **ktlint** (Kotlin). Separate so the lean image stays
  JVM-free. See [`APPENDIX.md#jvm-variant`](./APPENDIX.md#jvm-variant).
- **`linterpol-dotnet`** (sibling): the .NET runtime plus **CSharpier** (C#). Separate so the lean
  image stays .NET-free; file-level only (no SDK or build tooling). See
  [`APPENDIX.md#dotnet-variant`](./APPENDIX.md#dotnet-variant).

Full list: [`LINTERS.md`](./LINTERS.md).

## Scope — what this repo is and is NOT

- **In scope:** building and publishing the combined tools images (the per-variant Dockerfiles, the
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
- **Per-stack image variants** — one image per `images/<variant>/Dockerfile`: the lean `linterpol`,
  the `linterpol-jvm` sibling (a JRE + JVM linters), and the `linterpol-dotnet` sibling (a .NET
  runtime + CSharpier). Independent images, picked by base runtime. See
  [`APPENDIX.md#jvm-variant`](./APPENDIX.md#jvm-variant) and
  [`APPENDIX.md#dotnet-variant`](./APPENDIX.md#dotnet-variant).
- **Two-lane architecture** (within an image) — static-binary tools with an official image (Lane 1)
  vs downloaded-binary / package-manager tools (Lane 2), orthogonal to the variant axis. See
  [`LINTERS.md`](./LINTERS.md) and [`APPENDIX.md#two-lane-architecture`](./APPENDIX.md#two-lane-architecture).
- **GitHub Actions** — `.github/workflows/`: `test.yml` self-test, `build_and_push.yml` publish,
  `release.yml` manual semver bump + tag, `regen-linters.yml` LINTERS.md regen (any Dockerfile
  change), `cleanup-packages.yml` weekly GHCR prune.
- **Semver releases** — a bare `1.2.3` git tag is the only thing that publishes; `release.yml` cuts
  it from a `workflow_dispatch` bump level. See
  [`APPENDIX.md#versioning-releases`](./APPENDIX.md#versioning-releases).
- **GHCR** — `ghcr.io/lahaluhem` (lowercase; GHCR namespaces are lowercase).
- **Renovate** — version tracking (`.github/renovate.jsonc`): `config:best-practices` digest-pins
  and bumps the `FROM`s and SHA-pins the workflow actions; a `custom.regex` manager bumps the
  `ARG`-pinned tool versions (`container-structure-test`, `swiftlint`, `rumdl`, `ryl`, `shellspec`,
  `ktlint`, `csharpier`). Weekly. See
  [`APPENDIX.md#reproducibility-renovate`](./APPENDIX.md#reproducibility-renovate).
- **Bash** — `scripts/build.sh` (local build + self-check) and `scripts/gen-linters.sh`.

## Repo layout

```
linterpol/
├── images/                 one Dockerfile per image variant
│   ├── lean/Dockerfile     lean tools image (linterpol:latest); two lanes, FROMs pinned tag@digest
│   ├── jvm/Dockerfile      JVM sibling (linterpol-jvm:latest); Temurin JRE + ktlint
│   └── dotnet/Dockerfile   .NET sibling (linterpol-dotnet:latest); .NET runtime + CSharpier
├── scripts/
│   ├── build.sh            host-arch build + self-check of any/all variants (linterpol[-<v>]:local)
│   └── gen-linters.sh      regenerate the LINTERS.md tables from the Dockerfiles (+ --check)
├── tests/
│   ├── image-structure.yaml         container-structure-test spec for the lean image
│   ├── image-structure-jvm.yaml     ... and for the jvm image
│   └── image-structure-dotnet.yaml  ... and for the dotnet image
├── .dockerignore
├── LINTERS.md              bundled-tools manifest; the table is generated from the Dockerfile
├── README.md               what it is, usage, architecture
├── APPENDIX.md             design rationale (anchor-keyed)
├── .github/
│   ├── renovate.jsonc      config:best-practices + a custom manager for c-s-t; weekly
│   └── workflows/
│       ├── test.yml             self-test / dogfood (structure test + lint + LINTERS.md drift check)
│       ├── build_and_push.yml   single-job multi-arch publish (version tags only)
│       ├── release.yml          manual bump (patch|minor|major) -> pushes the semver tag
│       ├── regen-linters.yml    regenerate LINTERS.md on any Dockerfile change
│       └── cleanup-packages.yml weekly GHCR prune of old versions
└── .ai/                    AGENTS.md + CLAUDE.md (symlinked at root, gitignored)
```

## Making changes: refactor first

Before adding a tool, variant, or workflow change, check whether the current structure is the
right foundation for it. If a refactor would make this change (and the ones that predictably
follow) cleaner or easier to extend, do that refactor first as its own behaviour-preserving step,
then build on top. Long-term maintainability of the repo outranks the speed of any single change.
Keep the refactor separate from the feature so each is easy to review and revert, and don't
gold-plate: refactor for the change in front of you or work you can concretely see coming, not for
hypothetical futures.

## Hard rules

1. **Scope is build + publish the tools images.** Don't add consumer-specific logic; consumption
   is portable and out of scope.
2. **Registry is `ghcr.io/lahaluhem`** (lowercase).
3. **One image per stack; two lanes within each; one tool = one unit of change.** Each image is an
   `images/<variant>/Dockerfile`: the lean `linterpol`, the `linterpol-jvm` sibling, and the
   `linterpol-dotnet` sibling. A new heavy-runtime stack is a new sibling (`images/<variant>/Dockerfile`, published as
   `linterpol-<variant>`, with its own `tests/image-structure-<variant>.yaml` and a `linters:<variant>`
   section in `LINTERS.md`), not tools bolted onto the lean image. Within an image, a static binary with
   an official image goes in **Lane 1** (a `# linter:` annotation + `FROM <img>:<tag>@<digest> AS <name>`
   + `COPY --from=<name> …`); a tool with no usable official image goes in **Lane 2** (a package-manager
   install block, or a prebuilt binary downloaded and verified in a stage then `COPY`d in), with a
   self-contained `# linter:` annotation. Lanes are orthogonal to variants. Every bundled tool gets a row
   in [`LINTERS.md`](./LINTERS.md), whose tables are **generated** from the Dockerfiles; CI
   (`regen-linters.yml`) regenerates and commits on any Dockerfile change, so don't hand-edit or commit
   it (run `./scripts/gen-linters.sh` locally only to preview). See
   [`APPENDIX.md#jvm-variant`](./APPENDIX.md#jvm-variant),
   [`APPENDIX.md#two-lane-architecture`](./APPENDIX.md#two-lane-architecture) and
   [`APPENDIX.md#generated-manifest`](./APPENDIX.md#generated-manifest).
4. **Multi-arch (`amd64` + `arm64`).** Before adding a Lane-1 tool, confirm its upstream image
   ships both arches: `docker buildx imagetools inspect <ref>` should show an image index with
   both platforms. (All current tools do, natively.)
5. **Pin upstreams by digest** (`tag@sha256:…`: the tag is the readable version, the digest makes
   the build reproducible). The exceptions are the downloaded tools (`container-structure-test`,
   `swiftlint`, `rumdl`, `ryl`, `shellspec`, `ktlint`), which have no usable image and are version-pinned + verified at build (each
   version lives in an `ARG <NAME>_VERSION`). Don't hand-edit a digest or those versions except when
   adding/removing a tool; **Renovate owns the bumps**. See
   [`APPENDIX.md#reproducibility-renovate`](./APPENDIX.md#reproducibility-renovate).
6. **Publishing is outward-facing, so confirm-first**, and gated to **version tags**: a bare semver
   tag (`1.2.3`) publishes `1.2.3` + `1.2` + `1` + `latest`, while `main` pushes and pull requests
   build-validate both arches without pushing. Cut a release from the **Release** workflow
   (`workflow_dispatch`, bump level `patch`/`minor`/`major`); never hand-push a version tag. Pick the
   level by consumer impact: **major** for a break (tool removed, `/work` or non-root `lint` contract
   changed, image renamed, a tool's own breaking major), **minor** for a tool added or a new variant,
   **patch** for tool/base-image bumps, build internals, and docs. See
   [`APPENDIX.md#versioning-releases`](./APPENDIX.md#versioning-releases).
7. **Verify versions/digests against registries before pinning** — never from memory.
8. **Never claim a multi-arch publish succeeded** without `docker manifest inspect <ref>` showing
   **both** `linux/amd64` and `linux/arm64`.
9. **Image metadata is workflow-owned.** Published images use OCI media types
   (`oci-mediatypes=true`), and their `org.opencontainers.image.*` labels and annotations come from
   `docker/metadata-action` in `build_and_push.yml`, **not** `LABEL`s in the Dockerfiles (which stay
   LABEL-free). See [`APPENDIX.md#oci-metadata`](./APPENDIX.md#oci-metadata).

## Build & test flow

1. `./scripts/build.sh [variant...]` builds the named variants (or all of `images/*/` if none) for the
   host arch and self-checks each. See [`APPENDIX.md#build-script`](./APPENDIX.md#build-script).
2. `./scripts/test.sh [lint|structure|oci|all]` runs the check suite locally or in CI (one source of
   truth, so the two can't drift): it **dogfoods** the lean image's linters over this repo, structure-
   tests the lean image and the jvm + dotnet siblings (tar driver, no socket) against the
   `tests/image-structure*.yaml` specs, runs `gen-linters.sh --check` for `LINTERS.md` drift, and
   asserts the lean image's OCI media types. `test.yml` just calls its targets as separate steps
   (behind a CI-only gate that skips commits already tested on their PR).
3. `release.yml` (manual dispatch, bump level) pushes a bare `1.2.3` tag with the App token, and that
   push is what triggers a publish. It pre-flights first: main only, and no failing or in-flight
   checks on HEAD.
4. `build_and_push.yml` does a matrix multi-arch build and pushes `linterpol`, `linterpol-jvm`, and
   `linterpol-dotnet` as `1.2.3` + `1.2` + `1` + `latest`. Version tags only; `main` pushes and PRs
   build-validate both arches without pushing.
5. Renovate bumps the `FROM` digests, action pins, and the `container-structure-test` version weekly.
6. On any Dockerfile change (a Renovate or manual PR, or a push to `main`), `regen-linters.yml`
   regenerates `LINTERS.md` and commits it back via the lahaluhem-ci-bot App token, so `test.yml`'s
   drift check clears automatically. (Don't commit `LINTERS.md` by hand; CI owns it.)

## Testing

- `./scripts/build.sh` builds locally (host arch); `./scripts/test.sh` runs the full check suite
  locally (`lint` / `structure` / `oci`, or a single target), the same thing CI runs. No CI round-trip.
- To add a tool: add it to its lane (with its `# linter:` annotation), build locally, confirm it
  runs on this arch, and (Lane 1) confirm the upstream ships `arm64`. Leave [`LINTERS.md`](./LINTERS.md)
  to CI (`regen-linters.yml`); run `./scripts/gen-linters.sh` locally only to preview the table.

## Code style (no separate CODESTYLE.md yet)

The surface is small (one Dockerfile, a couple of shell scripts, soon some workflow YAML), so:

- **Dockerfile:** two lanes; one `FROM` + one `COPY` per Lane-1 tool, each with a `# linter:`
  annotation above its `FROM` (feeds `LINTERS.md`); pin `tag@digest`; in Lane 2 clean apt lists in
  the same layer (`rm -rf /var/lib/apt/lists/*`). No `org.opencontainers.image.*` `LABEL`s; image
  metadata is workflow-owned (hard rule 9). The image runs as the non-root `lint` user and expects
  the repo mounted read-only at `/work`.
- **Workflow YAML:** 2-space indent; pin actions by **SHA + a version comment** (so Renovate
  tracks them); keep `run:` blocks `actionlint`/shellcheck-clean; and run `ryl` on touched YAML
  before calling it done (`test.yml` lints all YAML with it, per `.ryl.toml`), since `actionlint`
  alone doesn't catch everything `ryl` does.
- **Bash:** `set -euo pipefail`; quote expansions.
- **Comments: one or two lines, not a thesis.** Comment the *why* and the surprising; skip what the
  line already says. A point needing a paragraph is rationale, so it belongs in `APPENDIX.md` behind
  an anchor with a one-line pointer here. Applies to YAML, Dockerfiles, and shell alike. **Why:** a
  wall-of-text comment block buries the one line that mattered, and it rots faster than the code.
  **How to apply:** when you edit near a comment that has outgrown its point, trim it in the same
  pass.
- **Docs:** don't hardcode a tool *count* in prose (e.g. "the lean image's nine"); it churns on
  every tool add. Enumerate tools where it helps, or use count-free phrasing; the generated
  `LINTERS.md` is the canonical list.

## Status & remaining polish (as of 2026-07-31; prune as done)

The image (now including container-structure-test), `scripts/build.sh`, digest pins, and Renovate
are in place and verified. To finish the standalone setup:

- [x] **Pick the final name** (`Linterpol`); renamed across the image `LABEL`s, `README`, the
      local tag, and chrysalis's `LINTERPOL_IMAGE` default.
- [x] **`README.md` finalized** (usage, architecture, roadmap).
- [x] **`LICENSE` added** (MIT, matching chrysalis).
- [x] **`test.yml`**: self-test / dogfood workflow (build + lint this repo with the image; also runs
      `./scripts/gen-linters.sh --check`).
- [x] **`build_and_push.yml`**: single-job buildx multi-arch publish, gated to version tags.
- [x] **`container-structure-test` added** (Lane-2 downloaded binary; both arches verified, in
      `LINTERS.md`).
- [x] **Migrated Dependabot → Renovate** (`.github/renovate.jsonc` + `regen-linters.yml`; tracks the
      `FROM`s, action SHAs, and the c-s-t version).
- [x] **First GHCR publish** done and verified: `ghcr.io/lahaluhem/linterpol:latest` is a multi-arch
      manifest (linux/amd64 + linux/arm64), and chrysalis pins a digest of it.
- [x] **Semver releases** (`release.yml` + tag-gated `build_and_push.yml`), closing
      [#15](https://github.com/LahaLuhem/linterpol/issues/15). Not yet exercised: no tag pushed.
- [ ] **Cut `1.0.0`** (outward-facing, so confirm-first): dispatch Release with `bump: major`
      (`dry_run` first), then verify both arches on `1.0.0` for all three images via
      `docker manifest inspect`. This is also the first publish carrying `container-structure-test`
      and the **first `linterpol-dotnet` publish** (creates a NEW GHCR package, private by default;
      its matrix leg, structure spec, `LINTERS.md` section, Renovate coverage, and docs are all in and
      it builds + self-checks on both arches locally).
- [ ] Back in chrysalis: repoint `LINTERPOL_IMAGE` off the bare `:latest` digest onto a `1.2.3` tag,
      so Renovate tracks releases instead of a moving tag's digest.
- [ ] **Only then** switch `cleanup-packages.yml` to `keep-n-tagged` + prune untagged and drop the age
      window. Unsafe before consumers repoint: cutting `1.0.0` leaves the old `latest` digest untagged,
      and the current 30-day window is what still protects a consumer pinning it.
