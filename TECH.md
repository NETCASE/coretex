# coretex — technical reference

Internal documentation for contributors (human or AI agent). Covers
architecture, data formats, algorithms, code layout, and invariants.
For end-user usage, see [README.md](README.md).

## 1 · Overview

`coretex` is a thin layer on top of the [skills.sh CLI](https://skills.sh).
It does three things the skills CLI alone doesn't:

1. **Bundles installs into versioned profiles** (JSON files in `profiles/`).
2. **Tracks which skills it manages** (per-scope manifests in
   `~/.coretex/manifest.json` and `<project>/.coretex.json`).
3. **Presents that state in a useful CLI** (`coretex install`, `status`,
   `detect-agents`, etc.).

All persistence is plain JSON. All logic is Bash + `jq`. There are no
Node dependencies of our own — we only invoke `npx skills` as a child
process.

### Components

```
coretex/
├── scripts/
│   ├── coretex.sh   ← dispatcher: pretty CLI; pure presentation
│   └── install.sh   ← the work: reads profiles, calls skills CLI,
│                      diffs snapshots, writes manifests
├── profiles/        ← <name>.json profile files (versioned, committed)
├── skills/          ← published skills (the *content* of this repo's
│                      role as a skill source — separate from the CLI)
├── README.md        ← end-user docs
└── TECH.md          ← this file
```

`coretex.sh` is purely a UX wrapper — banner, table formatting, BY column
colouring, profile picker. It delegates the actual install logic to
`install.sh`. They share zero state at runtime; the only handoff is
`bash install.sh <profile>` plus the manifest files on disk.

### Runtime dependencies

| Tool | Used for | Notes |
|---|---|---|
| `bash` ≥ 3.2 | both scripts | macOS ships 3.2; we avoid `mapfile`, `${var,,}`, etc. |
| `jq` | install.sh + status | Hard requirement. `brew install jq` on macOS. |
| `npx` / Node | invoking `skills add` / `skills list` | We use `npx -y skills` so users don't need a global install. |
| `git` | only for `git`-provider sources | Skills CLI handles the clone; we just hand it the URL. |

## 2 · Data formats

### 2.1 Profile (`profiles/<name>.json`)

```jsonc
{
  "name": "system",
  "description": "Base skills installed on every machine.",
  "sources": [
    { "source": "anthropics/skills", "scope": "global", "skills": ["skill-creator"], "agents": ["claude-code"] }
  ]
}
```

| Top-level field | Required | Notes |
|---|---|---|
| `name` | yes | Matches the filename stem. Informational; coretex doesn't validate it. |
| `description` | no | Used only for the profile picker (future). |
| `sources` | yes | Array of source objects (may be empty for stub profiles). |

Per source:

| Field | Required | Type | Notes |
|---|---|---|---|
| `source` | yes | string | See §2.2 for accepted formats. |
| `scope` | yes | `"global"` \| `"project"` | Anything else: source is skipped with a warning. |
| `skills` | no | string[] | When set, install just these. When absent, install the whole source. |
| `agents` | no | string[] | When set, overrides `CORETEX_AGENTS` env + the CLI's auto-detect. |

The same `source` may appear multiple times with different scope/skills
combinations — that's how you split a multi-skill repo across scopes
(see README "Install the same repo at two scopes").

### 2.2 Source string formats

The `source` field is parsed by [`resolve_source` in scripts/install.sh:133-179](scripts/install.sh#L133-L179).
Provider is detected from the leading characters of the string:

| Pattern | Provider | Passed to `skills add` as |
|---|---|---|
| `owner/name` (exactly one slash, no spaces) | `github` | unchanged — registered through skills.sh registry |
| `http://…` `https://…` `git://…` `ssh://…` `git@…` | `git` | unchanged — `skills add` invokes `git clone` |
| `/abs/path` `~/rel` `./rel` `../rel` | `local` | absolute path (after `~` and relative-path expansion) |

Strings that match `*/*` but have additional slashes (e.g. `foo/bar/baz`)
are rejected with an error suggesting `./` prefix — this prevents a
typo from silently being interpreted as a github source.

### 2.3 Manifests

Two manifests, same schema:

| File | Stores | When it's written |
|---|---|---|
| `~/.coretex/manifest.json` | global-scope skills | Whenever a source with `"scope": "global"` is processed. |
| `<cwd>/.coretex.json` | project-scope skills (one per project dir) | Whenever a source with `"scope": "project"` is processed. The path is `$PWD` at install time. |

Shape:

```jsonc
{
  "version": 1,
  "skills": {
    "skill-creator": {
      "source": "anthropics/skills",       // original source string from the profile
      "provider": "github",                // detected at resolve time
      "scope": "global",                   // "global" | "project"
      "profile": "system",                 // which profile installed it
      "agents": ["Claude Code", "Continue", "Qwen Code"],   // display names from `skills list`
      "first_seen": "2026-05-13T18:19:43Z", // ISO-8601 UTC; write-once
      "updated_at": "2026-05-13T18:19:46Z", // refreshed on every install run
      "adopted": true                       // write-once; see §3.3
    }
  }
}
```

The `version` field is reserved for future schema migrations.

## 3 · Algorithms

### 3.1 Install loop (`scripts/install.sh:181-`)

For each entry in `profile.sources`:

```
parse scope             → skip if not global/project
resolve_source          → { provider, resolved_source_string }  (§3.2)
build skill_args        → ["--skill", "a", "b", …]              (variadic)
build agent_args        → ["-a", "x", "y", …]                   (variadic)
                          precedence: per-source > CORETEX_AGENTS > auto-detect

before = snapshot_for_scope(scope)
npx skills add <resolved> [-g] [-y] [-a …] [--skill …]
after  = snapshot_for_scope(scope)

names_to_track =
   .skills array if profile entry had one
   else after.names - before.names
   else all of after  (re-run with nothing new → adopt everything)

for name in names_to_track:
   actual_agents = after[name].agents
   skip if name not present in after  (install failed silently)
   was_in_before = name ∈ before.names
   manifest_upsert(... adopted = was_in_before ...)
```

The `before`/`after` snapshots are JSON arrays returned by `npx skills
list [-g] --json`. They're filtered to the current `$PWD` for the
project scope so cross-project state doesn't leak in.

### 3.2 Provider detection (`resolve_source`)

Pure pattern match — no `git ls-remote`, no HTTP, no fallback chain.
The user picks the format; we detect from the prefix:

```bash
case "$s" in
  "/"*|"~"|"~/"*|"./"*|"../"*)            provider="local"  ;;
  http://*|https://*|git://*|ssh://*|git@*) provider="git"   ;;
  */*)  # owner/name only, exactly one slash
        [[ "$s" =~ ^[^[:space:]/]+/[^[:space:]/]+$ ]] && provider="github" ;;
  *)    error "unrecognized source format" ;;
esac
```

Detection runs once per source per install. The detected provider is
stored in the manifest (§2.3) so `coretex status` doesn't need to
re-parse on every read.

### 3.3 Manifest upsert with write-once fields

`manifest_upsert()` ([scripts/install.sh:88-108](scripts/install.sh#L88-L108))
must preserve `adopted` and `first_seen` across re-runs. Implementation:

```jq
.skills[$name] = (
  (.skills[$name] // { adopted: $adopted, first_seen: $now })
  + { provider: $provider, source: $source, scope: $scope, profile: $prof,
      agents: $agents, updated_at: $now }
)
```

Read carefully: the `//` fallback supplies a *default object* when the
key is missing. That default object contains `adopted` and `first_seen`
— so they're only set if the entry is new. The `+` merge that follows
overwrites only the fields that should change every run (`provider`,
`source`, `scope`, `profile`, `agents`, `updated_at`).

This means: a skill that was `adopted: true` at first contact will
*always* show as `adopt` in `coretex status`, even after a user manually
removes it (`npx skills remove`) and `coretex install` puts it back.
The flag is about origin, not current state.

### 3.4 `BY` column derivation (`scripts/coretex.sh`)

For each row produced by `npx skills list --json`, `coretex status`
looks up the skill name in the relevant manifest:

- Global skills (skills under `~/.agents/skills/` or per-agent dirs):
  check `~/.coretex/manifest.json`.
- Project skills (under any `<root>/.claude/skills/` or `<root>/skills/`
  that isn't an agent home dir): check `<root>/.coretex.json`.

The lookup is implemented in two `jq` expressions inside
[scripts/coretex.sh:print_global](scripts/coretex.sh#L258-L283) and
[scripts/coretex.sh:print_folders](scripts/coretex.sh#L288-L327):

```jq
( if $mani[$s.name] then
    if $mani[$s.name].adopted then "adopt" else "coretex" end
  else "ext" end ) as $by
```

The `by` value is then coloured by `style_by_column` (teal for coretex/adopt,
dim for ext) before the table is printed.

## 4 · CLI dispatcher (`coretex.sh`)

`coretex.sh` is a thin wrapper:

- `install [<profile>]` — picks a profile (numbered menu if no arg), then
  `bash install.sh <profile>`. Adds the banner/footer chrome.
- `status` — runs `npx skills list --json` twice (global + everything),
  filters, formats, applies the BY column.
- `detect-agents` — walks a hardcoded list of `~/.<agent>/` dirs and
  prints the ones that exist. Mirrors what skills.sh auto-detect targets.
- `update`, `remove` — placeholders; print "not yet implemented".

### Style primitives

| Helper | Purpose |
|---|---|
| `print_header <cmd>` / `print_footer` | The banner + horizontal rules + version footer. |
| `fmt_table` | Reads TSV from stdin, aligns columns via `column -t`, adds a rule under the header. |
| `style_name_column` | Colours the first column teal; blanks repeated names in consecutive rows. |
| `style_by_column` | Colours the BY token (coretex/adopt teal, ext dim) without breaking column alignment. |

All colour output is gated on `[[ -t 1 && -z "${NO_COLOR:-}" ]]` so
piping to a file or running under CI strips ANSI codes.

### Profile picker

`pick_profile` ([scripts/coretex.sh:131-152](scripts/coretex.sh#L131-L152)) reads available profiles via
`list_profiles`, prompts with a numbered list, and validates the
selection. Quits cleanly on `q` or empty input.

## 5 · Invariants and edge cases

| Invariant | Why it matters |
|---|---|
| `adopted` and `first_seen` never change after first write | The audit trail would lie if they could flip. |
| Manifest is only written when `skills add` actually puts the skill on disk | Failed installs (auth, network, missing SKILL.md) leave no record. The post-install snapshot is the source of truth. |
| The before/after diff falls back to "track everything in `after`" on a re-run with no changes | Adopts pre-existing skills cleanly on the first run after manifest deletion. |
| `provider` is detected, not user-supplied | Removes one entire category of user errors (typos in `provider` field). |
| Project manifest goes to `$PWD`, not the profile's location | A profile is portable; the manifest is the project's. |

### Edge case: ambiguous source strings

`foo/bar/baz` is rejected (looks like a path without `./`). `~bar` is
treated as a relative path (no slash). Empty `source` errors with a
specific message.

### Edge case: empty `sources` array

`thinktank.json` and `web-design.json` ship empty. install.sh prints
"No sources in profile" and exits 0 — not an error.

### Edge case: re-run after manual removal

Manual `npx skills remove X` doesn't touch the manifest. Next
`coretex install` re-installs X; the upsert keeps `adopted` as it was
(write-once), updates `updated_at`.

### Edge case: profile JSON has invalid syntax

`jq -e . "$profile_file"` runs before the loop. We fail fast with the
profile path so the user can `jq . profiles/<name>.json` to find the
bad line.

## 6 · Bash 3.2 compatibility notes

macOS ships Bash 3.2 by default and we don't want to require Homebrew
Bash. Two patterns we deliberately avoid:

- `mapfile` / `readarray` — Bash 4+. We use `while IFS= read -r …; do
  arr+=("$line"); done < <(…)` instead.
- `${var,,}` lowercase / `${var^^}` uppercase — Bash 4+. None currently
  needed; if required later, fall back to `tr '[:upper:]' '[:lower:]'`.

`set -u` + empty arrays is a classic foot-gun. The pattern we use is:

```bash
${arr[@]+"${arr[@]}"}     # expands to nothing if arr is unset/empty,
                          # otherwise to the properly-quoted elements
```

## 7 · How to extend

### Adding a new provider

1. Add a `case` arm in `resolve_source` ([install.sh:133-179](scripts/install.sh#L133-L179))
   that recognises the new pattern and sets `provider` + `resolved`.
2. Ensure the resolved string is something `npx skills add` understands.
   If it doesn't, we'd need to clone/copy locally first and hand `skills
   add` a local path — keep that complexity in `resolve_source`, not
   downstream.
3. Add an entry to the source-formats table in
   [README.md](README.md) and a corresponding row to §2.2 of this doc.
4. Add a test case (manual) covering both success and failure of the
   new format.

### Adding a new command

1. Add `cmd_<name>()` in `coretex.sh`.
2. Add the dispatch case at the bottom ([scripts/coretex.sh:406](scripts/coretex.sh#L406)).
3. Add the line to `usage()` and to the README command table.
4. If the command touches manifests, share the helpers (`read_manifest`,
   `project_manifest_for`, `GLOBAL_MANIFEST`) instead of re-implementing.

### Implementing `coretex remove`

Sketch (not implemented):

- Read manifest. For each entry, optionally `npx skills remove <name>`
  with the recorded scope.
- If `adopted == true`, prompt before removing — coretex isn't the
  origin, so the user might want to keep the skill.
- Delete the entry from the manifest only if the `skills remove` exit
  status was 0 and a post-snapshot confirms it's gone.

### Implementing `coretex update`

Two layers:

- **Skill content refresh** — `npx skills update` (no manifest change).
- **Profile re-application** — `coretex install <profile>` (idempotent;
  refreshes manifest timestamps, picks up new sources, doesn't remove
  dropped sources). A future flag could prune dropped sources.

## 8 · References

- Skills CLI: <https://skills.sh>
- Agent Skills spec: <https://agentskills.io/specification>
- This repo: <https://github.com/NETCASE/coretex>
