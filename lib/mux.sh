# shellcheck shell=bash
# vaibhav/lib/mux.sh — Multiplexer abstraction (tmux / zellij)

normalize_multiplexer_preference() {
    local raw="${1:-auto}"
    raw=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
    case "$raw" in
        tmux|zellij|auto|"")
            printf '%s\n' "${raw:-auto}"
            ;;
        *)
            printf '%s\n' "auto"
            ;;
    esac
}

resolve_zellij_binary() {
    local configured="${VAIBHAV_ZELLIJ_BIN:-}"
    if [[ -n "$configured" && -x "$configured" ]]; then
        printf '%s\n' "$configured"
        return 0
    fi

    local from_path=""
    from_path=$(command -v zellij 2>/dev/null || true)
    if [[ -n "$from_path" && -x "$from_path" ]]; then
        printf '%s\n' "$from_path"
        return 0
    fi

    local candidate
    for candidate in "$HOME/.cargo/bin/zellij" "$HOME/.local/bin/zellij" "/usr/local/bin/zellij" "/snap/bin/zellij"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    printf '%s\n' ""
    return 0
}

resolve_multiplexer_backend() {
    local preference="${1:-auto}"
    local backend=""

    case "$preference" in
        tmux)
            if command -v tmux >/dev/null 2>&1; then
                backend="tmux"
            fi
            ;;
        zellij)
            if [[ -n "$VAIBHAV_ZELLIJ_BIN" ]]; then
                backend="zellij"
            fi
            ;;
        auto)
            if command -v tmux >/dev/null 2>&1; then
                backend="tmux"
            elif [[ -n "$VAIBHAV_ZELLIJ_BIN" ]]; then
                backend="zellij"
            fi
            ;;
    esac

    printf '%s\n' "$backend"
    return 0
}

mux_backend_name() {
    if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" || "$VAIBHAV_MUX_BACKEND" == "zellij" ]]; then
        printf '%s\n' "$VAIBHAV_MUX_BACKEND"
    else
        printf '%s\n' "session"
    fi
}

mux_target_name() {
    if [[ "$VAIBHAV_MUX_BACKEND" == "zellij" ]]; then
        printf '%s\n' "tab"
    else
        printf '%s\n' "window"
    fi
}

mux_target_name_plural() {
    if [[ "$VAIBHAV_MUX_BACKEND" == "zellij" ]]; then
        printf '%s\n' "tabs"
    else
        printf '%s\n' "windows"
    fi
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
        zellij)
            echo -e "${RED}Error:${NC} zellij is selected but not installed"
            echo -e "${DIM}Install with: cargo install --locked zellij${NC}"
            echo -e "${DIM}If already installed outside PATH, set VAIBHAV_ZELLIJ_BIN in ${CONFIG_FILE}${NC}"
            ;;
        *)
            echo -e "${RED}Error:${NC} No supported multiplexer found"
            echo -e "${DIM}Install tmux (sudo apt install tmux) or zellij (cargo install --locked zellij)${NC}"
            ;;
    esac
    return 1
}

run_zellij() {
    "$VAIBHAV_ZELLIJ_BIN" "$@"
}

mux_active_sessions_for_backend() {
    local backend="$1"
    case "$backend" in
        tmux)
            tmux list-sessions -F "#{session_name}" 2>/dev/null || true
            ;;
        zellij)
            run_zellij list-sessions --no-formatting 2>/dev/null |
                awk '
                    /^[[:space:]]*$/ { next }
                    /No active sessions/ { next }
                    /\(EXITED/ { next }
                    { print $1 }
                ' || true
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
        zellij)
            run_zellij --session "$session" action query-tab-names 2>/dev/null | sed '/^[[:space:]]*$/d' || true
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
    local path="$2"

    case "$VAIBHAV_MUX_BACKEND" in
        tmux)
            if [[ -n "${TMUX:-}" ]]; then
                tmux switch-client -t "$session"
            else
                tmux attach-session -t "$session"
            fi
            ;;
        zellij)
            if [[ -n "${ZELLIJ:-}" ]]; then
                if ! run_zellij action switch-session "$session" --cwd "$path"; then
                    run_zellij action switch-session "$session"
                fi
            else
                (
                    cd "$path" || return
                    run_zellij attach --create "$session"
                )
            fi
            ;;
    esac
}

zellij_ensure_background_session() {
    local session="$1"
    local path="$2"

    (
        cd "$path"
        run_zellij attach --create-background "$session"
    ) >/dev/null 2>&1 || true
}
