#!/usr/bin/env bash
# install.sh — install skills listed in a profile, with coretex tracking.
#
# Usage:
#   bash scripts/install.sh <profile>
#
# Reads profiles/<profile>.json, runs `npx skills add` per source, and updates
# the coretex manifest:
#   global scope  →  ~/.coretex/manifest.json
#   project scope →  <cwd>/.coretex.json
#
# Source schema (one entry per element of profile.sources):
#   source   string                 required (see "source formats" below)
#   scope    "global" | "project"   required
#   skills   ["a","b"]              optional (omit = whole source)
#   agents   ["x","y"]              optional (omit = auto-detect / CORETEX_AGENTS)
#
# Source formats — provider is detected from the string itself:
#   "owner/name"                 → github (resolved via skills.sh registry)
#   "https://…", "http://…",
#   "git://…", "ssh://…", "git@…"  → git (direct clone, bypasses registry)
#   "/abs/path", "~/rel",
#   "./rel", "../rel"            → local (filesystem)
#
# Env vars:
#   CORETEX_AGENTS=claude-code,qwen   default agents for sources without
#                                     their own `agents` field.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROFILES_DIR="$REPO_ROOT/profiles"

# ── arg validation ───────────────────────────────────────────────
profile="${1:-}"
if [[ -z "$profile" ]]; then
  echo "Usage: bash scripts/install.sh <profile>" >&2
  echo "" >&2
  echo "Available profiles:" >&2
  for f in "$PROFILES_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    echo "  - $(basename "$f" .json)" >&2
  done
  exit 1
fi

profile_file="$PROFILES_DIR/${profile}.json"
if [[ ! -f "$profile_file" ]]; then
  echo "Profile not found: $profile_file" >&2
  exit 1
fi

# ── dependencies ─────────────────────────────────────────────────
for tool in npx jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    case "$tool" in
      npx) echo "npx not found. Install Node.js (https://nodejs.org) first." >&2 ;;
      jq)  echo "jq not found. Install with: brew install jq" >&2 ;;
    esac
    exit 1
  }
done

jq -e . "$profile_file" >/dev/null || {
  echo "Invalid JSON in $profile_file" >&2
  exit 1
}

# ── manifest helpers ─────────────────────────────────────────────
manifest_path_for() {
  case "$1" in
    global)  echo "$HOME/.coretex/manifest.json" ;;
    project) echo "$PWD/.coretex.json" ;;
  esac
}

manifest_init() {
  local path="$1"
  [[ -f "$path" ]] && return
  mkdir -p "$(dirname "$path")"
  echo '{"version":1,"skills":{}}' > "$path"
}

# manifest_upsert <manifest_path> <skill_name> <provider> <source> <scope> <profile> <agents_json> <adopted_bool>
# `adopted` and `first_seen` are write-once — they capture the state at the
# moment coretex first saw the skill and must not flip on later re-installs.
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

# ── skill snapshot helpers ───────────────────────────────────────
snapshot_global() {
  npx -y skills list --global --json 2>/dev/null || echo '[]'
}

snapshot_project() {
  # Skills installed under $PWD (excludes the global ~/.agents store).
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

# ── source resolution ────────────────────────────────────────────
# Reads one source object (compact JSON), echoes "<provider>\t<resolved>"
# where <resolved> is the string passed to `skills add`. The provider is
# inferred from the source string itself. Returns non-zero on bad input.
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
      # Expand ~ → $HOME.
      case "$resolved" in
        "~"|"~/"*) resolved="${HOME}${resolved#\~}" ;;
      esac
      # Resolve relative paths to absolute.
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
      # Single slash + no whitespace; reject paths-with-more-slashes silently here
      # (they'd be local without a leading ./, which we don't accept implicitly).
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

# ── main install loop ────────────────────────────────────────────
echo "Installing skills from profile: $profile"
echo "Source: $profile_file"
echo

