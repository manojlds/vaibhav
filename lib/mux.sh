# shellcheck shell=bash
# vaibhav/lib/mux.sh — Multiplexer abstraction (tmux)

normalize_multiplexer_preference() {
    local raw="${1:-auto}"
    raw=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
    case "$raw" in
        tmux|auto|"")
            printf '%s\n' "${raw:-auto}"
            ;;
        *)
            printf '%s\n' "auto"
            ;;
    esac
}

resolve_multiplexer_backend() {
    local preference="${1:-auto}"
    local backend=""

    case "$preference" in
        tmux|auto)
            if command -v tmux >/dev/null 2>&1; then
                backend="tmux"
            fi
            ;;
    esac

    printf '%s\n' "$backend"
    return 0
}

mux_backend_name() {
    if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" ]]; then
        printf '%s\n' "$VAIBHAV_MUX_BACKEND"
    else
        printf '%s\n' "session"
    fi
}

mux_target_name() {
    printf '%s\n' "window"
}

mux_target_name_plural() {
    printf '%s\n' "windows"
}

require_mux_backend() {
    if [[ -n "$VAIBHAV_MUX_BACKEND" ]]; then
        return 0
    fi

    case "$VAIBHAV_MULTIPLEXER" in
        tmux)
            echo -e "${RED}Error:${NC} tmux is selected but not installed"
            echo -e "${DIM}Install with: sudo apt install tmux${NC}"
            ;;
        *)
            echo -e "${RED}Error:${NC} No supported multiplexer found"
            echo -e "${DIM}Install tmux: sudo apt install tmux${NC}"
            ;;
    esac
    return 1
}

mux_active_sessions_for_backend() {
    local backend="$1"
    case "$backend" in
        tmux)
            tmux list-sessions -F "#{session_name}" 2>/dev/null || true
            ;;
    esac
}

mux_active_sessions() {
    mux_active_sessions_for_backend "$VAIBHAV_MUX_BACKEND"
}

mux_session_exists() {
    local session="$1"
    mux_active_sessions | grep -qx "$session" 2>/dev/null
}

mux_list_targets_for_backend() {
    local backend="$1"
    local session="$2"
    case "$backend" in
        tmux)
            tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null || true
            ;;
    esac
}

mux_list_targets() {
    local session="$1"
    mux_list_targets_for_backend "$VAIBHAV_MUX_BACKEND" "$session"
}

mux_target_exists() {
    local session="$1"
    local target="$2"
    mux_list_targets "$session" | grep -qx "$target" 2>/dev/null
}

mux_targets_csv_for_backend() {
    local backend="$1"
    local session="$2"
    mux_list_targets_for_backend "$backend" "$session" | tr '\n' ',' | sed 's/,$//'
}

mux_targets_csv() {
    local session="$1"
    mux_targets_csv_for_backend "$VAIBHAV_MUX_BACKEND" "$session"
}

mux_switch_or_attach() {
    local session="$1"

    case "$VAIBHAV_MUX_BACKEND" in
        tmux)
            if [[ -n "${TMUX:-}" ]]; then
                tmux switch-client -t "$session"
            else
                tmux attach-session -t "$session"
            fi
            ;;
    esac
}
