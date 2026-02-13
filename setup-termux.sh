#!/usr/bin/env bash
# Setup script for Termux (Android) side
# Run this INSIDE Termux on your Android phone
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

step() { echo -e "\n${CYAN}▶${NC} ${BOLD}$1${NC}"; }
ok() { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

echo -e "${BOLD}vaibhav — Termux Setup${NC}"
echo ""

# --- Collect desktop info for SSH config ---
if [[ -z "${1:-}" ]]; then
    read -rp "Desktop hostname or IP: " DESKTOP_HOST
else
    DESKTOP_HOST="$1"
fi

if [[ -z "${2:-}" ]]; then
    read -rp "Desktop username: " DESKTOP_USER
else
    DESKTOP_USER="$2"
fi
echo ""

# --- Install packages ---
step "Installing packages"
pkg update -y
pkg install -y openssh tmux
ok "openssh and tmux installed"

# --- SSH key ---
step "Setting up SSH key"
if [[ -f ~/.ssh/id_ed25519 ]]; then
    ok "SSH key already exists"
else
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "termux@android"
    ok "SSH key generated"
fi

echo ""
echo -e "  ${YELLOW}Copy this public key to your desktop:${NC}"
echo ""
cat ~/.ssh/id_ed25519.pub
echo ""
echo -e "  ${DIM}On your desktop, run:${NC}"
echo -e "  ${DIM}echo '<paste_key>' >> ~/.ssh/authorized_keys${NC}"
echo ""
read -rp "Press Enter once you've copied the key to your desktop..."

# --- SSH config ---
step "Configuring SSH"
mkdir -p ~/.ssh
if grep -q "# vaibhav — Desktop connection" ~/.ssh/config 2>/dev/null; then
    ok "SSH config already configured"
else
    cat >> ~/.ssh/config << EOF

# vaibhav — Desktop connection
Host desktop
    HostName ${DESKTOP_HOST}
    User ${DESKTOP_USER}
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
    ServerAliveCountMax 5
    Compression yes
EOF
    ok "SSH config added (Host: desktop)"
fi

# --- vaibhav script ---
step "Installing vaibhav command"
mkdir -p ~/bin

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
REPO_URL="https://raw.githubusercontent.com/manojlds/vaibhav/main"

if [[ -n "$SCRIPT_DIR" ]] && [[ -f "$SCRIPT_DIR/bin/vaibhav" ]]; then
    cp "$SCRIPT_DIR/bin/vaibhav" ~/bin/vaibhav
else
    curl -fsSL "${REPO_URL}/bin/vaibhav" -o ~/bin/vaibhav
fi
chmod +x ~/bin/vaibhav
ok "~/bin/vaibhav installed"

# --- Shell config ---
step "Adding shell config"
SHELL_RC="$HOME/.bashrc"
if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
fi

if ! grep -q "# vaibhav" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'ALIASES'

# vaibhav
alias desktop="ssh -t desktop 'tmux attach || tmux new'"
export PATH="$HOME/bin:$PATH"
ALIASES
    ok "Aliases added to $SHELL_RC"
else
    ok "Aliases already configured"
fi

# --- Configure vaibhav ---
step "Configuring vaibhav"
export PATH="$HOME/bin:$PATH"
vaibhav init

# --- Termux properties for better keyboard ---
step "Configuring Termux"
mkdir -p ~/.termux
if [[ ! -f ~/.termux/termux.properties ]] || ! grep -q "extra-keys" ~/.termux/termux.properties 2>/dev/null; then
    cat > ~/.termux/termux.properties << 'PROPS'
# Extra keys row for tmux and coding
extra-keys = [ \
  ['ESC', 'CTRL', 'ALT', 'TAB', '|', '-', 'UP', 'DOWN'] \
]
# Second row with common coding keys
extra-keys-rows = 2
extra-keys-2 = [ \
  ['{', '}', '[', ']', '(', ')', '/', '\\'] \
]
PROPS
    ok "Extra keyboard rows configured"
    warn "Run 'termux-reload-settings' to apply keyboard changes"
else
    ok "Termux properties already configured"
fi

# --- Summary ---
echo ""
echo -e "${BOLD}${GREEN}Termux setup complete!${NC}"
echo ""
echo -e "${BOLD}Quick start:${NC}"
echo "  vaibhav list               # See your projects"
echo "  vaibhav heimdall amp       # Start coding with Amp"
echo "  desktop                    # Connect to last session"
echo ""
echo -e "${BOLD}Tips:${NC}"
echo "  • Swipe left edge of screen → toggle extra keys"
echo "  • Pinch to zoom text size"
echo "  • Closing Termux keeps sessions alive on desktop"
echo "  • Alt+s to switch projects (once in tmux)"
echo ""
echo -e "${DIM}Make sure Tailscale is running on both devices!${NC}"
