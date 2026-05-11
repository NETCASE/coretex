# NETCASE Agent Skills — `coretex`

A collection of [Agent Skills](https://agentskills.io) maintained by [NETCASE GmbH](https://www.netcase.ch), plus the bootstrap tooling to install curated skill sets across machines. Compatible with Claude Code, skills.sh, and other [agent-skills-compatible](https://agentskills.io/clients) clients.

## Quick install (single skill source)

```sh
npx skills add -g NETCASE/coretex
```

This installs every skill under `skills/` into `~/.claude/skills/` (global).

## Profile-based install (recommended)

Profiles let you keep a versioned list of skill sources per context (system, dev, web-design, thinktank) and replay the same setup on every machine.

```sh
gh repo clone NETCASE/coretex
cd coretex
bash scripts/install.sh system        # base skills for every machine
bash scripts/install.sh dev           # development context
bash scripts/install.sh web-design    # web and UI/UX work
bash scripts/install.sh thinktank     # ideation, planning, structured thinking
```

Edit `profiles/<name>.txt` to add or activate sources — one entry per line:

```
<owner/repo> [global|project]
```

Lines starting with `#` are ignored. Default scope is `global` (installs to `~/.claude/skills/`).

To update everything later:

```sh
npx skills update
```

## Available skills

<!-- skills:start -->
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
├── profiles/         # installable bundles: system.txt, dev.txt, …
├── scripts/
│   └── install.sh    # bash scripts/install.sh <profile>
└── README.md
```

## License

MIT — see [LICENSE](LICENSE).
