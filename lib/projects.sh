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

    local active_sessions=""
    active_sessions=$(mux_active_sessions || true)

    while IFS='=' read -r name path; do
        [[ -z "$name" || "$name" == \#* ]] && continue

        local status="${DIM}inactive${NC}"
        local indicator=" "

        if echo "$active_sessions" | grep -qx "$name" 2>/dev/null; then
            local targets
            targets=$(mux_targets_csv "$name")
            status="${GREEN}active${NC} ${DIM}[${targets}]${NC}"
            indicator="${GREEN}●${NC}"
        fi

        if echo "$active_sessions" | grep -qx "ralph-${name}" 2>/dev/null; then
            status+=" ${YELLOW}ralph running${NC}"
            [[ "$indicator" == " " ]] && indicator="${YELLOW}●${NC}"
        fi

        echo -e "  ${indicator} ${CYAN}${name}${NC} ${DIM}→${NC} ${path}"
        echo -e "    ${status}"
    done < "$PROJECTS_FILE"

    echo ""

    # Show orphan sessions (not in projects file)
    if [[ -n "$active_sessions" ]]; then
        local orphans=""
        while IFS= read -r session; do
            # Skip ralph sessions (shown with their project above)
            local base_name="${session#ralph-}"
            if [[ "$base_name" != "$session" ]] && grep -q "^${base_name}=" "$PROJECTS_FILE" 2>/dev/null; then
                continue
            fi
            if ! grep -q "^${session}=" "$PROJECTS_FILE" 2>/dev/null; then
                orphans+="  ${YELLOW}?${NC} ${session}\n"
            fi
        done <<< "$active_sessions"
        if [[ -n "$orphans" ]]; then
            echo -e "${BOLD}Other tmux sessions${NC}"
            echo ""
            echo -e "$orphans"
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
    if mux_session_exists "$name"; then
        read -rp "Kill active tmux session '$name'? [y/N] " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            tmux kill-session -t "$name"
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
        # Kill specific window
        if ! mux_target_exists "$name" "$window"; then
            echo -e "${RED}Error:${NC} Window '${window}' not found in session '${name}'"
            echo -e "${DIM}Active windows:${NC}"
            tmux list-windows -t "$name" -F "  #{window_index}: #{window_name}" 2>/dev/null
            exit 1
        fi

        tmux kill-window -t "${name}:${window}"
        echo -e "${GREEN}✓${NC} Killed window ${CYAN}${window}${NC} in ${CYAN}${name}${NC}"
    else
        # Kill entire session — show windows first
        echo -e "${BOLD}Session:${NC} ${CYAN}${name}${NC}"
        tmux list-windows -t "$name" -F "  #{window_index}: #{window_name}" 2>/dev/null
        echo ""
        read -rp "Kill entire session? [y/N] " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            tmux kill-session -t "$name"
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
}
