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
ok "~/.tmux.conf → $SCRIPT_DIR/tmux.conf"

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

# --- vaibhav script ---
step "Installing vaibhav command"
mkdir -p ~/bin
ln -sf "$SCRIPT_DIR/bin/vaibhav" ~/bin/vaibhav
chmod +x "$SCRIPT_DIR/bin/vaibhav"
ok "~/bin/vaibhav → $SCRIPT_DIR/bin/vaibhav"

# Make sure ~/bin is in PATH
SHELL_RC="$HOME/.bashrc"
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
fi
if grep -q 'export PATH="$HOME/bin:$PATH"' "$SHELL_RC" 2>/dev/null; then
    ok "PATH already configured in $SHELL_RC"
elif [[ ":$PATH:" == *":$HOME/bin:"* ]]; then
    ok "~/bin already in PATH"
else
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
else
    warn "Tailscale not installed. Install from: https://tailscale.com/download/linux"
fi

# --- Summary ---
echo ""
echo -e "${BOLD}${GREEN}Desktop setup complete!${NC}"
echo ""
echo -e "Your Tailscale IP: ${CYAN}$(tailscale ip -4 2>/dev/null || echo 'N/A')${NC}"
echo -e "Hostname:          ${CYAN}$(hostname)${NC}"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Run the Termux setup on your Android phone"
echo "  2. Use 'vaibhav list' to see your projects"
echo "  3. Use 'vaibhav <name> <tool>' to start coding"
echo ""
echo -e "${DIM}Example: vaibhav vaibhav amp${NC}"
