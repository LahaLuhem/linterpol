# CLAUDE.md — `Linterpol`

Claude-Code-specific guidance. Project facts, stack, repo layout, and hard rules live in
[AGENTS.md](./AGENTS.md); design rationale lives in [`APPENDIX.md`](./APPENDIX.md).
**Read AGENTS.md first.**

## Role & context

You're assisting with **Linterpol**: a repo whose job is to **build and publish** one small,
multi-arch (`amd64` + `arm64`) Docker image bundling CI lint/check tools, to
`ghcr.io/lahaluhem`, for reuse across the author's repos. *How or where the image is consumed is
out of scope.* The image is published (multi-arch) at `ghcr.io/lahaluhem/linterpol:latest`; a
republish is needed whenever the tool set changes. Treat the user as technical and direct.
Published images are outward-facing, so publishing is a confirm-first action.

## Communication

- **Concise.** No "here's what I just did" recap; the diff speaks.
- **Explain the *why*** when recommending; the *what* is in the diff.
- Reference files as `path:line`, markdown links when you can.
- Flag anything that changes *what gets published* (tags, registry, platforms, the bundled tool
  set) loudly and early.

## How the user wants work driven

- **Plan first, then execute incrementally.** For any non-trivial task, present a written plan and
  **wait for review** before editing. Then do **one sub-task at a time**, pausing for review
  between them. Don't one-shot a multi-step change.
- **Ask before choosing between defensible alternatives.** List options with trade-offs, mark your
  recommendation with `★`, then wait. Obvious single-answer fixes: just do them.
- **Surface findings that change the premise** before building on them.

## VCS — the user manages git

- **Do NOT commit, push, branch, merge, rebase, tag, or otherwise mutate git** unless the user
  explicitly asks *in that message*. Make changes in the working tree and let the user commit;
  suggest a message if something is commit-worthy.
- Never `git add -A`; never `--force` / `reset --hard` / `branch -D` / `clean -fd`.

## Tool preferences

- **Read / Edit / Grep / Glob** over `cat` / `sed` / `grep` / `find`.
- **Bash** for `docker` / `docker buildx`, `gh`, `curl`, and (only when asked) `git`.
- **Lint workflow YAML with `actionlint`** before calling a workflow change done.
- **Verify action/tool/image versions against their registries before pinning** — never from
  memory.
- **The image dogfoods:** build it (`./scripts/build.sh`) and run it against this repo to validate a change
  to the tool set.
- **Agent / Explore** for wide, open-ended searches.

## Validating multi-arch

This is an Apple-Silicon host with OrbStack, so you can build `linux/arm64` natively and run the
tools, and build `linux/amd64` under emulation. All current tools ship native `arm64`. When adding
a tool, confirm it runs on **both** arches (`docker buildx imagetools inspect <ref>` for the
upstream; a quick `--platform` build to run it). The only emulated steps in the build itself are the
`container-structure-test` checksum-verify and the one-line `useradd`. Report what you verified and
what you did NOT.

## Definition of done

- **`actionlint` clean** on any touched workflow.
- **The image builds** for the affected arch(es) and `scripts/build.sh`'s self-check passes.
- **A publish is "done" only when `docker manifest inspect <ref>` shows BOTH `linux/amd64` and
  `linux/arm64`.** Never claim a multi-arch publish otherwise.
- Report outcomes faithfully: if CI hasn't run or you couldn't verify, say so.

## Auto-memory conventions for this project

- **`project`** — scope/constraints the user states aloud (the final name once chosen, the publish
  decision). Convert relative dates to absolute.
- **`feedback`** — corrections and validated non-obvious choices, with **Why** + **How to apply**.
- **`reference`** — external pointers (the GHCR package page, upstream tool repos, the consuming
  repos such as chrysalis).
- **Don't save** what the repo records (the Dockerfile shape, `LINTERS.md`, the lane pattern); re-
  derive it. Verify a named file/flag still exists before acting on a memory.

## Forbidden / confirm-first actions

- **Publishing the image** — anything that pushes to `ghcr.io/lahaluhem`, including a
  `workflow_dispatch` publish on a branch — is **confirm-first** (outward-facing).
- **Any git mutation** — see *VCS* above.
- **Hand-editing pinned digests in the `images/*/Dockerfile`s** (or a downloaded-binary
  `ARG <NAME>_VERSION` pin) — that's Renovate's job, except when you're adding or removing a tool.
- **Destructive Docker on shared state** (`docker system prune`, removing the user's images/volumes)
  — ask first.
