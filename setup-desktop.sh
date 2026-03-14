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
step "Installing tmux (default multiplexer)"
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

# --- zellij (optional) ---
step "Zellij (optional multiplexer)"
if command -v zellij &>/dev/null; then
    ok "zellij already installed ($(zellij --version 2>/dev/null || echo 'version unknown'))"
else
    read -rp "  Install zellij as an alternative to tmux? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        CARGO_BIN=""
        if command -v cargo &>/dev/null; then
            CARGO_BIN="$(command -v cargo)"
        elif [[ -x "$HOME/.cargo/bin/cargo" ]]; then
            CARGO_BIN="$HOME/.cargo/bin/cargo"
            export PATH="$HOME/.cargo/bin:$PATH"
        else
            warn "cargo not found — installing Rust toolchain with rustup"
            if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
                if [[ -f "$HOME/.cargo/env" ]]; then
                    # shellcheck source=/dev/null
                    source "$HOME/.cargo/env"
                else
                    export PATH="$HOME/.cargo/bin:$PATH"
                fi
                CARGO_BIN="$(command -v cargo 2>/dev/null || true)"
            else
                warn "rustup install failed"
            fi
        fi

        if [[ -n "$CARGO_BIN" ]]; then
            if "$CARGO_BIN" install --locked zellij; then
                export PATH="$HOME/.cargo/bin:$PATH"
                hash -r
                if command -v zellij &>/dev/null; then
                    ok "zellij installed ($(zellij --version 2>/dev/null || echo 'version unknown'))"
                elif [[ -x "$HOME/.cargo/bin/zellij" ]]; then
                    ok "zellij installed at $HOME/.cargo/bin/zellij"
                else
                    warn "cargo install completed but zellij is not in PATH"
                fi
            else
                warn "Could not install zellij — run manually: cargo install --locked zellij"
            fi
        else
            warn "cargo unavailable — install Rust first: https://rustup.rs"
        fi
    else
        skip "zellij (can install later with: cargo install --locked zellij)"
    fi
fi

# --- zellij config ---
step "Linking zellij config (mobile-friendly)"
mkdir -p "$HOME/.config/zellij"
if [[ -f "$HOME/.config/zellij/config.kdl" ]] && [[ ! -L "$HOME/.config/zellij/config.kdl" ]]; then
    backup="$HOME/.config/zellij/config.kdl.backup.$(date +%s)"
    cp "$HOME/.config/zellij/config.kdl" "$backup"
    warn "Backed up existing ~/.config/zellij/config.kdl to $backup"
fi
ln -sf "$SCRIPT_DIR/zellij.kdl" "$HOME/.config/zellij/config.kdl"
ok "$HOME/.config/zellij/config.kdl → $SCRIPT_DIR/zellij.kdl"

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

# --- mDNS (optional) ---
step "mDNS LAN hostname (optional)"
if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    ok "mDNS already active ($(hostname).local)"
else
    read -rp "  Install/enable mDNS (avahi-daemon) for LAN hostname $(hostname).local? [Y/n] " yn
    if [[ ! "$yn" =~ ^[Nn]$ ]]; then
        if sudo apt-get update -qq && sudo apt-get install -y -qq avahi-daemon libnss-mdns; then
            sudo systemctl enable --now avahi-daemon
            if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
                ok "mDNS enabled ($(hostname).local)"
            else
                warn "avahi-daemon installed but not active — check: sudo systemctl status avahi-daemon"
            fi
        else
            warn "Could not install avahi-daemon — install manually: sudo apt install avahi-daemon libnss-mdns"
        fi
    else
        skip "mDNS setup"
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

# --- Zellij Web systemd service ---
step "Zellij Web (systemd service)"
ZELLIJ_BIN=$(command -v zellij 2>/dev/null || true)
ZELLIJ_SERVICE_FILE="$HOME/.config/systemd/user/zellij-web.service"

if [[ -z "$ZELLIJ_BIN" ]]; then
    skip "zellij-web service (zellij not installed)"
elif systemctl --user is-active --quiet zellij-web 2>/dev/null; then
    ok "zellij-web service already running"
    ZJ_STATUS=$(zellij web --status 2>/dev/null || echo "status unavailable")
    echo -e "  ${DIM}${ZJ_STATUS}${NC}"
