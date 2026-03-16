# shellcheck shell=bash
# vaibhav/lib/init.sh — Interactive setup (vaibhav init)

init_config() {
    echo -e "${BOLD}vaibhav init${NC}"
    echo ""

    local current_projects_dir="${VAIBHAV_PROJECTS_DIR:-}"
    local current_desktop_host="${VAIBHAV_DESKTOP_HOST:-}"
    local current_ssh_host="${VAIBHAV_SSH_HOST:-desktop}"
    local current_mosh_no_init="${VAIBHAV_MOSH_NO_INIT:-true}"
    # Projects directory
    local default_projects_dir="${current_projects_dir:-$HOME/projects}"
    read -rp "Projects directory [${default_projects_dir}]: " input_projects_dir
    local projects_dir="${input_projects_dir:-$default_projects_dir}"

    # Desktop hostname (for remote mode)
    local default_desktop_host="${current_desktop_host:-$(hostname)}"
    read -rp "Desktop hostname [${default_desktop_host}]: " input_desktop_host
    local desktop_host="${input_desktop_host:-$default_desktop_host}"

    # SSH host alias (for remote mode)
    local default_ssh_host="${current_ssh_host}"
    read -rp "SSH host alias [${default_ssh_host}]: " input_ssh_host
    local ssh_host="${input_ssh_host:-$default_ssh_host}"

    # Mosh (optional)
    read -rp "Use mosh by default? [y/N] " input_use_mosh
    local use_mosh="false"
    if [[ "$input_use_mosh" =~ ^[Yy]$ ]]; then
        use_mosh="true"
    fi

    # Write config
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
# vaibhav configuration
VAIBHAV_PROJECTS_DIR="${projects_dir}"
VAIBHAV_DESKTOP_HOST="${desktop_host}"
VAIBHAV_SSH_HOST="${ssh_host}"
VAIBHAV_USE_MOSH="${use_mosh}"
VAIBHAV_MOSH_NO_INIT="${current_mosh_no_init}"
VAIBHAV_MULTIPLEXER="tmux"
EOF

    echo ""
    echo -e "${GREEN}✓${NC} Config saved to ${CYAN}${CONFIG_FILE}${NC}"
    echo ""
    cat "$CONFIG_FILE"

    # Offer to scan projects
    if [[ -d "$projects_dir" ]]; then
        echo ""
        read -rp "Scan ${projects_dir} for projects? [Y/n] " yn
        if [[ ! "$yn" =~ ^[Nn]$ ]]; then
            # Reload config
            # shellcheck source=/dev/null
            source "$CONFIG_FILE"
            scan_projects "$projects_dir"
        fi
    fi
}
