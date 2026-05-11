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

Scope is set **per profile entry** (one `<repo> [global|project]` line in a profile file). The entire repo installs to that one scope — there is no per-skill scope flag. If you need both, list the repo twice with different scopes.

In practice you rarely need to be stingy with global: agents use **progressive disclosure** — only skill names and descriptions are kept in context; the full instructions load only when a task matches.

### Profiles

A profile is a versioned list of `<repo> <scope>` lines under `profiles/<name>.txt`. Bundling lets you re-create the same setup on any machine.

Initial profiles:

| Profile | Purpose |
|---|---|
| `system` | Base skills installed globally on every machine (NETCASE/coretex itself, etc.) |
| `dev` | Software development context (Payload, Next.js, Matt Pocock) — usually project-scoped |
| `web-design` | Web and UI/UX work |
| `thinktank` | Ideation, planning, structured thinking |

Edit `profiles/<name>.txt` to activate or add sources. Each line is:

```
<owner/repo> [global|project] [extra-flags...]
```

Extra flags are passed straight to `npx skills add`. Most useful is `--skill <name1> <name2>` to install only specific skills from a multi-skill repo (e.g. only `skill-creator` from `anthropics/skills`'s 17 skills). Lines starting with `#` are ignored.

## Setup

### One-time per machine (global skills)

```sh
# 1. Clone the repo somewhere persistent
gh repo clone NETCASE/coretex ~/Documents/NETCASE/Code/coretex

# 2. Install the system profile (global skills)
bash ~/Documents/NETCASE/Code/coretex/scripts/install.sh system

# 3. Optional alias for convenience
echo 'alias coretex="bash ~/Documents/NETCASE/Code/coretex/scripts/install.sh"' >> ~/.zshrc
exec zsh
```

### Per project (project-scoped skills)

For each new project you start working on:

```sh
cd ~/Code/my-new-payload-project
coretex dev          # installs project-scoped sources from profiles/dev.txt into ./.claude/skills/
```

Note: `install.sh` for **project-scoped** entries uses your **current working directory** as the target. Always `cd` into the project first.

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
   `~/.claude/skills/`         profile decides scope per source:
   (just coretex's skills)     global → `~/.claude/skills/`
                               project → `./.claude/skills/` (CWD)
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
├── profiles/         # installable bundles: system.txt, dev.txt, web-design.txt, thinktank.txt
├── scripts/
│   └── install.sh    # bash scripts/install.sh <profile>
└── README.md
```

## License

MIT — see [LICENSE](LICENSE).
