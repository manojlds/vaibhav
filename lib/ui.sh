# shellcheck shell=bash
# vaibhav/lib/ui.sh — Colors and UI helpers

# Colors (used across all sourced modules)
# shellcheck disable=SC2034
RED='\033[0;31m'
# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

step() { echo -e "\n${CYAN}▶${NC} ${BOLD}$1${NC}"; }
ok() { echo -e "  ${GREEN}✓${NC} $1"; }
skip() { echo -e "  ${DIM}skip${NC} $1"; }

show_usage() {
    echo -e "${BOLD}vaibhav${NC} ${DIM}v${VAIBHAV_VERSION}${NC} — Project session manager for AI coding tools"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  vaibhav init                Interactive setup"
    echo "  vaibhav list                List all projects and active sessions"
    echo "  vaibhav <name>              Open a project in tmux"
    echo "  vaibhav <name> <tool>       Open a project with an AI tool (amp, claude, codex, opencode, pi)"
    echo "  vaibhav <name> --mosh       Open a project using mosh (resilient connection)"
    echo "  vaibhav <name> <tool> --mosh  Open with an AI tool via mosh"
    echo "  vaibhav add <name> <path>   Register a new project"
    echo "  vaibhav kill <name>         Kill a project's session"
    echo "  vaibhav kill <name> <win>   Kill a specific window/tab in a project"
    echo "  vaibhav remove <name>       Unregister a project"
    echo "  vaibhav scan [dir]          Auto-register projects under a directory"
    echo "  vaibhav share [file] [dir]  Share files (copy to ~/vaibhav-share, list shared files)"
    echo "  vaibhav dev [cmd] [project] Manage dev servers (start, stop, list, restart)"
    echo "  vaibhav web                 Show/manage OpenCode Web + Files services"
    echo "  vaibhav doctor              Check SSH routing (LAN vs Tailscale)"
    echo "  vaibhav refresh             Detect desktop LAN IP and save it to config"
    echo "  vaibhav doctor --refresh-lan  Same as refresh + doctor output"
    echo "  vaibhav setup               Set up Termux environment (packages, config)"
    echo "  vaibhav update              Update vaibhav to the latest version"
    echo "  vaibhav ralph ...           Ralph loop utility (run 'vaibhav ralph help' for details)"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  vaibhav init                First-time setup"
    echo "  vaibhav heimdall pi         Open heimdall project with pi"
    echo "  vaibhav doctor              See whether desktop uses LAN or Tailscale"
    echo "  vaibhav refresh             Refresh LAN IP after connecting via Tailscale"
    echo "  vaibhav scan ~/projects     Register all projects under ~/projects"
    echo "  vaibhav ralph init          Setup ralph config for current project"
    echo ""
    if [[ -n "$VAIBHAV_MUX_BACKEND" ]]; then
        echo -e "${BOLD}Multiplexer:${NC} tmux"
    else
        echo -e "${BOLD}Multiplexer:${NC} ${DIM}tmux not found${NC}"
    fi
    echo -e "${BOLD}Config:${NC} ${CONFIG_FILE}"
}
