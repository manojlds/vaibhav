# shellcheck shell=bash
# vaibhav/lib/doctor.sh — Doctor, web status, refresh, and network helpers

parse_service_port_from_unit() {
    local service_file="$1"
    local default_port="$2"

    local parsed_port=""
    if [[ -f "$service_file" ]]; then
        parsed_port=$(grep -o -- '--port [0-9]*' "$service_file" 2>/dev/null | awk '{print $2}' | head -n1 || true)
    fi

    printf '%s\n' "${parsed_port:-$default_port}"
}

get_tailscale_serve_url_for_proxy() {
    local proxy_url="$1"

    if ! command -v tailscale &>/dev/null; then
        return 0
    fi

    local serve_json=""
    serve_json=$(tailscale serve status --json 2>/dev/null || true)
    if [[ -z "$serve_json" ]]; then
        return 0
    fi

    local hostport=""
    if command -v python3 &>/dev/null; then
        hostport=$(printf '%s' "$serve_json" | python3 -c '
import json
import sys

target = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)

for host, meta in (data.get("Web") or {}).items():
    handlers = (meta or {}).get("Handlers") or {}
    for handler in handlers.values():
        if isinstance(handler, dict) and handler.get("Proxy") == target:
            print(host)
            raise SystemExit(0)
' "$proxy_url" 2>/dev/null || true)
    fi

    if [[ -z "$hostport" ]]; then
        hostport=$(printf '%s\n' "$serve_json" | awk -v target="$proxy_url" '
            match($0, /"([^"]+)"[[:space:]]*:[[:space:]]*\{/, m) {
                if (m[1] ~ /:[0-9]+$/) {
                    current = m[1]
                }
            }
            index($0, "\"Proxy\": \"" target "\"") > 0 {
                print current
                exit
            }
        ' 2>/dev/null || true)
    fi

    if [[ -z "$hostport" ]]; then
        return 0
    fi

    if [[ "$hostport" == *":443" ]]; then
        printf 'https://%s\n' "${hostport%:443}"
    else
        printf 'https://%s\n' "$hostport"
    fi
}

opencode_web_local_url() {
    local service_file="$HOME/.config/systemd/user/opencode-web.service"
    local port
    port=$(parse_service_port_from_unit "$service_file" "4096")
    printf 'http://127.0.0.1:%s\n' "$port"
}

zellij_web_local_url() {
    local service_file="$HOME/.config/systemd/user/zellij-web.service"
    local port
    port=$(parse_service_port_from_unit "$service_file" "8082")
    printf 'http://127.0.0.1:%s\n' "$port"
}

opencode_web_effective_url() {
    local local_url
    local_url=$(opencode_web_local_url)
    local ts_url
    ts_url=$(get_tailscale_serve_url_for_proxy "$local_url")

    if [[ -n "$ts_url" ]]; then
        printf '%s\n' "$ts_url"
    else
        printf '%s\n' "$local_url"
    fi
}

zellij_web_effective_url() {
    local local_url
    local_url=$(zellij_web_local_url)
    local ts_url
    ts_url=$(get_tailscale_serve_url_for_proxy "$local_url")

    if [[ -n "$ts_url" ]]; then
        printf '%s\n' "$ts_url"
    else
        printf '%s\n' "$local_url"
    fi
}

files_local_url() {
    local service_file="$HOME/.config/systemd/user/vaibhav-files.service"
    local port
    port=$(parse_service_port_from_unit "$service_file" "9090")
    printf 'http://127.0.0.1:%s\n' "$port"
}

files_effective_url() {
    local local_url
    local_url=$(files_local_url)
    local ts_url
    ts_url=$(get_tailscale_serve_url_for_proxy "$local_url")

    if [[ -n "$ts_url" ]]; then
        printf '%s\n' "$ts_url"
    else
        printf '%s\n' "$local_url"
    fi
}

