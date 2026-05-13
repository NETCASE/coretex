# Architecture

This document is the entry point for contributors — human or AI — who
need to read, change, or extend coretex. End-user docs live in
[README.md](README.md).

Read top to bottom on a first pass. Sections 1–3 build the mental model;
4 is the code walkthrough; 5–8 are reference material.

---

## 1 · Mental model

coretex is a profile-replay layer on top of the [skills.sh
CLI](https://skills.sh). The skills CLI installs and lists individual
skills; coretex describes a *machine setup* as a JSON file you can
re-apply anywhere, and records the result so you can later tell what
it manages from what the user installed by hand.

### The state we care about

There are three pieces of state, in three places:

```
┌──────────────────┐        ┌─────────────────────┐        ┌────────────────┐
│  profile (json)  │ ─────▶ │  on-disk skills     │ ─────▶ │  manifest      │
│  (versioned,     │        │  (where skills.sh   │        │  (what coretex │
│   intent)        │        │   put them)         │        │   thinks it    │
│                  │        │                     │        │   manages)     │
└──────────────────┘        └─────────────────────┘        └────────────────┘
        ▲                            ▲                             ▲
        │ user edits                 │ `skills add` writes         │ coretex writes
        │                            │   (or removes)              │   after each install
```

A skill's "BY" state in `coretex status` is the join of the **on-disk
skills** with the **manifest**:

| On disk? | In manifest? | BY |
|---|---|---|
| yes | yes, `adopted=false` | `coretex` |
| yes | yes, `adopted=true`  | `adopt` |
| yes | no                   | `ext` |
| no  | yes                  | (orphan — currently shown only by inspecting the manifest directly; future `coretex remove --prune` will surface it) |
| no  | no                   | — |

### Lifecycle of a single skill

```
        not installed
              │
              │   coretex install <profile>  (source new)
              ▼
    coretex  ◀────────┐
        │             │ skills.sh update / coretex install (re-run)
        │             │
        │ user        │
        │ removes     │
        ▼ manually    │
    orphan in        ─┘
    manifest

    manually installed
              │
              │   coretex install <profile> picks it up in the post-install snapshot
              ▼
    adopt  (write-once — even after manual remove + coretex re-install)
```

The `adopted` flag is fixed at first contact. It answers *"did coretex
originally put this skill on the machine?"* — not *"is coretex currently
keeping it alive?"* That separation matters when implementing
`coretex remove`: an `adopt`-flagged skill predates coretex and the user
likely wants confirmation before removal.

---

## 2 · Components

```
coretex/
├── scripts/
│   ├── coretex.sh             ← single entry point; the `coretex` alias points here
│   └── lib/
│       ├── style.sh           ← ANSI colours, banner, table formatters
│       ├── manifest.sh        ← manifest paths + read/write/upsert
│       └── source.sh          ← provider detection + before/after snapshots
├── profiles/<name>.json       ← versioned profile files
├── skills/<name>/             ← published NETCASE skills (independent of the CLI)
├── README.md                  ← end-user docs
└── ARCHITECTURE.md            ← this file
```

`coretex.sh` is the only entry point. The libs are pure source files —
they contain no top-level code, only function definitions. Sourcing one
in isolation (`. scripts/lib/source.sh`) gives you its helpers in your
shell, which is handy for poking at `resolve_source` while developing.

### What lives where

| File | Lines | Owns |
|---|---|---|
| `scripts/coretex.sh` | ~360 | Dispatcher, `cmd_*` functions, the install loop, agent-detect maps. |
| `scripts/lib/style.sh` | ~140 | All colour / banner / table primitives. The only file that reads `NO_COLOR`. |
| `scripts/lib/manifest.sh` | ~70 | Manifest I/O. The only file that writes to `~/.coretex/` or `<cwd>/.coretex.json`. |
| `scripts/lib/source.sh` | ~80 | `resolve_source` and snapshot helpers. The only file that calls `npx skills list`. |

The "only file that does X" property is intentional — it means a change
to manifest format, or a new provider, has one place to touch.

---

## 3 · Walkthrough: what happens during `coretex install system`

This is the most useful read on a first contact: trace one command end-to-end.

1. **Dispatch** ([coretex.sh:403-415](scripts/coretex.sh#L403-L415)). The
   `case` on `${1:-}` matches `install`, shifts, calls `cmd_install`
   with the rest of the args.

2. **`cmd_install`** ([coretex.sh:197-234](scripts/coretex.sh#L197-L234)).
   - `need_jq` / `need_npx` — abort early if missing.
   - `print_header "install"` — banner.
   - Resolve the profile name (or `pick_profile` interactively).
   - `jq -e .` against `profiles/<profile>.json` — fail fast on bad JSON.
   - Loop over each element of `.sources[]`, calling `install_one_source`.

3. **`install_one_source`** ([coretex.sh:94-195](scripts/coretex.sh#L94-L195)). For each entry:
   - **Validate scope** (global / project / else skip).
   - **`resolve_source`** ([lib/source.sh:resolve_source](scripts/lib/source.sh#L15-L57)) — pattern-match the `source` string to `(provider, resolved_path_or_url)`. See §6.1.
   - **Build CLI args**. `--skill` and `-a` are variadic in the skills
     CLI, so order matters: `-a …` first, `--skill …` last.
   - **`snapshot_for_scope` (before)** — JSON array of skills the CLI
     currently sees in this scope.
   - **`npx skills add <resolved> [-g] [-y] [-a …] [--skill …]`**. We
     redirect stdin from `</dev/null` so `npx` doesn't read the profile
     file (npm is quirky when stdin is a TTY-less file).
   - **`snapshot_for_scope` (after)**.
   - **Decide what to track in the manifest** (§6.2): explicit
     `skills` list wins; otherwise diff after − before; if empty,
     fall back to "everything in after".
   - **`manifest_upsert`** ([lib/manifest.sh:manifest_upsert](scripts/lib/manifest.sh#L42-L62))
     each tracked name. See §6.3 for the write-once trick.

4. **Footer**. `print_footer` writes the version / size / date line.

That's the entire install path. About 300 lines of bash, end to end.

---

## 4 · `coretex status` walkthrough

1. **`cmd_status`** ([coretex.sh:326-335](scripts/coretex.sh#L326-L335)).
   Calls `print_global` and `print_folders`.

2. **`print_global`** ([coretex.sh:258-283](scripts/coretex.sh#L258-L283)).
   - `npx skills list --global --json` — every globally installed skill,
     each with its `agents` list.
   - `read_manifest "$GLOBAL_MANIFEST"` — the `.skills` object of the
     global manifest, or `{}` if missing.
   - One `jq` filter emits one row per `(skill, agent)`. The BY value
     is derived inline:
     `if $mani[name] then (if adopted then "adopt" else "coretex" end) else "ext" end`.
   - The TSV is piped through `fmt_table → style_name_column → style_by_column`.

3. **`print_folders`** ([coretex.sh:288-324](scripts/coretex.sh#L288-L324)).
   Same idea, but groups by project root. For each `<root>/.claude/skills/`
   or `<root>/skills/` discovered (excluding agent home dirs like
   `~/.claude/`), it reads the per-project manifest at
   `<root>/.coretex.json` and computes BY against that.

`coretex status` never modifies state — it's a pure read of what
`skills list` reports plus the manifests.

---

## 5 · Data formats

### 5.1 Profile (`profiles/<name>.json`)

```jsonc
{
  "name": "system",
  "description": "Base skills installed on every machine.",
  "sources": [
    { "source": "anthropics/skills", "scope": "global",
      "skills": ["skill-creator"], "agents": ["claude-code"] }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Matches the filename stem. Informational; never validated. |
| `description` | no | Picker hint (currently unused). |
| `sources` | yes | Array; may be empty (stub profile). |

Per-source:

| Field | Required | Notes |
|---|---|---|
| `source` | yes | String — provider is detected from the format (§6.1). |
| `scope` | yes | `"global"` or `"project"`. Anything else → source skipped with a warning. |
| `skills` | no | When set, install only these names. When absent, install the whole source. |
| `agents` | no | Per-source override; wins over `CORETEX_AGENTS` env and auto-detect. |

### 5.2 Manifest (both global and project)

```jsonc
{
  "version": 1,
  "skills": {
    "skill-creator": {
      "source":   "anthropics/skills",
      "provider": "github",
      "scope":    "global",
      "profile":  "system",
      "agents":   ["Claude Code", "Continue", "Qwen Code"],
      "first_seen": "2026-05-13T18:19:43Z",   // write-once
      "updated_at": "2026-05-13T19:02:11Z",   // refreshed every run
      "adopted":  true                         // write-once (§6.3)
    }
  }
}
```

| Manifest | Path | Written by | Owned by |
|---|---|---|---|
| Global | `~/.coretex/manifest.json` | sources with `"scope": "global"` | the machine |
| Project | `<cwd>/.coretex.json` | sources with `"scope": "project"` | the project (commit it!) |

`version` is reserved for future schema migrations.

---

## 6 · Algorithms

### 6.1 Provider detection ([lib/source.sh:resolve_source](scripts/lib/source.sh#L15-L57))

Pure pattern match — no network, no `git ls-remote`. The user's choice of
prefix tells us the provider:

```
"/", "~", "~/...", "./...", "../..."     → local   (resolve path; require dir exists)
"http://", "https://", "git://",
"ssh://", "git@..."                       → git     (passed verbatim to skills add)
"owner/name" (exactly one slash, no ws)   → github  (skills.sh registry handles it)
everything else                           → error
```

Strings with two or more slashes (`foo/bar/baz`) are rejected with a
hint to prefix with `./` — that catches the ambiguous case where a user
might have meant a path but wrote it without a leading dot.

### 6.2 Which skill names to track

After running `skills add`, we have to decide which entries to write to
the manifest. The skill names are not part of the CLI output, so we
infer them:

```
if source had explicit `skills` list:
    track exactly those names
elif `after.names - before.names` is non-empty:
    track the new names
else:
    # re-run: the source had been fully installed before. Adopt every
    # skill currently in this scope. This is the only place where we
    # might over-attribute skills to a source, but it only happens
    # when the diff is empty AND no skills list was given, so the
    # blast radius is bounded.
    track every name in `after`
```

For each candidate, we look it up in `after` to grab the *actual* agents
list (which differs from what was requested when auto-detect runs). If
the name isn't present in `after`, the install for that skill failed —
we skip the manifest entry.

### 6.3 Manifest write-once fields

`first_seen` and `adopted` must not flip on re-runs. The
[manifest_upsert](scripts/lib/manifest.sh#L42-L62) `jq` filter:

```jq
.skills[$name] = (
  (.skills[$name] // { adopted: $adopted, first_seen: $now })
  + { provider: $provider, source: $source, scope: $scope,
      profile: $prof, agents: $agents, updated_at: $now }
)
```

The `//` fallback supplies a default object with `adopted` + `first_seen`
*only when the entry is absent*. The `+` merge that follows overrides
every other field. So the two write-once fields enter the manifest on
first write and never appear in any subsequent merge object.

Consequence: a skill that started as `adopt=true` (it was already on
disk) stays `adopt` forever — even if you `npx skills remove` it and
let coretex re-install. The flag records origin, not current state.

### 6.4 BY column derivation (in `print_global` / `print_folders`)

For each row from `skills list --json`:

```jq
if $manifest[skill_name] then
  if $manifest[skill_name].adopted then "adopt" else "coretex" end
else
  "ext"
end
```

The relevant manifest depends on the skill's path: global manifest for
skills under `~/.agents/` or `~/.<agent>/`; project manifest at
`<root>/.coretex.json` for any other location.

---

## 7 · Design log

Why things are the way they are. Read this before changing them.

### Why Bash, not Python / Node?

Skills.sh ships as a Node CLI; users already have Node. But coretex
operates *above* it — orchestration, file glue, manifest I/O. Adding a
Python or Node runtime to bootstrap coretex itself would force a second
language toolchain on every machine. Bash + `jq` is enough, runs
everywhere we care about (macOS, Linux, WSL), and the entire codebase
fits in one head.

The cost: no static typing, no test framework. We mitigate with strict
mode (`set -euo pipefail`), small focused functions, and explicit
write-once invariants documented in code comments.

### Why JSON profiles (not YAML / TOML)?

`jq` is already a hard dependency for the manifest. Adding YAML/TOML
means a second parser (`yq` / `toml-cli`) and another tool to install.
JSON is uglier to write but trivial to parse, and we have very small
profiles.

### Why detect the provider instead of an explicit `provider` field?

Earlier iterations had `{ "provider": "github", "repo": "owner/name" }`.
Two fields for the most common case (90 % of entries) is boilerplate.
The auto-detect prefixes (`./`, `https://`, `owner/name`) are
unambiguous and match how users already write skill sources in their
head.

The trade-off: ambiguity at the boundary (`foo/bar/baz`). We reject
those explicitly with an error message that names the fix.

### Why two manifests (global + per-project), not one?

A project's skill setup is part of the project, not the machine. If a
team-mate clones the repo, `coretex install` should give them the same
project skills as the original author. That means the manifest must
travel with the repo — hence `<cwd>/.coretex.json`, committable.

Global skills are the inverse: they belong to the machine, not any one
project. They live in `~/.coretex/`.

### Why no credential storage in coretex?

Git already solves this — Keychain on macOS, libsecret on Linux, Git
Credential Manager cross-platform — and other tools (`gh`, IDE
integrations) benefit from those stores. A coretex-specific store would
either duplicate or fight them. We document setup in the README and
stay out of the credential business.

See the longer discussion at the end of git history if you want
context: PR-by-PR, this question got revisited and rejected three times.

### Why the library split (introduced after the first cut)?

The original layout had `install.sh` as a separate worker script
invoked via `bash scripts/install.sh` from inside `coretex.sh`. That
worked but didn't earn its complexity:

- Nobody called `install.sh` directly — every entry was through the
  `coretex` alias.
- Manifest path logic was duplicated in both files.
- Reading "what does install do" required jumping across scripts.

Extracting `lib/style.sh`, `lib/manifest.sh`, and `lib/source.sh` made
each concern independently inspectable and let `coretex.sh` host the
install loop alongside the other commands.

---

## 8 · Failure modes and invariants

| Invariant | Where it's enforced | Why it matters |
|---|---|---|
| `adopted` and `first_seen` never change after first write | [lib/manifest.sh:manifest_upsert](scripts/lib/manifest.sh#L42-L62) | The audit trail would lie if they could flip. |
| Manifest is only written for skills the post-install snapshot confirms | [coretex.sh:183-186](scripts/coretex.sh#L183-L186) | Failed installs (auth, network, missing `SKILL.md`) leave no record. |
| Project manifest lives at `$PWD`, not the profile's directory | [lib/manifest.sh:manifest_path_for](scripts/lib/manifest.sh#L21-L26) | A profile is portable; the manifest belongs to the project. |
| `provider` is detected from the source string, never user-supplied | [lib/source.sh:resolve_source](scripts/lib/source.sh#L15-L57) | Removes a whole category of typo errors. |
| `coretex status` is read-only | [coretex.sh print_global / print_folders](scripts/coretex.sh#L258-L324) | Inspecting state should never accidentally change it. |

### Edge cases worth knowing

**Invalid profile JSON.** `jq -e . "$profile_file"` runs before the
install loop. We bail with a path the user can pipe back to `jq` to
find the bad line.

**`skills add` exits non-zero but installs anyway.** The post-install
snapshot is authoritative. We only write a manifest entry for a skill
that actually appears in `after`.

**Empty `sources` array.** `thinktank.json` and `web-design.json` ship
this way. We print "No sources" and exit cleanly — not an error.

**Re-run with nothing new.** The before/after diff is empty. We fall
back to "track every skill currently in scope" as adoptions. The
write-once `adopted` flag prevents this from re-attributing already-
tracked skills.

**Manual `skills remove`.** Doesn't touch the manifest. Next `coretex
install` re-installs; `adopted` stays as it was.

**Corrupt manifest.** `read_manifest` falls back to `{}` for missing
files, but a present-but-broken file will crash `jq`. We treat that as
a "user repair" situation — printing a useful error and pointing them
at the file path is enough.

---

## 9 · Bash 3.2 compatibility

macOS ships Bash 3.2 (GPLv3 licensing means Apple won't upgrade).
We don't want to require Homebrew Bash, so the codebase avoids:

- **`mapfile` / `readarray`** (Bash 4+) — use
  `while IFS= read -r line; do arr+=("$line"); done < <(…)` instead.
- **`${var,,}` / `${var^^}`** (Bash 4+) — use `tr '[:upper:]' '[:lower:]'`
  if you need case folding.
- **Associative arrays** (`declare -A`) — represent maps as JSON strings
  and parse with `jq`, like `AGENT_LINK_DIRS` in coretex.sh.

The `set -u` foot-gun with empty arrays: use
`${arr[@]+"${arr[@]}"}` to expand to nothing-when-unset and the quoted
elements otherwise. See the `agent_args` / `skill_args` handling in
`install_one_source`.

---

## 10 · Extending

### Add a new provider

1. Add a `case` arm in [lib/source.sh:resolve_source](scripts/lib/source.sh#L15-L57).
   Set `provider` to the new label, `resolved` to whatever string
   `skills add` will accept.
2. If `skills add` doesn't understand the format, handle the
   conversion in `resolve_source` (e.g. clone the URL to a temp dir
   and return that path) — keep the complexity contained.
3. Update §6.1 of this doc and the source-formats table in README.

### Add a new command

1. Write `cmd_<name>()` in `coretex.sh`. Call `print_header` first and
   `print_footer` last so the banner/footer chrome is consistent.
2. Add a line to `usage()` and to the `case "${1:-}" in` dispatcher
   at the bottom of `coretex.sh`.
3. Add the command to the README table.
4. Share helpers from `lib/` instead of re-implementing — anything new
   that touches manifests belongs in `lib/manifest.sh`.

### Implementing `coretex remove`

Sketch (not yet implemented):

- Read manifest. For each entry, optionally `npx skills remove <name>`
  with the recorded scope.
- If `adopted == true`, prompt before removing — coretex isn't the
  origin, so the user might want to keep the skill.
- Delete the entry from the manifest only if the post-snapshot
  confirms the skill is actually gone.

### Implementing `coretex update`

Two layers:

- **Refresh skill content** — `npx skills update`. No manifest change.
- **Re-apply profiles** — `coretex install <profile>` is already
  idempotent. A future `--prune` flag could remove manifest entries for
  sources no longer in the profile.

---

## 11 · Glossary

| Term | Meaning |
|---|---|
| **Skill** | A folder with `SKILL.md` plus optional resources. Unit of install. |
| **Source** | A string in a profile that tells `skills add` where to fetch from. Maps to a single skill or a skill repo. |
| **Provider** | The detected type of a source: `github` / `git` / `local`. |
| **Profile** | A `profiles/<name>.json` file listing sources + scopes. The replayable unit. |
| **Scope** | `global` (machine-wide) or `project` (per-CWD). Decides which manifest gets the entry. |
| **Manifest** | The JSON file (`~/.coretex/manifest.json` or `<cwd>/.coretex.json`) where coretex records what it installed. |
| **Adopted** | A skill that pre-dated coretex on the machine and was picked up by the first install. Stays adopted forever. |
| **BY** | The `coretex status` column showing each skill's relationship to coretex: `coretex` / `adopt` / `ext`. |
| **Snapshot** | The JSON output of `npx skills list --json` at a point in time, filtered to a scope. Used as before/after to detect new installs. |

---

## 12 · References

- Skills CLI: <https://skills.sh>
- Agent Skills spec: <https://agentskills.io/specification>
- This repo: <https://github.com/NETCASE/coretex>
- matklad on `ARCHITECTURE.md`: <https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html>
