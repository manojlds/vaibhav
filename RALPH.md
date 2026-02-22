# Ralph Loop

Autonomous AI-driven development loop built into vaibhav. Write a PRD, break it into stories, and let AI agents implement them one by one — from your desktop or your phone.

Based on the [Ralph pattern](https://ghuntley.com/ralph/) — each iteration spawns a fresh AI instance that picks up the next incomplete story, implements it, runs quality checks, commits, and moves on.

## Architecture

Ralph uses **skills** (`.agents/skills/`) for all intelligent work. The CLI commands are thin wrappers that invoke skills via your chosen AI engine (amp, claude, opencode, pi). Skills are engine-agnostic — any tool that discovers `.agents/skills/` can use them directly without the vaibhav CLI.

| Skill | Purpose |
|-------|---------|
| `vaibhav-init` | Agentic project scanner — detects commands/rules, generates config, bootstraps engine guidance files (`AGENTS.md`/`CLAUDE.md`), sets up prek hooks |
| `vaibhav-prd` | PRD generator — asks clarifying questions, writes structured PRDs |
| `vaibhav-convert` | PRD → prd.json converter — ensures stories are right-sized and dependency-ordered |
| `vaibhav-loop` | Per-iteration loop instructions — reads config.yaml directly for commands and rules |

Skills are installed to your project's `.agents/skills/` during `vaibhav ralph init` and updated via `vaibhav ralph update-skills` or `vaibhav update`.

```
PRD → prd.json → Ralph Loop → Done
                    ↓
              Pick next story
              Implement it
              Run tests/lint
              Commit
              Update progress
              Loop ↺
```

## Quick start

```bash
cd ~/projects/myapp
vaibhav ralph init                          # 1. Setup config
vaibhav ralph prd create auth "Add user auth with email/password login"  # 2. Write a PRD
vaibhav ralph prd convert tasks/prd-auth.md # 3. Convert to prd.json
vaibhav ralph run                           # 4. Start the loop
```

---

## Step 1: Initialize project config

Installs skills to `.agents/skills/`, then invokes the `vaibhav-init` skill via your AI engine. The skill interactively scans your project, confirms detected commands, generates `.vaibhav/config.yaml`, bootstraps engine guidance files (`AGENTS.md`/`CLAUDE.md`), sets up prek pre-commit hooks, and updates `.gitignore`.

**Desktop** (from the project directory):

```bash
cd ~/projects/myapp
vaibhav ralph init
```

**Phone:**

```bash
vaibhav ralph -p myapp init
```

**Static detection fallback** (no AI engine needed):

```bash
vaibhav ralph init --no-agent
```

**What it does:**

- Copies vaibhav skills to `.agents/skills/`
- Invokes the `vaibhav-init` skill via your AI engine (interactive detection, config generation, prek hooks, guidance-file bootstrap, .gitignore update)
- With `--no-agent`: falls back to static detection (grep-based scanning of package.json, pyproject.toml, etc.)
- Asks you to pick a default AI engine (amp, claude, opencode, pi)

### Add rules

Add project-specific rules that the AI agent must follow during the loop:

**Desktop:**

```bash
vaibhav ralph add-rule "use server actions not API routes"
vaibhav ralph add-rule "prefer shadcn/ui components"
```

**Phone:**

```bash
vaibhav ralph -p myapp add-rule "use server actions not API routes"
```

### View config

**Desktop:**

```bash
vaibhav ralph config
```

**Phone:**

```bash
vaibhav ralph -p myapp config
```

---

## Step 2: Write a PRD

Launches your AI engine with a PRD-writing skill. The AI asks clarifying questions, then generates a structured PRD with user stories and acceptance criteria.

**Desktop:**

```bash
vaibhav ralph prd create auth "Add user authentication with email/password login and session management"
```

**Phone:**

```bash
vaibhav ralph -p myapp prd create auth "Add user auth with email/password login"
```

The description is optional but recommended — it gives the AI the context it needs to ask better clarifying questions and generate a more accurate PRD. Without it, you just get generic questions about the feature name.

**What happens:**

1. AI reads your description and asks 3–5 targeted clarifying questions (with lettered options)
2. You answer (e.g., "1A, 2C, 3B")
3. AI generates `tasks/prd-auth.md` with:
   - Introduction and goals
   - User stories with acceptance criteria
   - Functional requirements
   - Non-goals and open questions

**You can also write PRDs by hand** — just create a markdown file in `tasks/` following the format with `### US-001:` story headers.

---

## Step 3: Convert PRD to prd.json

Converts your markdown PRD into the machine-readable `prd.json` format that the Ralph loop uses. The AI ensures stories are right-sized and dependency-ordered.

**Desktop:**

```bash
vaibhav ralph prd convert tasks/prd-auth.md
```

**Phone:**

```bash
vaibhav ralph -p myapp prd convert tasks/prd-auth.md
```

**What it produces** (`prd.json`):

```json
{
  "project": "myapp",
  "branchName": "ralph/auth",
  "description": "Authentication system with login and session management",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add users table",
      "description": "As a developer, I need a users table to store credentials.",
      "acceptanceCriteria": [
        "Create users table with email, password_hash, created_at",
        "Migration runs successfully",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Add login API endpoint",
      "...": "..."
    }
  ]
}
```

**Key rules the converter follows:**

- Each story must be completable in one iteration (one context window)
- Stories ordered by dependency: schema → backend → UI
- Acceptance criteria must be verifiable, not vague

---

## Step 4: Run the Ralph loop

Starts the agentic loop. Each iteration spawns a fresh AI instance that picks the next incomplete story, implements it, and commits.

**Desktop:**

```bash
vaibhav ralph run
```

**Phone:**

```bash
vaibhav ralph -p myapp run
```

**With options:**

```bash
# Override engine
vaibhav ralph run --engine pi

# Limit iterations
vaibhav ralph run --max-iterations 5

# From phone with options
vaibhav ralph -p myapp run --engine pi --max-iterations 3

# Preview the prompt without running
vaibhav ralph run --dry-run
```

**What each iteration does:**

1. Reads `prd.json` and `progress.txt`
2. Checks out the correct git branch
3. Picks the highest-priority story where `passes: false`
4. Implements that single story
5. Runs quality checks (test, lint, typecheck — from your config)
6. Commits with message: `feat: [US-001] - Story title`
7. Updates `prd.json` to mark the story as `passes: true`
8. Appends learnings to `progress.txt`
9. If all stories done → exits. Otherwise → next iteration.

**Completion signal:** When the AI finishes all stories, it outputs `<promise>COMPLETE</promise>` and the loop exits.

### Single task mode

For quick one-off tasks without a PRD:

**Desktop:**

```bash
vaibhav ralph run "fix the login redirect bug"
vaibhav ralph run "add dark mode toggle to the header"
```

**Phone:**

```bash
vaibhav ralph -p myapp run "fix the login redirect bug"
```

---

## Step 5: Check progress

See which stories are done and which are pending.

**Desktop:**

```bash
vaibhav ralph status
```

**Phone:**

```bash
vaibhav ralph -p myapp status
```

**Example output:**

```
Ralph Status

  Project:  myapp
  Branch:   ralph/auth
  Progress: 3/5 stories complete

  ● US-001  Add users table                    ✓
  ● US-002  Add login API endpoint             ✓
  ● US-003  Add session middleware              ✓
  ○ US-004  Add login page UI
  ○ US-005  Add logout and session expiry
```

### List PRDs

See all PRD files and the active prd.json status:

**Desktop:**

```bash
vaibhav ralph prd list
```

**Phone:**

```bash
vaibhav ralph -p myapp prd list
```

---

## Files created by Ralph

These files live in your project root:

| File | Purpose |
|------|---------|
| `.vaibhav/config.yaml` | Project config (language, commands, rules, boundaries) |
| `.agents/skills/vaibhav-*` | Installed skills (engine-agnostic, discoverable by amp/claude/opencode/pi) |
| `tasks/prd-*.md` | PRD markdown files |
| `prd.json` | Active task queue with story completion status |
| `progress.txt` | Append-only log of learnings from each iteration |
| `archive/` | Archived previous runs (when switching features) |

### progress.txt

Each iteration appends what it learned. Future iterations read this to avoid repeating mistakes:

```
## Codebase Patterns
- Use server actions in app/actions/ for all mutations
- Always validate with zod schemas from lib/validators

## 2026-02-17 14:32 - US-001
Session: [session URL/ID if available, else N/A]
- Added users table with email, password_hash, created_at
- Files: prisma/schema.prisma, prisma/migrations/
- Learnings:
  - Must run `npx prisma generate` after migration
  - Database URL is in .env.local
---
```

---

## Command reference

All commands support `-p <project>` to target a registered project from anywhere.

### Setup

| Command | Description |
|---------|-------------|
| `vaibhav ralph init [dir]` | Initialize project (install skills, run AI detection) |
| `vaibhav ralph init --no-agent` | Initialize with static detection only (no AI) |
| `vaibhav ralph config` | Show current config |
| `vaibhav ralph add-rule "rule"` | Add a project rule |
| `vaibhav ralph update-skills` | Update skills in current project from vaibhav install |
| `vaibhav ralph check` | Run quality checks (lint → typecheck → test → build) |

### PRD

| Command | Description |
|---------|-------------|
| `vaibhav ralph prd create <name> ["desc"]` | Write a PRD with AI assistance |
| `vaibhav ralph prd convert <file>` | Convert markdown PRD → prd.json |
| `vaibhav ralph prd list` | List all PRDs and progress |

### Run

| Command | Description |
|---------|-------------|
| `vaibhav ralph run` | Start the ralph loop |
| `vaibhav ralph run "task"` | Single task mode |
| `vaibhav ralph run --dry-run` | Preview prompt |
| `vaibhav ralph run --engine pi` | Override AI engine |
| `vaibhav ralph run --max-iterations N` | Cap iterations |
| `vaibhav ralph status` | Show story progress |

### Phone examples

```bash
vaibhav ralph -p heimdall init
vaibhav ralph -p heimdall prd create auth "Add login and session management"
vaibhav ralph -p heimdall run --max-iterations 5
vaibhav ralph -p heimdall status
vaibhav ralph -p heimdall config
```