count=0
while IFS= read -r src; do
  [[ -z "$src" ]] && continue
  scope="$(jq -r '.scope // "global"' <<<"$src")"

  case "$scope" in
    global|project) ;;
    *) echo "  ! Unknown scope '$scope' — skipping: $src" >&2; continue ;;
  esac

  # Provider → effective source string passed to `skills add`.
  resolved_line="$(resolve_source "$src")" || continue
  provider="${resolved_line%%	*}"
  source_str="${resolved_line#*	}"

  skills_json="$(jq -c '.skills // []' <<<"$src")"
  agents_json="$(jq -c '.agents // []' <<<"$src")"

  scope_flag=""
  [[ "$scope" == "global" ]] && scope_flag="-g"

  # Build skill / agent CLI arg arrays.
  # `--skill` and `-a` are variadic → put `--skill` LAST so it can't swallow
  # other flags; `-a` must come BEFORE `--skill` so it stops at the boundary.
  skill_args=()
  agent_args=()
  if [[ "$(jq 'length' <<<"$skills_json")" -gt 0 ]]; then
    skill_args=(--skill)
    while IFS= read -r s; do skill_args+=("$s"); done < <(jq -r '.[]' <<<"$skills_json")
  fi
  if [[ "$(jq 'length' <<<"$agents_json")" -gt 0 ]]; then
    agent_args=(-a)
    while IFS= read -r a; do agent_args+=("$a"); done < <(jq -r '.[]' <<<"$agents_json")
  elif [[ -n "${CORETEX_AGENTS:-}" ]]; then
    agent_args=(-a)
    IFS=',' read -ra _a <<<"$CORETEX_AGENTS"
    for a in "${_a[@]}"; do agent_args+=("$a"); done
  fi

  desc=" [$provider]"
  [[ ${#skill_args[@]} -gt 0 ]] && desc+=" [skills: $(jq -r 'join(", ")' <<<"$skills_json")]"
  if [[ ${#agent_args[@]} -gt 0 ]]; then
    if [[ "$(jq 'length' <<<"$agents_json")" -gt 0 ]]; then
      desc+=" [agents: $(jq -r 'join(", ")' <<<"$agents_json")]"
    else
      desc+=" [agents: ${CORETEX_AGENTS}]"
    fi
  fi
  echo "→ $source_str ($scope)$desc"

  before="$(snapshot_for_scope "$scope")"

  # </dev/null prevents npx from consuming the profile file via stdin.
  npx -y skills add "$source_str" $scope_flag -y \
    ${agent_args[@]+"${agent_args[@]}"} \
    ${skill_args[@]+"${skill_args[@]}"} </dev/null

  after="$(snapshot_for_scope "$scope")"

  manifest="$(manifest_path_for "$scope")"
  manifest_init "$manifest"

  # Decide which skill names to track in the manifest.
  # 1. Explicit `skills` list → track exactly those.
  # 2. Whole repo → diff after - before = new skills. If nothing new (re-run),
  #    fall back to all skills present after, since we can't otherwise tell
  #    which ones belong to this repo.
  names_to_track=()
  if [[ "$(jq 'length' <<<"$skills_json")" -gt 0 ]]; then
    while IFS= read -r n; do names_to_track+=("$n"); done < <(jq -r '.[]' <<<"$skills_json")
  else
    while IFS= read -r n; do names_to_track+=("$n"); done < <(
      jq -r --argjson b "$before" --argjson a "$after" \
        '([$a[].name] - [$b[].name]) | .[]' <<<null
    )
    if [[ ${#names_to_track[@]} -eq 0 ]]; then
      # Re-run with nothing new: adopt every skill currently in this scope.
      while IFS= read -r n; do names_to_track+=("$n"); done < <(jq -r '.[].name' <<<"$after")
    fi
  fi

  before_names_json="$(jq '[.[].name]' <<<"$before")"
  tracked=0
  for name in "${names_to_track[@]}"; do
    [[ -z "$name" ]] && continue
    # Real agents for this skill from the post-install snapshot.
    actual_agents="$(jq -c --arg n "$name" \
      'map(select(.name == $n)) | (.[0].agents // [])' <<<"$after")"
    # If the skill is not in `after`, the install failed — skip the manifest entry.
    if [[ -z "$actual_agents" || "$actual_agents" == "null" ]] || \
       [[ "$(jq --arg n "$name" 'any(.name == $n)' <<<"$after")" != "true" ]]; then
      continue
    fi
    was_before="$(jq --arg n "$name" 'index($n) != null' <<<"$before_names_json")"
    manifest_upsert "$manifest" "$name" "$provider" "$source_str" "$scope" "$profile" "$actual_agents" "$was_before"
    tracked=$((tracked + 1))
  done

  echo "  tracked $tracked skill(s) in $(echo "$manifest" | sed "s|^$HOME|~|")"
  echo
  count=$((count + 1))
done < <(jq -c '.sources[]' "$profile_file")

if [[ $count -eq 0 ]]; then
  echo "No sources in profile '$profile'."
else
  echo "✓ Processed $count source(s) from profile '$profile'."
  echo "  Run 'coretex status' to see installed skills."
fi
