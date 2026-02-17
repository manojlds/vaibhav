# Updating vaibhav

The `vaibhav update` command keeps both your phone and desktop in sync with the latest version.

## Quick update

**Phone (Termux):**

```bash
vaibhav update
```

This does three things:
1. Downloads latest `bin/vaibhav` and `bin/vaibhav-ralph` from GitHub
2. Verifies SHA256 checksums before replacing files
3. SSHes to your desktop and runs `git pull` to update there too

**Desktop:**

```bash
vaibhav update
```

Runs `git pull` in the vaibhav repo (since the desktop script is symlinked to the repo).

---

## What happens on each platform

### Termux (phone) update flow

```
vaibhav update
  │
  ├─ Download checksums.sha256 from GitHub
  ├─ Download bin/vaibhav (check remote version)
  │
  ├─ Same version + same checksums?
  │   └─ "Already up to date (v0.3.0)" → done
  │
  ├─ Download bin/vaibhav-ralph
  ├─ Verify SHA256 checksums of all downloaded files
  │   ├─ Mismatch? → abort, keep old files
  │   └─ Match? → continue
  │
  ├─ Atomic update: move verified files into ~/bin/
  ├─ "✓ Updated: v0.2.0 → v0.3.0"
  │
  └─ SSH to desktop → git pull
      ├─ "✓ Desktop updated: v0.2.0 → v0.3.0"
      ├─ "✓ Desktop already up to date"
      └─ (warns and continues if SSH fails)
```

### Desktop update flow

```
vaibhav update
  │
  ├─ Resolve repo path from ~/bin/vaibhav symlink
  ├─ Check for uncommitted changes
  │   └─ Changes found? → abort with warning
  │
  ├─ git pull
  │   ├─ "Already up to date (v0.3.0)"
  │   └─ "✓ Updated: v0.2.0 → v0.3.0"
```

---

## Options

```bash
vaibhav update            # Update phone + desktop
vaibhav update --local    # Update phone only, skip desktop
```

---

## Checksum verification

Every Termux update verifies file integrity using SHA256 checksums. The `checksums.sha256` file in the repo contains hashes for all distributable files:

```
daae8fca...  bin/vaibhav
43f44bcc...  bin/vaibhav-ralph
da115322...  tmux.conf
```

If any downloaded file doesn't match its checksum, the update aborts and your existing files are untouched.

### Regenerating checksums (for maintainers)

After making changes to distributable files, regenerate checksums before committing:

```bash
bin/generate-checksums
git add checksums.sha256
git commit -m "chore: update checksums"
```

---

## Version checking

```bash
vaibhav --version         # Show installed version
```

The version is embedded in `bin/vaibhav` as `VAIBHAV_VERSION`. The update command shows the version change:

```
✓ Updated: v0.2.0 → v0.3.0
```

---

## Safety guarantees

- **Atomic updates** — files are downloaded to a temp directory, verified, then moved into place. A failed download never leaves you with a broken install.
- **Checksum verification** — corrupted or incomplete downloads are caught before replacing files.
- **No force-pull** — desktop update aborts if there are local uncommitted changes.
- **Desktop failure is non-fatal** — if SSH to desktop fails during a phone update, the local update still succeeds with a warning.
- **Idempotent** — running `vaibhav update` when already up to date is a no-op.

---

## Setup scripts are also idempotent

Both setup scripts can be safely re-run to repair or upgrade an installation:

**Termux:**

```bash
bash setup-termux.sh
```

- Skips SSH key generation if key exists
- Detects existing SSH config block — replaces if changed, skips if identical
- Uses existing config values as defaults (no need to re-enter hostname/username)
- Doesn't overwrite custom `termux.properties` settings beyond the extra-keys block

**Desktop:**

```bash
./setup-desktop.sh
```

- Doesn't duplicate PATH entries in shell rc files
- Skips mosh prompt if already installed
- Only runs `vaibhav init` if config doesn't exist (offers re-configure otherwise)
- SSH server install/start skipped if already running

---

## Troubleshooting

**"Checksum verification failed"** — The downloaded file doesn't match the expected hash. This usually means GitHub's CDN served a stale version. Wait a minute and try again.

**"Desktop has local changes"** — Your desktop repo has uncommitted changes. Commit or stash them first: `cd ~/projects/vaibhav && git stash && vaibhav update`.

**"Could not connect to desktop via SSH"** — Make sure Tailscale is running on both devices and SSH is configured. Use `vaibhav update --local` to skip the desktop update.
