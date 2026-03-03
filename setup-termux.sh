#!/usr/bin/env bash
# Setup script for Termux (Android) side
# Run this INSIDE Termux on your Android phone
# Idempotent — safe to re-run for repairs or upgrades
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

step() { echo -e "\n${CYAN}▶${NC} ${BOLD}$1${NC}"; }
ok() { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

echo -e "${BOLD}vaibhav — Termux Setup${NC}"
echo ""

# --- Load existing config for defaults ---
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/vaibhav"
CONFIG_FILE="$CONFIG_DIR/config"
EXISTING_HOST=""
EXISTING_USER=""
EXISTING_LAN_HOST=""
if [[ -f "$CONFIG_FILE" ]]; then
    EXISTING_HOST=$(grep '^VAIBHAV_DESKTOP_HOST=' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2) || true
    EXISTING_LAN_HOST=$(grep '^VAIBHAV_LAN_HOST=' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2) || true
    # Extract username from SSH config (not from vaibhav config — it doesn't store username)
    if [[ -f ~/.ssh/config ]]; then
        EXISTING_USER=$(awk '/^# vaibhav/,/^$/{if(/User /){print $2}}' ~/.ssh/config 2>/dev/null) || true
    fi
fi

# --- Collect desktop info ---
# Use positional args, then existing config defaults, then prompt
if [[ -n "${1:-}" ]]; then
    DESKTOP_HOST="$1"
elif [[ -n "$EXISTING_HOST" ]]; then
    read -rp "Desktop Tailscale hostname/IP [$EXISTING_HOST]: " input_host </dev/tty
    DESKTOP_HOST="${input_host:-$EXISTING_HOST}"
else
    read -rp "Desktop Tailscale hostname/IP: " DESKTOP_HOST </dev/tty
fi

# Extract existing SSH user from SSH config for default
if [[ -n "${2:-}" ]]; then
    DESKTOP_USER="$2"
elif [[ -n "$EXISTING_USER" ]]; then
    read -rp "Desktop username [$EXISTING_USER]: " input_user </dev/tty
    DESKTOP_USER="${input_user:-$EXISTING_USER}"
else
    read -rp "Desktop username: " DESKTOP_USER </dev/tty
fi

# Optional LAN hostname for auto-switching when on home Wi-Fi
DEFAULT_LAN_HOST="${EXISTING_LAN_HOST:-}"
if [[ -z "$DEFAULT_LAN_HOST" ]] && [[ "$DESKTOP_HOST" == *.* ]] && [[ ! "$DESKTOP_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    DEFAULT_LAN_HOST="${DESKTOP_HOST%%.*}.local"
fi
if [[ -n "${3:-}" ]]; then
    LAN_HOST="$3"
else
    lan_prompt_default="${DEFAULT_LAN_HOST:-none}"
    read -rp "LAN mDNS hostname (optional, '-' to disable) [${lan_prompt_default}]: " input_lan_host </dev/tty
    if [[ "$input_lan_host" == "-" ]]; then
        LAN_HOST=""
    elif [[ -n "$input_lan_host" ]]; then
        LAN_HOST="$input_lan_host"
    else
        LAN_HOST="$DEFAULT_LAN_HOST"
    fi
fi
echo ""

# --- Install packages ---
step "Installing packages"
if dpkg -s openssh &>/dev/null 2>&1 || command -v ssh &>/dev/null; then
    ok "openssh already installed"
else
    pkg update -y
    pkg install -y openssh
    ok "openssh installed"
fi

# --- SSH key ---
step "Setting up SSH key"
mkdir -p ~/.ssh
if [[ -f ~/.ssh/id_ed25519 ]]; then
    ok "SSH key already exists"
else
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "termux@android"
    ok "SSH key generated"
fi

# --- SSH config ---
step "Configuring SSH"
if [[ -n "$LAN_HOST" ]]; then
    SSH_BLOCK=$(cat << EOF
# vaibhav — Desktop connection
Host desktop
    HostName ${DESKTOP_HOST}
    User ${DESKTOP_USER}
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
    ServerAliveCountMax 5
    Compression yes
Match host desktop exec "ping -c 1 -W 1 ${LAN_HOST} >/dev/null 2>&1"
    HostName ${LAN_HOST}
EOF
)
else
    SSH_BLOCK=$(cat << EOF
# vaibhav — Desktop connection
Host desktop
    HostName ${DESKTOP_HOST}
    User ${DESKTOP_USER}
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
    ServerAliveCountMax 5
    Compression yes
EOF
)
fi

if grep -q "# vaibhav — Desktop connection" ~/.ssh/config 2>/dev/null; then
    # Extract existing block and compare
    existing_block=$(awk '/^# vaibhav — Desktop connection/,/^$/' ~/.ssh/config | sed '/^$/d')
    if [[ "$existing_block" == "$SSH_BLOCK" ]]; then
        ok "SSH config already configured"
    else
        # Replace existing block: remove old block (from marker to next blank line or EOF)
        awk '
            /^# vaibhav — Desktop connection/ { skip=1; next }
            skip && /^$/ { skip=0; next }
            skip { next }
            { print }
        ' ~/.ssh/config > ~/.ssh/config.tmp
        mv ~/.ssh/config.tmp ~/.ssh/config
        chmod 600 ~/.ssh/config
        printf '\n%s\n' "$SSH_BLOCK" >> ~/.ssh/config
        ok "SSH config updated"
    fi
elif grep -q "^Host desktop$" ~/.ssh/config 2>/dev/null; then
    # Existing Host desktop block without vaibhav marker — replace it
    echo -e "  ${YELLOW}Note:${NC} Replacing existing 'Host desktop' SSH config block"
    awk '
        /^Host desktop$/ { skip=1; next }
        skip && /^$/ { skip=0; next }
        skip && /^Match[[:space:]]+host[[:space:]]+desktop([[:space:]]|$)/ { next }
        skip && /^[^ \t]/ { skip=0 }
        !skip { print }
    ' ~/.ssh/config > ~/.ssh/config.tmp
    mv ~/.ssh/config.tmp ~/.ssh/config
    chmod 600 ~/.ssh/config
    printf '\n%s\n' "$SSH_BLOCK" >> ~/.ssh/config
    ok "SSH config updated (replaced existing Host desktop block)"
else
    printf '\n%s\n' "$SSH_BLOCK" >> ~/.ssh/config
    chmod 600 ~/.ssh/config
    ok "SSH config added (Host: desktop)"
fi

# --- Copy SSH key to desktop ---
step "Setting up SSH key on desktop"
if ssh -o BatchMode=yes -o ConnectTimeout=5 desktop "echo ok" &>/dev/null; then
    ok "SSH key already works"
else
    echo -e "  ${DIM}Attempting ssh-copy-id (you'll need to enter your desktop password once)${NC}"
    echo ""
    if ssh-copy-id -i ~/.ssh/id_ed25519.pub desktop 2>/dev/null; then
        ok "SSH key copied to desktop"
    else
        warn "ssh-copy-id failed. Copy this key to your desktop manually:"
        echo ""
        cat ~/.ssh/id_ed25519.pub
        echo ""
        echo -e "  ${DIM}On your desktop, run:${NC}"
        echo -e "  ${DIM}echo '<paste_key>' >> ~/.ssh/authorized_keys${NC}"
        echo ""
        read -rp "Press Enter once done..." </dev/tty
    fi
fi

# --- Install vaibhav command ---
step "Installing vaibhav command"
mkdir -p ~/bin

curl -fsSL "https://raw.githubusercontent.com/manojlds/vaibhav/main/bin/vaibhav" -o ~/bin/vaibhav
chmod +x ~/bin/vaibhav
ok "~/bin/vaibhav installed"

# --- Configure vaibhav for remote mode ---
step "Configuring vaibhav"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" << EOF
# vaibhav configuration (remote mode)
VAIBHAV_DESKTOP_HOST="${DESKTOP_HOST}"
VAIBHAV_SSH_HOST="desktop"
VAIBHAV_MOSH_NO_INIT="true"
VAIBHAV_LAN_HOST="${LAN_HOST}"
EOF
ok "Config saved to $CONFIG_DIR/config"

# --- Run vaibhav setup for environment config ---
# This handles: mosh, vaibhav-ralph, PATH, extra keys, font
echo ""
"$HOME/bin/vaibhav" setup

# --- Summary ---
echo ""
echo -e "${BOLD}${GREEN}Termux setup complete!${NC}"
echo ""
echo -e "${BOLD}Quick start:${NC}"
echo "  vaibhav list               # See your projects"
echo "  vaibhav heimdall pi        # Start coding with pi (or amp/claude/codex/opencode)"
echo ""
echo -e "${BOLD}Tips:${NC}"
echo "  • Swipe left edge of screen → toggle extra keys"
echo "  • Pinch to zoom text size"
echo "  • Closing Termux keeps sessions alive on desktop"
echo "  • Alt+s to switch projects (once in tmux)"
if [[ -n "$LAN_HOST" ]]; then
    echo "  • SSH auto-switches: LAN (${LAN_HOST}) first, then Tailscale (${DESKTOP_HOST})"
fi
echo ""
echo -e "${DIM}Make sure Tailscale is running on both devices when outside home LAN!${NC}"
