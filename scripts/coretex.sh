#!/usr/bin/env bash
# coretex — CLI for the NETCASE skills repo.
#
# Usage:
#   coretex install [<profile>]   install all sources in profiles/<profile>.txt
#                                 (no argument → pick from a list)
#   coretex status                list installed skills: global, then project
#   coretex detect-agents         agents auto-detect would target
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

RULE_W=76
_hr() {  # dim horizontal rule, 2-space indent; arg = width (default $RULE_W)
  local w="${1:-$RULE_W}"
  printf '  %s%s%s\n' "$DIM" "$(printf '%*s' "$w" '' | tr ' ' '─')" "$RESET"
}

# ASCII-art wordmark — figlet "Big", "CoreTex" (mixed case). Quoted heredoc → all literal.
read -r -d '' COTX_BANNER <<'BANNER' || true
  _____                _______
 / ____|              |__   __|
| |       ___   _ __   ___    | |   ___ __   __
| |      / _ \ | '__| / _ \   | |  / _ \\ \ / /
| |____ | (_) || |   |  __/   | | |  __/ \ V /
 \_____| \___/ |_|    \___|   |_|  \___|  \_/
BANNER
COTX_BANNER="${COTX_BANNER%$'\n'}"

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

print_header() {  # arg = command name
  local cmd="$1" banner
  banner="$(printf '%s\n' "$COTX_BANNER" | sed 's/^/  /')"
  echo
  _hr
  echo
  printf '%s%s%s\n' "$TEAL" "$banner" "$RESET"
  echo
  _hr
  printf '  %scommand:%s %s%s%s\n' "$DIM" "$RESET" "$BOLD" "$cmd" "$RESET"
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
  coretex detect-agents         show which agents auto-detect would target
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
  # Rule spans the widest row, but never narrower than the header/footer rule.
  maxw="$(printf '%s\n' "$formatted" | awk -v min="$RULE_W" '{ if (length > m) m = length } END { print (m > min ? m : min) + 0 }')"
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
    printf 'NAME\tAGENTS\tPATH\n'
    echo "$json" | jq -r '
      .[] | [ .name,
              ( if ((.agents // []) | length) == 0 then "—" else (.agents | join(", ")) end ),
              (.path | sub("^"+env.HOME; "~")) ] | @tsv'
  } | fmt_table | colorize_first_column
}

# Project skills, grouped by the folder that contains them.
# Excludes the canonical store (~/.agents/skills/) and per-agent dirs (~/.<agent>/skills/),
# which belong to the "Globally installed" section.
print_folders() {
  local json rows
  json="$(npx -y skills list --json 2>/dev/null || echo '[]')"
  rows="$(echo "$json" | jq -r --arg home "$HOME" '
    .[]
    | (.path | ltrimstr($home + "/")) as $rest
    | select(($rest | test("^\\.[^/]+/skills/")) | not)         # drop ~/.<agent>/skills/ installs
    | select(.path | test("/(?:\\.claude/)?skills/[^/]+$"))
    | (.path | capture("(?<root>.*?)/(?<rel>(?:\\.claude/)?skills/[^/]+)$")) as $m
    | [ $m.root,
        .name,
        ( if ((.agents // []) | length) == 0 then "—" else (.agents | join(", ")) end ),
        $m.rel ] | @tsv' 2>/dev/null)"
  if [[ -z "$rows" ]]; then echo "  $DIM(none)$RESET"; return; fi

  local roots root first=1 short name
  roots="$(printf '%s\n' "$rows" | cut -f1 | sort -u)"
  while IFS= read -r root; do
    [[ -z "$root" ]] && continue
    [[ $first -eq 0 ]] && echo
    first=0
    short="${root/#$HOME/~}"
    name="$(basename "$root")"
    printf '  %s▸%s %s%s%s  %s%s%s\n\n' "$TEAL" "$RESET" "$BOLD" "$name" "$RESET" "$DIM" "$short" "$RESET"
    {
      printf 'NAME\tAGENTS\tPATH\n'
      printf '%s\n' "$rows" | awk -F'\t' -v r="$root" 'BEGIN{OFS="\t"} $1==r { print $2,$3,$4 }'
    } | fmt_table | colorize_first_column
  done <<<"$roots"
}

cmd_status() {
  need_jq
  print_header "status"
  printf '  %sGlobally installed skills%s  %s~/.agents/skills/%s\n\n' "$BOLD" "$RESET" "$DIM" "$RESET"
  print_global
  echo
  printf '  %sFolder-local skills%s\n\n' "$BOLD" "$RESET"
  print_folders
  print_footer
}

# ── detect-agents ────────────────────────────────────────────────
# Known agent-id → home-relative directory. skills.sh auto-detects an agent
# when its directory exists; this map mirrors that for the common ones.
AGENT_DIRS="claude-code:.claude
qwen-code:.qwen
continue:.continue
cursor:.cursor
gemini-cli:.gemini
codex:.codex
windsurf:.windsurf
github-copilot:.config/github-copilot
opencode:.config/opencode
goose:.config/goose
amp:.amp
cline:.cline
roo:.roo
kilo:.kilo
kode:.kode
codebuddy:.codebuddy
trae:.trae
warp:.warp
junie:.junie
firebender:.firebender
aider-desk:.aider-desk
crush:.crush
mux:.mux
openhands:.openhands
kimi-cli:.kimi"

cmd_detect_agents() {
  print_header "detect-agents"
  printf '  %sAgents whose directory exists under your home — `coretex install` targets all of these:%s\n\n' "$DIM" "$RESET"

  local rows="" id dir
  while IFS=: read -r id dir; do
    [[ -d "$HOME/$dir" ]] && rows+="$id"$'\t'"~/$dir"$'\n'
  done <<<"$AGENT_DIRS"

  if [[ -z "$rows" ]]; then
    echo "  $DIM(none detected)$RESET"
  else
    { printf 'AGENT\tDIRECTORY\n'; printf '%s' "$rows"; } | fmt_table | colorize_first_column
  fi

  echo
  printf '  %sNote: this mirrors the skills.sh directory-presence heuristic. A few agents are\n' "$DIM"
  printf '  detected via editor plugins or other markers this scan does not check (e.g. some\n'
  printf '  GitHub Copilot setups) — those still get installed by `coretex install`. To target\n'
  printf '  a specific agent only:  npx skills add <repo> -a <agent-id>%s\n' "$RESET"
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
  install)        shift; cmd_install "${1:-}" ;;
  status)         cmd_status ;;
  detect-agents)  cmd_detect_agents ;;
  update)         cmd_update ;;
  remove)         cmd_remove ;;
  ""|--help|-h)   usage ;;
  *)
    echo "unknown command: $1" >&2
    echo >&2
    usage >&2
    exit 1 ;;
esac
