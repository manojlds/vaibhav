# shellcheck shell=bash
# vaibhav/lib/setup.sh — Termux setup and update functions

# --- setup (Termux environment sync) ---
# Idempotent, non-interactive in --post-update mode
# Ensures Termux-side packages and config are up to date
setup_termux() {
    local post_update=false
    for arg in "$@"; do
        [[ "$arg" == "--post-update" ]] && post_update=true
    done

    if [[ "$post_update" == "false" ]]; then
        echo -e "${BOLD}vaibhav setup${NC}"
    fi

    # --- openssh ---
    step "Checking openssh"
    if command -v ssh &>/dev/null; then
        ok "openssh installed"
    else
        pkg install -y openssh
        ok "openssh installed"
    fi

    # --- SSH config (desktop alias) ---
    step "Checking SSH config"
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"

    local ssh_host_alias="${VAIBHAV_SSH_HOST:-desktop}"
    if [[ "$ssh_host_alias" != "desktop" ]]; then
        skip "custom SSH alias '${ssh_host_alias}' (not managed)"
    elif [[ -z "${VAIBHAV_DESKTOP_HOST:-}" ]]; then
        skip "VAIBHAV_DESKTOP_HOST not set"
    else
        local ssh_user=""
        ssh_user=$(awk '/^# vaibhav — Desktop connection/,/^$/{if($1=="User"){print $2; exit}}' "$HOME/.ssh/config" 2>/dev/null || true)

        if [[ -z "$ssh_user" ]]; then
            ssh_user=$(awk '
                /^Host desktop$/ { in_host=1; next }
                in_host && /^Host[[:space:]]+/ { in_host=0 }
                in_host && /^[[:space:]]*User[[:space:]]+/ { print $2; exit }
            ' "$HOME/.ssh/config" 2>/dev/null || true)
        fi

        if [[ -z "$ssh_user" ]]; then
            skip "desktop SSH user not found in ~/.ssh/config"
        else
            local lan_host="${VAIBHAV_LAN_HOST:-}"
            local has_lan_host_setting=false
            if [[ -f "$CONFIG_FILE" ]] && grep -q '^VAIBHAV_LAN_HOST=' "$CONFIG_FILE" 2>/dev/null; then
                has_lan_host_setting=true
            fi
            if [[ -z "$lan_host" ]] && [[ "$has_lan_host_setting" == "false" ]] && [[ ! "$VAIBHAV_DESKTOP_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                if [[ "$VAIBHAV_DESKTOP_HOST" == *.local ]]; then
                    lan_host="$VAIBHAV_DESKTOP_HOST"
                else
                    lan_host="${VAIBHAV_DESKTOP_HOST%%.*}.local"
                fi
            fi
            if [[ "$has_lan_host_setting" == "false" ]] && [[ -n "$lan_host" ]] && [[ -f "$CONFIG_FILE" ]]; then
                echo "VAIBHAV_LAN_HOST=\"${lan_host}\"" >> "$CONFIG_FILE"
                VAIBHAV_LAN_HOST="$lan_host"
            fi

            local ssh_block=""
            if [[ -n "$lan_host" ]]; then
                ssh_block=$(cat << EOF
# vaibhav — Desktop connection
Host desktop
    HostName ${VAIBHAV_DESKTOP_HOST}
    User ${ssh_user}
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
    ServerAliveCountMax 5
    Compression yes
Match host desktop exec "ping -c 1 -W 1 ${lan_host} >/dev/null 2>&1"
    HostName ${lan_host}
EOF
)
            else
                ssh_block=$(cat << EOF
# vaibhav — Desktop connection
Host desktop
    HostName ${VAIBHAV_DESKTOP_HOST}
    User ${ssh_user}
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
    ServerAliveCountMax 5
    Compression yes
EOF
)
            fi

            if grep -q "# vaibhav — Desktop connection" "$HOME/.ssh/config" 2>/dev/null; then
                local existing_block=""
                existing_block=$(awk '/^# vaibhav — Desktop connection/,/^$/' "$HOME/.ssh/config" | sed '/^$/d')
                if [[ "$existing_block" == "$ssh_block" ]]; then
                    ok "SSH config already configured"
                else
                    awk '
                        /^# vaibhav — Desktop connection/ { skip=1; next }
                        skip && /^Match.*desktop/ { next }
                        skip && /^[^ \t]/ { skip=0 }
                        skip && /^$/ { skip=0; next }
                        skip { next }
                        { print }
                    ' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp"
                    mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
                    chmod 600 "$HOME/.ssh/config"
                    printf '\n%s\n' "$ssh_block" >> "$HOME/.ssh/config"
                    ok "SSH config updated"
                fi
            elif grep -q "^Host desktop$" "$HOME/.ssh/config" 2>/dev/null; then
                awk '
                    /^Host desktop$/ { skip=1; next }
                    skip && /^$/ { skip=0; next }
                    skip && /^Match.*desktop/ { next }
                    skip && /^[^ \t]/ { skip=0 }
                    !skip { print }
                ' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp"
                mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
                chmod 600 "$HOME/.ssh/config"
                printf '\n%s\n' "$ssh_block" >> "$HOME/.ssh/config"
                ok "SSH config updated"
            else
                printf '\n%s\n' "$ssh_block" >> "$HOME/.ssh/config"
                chmod 600 "$HOME/.ssh/config"
                ok "SSH config added (Host: desktop)"
            fi
        fi
    fi

    # --- mosh ---
    step "Checking mosh"
    local mosh_just_installed=false
    if command -v mosh &>/dev/null; then
        ok "mosh already installed"
    elif [[ "${VAIBHAV_USE_MOSH:-false}" == "true" ]]; then
        pkg install -y mosh
        ok "mosh installed (VAIBHAV_USE_MOSH=true)"
        mosh_just_installed=true
    else
        # Check if desktop has mosh-server
        local desktop_has_mosh=false
        if [[ -n "${VAIBHAV_SSH_HOST:-}" ]] && ssh "${_VSSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$VAIBHAV_SSH_HOST" "command -v mosh-server" &>/dev/null; then
            desktop_has_mosh=true
        fi

        if [[ "$desktop_has_mosh" == "true" ]]; then
            echo -e "  ${DIM}Desktop has mosh-server — installing mosh client...${NC}"
            pkg install -y mosh
            ok "mosh installed (desktop has mosh-server)"
            mosh_just_installed=true
        elif [[ "$post_update" == "false" ]]; then
            read -rp "  Install mosh for resilient mobile connections? [y/N] " yn </dev/tty
            if [[ "$yn" =~ ^[Yy]$ ]]; then
                pkg install -y mosh
                ok "mosh installed"
                mosh_just_installed=true
            else
                skip "mosh (install later with: pkg install mosh)"
            fi
        else
            skip "mosh not installed"
        fi
    fi

    # Offer to enable mosh if installed but not enabled
    if command -v mosh &>/dev/null && [[ "${VAIBHAV_USE_MOSH:-false}" != "true" ]]; then
        if [[ "$mosh_just_installed" == "true" ]] || [[ "$post_update" == "false" ]]; then
            echo ""
            read -rp "  Enable mosh by default? (use mosh for all connections) [Y/n] " yn </dev/tty
            if [[ ! "$yn" =~ ^[Nn]$ ]]; then
                if [[ -f "$CONFIG_FILE" ]] && grep -q '^VAIBHAV_USE_MOSH=' "$CONFIG_FILE"; then
                    sed -i 's/^VAIBHAV_USE_MOSH=.*/VAIBHAV_USE_MOSH="true"/' "$CONFIG_FILE"
                else
                    echo 'VAIBHAV_USE_MOSH="true"' >> "$CONFIG_FILE"
                fi
                VAIBHAV_USE_MOSH="true"
                ok "mosh enabled (VAIBHAV_USE_MOSH=true)"
            else
                ok "mosh installed but not enabled (use --mosh flag per connection)"
            fi
        fi
    fi

    # --- vaibhav-ralph ---
    step "Checking vaibhav-ralph"
    if [[ -x "$HOME/bin/vaibhav-ralph" ]]; then
        ok "vaibhav-ralph installed"
    else
        echo -e "  ${DIM}Downloading vaibhav-ralph...${NC}"
        local ralph_url="https://raw.githubusercontent.com/manojlds/vaibhav/main/bin/vaibhav-ralph"
        if curl -fsSL "$ralph_url" -o "$HOME/bin/vaibhav-ralph"; then
            chmod +x "$HOME/bin/vaibhav-ralph"
            ok "vaibhav-ralph installed"
        else
            echo -e "  ${YELLOW}!${NC} Failed to download vaibhav-ralph (non-fatal)"
        fi
    fi

    # --- Shell PATH ---
    step "Checking PATH"
    local shell_rc="$HOME/.bashrc"
    if [[ -f "$HOME/.zshrc" ]]; then
        shell_rc="$HOME/.zshrc"
    fi

    # shellcheck disable=SC2016
    if grep -q 'PATH=.*\$HOME/bin' "$shell_rc" 2>/dev/null; then
        ok "PATH already configured in $shell_rc"
    else
        cat >> "$shell_rc" << 'PATHBLOCK'

# vaibhav
export PATH="$HOME/bin:$PATH"
PATHBLOCK
        ok "PATH configured in $shell_rc"
    fi

    # --- Termux extra keys ---
    step "Checking Termux keyboard"
    if [[ -d "$HOME/.termux" ]] || command -v termux-info &>/dev/null; then
        mkdir -p ~/.termux
        if [[ ! -f ~/.termux/termux.properties ]]; then
            cat > ~/.termux/termux.properties << 'PROPS'
# Extra keys row for multiplexer shortcuts and coding
extra-keys = [ \
  ['ESC', 'CTRL', 'ALT', 'TAB', '|', '-', 'UP', 'DOWN'] \
]
PROPS
            ok "Extra keyboard row configured"
        elif grep -q "extra-keys" ~/.termux/termux.properties 2>/dev/null; then
            ok "Extra keys already configured"
        else
            echo '' >> ~/.termux/termux.properties
            cat >> ~/.termux/termux.properties << 'PROPS'
# Extra keys row for multiplexer shortcuts and coding
extra-keys = [ \
  ['ESC', 'CTRL', 'ALT', 'TAB', '|', '-', 'UP', 'DOWN'] \
]
PROPS
            ok "Extra keyboard row added"
        fi
    else
        skip "not running in Termux"
    fi

    # --- Font (interactive only) ---
    if [[ "$post_update" == "false" ]] && command -v termux-info &>/dev/null; then
        step "Font setup"
        if [[ -f ~/.termux/font.ttf ]]; then
            ok "Custom font already installed"
        else
            read -rp "Install FiraCode Nerd Font? (recommended for icons) [Y/n] " yn </dev/tty
            if [[ ! "$yn" =~ ^[Nn]$ ]]; then
                curl -fsSL "https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/FiraCode/Regular/FiraCodeNerdFont-Regular.ttf" -o ~/.termux/font.ttf
                ok "FiraCode Nerd Font installed"
                termux-reload-settings 2>/dev/null || true
            else
                skip "font"
            fi
        fi
    fi

    echo ""
    echo -e "${GREEN}✓${NC} Setup complete"
}

GITHUB_REPO="manojlds/vaibhav"
GITHUB_RELEASES_BASE="https://github.com/${GITHUB_REPO}/releases"

update_termux() {
    local old_version="$VAIBHAV_VERSION"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "'"$tmp_dir"'"' EXIT

    echo -e "${DIM}Checking for updates...${NC}"

    local download_base="${GITHUB_RELEASES_BASE}/latest/download"

    # Release artifacts: dist/vaibhav (bundled), bin/vaibhav-ralph, bin/vaibhav-switcher
    local artifacts=("vaibhav" "vaibhav-ralph" "vaibhav-switcher")

    if ! curl -fsSL "${download_base}/vaibhav" -o "$tmp_dir/vaibhav"; then
        echo -e "${RED}Error:${NC} Failed to download latest vaibhav"
        return 1
    fi

    local remote_version
    remote_version=$(sed -n 's/^VAIBHAV_VERSION="\([^"]*\)"/\1/p' "$tmp_dir/vaibhav" | head -n1)
    if [[ -z "$remote_version" ]]; then
        echo -e "${RED}Error:${NC} Failed to determine latest version"
        return 1
    fi

    if [[ "$remote_version" == "$old_version" ]]; then
        echo -e "Already up to date (v${old_version})"
        return 0
    fi

    local highest_version
    highest_version=$(printf '%s\n%s\n' "$old_version" "$remote_version" | sort -V | tail -n1)
    if [[ "$highest_version" == "$old_version" ]]; then
        echo -e "Installed version (v${old_version}) is newer than latest release (v${remote_version}); skipping"
        return 0
    fi

    for artifact in "${artifacts[@]}"; do
        [[ "$artifact" == "vaibhav" ]] && continue  # already downloaded
        if ! curl -fsSL "${download_base}/${artifact}" -o "$tmp_dir/${artifact}"; then
            echo -e "${RED}Error:${NC} Failed to download ${artifact}"
            return 1
        fi
    done

    if ! curl -fsSL "${download_base}/checksums.sha256" -o "$tmp_dir/checksums.sha256"; then
        echo -e "${RED}Error:${NC} Failed to download checksums.sha256"
        return 1
    fi

    # Verify checksums — map release paths to downloaded files
    mkdir -p "$tmp_dir/verify/dist" "$tmp_dir/verify/bin"
    cp "$tmp_dir/vaibhav" "$tmp_dir/verify/dist/vaibhav"
    cp "$tmp_dir/vaibhav-ralph" "$tmp_dir/verify/bin/vaibhav-ralph"
    cp "$tmp_dir/vaibhav-switcher" "$tmp_dir/verify/bin/vaibhav-switcher"

    local checksum_ok=true
    while read -r expected_hash filepath; do
        case "$filepath" in
            dist/*|bin/*) ;;
            *) continue ;;
        esac
        [[ ! -f "$tmp_dir/verify/$filepath" ]] && continue
        local actual_hash
        actual_hash=$(sha256sum "$tmp_dir/verify/$filepath" | cut -d' ' -f1)
        if [[ "$expected_hash" != "$actual_hash" ]]; then
            echo -e "${RED}Error:${NC} Checksum verification failed for $filepath"
            echo -e "  Expected: ${expected_hash}"
            echo -e "  Got:      ${actual_hash}"
            checksum_ok=false
        fi
    done < "$tmp_dir/checksums.sha256"

    if [[ "$checksum_ok" != "true" ]]; then
        echo -e "${RED}Update aborted:${NC} Checksum verification failed. Existing files unchanged."
        return 1
    fi

    # Stage in ~/bin so mv is same-filesystem (atomic rename, preserves old inode)
    # cp would overwrite inode contents while bash is still reading this script
    for artifact in "${artifacts[@]}"; do
        cp "$tmp_dir/$artifact" "$HOME/bin/${artifact}.new"
        chmod +x "$HOME/bin/${artifact}.new"
        mv -f "$HOME/bin/${artifact}.new" "$HOME/bin/${artifact}"
    done

    echo -e "${GREEN}✓${NC} Updated: v${old_version} → v${remote_version}"
    return 0
}

update_desktop_remote() {
    # SSH to the desktop and run git pull in the vaibhav repo
    echo ""
    echo -e "${DIM}Updating desktop via SSH...${NC}"

    # Discover the repo path on the desktop via readlink
    local remote_repo
    # shellcheck disable=SC2016
    if ! remote_repo=$(ssh "${_VSSH_OPTS[@]}" "$VAIBHAV_SSH_HOST" 'repo=$(dirname "$(dirname "$(readlink -f "$HOME/bin/vaibhav")")") && echo "$repo"' 2>/dev/null); then
        echo -e "${YELLOW}Warning:${NC} Could not connect to desktop via SSH — skipping desktop update"
        return 0
    fi

    if [[ -z "$remote_repo" ]]; then
        echo -e "${YELLOW}Warning:${NC} Could not resolve vaibhav repo path on desktop — skipping desktop update"
        return 0
    fi

    # Get the old version on the desktop before pulling
    local desktop_old_version
    # shellcheck disable=SC2029
    desktop_old_version=$(ssh "${_VSSH_OPTS[@]}" "$VAIBHAV_SSH_HOST" "grep '^VAIBHAV_VERSION=' '$remote_repo/bin/vaibhav' | cut -d'\"' -f2" 2>/dev/null) || desktop_old_version="unknown"

    # Check for local changes on desktop
    # shellcheck disable=SC2029
    if ! ssh "${_VSSH_OPTS[@]}" "$VAIBHAV_SSH_HOST" "git -C '$remote_repo' diff --quiet 2>/dev/null && git -C '$remote_repo' diff --cached --quiet 2>/dev/null" 2>/dev/null; then
        echo -e "${YELLOW}Warning:${NC} Desktop has local changes — skipping desktop update"
        return 0
    fi

    # Run git pull on the desktop
    local pull_output
    # shellcheck disable=SC2029
    if ! pull_output=$(ssh "${_VSSH_OPTS[@]}" "$VAIBHAV_SSH_HOST" "git -C '$remote_repo' fetch origin && git -C '$remote_repo' checkout main && git -C '$remote_repo' pull origin main" 2>&1); then
        echo -e "${YELLOW}Warning:${NC} Desktop git pull failed — skipping"
        echo -e "  ${DIM}${pull_output}${NC}"
        return 0
    fi

    if echo "$pull_output" | grep -q "Already up to date"; then
        echo -e "${GREEN}✓${NC} Desktop already up to date (v${desktop_old_version})"
    else
        local desktop_new_version
        # shellcheck disable=SC2029
        desktop_new_version=$(ssh "${_VSSH_OPTS[@]}" "$VAIBHAV_SSH_HOST" "grep '^VAIBHAV_VERSION=' '$remote_repo/bin/vaibhav' | cut -d'\"' -f2" 2>/dev/null) || desktop_new_version="unknown"
        echo -e "${GREEN}✓${NC} Desktop updated: v${desktop_old_version} → v${desktop_new_version}"
    fi
    return 0
}

update_desktop() {
    # Resolve repo directory from the symlink at ~/bin/vaibhav
    local vaibhav_bin
    vaibhav_bin=$(readlink -f "$HOME/bin/vaibhav")
    if [[ -z "$vaibhav_bin" || ! -f "$vaibhav_bin" ]]; then
        echo -e "${RED}Error:${NC} Cannot resolve vaibhav installation path from ~/bin/vaibhav"
        return 1
    fi
    # Two levels up: bin/vaibhav -> bin/ -> repo root
    local repo_dir
    repo_dir=$(cd "$(dirname "$vaibhav_bin")/.." && pwd)

    if [[ ! -d "$repo_dir/.git" ]]; then
        echo -e "${RED}Error:${NC} Not a git repository: $repo_dir"
        return 1
    fi

    local old_version="$VAIBHAV_VERSION"

    # Check for local changes that would conflict with pull
    if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
        echo -e "${YELLOW}Warning:${NC} Local changes detected in $repo_dir"
        echo -e "  ${DIM}Commit or stash your changes before updating.${NC}"
        return 1
    fi

    # Run git pull
    local pull_output
    pull_output=$(git -C "$repo_dir" checkout main && git -C "$repo_dir" pull origin main 2>&1) || {
        echo -e "${RED}Error:${NC} git pull failed"
        echo "$pull_output"
        return 1
    }

    # Check if already up to date
    if echo "$pull_output" | grep -q "Already up to date"; then
        echo -e "Already up to date (v${old_version})"
        return 0
    fi

    # Source the new version
    local new_version
    new_version=$(grep '^VAIBHAV_VERSION=' "$vaibhav_bin" | cut -d'"' -f2)

    echo -e "${GREEN}✓${NC} Updated: v${old_version} → v${new_version}"

    # Update skills in any initialized projects
    local skills_source="$repo_dir/skills"
    if [[ -d "$skills_source" && -s "$PROJECTS_FILE" ]]; then
        local updated=0
        while IFS='=' read -r name path; do
            [[ -z "$name" || "$name" == \#* ]] && continue
            if [[ -d "$path/.agents/skills/vaibhav-loop" ]]; then
                local target="$path/.agents/skills"
                for skill_dir in "$skills_source"/vaibhav-*/; do
                    [[ -d "$skill_dir" ]] && cp -r "$skill_dir" "$target/"
                done
                updated=$((updated + 1))
            fi
        done < "$PROJECTS_FILE"
        if [[ $updated -gt 0 ]]; then
            echo -e "${GREEN}✓${NC} Updated skills in ${updated} project(s)"
        fi
    fi

    return 0
}
