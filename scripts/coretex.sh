#!/usr/bin/env bash
# coretex — CLI for the NETCASE skills repo.
#
# Usage:
#   coretex install [<profile>]   install all sources in profiles/<profile>.txt
#                                 (no argument → pick from a list)
#   coretex status                list installed skills: global, then project
#   coretex --help
#
# `install` is a thin wrapper around scripts/install.sh.
# `status` needs `jq` (preinstalled on macOS at /usr/bin/jq).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
PROFILES_DIR="$(dirname "$SCRIPT_DIR")/profiles"

list_profiles() {
  ls "$PROFILES_DIR"/*.txt 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.txt$//'
}

usage() {
  cat <<EOF
coretex — NETCASE skills CLI

  coretex install [<profile>]   install all sources from profiles/<profile>.txt
                                (no <profile> → choose from a list)
  coretex status                list installed skills (global, then project)
  coretex --help

Available profiles: $(list_profiles | paste -sd' ' -)
EOF
}

# ── install ──────────────────────────────────────────────────────
pick_profile() {
  # Prints the chosen profile name to stdout; menu + prompt go to stderr.
  local profiles=() p i=1 choice
  while IFS= read -r p; do profiles+=("$p"); done < <(list_profiles)
  if [[ ${#profiles[@]} -eq 0 ]]; then
    echo "No profiles found in $PROFILES_DIR" >&2
    exit 1
  fi
  echo "Available profiles:" >&2
  for p in "${profiles[@]}"; do
    printf "  %d) %s\n" "$i" "$p" >&2
    i=$((i + 1))
  done
  printf "Pick a profile [1-%d] (q to quit): " "${#profiles[@]}" >&2
  read -r choice || exit 0
  [[ "$choice" =~ ^[qQ]$ || -z "$choice" ]] && exit 0
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#profiles[@]} )); then
    echo "Invalid choice: $choice" >&2
    exit 1
  fi
  echo "${profiles[$((choice - 1))]}"
}

cmd_install() {
  local profile="${1:-}"
  if [[ -z "$profile" ]]; then
    profile="$(pick_profile)"
  fi
  if [[ ! -f "$PROFILES_DIR/$profile.txt" ]]; then
    echo "no such profile: $profile  (have: $(list_profiles | paste -sd' ' -))" >&2
    exit 1
  fi
  bash "$INSTALL_SH" "$profile"
}

# ── status ───────────────────────────────────────────────────────
need_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "coretex status needs 'jq' — install with: brew install jq" >&2
    exit 1
  }
}

# Read TSV from stdin (first line = header), print an indented, aligned
# table with a rule under the header spanning the widest row.
fmt_table() {
  local formatted maxw rule
  formatted="$(column -t -s$'\t')"
  [[ -z "$formatted" ]] && { echo "  (none)"; return; }
  maxw="$(printf '%s\n' "$formatted" | awk '{ if (length > m) m = length } END { print m+0 }')"
  rule="$(printf '%*s' "$maxw" '' | tr ' ' '─')"
  { printf '%s\n' "$formatted" | head -1; printf '%s\n' "$rule"; printf '%s\n' "$formatted" | tail -n +2; } | sed 's/^/  /'
}

print_global() {
  local json
  json="$(npx -y skills list --global --json 2>/dev/null || echo '[]')"
  if [[ "$(echo "$json" | jq 'length')" -eq 0 ]]; then echo "  (none)"; return; fi
  {
    printf 'NAME\tPATH\tAGENTS\n'
    echo "$json" | jq -r '
      .[] | [ .name,
              (.path | sub("^"+env.HOME; "~")),
              ( if ((.agents // []) | length) == 0 then "—" else (.agents | join(", ")) end ) ] | @tsv'
  } | fmt_table
}

print_project() {
  local json
  json="$(npx -y skills list --json 2>/dev/null || echo '[]')"
  if [[ "$(echo "$json" | jq 'length')" -eq 0 ]]; then echo "  (none)"; return; fi
  {
    printf 'NAME\tPROJECT\tPATH\tAGENTS\n'
    echo "$json" | jq -r '
      .[] | [ .name,
              ( try ( .path | capture("(?<r>.*)/(?:\\.claude/)?skills/[^/]+$").r | split("/") | last ) catch "?" ),
              (.path | sub("^"+env.HOME; "~")),
              ( if ((.agents // []) | length) == 0 then "—" else (.agents | join(", ")) end ) ] | @tsv'
  } | fmt_table
}

cmd_status() {
  need_jq
  echo "GLOBAL SKILLS  (~/.agents/skills/ + per-agent symlinks)"
  echo
  print_global
  echo
  echo "PROJECT SKILLS  (cwd: $(pwd | sed "s|^$HOME|~|"))"
  echo
  print_project
}

# ── dispatch ─────────────────────────────────────────────────────
case "${1:-}" in
  install)       shift; cmd_install "${1:-}" ;;
  status)        cmd_status ;;
  ""|--help|-h)  usage ;;
  *)
    echo "unknown command: $1" >&2
    echo >&2
    usage >&2
    exit 1 ;;
esac
