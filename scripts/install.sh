#!/usr/bin/env bash
# Install all skills listed in a profile.
#
# Usage:
#   bash scripts/install.sh <profile>
#
# Examples:
#   bash scripts/install.sh system
#   bash scripts/install.sh dev
#
# Profile files live in profiles/<name>.txt and contain one entry per line:
#   <owner/repo> [global|project]
#
# Lines starting with `#` and blank lines are ignored.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROFILES_DIR="$REPO_ROOT/profiles"

profile="${1:-}"

if [[ -z "$profile" ]]; then
  echo "Usage: bash scripts/install.sh <profile>" >&2
  echo "" >&2
  echo "Available profiles:" >&2
  for f in "$PROFILES_DIR"/*.txt; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .txt)"
    echo "  - $name" >&2
  done
  exit 1
fi

profile_file="$PROFILES_DIR/${profile}.txt"

if [[ ! -f "$profile_file" ]]; then
  echo "Profile not found: $profile_file" >&2
  exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "npx not found. Install Node.js (https://nodejs.org) first." >&2
  exit 1
fi

# Optional agent override via env var (comma-separated).
# Default: pass nothing → `npx skills add` auto-detects every installed agent
# (~/.claude, ~/.qwen, ~/.continue, …) and targets all of them.
agent_args=()
if [[ -n "${CORETEX_AGENTS:-}" ]]; then
  IFS=',' read -ra _agents <<<"$CORETEX_AGENTS"
  agent_args=(-a "${_agents[@]}")
fi

echo "Installing skills from profile: $profile"
echo "Source: $profile_file"
[[ ${#agent_args[@]} -gt 0 ]] && echo "Agents: ${_agents[*]}" || echo "Agents: auto-detect"
echo

count=0
while IFS= read -r line || [[ -n "$line" ]]; do
  # Strip inline comments
  line="${line%%#*}"
  # Trim whitespace
  line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -z "$line" ]] && continue

  read -r repo scope rest <<<"$line"
  scope="${scope:-global}"

  scope_flag=""
  case "$scope" in
    global)  scope_flag="-g" ;;
    project) scope_flag="" ;;
    *)
      echo "  ! Unknown scope '$scope' for $repo (expected global|project) — skipping" >&2
      continue
      ;;
  esac

  if [[ -n "$rest" ]]; then
    echo "→ $repo ($scope) [$rest]"
  else
    echo "→ $repo ($scope)"
  fi
  # NOTE: source must come BEFORE -a/--agent because -a is variadic
  # and will swallow following positional arguments.
  # $rest is intentionally unquoted so extra flags split into separate args.
  # </dev/null prevents npx from consuming our profile file via stdin (kills the loop otherwise).
  # No -a by default → CLI auto-detects every installed agent dir and targets all of them.
  npx -y skills add "$repo" $scope_flag ${agent_args[@]+"${agent_args[@]}"} $rest -y </dev/null
  echo
  count=$((count + 1))
done <"$profile_file"

if [[ $count -eq 0 ]]; then
  echo "No active entries in profile '$profile' (all commented out or empty)."
else
  echo "✓ Installed $count source(s) from profile '$profile'."
  echo "  Run 'npx skills list' to see installed skills."
fi
