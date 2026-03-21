# shellcheck shell=bash
# vaibhav/lib/devserver.sh — Dev server management via process-compose + tailscale serve

# Ensure mise shims are in PATH (covers sessions started before ~/.profile update)
if [[ -d "$HOME/.local/share/mise/shims" ]] && [[ ":$PATH:" != *":$HOME/.local/share/mise/shims:"* ]]; then
    export PATH="$HOME/.local/share/mise/shims:$PATH"
fi

DEVSERVERS_FILE="$CONFIG_DIR/devservers"
DEVSERVER_TS_PORT_START=10443

# --- Helpers ---

_ds_ensure_file() {
    touch "$DEVSERVERS_FILE"
}

# Get a devserver field: _ds_get <project> <field>
# Fields: port, tsport, pid
_ds_get() {
    local project="$1" field="$2"
    grep "^${project}|" "$DEVSERVERS_FILE" 2>/dev/null | head -1 | cut -d'|' -f"$(_ds_field_index "$field")"
}

_ds_field_index() {
    case "$1" in
        project) echo 1 ;;
        port)    echo 2 ;;
        tsport)  echo 3 ;;
        pid)     echo 4 ;;
    esac
}

# Find the next available tailscale serve port
_ds_next_tsport() {
    local port=$DEVSERVER_TS_PORT_START
    while grep -q "|${port}|" "$DEVSERVERS_FILE" 2>/dev/null; do
        port=$((port + 1))
    done
    echo "$port"
}

# Detect port from process-compose.yaml
_ds_detect_port() {
    local project_path="$1"
    local pc_file="$project_path/process-compose.yaml"
    local port=""

    if [[ -f "$pc_file" ]]; then
        # Try readiness_probe.http_get.port first
        port=$(grep -A5 'http_get:' "$pc_file" 2>/dev/null | grep 'port:' | head -1 | awk '{print $2}')

        # Fall back to x-port top-level annotation
        if [[ -z "$port" ]]; then
            port=$(grep '^x-port:' "$pc_file" 2>/dev/null | awk '{print $2}')
        fi
    fi

    echo "$port"
}

