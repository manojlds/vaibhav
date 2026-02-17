# PRD: Installation & Update System

## 1. Introduction/Overview

Vaibhav's current installation and update experience on Termux (Android) is fragile. Users must manually `curl` the script from GitHub, and there's no reliable way to know if the update succeeded or if the correct version is running. The desktop side relies on `git pull`, which is fine but disconnected from a unified workflow.

This feature introduces a `vaibhav update` command that works on both Termux and desktop, verifies success via version and integrity checks, and makes the setup scripts robust and idempotent so they can be safely re-run to repair or upgrade an installation.

## 2. Goals

- Provide a single `vaibhav update` command that updates vaibhav on both Termux and desktop
- Verify every install/update with version checks and file integrity checks (checksums)
- Make `setup-termux.sh` and `setup-desktop.sh` idempotent and safe to re-run
- Update all necessary files (scripts, tmux.conf, etc.) — not just `~/bin/vaibhav`
- Give clear feedback: what version was running, what version is now running, what files changed

## 3. User Stories

### US-001: `vaibhav update` on Termux updates local scripts

**Description:** As a Termux user, I want to run `vaibhav update` so that all vaibhav files on my phone are updated to the latest version from GitHub.

**Acceptance Criteria:**
- [ ] `vaibhav update` downloads the latest `bin/vaibhav` from GitHub and replaces `~/bin/vaibhav`
- [ ] Also downloads and updates `bin/vaibhav-ralph` to `~/bin/vaibhav-ralph`
- [ ] Shows old version → new version (e.g., `0.2.0 → 0.3.0`)
- [ ] If already on the latest version, prints "Already up to date (v0.3.0)" and exits cleanly
- [ ] Verifies downloaded files with SHA256 checksum against a `checksums.sha256` file hosted in the repo
- [ ] If checksum verification fails, aborts the update, keeps old files in place, and prints an error
- [ ] Exit code is 0 on success, non-zero on failure

### US-002: `vaibhav update` on Termux triggers desktop update

**Description:** As a Termux user, I want `vaibhav update` to also update the desktop side so that both environments stay in sync.

**Acceptance Criteria:**
- [ ] When running in remote mode (Termux), after updating local files, `vaibhav update` SSHes to the desktop and runs `git -C <repo-path> pull` to update the desktop
- [ ] The repo path on the desktop is discovered by running `readlink -f ~/bin/vaibhav` on the desktop to find the repo root (two levels up from `bin/vaibhav`)
- [ ] Shows the desktop update result (e.g., "Desktop updated: v0.2.0 → v0.3.0" or "Desktop already up to date")
- [ ] If SSH to desktop fails, prints a warning but still considers the local update successful
- [ ] A `--local` flag skips the desktop update

### US-003: `vaibhav update` on desktop updates via git pull

**Description:** As a desktop user, I want to run `vaibhav update` so that vaibhav is updated via `git pull` in the repo directory.

**Acceptance Criteria:**
- [ ] `vaibhav update` on the desktop runs `git pull` in the vaibhav repo directory
- [ ] The repo directory is resolved from the symlink at `~/bin/vaibhav`
- [ ] Shows old version → new version after pulling
- [ ] If there are local changes that would conflict, warns the user and aborts (does not force-pull)
- [ ] If already up to date, prints "Already up to date (v0.3.0)"

### US-004: Checksum file generation and hosting

**Description:** As a maintainer, I want a checksums file in the repo so that Termux updates can verify file integrity.

**Acceptance Criteria:**
- [ ] A `checksums.sha256` file exists in the repo root containing SHA256 hashes for all distributable files (`bin/vaibhav`, `bin/vaibhav-ralph`, `tmux.conf`)
- [ ] A script `bin/generate-checksums` regenerates `checksums.sha256` from the current files
- [ ] The checksum file is committed to the repo alongside releases
- [ ] `vaibhav update` on Termux downloads this file and verifies each downloaded file against it

### US-005: Make `setup-termux.sh` idempotent and safe to re-run

**Description:** As a Termux user, I want to re-run `setup-termux.sh` to repair or upgrade my installation without breaking anything.

**Acceptance Criteria:**
- [ ] Re-running the script does not duplicate SSH config entries (detects existing `# vaibhav` block and skips or replaces)
- [ ] Re-running does not re-prompt for desktop hostname/username if config already exists (uses existing values as defaults, allows override)
- [ ] Re-running does not overwrite custom changes to `~/.termux/termux.properties` beyond the extra-keys block
- [ ] SSH key generation is skipped if key already exists (already works today)
- [ ] `ssh-copy-id` is skipped if SSH access already works (already works today)
- [ ] Script can be re-run with no arguments if config already exists (reads defaults from `~/.config/vaibhav/config`)
- [ ] All steps print clear skip/update/done status (e.g., `✓ SSH config already configured` vs `✓ SSH config updated`)
- [ ] Font installation prompt is skipped if font already installed (already works today)

