#!/usr/bin/env bash
# coretex — CLI for the NETCASE skills repo.
#
# Usage:
#   coretex install <profile>   install all sources listed in profiles/<profile>.txt
#   coretex status              list installed skills: global first, then project
#   coretex <profile>           shorthand for `coretex install <profile>`
#   coretex --help
#
# `install` is a thin wrapper around scripts/install.sh.
# `status` needs `jq` (preinstalled on macOS at /usr/bin/jq).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
PROFILES_DIR="$(dirname "$SCRIPT_DIR")/profiles"

profiles_list() {
  ls "$PROFILES_DIR"/*.txt 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.txt$//' | paste -sd' ' -
}

usage() {
  cat <<EOF
coretex — NETCASE skills CLI

  coretex install <profile>   install all sources from profiles/<profile>.txt
  coretex status              list installed skills (global, then project)
  coretex <profile>           shorthand for: coretex install <profile>
  coretex --help

Available profiles: $(profiles_list)
EOF
}

# ── status ───────────────────────────────────────────────────────
_need_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "coretex status needs 'jq' — install with: brew install jq" >&2
    exit 1
  }
}

print_global() {
  local json
  json="$(npx -y skills list --global --json 2>/dev/null || echo '[]')"
  if [[ "$(echo "$json" | jq 'length')" -eq 0 ]]; then echo "  (none)"; return; fi
  echo "$json" | jq -r '
    .[] | [ .name,
            (.path | sub("^"+env.HOME; "~")),
            ((.agents // []) | join(", ")) ] | @tsv
  ' | while IFS=$'\t' read -r name path agents; do
    printf "  %-24s %s\n" "$name" "$path"
    [[ -n "$agents" ]] && printf "  %-24s   agents: %s\n" "" "$agents"
  done
}

print_project() {
  local json
  json="$(npx -y skills list --json 2>/dev/null || echo '[]')"
  if [[ "$(echo "$json" | jq 'length')" -eq 0 ]]; then echo "  (none)"; return; fi
  echo "$json" | jq -r '
    .[] | [ .name,
            (.path | sub("^"+env.HOME; "~")),
            ( try ( .path | capture("(?<r>.*)/(?:\\.claude/)?skills/[^/]+$").r | split("/") | last )
              catch "?" ),
            ((.agents // []) | join(", ")) ] | @tsv
  ' | while IFS=$'\t' read -r name path proj agents; do
    printf "  %-24s %s\n" "$name" "$path"
    printf "  %-24s   project: %s%s\n" "" "${proj:-?}" "${agents:+ | agents: $agents}"
  done
}

cmd_status() {
  _need_jq
  echo "Global skills  (canonical store + per-agent symlinks)"
  print_global
  echo
  echo "Project skills  (cwd: $(pwd | sed "s|^$HOME|~|"))"
  print_project
}

# ── dispatch ─────────────────────────────────────────────────────
case "${1:-}" in
  ""|--help|-h)
    usage ;;
  install)
    shift
    [[ -n "${1:-}" ]] || { echo "usage: coretex install <profile>" >&2; exit 1; }
    [[ -f "$PROFILES_DIR/$1.txt" ]] || { echo "no such profile: $1  (have: $(profiles_list))" >&2; exit 1; }
    bash "$INSTALL_SH" "$1" ;;
  status)
    cmd_status ;;
  *)
    # Back-compat: bare profile name → install it.
    if [[ -f "$PROFILES_DIR/$1.txt" ]]; then
      bash "$INSTALL_SH" "$1"
    else
      echo "unknown command or profile: $1" >&2
      usage >&2
      exit 1
    fi ;;
esac
