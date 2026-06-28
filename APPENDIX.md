<!-- TOC start -->

- [`AGENTS.md` and `CLAUDE.md` are symlinks into `.ai/`](#ai-files-symlinked)
- [Why this repo exists: one multi-arch tools image](#why-linterpol)
- [The two-lane architecture](#two-lane-architecture)
- [The JVM variant: a sibling image, not a Lane 3](#jvm-variant)
- [The .NET variant: CSharpier only, no build tooling](#dotnet-variant)
- [`LINTERS.md` is generated from the Dockerfile](#generated-manifest)
- [Multi-arch via a single-job buildx build](#single-job-buildx)
- [The build script: shell with variant args, not bake (yet)](#build-script)
- [Reproducibility: digest pins + Renovate](#reproducibility-renovate)
- [Publishing is gated to `main` and manual dispatch](#publish-gating)

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

<a id="why-linterpol"></a>
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

Rolling our own is a handful of mostly-static binaries (`COPY --from` the official images, or a
download-and-verify for the ones that ship no usable image): ~350 MB with the current set
(SwiftLint's static build is ~80 MB of that), natively multi-arch, MIT, and you curate exactly the
tool set. The trade-off (you maintain the list) is the point. See
[#two-lane-architecture](#two-lane-architecture).

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

`container-structure-test` is the first tool that isn't a pure Lane-1 drop-in, in two ways:

- **Distribution:** it ships no usable multi-arch image (`gcr.io/gcp-runtimes/container-structure-test`
  is amd64-only and last built in 2023), so instead of a `COPY --from` it's a Lane-2 download: a
  throwaway stage fetches the per-arch release binary, verifies it against the release's own
  `checksums.txt`, and the final image `COPY`s just the binary. The version is pinned by an `ARG`
  (Renovate-tracked); see [#reproducibility-renovate](#reproducibility-renovate).
- **Runtime:** unlike the lint tools, which read the read-only-mounted sources, it loads and inspects
  a Docker *image*. So it needs either the host Docker socket mounted (Docker-out-of-Docker) or an
  image tarball via `--driver tar`. The repo's own self-test uses the tar driver (no socket needed);
  wiring the socket path for real consumers is their job, not this image's.

**SwiftLint** is the second Lane-2 downloaded binary, with two wrinkles of its own:

- **No checksums.txt.** Unlike c-s-t, SwiftLint publishes no checksum file for its Linux zips, so
  there's nothing in the release to verify against at build. Integrity rests on the pinned
  `SWIFTLINT_VERSION` fetched over HTTPS from the immutable release tag, plus an `unzip -t` CRC check
  of the archive. That keeps a Renovate bump a one-liner (bump the ARG, rebuild and re-verify); a
  hand-frozen per-arch SHA was rejected for the same reason c-s-t avoids one (a version-plus-hashes
  edit breaks the build on every bump until someone recomputes the hashes).
- **Static build, no SourceKit.** The release zip ships both a dynamic `swiftlint` (which needs the
  Swift runtime, so it only runs on the ~185 MB official image) and a fully static `swiftlint-static`.
  We take the static one so it drops onto `debian:stable-slim` like any other Lane-2 binary, at the
  cost of the handful of rules that need SourceKit (skipped at runtime with a warning); the
  SwiftSyntax-based majority run. Shipping the full runtime to recover those rules would roughly
  double the image, not worth it for a CI lint image.

---

<a id="jvm-variant"></a>
## The JVM variant: a sibling image, not a Lane 3

- **Decision:** JVM-stack linters ship in a separate image, `linterpol-jvm`, built from its own
  `images/jvm/Dockerfile`. It is a **sibling** of the lean image, not a superset: it carries a JRE
  plus JVM-language linters (ktlint today) and nothing from the lean image. `linterpol:latest` stays
  JVM-free.
- **Why a separate image.** ktlint (and detekt later) are JVM tools with no native binary, so they
  need a JRE. The Temurin JRE base is ~340 MB, about the size of the entire lean image, so folding it
  into `linterpol` would roughly double a tag that consumers pin precisely because it's lean and that
  they don't use for JVM linting. A separate tag isolates that cost to the repos that opt in.
- **Why a sibling, not a superset.** A superset (lean tools plus JVM tools in one image) was the
  alternative. The sibling keeps the JVM image to just what JVM linting needs and keeps the two
  Dockerfiles independent (each its own base, its own `FROM` pins, its own structure spec and
  `LINTERS.md` section), which suits the per-stack layout. The trade-off: a repo that lints both its
  Dockerfiles/workflows and its Kotlin runs two images. That's accepted; mixed repos are rare and the
  invocation contract is identical across images.
- **It is NOT a new lane.** The two lanes describe *how a tool is distributed* (Lane 1 = static
  binary `COPY`d from an official image; Lane 2 = downloaded artifact or package install). That axis is
  orthogonal to *which image* a tool lands in. ktlint is a plain Lane-2 download (a self-executing fat
  JAR), the same shape as swiftlint and container-structure-test in the lean image; it just lands in
  the jvm image because it needs the JRE. The new axis is the **image variant / base runtime**, not a
  third lane. A future static JVM tool would be Lane 1 *in* the jvm image; a future heavy stack (e.g.
  `linterpol-dotnet`) is another sibling at `images/dotnet/Dockerfile`.
- **Base + verification.** The base is `eclipse-temurin:21-jre`, digest-pinned and multi-arch like any
  `FROM` (Renovate bumps it); 21 is the conservative current LTS. ktlint ships no `checksums.txt`, and
  its `#!/bin/sh` self-executing JAR makes `unzip -t` only warn (so neither the
  container-structure-test checksum model nor the swiftlint CRC model fits), so integrity is "run it on
  the JRE and assert the pinned version". Because the jar is architecture-independent JVM bytecode, the
  fetch and verify happen once on the build host's arch (`--platform=$BUILDPLATFORM`, no QEMU) and the
  one jar is `COPY`d into the per-arch final image; the only emulated step in a cross-arch build stays
  the one-line `useradd`, same as the lean image.
- **Entrypoint reset.** `eclipse-temurin` ships an `ENTRYPOINT` (`/__cacert_entrypoint.sh`, a runtime
  CA-cert importer). The jvm Dockerfile clears it with `ENTRYPOINT []` so the image matches the lean
  contract (no entrypoint; `docker run <img> <tool> <args>` runs the tool directly). ktlint lints local
  files, so the CA-cert import isn't needed; `tests/image-structure-jvm.yaml` asserts the empty
  entrypoint.
- **Deferred / skipped (from the investigation in issue #4).** detekt is deferred: it's also a JVM CLI
  but degrades standalone (its type-resolution rules want a compiled classpath), so it can be added to
  this image later if wanted. Android Lint is skipped (needs the Android SDK + Gradle + a project build
  model, not portable), as is Konsist (a JUnit/kotlin-test library whose rules run via a test runner,
  not against mounted source).

---

<a id="dotnet-variant"></a>
## The .NET variant: CSharpier only, no build tooling

- **Decision:** .NET-stack linting ships in a separate image, `linterpol-dotnet`, built from its own
  `images/dotnet/Dockerfile`. Like the jvm image it is a **sibling**, not a superset: it carries the
  .NET runtime plus C# linters (CSharpier today) and nothing from the lean image. `linterpol:latest`
  stays .NET-free.
- **Why a separate image.** CSharpier ships only as a NuGet `dotnet tool` (no native binary), so it
  needs the .NET runtime. That runtime base is heavy relative to the lean image, and lean's consumers
  don't lint C#, so the same logic as the jvm image applies: isolate the runtime's cost to the tag
  that opts in. A repo that lints both its Dockerfiles/workflows and its C# runs both images.
- **CSharpier only, and why not the rest.** CSharpier is the one mainstream C# tool that runs
  *file-level*: it parses and reprints source in memory and reports the diff, with no project build.
  It's MIT, so it bakes into a public image cleanly. The others were deliberately skipped:
  - **Roslynator CLI, `dotnet format`, StyleCop.Analyzers, SonarAnalyzer.CSharp** are Roslyn
    analyzers or MSBuild tasks. They need the *compilation* (a restored solution and the SDK), which
    is exactly the contract this image declines to take on (next bullet).
  - **jb / ReSharper Command Line Tools** are skipped on license grounds: the ReSharper CLT license
    forbids redistribution without JetBrains' written consent, so it can't be baked into a public
    image (same spirit as the AGPL/MegaLinter rejection in [#why-linterpol](#why-linterpol)). It also
    wants a solution plus the SDK, so it fails the file-level contract anyway.
- **File-level, read-only contract.** The image lints a read-only mount like every other linterpol
  image. There is **no** SDK in the final image, no NuGet restore at runtime, and no `.sln`-loading
  tools. `csharpier check <path>` is the read-only mode (it reports unformatted files and exits
  non-zero; `format` is the one that writes, and we don't use it). Taking on a build/restore contract
  would mean shipping the SDK and a restore step, a different and much heavier kind of image, out of
  scope by design.
- **It is NOT a new lane.** As with the jvm image, CSharpier is a plain Lane-2 install (a NuGet
  `dotnet tool`), the same axis as swiftlint / ktlint / container-structure-test. The new axis is the
  **image variant / base runtime** (a .NET runtime), not a third lane.
- **Base + the multi-arch gotcha.** The base is `mcr.microsoft.com/dotnet/runtime:10.0`, digest-pinned
  and multi-arch like any `FROM` (Renovate bumps it); 10 is the current LTS (Nov 2025). We use the
  standard tag, not a `-chiseled` one: chiseled has no shell or `useradd`, which the non-root-`lint`
  plus `sh -c` self-check contract needs. A `dotnet tool`'s launcher *shim* is arch-specific, but the
  tool's payload DLLs are architecture-independent IL (they live under `tools/<tfm>/any/`). So the
  ktlint "fetch once on `$BUILDPLATFORM`" trick still applies, just via the SDK: an SDK stage on
  `--platform=$BUILDPLATFORM` runs `dotnet tool install` (no QEMU), the `net10.0` payload is copied
  into the per-arch final image, and a tiny `csharpier` wrapper on PATH runs the DLL through the
  `dotnet` host (`exec dotnet …/CSharpier.dll "$@"`) instead of the arch-specific shim. The only
  emulated step in a cross-arch build stays the one-line `useradd`, same as lean and jvm. The
  `net10.0` payload targets `Microsoft.NETCore.App 10.0.0`, an exact match for the base, and its
  `runtimeconfig.json` sets `rollForward: Major` as a safety net.
- **Verification.** CSharpier ships no `checksums.txt`, but `dotnet tool install` validates the
  package signature, and running the DLL (`csharpier --version`) asserts the pinned version, so
  integrity and version are proven in one step, the same "run it and assert" model as ktlint. The
  `ARG CSHARPIER_VERSION` is the single source of version truth: `gen-linters.sh` reads it for
  `LINTERS.md` and Renovate bumps it (the `custom.regex` manager, `datasource=nuget depName=CSharpier`).
- **Entrypoint.** Unlike the Temurin base the jvm image has to reset, the .NET runtime base sets no
  `ENTRYPOINT`, so there's nothing to clear; `tests/image-structure-dotnet.yaml` still asserts the
  empty entrypoint so the contract is locked either way.

---

<a id="generated-manifest"></a>
## `LINTERS.md` is generated from the Dockerfile

- **Decision:** the tool table in `LINTERS.md` is produced by [`gen-linters.sh`](./scripts/gen-linters.sh),
  not hand-maintained. The `Dockerfile` is the single source of truth.
- **Why:** Renovate bumps the `FROM` refs (and the `container-structure-test` version ARG) in the
  `Dockerfile`, but it can't touch a markdown table, so a hand-typed version list silently goes
  stale on every bump (worse than no table). With the table generated, a bump flows straight
  through and the doc can't disagree with the image.
- **Where the data comes from:** for a Lane-1 tool the version and upstream image are parsed off its
  `FROM <img>:<tag>@<digest> AS <name>` line; the two things not in a `FROM` (what it lints, its repo
  link) come from a `# linter: lints: … | repo: …` comment directly above that `FROM`. A Lane-2 tool
  has no `FROM`, so its annotation also carries `tool:`, `version:`, and `lane: 2`. One tool is still
  one place to edit.
- **The Version column is the raw pin:** for a Lane-1 tool, the tag from its `FROM` (e.g.
  `v2.14.0-alpine`); for a Lane-2 downloaded binary, the value of its `ARG …_VERSION` line (e.g.
  `container-structure-test`'s `CST_VERSION`). No flavor-stripping heuristic, so it tracks whatever
  Renovate writes, literally.
- **Drift guard:** `./scripts/gen-linters.sh --check` regenerates and diffs against the committed file,
  exiting non-zero on a mismatch. It runs locally and is meant to run in `test.yml`, so a stale
  `LINTERS.md` fails CI instead of merging.
- **Only the table is generated.** It sits between `<!-- linters:start -->` / `<!-- linters:end -->`
  markers; the surrounding prose (the "Adding a linter" guide) is hand-written and left alone.
- **Rejected:** a sidecar data file (e.g. `linters.yaml`) merged with the Dockerfile versions. It
  would split "add a tool" across two files; the annotation keeps everything in the Dockerfile.

---

<a id="single-job-buildx"></a>
## Multi-arch via a single-job buildx build

- **Decision:** publish with a single `docker buildx build --platform linux/amd64,linux/arm64
  --push`, not a native-runner matrix with push-by-digest + manifest merge (which is what the
  chrysalis repo uses).
- **Why it differs from chrysalis:** chrysalis compiles Flutter/Android natively, where emulating
  the non-host arch under QEMU is slow, so a native matrix earns its complexity. This image
  **compiles nothing**: each platform's build just lands that platform's prebuilt binary (a
  `COPY --from` of the upstream image for Lane 1, a download-and-verify stage for Lane 2). The only
  steps that execute in the target rootfs are the `container-structure-test` checksum-verify and a
  one-line `useradd`, both trivial, so the QEMU penalty is negligible and the simpler single job wins.

---

<a id="build-script"></a>
## The build script: shell with variant args, not bake (yet)

- **Decision:** [`scripts/build.sh`](./scripts/build.sh) is a thin shell wrapper that builds one or
  more image variants for the host arch and runs each image's self-check. It takes variant names as
  args (`./scripts/build.sh jvm`, or `lean jvm`, or none for all) and auto-discovers them from
  `images/*/Dockerfile`, mapping `lean` to `linterpol:local` and `<v>` to `linterpol-<v>:local`.
- **Not one script per image.** The per-image difference is two strings (the Dockerfile path and the
  tag); a script per variant would copy the other ~20 lines just to vary those two. One arg-taking
  script keeps the build-and-self-check logic in one place, and CI still calls exactly the variant it
  needs (`./scripts/build.sh jvm`).
- **Not `docker buildx bake` (yet).** Bake is the Docker-native way to declare several build targets
  in one file, and it's the obvious destination if this grows. Two things make it not worth it
  today: (1) build.sh also runs the self-check (`docker run <image>`), which bake doesn't do, so bake
  would replace only the *build* invocation, not the script; and (2) at two small variants the shell
  loop is trivial and adds no new file or language (HCL).
- **When to switch to bake.** Reach for a `docker-bake.hcl` once any of these holds:
  - **~3+ variants, or per-variant build options diverge** (different `--build-arg`s, platforms,
    cache scopes, labels). Bake's target inheritance and matrices cut the duplication a shell loop
    starts to pile up.
  - **One declarative target set should feed both local and CI.** Bake files are consumed by
    `docker buildx bake` locally and by `docker/bake-action` in CI, so platforms/tags/targets live in
    one place instead of being repeated across build.sh and `build_and_push.yml`.
  - **You need several images built in one buildx call** with a shared cache, instead of N separate
    `docker buildx build` invocations.

  Even then the self-check stays a separate step (bake builds, it doesn't run), so build.sh or a small
  successor keeps that job.

---

<a id="reproducibility-renovate"></a>
## Reproducibility: digest pins + Renovate

- **Digest pins:** every `FROM` is `tag@sha256:…`. The tag stays human-readable; the digest makes
  the build reproducible. They're multi-arch index digests, so the pin stays multi-arch.
- **The one binary that isn't an image:** `container-structure-test` has no usable multi-arch image,
  so it's a downloaded release binary (see [#two-lane-architecture](#two-lane-architecture)). It's
  pinned by an `ARG CST_VERSION` and verified at build against the *release's own* `checksums.txt`,
  not a hand-frozen per-arch SHA in the Dockerfile. Why: that keeps a version bump a true one-liner
  (bump the ARG, the build re-fetches and re-verifies) instead of a version-plus-two-hashes edit that
  breaks the build until someone hand-updates the hashes. The integrity guarantee is "the binary
  matches the checksum the release published for that immutable tag", the same model every install
  script uses; combined with the version pin it's reproducible enough for a CI tool image.
- **Renovate, not Dependabot.** This repo originally used Dependabot, on the logic that its only
  dependencies were standard `FROM` refs and Actions pins, both of which Dependabot parses natively.
  Adding `container-structure-test` broke that premise: a binary downloaded from a GitHub release is
  **not** a `FROM` ref, and Dependabot has no generic mechanism to track it. Renovate does, via a
  `custom.regex` manager keyed on the `# renovate:` marker above the ARG. Rather than run two bots,
  the repo moved wholesale to Renovate, which also matches **chrysalis** (the main consumer already
  runs Renovate, so it's one tool and one already-authorized Mend app across both repos). The config
  `.github/renovate.jsonc` extends `config:best-practices` (digest-pins Docker, SHA-pins Actions) on
  a weekly schedule, plus the one custom manager for the binary. Grouping is left to the preset's
  defaults; the old Dependabot `update-types`-filter juggling for digest-only bumps is gone.
- **Keeping the generated table honest across a bump:** a Renovate bump that changes a `FROM` tag or
  the `CST_VERSION` ARG makes `LINTERS.md` stale. `regen-linters.yml` regenerates it on the bump PR
  and commits it back with the lahaluhem-ci-bot App token (an App-token push re-triggers CI, so the
  `gen-linters.sh --check` drift gate clears on its own).

---

<a id="publish-gating"></a>
## Publishing is gated to `main` and manual dispatch

- **Publish on `main` pushes and `workflow_dispatch`; pull requests build-validate without
  pushing.** The consumer tag (`:latest`) is shared, so gating publishing keeps every branch from
  clobbering it, while PRs still validate both arches and a deliberate manual dispatch can
  publish/verify a branch.
- **Verification:** a publish is only "done" once `docker manifest inspect <ref>` shows both
  `linux/amd64` and `linux/arm64`. Never report success without it.
