# lib/style.sh — terminal styling and table formatting primitives.
#
# Sourced by scripts/coretex.sh. Does not run standalone.
# Inherits set -euo pipefail from the calling script.
#
# Exposes:
#   BOLD, DIM, TEAL, RESET   — ANSI codes (empty when NO_COLOR / non-TTY)
#   RULE_W                   — header/footer rule width
#   COTX_BANNER              — the "CORETEX" ASCII wordmark
#   _hr                      — print a dim horizontal rule
#   print_header <cmd>       — banner + command label
#   print_footer             — version/size/date line
#   coretex_version          — "<branch>@<sha>" of the repo, or "?"
#   human_size <kb>          — format bytes-in-KB as "N KB / N.N MB / N.NN GB"
#   total_skill_size         — humanised sum of known skill directories
#   fmt_table                — TSV on stdin → aligned table with header rule
#   style_name_column        — colour col1 teal; blank repeated names
#   style_by_column          — colour BY token (coretex=teal, ext=dim)

# ── colour palette ───────────────────────────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'
  TEAL=$'\033[38;2;70;210;192m'   # #46d2c0
  RESET=$'\033[0m'
else
  BOLD='' DIM='' TEAL='' RESET=''
fi

RULE_W=76

_hr() {
  local w="${1:-$RULE_W}"
  printf '  %s%s%s\n' "$DIM" "$(printf '%*s' "$w" '' | tr ' ' '─')" "$RESET"
}

# figlet "ANSI Shadow", "CORETEX" — box-drawing glyphs only, no shell-special chars.
COTX_BANNER=" ██████╗ ██████╗ ██████╗ ███████╗████████╗███████╗██╗  ██╗
██╔════╝██╔═══██╗██╔══██╗██╔════╝╚══██╔══╝██╔════╝╚██╗██╔╝
██║     ██║   ██║██████╔╝█████╗     ██║   █████╗   ╚███╔╝
██║     ██║   ██║██╔══██╗██╔══╝     ██║   ██╔══╝   ██╔██╗
╚██████╗╚██████╔╝██║  ██║███████╗   ██║   ███████╗██╔╝ ██╗
 ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝"

coretex_version() {
  local branch sha
  branch="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)" || { echo "?"; return; }
  sha="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null)" || { echo "?"; return; }
  echo "${branch}@${sha}"
}

human_size() {
  awk -v kb="${1:-0}" 'BEGIN {
    if (kb < 1024)        printf "%d KB\n",   kb
    else if (kb < 1048576) printf "%.1f MB\n", kb/1024
    else                   printf "%.2f GB\n", kb/1048576
  }'
}

total_skill_size() {
  local total=0 d kb
  for d in "$HOME/.agents/skills" "./skills" "./.claude/skills"; do
    [[ -d "$d" ]] || continue
    kb="$(du -sk "$d" 2>/dev/null | awk '{print $1}')"
    if [[ -n "$kb" ]]; then total=$((total + kb)); fi
  done
  human_size "$total"
}

print_header() {
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

# Reads TSV from stdin (first line = header), prints an indented, aligned
# table with a rule under the header spanning the widest row.
fmt_table() {
  local formatted maxw rule
  formatted="$(column -t -s$'\t')"
  [[ -z "$formatted" ]] && { echo "  (none)"; return; }
  maxw="$(printf '%s\n' "$formatted" | awk -v min="$RULE_W" '{ if (length > m) m = length } END { print (m > min ? m : min) + 0 }')"
  rule="$(printf '%*s' "$maxw" '' | tr ' ' '─')"
  { printf '%s\n' "$formatted" | head -1; printf '%s\n' "$rule"; printf '%s\n' "$formatted" | tail -n +2; } | sed 's/^/  /'
}

# Style the NAME column of a fmt_table block: colour it teal, blank it on
# consecutive rows that repeat the previous row's name. NR<=2 = header + rule.
style_name_column() {
  awk -v t="$TEAL" -v r="$RESET" '
    NR<=2 { print; prev=""; next }
    {
      ws = ""; line = $0
      if (match(line, /^[[:space:]]+/)) { ws = substr(line, 1, RLENGTH); line = substr(line, RLENGTH+1) }
      if (match(line, /^[^[:space:]]+/)) {
        name = substr(line, 1, RLENGTH); rest = substr(line, RLENGTH+1)
        if (name == prev) {
          pad = ""; n = length(ws) + length(name)
          for (i=0; i<n; i++) pad = pad " "
          print pad rest
        } else { prev = name; print ws t name r rest }
      } else { print $0 }
    }'
}

# Colour the BY column (column 2, after style_name_column). NR<=2 = header + rule.
style_by_column() {
  awk -v t="$TEAL" -v d="$DIM" -v r="$RESET" '
    NR<=2 { print; next }
    {
      line = $0
      out = ""
      if (match(line, /^[[:space:]]+/)) { out = substr(line,1,RLENGTH); line = substr(line,RLENGTH+1) }
      if (match(line, /^[^[:space:]]+/)) {
        out = out substr(line,1,RLENGTH); line = substr(line,RLENGTH+1)
      }
      if (match(line, /^[[:space:]]+/)) { out = out substr(line,1,RLENGTH); line = substr(line,RLENGTH+1) }
      if (match(line, /^[^[:space:]]+/)) {
        by = substr(line,1,RLENGTH); line = substr(line,RLENGTH+1)
        if      (by == "coretex") out = out t by r
        else if (by == "ext")     out = out d by r
        else                      out = out by
      }
      print out line
    }'
}
