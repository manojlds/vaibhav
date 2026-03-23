# shellcheck shell=bash
# vaibhav/lib/devserver.sh — Dev server management via devenv + tailscale serve

DEVSERVERS_FILE="$CONFIG_DIR/devservers"
DEVSERVER_TS_PORT_START=10443

# Optional per-project process metadata override file.
# Format (either style):
#   process|port|http
#   process=port
#
# Example:
#   server|4000|http
#   otel-collector|4318|nohttp
#   temporal-server||nohttp

# --- Helpers ---

_ds_ensure_file() {
    touch "$DEVSERVERS_FILE"
    _ds_migrate_registry_schema
}

_ds_migrate_registry_schema() {
    # Migrate legacy schema:
    #   project|port|tsport|pid
    # to new schema:
    #   project|process|port|tsport|task_path
    [[ -s "$DEVSERVERS_FILE" ]] || return 0

    local tmp_file
    tmp_file="${DEVSERVERS_FILE}.tmp"
    : >"$tmp_file"

    local changed=false
    while IFS='|' read -r f1 f2 f3 f4 f5 rest; do
        [[ -z "$f1" ]] && continue

        if [[ -n "$f5" || -n "$rest" ]]; then
            echo "${f1}|${f2}|${f3}|${f4}|${f5}" >>"$tmp_file"
            continue
        fi

        # Legacy row with 4 columns.
        if [[ -n "$f4" ]]; then
            changed=true
            echo "${f1}|server|${f2}|${f3}|" >>"$tmp_file"
            continue
        fi

        # Unknown shape, keep as-is with padded fields.
        echo "${f1}|${f2}|${f3}|${f4}|${f5}" >>"$tmp_file"
    done <"$DEVSERVERS_FILE"

    if [[ "$changed" == "true" ]]; then
        mv "$tmp_file" "$DEVSERVERS_FILE"
    else
        rm -f "$tmp_file"
    fi
}

_ds_project_meta_file() {
    local project_path="$1"
    echo "$project_path/.vaibhav-devservers"
}

_ds_is_registered_project() {
    local name="$1"
    [[ -n "$(get_project_path "$name")" ]]
}

_ds_has_devenv() {
    local project_path="$1"
    [[ -f "$project_path/devenv.nix" || -f "$project_path/devenv.yaml" ]]
}

_ds_resolve_project_context() {
    # Usage: _ds_resolve_project_context <arg1> <arg2>
    # Prints: project|project_path|process
    local arg1="${1:-}"
    local arg2="${2:-}"
    local project=""
    local project_path=""
    local process=""

    if [[ -z "$arg1" ]]; then
        project="$(basename "$PWD")"
        project_path="$PWD"
        process="$arg2"
        echo "$project|$project_path|$process"
        return
    fi

    if _ds_is_registered_project "$arg1"; then
        project="$arg1"
        project_path="$(get_project_path "$project")"
        process="$arg2"
        echo "$project|$project_path|$process"
        return
    fi

    # If current directory is a project with devenv, treat arg1 as process name.
    if _ds_has_devenv "$PWD"; then
        project="$(basename "$PWD")"
        project_path="$PWD"
        process="$arg1"
        echo "$project|$project_path|$process"
        return
    fi

    # Fall back: treat arg1 as project name even if not registered.
    project="$arg1"
    project_path="$PWD"
    process="$arg2"
    echo "$project|$project_path|$process"
}

_ds_next_tsport() {
    local port=$DEVSERVER_TS_PORT_START
    while awk -F'|' -v p="$port" '$4==p {found=1} END {exit !found}' "$DEVSERVERS_FILE" 2>/dev/null; do
        port=$((port + 1))
    done
    echo "$port"
}

_ds_remove_entry() {
    local project="$1" process="$2"
    sed -i "/^${project}|${process}|/d" "$DEVSERVERS_FILE"
}