print_opencode_web_status() {
    local service_name="opencode-web"
    local service_file="$HOME/.config/systemd/user/opencode-web.service"
    local local_url
    local_url=$(opencode_web_local_url)
    local ts_url
    ts_url=$(get_tailscale_serve_url_for_proxy "$local_url")

    echo -e "${BOLD}OpenCode Web${NC}"
    echo ""

    if [[ -f "$service_file" ]]; then
        if systemctl --user is-active --quiet "$service_name" 2>/dev/null; then
            echo -e "  Service:  ${GREEN}running${NC}"
            local health
            health=$(curl -sf "${local_url}/global/health" 2>/dev/null || echo "")
            if [[ -n "$health" ]]; then
                echo -e "  Health:   ${GREEN}healthy${NC}"
            else
                echo -e "  Health:   ${RED}unreachable${NC}"
            fi
        else
            echo -e "  Service:  ${RED}stopped${NC}"
            echo -e "  ${DIM}Start with: vaibhav web opencode start${NC}"
        fi
    else
        echo -e "  Service:  ${DIM}not configured${NC}"
        echo -e "  ${DIM}Set up via: ./setup-desktop.sh${NC}"
    fi

    echo -e "  Local:    ${CYAN}${local_url}${NC}"
    if [[ -n "$ts_url" ]]; then
        echo -e "  Tailscale:${BOLD} ${ts_url}${NC}"
    else
        echo -e "  Tailscale:${DIM} not configured${NC}"
    fi

    if [[ -f "$service_file" ]] && grep -q 'OPENCODE_SERVER_PASSWORD' "$service_file"; then
        echo -e "  Password: ${DIM}set (see systemd unit)${NC}"
    fi

    echo ""
}

print_zellij_web_status() {
    local service_name="zellij-web"
    local service_file="$HOME/.config/systemd/user/zellij-web.service"
    local local_url
    local_url=$(zellij_web_local_url)
    local ts_url
    ts_url=$(get_tailscale_serve_url_for_proxy "$local_url")

    echo -e "${BOLD}Zellij Web${NC}"
    echo ""

    if [[ -f "$service_file" ]]; then
        if systemctl --user is-active --quiet "$service_name" 2>/dev/null; then
            echo -e "  Service:  ${GREEN}running${NC}"
            if command -v zellij &>/dev/null; then
                local web_status
                web_status=$(zellij web --status 2>/dev/null || true)
                if echo "$web_status" | grep -qi 'online'; then
                    echo -e "  Health:   ${GREEN}healthy${NC}"
                else
                    echo -e "  Health:   ${RED}unreachable${NC}"
                fi
            else
                echo -e "  Health:   ${YELLOW}unknown${NC} ${DIM}(zellij binary not found)${NC}"
            fi
        else
            echo -e "  Service:  ${RED}stopped${NC}"
            echo -e "  ${DIM}Start with: vaibhav web zellij start${NC}"
        fi
    else
        echo -e "  Service:  ${DIM}not configured${NC}"
        echo -e "  ${DIM}Set up via: ./setup-desktop.sh${NC}"
    fi

    echo -e "  Local:    ${CYAN}${local_url}${NC}"
    if [[ -n "$ts_url" ]]; then
        echo -e "  Tailscale:${BOLD} ${ts_url}${NC}"
    else
        echo -e "  Tailscale:${DIM} not configured${NC}"
    fi

    if command -v zellij &>/dev/null; then
        echo -e "  Token:    ${DIM}create with: vaibhav web zellij token${NC}"
    fi

    echo ""
}