# Check if a process-compose is running for a project
_ds_is_running() {
    local project="$1"
    local pid
    pid=$(_ds_get "$project" "pid")
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# --- Commands ---

dev_start() {
    local project="${1:-}"
    local project_path=""

    _ds_ensure_file

    # Resolve project
    if [[ -z "$project" ]]; then
        # Try current directory
        project=$(basename "$PWD")
        project_path="$PWD"
    else
        project_path=$(get_project_path "$project")
    fi

    if [[ -z "$project_path" ]]; then
        echo -e "${RED}Error:${NC} Project '${project}' not found in vaibhav projects"
        exit 1
    fi

    if [[ ! -f "$project_path/process-compose.yaml" ]]; then
        echo -e "${RED}Error:${NC} No process-compose.yaml found in ${project_path}"
        echo -e "${DIM}Create one first. Example:${NC}"
        echo ""
        echo "  version: \"0.5\""
        echo "  processes:"
        echo "    server:"
        echo "      command: mix phx.server"
        echo "      readiness_probe:"
        echo "        http_get:"
        echo "          port: 4000"
        exit 1
    fi

    if _ds_is_running "$project"; then
        echo -e "${YELLOW}Already running:${NC} ${CYAN}${project}${NC}"
        local tsport
        tsport=$(_ds_get "$project" "tsport")
        echo -e "  ${DIM}Tailscale:${NC} https://$(hostname).tail0b43a9.ts.net:${tsport}"
        return
    fi

    # Detect port
    local port
    port=$(_ds_detect_port "$project_path")
    if [[ -z "$port" ]]; then
        echo -e "${RED}Error:${NC} Could not detect port from process-compose.yaml"
        echo -e "${DIM}Add a readiness_probe.http_get.port to your process config${NC}"
        exit 1
    fi

    # Get tailscale serve port
    local tsport
    tsport=$(_ds_next_tsport)

    step "Starting dev server for ${project}"

    # Start process-compose in daemon mode (-D forks and exits)
    # Run from project dir so working_dir and mise .mise.toml resolve correctly
    # Note: process-compose -D may exit with non-zero even on success
    (set +e; cd "$project_path" && \
        process-compose up -D --tui=false > .process-compose.log 2>&1) || true

    # Give the daemon a moment to start
    sleep 1

    # Find the daemon PID from the unix socket file
    local daemon_pid=""
    local sock_file=""
    sock_file=$(find /tmp -maxdepth 1 -name 'process-compose-*.sock' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2) || true
    if [[ -n "$sock_file" ]]; then
        # Extract PID from socket filename: /tmp/process-compose-<PID>.sock
        daemon_pid=$(basename "$sock_file" | sed 's/process-compose-//;s/\.sock//')
    fi
    if [[ -z "$daemon_pid" ]] || ! kill -0 "$daemon_pid" 2>/dev/null; then
        daemon_pid=$(pgrep -n -f "process-compose" 2>/dev/null) || true
    fi
    if [[ -z "$daemon_pid" ]]; then
        echo -e "${YELLOW}Warning:${NC} Could not find process-compose daemon PID, registering without it"
        daemon_pid="0"
    fi

    # Set up tailscale serve
    tailscale serve --bg --https "$tsport" "http://127.0.0.1:${port}" 2>/dev/null || {
        echo -e "${RED}Error:${NC} Failed to set up tailscale serve on port ${tsport}"
        return 1
    }

    # Remove old entry if exists, add new
    sed -i "/^${project}|/d" "$DEVSERVERS_FILE"
    echo "${project}|${port}|${tsport}|${daemon_pid}" >> "$DEVSERVERS_FILE"

    ok "process-compose started (pid: ${daemon_pid})"
    ok "Local: http://127.0.0.1:${port}"
    ok "Tailscale: https://$(hostname).tail0b43a9.ts.net:${tsport}"
}

dev_stop() {
    local project="${1:-}"

    _ds_ensure_file

    if [[ -z "$project" ]]; then
        project=$(basename "$PWD")
    fi

    if ! grep -q "^${project}|" "$DEVSERVERS_FILE" 2>/dev/null; then
        echo -e "${RED}Error:${NC} No dev server registered for '${project}'"
        return 1
    fi

    local pid tsport project_path
    pid=$(_ds_get "$project" "pid")
    tsport=$(_ds_get "$project" "tsport")
    project_path=$(get_project_path "$project")

    step "Stopping dev server for ${project}"

    # Stop process-compose
    if [[ -n "$project_path" ]] && [[ -f "$project_path/process-compose.yaml" ]]; then
        (cd "$project_path" && process-compose down 2>/dev/null) || true
    fi

    # Kill process if still alive
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi

    # Remove tailscale serve
    if [[ -n "$tsport" ]]; then
        tailscale serve --https "$tsport" off 2>/dev/null || true
    fi

    # Remove from registry
    sed -i "/^${project}|/d" "$DEVSERVERS_FILE"

    ok "Stopped"
}

dev_list() {
    _ds_ensure_file

    echo -e "${BOLD}Dev Servers${NC}"
    echo ""

    if [[ ! -s "$DEVSERVERS_FILE" ]]; then
        echo -e "  ${DIM}No dev servers running. Use 'vaibhav dev start' in a project directory.${NC}"
        echo ""
        return
    fi

    local hostname
    hostname=$(hostname)

    while IFS='|' read -r project port tsport pid; do
        [[ -z "$project" ]] && continue

        local status
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            status="${GREEN}running${NC}"
        else
            status="${RED}stopped${NC}"
        fi

        echo -e "  ${CYAN}${project}${NC} ${status}"
        echo -e "    ${DIM}Local:${NC}     http://127.0.0.1:${port}"
        echo -e "    ${DIM}Tailscale:${NC} https://${hostname}.tail0b43a9.ts.net:${tsport}"
    done < "$DEVSERVERS_FILE"

    echo ""
}

dev_restart() {
    local project="${1:-}"
    if [[ -z "$project" ]]; then
        project=$(basename "$PWD")
    fi
    dev_stop "$project"
    dev_start "$project"
}

# Main dispatch for dev subcommand
dev_dispatch() {
    local action="${1:-list}"
    shift 2>/dev/null || true

    case "$action" in
        start)
            dev_start "$@"
            ;;
        stop)
            dev_stop "$@"
            ;;
        restart)
            dev_restart "$@"
            ;;
        list|ls)
            dev_list
            ;;
        *)
            echo -e "${BOLD}Usage:${NC} vaibhav dev <command> [project]"
            echo ""
            echo -e "${BOLD}Commands:${NC}"
            echo "  start [project]    Start dev server (auto-detects from current dir)"
            echo "  stop [project]     Stop dev server"
            echo "  restart [project]  Restart dev server"
            echo "  list               List all running dev servers"
            echo ""
            echo -e "${BOLD}Examples:${NC}"
            echo "  cd ~/projects/myapp && vaibhav dev start"
            echo "  vaibhav dev start kollywood"
            echo "  vaibhav dev list"
            echo "  vaibhav dev stop kollywood"
            ;;
    esac
}
