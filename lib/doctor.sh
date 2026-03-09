# shellcheck shell=bash
# vaibhav/lib/doctor.sh — Doctor, web status, refresh, and network helpers

show_web_status() {
    local url_only=false
    for arg in "$@"; do
        [[ "$arg" == "--url-only" ]] && url_only=true
    done

    # Check if opencode-web service is running
    local service_active=false
    if systemctl --user is-active --quiet opencode-web 2>/dev/null; then
        service_active=true
    fi

    # Get port from the service file
    local port=4096
    local service_file="$HOME/.config/systemd/user/opencode-web.service"
    if [[ -f "$service_file" ]]; then
        local parsed_port
        parsed_port=$(grep -o -- '--port [0-9]*' "$service_file" | awk '{print $2}')
        if [[ -n "$parsed_port" ]]; then
            port="$parsed_port"
        fi
    fi

    # Get tailscale serve URL
    local ts_url=""
    if command -v tailscale &>/dev/null; then
        local ts_hostname
        ts_hostname=$(tailscale status --json 2>/dev/null | grep -m1 '"DNSName"' | grep -o '"DNSName": *"[^"]*"' | cut -d'"' -f4 | sed 's/\.$//')
        if [[ -n "$ts_hostname" ]]; then
            # Check tailscale serve status for the actual external port
            local ts_port
            ts_port=$(tailscale serve status --json 2>/dev/null | grep -o '"https://[^"]*"' | head -1 | grep -o ':[0-9]*' | tr -d ':' || true)
            if [[ -z "$ts_port" || "$ts_port" == "443" ]]; then
                ts_url="https://${ts_hostname}"
            else
                ts_url="https://${ts_hostname}:${ts_port}"
            fi
        fi
    fi

    if [[ "$url_only" == "true" ]]; then
        if [[ -n "$ts_url" ]]; then
            echo "$ts_url"
        else
            echo "http://127.0.0.1:${port}"
        fi
        return 0
    fi

    echo -e "${BOLD}OpenCode Web${NC}"
    echo ""

    # Service status
    if [[ "$service_active" == "true" ]]; then
        echo -e "  Service:  ${GREEN}running${NC}"
        local health
        health=$(curl -sf "http://127.0.0.1:${port}/global/health" 2>/dev/null || echo "")
        if [[ -n "$health" ]]; then
            echo -e "  Health:   ${GREEN}healthy${NC}"
        else
            echo -e "  Health:   ${RED}unreachable${NC}"
        fi
    else
        echo -e "  Service:  ${RED}stopped${NC}"
        echo -e "  ${DIM}Start with: systemctl --user start opencode-web${NC}"
        echo -e "  ${DIM}Or re-run:  ./setup-desktop.sh${NC}"
        return 0
    fi

    # URLs
    echo -e "  Local:    ${CYAN}http://127.0.0.1:${port}${NC}"
    if [[ -n "$ts_url" ]]; then
        echo -e "  Tailscale:${BOLD} ${ts_url}${NC}"
    else
        echo -e "  Tailscale:${DIM} not configured${NC}"
    fi

    # Password hint
    if [[ -f "$service_file" ]] && grep -q 'OPENCODE_SERVER_PASSWORD' "$service_file"; then
        echo -e "  Password: ${DIM}set (see systemd unit)${NC}"
    fi

    echo ""
}

is_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    local IFS='.'
    read -r o1 o2 o3 o4 <<< "$ip"
    for octet in "$o1" "$o2" "$o3" "$o4"; do
        [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
        (( octet >= 0 && octet <= 255 )) || return 1
    done
    return 0
}

is_tailscale_ipv4() {
    local ip="$1"
    is_ipv4 "$ip" || return 1

    local IFS='.'
    read -r o1 o2 _ _ <<< "$ip"
    (( o1 == 100 && o2 >= 64 && o2 <= 127 ))
}

update_config_value() {
    local key="$1"
    local value="$2"

    mkdir -p "$CONFIG_DIR"
    touch "$CONFIG_FILE"

    if grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$CONFIG_FILE"
    else
        echo "${key}=\"${value}\"" >> "$CONFIG_FILE"
    fi
}