else
    read -rp "  Set up Zellij Web as a systemd service? [y/N] " yn </dev/tty
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        ZELLIJ_WEB_PORT=8082
        ZELLIJ_WEB_HTTPS_PORT=8443
        read -rp "  Tailscale HTTPS port [${ZELLIJ_WEB_HTTPS_PORT}]: " input_zellij_https_port </dev/tty
        ZELLIJ_WEB_HTTPS_PORT="${input_zellij_https_port:-$ZELLIJ_WEB_HTTPS_PORT}"

        mkdir -p ~/.config/systemd/user
        cat > "$ZELLIJ_SERVICE_FILE" << UNIT
[Unit]
Description=Zellij Web Server
After=network.target

[Service]
Type=simple
WorkingDirectory=%h
ExecStart=${ZELLIJ_BIN} web --start --ip 127.0.0.1 --port ${ZELLIJ_WEB_PORT}
ExecStop=${ZELLIJ_BIN} web --stop
ExecStartPost=-/bin/sh -c '/usr/bin/tailscale serve --bg --yes --https ${ZELLIJ_WEB_HTTPS_PORT} http://127.0.0.1:${ZELLIJ_WEB_PORT} &'
ExecStopPost=-/usr/bin/tailscale serve --https ${ZELLIJ_WEB_HTTPS_PORT} off
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
        ok "Created ${ZELLIJ_SERVICE_FILE}"

        # Enable lingering so service runs after logout
        loginctl enable-linger "$USER" 2>/dev/null || true
        ok "User lingering enabled"

        systemctl --user daemon-reload
        systemctl --user enable zellij-web
        systemctl --user start zellij-web
        ok "zellij-web service started"

        sleep 1
        ZJ_STATUS=$(zellij web --status 2>/dev/null || true)
        if echo "$ZJ_STATUS" | grep -qi "online"; then
            ok "Zellij Web healthy on 127.0.0.1:${ZELLIJ_WEB_PORT}"
        else
            warn "Health check failed — check: journalctl --user -u zellij-web -f"
        fi

        if command -v tailscale &>/dev/null; then
            TS_HOSTNAME=$(tailscale status --json 2>/dev/null | grep -m1 '"DNSName"' | grep -o '"DNSName": *"[^"]*"' | cut -d'"' -f4 | sed 's/\.$//')
            if [[ -n "$TS_HOSTNAME" ]]; then
                if [[ "$ZELLIJ_WEB_HTTPS_PORT" == "443" ]]; then
                    echo -e "  ${GREEN}URL:${NC} ${BOLD}https://${TS_HOSTNAME}${NC}"
                else
                    echo -e "  ${GREEN}URL:${NC} ${BOLD}https://${TS_HOSTNAME}:${ZELLIJ_WEB_HTTPS_PORT}${NC}"
                fi
            fi
        fi

        echo ""
        read -rp "  Create a Zellij Web login token now? [Y/n] " yn </dev/tty
        if [[ ! "$yn" =~ ^[Nn]$ ]]; then
            if ! zellij web --create-token; then
                warn "Could not create token (try later: vaibhav web zellij token)"
            fi
        else
            skip "token creation (later: vaibhav web zellij token)"
        fi
    else
        skip "zellij-web systemd service"
    fi
fi

# --- Vaibhav Files (file sharing) ---
step "Vaibhav Files (file sharing server)"
SHARE_DIR="$HOME/vaibhav-share"
FILES_SERVICE_FILE="$HOME/.config/systemd/user/vaibhav-files.service"

if systemctl --user is-active --quiet vaibhav-files 2>/dev/null; then
    ok "vaibhav-files service already running"
    echo -e "  ${DIM}Sharing: ${SHARE_DIR}${NC}"
else
    read -rp "  Set up a file sharing server (APKs, HTML, etc.)? [y/N] " yn </dev/tty
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        FILES_PORT=9090
        FILES_HTTPS_PORT=9443
        read -rp "  Local port [${FILES_PORT}]: " input_files_port </dev/tty
        FILES_PORT="${input_files_port:-$FILES_PORT}"
        read -rp "  Tailscale HTTPS port [${FILES_HTTPS_PORT}]: " input_files_https_port </dev/tty
        FILES_HTTPS_PORT="${input_files_https_port:-$FILES_HTTPS_PORT}"

        # Create share directory with common subdirs
        mkdir -p "$SHARE_DIR"/{apk,html,output}
        ok "Created ${SHARE_DIR}/ (apk/ html/ output/)"

        # Create systemd unit — Python http.server on localhost
        mkdir -p ~/.config/systemd/user
        cat > "$FILES_SERVICE_FILE" << UNIT
