# vaibhav

vaibhav is a remote-first AI coding environment with a Bash CLI (`bin/vaibhav`, `bin/vaibhav-ralph`) and a Pi-native extension package (`extensions/vaibhav`).

## Commands

After any meaningful change, run:

```bash
vaibhav ralph check
```

Primary quality commands (from `.vaibhav/config.yaml`):

- `shellcheck -S error bin/vaibhav bin/vaibhav-ralph` — Bash lint (errors only)
- `npm pack --dry-run` — package/build sanity check for the Pi package manifest

Useful workflows:

- `vaibhav ralph init` — initialize Ralph config/skills flow
- `vaibhav ralph run` — run Ralph loop from CLI
- `/reload` in Pi after extension code changes

## Conventions

- Use `set -euo pipefail` in Bash scripts.
- Follow existing output/style helpers (`step`, `ok`, `warn`) and color conventions.
- Keep Pi extension code modular under `extensions/vaibhav/src`.
- Keep Pi-native workflows additive; do not regress existing `vaibhav ralph` CLI behavior.
- Treat `skills/vaibhav-*` as the source of truth for init/prd/convert/loop behavior.
- Prefer focused changes with minimal surface area.

## Directory Structure

```text
bin/                    # CLI entrypoints (vaibhav, vaibhav-ralph)
skills/vaibhav-*/       # reusable skills for init/prd/convert/loop
extensions/vaibhav/     # Pi extension (entrypoint + src modules)
prompts/                # legacy prompt templates/fallbacks
```

## Testing Patterns

- Bash changes: run shellcheck command above.
- Pi extension changes: run `/reload` and test affected `/vaibhav-*` commands.
- Loop/phase behavior: validate `vaibhav_phase_done` handshake and finalize flow (`/vaibhav-finalize <runId>`).