print_files_status() {
    local service_name="vaibhav-files"
    local service_file="$HOME/.config/systemd/user/vaibhav-files.service"
    local local_url
    local_url=$(files_local_url)
    local ts_url
    ts_url=$(get_tailscale_serve_url_for_proxy "$local_url")
    local share_dir="$HOME/vaibhav-share"

    echo -e "${BOLD}Vaibhav Files${NC}"
    echo ""

    if [[ -f "$service_file" ]]; then
        if systemctl --user is-active --quiet "$service_name" 2>/dev/null; then
            echo -e "  Service:  ${GREEN}running${NC}"
            if curl -sf "${local_url}/" >/dev/null 2>&1; then
                echo -e "  Health:   ${GREEN}healthy${NC}"
            else
                echo -e "  Health:   ${RED}unreachable${NC}"
            fi
        else
            echo -e "  Service:  ${RED}stopped${NC}"
            echo -e "  ${DIM}Start with: vaibhav web files start${NC}"
        fi
    else
        echo -e "  Service:  ${DIM}not configured${NC}"
        echo -e "  ${DIM}Set up via: ./setup-desktop.sh${NC}"
    fi

    echo -e "  Local:    ${CYAN}${local_url}${NC}"
    if [[ -n "$ts_url" ]]; then
        echo -e "  Tailscale:${BOLD} ${ts_url}${NC}"
    else
        echo -e "  Tailscale:${DIM} not configured${NC}"
    fi

    if [[ -d "$share_dir" ]]; then
        local file_count
        file_count=$(find "$share_dir" -type f 2>/dev/null | wc -l)
        echo -e "  Directory:${DIM} ${share_dir} (${file_count} files)${NC}"
    fi

    echo ""
}

show_web_usage() {
    echo -e "${BOLD}vaibhav web${NC}"
    echo ""
    echo "Usage:"
    echo "  vaibhav web                         Show OpenCode + Zellij web status"
    echo "  vaibhav web opencode               Show OpenCode Web status"
    echo "  vaibhav web zellij               Show Zellij Web status"
    echo "  vaibhav web <service> <action>    Manage service"
    echo ""
    echo "Services: opencode | zellij | files"
    echo "Actions:  status | start | stop | restart"
    echo "          zellij also supports: token | tokens"
    echo ""
    echo "Flags:"
    echo "  --url-only            Print OpenCode Web URL only"
    echo "  --zellij-url-only     Print Zellij Web URL only"
    echo "  --files-url-only      Print Vaibhav Files URL only"
}

web_service_control() {
    local target="$1"
    local action="$2"

    case "$target" in
        opencode)
            local op_service_file="$HOME/.config/systemd/user/opencode-web.service"
            if [[ ! -f "$op_service_file" ]]; then
                echo -e "${YELLOW}Warning:${NC} OpenCode Web service is not configured. Run ./setup-desktop.sh"
                return 1
            fi
            ;;
        zellij)
            local zj_service_file="$HOME/.config/systemd/user/zellij-web.service"
            if [[ "$action" == "token" ]]; then
                if ! command -v zellij &>/dev/null; then
                    echo -e "${RED}Error:${NC} zellij not found"
                    return 1
                fi
                zellij web --create-token
                return 0
            fi
            if [[ "$action" == "tokens" ]]; then
                if ! command -v zellij &>/dev/null; then
                    echo -e "${RED}Error:${NC} zellij not found"
                    return 1
                fi
                zellij web --list-tokens
                return 0
            fi
            if [[ ! -f "$zj_service_file" ]]; then
                echo -e "${YELLOW}Warning:${NC} Zellij Web service is not configured. Run ./setup-desktop.sh"
                return 1
            fi
            ;;
        files)
            local files_service_file="$HOME/.config/systemd/user/vaibhav-files.service"
            if [[ ! -f "$files_service_file" ]]; then
                echo -e "${YELLOW}Warning:${NC} Vaibhav Files service is not configured. Run ./setup-desktop.sh"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}Error:${NC} Unknown web service '${target}'"
            return 1
            ;;
    esac

    local service_name
    case "$target" in
        files) service_name="vaibhav-files" ;;
        *) service_name="${target}-web" ;;
    esac

    if ! systemctl --user "$action" "$service_name" >/dev/null 2>&1; then
        echo -e "${RED}Error:${NC} Failed to ${action} ${service_name}"
        return 1
    fi

    echo -e "${GREEN}✓${NC} ${service_name} ${action}"
    return 0
}

