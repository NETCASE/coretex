#!/usr/bin/env bash
# coretex — CLI for the NETCASE skills repo.
#
# Usage:
#   coretex install [<profile>]   install all sources in profiles/<profile>.txt
#                                 (no argument → pick from a list)
#   coretex status                list installed skills: global, then project
#   coretex update                update all installed skills   (coming soon)
#   coretex remove                remove installed skills        (coming soon)
#   coretex --help
#
# `install` is a thin wrapper around scripts/install.sh.
# `status` needs `jq` (preinstalled on macOS at /usr/bin/jq).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
PROFILES_DIR="$(dirname "$SCRIPT_DIR")/profiles"

# ── style ────────────────────────────────────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'
  TEAL=$'\033[38;2;70;210;192m'   # #46d2c0
  RESET=$'\033[0m'
else
  BOLD='' DIM='' TEAL='' RESET=''
fi

RULE_W=58
_hr() {  # dim horizontal rule, 2-space indent; arg = width (default $RULE_W)
  local w="${1:-$RULE_W}"
  printf '  %s%s%s\n' "$DIM" "$(printf '%*s' "$w" '' | tr ' ' '─')" "$RESET"
}

# ASCII-art wordmark — box-drawing "coretex" (no shell-special chars).
COTX_BANNER="┌─┐┌─┐┬─┐┌─┐┌┬┐┌─┐─┐ ┬
│  │ │├┬┘├┤  │ ├┤ ┌┴┬┘
└─┘└─┘┴└─└─┘ ┴ └─┘┴ └─"

coretex_version() {  # <branch>@<short-sha>, or "?" if not a git repo
  local branch sha
  branch="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)" || { echo "?"; return; }
  sha="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null)" || { echo "?"; return; }
  echo "${branch}@${sha}"
}

human_size() {  # KB -> "N KB" / "N.N MB" / "N.NN GB"
  awk -v kb="${1:-0}" 'BEGIN {
    if (kb < 1024)        printf "%d KB\n",   kb
    else if (kb < 1048576) printf "%.1f MB\n", kb/1024
    else                   printf "%.2f GB\n", kb/1048576
  }'
}

total_skill_size() {  # sum of skill dirs that exist, humanised
  local total=0 d kb
  for d in "$HOME/.agents/skills" "./skills" "./.claude/skills"; do
    [[ -d "$d" ]] || continue
    kb="$(du -sk "$d" 2>/dev/null | awk '{print $1}')"
    if [[ -n "$kb" ]]; then total=$((total + kb)); fi
  done
  human_size "$total"
}

print_header() {  # arg = component name
  local comp="$1" banner
  comp="$(printf '%s' "${comp:0:1}" | tr '[:lower:]' '[:upper:]')${comp:1}"
  banner="$(printf '%s\n' "$COTX_BANNER" | sed 's/^/  /')"
  echo
  _hr
  printf '%s%s%s\n' "$TEAL" "$banner" "$RESET"
  echo
  printf '  %s%s%s\n' "$BOLD" "$comp" "$RESET"
  _hr
  echo
}

print_footer() {
  echo
  _hr
  printf '  %scoretex%s %s· %s · %s · %s%s\n' \
    "$TEAL" "$RESET" "$DIM" "$(coretex_version)" "$(total_skill_size)" "$(date +%Y-%m-%d)" "$RESET"
  _hr
  echo
  echo
}

# ── shared helpers ───────────────────────────────────────────────
list_profiles() {
  ls "$PROFILES_DIR"/*.txt 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.txt$//'
}

usage() {
  cat <<EOF
coretex — NETCASE skills CLI

  coretex install [<profile>]   install all sources from profiles/<profile>.txt
                                (no <profile> → choose from a list)
  coretex status                list installed skills (global, then project)
  coretex update                update all installed skills        (coming soon)
  coretex remove                remove installed skills            (coming soon)
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
  print_header "install"
  local profile="${1:-}"
  if [[ -z "$profile" ]]; then
    profile="$(pick_profile)"
  fi
  if [[ ! -f "$PROFILES_DIR/$profile.txt" ]]; then
    echo "no such profile: $profile  (have: $(list_profiles | paste -sd' ' -))" >&2
    exit 1
  fi
  bash "$INSTALL_SH" "$profile"
  print_footer
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

# Colour the first column of a fmt_table-formatted block. NR<=2 = header + rule.
colorize_first_column() {
  awk -v t="$TEAL" -v r="$RESET" 'NR<=2 {print; next} { sub(/^[[:space:]]*[^[:space:]]+/, t "&" r); print }'
}

print_global() {
  local json
  json="$(npx -y skills list --global --json 2>/dev/null || echo '[]')"
  if [[ "$(echo "$json" | jq 'length')" -eq 0 ]]; then echo "  $DIM(none)$RESET"; return; fi
  {
    printf 'NAME\tPATH\tAGENTS\n'
    echo "$json" | jq -r '
      .[] | [ .name,
              (.path | sub("^"+env.HOME; "~")),
              ( if ((.agents // []) | length) == 0 then "—" else (.agents | join(", ")) end ) ] | @tsv'
  } | fmt_table | colorize_first_column
}

print_project() {
  local json
  json="$(npx -y skills list --json 2>/dev/null || echo '[]')"
  if [[ "$(echo "$json" | jq 'length')" -eq 0 ]]; then echo "  $DIM(none)$RESET"; return; fi
  {
    printf 'NAME\tPROJECT\tPATH\tAGENTS\n'
    echo "$json" | jq -r '
      .[] | [ .name,
              ( try ( .path | capture("(?<r>.*)/(?:\\.claude/)?skills/[^/]+$").r | split("/") | last ) catch "?" ),
              (.path | sub("^"+env.HOME; "~")),
              ( if ((.agents // []) | length) == 0 then "—" else (.agents | join(", ")) end ) ] | @tsv'
  } | fmt_table | colorize_first_column
}

cmd_status() {
  need_jq
  print_header "status"
  printf '  %sGLOBAL%s  %s~/.agents/skills/%s\n\n' "$BOLD" "$RESET" "$DIM" "$RESET"
  print_global
  echo
  printf '  %sPROJECT%s  %s%s%s\n\n' "$BOLD" "$RESET" "$DIM" "$(pwd | sed "s|^$HOME|~|")" "$RESET"
  print_project
  print_footer
}

# ── placeholders ─────────────────────────────────────────────────
cmd_update() {
  print_header "update"
  printf '  %snot yet implemented%s\n' "$DIM" "$RESET"
  print_footer
}

cmd_remove() {
  print_header "remove"
  printf '  %snot yet implemented%s\n' "$DIM" "$RESET"
  print_footer
}

# ── dispatch ─────────────────────────────────────────────────────
case "${1:-}" in
  install)       shift; cmd_install "${1:-}" ;;
  status)        cmd_status ;;
  update)        cmd_update ;;
  remove)        cmd_remove ;;
  ""|--help|-h)  usage ;;
  *)
    echo "unknown command: $1" >&2
    echo >&2
    usage >&2
    exit 1 ;;
esac
