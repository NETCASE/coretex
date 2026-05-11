---
name: skill-publish
description: Publish a local Agent Skill folder to the NETCASE/coretex GitHub repository so it becomes installable via `npx skills add NETCASE/coretex`. Use when the user says "publish this skill", "release the skill", "push to skills.sh", or has just finished writing a SKILL.md and wants to share it on the NETCASE skill registry.
---

# skill-publish

Publishes a local Agent Skill (the Anthropic / agentskills.io `SKILL.md` format) to **NETCASE/coretex** on GitHub. Once pushed, anyone can install it with:

```sh
npx skills add NETCASE/coretex
```

The Agent Skills format is identical for Anthropic skills and skills.sh — there is **no format conversion**. This skill validates, places, commits, pushes, and verifies.

## Inputs

The user provides (or you infer from context):

- `SKILL_PATH` — absolute path to a folder containing a `SKILL.md`. Common sources:
  - `~/.claude/skills/<name>/` (from Anthropic's skill-creator)
  - `<project>/.claude/skills/<name>/`
  - Any other folder with a valid `SKILL.md`

If the user says "publish the skill I just made" without a path, look in `~/.claude/skills/` for the most recently modified skill folder and confirm with the user before proceeding.

## Procedure

### 1. Validate the skill

Read `SKILL_PATH/SKILL.md`. Reject (and tell the user why) if any of these fail:

- File exists and starts with a YAML frontmatter block (`---` ... `---`).
- Frontmatter has both `name` and `description` keys.
- `name` matches `^[a-z][a-z0-9-]*$` (lowercase, hyphens, no spaces or underscores).
- `name` equals the folder name (case-sensitive). If not, ask whether to rename folder or frontmatter.
- `description` is a single line, ≥ 40 characters, and clearly states **when to use** (discovery requires this — descriptions like "does X" without a trigger context are too weak).
- No file in the skill folder contains obvious secrets. Scan for common credential formats (cloud provider access keys, GitHub or Slack tokens, private key headers, `.env`-style assignments with non-placeholder values). Use a dedicated scanner if available (`gitleaks detect`, `trufflehog filesystem`); otherwise apply regex checks for these formats yourself. Abort if any non-test content matches.

Optional checks (warn but don't block):

- `scripts/`, `references/`, `assets/` subfolders follow spec convention if present.
- Total skill size < 5 MB (large bundles slow `npx skills add`).

### 2. Sync the target repo

```sh
TMPDIR=$(mktemp -d)
gh repo clone NETCASE/coretex "$TMPDIR/coretex"
cd "$TMPDIR/coretex"
git checkout main
git pull --ff-only
```

If the repo doesn't exist yet (first-time bootstrap), the user must create it via the bootstrap flow in the repo's `README.md` rather than this skill.

### 3. Place the skill

```sh
DEST="$TMPDIR/coretex/skills/<name>"
rm -rf "$DEST"  # remove old version if updating
mkdir -p "$DEST"
cp -R "$SKILL_PATH/." "$DEST/"
```

Strip noise that doesn't belong in the public repo:

```sh
find "$DEST" -name ".DS_Store" -delete
find "$DEST" -name "*.swp" -delete
```

### 4. Update the repo README index

The repo `README.md` has a `<!-- skills:start -->` … `<!-- skills:end -->` section listing all skills. Regenerate it:

- One bullet per `skills/*/SKILL.md`, format:
  `- **[<name>](skills/<name>/)** — <description first sentence, max 140 chars>`
- Sort alphabetically.
- If the markers are missing, append the section to the README.

### 5. Commit and push

```sh
cd "$TMPDIR/coretex"
git add skills/<name>/ README.md
git status  # show the user what's about to be committed
git commit -m "Add skill: <name>" -m "<description first sentence>"
git push origin main
```

Use `Update skill: <name>` if the skill folder already existed before this run.

### 6. Provide verification instructions (don't auto-run)

The skill is now in the repo. Do **not** execute a verification install yourself — output the command for the user to run, so they decide when to fetch and execute remote code:

```sh
# Verify install (run in any directory):
cd "$(mktemp -d)" && npx skills add NETCASE/coretex -g -a claude-code
# Then list installed skills:
npx skills list
```

If the user reports a failure: read the error output, do **not** delete the push, and surface the underlying issue. Most failures are SKILL.md spec violations that escaped step 1 (validation).

### 7. Report back

Tell the user:

- Commit SHA
- Direct link: `https://github.com/NETCASE/coretex/tree/main/skills/<name>`
- Install snippet: `npx skills add NETCASE/coretex`

## When NOT to use this skill

- The skill is private/internal and must not leak to a public repo. Use a private repo workflow instead.
- The skill contains third-party content with unclear licensing (e.g. someone else's skills). Confirm rights first.
- The user wants to publish to a registry other than NETCASE/coretex (e.g. their personal `<user>/skills` repo) — this skill is hard-coded to NETCASE/coretex. Adapt or fork for other targets.

## Notes

- skills.sh discovers and ranks repos via anonymous telemetry when users run `npx skills add`. There is no manual submission step.
- The `SKILL.md` format is governed by [agentskills.io](https://agentskills.io). Frontmatter rules there are authoritative — when in doubt, check the spec.
- Anthropic's skill-creator writes skills directly into `~/.claude/skills/<name>/`. That output is publish-ready; this skill exists to handle the GitHub plumbing, not format conversion.
