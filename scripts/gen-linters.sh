#!/usr/bin/env bash
#
# Generate the linter table in LINTERS.md from the Dockerfile.
#
# The Dockerfile is the single source of truth. For each Lane-1 tool the version and
# upstream image come from its `FROM <img>:<tag>@<digest> AS <name>` line; the descriptive
# bits (what it lints, its repo link) come from a `# linter:` annotation directly above
# that FROM:
#
#     # linter: lints: Dockerfiles | repo: https://github.com/hadolint/hadolint
#     FROM hadolint/hadolint:v2.14.0-alpine@sha256:... AS hadolint
#
# A Lane-2 tool (apt/npm/pip, no FROM) carries its own name + version in the annotation:
#
#     # linter: tool: yamllint | version: 1.35.1 | lane: 2 | lints: YAML | repo: https://...
#
# The table is written between the markers in LINTERS.md; the rest of that file is
# hand-written and left untouched.
#
# Usage:
#   ./scripts/gen-linters.sh           rewrite the table in LINTERS.md
#   ./scripts/gen-linters.sh --check   exit non-zero if LINTERS.md is stale; write nothing
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

dockerfile='Dockerfile'
manifest='LINTERS.md'
start='<!-- linters:start -->'
end='<!-- linters:end -->'

tmp_table=''
tmp_out=''
cleanup() {
  if [ -n "${tmp_table:-}" ]; then rm -f "$tmp_table"; fi
  if [ -n "${tmp_out:-}" ]; then rm -f "$tmp_out"; fi
}
trap cleanup EXIT

# Emit the markdown table (header + one row per tool) from the Dockerfile to stdout.
gen_table() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function field(ann, key,   n, parts, i, kv, p, k) {
      n = split(ann, parts, "|")
      for (i = 1; i <= n; i++) {
        kv = parts[i]; p = index(kv, ":")
        if (p > 0) {
          k = trim(substr(kv, 1, p - 1))
          if (k == key) return trim(substr(kv, p + 1))
        }
      }
      return ""
    }
    function lane_label(l) {
      if (l == "1") return "1 (static)"
      if (l == "2") return "2 (pkg)"
      return l
    }
    function emit(name, ver, lane, lints, repo, img) {
      printf "| [%s](%s) | %s | %s | %s | `%s` |\n", name, repo, ver, lane_label(lane), lints, img
    }
    BEGIN {
      print "| Tool | Version | Lane | Lints | Upstream image |"
      print "| --- | --- | --- | --- | --- |"
      pending = 0
    }
    /^[[:space:]]*#[[:space:]]*linter:/ {
      ann = $0
      sub(/^[[:space:]]*#[[:space:]]*linter:[[:space:]]*/, "", ann)
      if (field(ann, "tool") != "") {
        lane = field(ann, "lane"); if (lane == "") lane = "2"
        emit(field(ann, "tool"), field(ann, "version"), lane, field(ann, "lints"), field(ann, "repo"), field(ann, "image"))
        pending = 0
      } else {
        p_lints = field(ann, "lints"); p_repo = field(ann, "repo")
        pending = 1
      }
      next
    }
    pending && /^[[:space:]]*FROM[[:space:]]/ {
      ref = $2
      amp = index(ref, "@")
      imgtag = (amp > 0) ? substr(ref, 1, amp - 1) : ref
      lc = 0
      for (i = length(imgtag); i >= 1; i--) if (substr(imgtag, i, 1) == ":") { lc = i; break }
      tag = (lc > 0) ? substr(imgtag, lc + 1) : ""
      name = ""
      for (i = 3; i < NF; i++) if (toupper($i) == "AS") { name = $(i + 1); break }
      emit(name, tag, "1", p_lints, p_repo, imgtag)
      pending = 0
    }
  ' "$dockerfile"
}

# Print LINTERS.md with the table region replaced by a freshly generated table.
render() {
  tmp_table="$(mktemp)"
  gen_table >"$tmp_table"
  awk -v tablefile="$tmp_table" -v s="$start" -v e="$end" '
    BEGIN { while ((getline line < tablefile) > 0) tbl = tbl line "\n"; sub(/\n$/, "", tbl) }
    index($0, s) { print; print tbl; skip = 1; next }
    index($0, e) { skip = 0; print; next }
    skip { next }
    { print }
  ' "$manifest"
}

main() {
  if ! grep -qF "$start" "$manifest" || ! grep -qF "$end" "$manifest"; then
    printf 'error: %s is missing the "%s" / "%s" markers\n' "$manifest" "$start" "$end" >&2
    exit 2
  fi

  tmp_out="$(mktemp)"
  render >"$tmp_out"

  if [ "${1:-}" = '--check' ]; then
    if diff -u "$manifest" "$tmp_out" >/dev/null; then
      echo "LINTERS.md is up to date"
    else
      echo "LINTERS.md is stale; run ./scripts/gen-linters.sh" >&2
      diff -u "$manifest" "$tmp_out" >&2 || true
      exit 1
    fi
  else
    cat "$tmp_out" >"$manifest"
    echo "updated $manifest"
  fi
}

main "$@"