refresh_lan_host_from_desktop() {
    local ssh_alias="${VAIBHAV_SSH_HOST:-desktop}"

    local remote_cmd=""
    remote_cmd=$(cat <<'EOF'
iface=$(ip -4 route show default 2>/dev/null | awk '$5!="tailscale0"{print $5; exit}')
ip=""
if [ -n "$iface" ]; then
    ip=$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
fi
if [ -z "$ip" ]; then
    ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '$2!="tailscale0"{print $4}' | cut -d/ -f1 | head -n1)
fi
printf '%s' "$ip"
EOF
)

    local detected_ip=""

    # Prefer explicit desktop host (usually Tailscale) so stale LAN overrides don't interfere.
    if [[ -n "${VAIBHAV_DESKTOP_HOST:-}" ]]; then
        detected_ip=$(ssh -o "HostName=$VAIBHAV_DESKTOP_HOST" -o BatchMode=yes -o ConnectTimeout=8 "$ssh_alias" "$remote_cmd" 2>/dev/null || true)
    fi

    if [[ -z "$detected_ip" ]]; then
        detected_ip=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$ssh_alias" "$remote_cmd" 2>/dev/null || true)
    fi

    detected_ip="${detected_ip//$'\r'/}"
    detected_ip="${detected_ip//$'\n'/}"

    if [[ -z "$detected_ip" ]]; then
        echo -e "  ${YELLOW}!${NC} Could not query desktop over SSH (connect via Tailscale or LAN first)"
        return 1
    fi

    if ! is_ipv4 "$detected_ip"; then
        echo -e "  ${YELLOW}!${NC} Desktop did not return a valid LAN IPv4 address"
        return 1
    fi

    if is_tailscale_ipv4 "$detected_ip"; then
        echo -e "  ${YELLOW}!${NC} Detected IP ${detected_ip} looks like a Tailscale address; not updating LAN host"
        return 1
    fi

    update_config_value "VAIBHAV_LAN_HOST" "$detected_ip"
    VAIBHAV_LAN_HOST="$detected_ip"

    _VSSH_OPTS=()
    if ping -c 1 -W 2 "$VAIBHAV_LAN_HOST" >/dev/null 2>&1; then
        _VSSH_OPTS=(-o "HostName=$VAIBHAV_LAN_HOST")
    fi

    echo -e "  ${GREEN}✓${NC} LAN host updated: ${CYAN}${detected_ip}${NC}"
    echo -e "  ${DIM}Saved to ${CONFIG_FILE}${NC}"
    return 0
}

run_refresh() {
    echo -e "${BOLD}vaibhav refresh${NC}"
    echo ""
    refresh_lan_host_from_desktop
    echo ""
    show_doctor # intentionally no args
}

