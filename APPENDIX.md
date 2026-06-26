<!-- TOC start -->

- [`AGENTS.md` and `CLAUDE.md` are symlinks into `.ai/`](#ai-files-symlinked)
- [Why this repo exists: one multi-arch tools image](#why-ci-tools)
- [The two-lane architecture](#two-lane-architecture)
- [Multi-arch via a single-job buildx build](#single-job-buildx)
- [Reproducibility: digest pins + Dependabot](#digest-pins-dependabot)
- [Publishing is gated to `master` and manual dispatch](#publish-gating)

<!-- TOC end -->

Consolidated source of truth for design decisions, rejected paths, and non-obvious trade-offs.
The README, [`.ai/AGENTS.md`](./.ai/AGENTS.md), and [`.ai/CLAUDE.md`](./.ai/CLAUDE.md) reference
sections here by anchor (e.g. `APPENDIX.md#two-lane-architecture`).

---

<a id="ai-files-symlinked"></a>
## `AGENTS.md` and `CLAUDE.md` are symlinks into `.ai/`

- **Decision:** the canonical text for both files lives under `.ai/`. The repo root holds symlinks
  (`AGENTS.md → .ai/AGENTS.md`, `CLAUDE.md → .ai/CLAUDE.md`).
- **Why:** agents auto-discover `CLAUDE.md` / `AGENTS.md` at the project root, but two more loose
  Markdown files at the root add noise. Scoping them under `.ai/` keeps them together; the root
  symlinks preserve auto-discovery.
- **Committed vs. local:** the `.ai/` files are committed; the root symlinks are **gitignored**
  (`/AGENTS.md`, `/CLAUDE.md`), so nothing depends on them. Recreate them locally:

  ```bash
  ln -s .ai/AGENTS.md AGENTS.md
  ln -s .ai/CLAUDE.md CLAUDE.md
  ```

  A real file at the root works too; the `.ai/` copies stay the default. (Same pattern as the
  chrysalis repo this was modeled on.)

---

<a id="why-ci-tools"></a>
## Why this repo exists: one multi-arch tools image

The problem: a test script that shells out to `hadolint` / `actionlint` / `shellcheck` forces
every contributor to install those tools by hand. The fix is one image with the tools baked in,
run against a mounted checkout.

Why not an off-the-shelf aggregator (researched 2026-06):

- **super-linter** (`ghcr.io/super-linter/super-linter`): ~1.9 GB, and **amd64-only** (the arm64
  PR is still a draft). New linters can't be added without forking.
- **MegaLinter** (`oxsecurity/megalinter`): ~4.9 GB for the full flavor, **amd64-only** (arm64
  issue open), and **AGPL-3.0**. No stock flavor is just these tools; a lean one means building a
  custom flavor yourself.
- Both run under emulation on Apple Silicon, and both are "huge + configurable from a fixed menu",
  not "lean + extensible".

Rolling our own is a few static binaries (`COPY --from` the official images): ~220 MB, natively
multi-arch, MIT, and you curate exactly the tool set. The trade-off (you maintain the list) is the
point. See [#two-lane-architecture](#two-lane-architecture).

---

<a id="two-lane-architecture"></a>
## The two-lane architecture

Tools are added via one of two lanes, chosen by **how the tool is distributed**:

- **Lane 1, static-binary tools** (Go/Rust/Haskell with an official image): one build stage per
  tool (`FROM <img> AS <name>`) and one `COPY --from=<name>` of the binary into the final image.
  Cheap, tiny, natively multi-arch. Most modern linters land here. The three current tools are all
  statically linked, so the base barely matters (even `scratch` would run them); `debian:stable-slim`
  is chosen for headroom when Lane 2 grows.
- **Lane 2, package-manager tools** (npm/pip/apt): a clearly separated install block in the
  `Dockerfile`.

Adding a tool touches only its lane plus a row in [`LINTERS.md`](./LINTERS.md). The lane split is
what keeps the image **modular and scalable**: any future tool has an obvious home. If Lane 2 ever
grows into many heterogeneous tools, that is the cue to switch its runner to
[pre-commit](https://pre-commit.com) rather than hand-rolling installs.

`container-structure-test` (planned) is the first tool that won't be a pure Lane-1 drop-in: it
talks to a Docker daemon, so it needs the host socket mounted and the image-under-test loaded. Treat
it as its own documented case, not the read-only-mount default the lint tools follow.

---

<a id="single-job-buildx"></a>
## Multi-arch via a single-job buildx build

- **Decision:** publish with a single `docker buildx build --platform linux/amd64,linux/arm64
  --push`, not a native-runner matrix with push-by-digest + manifest merge (which is what the
  chrysalis repo uses).
- **Why it differs from chrysalis:** chrysalis compiles Flutter/Android natively, where emulating
  the non-host arch under QEMU is slow, so a native matrix earns its complexity. This image
  **compiles nothing**: each platform's build just `COPY`s that platform's prebuilt binary out of
  the upstream multi-arch image. The only step that executes in the target rootfs is a one-line
  `useradd`, so the QEMU penalty is negligible and the simpler single job wins.

---

<a id="digest-pins-dependabot"></a>
## Reproducibility: digest pins + Dependabot

- **Digest pins:** every `FROM` is `tag@sha256:…`. The tag stays human-readable; the digest makes
  the build reproducible. All four are multi-arch index digests, so the pin stays multi-arch.
- **Dependabot, not Renovate.** This is the inverse of the chrysalis decision. chrysalis needs
  Renovate because its key dependency (the Flutter SDK pin) is a bare string in a `.env` file that
  no Dependabot ecosystem parses, so it needs Renovate's custom manager plus a bespoke datasource.
  Here the only dependencies are **standard `FROM` image refs and GitHub Actions pins**, both of
  which Dependabot parses natively. So the simpler, GitHub-native tool (no Mend app to authorize)
  suffices: `.github/dependabot.yml` runs the `docker` + `github-actions` ecosystems weekly.
- **Why the `docker` group is unfiltered.** The Actions group keeps the usual minor+patch-grouped /
  majors-individual split. The `docker` group intentionally has **no `update-types` filter**: the
  common update here is a digest-only bump (e.g. `debian:stable-slim` re-pushed under the same tag),
  which carries no semver type, so an `update-types` filter would scatter each digest bump into its
  own PR instead of grouping them.

---

<a id="publish-gating"></a>
## Publishing is gated to `master` and manual dispatch

*(Applies once `build_and_push.yml` exists.)*

- **Publish on `master` pushes and `workflow_dispatch`; pull requests build-validate without
  pushing.** The consumer tag (`:latest`) is shared, so gating publishing keeps every branch from
  clobbering it, while PRs still validate both arches and a deliberate manual dispatch can
  publish/verify a branch.
- **Verification:** a publish is only "done" once `docker manifest inspect <ref>` shows both
  `linux/amd64` and `linux/arm64`. Never report success without it.
