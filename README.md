# vaibhav

Remote AI coding environment — run tools like Amp, Claude Code, Codex, and OpenCode on your Ubuntu desktop and use them seamlessly from your Android phone.

## How it works

```
Android (Termux) → SSH over Tailscale → Ubuntu Desktop → tmux sessions → AI tools
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
- Run `vaibhav init` to configure your projects directory and scan for projects

### 2. Termux setup (Android)

Install [Termux](https://f-droid.org/en/packages/com.termux/) and [Tailscale](https://play.google.com/store/apps/details?id=com.tailscale.ipn) on your phone, then in Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/manojlds/vaibhav/main/setup-termux.sh -o setup-termux.sh
bash setup-termux.sh
```

## Usage

Same command works everywhere — on the desktop it runs locally, from Termux it automatically SSHes in:

```bash
vaibhav init                # Interactive setup
vaibhav list                # List all projects and active sessions
vaibhav heimdall amp        # Open heimdall project with Amp
vaibhav drs claude          # Open drs with Claude Code
vaibhav myapp opencode      # Open myapp with OpenCode
vaibhav add myapp ~/myapp   # Register a new project
vaibhav scan                # Auto-register all projects in configured directory
vaibhav scan ~/other        # Scan a specific directory
desktop                     # Connect to last tmux session (Termux alias)
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
```

Project registry is stored at `~/.config/vaibhav/projects`.

## Project structure

```
vaibhav/
├── bin/vaibhav         # Project session manager script
├── tmux.conf           # tmux configuration (mobile-optimized)
├── setup-desktop.sh    # Ubuntu desktop setup
├── setup-termux.sh     # Android Termux setup
└── README.md
```

## Tips

- **Closing Termux** doesn't kill sessions — everything keeps running on the desktop
- **Multiple tools**: Run `vaibhav myapp amp`, then `vaibhav myapp claude` to add Claude Code in a new window
- **Tailscale** gives you a stable connection even when switching WiFi/mobile networks
- **Termux extra keys**: Swipe from the left edge to toggle the extra keyboard row with `ESC`, `CTRL`, `ALT`, `TAB`, and common coding symbols
- **Pinch to zoom** in Termux to adjust text size for comfortable reading on your phone