show_web_status() {
    local target=""
    local action="status"
    local url_only=false
    local zellij_url_only=false
    local files_url_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url-only)
                url_only=true
                ;;
            --zellij-url-only)
                zellij_url_only=true
                ;;
            --files-url-only)
                files_url_only=true
                ;;
            opencode|zellij|files)
                target="$1"
                ;;
            status|start|stop|restart|token|tokens)
                action="$1"
                ;;
            help|-h|--help)
                show_web_usage
                return 0
                ;;
            *)
                echo -e "${RED}Error:${NC} Unknown argument '$1'"
                show_web_usage
                return 1
                ;;
        esac
        shift
    done

    if [[ "$zellij_url_only" == "true" ]]; then
        echo "$(zellij_web_effective_url)"
        return 0
    fi

    if [[ "$files_url_only" == "true" ]]; then
        echo "$(files_effective_url)"
        return 0
    fi

    if [[ "$url_only" == "true" ]]; then
        if [[ "$target" == "zellij" ]]; then
            echo "$(zellij_web_effective_url)"
        elif [[ "$target" == "files" ]]; then
            echo "$(files_effective_url)"
        else
            echo "$(opencode_web_effective_url)"
        fi
        return 0
    fi

    if [[ "$action" != "status" ]]; then
        if [[ -z "$target" ]]; then
            echo -e "${RED}Error:${NC} Specify a service (opencode|zellij|files) for action '${action}'"
            show_web_usage
            return 1
        fi
        web_service_control "$target" "$action" || return 1
        echo ""
    fi

    case "$target" in
        opencode)
            print_opencode_web_status
            ;;
        zellij)
            print_zellij_web_status
            ;;
        files)
            print_files_status
            ;;
        "")
            print_opencode_web_status
            print_zellij_web_status
            print_files_status
            ;;
        *)
            echo -e "${RED}Error:${NC} Unknown web service '${target}'"
            return 1
            ;;
    esac
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
    if declare -F vaibhav_is_current_host_desktop >/dev/null 2>&1; then
        if vaibhav_is_current_host_desktop; then
            on_desktop=true
        fi
    elif [[ -n "${VAIBHAV_DESKTOP_HOST:-}" ]] && [[ "$(hostname)" == "$VAIBHAV_DESKTOP_HOST" ]]; then
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

