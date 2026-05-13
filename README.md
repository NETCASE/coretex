# NETCASE Agent Skills — `coretex`

A collection of [Agent Skills](https://agentskills.io) maintained by [NETCASE GmbH](https://www.netcase.ch), plus a profile-based installer for replaying curated skill bundles on every machine. Compatible with Claude Code, skills.sh, and other [agent-skills-compatible](https://agentskills.io/clients) clients.

## Two roles in one repo

This repo wears two hats — they are independent:

1. **Skill source** — `skills/` contains the skills NETCASE publishes. Anyone can install them via `npx skills add NETCASE/coretex`. You don't need to clone the repo for this.
2. **Profile-based installer** — `profiles/` + `scripts/install.sh` is YOUR machine setup. It pulls curated bundles (NETCASE + upstream sources like `payloadcms/payload`, `mattpocock/skills`, etc.) into the right scope on each machine. This requires cloning the repo.

You can use role 1 without ever touching role 2, and vice versa.

## Concepts

### Scope: global vs. project

The skills.sh CLI installs to one of two destinations:

| Scope | Location | When to use |
|---|---|---|
| **global** | `~/.claude/skills/` | "Always available" — system tools, thinking aids, publishers |
| **project** | `./.claude/skills/` | Per-project — frameworks (Payload, Next.js), versioned with the project |

Scope is set **per source** in a profile (one entry in the `sources` array). The entire repo installs to that one scope unless `skills` narrows it to specific names. If you need the same repo in both scopes, list it twice — once with `"scope": "global"`, once with `"scope": "project"` — and use `skills` to split the contents.

In practice you rarely need to be stingy with global: agents use **progressive disclosure** — only skill names and descriptions are kept in context; the full instructions load only when a task matches.

### Which agents get the skills

By default, no `--agent` is passed, so the `npx skills` CLI **auto-detects every installed agent** (it looks for `~/.claude/`, `~/.qwen/`, `~/.continue/`, `~/.cursor/`, …) and installs to all of them. The real files land in a shared store at `~/.agents/skills/<name>/`, and each agent directory gets a **symlink** to it — install once, every agent sees it.

Three ways to override, in order of precedence:

1. **Per source** in a profile — `"agents": ["claude-code", "qwen-code"]` on the entry.
2. **Per run** via env var — `CORETEX_AGENTS=claude-code,qwen-code coretex install system`. Applies to sources that don't specify their own `agents`.
3. **Default** — both omitted → auto-detect.

### Profiles

A profile is a versioned JSON file under `profiles/<name>.json` describing which sources to install at which scope. Bundling lets you re-create the same setup on any machine.

Initial profiles:

| Profile | Purpose |
|---|---|
| `system` | Base skills installed globally on every machine (NETCASE/coretex itself, etc.) |
| `dev` | Software development context (Payload, Next.js, Matt Pocock) — usually project-scoped |
| `web-design` | Web and UI/UX work |
| `thinktank` | Ideation, planning, structured thinking |

#### Profile schema

```json
{
  "name": "system",
  "description": "Base skills installed on every machine.",
  "sources": [
    { "provider": "github",    "repo": "NETCASE/coretex",   "scope": "global" },
    { "provider": "github",    "repo": "anthropics/skills", "scope": "global",  "skills": ["skill-creator"] },
    { "provider": "skills.sh", "name": "vercel-labs/agent-skills", "scope": "project" },
    { "provider": "git",       "url":  "git@gitlab.example.com:team/skills.git", "scope": "project" },
    { "provider": "local",     "path": "~/work/my-skills",  "scope": "project", "agents": ["claude-code"] }
  ]
}
```

Each `sources` entry has common fields and provider-specific fields.

**Common:**

| Field | Required | Meaning |
|---|---|---|
| `provider` | no | `"github"` (default) · `"skills.sh"` · `"git"` · `"local"` |
| `scope` | yes | `"global"` or `"project"` |
| `skills` | no | Array of skill names. Omit = whole source. |
| `agents` | no | Array of agent IDs. Omit = auto-detect (or `CORETEX_AGENTS`) |

**Provider-specific:**

| Provider | Source field | Example |
|---|---|---|
| `github` | `repo` | `"anthropics/skills"` — resolved through skills.sh |
| `skills.sh` | `name` | `"vercel-labs/agent-skills"` — explicit registry lookup |
| `git` | `url` | `"git@gitlab.example.com:team/skills.git"` or any https URL |
| `local` | `path` | `"~/work/my-skills"` — also accepts absolute or `./relative` |

Same source can be listed multiple times with different `scope`/`skills` combinations — e.g. one `global` entry installing only `skill-creator` and a second `project` entry installing `webapp-testing`.

### What coretex tracks

After every install, coretex writes a **manifest** so it knows which skills are managed by it (versus already installed by hand or by another tool):

| Manifest | Location | Tracks |
|---|---|---|
| Global | `~/.coretex/manifest.json` | Skills installed with `"scope": "global"` |
| Project | `<cwd>/.coretex.json` | Skills installed with `"scope": "project"`, per project directory |

The project manifest is meant to be **committed** into the project repo — it makes the skill setup reproducible for collaborators.

Each manifest entry records: `repo`, `scope`, `profile`, `agents`, `first_seen`, `updated_at`, and an `adopted` flag (`true` if the skill already existed before coretex first picked it up). `coretex status` uses this to mark each skill as **`coretex`** (installed by coretex), **`adopt`** (existed already, now managed), or **`ext`** (external — coretex doesn't manage it).

## Setup

### One-time per machine (global skills)

```sh
# 1. Clone the repo somewhere persistent
gh repo clone NETCASE/coretex ~/Documents/NETCASE/Code/coretex

# 2. Alias
echo 'alias coretex="bash ~/Documents/NETCASE/Code/coretex/scripts/coretex.sh"' >> ~/.zshrc
source ~/.zshrc        # or open a new terminal

# 3. Install the system profile (global skills)
coretex install system
```

### `coretex` commands

```
coretex install [<profile>]   install all sources from profiles/<profile>.json
                              (no <profile> → numbered picker)
coretex status                list installed skills — global first, then project
                              (with BY column: coretex / adopt / ext)
coretex detect-agents         show which agents auto-detect would target
coretex update                update all installed skills        (coming soon)
coretex remove                remove installed skills            (coming soon)
coretex --help
```

Every command prints a `CoreTex · <command>` header and a footer with the repo version (`<branch>@<sha>`), total skill size, and date. Colours follow `NO_COLOR` / non-TTY conventions.

`coretex.sh` is a thin dispatcher: `install` wraps `scripts/install.sh`; `status` reads `npx skills list --json` (needs `jq`, preinstalled on macOS).

### Per project (project-scoped skills)

For each new project you start working on:

```sh
cd ~/Code/my-new-payload-project
coretex install dev    # installs project-scoped sources from profiles/dev.json into ./.claude/skills/
                       # and writes a manifest to ./.coretex.json (commit it!)
```

Note: for **project-scoped** entries the target is your **current working directory**, so `cd` into the project first.

### Updating

```sh
npx skills update    # updates ALL installed skills (global + project) to latest
```

`install.sh` only needs to be re-run when you change a profile file or add new sources. It is idempotent — safe to run multiple times.

### Removing

```sh
npx skills list                    # see what's installed
npx skills remove <skill-name>     # remove a single skill
```

### How `install.sh` works

`bash scripts/install.sh <profile>`:

1. Reads `profiles/<profile>.json` (validates JSON, errors loudly on bad syntax).
2. For each entry in `sources`:
   - resolves `scope` (`global` → `-g`; `project` → no flag → installs into `$PWD/.claude/skills/`)
   - takes a snapshot of currently installed skills in that scope
   - runs `npx skills add <repo> [-g] [-a …] [--skill …] -y`
   - takes a second snapshot — the difference (or the explicit `skills` array) tells coretex which skill names to record
   - upserts each one into the manifest (`~/.coretex/manifest.json` for global, `<cwd>/.coretex.json` for project), marking it `adopted: true` if it already existed before the install.
3. Prints a one-line result per source.

It's **idempotent** — re-running just refreshes manifest timestamps (and re-installs if upstream changed). For `project`-scoped entries, the target is your **current working directory**, so `cd` into the project first. `npx skills update` is the lighter way to refresh skill contents later without touching the manifest.

## Flow at a glance

```
┌──────────────────────────────────────────────────────────────┐
│  GitHub: NETCASE/coretex                                     │
│  ├── skills/         ← published skills (role 1)             │
│  ├── profiles/       ← curated bundles (role 2)              │
│  └── scripts/        ← installer (role 2)                    │
└──────────────────────────────────────────────────────────────┘
                            │
            ┌───────────────┴────────────────┐
            ▼                                ▼
   role 1: install              role 2: clone + run installer
   npx skills add               git clone + bash scripts/install.sh
            │                                │
            ▼                                ▼
   ~/.agents/skills/<name>/     profile decides scope per source:
   + symlinks into every        global  → ~/.agents/skills/ + symlinks
   detected agent dir                       into every detected agent
                                project → ./.claude/skills/ (CWD)
```

## Available skills

<!-- skills:start -->
- **[netcase-bbq](skills/netcase-bbq/)** — Socratic stress-test of a plan or design, ending with a written decision register.
- **[skill-publish](skills/skill-publish/)** — Publish a local Agent Skill folder to the NETCASE/coretex GitHub repository so it becomes installable via `npx skills add NETCASE/coretex`.
<!-- skills:end -->

## Adding a new skill

1. Create the skill folder under `skills/<name>/` with a valid `SKILL.md` (see [agentskills.io/specification](https://agentskills.io/specification)).
2. Use the [skill-publish](skills/skill-publish/) skill — it validates, commits, pushes, and verifies installation.

## Format

Every skill follows the open [Agent Skills specification](https://agentskills.io/specification):

```
skills/my-skill/
├── SKILL.md          # required: YAML frontmatter (name, description) + instructions
├── scripts/          # optional: executable helpers
├── references/       # optional: docs the agent can load on demand
└── assets/           # optional: templates, fixtures
```

## Repository layout

```
coretex/
├── skills/           # published skills (one folder per skill)
├── profiles/         # installable bundles: system.json, dev.json, web-design.json, thinktank.json
├── scripts/
│   ├── coretex.sh    # CLI dispatcher — the `coretex` alias points here (install / status)
│   └── install.sh    # the actual installer: bash scripts/install.sh <profile>
└── README.md
```

## License

MIT — see [LICENSE](LICENSE).
