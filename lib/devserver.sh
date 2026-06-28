# shellcheck shell=bash
# vaibhav/lib/devserver.sh — Dev server management via pitchfork + tailscale serve

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

_ds_has_pitchfork() {
    local project_path="$1"
    [[ -f "$project_path/pitchfork.toml" ]]
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

    # If current directory is a project with pitchfork, treat arg1 as process name.
    if _ds_has_pitchfork "$PWD"; then
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

_ds_strip_toml_quotes() {
    local value="$1"
    value="$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [[ ${#value} -ge 2 && "$value" == \"*\" && "$value" == *\" ]]; then
        value="${value:1:${#value}-2}"
        value="${value//\\\"/\"}"
    elif [[ ${#value} -ge 2 && "$value" == \'*\' && "$value" == *\' ]]; then
        value="${value:1:${#value}-2}"
    fi

    echo "$value"
}

_ds_expand_mise_env_vars() {
    local text="$1"
    local needle

    needle="\${PORT:-4000}"
    text="${text//$needle/4000}"
    needle="\${PORT:-8233}"
    text="${text//$needle/8233}"
    needle="\${PORT:-17451}"
    text="${text//$needle/17451}"
    needle="\${PORT:-4318}"
    text="${text//$needle/4318}"
    needle="\${PORT}"
    text="${text//$needle/4000}"
    needle="\$PORT"
    text="${text//$needle/4000}"
    needle="\${APP_PORT}"
    text="${text//$needle/4000}"
    needle="\$APP_PORT"
    text="${text//$needle/4000}"
    needle="\${ADK_DEEPAGENTS_TEMPORAL_WORKER_HEALTH_PORT}"
    text="${text//$needle/17451}"
    needle="\$ADK_DEEPAGENTS_TEMPORAL_WORKER_HEALTH_PORT"
    text="${text//$needle/17451}"
    echo "$text"
}

_ds_extract_pitchfork_metadata() {
    # Emits lines in format:
    #   PROC|<daemon>|<run>
    #   TASK|<daemon>|<metadata_blob>
    local project_path="$1"
    local config_file="$project_path/pitchfork.toml"
    [[ -f "$config_file" ]] || return 1

    local current=""
    local run=""
    local ready_http=""
    local ready_port=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*\[daemons\.([a-zA-Z0-9_.-]+)\][[:space:]]*$ ]]; then
            if [[ -n "$current" ]]; then
                local metadata_blob
                metadata_blob="$(_ds_expand_mise_env_vars "$run")"
                if [[ -n "$ready_http" ]]; then
                    metadata_blob="${metadata_blob} $(_ds_expand_mise_env_vars "$ready_http")"
                fi
                [[ -n "$ready_port" ]] && metadata_blob="${metadata_blob} ready_port:${ready_port}"
                echo "PROC|${current}|${run}"
                echo "TASK|${current}|${metadata_blob}"
            fi

            current="${BASH_REMATCH[1]}"
            run=""
            ready_http=""
            ready_port=""
            continue
        fi

        [[ -z "$current" ]] && continue

        if [[ "$line" =~ ^[[:space:]]*run[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            run="$(_ds_strip_toml_quotes "${BASH_REMATCH[1]}")"
        elif [[ "$line" =~ ^[[:space:]]*ready_http[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            ready_http="$(_ds_strip_toml_quotes "${BASH_REMATCH[1]}")"
        elif [[ "$line" =~ ^[[:space:]]*ready_port[[:space:]]*=[[:space:]]*([0-9]{1,5})[[:space:]]*$ ]]; then
            ready_port="${BASH_REMATCH[1]}"
        fi
    done <"$config_file"

    if [[ -n "$current" ]]; then
        local metadata_blob
        metadata_blob="$(_ds_expand_mise_env_vars "$run")"
        if [[ -n "$ready_http" ]]; then
            metadata_blob="${metadata_blob} $(_ds_expand_mise_env_vars "$ready_http")"
        fi
        [[ -n "$ready_port" ]] && metadata_blob="${metadata_blob} ready_port:${ready_port}"
        echo "PROC|${current}|${run}"
        echo "TASK|${current}|${metadata_blob}"
    fi
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

_ds_detect_ports_from_metadata() {
    local metadata="$1"
    [[ -n "$metadata" ]] || return 0

    {
        grep -Eo '(127\.0\.0\.1|0\.0\.0\.0|localhost):[0-9]{2,5}' <<<"$metadata" 2>/dev/null \
            | grep -Eo '[0-9]{2,5}' || true
        grep -Eo '(--[a-zA-Z0-9-]*port|port)[[:space:]:=]+[0-9]{2,5}' <<<"$metadata" 2>/dev/null \
            | grep -Eo '[0-9]{2,5}' || true
        grep -Eo 'https?://[^[:space:]]+:[0-9]{2,5}' <<<"$metadata" 2>/dev/null \
            | grep -Eo '[0-9]{2,5}' || true
    } | awk '$1 >= 1 && $1 <= 65535 { print $1 }' | sort -n | uniq
}

_ds_detect_ui_port_from_metadata() {
    local metadata="$1"
    [[ -n "$metadata" ]] || return 0

    grep -Eo -- '--ui-port[[:space:]=]+[0-9]{2,5}' <<<"$metadata" 2>/dev/null \
        | grep -Eo '[0-9]{2,5}' \
        | head -1 || true
}

_ds_detect_ready_port_from_metadata() {
    local metadata="$1"
    [[ -n "$metadata" ]] || return 0

    grep -Eo 'ready_port:[0-9]{2,5}' <<<"$metadata" 2>/dev/null \
        | grep -Eo '[0-9]{2,5}' \
        | tail -1 && return 0

    grep -Eo 'https?://[^[:space:]]+:[0-9]{2,5}' <<<"$metadata" 2>/dev/null \
        | grep -Eo '[0-9]{2,5}' \
        | tail -1 || true
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

_ds_should_expose_http() {
    local process="$1" mode="${2:-}" metadata="${3:-}"

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
    hints="${process,,} ${metadata,,}"
    if [[ "$hints" == *http://* || "$hints" == *https://* ]]; then
        return 0
    fi

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

_ds_pitchfork_running() {
    local project_path="$1" process="$2"
    [[ -n "$project_path" && -n "$process" ]] || return 1

    (cd "$project_path" && pitchfork status "$process" 2>/dev/null) \
        | grep -Eiq '^Status:[[:space:]]*running'
}

_ds_process_running() {
    local project_path="$1" process="$2" port="${3:-}" allow_port_fallback="${4:-false}"

    if _ds_pitchfork_running "$project_path" "$process"; then
        return 0
    fi

    if [[ "$allow_port_fallback" == "true" ]]; then
        _ds_port_is_open "$port"
        return
    fi

    return 1
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

    if ! _ds_has_pitchfork "$project_path"; then
        echo -e "${RED}Error:${NC} No pitchfork.toml found in ${project_path}"
        echo -e "${DIM}Add a [daemons.<name>] block in pitchfork.toml first.${NC}"
        return 1
    fi

    local metadata
    if ! metadata="$(_ds_extract_pitchfork_metadata "$project_path")"; then
        echo -e "${RED}Error:${NC} Failed to read pitchfork daemon metadata for ${project}"
        return 1
    fi

    declare -A metadata_by_process=()
    declare -A run_by_process=()
    declare -a processes=()
    while IFS='|' read -r kind name data; do
        [[ -z "$kind" ]] && continue
        if [[ "$kind" == "PROC" ]]; then
            processes+=("$name")
            run_by_process["$name"]="$data"
        elif [[ "$kind" == "TASK" ]]; then
            metadata_by_process["$name"]="$data"
        fi
    done <<<"$metadata"

    if [[ ${#processes[@]} -eq 0 ]]; then
        echo -e "${RED}Error:${NC} No daemons found in pitchfork config for ${project}"
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

    step "Starting pitchfork process(es) for ${project}: ${selected[*]}"

    local name metadata_blob metadata_inline meta_port port tsport http_mode candidate_ports ui_port
    local detected_port ready_port expose_http existing_entry existing_port existing_tsport
    local any_failed=false
    for name in "${selected[@]}"; do
        metadata_blob="${metadata_by_process[$name]:-${run_by_process[$name]:-}}"
        metadata_inline="${metadata_blob//$'\n'/ }"
        metadata_inline="${metadata_inline//|//}"

        meta_port="$(_ds_process_port_from_meta "$project_path" "$name")"
        port="$meta_port"
        http_mode="$(_ds_process_http_mode_from_meta "$project_path" "$name")"
        candidate_ports="$(_ds_detect_ports_from_metadata "$metadata_blob")"
        ui_port="$(_ds_detect_ui_port_from_metadata "$metadata_blob")"
        ready_port="$(_ds_detect_ready_port_from_metadata "$metadata_blob")"
        existing_entry="$(_ds_get_registry_entry "$project" "$name")"
        existing_port=""
        existing_tsport=""
        if [[ -n "$existing_entry" ]]; then
            IFS='|' read -r _ _ existing_port existing_tsport _ <<<"$existing_entry"
        fi

        expose_http=false
        if _ds_should_expose_http "$name" "$http_mode" "$metadata_blob"; then
            expose_http=true
        elif [[ -z "$http_mode" && -n "$ui_port" ]]; then
            expose_http=true
        fi

        if [[ -z "$meta_port" && "$expose_http" == "true" && -n "$ui_port" ]]; then
            port="$ui_port"
        fi

        if [[ -z "$port" && -n "$ready_port" ]]; then
            port="$ready_port"
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

        if _ds_process_running "$project_path" "$name" "$port"; then
            is_running=true
        elif [[ -n "$candidate_ports" ]]; then
            detected_port="$(_ds_first_open_port_from_list "$candidate_ports" || true)"
            if [[ -n "$detected_port" ]]; then
                port="$detected_port"
                is_running=true
            fi
        fi

        if [[ "$is_running" == "false" ]]; then
            local start_output
            if ! start_output="$(cd "$project_path" && pitchfork start "$name" 2>&1)"; then
                if _ds_process_running "$project_path" "$name" "$port"; then
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
                    echo -e "  ${YELLOW}Warning:${NC} failed to start ${name} via pitchfork"
                    if [[ -n "$start_output" ]]; then
                        echo -e "  ${DIM}${start_output//$'\n'/ }${NC}"
                    fi
                    continue
                fi
            fi
        fi

        if [[ "$is_running" == "false" ]]; then
            for (( _attempt=1; _attempt<=max_attempts; _attempt++ )); do
                if _ds_process_running "$project_path" "$name" "$port"; then
                    is_running=true
                elif [[ -n "$candidate_ports" ]]; then
                    detected_port="$(_ds_first_open_port_from_list "$candidate_ports" || true)"
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

        local registry_meta
        registry_meta="$metadata_inline"
        if [[ -z "$registry_meta" ]]; then
            registry_meta="$name"
        fi
        _ds_register_process_entry "$project" "$name" "$port" "$tsport" "$registry_meta"

        if [[ "$is_running" == "true" ]]; then
            ok "${name} running"
        else
            any_failed=true
            echo -e "  ${YELLOW}Warning:${NC} ${name} is not running"
            echo -e "  ${DIM}hint:${NC} cd ${project_path} && pitchfork logs ${name}"
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

    if [[ -z "$project_path" ]] || [[ ! -d "$project_path" ]]; then
        echo -e "${RED}Error:${NC} Project path not found for '${project}'"
        return 1
    fi

    step "Stopping pitchfork process(es) for ${project}${process:+ (${process})}"

    if [[ -n "$process" ]]; then
        local entry port tsport task_meta
        entry="$(_ds_get_registry_entry "$project" "$process")"
        port=""
        tsport=""
        task_meta=""
        if [[ -n "$entry" ]]; then
            IFS='|' read -r _ _ port tsport task_meta <<<"$entry"
        fi

        local stop_output
        if ! stop_output="$(cd "$project_path" && pitchfork stop "$process" 2>&1)"; then
            if grep -qi 'not found' <<<"$stop_output"; then
                echo -e "${RED}Error:${NC} Process '${process}' not found in ${project}"
                return 1
            fi
        fi

        local still_running=false
        for _attempt in 1 2 3; do
            if _ds_process_running "$project_path" "$process" "$port"; then
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

    if _ds_has_pitchfork "$project_path"; then
        (cd "$project_path" && pitchfork stop --all >/dev/null 2>&1) || true
    fi

    local entries
    entries="$(grep "^${project}|" "$DEVSERVERS_FILE" 2>/dev/null || true)"
    local had_failure=false
    if [[ -n "$entries" ]]; then
        local process_name port tsport task_meta
        while IFS='|' read -r _ process_name port tsport task_meta; do
            [[ -z "$process_name" ]] && continue

            if _ds_process_running "$project_path" "$process_name" "$port"; then
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
    local project process port tsport task_meta
    while IFS='|' read -r project process port tsport task_meta; do
        [[ -z "$project" ]] && continue

        if [[ "$project" != "$current_project" ]]; then
            current_project="$project"
            echo -e "${CYAN}${project}${NC}"
        fi

        local project_path status
        project_path="$(get_project_path "$project")"
        if [[ -n "$project_path" ]] && _ds_process_running "$project_path" "$process" "$port"; then
            status="${GREEN}running${NC}"
        else
            status="${RED}stopped${NC}"
        fi

        echo -e "  ${BOLD}${process}${NC} ${status}"
        if [[ -n "$port" ]]; then
            if _ds_should_expose_http "$process" "" "$task_meta"; then
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
            echo "  start [project] [process]    Start pitchfork process(es)"
            echo "  stop [project] [process]     Stop pitchfork process(es)"
            echo "  restart [project] [process]  Restart pitchfork process(es)"
            echo "  list                         List all registered dev processes"
            echo ""
            echo -e "${BOLD}Examples:${NC}"
            echo "  cd ~/projects/myapp && vaibhav dev start"
            echo "  vaibhav dev start kollywood"
            echo "  vaibhav dev start kollywood server"
            echo "  vaibhav dev stop kollywood server"
            echo "  vaibhav dev list"
            ;;
    esac
}
