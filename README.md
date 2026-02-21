# vaibhav

Remote AI coding environment — run tools like Amp, Claude Code, Codex, and OpenCode on your Ubuntu desktop and use them seamlessly from your Android phone.

## How it works

```
Android (Termux) → SSH/mosh over Tailscale → Ubuntu Desktop → tmux sessions → AI tools
```

Each project gets its own tmux session. Sessions persist when you disconnect — close Termux, reopen later, and pick up exactly where you left off.

## Quick start

### 1. Desktop setup (Ubuntu)

```bash
cd ~/projects/vaibhav
./setup-desktop.sh
```

This will:
- Install and configure tmux
- Install the `vaibhav` command
- Set up SSH server
- Optionally install mosh for resilient mobile connections
- Run `vaibhav init` to configure your projects directory and scan for projects

### 2. Termux setup (Android)

Install [Termux](https://f-droid.org/en/packages/com.termux/) and [Tailscale](https://play.google.com/store/apps/details?id=com.tailscale.ipn) on your phone, then in Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/manojlds/vaibhav/main/setup-termux.sh -o setup-termux.sh
bash setup-termux.sh
```

The setup will:
- Install OpenSSH (and optionally mosh)
- Generate an SSH key and copy it to your desktop (via `ssh-copy-id`)
- Configure SSH connection to your desktop
- Download and install the `vaibhav` command
- Configure remote mode
- Set up extra keyboard keys for coding
- Optionally install FiraCode Nerd Font for proper icon rendering

## Usage

Same command works everywhere — on the desktop it runs locally, from Termux it automatically SSHes in:

```bash
vaibhav init                # Interactive setup
vaibhav list                # List all projects and active sessions
vaibhav heimdall amp        # Open heimdall project with Amp
vaibhav drs claude          # Open drs with Claude Code
vaibhav myapp opencode      # Open myapp with OpenCode
vaibhav heimdall amp --mosh # Open with Amp via mosh
vaibhav add myapp ~/myapp   # Register a new project
vaibhav scan                # Auto-register all projects in configured directory
vaibhav scan ~/other        # Scan a specific directory
vaibhav --version           # Check installed version
```

### Switching projects

Once inside tmux, you can switch projects without disconnecting:

| Shortcut | Action |
|----------|--------|
| `Alt+s` | Session picker (switch projects) |
| `Prefix → p` | Session picker |
| `Prefix → f` | Search sessions by name |
| `Alt+n` / `Alt+p` | Next/previous window |
| `Alt+1..5` | Jump to window by number |

(`Prefix` is `Ctrl+b` by default)

## Configuration

`vaibhav init` creates `~/.config/vaibhav/config`:

```bash
VAIBHAV_PROJECTS_DIR="/home/user/projects"    # Where your projects live
VAIBHAV_DESKTOP_HOST="mypc"                   # Desktop hostname (enables remote mode)
VAIBHAV_SSH_HOST="desktop"                    # SSH host alias
VAIBHAV_USE_MOSH="false"                      # Use mosh by default (true/false)
VAIBHAV_MOSH_NO_INIT="true"                   # Pass --no-init to mosh (better touch scroll in Termux)
```

Project registry is stored at `~/.config/vaibhav/projects`.

## Updating

```bash
vaibhav update            # updates phone + desktop
vaibhav update --local    # phone only
```

On Termux, this downloads and checksum-verifies the latest files, then SSHes to your desktop to `git pull`. On desktop, it runs `git pull` directly.

See [UPDATE.md](UPDATE.md) for the full details on the update process, checksum verification, and troubleshooting.

## Ralph loop

vaibhav includes a built-in [Ralph loop](RALPH.md) — an autonomous AI coding loop that works through a PRD, implementing stories one by one.

```bash
vaibhav ralph init                          # Setup project config
vaibhav ralph prd create auth               # Write a PRD
vaibhav ralph prd convert tasks/prd-auth.md # Convert to prd.json
vaibhav ralph run                           # Start the loop
vaibhav ralph status                        # Check progress
```

Works from your phone too — use `-p` to target any project:

```bash
vaibhav ralph -p myapp status
vaibhav ralph -p myapp run --max-iterations 3
```

See [RALPH.md](RALPH.md) for the full guide.

## Project structure

```
vaibhav/
├── bin/
│   ├── vaibhav          # Project session manager
│   └── vaibhav-ralph    # Ralph loop engine
├── prompts/
│   ├── ralph-prompt.md  # Loop iteration prompt template
│   ├── prd-skill.md     # PRD writing skill
│   └── prd-convert.md   # PRD → prd.json converter
├── tmux.conf            # tmux configuration (mobile-optimized)
├── setup-desktop.sh     # Ubuntu desktop setup
├── setup-termux.sh      # Android Termux setup
├── RALPH.md             # Ralph loop documentation
└── README.md
```

## Tips

- **Closing Termux** doesn't kill sessions — everything keeps running on the desktop
- **Multiple tools**: Run `vaibhav myapp amp`, then `vaibhav myapp claude` to add Claude Code in a new window
- **Tailscale** gives you a stable connection even when switching WiFi/mobile networks
- **Termux extra keys**: Swipe from the left edge to toggle the extra keyboard row with `ESC`, `CTRL`, `ALT`, `TAB`, and common coding symbols
- **Pinch to zoom** in Termux to adjust text size for comfortable reading on your phone
- **FiraCode Nerd Font** is installed during Termux setup for proper icon rendering (starship, etc.)
- **Clipboard from tmux**: Use copy mode (`Ctrl+b` then `[` or `Alt+u`), select, then `Enter` or `y`; vaibhav's tmux config sends copied text to your local clipboard via OSC 52
- **After updating tmux.conf**: If tmux is already running, reload once with `tmux source-file ~/.tmux.conf`