# shellcheck disable=SC2120
show_doctor() {
    local refresh_lan=false
    for arg in "$@"; do
        case "$arg" in
            --refresh-lan|--refresh-lan-ip|--update-lan-ip)
                refresh_lan=true
                ;;
        esac
    done

    echo -e "${BOLD}vaibhav doctor${NC}"
    echo ""

    if [[ "$refresh_lan" == "true" ]]; then
        echo -e "  ${DIM}Refreshing LAN host from desktop...${NC}"
        refresh_lan_host_from_desktop || true
        echo ""
    fi

    local ssh_alias="${VAIBHAV_SSH_HOST:-desktop}"
    local tailscale_host="${VAIBHAV_DESKTOP_HOST:-}"
    local lan_host="${VAIBHAV_LAN_HOST:-}"
    local ssh_user=""
    local alias_configured=false

    local on_desktop=false
    if [[ -n "${VAIBHAV_DESKTOP_HOST:-}" ]] && [[ "$(hostname)" == "$VAIBHAV_DESKTOP_HOST" ]]; then
        on_desktop=true
    fi

    local vaibhav_block=""
    if [[ -f "$HOME/.ssh/config" ]]; then
        vaibhav_block=$(awk '/^# vaibhav — Desktop connection/,/^$/' "$HOME/.ssh/config" 2>/dev/null || true)
    fi

    if [[ -z "$tailscale_host" ]] && [[ -n "$vaibhav_block" ]]; then
        tailscale_host=$(printf '%s\n' "$vaibhav_block" | awk '$1=="HostName"{print $2; exit}')
    fi
    if [[ -z "$lan_host" ]] && [[ -n "$vaibhav_block" ]]; then
        lan_host=$(printf '%s\n' "$vaibhav_block" | sed -n 's/.*ping -c 1 -W 1 \([^ ]*\) .*/\1/p' | head -n1)
    fi

    if [[ -f "$HOME/.ssh/config" ]]; then
        if awk -v h="$ssh_alias" '$1=="Host"{for(i=2;i<=NF;i++){if($i==h){found=1}}} END{exit !found}' "$HOME/.ssh/config" 2>/dev/null; then
            alias_configured=true
        fi
    fi

    if [[ "$alias_configured" == "true" ]] && command -v ssh &>/dev/null; then
        ssh_user=$(ssh -G "$ssh_alias" 2>/dev/null | awk '$1=="user"{print $2; exit}')
    elif [[ -n "$vaibhav_block" ]]; then
        ssh_user=$(printf '%s\n' "$vaibhav_block" | awk '$1=="User"{print $2; exit}')
    fi

    if [[ "$on_desktop" == "true" ]]; then
        echo -e "  Mode:            ${DIM}desktop (routing checks are most useful on Termux)${NC}"
    fi

    echo -e "  SSH alias:       ${CYAN}${ssh_alias}${NC}"
    if [[ -n "$ssh_user" ]]; then
        echo -e "  SSH user:        ${CYAN}${ssh_user}${NC}"
    fi

    if [[ -n "$tailscale_host" ]]; then
        echo -e "  Tailscale host:  ${CYAN}${tailscale_host}${NC}"
    else
        echo -e "  Tailscale host:  ${YELLOW}not set${NC}"
    fi

    local lan_reachable="unknown"
    if [[ -n "$lan_host" ]]; then
        if command -v ping &>/dev/null; then
            if ping -c 1 -W 2 "$lan_host" >/dev/null 2>&1; then
                lan_reachable="yes"
            else
                lan_reachable="no"
            fi
            if [[ "$lan_reachable" == "yes" ]]; then
                echo -e "  LAN host:        ${CYAN}${lan_host}${NC} ${GREEN}(reachable)${NC}"
            else
                echo -e "  LAN host:        ${CYAN}${lan_host}${NC} ${DIM}(not reachable)${NC}"
            fi
        else
            echo -e "  LAN host:        ${CYAN}${lan_host}${NC}"
        fi
    else
        echo -e "  LAN host:        ${DIM}not set${NC}"
    fi

    local effective_host=""
    if [[ -n "$lan_host" && "$lan_reachable" == "yes" ]]; then
        effective_host="$lan_host"
    elif [[ "$alias_configured" == "true" ]] && command -v ssh &>/dev/null; then
        effective_host=$(ssh -G "$ssh_alias" 2>/dev/null | awk '$1=="hostname"{print $2; exit}')
    fi

    if [[ -z "$effective_host" || "$effective_host" == "$ssh_alias" ]]; then
        effective_host="${tailscale_host:-}"
    fi

    if [[ -n "$effective_host" ]]; then
        echo -e "  Current target:  ${BOLD}${effective_host}${NC}"
    else
        echo -e "  Current target:  ${YELLOW}unknown${NC}"
    fi

    if [[ "$alias_configured" != "true" ]]; then
        echo -e "  SSH config:      ${YELLOW}alias '${ssh_alias}' not found in ~/.ssh/config${NC}"
    fi

    if command -v ssh &>/dev/null; then
        local ssh_debug=""
        if ssh "${_VSSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$ssh_alias" "echo ok" >/dev/null 2>&1; then
            echo -e "  SSH key auth:    ${GREEN}ok${NC}"
        else
            echo -e "  SSH key auth:    ${YELLOW}failed${NC}"
            ssh_debug=$(ssh "${_VSSH_OPTS[@]}" -v -o BatchMode=yes -o ConnectTimeout=5 "$ssh_alias" "echo ok" 2>&1 || true)
            echo -e "  ${DIM}--- SSH debug ---${NC}"
            echo "$ssh_debug" | grep -iE 'connect|resolve|hostname|identity|auth|offer|accept|reject|error|fail|denied|timeout|key' | while read -r line; do
                echo -e "  ${DIM}${line}${NC}"
            done
            echo -e "  ${DIM}--- end ---${NC}"
        fi
    fi

    echo ""
}