[Unit]
Description=Vaibhav File Sharing Server
After=network.target

[Service]
Type=simple
WorkingDirectory=${SHARE_DIR}
ExecStart=/usr/bin/python3 -m http.server ${FILES_PORT} --bind 127.0.0.1
ExecStartPost=-/bin/sh -c '/usr/bin/tailscale serve --bg --yes --https ${FILES_HTTPS_PORT} http://127.0.0.1:${FILES_PORT} &'
ExecStopPost=-/usr/bin/tailscale serve --https ${FILES_HTTPS_PORT} off
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
        ok "Created ${FILES_SERVICE_FILE}"

        loginctl enable-linger "$USER" 2>/dev/null || true

        systemctl --user daemon-reload
        systemctl --user enable vaibhav-files
        systemctl --user start vaibhav-files
        ok "vaibhav-files service started"

        sleep 1
        if curl -sf "http://127.0.0.1:${FILES_PORT}/" >/dev/null 2>&1; then
            ok "File server healthy on 127.0.0.1:${FILES_PORT}"
        else
            warn "Health check failed — check: journalctl --user -u vaibhav-files -f"
        fi

        if command -v tailscale &>/dev/null; then
            TS_HOSTNAME=$(tailscale status --json 2>/dev/null | grep -m1 '"DNSName"' | grep -o '"DNSName": *"[^"]*"' | cut -d'"' -f4 | sed 's/\.$//')
            if [[ -n "$TS_HOSTNAME" ]]; then
                if [[ "$FILES_HTTPS_PORT" == "443" ]]; then
                    echo -e "  ${GREEN}URL:${NC} ${BOLD}https://${TS_HOSTNAME}${NC}"
                else
                    echo -e "  ${GREEN}URL:${NC} ${BOLD}https://${TS_HOSTNAME}:${FILES_HTTPS_PORT}${NC}"
                fi
            fi
        fi
    else
        skip "vaibhav-files service"
    fi
fi

# --- vaibhav script ---
step "Installing vaibhav command"
mkdir -p ~/bin
ln -sf "$SCRIPT_DIR/bin/vaibhav" ~/bin/vaibhav
chmod +x "$SCRIPT_DIR/bin/vaibhav"
ok "$HOME/bin/vaibhav → $SCRIPT_DIR/bin/vaibhav"

ln -sf "$SCRIPT_DIR/bin/vaibhav-switcher" ~/bin/vaibhav-switcher
chmod +x "$SCRIPT_DIR/bin/vaibhav-switcher"
ok "$HOME/bin/vaibhav-switcher → $SCRIPT_DIR/bin/vaibhav-switcher"

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
if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    echo -e "mDNS hostname:     ${CYAN}$(hostname).local${NC}"
fi

# Show Web URLs if configured
if systemctl --user is-active --quiet opencode-web 2>/dev/null; then
    WEB_URL=$(vaibhav web --url-only 2>/dev/null || true)
    if [[ -n "$WEB_URL" ]]; then
        echo -e "OpenCode Web:      ${CYAN}${WEB_URL}${NC}"
    fi
fi
if systemctl --user is-active --quiet zellij-web 2>/dev/null; then
    ZELLIJ_WEB_URL=$(vaibhav web --zellij-url-only 2>/dev/null || true)
    if [[ -n "$ZELLIJ_WEB_URL" ]]; then
        echo -e "Zellij Web:       ${CYAN}${ZELLIJ_WEB_URL}${NC}"
    fi
fi
if systemctl --user is-active --quiet vaibhav-files 2>/dev/null; then
    FILES_URL=$(vaibhav web --files-url-only 2>/dev/null || true)
    if [[ -n "$FILES_URL" ]]; then
        echo -e "Vaibhav Files:    ${CYAN}${FILES_URL}${NC}"
    fi
fi

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Run the Termux setup on your Android phone"
echo "  2. Use 'vaibhav list' to see your projects"
echo "  3. Use 'vaibhav <name> <tool>' to start coding"
echo "  4. Use 'vaibhav web' to see/manage OpenCode + Zellij Web + Files"
echo ""
echo -e "${DIM}Example: vaibhav vaibhav pi (or amp/claude/codex/opencode)${NC}"