_ds_port_is_open() {
    local port="$1"
    [[ -n "$port" ]] || return 1
    (echo >"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1
}

_ds_process_running() {
    local task_path="$1" port="${2:-}"

    if _ds_port_is_open "$port"; then
        return 0
    fi

    [[ -n "$task_path" ]] && pgrep -f "$task_path" >/dev/null 2>&1
}

_ds_extract_devenv_metadata() {
    # Emits lines in format:
    #   PROC|<process>|<exec_path>
    #   TASK|<process>|<task_path>
    local project_path="$1"
    local info
    if ! info="$(cd "$project_path" && devenv info 2>/dev/null)"; then
        return 1
    fi

    local mode=""
    while IFS= read -r line; do
        case "$line" in
            "# processes")
                mode="processes"
                continue
                ;;
            "# tasks")
                mode="tasks"
                continue
                ;;
            "# "*)
                mode=""
                ;;
        esac

        if [[ "$mode" == "processes" ]]; then
            if [[ "$line" =~ ^-\ ([^:]+):\ exec\ (.+)$ ]]; then
                echo "PROC|${BASH_REMATCH[1]}|${BASH_REMATCH[2]}"
            fi
        elif [[ "$mode" == "tasks" ]]; then
            if [[ "$line" == "- devenv:processes:"* ]]; then
                local task_name task_path
                task_name="$(echo "$line" | sed -n 's/^- devenv:processes:\([^:]*\):.*$/\1/p')"
                task_path="$(echo "$line" | sed -n 's/^.*(\(.*\))$/\1/p')"
                if [[ -n "$task_name" && -n "$task_path" ]]; then
                    echo "TASK|${task_name}|${task_path}"
                fi
            fi
        fi
    done <<<"$info"
}

_ds_process_port_from_meta() {
    local project_path="$1" process="$2"
    local meta_file
    meta_file="$(_ds_project_meta_file "$project_path")"
    [[ -f "$meta_file" ]] || return 0

    local line
    line="$(grep "^${process}[|=]" "$meta_file" 2>/dev/null | head -1 || true)"
    [[ -n "$line" ]] || return 0

    if [[ "$line" == *"|"* ]]; then
        echo "$line" | cut -d'|' -f2
    else
        echo "$line" | cut -d'=' -f2
    fi
}

_ds_process_http_mode_from_meta() {
    local project_path="$1" process="$2"
    local meta_file
    meta_file="$(_ds_project_meta_file "$project_path")"
    [[ -f "$meta_file" ]] || return 0

    local line
    line="$(grep "^${process}[|=]" "$meta_file" 2>/dev/null | head -1 || true)"
    [[ -n "$line" ]] || return 0

    if [[ "$line" == *"|"* ]]; then
        echo "$line" | cut -d'|' -f3
    fi
}

_ds_detect_ports_from_task_script() {
    local task_path="$1"
    [[ -f "$task_path" ]] || return 0

    {
        grep -Eo '(127\.0\.0\.1|0\.0\.0\.0|localhost):[0-9]{2,5}' "$task_path" 2>/dev/null \
            | grep -Eo '[0-9]{2,5}' || true
        grep -Eo '(--[a-zA-Z0-9-]*port|port)[[:space:]:=]+[0-9]{2,5}' "$task_path" 2>/dev/null \
            | grep -Eo '[0-9]{2,5}' || true
        grep -Eo 'https?://[^[:space:]]+:[0-9]{2,5}' "$task_path" 2>/dev/null \
            | grep -Eo '[0-9]{2,5}' || true
    } | awk '$1 >= 1 && $1 <= 65535 { print $1 }' | sort -n | uniq
}

_ds_detect_ui_port_from_task_script() {
    local task_path="$1"
    [[ -f "$task_path" ]] || return 0

    grep -Eo -- '--ui-port[[:space:]=]+[0-9]{2,5}' "$task_path" 2>/dev/null \
        | grep -Eo '[0-9]{2,5}' \
        | head -1 || true
}

_ds_first_open_port_from_list() {
    local ports="$1"
    local port

    while IFS= read -r port; do
        [[ -z "$port" ]] && continue
        if _ds_port_is_open "$port"; then
            echo "$port"
            return 0
        fi
    done <<<"$ports"

    return 1
}

_ds_list_listening_ports() {
    lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null \
        | awk 'NR > 1 { split($9, a, ":"); p = a[length(a)]; if (p ~ /^[0-9]+$/) print p }' \
        | sort -n \
        | uniq || true
}

_ds_first_new_port_from_snapshot() {
    local before_ports="$1"
    local current_ports port

    current_ports="$(_ds_list_listening_ports)"
    while IFS= read -r port; do
        [[ -z "$port" ]] && continue
        if ! grep -qx "$port" <<<"$before_ports"; then
            echo "$port"
            return 0
        fi
    done <<<"$current_ports"

    return 1
}

