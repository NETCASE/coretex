# lib/manifest.sh — coretex manifest read/write.
#
# Sourced by scripts/coretex.sh. Does not run standalone.
#
# Manifest locations:
#   global  → ~/.coretex/manifest.json
#   project → <cwd>/.coretex.json    (per project directory)
#
# Exposes:
#   GLOBAL_MANIFEST          — absolute path of the global manifest
#   project_manifest_for <d> — manifest path for a given project root
#   manifest_path_for <s>    — global|project → corresponding manifest path
#   manifest_init <path>     — create empty {version:1,skills:{}} if absent
#   manifest_upsert ...      — write/refresh one skill entry (see below)
#   read_manifest <path>     — emit `.skills` object (or {} if missing)

GLOBAL_MANIFEST="$HOME/.coretex/manifest.json"

project_manifest_for() { echo "$1/.coretex.json"; }

manifest_path_for() {
  case "$1" in
    global)  echo "$GLOBAL_MANIFEST" ;;
    project) echo "$PWD/.coretex.json" ;;
  esac
}

manifest_init() {
  local path="$1"
  [[ -f "$path" ]] && return
  mkdir -p "$(dirname "$path")"
  echo '{"version":1,"skills":{}}' > "$path"
}

# manifest_upsert <path> <name> <provider> <source> <scope> <profile> <agents_json> <adopted_bool>
#
# `adopted` and `first_seen` are write-once — they capture the state at the
# moment coretex first saw the skill and must not flip on later re-installs.
# Implementation: the `//` fallback supplies a default object containing those
# two fields only when the entry is absent; the trailing `+` merge overwrites
# only the fields that should change every run.
manifest_upsert() {
  local path="$1" name="$2" provider="$3" source="$4" scope="$5" prof="$6" agents="$7" adopted="$8"
  local now tmp
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$(mktemp)"
  jq --arg name "$name" \
     --arg provider "$provider" \
     --arg source "$source" \
     --arg scope "$scope" \
     --arg prof "$prof" \
     --argjson agents "$agents" \
     --arg now "$now" \
     --argjson adopted "$adopted" '
     .skills[$name] = (
       (.skills[$name] // { adopted: $adopted, first_seen: $now })
       + { provider: $provider, source: $source, scope: $scope, profile: $prof,
           agents: $agents, updated_at: $now }
     )
  ' "$path" > "$tmp"
  mv "$tmp" "$path"
}

# Read manifest at $1 (defaults to {} if missing). Emits the .skills object.
read_manifest() {
  local path="$1"
  if [[ -f "$path" ]]; then jq -c '.skills // {}' "$path"; else echo '{}'; fi
}
