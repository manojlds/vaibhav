#!/usr/bin/env bash
# Setup script for Ubuntu desktop side
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

step() { echo -e "\n${CYAN}▶${NC} ${BOLD}$1${NC}"; }
ok() { echo -e "  ${GREEN}✓${NC} $1"; }
skip() { echo -e "  ${DIM}skip: $1${NC}"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

echo -e "${BOLD}vaibhav — Desktop Setup${NC}"
echo -e "${DIM}Setting up remote AI coding environment on $(hostname)${NC}"

# --- tmux ---
step "Installing tmux"
if command -v tmux &>/dev/null; then
    ok "tmux already installed ($(tmux -V))"
else
    sudo apt-get update -qq && sudo apt-get install -y -qq tmux
    ok "tmux installed"
fi

# --- tmux config ---
step "Linking tmux config"
if [[ -f ~/.tmux.conf ]] && [[ ! -L ~/.tmux.conf ]]; then
    backup="$HOME/.tmux.conf.backup.$(date +%s)"
    cp ~/.tmux.conf "$backup"
    warn "Backed up existing ~/.tmux.conf to $backup"
fi
ln -sf "$SCRIPT_DIR/tmux.conf" ~/.tmux.conf
ok "$HOME/.tmux.conf → $SCRIPT_DIR/tmux.conf"

if tmux ls &>/dev/null; then
    if tmux source-file ~/.tmux.conf &>/dev/null; then
        ok "Reloaded tmux config in running server"
    else
        warn "Could not reload tmux config automatically (reload manually with: tmux source-file ~/.tmux.conf)"
    fi
else
    skip "tmux server not running (config applies on next start)"
fi

# --- SSH server ---
step "Checking SSH server"
if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
    ok "SSH server is running"
else
    if dpkg -l | grep -q openssh-server 2>/dev/null; then
        sudo systemctl enable --now ssh
        ok "SSH server started"
    else
        sudo apt-get update -qq && sudo apt-get install -y -qq openssh-server
        sudo systemctl enable --now ssh
        ok "SSH server installed and started"
    fi
fi

# --- mosh (optional) ---
step "Mosh (optional)"
if command -v mosh-server &>/dev/null; then
    ok "mosh already installed"
else
    read -rp "  Install mosh for resilient mobile connections? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        sudo apt-get update -qq && sudo apt-get install -y -qq mosh
        ok "mosh installed"
    else
        skip "mosh (can install later with: sudo apt install mosh)"
    fi
fi

# --- OpenCode Web systemd service ---
step "OpenCode Web (systemd service)"
OPENCODE_BIN=$(command -v opencode 2>/dev/null || true)
SERVICE_FILE="$HOME/.config/systemd/user/opencode-web.service"

if [[ -z "$OPENCODE_BIN" ]]; then
    read -rp "  opencode not found. Install it? [Y/n] " yn </dev/tty
    if [[ ! "$yn" =~ ^[Nn]$ ]]; then
        echo -e "  ${DIM}Installing opencode...${NC}"
        if curl -fsSL https://opencode.ai/install | bash; then
            # Re-detect after install
            hash -r
            OPENCODE_BIN=$(command -v opencode 2>/dev/null || true)
            if [[ -n "$OPENCODE_BIN" ]]; then
                ok "opencode installed ($OPENCODE_BIN)"
            else
                warn "Install completed but opencode not found in PATH — restart your shell and re-run setup"
            fi
        else
            warn "opencode install failed — install manually: curl -fsSL https://opencode.ai/install | bash"
        fi
    else
        skip "opencode (install later with: curl -fsSL https://opencode.ai/install | bash)"
    fi
fi

if [[ -z "$OPENCODE_BIN" ]]; then
    skip "opencode-web systemd service (opencode not installed)"
elif systemctl --user is-active --quiet opencode-web 2>/dev/null; then
    ok "opencode-web service already running"
    HEALTH=$(curl -sf http://127.0.0.1:4096/global/health 2>/dev/null || echo "unreachable")
    echo -e "  ${DIM}health: ${HEALTH}${NC}"
else
    read -rp "  Set up OpenCode Web as a systemd service? [Y/n] " yn </dev/tty
    if [[ ! "$yn" =~ ^[Nn]$ ]]; then
        # Port and password
        OPENCODE_PORT=4096
        read -rp "  Port [${OPENCODE_PORT}]: " input_port </dev/tty
        OPENCODE_PORT="${input_port:-$OPENCODE_PORT}"

        OPENCODE_PASSWORD=""
        read -rp "  Server password (leave empty for none): " input_pw </dev/tty
        OPENCODE_PASSWORD="${input_pw:-}"

        # Build Environment line
        ENV_LINE=""
        if [[ -n "$OPENCODE_PASSWORD" ]]; then
            ENV_LINE=$'\n'"Environment=OPENCODE_SERVER_PASSWORD=${OPENCODE_PASSWORD}"
        fi

        # Create systemd unit — bind to 127.0.0.1, NOT 0.0.0.0
        # Tailscale serve handles external access with proper HTTPS
        mkdir -p ~/.config/systemd/user
        cat > "$SERVICE_FILE" << UNIT
[Unit]
Description=OpenCode Web Server
After=network.target

[Service]
Type=simple
WorkingDirectory=%h
ExecStart=${OPENCODE_BIN} web --port ${OPENCODE_PORT} --hostname 127.0.0.1${ENV_LINE}
ExecStartPost=/bin/sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do curl -sf http://127.0.0.1:${OPENCODE_PORT}/global/health && exit 0; sleep 1; done; exit 1'
ExecStartPost=-/bin/sh -c '/usr/bin/tailscale serve --bg --yes --https 443 http://127.0.0.1:${OPENCODE_PORT} &'
ExecStopPost=-/usr/bin/tailscale serve --https 443 off
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
        ok "Created ${SERVICE_FILE}"

        # Enable lingering so service runs after logout
        loginctl enable-linger "$USER" 2>/dev/null || true
        ok "User lingering enabled"

        # Start service
        systemctl --user daemon-reload
        systemctl --user enable opencode-web
        systemctl --user start opencode-web
        ok "opencode-web service started"

        # Health check
        echo -e "  ${DIM}Waiting for health check...${NC}"
        HEALTHY=false
        for _i in $(seq 1 10); do
            if curl -sf "http://127.0.0.1:${OPENCODE_PORT}/global/health" >/dev/null 2>&1; then
                HEALTHY=true
                break
            fi
            sleep 1
        done
        if [[ "$HEALTHY" == "true" ]]; then
            ok "OpenCode Web healthy on 127.0.0.1:${OPENCODE_PORT}"
        else
            warn "Health check failed — check: journalctl --user -u opencode-web -f"
        fi

        # Tailscale serve — publish via HTTPS
        if command -v tailscale &>/dev/null; then
            # Check for existing serve mapping (idempotent)
            EXISTING_SERVE=$(tailscale serve status --json 2>/dev/null | grep -c '"https://' 2>/dev/null || echo "0")
            if [[ "$EXISTING_SERVE" -gt 0 ]]; then
                ok "tailscale serve already configured"
            else
                read -rp "  Publish via tailscale serve (HTTPS)? [Y/n] " yn </dev/tty
                if [[ ! "$yn" =~ ^[Nn]$ ]]; then
                    if tailscale serve --bg --yes --https 443 "http://127.0.0.1:${OPENCODE_PORT}" 2>/dev/null; then
                        ok "tailscale serve configured"
                        # Show the URL
                        TS_HOSTNAME=$(tailscale status --json 2>/dev/null | grep -m1 '"DNSName"' | grep -o '"DNSName": *"[^"]*"' | cut -d'"' -f4 | sed 's/\.$//')
                        if [[ -n "$TS_HOSTNAME" ]]; then
                            echo -e "  ${GREEN}URL:${NC} ${BOLD}https://${TS_HOSTNAME}${NC}"
                        fi
                    else
                        warn "tailscale serve failed — you can set it up manually later"
                    fi
                fi
            fi
        else
            warn "Tailscale not installed — skipping tailscale serve"
        fi
    else
        skip "opencode-web systemd service"
    fi
fi

# --- vaibhav script ---
step "Installing vaibhav command"
mkdir -p ~/bin
ln -sf "$SCRIPT_DIR/bin/vaibhav" ~/bin/vaibhav
chmod +x "$SCRIPT_DIR/bin/vaibhav"
ok "$HOME/bin/vaibhav → $SCRIPT_DIR/bin/vaibhav"

# Make sure ~/bin is in PATH
SHELL_RC="$HOME/.bashrc"
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
fi
# shellcheck disable=SC2016
if grep -q 'export PATH="$HOME/bin:$PATH"' "$SHELL_RC" 2>/dev/null; then
    ok "PATH already configured in $SHELL_RC"
elif [[ ":$PATH:" == *":$HOME/bin:"* ]]; then
    ok "$HOME/bin already in PATH"
else
    # shellcheck disable=SC2016
    echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
    warn "Added ~/bin to PATH in $SHELL_RC (restart shell or: source $SHELL_RC)"
fi

# --- Configure vaibhav ---
step "Configuring vaibhav"
export PATH="$HOME/bin:$PATH"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/vaibhav/config"
if [[ -f "$CONFIG_FILE" ]]; then
    ok "vaibhav already configured ($CONFIG_FILE)"
    read -rp "  Re-configure? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        vaibhav init
    else
        skip "re-configuration"
    fi
else
    vaibhav init
fi

# --- Tailscale ---
step "Checking Tailscale"
if command -v tailscale &>/dev/null; then
    local_ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
    ok "Tailscale installed (IP: $local_ip)"

    # Ensure current user is set as Tailscale operator (needed for tailscale serve without sudo)
    TS_OPERATOR=$(tailscale debug prefs 2>/dev/null | grep -o '"OperatorUser":"[^"]*"' | cut -d'"' -f4 || true)
    if [[ "$TS_OPERATOR" == "$USER" ]]; then
        ok "Tailscale operator already set to $USER"
    else
        echo -e "  ${DIM}Setting Tailscale operator to $USER (needed for tailscale serve without sudo)${NC}"
        if sudo tailscale set --operator="$USER"; then
            ok "Tailscale operator set to $USER"
        else
            warn "Could not set Tailscale operator — run manually: sudo tailscale set --operator=\$USER"
        fi
    fi
else
    warn "Tailscale not installed. Install from: https://tailscale.com/download/linux"
fi

# --- Summary ---
echo ""
echo -e "${BOLD}${GREEN}Desktop setup complete!${NC}"
echo ""
echo -e "Your Tailscale IP: ${CYAN}$(tailscale ip -4 2>/dev/null || echo 'N/A')${NC}"
echo -e "Hostname:          ${CYAN}$(hostname)${NC}"

# Show OpenCode Web URL if configured
if systemctl --user is-active --quiet opencode-web 2>/dev/null; then
    WEB_URL=$(vaibhav web --url-only 2>/dev/null || true)
    if [[ -n "$WEB_URL" ]]; then
        echo -e "OpenCode Web:      ${CYAN}${WEB_URL}${NC}"
    fi
fi

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Run the Termux setup on your Android phone"
echo "  2. Use 'vaibhav list' to see your projects"
echo "  3. Use 'vaibhav <name> <tool>' to start coding"
echo "  4. Use 'vaibhav web' to see OpenCode Web URL"
echo ""
echo -e "${DIM}Example: vaibhav vaibhav pi (or amp/claude/codex/opencode)${NC}"