_ds_should_expose_http() {
    local process="$1" mode="${2:-}" task_path="${3:-}"

    case "$mode" in
        http|true|yes|1)
            return 0
            ;;
        nohttp|false|no|0)
            return 1
            ;;
    esac

    # Heuristic defaults when no explicit metadata is provided.
    local hints
    hints="${process,,} ${task_path,,}"
    case "$hints" in
        *temporal*|*otel*|*collector*|*grpc*|*postgres*|*mysql*|*redis*|*kafka*|*rabbit*|*nats*|*db*|*queue*|*worker*|*scheduler*)
            return 1
            ;;
    esac

    return 0
}

_ds_get_registry_entry() {
    local project="$1" process="$2"
    grep "^${project}|${process}|" "$DEVSERVERS_FILE" 2>/dev/null | head -1 || true
}

_ds_register_process_entry() {
    local project="$1" process="$2" port="$3" tsport="$4" task_path="$5"
    _ds_remove_entry "$project" "$process"
    echo "${project}|${process}|${port}|${tsport}|${task_path}" >> "$DEVSERVERS_FILE"
}

_ds_tailscale_on() {
    local tsport="$1" port="$2"
    if ! tailscale serve --bg --yes --https "$tsport" "http://127.0.0.1:${port}" >/dev/null 2>&1; then
        tailscale serve --bg --https "$tsport" "http://127.0.0.1:${port}" >/dev/null 2>&1 || return 1
    fi
    _ds_tailscale_is_active "$tsport"
}

_ds_tailscale_off() {
    local tsport="$1"
    [[ -n "$tsport" ]] || return 0
    tailscale serve --https "$tsport" off >/dev/null 2>&1 || true
    if _ds_tailscale_is_active "$tsport"; then
        sleep 1
        tailscale serve --https "$tsport" off >/dev/null 2>&1 || true
    fi
}

_ds_tailscale_is_active() {
    local tsport="$1"
    [[ -n "$tsport" ]] || return 1
    tailscale serve status 2>/dev/null | grep -Eq "\.ts\.net:${tsport}([^0-9]|$)"
}

_ds_stop_process_by_task_path() {
    local task_path="$1"
    [[ -n "$task_path" ]] || return 0
    local pids
    pids="$(pgrep -f "$task_path" 2>/dev/null || true)"
    [[ -n "$pids" ]] || return 0
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
}

_ds_stop_process_by_port() {
    local port="$1"
    [[ -n "$port" ]] || return 0

    local pids
    pids="$(lsof -ti tcp:"$port" -sTCP:LISTEN 2>/dev/null || true)"
    [[ -n "$pids" ]] || return 0

    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
    sleep 1
    pids="$(lsof -ti tcp:"$port" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
        # shellcheck disable=SC2086
        kill -9 $pids 2>/dev/null || true
    fi
}

_ds_stop_devenv_up_launcher() {
    local project_path="$1" process="$2"
    [[ -n "$project_path" && -n "$process" ]] || return 0

    local pids
    pids="$(pgrep -f "devenv up --no-tui ${process}" 2>/dev/null || true)"
    [[ -n "$pids" ]] || return 0

    local pid cwd
    for pid in $pids; do
        cwd="$(readlink "/proc/${pid}/cwd" 2>/dev/null || true)"
        [[ "$cwd" == "$project_path" ]] || continue
        kill "$pid" 2>/dev/null || true
    done
}

# --- Commands ---