### US-006: Make `setup-desktop.sh` idempotent and safe to re-run

**Description:** As a desktop user, I want to re-run `setup-desktop.sh` to repair or upgrade my installation without breaking anything.

**Acceptance Criteria:**
- [ ] Re-running does not duplicate PATH entries in shell rc files
- [ ] Re-running updates the tmux.conf symlink without error if it already exists (already works today via `ln -sf`)
- [ ] `vaibhav init` is only run if config doesn't exist yet, or user explicitly confirms re-configuration
- [ ] SSH server install/start is skipped if already running (already works today)
- [ ] All steps print clear skip/update/done status
- [ ] Mosh prompt is skipped if mosh is already installed

### US-007: Version flag and version source of truth

**Description:** As a user, I want `vaibhav --version` to reliably show the installed version so I can verify updates worked.

**Acceptance Criteria:**
- [ ] `VAIBHAV_VERSION` in `bin/vaibhav` is the single source of truth for the version
- [ ] `vaibhav --version` prints just the version string (e.g., `vaibhav 0.3.0`)
- [ ] `vaibhav update` reads the version before and after update and displays the change
- [ ] `vaibhav-ralph` does not independently track a version — it defers to `vaibhav --version`

## 4. Functional Requirements

- FR-1: The `vaibhav update` command must work in both local (desktop) and remote (Termux) modes
- FR-2: On Termux, `vaibhav update` must download files from `https://raw.githubusercontent.com/manojlds/vaibhav/main/` 
- FR-3: On Termux, downloaded files must be verified against SHA256 checksums before replacing existing files
- FR-4: On desktop, `vaibhav update` must use `git pull` (not raw downloads) since the script is symlinked to the repo
- FR-5: On Termux, `vaibhav update` must update all distributable files: `bin/vaibhav`, `bin/vaibhav-ralph`, and any other files listed in the checksums file
- FR-6: The update must be atomic — download to temp files first, verify checksums, then move into place. Never leave a half-updated state
- FR-7: Both setup scripts must be idempotent — running them multiple times produces the same result as running once
- FR-8: `checksums.sha256` must be generated by a script (`bin/generate-checksums`) to avoid manual errors
- FR-9: The `vaibhav update` command must use `Cache-Control: no-cache` header when downloading from GitHub to avoid stale CDN caches

## 5. Non-Goals (Out of Scope)

- Auto-update on launch or background update checks — updates are manual via `vaibhav update`
- Package manager distribution (apt, pkg, brew) — files are downloaded from GitHub
- Rollback to a previous version — users can `git checkout` on desktop or re-run setup on Termux
- Updating AI tools (Amp, Claude Code, etc.) — only vaibhav itself
- Signing releases with GPG keys — SHA256 checksums are sufficient for integrity

## 6. Technical Considerations

- `curl` is available on both Termux and Ubuntu; use it for all downloads
- `sha256sum` is available on both platforms for checksum verification
- Temp files for atomic updates should use `mktemp` and be cleaned up on failure (use a trap)
- The Termux `vaibhav` script is a standalone copy (not a symlink), so it must be replaced in-place
- The desktop `vaibhav` script is a symlink to the repo, so `git pull` is the correct update mechanism
- GitHub raw URLs can be CDN-cached; always pass `-H 'Cache-Control: no-cache'` to `curl`
- Remote update (Termux → desktop) uses the existing `VAIBHAV_SSH_HOST` config for SSH connectivity

## 7. Success Metrics

- Running `vaibhav update` on Termux correctly updates all files and shows version change
- Running `vaibhav update` on Termux also updates the desktop via SSH
- Checksum verification catches corrupted or incomplete downloads
- Both setup scripts can be re-run without duplicating config or breaking the installation
- `vaibhav --version` matches the expected version after every update

## 8. Open Questions

- Should `vaibhav update` on Termux also update the tmux.conf? Currently tmux.conf lives on the desktop (symlinked from repo), so `git pull` handles it. But if we ever sync tmux.conf to Termux, we'd need to handle it.
- Should there be a `vaibhav update --check` that just reports if an update is available without applying it?
- Should the version be compared against a `VERSION` file in the repo (simpler to parse remotely) or should we keep it embedded in the script?