share_files() {
    local share_dir="$HOME/vaibhav-share"

    if [[ $# -eq 0 ]]; then
        if [[ ! -d "$share_dir" ]]; then
            echo -e "${YELLOW}Share directory not set up.${NC}"
            echo -e "${DIM}Run ./setup-desktop.sh to configure the file sharing service.${NC}"
            return 1
        fi

        local url
        url=$(files_effective_url 2>/dev/null || echo "http://127.0.0.1:9090")

        echo -e "${BOLD}Vaibhav Files${NC}  ${CYAN}${url}${NC}"
        echo ""

        if [[ -z "$(ls -A "$share_dir" 2>/dev/null)" ]]; then
            echo -e "  ${DIM}(empty)${NC}"
        else
            find "$share_dir" -type f -printf '  %P\n' 2>/dev/null | sort
        fi

        echo ""
        echo -e "${DIM}Usage: vaibhav share <file> [subdir]${NC}"
        return 0
    fi

    local src="$1"
    local subdir="${2:-}"

    if [[ ! -e "$src" ]]; then
        echo -e "${RED}Error:${NC} File not found: $src"
        return 1
    fi

    mkdir -p "$share_dir"
    local dest_dir="$share_dir"
    if [[ -n "$subdir" ]]; then
        dest_dir="$share_dir/$subdir"
        mkdir -p "$dest_dir"
    fi

    cp -v "$src" "$dest_dir/"

    local filename
    filename=$(basename "$src")
    local url
    url=$(files_effective_url 2>/dev/null || echo "http://127.0.0.1:9090")
    local rel_path="${subdir:+$subdir/}$filename"

    echo -e "${GREEN}✓${NC} Shared: ${CYAN}${url}/${rel_path}${NC}"
}

api_status() {
    local projects_file="${PROJECTS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/vaibhav/projects}"
    local zellij_bin="${VAIBHAV_ZELLIJ_BIN:-$(command -v zellij 2>/dev/null || true)}"

    # Get active zellij sessions
    local active_sessions=""
    if [[ -n "$zellij_bin" ]]; then
        active_sessions=$("$zellij_bin" list-sessions --no-formatting 2>/dev/null | awk '
            /^[[:space:]]*$/ { next }
            /No active sessions/ { next }
            /\(EXITED/ { next }
            { print $1 }
        ' || true)
    fi

    # Build JSON
    printf '{"projects":['
    local first=true
    if [[ -f "$projects_file" ]]; then
        while IFS='=' read -r name path; do
            [[ -z "$name" || "$name" == \#* ]] && continue
            local active=false
            if [[ -n "$active_sessions" ]] && echo "$active_sessions" | grep -qx "$name" 2>/dev/null; then
                active=true
            fi
            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ','
            fi
            printf '{"name":"%s","path":"%s","active":%s}' "$name" "$path" "$active"
        done < "$projects_file"
    fi
    printf '],"sessions":['

    # List all active zellij sessions (including non-project ones)
    first=true
    if [[ -n "$active_sessions" ]]; then
        while IFS= read -r sess; do
            [[ -z "$sess" ]] && continue
            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ','
            fi
            printf '"%s"' "$sess"
        done <<< "$active_sessions"
    fi
    printf ']}\n'
}

api_kill_session() {
    local session_name="$1"
    local zellij_bin="${VAIBHAV_ZELLIJ_BIN:-$(command -v zellij 2>/dev/null || true)}"

    if [[ -z "$session_name" ]]; then
        printf '{"ok":false,"error":"session name required"}\n'
        return 1
    fi

    if [[ -z "$zellij_bin" ]]; then
        printf '{"ok":false,"error":"zellij not found"}\n'
        return 1
    fi

    if "$zellij_bin" kill-session "$session_name" 2>/dev/null; then
        printf '{"ok":true}\n'
    else
        printf '{"ok":false,"error":"failed to kill session %s"}\n' "$session_name"
        return 1
    fi
}

api_open_project() {
    local project_name="$1"
    local tool="${2:-}"
    local zellij_bin="${VAIBHAV_ZELLIJ_BIN:-$(command -v zellij 2>/dev/null || true)}"
    local projects_file="${PROJECTS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/vaibhav/projects}"

    if [[ -z "$project_name" ]]; then
        printf '{"ok":false,"error":"project name required"}\n'
        return 1
    fi

    local project_path=""
    if [[ -f "$projects_file" ]]; then
        project_path=$(grep "^${project_name}=" "$projects_file" 2>/dev/null | cut -d= -f2-)
    fi

    if [[ -z "$project_path" ]]; then
        printf '{"ok":false,"error":"project not found: %s"}\n' "$project_name"
        return 1
    fi

    if [[ -z "$zellij_bin" ]]; then
        printf '{"ok":false,"error":"zellij not found"}\n'
        return 1
    fi

    # Don't create the session here — zellij web creates/attaches sessions
    # automatically when the browser navigates to the session URL.
    # Sessions created via CLI are not "shared" to web clients.

    # If tool specified, wait for the web client to create the session, then add tool tab
    if [[ -n "$tool" ]]; then
        local tool_cmd=""
        case "$tool" in
            amp) tool_cmd="amp" ;;
            claude) tool_cmd="claude" ;;
            codex) tool_cmd="codex" ;;
            opencode) tool_cmd="opencode" ;;
            pi) tool_cmd="pi" ;;
            *) tool_cmd="$tool" ;;
        esac
        # Wait for the session to appear (created by web client navigation)
        local retries=0
        while ! "$zellij_bin" list-sessions --no-formatting 2>/dev/null | grep -q "^${project_name} "; do
            retries=$((retries + 1))
            if [[ $retries -ge 10 ]]; then
                printf '{"ok":true,"session":"%s","tool_pending":true}\n' "$project_name"
                return 0
            fi
            sleep 0.5
        done
        "$zellij_bin" --session "$project_name" action new-tab --name "$tool" --cwd "$project_path" -- "$tool_cmd" 2>/dev/null || true
    fi

    printf '{"ok":true,"session":"%s"}\n' "$project_name"
}