dev_start() {
    local arg1="${1:-}" arg2="${2:-}"
    local resolved project project_path process

    _ds_ensure_file

    resolved="$(_ds_resolve_project_context "$arg1" "$arg2")"
    IFS='|' read -r project project_path process <<<"$resolved"

    if [[ -z "$project_path" ]] || [[ ! -d "$project_path" ]]; then
        echo -e "${RED}Error:${NC} Project path not found for '${project}'"
        return 1
    fi

    if ! _ds_has_devenv "$project_path"; then
        echo -e "${RED}Error:${NC} No devenv.nix/devenv.yaml found in ${project_path}"
        echo -e "${DIM}Initialize devenv first (e.g. devenv init), then define processes.<name>.exec${NC}"
        return 1
    fi

    local metadata
    if ! metadata="$(_ds_extract_devenv_metadata "$project_path")"; then
        echo -e "${RED}Error:${NC} Failed to read devenv process metadata for ${project}"
        return 1
    fi

    declare -A task_path_by_process=()
    declare -A exec_path_by_process=()
    declare -a processes=()
    while IFS='|' read -r kind name path; do
        [[ -z "$kind" ]] && continue
        if [[ "$kind" == "PROC" ]]; then
            processes+=("$name")
            exec_path_by_process["$name"]="$path"
        elif [[ "$kind" == "TASK" ]]; then
            task_path_by_process["$name"]="$path"
        fi
    done <<<"$metadata"

    if [[ ${#processes[@]} -eq 0 ]]; then
        echo -e "${RED}Error:${NC} No processes found in devenv config for ${project}"
        return 1
    fi

    declare -a selected=()
    if [[ -n "$process" ]]; then
        local found=false
        for name in "${processes[@]}"; do
            if [[ "$name" == "$process" ]]; then
                found=true
                selected+=("$name")
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            echo -e "${RED}Error:${NC} Process '${process}' not found in ${project}"
            echo -e "${DIM}Available:${NC} ${processes[*]}"
            return 1
        fi
    else
        selected=("${processes[@]}")
    fi

    step "Starting devenv process(es) for ${project}: ${selected[*]}"

    local name task_path meta_port port tsport http_mode candidate_ports ui_port
    local detected_port ports_before expose_http
    local existing_entry existing_port existing_tsport
    local any_failed=false
    for name in "${selected[@]}"; do
        task_path="${task_path_by_process[$name]:-${exec_path_by_process[$name]:-}}"
        meta_port="$(_ds_process_port_from_meta "$project_path" "$name")"
        port="$meta_port"
        http_mode="$(_ds_process_http_mode_from_meta "$project_path" "$name")"
        candidate_ports="$(_ds_detect_ports_from_task_script "$task_path")"
        ui_port="$(_ds_detect_ui_port_from_task_script "$task_path")"
        existing_entry="$(_ds_get_registry_entry "$project" "$name")"
        existing_port=""
        existing_tsport=""
        if [[ -n "$existing_entry" ]]; then
            IFS='|' read -r _ _ existing_port existing_tsport _ <<<"$existing_entry"
        fi

        expose_http=false
        if _ds_should_expose_http "$name" "$http_mode" "$task_path"; then
            expose_http=true
        elif [[ -z "$http_mode" && -n "$ui_port" ]]; then
            # Explicit UI port in process script means this process is browser-facing.
            expose_http=true
        fi

        if [[ -z "$meta_port" && "$expose_http" == "true" && -n "$ui_port" ]]; then
            port="$ui_port"
        fi

        if [[ -z "$port" ]]; then
            port="$(_ds_first_open_port_from_list "$candidate_ports" || true)"
        fi
        if [[ -z "$port" && -n "$candidate_ports" ]]; then
            port="$(head -1 <<<"$candidate_ports")"
        fi
        if [[ -z "$port" && -n "$existing_port" ]]; then
            port="$existing_port"
        fi

        local is_running=false
        local max_attempts=45
        if [[ -z "$port" && -z "$candidate_ports" ]]; then
            max_attempts=20
        fi

        # Idempotent start: if already running, do not launch another supervisor.
        if _ds_process_running "$task_path" "$port"; then
            is_running=true
        elif [[ -n "$candidate_ports" ]]; then
            detected_port="$(_ds_first_open_port_from_list "$candidate_ports" || true)"
            if [[ -n "$detected_port" ]]; then
                port="$detected_port"
                is_running=true
            fi
        fi

        if [[ "$is_running" == "false" ]]; then
            ports_before="$(_ds_list_listening_ports)"

            if ! (cd "$project_path" && devenv processes up --detach --no-tui "$name"); then
                # A failed detach can still mean the process is already running.
                if _ds_process_running "$task_path" "$port"; then
                    is_running=true
                elif [[ -n "$candidate_ports" ]]; then
                    detected_port="$(_ds_first_open_port_from_list "$candidate_ports" || true)"
                    if [[ -n "$detected_port" ]]; then
                        port="$detected_port"
                        is_running=true
                    fi
                fi

                if [[ "$is_running" == "false" ]]; then
                    any_failed=true
                    echo -e "  ${YELLOW}Warning:${NC} failed to start ${name} via devenv --detach"
                    continue
                fi
            fi
        fi

        if [[ "$is_running" == "false" ]]; then
            for (( _attempt=1; _attempt<=max_attempts; _attempt++ )); do
                if _ds_process_running "$task_path" "$port"; then
                    is_running=true
                elif [[ -n "$candidate_ports" ]]; then
                    detected_port="$(_ds_first_open_port_from_list "$candidate_ports" || true)"
                    if [[ -n "$detected_port" ]]; then
                        port="$detected_port"
                        is_running=true
                    fi
                else
                    detected_port="$(_ds_first_new_port_from_snapshot "$ports_before" || true)"
                    if [[ -n "$detected_port" ]]; then
                        port="$detected_port"
                        is_running=true
                    fi
                fi

                if [[ "$is_running" == "true" ]]; then
                    break
                fi

                sleep 1
            done

            if [[ "$is_running" == "false" ]]; then
                # Fallback: some devenv versions return from --detach without
                # leaving a persistent manager. Start this process via nohup.
                (cd "$project_path" && nohup devenv up --no-tui "$name" >/dev/null 2>&1 &)
                for (( _attempt=1; _attempt<=max_attempts; _attempt++ )); do
                    if _ds_process_running "$task_path" "$port"; then
                        is_running=true
                    elif [[ -n "$candidate_ports" ]]; then
                        detected_port="$(_ds_first_open_port_from_list "$candidate_ports" || true)"
                        if [[ -n "$detected_port" ]]; then
                            port="$detected_port"
                            is_running=true
                        fi
                    else
                        detected_port="$(_ds_first_new_port_from_snapshot "$ports_before" || true)"
                        if [[ -n "$detected_port" ]]; then
                            port="$detected_port"
                            is_running=true
                        fi
                    fi

                    if [[ "$is_running" == "true" ]]; then
                        break
                    fi

                    sleep 1
                done
            fi
        fi

        tsport=""
        if [[ -n "$port" && "$expose_http" == "true" ]]; then
            if [[ -n "$existing_tsport" ]]; then
                tsport="$existing_tsport"
            else
                tsport="$(_ds_next_tsport)"
            fi
            if ! _ds_tailscale_on "$tsport" "$port"; then
                echo -e "  ${YELLOW}Warning:${NC} failed tailscale serve for ${name} (${port})"
                tsport=""
            fi
        elif [[ -n "$existing_tsport" ]]; then
            _ds_tailscale_off "$existing_tsport"
        fi

        _ds_register_process_entry "$project" "$name" "$port" "$tsport" "$task_path"

        if [[ "$is_running" == "true" ]]; then
            ok "${name} running"
        else
            any_failed=true
            echo -e "  ${YELLOW}Warning:${NC} ${name} is not running"
            local log_path
            log_path="${project_path}/.devenv/run/processes/logs/${name}.stderr.log"
            if [[ -f "$log_path" ]]; then
                echo -e "  ${DIM}log:${NC} ${log_path}"
            fi
        fi

        if [[ -n "$port" ]]; then
            if [[ "$expose_http" == "true" ]]; then
                ok "${name} local: http://127.0.0.1:${port}"
            else
                ok "${name} local: 127.0.0.1:${port}"
            fi
        fi
        if [[ -n "$tsport" ]]; then
            ok "${name} tailscale: https://$(hostname).tail0b43a9.ts.net:${tsport}"
        fi
    done

    if [[ "$any_failed" == "true" ]]; then
        echo -e "${RED}Error:${NC} One or more processes failed to start for ${project}"
        return 1
    fi
}

dev_stop() {
    local arg1="${1:-}" arg2="${2:-}"
    local resolved project project_path process

    _ds_ensure_file

    resolved="$(_ds_resolve_project_context "$arg1" "$arg2")"
    IFS='|' read -r project project_path process <<<"$resolved"

    if [[ -z "$project" ]]; then
        echo -e "${RED}Error:${NC} Could not resolve project"
        return 1
    fi

    step "Stopping devenv process(es) for ${project}${process:+ (${process})}"

    if [[ -n "$process" ]]; then
        local entry port tsport task_path
        entry="$(_ds_get_registry_entry "$project" "$process")"
        if [[ -z "$entry" ]]; then
            echo -e "${RED}Error:${NC} No registered process '${process}' for ${project}"
            return 1
        fi

        IFS='|' read -r _ _ port tsport task_path <<<"$entry"
        _ds_stop_process_by_task_path "$task_path"
        _ds_stop_devenv_up_launcher "$project_path" "$process"
        _ds_stop_process_by_port "$port"

        local still_running=false
        for _attempt in 1 2 3; do
            if _ds_process_running "$task_path" "$port"; then
                still_running=true
                sleep 1
            else
                still_running=false
                break
            fi
        done

        if [[ "$still_running" == "true" ]]; then
            if [[ -n "$tsport" ]] && [[ -n "$port" ]]; then
                _ds_tailscale_on "$tsport" "$port" >/dev/null 2>&1 || true
            fi
            echo -e "${RED}Error:${NC} Failed to stop ${process} for ${project}"
            return 1
        fi

        _ds_tailscale_off "$tsport"
        ok "Stopped ${process}"
        return 0
    fi

    if [[ -d "$project_path" ]] && _ds_has_devenv "$project_path"; then
        (cd "$project_path" && devenv processes down >/dev/null 2>&1) || true
    fi

    local entries
    entries="$(grep "^${project}|" "$DEVSERVERS_FILE" 2>/dev/null || true)"
    local had_failure=false
    if [[ -n "$entries" ]]; then
        while IFS='|' read -r _ process_name port tsport task_path; do
            [[ -z "$process_name" ]] && continue
            _ds_stop_process_by_task_path "$task_path"
            _ds_stop_devenv_up_launcher "$project_path" "$process_name"
            _ds_stop_process_by_port "$port"

            if _ds_process_running "$task_path" "$port"; then
                had_failure=true
                echo -e "  ${YELLOW}Warning:${NC} ${process_name} still appears to be running"
                if [[ -n "$tsport" ]] && [[ -n "$port" ]]; then
                    _ds_tailscale_on "$tsport" "$port" >/dev/null 2>&1 || true
                fi
                continue
            fi

            _ds_tailscale_off "$tsport"
        done <<<"$entries"
    fi

    if [[ "$had_failure" == "true" ]]; then
        echo -e "${RED}Error:${NC} One or more processes failed to stop for ${project}"
        return 1
    fi

    ok "Stopped all registered processes for ${project}"
}

dev_list() {
    _ds_ensure_file

    echo -e "${BOLD}Dev Servers${NC}"
    echo ""

    if [[ ! -s "$DEVSERVERS_FILE" ]]; then
        echo -e "  ${DIM}No dev servers registered. Use 'vaibhav dev start'.${NC}"
        echo ""
        return
    fi

    local hostname
    hostname="$(hostname)"

    local current_project=""
    while IFS='|' read -r project process port tsport task_path; do
        [[ -z "$project" ]] && continue

        if [[ "$project" != "$current_project" ]]; then
            current_project="$project"
            echo -e "${CYAN}${project}${NC}"
        fi

        local status
        if _ds_process_running "$task_path" "$port"; then
            status="${GREEN}running${NC}"
        else
            status="${RED}stopped${NC}"
        fi

        echo -e "  ${BOLD}${process}${NC} ${status}"
        if [[ -n "$port" ]]; then
            if _ds_should_expose_http "$process" "" "$task_path"; then
                echo -e "    ${DIM}Local:${NC}     http://127.0.0.1:${port}"
            else
                echo -e "    ${DIM}Local:${NC}     127.0.0.1:${port}"
            fi
        fi
        if [[ -n "$tsport" ]]; then
            echo -e "    ${DIM}Tailscale:${NC} https://${hostname}.tail0b43a9.ts.net:${tsport}"
        fi
    done < <(sort "$DEVSERVERS_FILE")

    echo ""
}

dev_restart() {
    local arg1="${1:-}" arg2="${2:-}"
    dev_stop "$arg1" "$arg2"
    dev_start "$arg1" "$arg2"
}

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
            echo -e "${BOLD}Usage:${NC} vaibhav dev <command> [project] [process]"
            echo ""
            echo -e "${BOLD}Commands:${NC}"
            echo "  start [project] [process]    Start devenv process(es)"
            echo "  stop [project] [process]     Stop devenv process(es)"
            echo "  restart [project] [process]  Restart devenv process(es)"
            echo "  list                         List all registered dev processes"
            echo ""
            echo -e "${BOLD}Examples:${NC}"
            echo "  cd ~/projects/myapp && vaibhav dev start"
            echo "  vaibhav dev start kollywood"
            echo "  vaibhav dev start kollywood server"
            echo "  vaibhav dev stop kollywood temporal-server"
            echo "  vaibhav dev list"
            ;;
    esac
}
