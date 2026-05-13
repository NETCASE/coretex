# lib/source.sh — source string resolution + skills.sh CLI snapshots.
#
# Sourced by scripts/coretex.sh. Does not run standalone.
#
# Exposes:
#   resolve_source <src_json>   — parse one source object, echo "<provider>\t<resolved>"
#   snapshot_global             — JSON array of globally installed skills
#   snapshot_project            — JSON array of skills under $PWD
#   snapshot_for_scope <scope>  — dispatcher: global → snapshot_global, etc.

# Reads one source object (compact JSON) and prints "<provider>\t<resolved>"
# where <resolved> is the string passed to `skills add`. Provider is detected
# from the source string itself — see ARCHITECTURE.md "Provider detection".
# Returns non-zero on bad input.
resolve_source() {
  local src="$1"
  local s resolved provider
  s="$(jq -r '.source // ""' <<<"$src")"
  [[ -z "$s" ]] && { echo "  ! source entry missing .source: $src" >&2; return 1; }

  case "$s" in
    # Local filesystem paths.
    "/"*|"~"|"~/"*|"./"*|"../"*)
      provider="local"
      resolved="$s"
      case "$resolved" in
        "~"|"~/"*) resolved="${HOME}${resolved#\~}" ;;
      esac
      [[ "$resolved" != /* ]] && resolved="$(cd "$resolved" 2>/dev/null && pwd)" || true
      [[ -n "$resolved" && -d "$resolved" ]] || {
        echo "  ! local source path does not exist: $s" >&2; return 1;
      }
      ;;
    # Explicit git URLs (any host, any protocol).
    http://*|https://*|git://*|ssh://*|git@*)
      provider="git"
      resolved="$s"
      ;;
    # owner/name → github via skills.sh registry.
    */*)
      if [[ "$s" =~ ^[^[:space:]/]+/[^[:space:]/]+$ ]]; then
        provider="github"
        resolved="$s"
      else
        echo "  ! source '$s' looks like a path — prefix with ./ for local sources" >&2
        return 1
      fi
      ;;
    *)
      echo "  ! unrecognized source format: '$s'" >&2
      echo "    expected: owner/name | https://… | git@… | /abs/path | ~/… | ./…" >&2
      return 1
      ;;
  esac

  printf '%s\t%s\n' "$provider" "$resolved"
}

snapshot_global() {
  npx -y skills list --global --json 2>/dev/null || echo '[]'
}

# Skills installed under $PWD (excludes the global ~/.agents store).
snapshot_project() {
  npx -y skills list --json 2>/dev/null \
    | jq --arg cwd "$PWD" '[.[] | select(.path | startswith($cwd + "/"))]' \
    2>/dev/null || echo '[]'
}

snapshot_for_scope() {
  case "$1" in
    global)  snapshot_global ;;
    project) snapshot_project ;;
  esac
}
