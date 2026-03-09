# shellcheck shell=bash
# vaibhav/lib/projects.sh — Project management (list, add, remove, open, scan, kill)

get_project_path() {
    local name="$1"
    grep "^${name}=" "$PROJECTS_FILE" 2>/dev/null | cut -d= -f2-
}

list_projects() {
    echo -e "${BOLD}Projects${NC}"
    echo ""

    if [[ ! -s "$PROJECTS_FILE" ]]; then
        echo -e "  ${DIM}No projects registered. Use 'vaibhav add <name> <path>' or 'vaibhav scan'${NC}"
        echo ""
        return
    fi

    local show_both=false
    local tmux_available=false
    local zellij_available=false
    local active_sessions=""
    local active_sessions_tmux=""
    local active_sessions_zellij=""

    if command -v tmux >/dev/null 2>&1; then
        tmux_available=true
    fi
    if [[ -n "${VAIBHAV_ZELLIJ_BIN:-}" ]]; then
        zellij_available=true
    fi

    if [[ "$VAIBHAV_MULTIPLEXER" == "auto" && "$tmux_available" == "true" && "$zellij_available" == "true" ]]; then
        show_both=true
        active_sessions_tmux=$(mux_active_sessions_for_backend "tmux" || true)
        active_sessions_zellij=$(mux_active_sessions_for_backend "zellij" || true)
    elif [[ -n "$VAIBHAV_MUX_BACKEND" ]]; then
        active_sessions=$(mux_active_sessions || true)
    elif [[ "$VAIBHAV_MULTIPLEXER" != "auto" ]]; then
        echo -e "  ${YELLOW}!${NC} ${DIM}${VAIBHAV_MULTIPLEXER} is configured but not installed; showing projects only${NC}"
    fi

    while IFS='=' read -r name path; do
        [[ -z "$name" || "$name" == \#* ]] && continue

        local status="${DIM}inactive${NC}"
        local indicator=" "

        local active_tmux=false
        local active_zellij=false

        if [[ "$show_both" == "true" ]]; then
            echo "$active_sessions_tmux" | grep -qx "$name" 2>/dev/null && active_tmux=true
            echo "$active_sessions_zellij" | grep -qx "$name" 2>/dev/null && active_zellij=true

            if [[ "$active_tmux" == "true" || "$active_zellij" == "true" ]]; then
                indicator="${GREEN}●${NC}"
                local status_parts=""

                if [[ "$active_tmux" == "true" ]]; then
                    local tmux_targets
                    tmux_targets=$(mux_targets_csv_for_backend "tmux" "$name")
                    status_parts="tmux:[${tmux_targets}]"
                fi

                if [[ "$active_zellij" == "true" ]]; then
                    local zellij_targets
                    zellij_targets=$(mux_targets_csv_for_backend "zellij" "$name")
                    if [[ -n "$status_parts" ]]; then
                        status_parts+=" | "
                    fi
                    status_parts+="zellij:[${zellij_targets}]"
                fi

                status="${GREEN}active${NC} ${DIM}[${status_parts}]${NC}"
            fi

            # Ralph sessions are tmux-only today.
            if echo "$active_sessions_tmux" | grep -qx "ralph-${name}" 2>/dev/null; then
                status+=" ${YELLOW}ralph running${NC}"
                [[ "$indicator" == " " ]] && indicator="${YELLOW}●${NC}"
            fi
        else
            if echo "$active_sessions" | grep -qx "$name" 2>/dev/null; then
                local targets
                targets=$(mux_targets_csv "$name")
                status="${GREEN}active${NC} ${DIM}[${targets}]${NC}"
                indicator="${GREEN}●${NC}"
            fi

            # Ralph sessions are tmux-only today.
            if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" ]] && echo "$active_sessions" | grep -qx "ralph-${name}" 2>/dev/null; then
                status+=" ${YELLOW}ralph running${NC}"
                [[ "$indicator" == " " ]] && indicator="${YELLOW}●${NC}"
            fi
        fi

        echo -e "  ${indicator} ${CYAN}${name}${NC} ${DIM}→${NC} ${path}"
        echo -e "    ${status}"
    done < "$PROJECTS_FILE"

    echo ""

    if [[ "$show_both" == "true" ]]; then
        local orphans_tmux=""
        local orphans_zellij=""

        while IFS= read -r session; do
            [[ -z "$session" ]] && continue
            local base_name="${session#ralph-}"
            if [[ "$base_name" != "$session" ]] && grep -q "^${base_name}=" "$PROJECTS_FILE" 2>/dev/null; then
                continue
            fi
            if ! grep -q "^${session}=" "$PROJECTS_FILE" 2>/dev/null; then
                orphans_tmux+="  ${YELLOW}?${NC} ${session}\n"
            fi
        done <<< "$active_sessions_tmux"

        while IFS= read -r session; do
            [[ -z "$session" ]] && continue
            if ! grep -q "^${session}=" "$PROJECTS_FILE" 2>/dev/null; then
                orphans_zellij+="  ${YELLOW}?${NC} ${session}\n"
            fi
        done <<< "$active_sessions_zellij"

        if [[ -n "$orphans_tmux" ]]; then
            echo -e "${BOLD}Other tmux sessions${NC}"
            echo ""
            echo -e "$orphans_tmux"
        fi
        if [[ -n "$orphans_zellij" ]]; then
            echo -e "${BOLD}Other zellij sessions${NC}"
            echo ""
            echo -e "$orphans_zellij"
        fi
    else
        # Show orphan sessions (not in projects file)
        if [[ -n "$active_sessions" ]]; then
            local orphans=""
            while IFS= read -r session; do
                if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" ]]; then
                    # Skip ralph sessions (shown with their project above)
                    local base_name="${session#ralph-}"
                    if [[ "$base_name" != "$session" ]] && grep -q "^${base_name}=" "$PROJECTS_FILE" 2>/dev/null; then
                        continue
                    fi
                fi
                if ! grep -q "^${session}=" "$PROJECTS_FILE" 2>/dev/null; then
                    orphans+="  ${YELLOW}?${NC} ${session}\n"
                fi
            done <<< "$active_sessions"
            if [[ -n "$orphans" ]]; then
                echo -e "${BOLD}Other $(mux_backend_name) sessions${NC}"
                echo ""
                echo -e "$orphans"
            fi
        fi
    fi
}

add_project() {
    local name="$1"
    local path="$2"

    # Resolve to absolute path
    path=$(cd "$path" 2>/dev/null && pwd)

    if [[ ! -d "$path" ]]; then
        echo -e "${RED}Error:${NC} Directory does not exist: $path"
        exit 1
    fi

    # Remove existing entry if any
    if grep -q "^${name}=" "$PROJECTS_FILE" 2>/dev/null; then
        sed -i "/^${name}=/d" "$PROJECTS_FILE"
        echo -e "${YELLOW}Updated${NC} ${CYAN}${name}${NC} → ${path}"
    else
        echo -e "${GREEN}Added${NC} ${CYAN}${name}${NC} → ${path}"
    fi

    echo "${name}=${path}" >> "$PROJECTS_FILE"
    # Sort the file for consistency
    sort -o "$PROJECTS_FILE" "$PROJECTS_FILE"
}

remove_project() {
    local name="$1"

    if ! grep -q "^${name}=" "$PROJECTS_FILE" 2>/dev/null; then
        echo -e "${RED}Error:${NC} Project '${name}' not found"
        exit 1
    fi

    sed -i "/^${name}=/d" "$PROJECTS_FILE"
    echo -e "${RED}Removed${NC} ${CYAN}${name}${NC}"

    # Kill active session if present
    if [[ -n "$VAIBHAV_MUX_BACKEND" ]] && mux_session_exists "$name"; then
        read -rp "Kill active $(mux_backend_name) session '$name'? [y/N] " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" ]]; then
                tmux kill-session -t "$name"
            else
                run_zellij kill-session "$name"
            fi
            echo -e "  ${DIM}Session killed${NC}"
        fi
    fi
}

kill_project() {
    local name="$1"
    local window="${2:-}"

    require_mux_backend || exit 1

    if ! mux_session_exists "$name"; then
        echo -e "${RED}Error:${NC} No active session for '${name}'"
        exit 1
    fi

    if [[ -n "$window" ]]; then
        # Kill specific window/tab
        if ! mux_target_exists "$name" "$window"; then
            echo -e "${RED}Error:${NC} $(mux_target_name) '${window}' not found in session '${name}'"
            echo -e "${DIM}Active $(mux_target_name_plural):${NC}"
            if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" ]]; then
                tmux list-windows -t "$name" -F "  #{window_index}: #{window_name}" 2>/dev/null
            else
                local idx=1
                while IFS= read -r tab_name; do
                    echo "  ${idx}: ${tab_name}"
                    idx=$((idx + 1))
                done < <(mux_list_targets "$name")
            fi
            exit 1
        fi

        if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" ]]; then
            tmux kill-window -t "${name}:${window}"
        else
            run_zellij --session "$name" action go-to-tab-name "$window" >/dev/null
            run_zellij --session "$name" action close-tab >/dev/null
        fi
        echo -e "${GREEN}✓${NC} Killed $(mux_target_name) ${CYAN}${window}${NC} in ${CYAN}${name}${NC}"
    else
        # Kill entire session — show windows/tabs first
        echo -e "${BOLD}Session:${NC} ${CYAN}${name}${NC}"
        if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" ]]; then
            tmux list-windows -t "$name" -F "  #{window_index}: #{window_name}" 2>/dev/null
        else
            local idx=1
            while IFS= read -r tab_name; do
                echo "  ${idx}: ${tab_name}"
                idx=$((idx + 1))
            done < <(mux_list_targets "$name")
        fi
        echo ""
        read -rp "Kill entire session? [y/N] " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" ]]; then
                tmux kill-session -t "$name"
            else
                run_zellij kill-session "$name"
            fi
            echo -e "${GREEN}✓${NC} Session ${CYAN}${name}${NC} killed"
        fi
    fi
}

scan_projects() {
    local scan_dir="${1:-${VAIBHAV_PROJECTS_DIR:-$HOME/projects}}"
    scan_dir=$(cd "$scan_dir" 2>/dev/null && pwd)

    echo -e "${BOLD}Scanning${NC} ${scan_dir} ..."
    echo ""

    local count=0
    for dir in "$scan_dir"/*/; do
        [[ ! -d "$dir" ]] && continue
        local name
        name=$(basename "$dir")

        # Skip hidden directories
        [[ "$name" == .* ]] && continue

        if ! grep -q "^${name}=" "$PROJECTS_FILE" 2>/dev/null; then
            echo "${name}=${dir%/}" >> "$PROJECTS_FILE"
            echo -e "  ${GREEN}+${NC} ${CYAN}${name}${NC} → ${dir%/}"
            count=$((count + 1))
        else
            echo -e "  ${DIM}skip${NC} ${name} (already registered)"
        fi
    done

    sort -o "$PROJECTS_FILE" "$PROJECTS_FILE"
    echo ""
    echo -e "${count} project(s) added"
}

open_project() {
    local name="$1"
    local tool="${2:-}"

    local path
    path=$(get_project_path "$name")

    if [[ -z "$path" ]]; then
        echo -e "${RED}Error:${NC} Project '${name}' not found"
        echo -e "${DIM}Run 'vaibhav list' to see registered projects, or 'vaibhav add ${name} /path/to/project'${NC}"
        exit 1
    fi

    if [[ ! -d "$path" ]]; then
        echo -e "${RED}Error:${NC} Project directory does not exist: $path"
        exit 1
    fi

    # Validate tool if specified
    if [[ -n "$tool" ]]; then
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${RED}Error:${NC} Tool '${tool}' not found in PATH"
            if [[ "$tool" == "pi" ]]; then
                echo -e "${DIM}Install with: npm install -g @mariozechner/pi-coding-agent${NC}"
            fi
            exit 1
        fi
    fi

    require_mux_backend || exit 1

    if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" ]]; then
        # Create or attach to tmux session
        if tmux has-session -t "$name" 2>/dev/null; then
            # Session exists
            if [[ -n "$tool" ]]; then
                # Create a new window for the tool if not already running
                local tool_window="${tool}"
                if tmux list-windows -t "$name" -F "#{window_name}" | grep -qx "$tool_window"; then
                    # Tool window exists, select it
                    tmux select-window -t "${name}:${tool_window}"
                else
                    # Create new window with the tool
                    tmux new-window -t "$name" -n "$tool_window" -c "$path" "$tool"
                fi
            fi

            # Attach or switch
            if [[ -n "${TMUX:-}" ]]; then
                tmux switch-client -t "$name"
            else
                tmux attach-session -t "$name"
            fi
        else
            # Create new session
            if [[ -n "$tool" ]]; then
                # Create session with tool in first window
                tmux new-session -d -s "$name" -c "$path" -n "$tool" "$tool"
                # Add a shell window
                tmux new-window -t "$name" -n "shell" -c "$path"
                # Go back to tool window
                tmux select-window -t "${name}:${tool}"
            else
                # Create session with shell
                tmux new-session -d -s "$name" -c "$path" -n "shell"
            fi

            # Attach or switch
            if [[ -n "${TMUX:-}" ]]; then
                tmux switch-client -t "$name"
            else
                tmux attach-session -t "$name"
            fi
        fi
    else
        local inside_zellij=false
        [[ -n "${ZELLIJ:-}" ]] && inside_zellij=true

        if [[ "$inside_zellij" == "false" ]]; then
            if mux_session_exists "$name"; then
                # Session already exists — queue tool tab creation then attach.
                if [[ -n "$tool" ]] && ! mux_target_exists "$name" "$tool"; then
                    (
                        # Wait for a client to attach, then create and focus the tool tab.
                        for _try in $(seq 1 60); do
                            if run_zellij --session "$name" action new-tab --name "$tool" --cwd "$path" >/dev/null 2>&1; then
                                run_zellij --session "$name" action go-to-tab-name "$tool" >/dev/null 2>&1 || true
                                if ! run_zellij --session "$name" action new-pane --in-place --cwd "$path" -- "$tool" >/dev/null 2>&1; then
                                    run_zellij --session "$name" action write-chars "$tool" >/dev/null 2>&1 || true
                                    run_zellij --session "$name" action write 10 >/dev/null 2>&1 || true
                                fi
                                break
                            fi
                            sleep 0.3
                        done
                    ) >/dev/null 2>&1 &
                elif [[ -n "$tool" ]]; then
                    # Tool tab exists — just focus it after attach.
                    (
                        sleep 0.5
                        run_zellij --session "$name" action go-to-tab-name "$tool" >/dev/null 2>&1 || true
                    ) &
                fi
                (
                    cd "$path" || exit
                    run_zellij attach "$name"
                )
            else
                # Clean up dead/exited session with the same name if it exists.
                if run_zellij list-sessions --no-formatting 2>/dev/null | grep -q "^${name} .*EXITED"; then
                    run_zellij delete-session "$name" >/dev/null 2>&1 || true
                fi

                # Session doesn't exist — create it with a layout that includes the tool.
                local layout_file=""
                if [[ -n "$tool" ]]; then
                    layout_file=$(mktemp /tmp/vaibhav-zellij-XXXXXX.kdl)
                    cat > "$layout_file" <<LAYOUT_EOF
layout {
    cwd "$path"
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="tab-bar"
        }
        children
        pane size=1 borderless=true {
            plugin location="status-bar"
        }
    }
    tab name="shell" {
        pane
    }
    tab name="$tool" focus=true {
        pane command="$tool"
    }
}
LAYOUT_EOF
                fi

                (
                    cd "$path" || exit
                    if [[ -n "$layout_file" ]]; then
                        run_zellij -s "$name" --new-session-with-layout "$layout_file"
                        rm -f "$layout_file"
                    else
                        run_zellij attach --create "$name"
                    fi
                )
                [[ -n "$layout_file" ]] && rm -f "$layout_file"
            fi
        else
            # Inside zellij — switch to or create the session, then add/focus tool tab.
            mux_switch_or_attach "$name" "$path"

            if [[ -n "$tool" ]]; then
                if ! run_zellij action go-to-tab-name "$tool" >/dev/null 2>&1; then
                    if run_zellij action new-tab --name "$tool" --cwd "$path" >/dev/null 2>&1; then
                        run_zellij action go-to-tab-name "$tool" >/dev/null 2>&1 || true
                        if ! run_zellij action new-pane --in-place --cwd "$path" -- "$tool" >/dev/null 2>&1; then
                            run_zellij action write-chars "$tool" >/dev/null 2>&1 || true
                            run_zellij action write 10 >/dev/null 2>&1 || true
                        fi
                    else
                        echo -e "  ${YELLOW}!${NC} ${DIM}Could not create zellij tab '${tool}' in session '${name}'${NC}"
                    fi
                fi
                run_zellij action go-to-tab-name "$tool" >/dev/null 2>&1 || true
            fi
        fi
    fi
}
