# shellcheck shell=bash
# vaibhav/lib/mux.sh — Multiplexer abstraction (tmux, herdr)

normalize_multiplexer_preference() {
    local raw="${1:-auto}"
    raw=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
    case "$raw" in
        tmux|herdr|auto|"")
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
        tmux)
            if command -v tmux >/dev/null 2>&1; then
                backend="tmux"
            fi
            ;;
        herdr)
            if command -v herdr >/dev/null 2>&1; then
                backend="herdr"
            fi
            ;;
        auto)
            if command -v tmux >/dev/null 2>&1; then
                backend="tmux"
            elif command -v herdr >/dev/null 2>&1; then
                backend="herdr"
            fi
            ;;
    esac

    printf '%s\n' "$backend"
    return 0
}

mux_backend_name() {
    if [[ "$VAIBHAV_MUX_BACKEND" == "tmux" || "$VAIBHAV_MUX_BACKEND" == "herdr" ]]; then
        printf '%s\n' "$VAIBHAV_MUX_BACKEND"
    else
        printf '%s\n' "session"
    fi
}

mux_target_name() {
    if [[ "$VAIBHAV_MUX_BACKEND" == "herdr" ]]; then
        printf '%s\n' "tab"
    else
        printf '%s\n' "window"
    fi
}

mux_target_name_plural() {
    if [[ "$VAIBHAV_MUX_BACKEND" == "herdr" ]]; then
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
        herdr)
            echo -e "${RED}Error:${NC} herdr is selected but not installed"
            echo -e "${DIM}Install with: curl -fsSL https://herdr.dev/install.sh | sh${NC}"
            ;;
        *)
            echo -e "${RED}Error:${NC} No supported multiplexer found"
            echo -e "${DIM}Install tmux or herdr.${NC}"
            ;;
    esac
    return 1
}

_mux_herdr_json_objects() {
    tr '{' '\n'
}

_mux_herdr_workspace_id_by_label() {
    local label="$1"
    herdr workspace list 2>/dev/null \
        | _mux_herdr_json_objects \
        | grep -F "\"label\":\"${label}\"" \
        | sed -n 's/.*"workspace_id":"\([^"]*\)".*/\1/p' \
        | head -1 || true
}

_mux_herdr_tab_id_by_label() {
    local workspace_id="$1" label="$2"
    herdr tab list --workspace "$workspace_id" 2>/dev/null \
        | _mux_herdr_json_objects \
        | grep -F "\"label\":\"${label}\"" \
        | sed -n 's/.*"tab_id":"\([^"]*\)".*/\1/p' \
        | head -1 || true
}

_mux_herdr_labels_from_json() {
    grep -Eo '"label":"[^"]+"' \
        | sed 's/^"label":"//; s/"$//'
}

mux_active_sessions_for_backend() {
    local backend="$1"
    case "$backend" in
        tmux)
            tmux list-sessions -F "#{session_name}" 2>/dev/null || true
            ;;
        herdr)
            herdr workspace list 2>/dev/null | _mux_herdr_labels_from_json || true
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
        herdr)
            local workspace_id
            workspace_id="$(_mux_herdr_workspace_id_by_label "$session")"
            [[ -n "$workspace_id" ]] || return 0
            herdr tab list --workspace "$workspace_id" 2>/dev/null | _mux_herdr_labels_from_json || true
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
        herdr)
            local workspace_id
            workspace_id="$(_mux_herdr_workspace_id_by_label "$session")"
            if [[ -n "$workspace_id" ]]; then
                herdr workspace focus "$workspace_id" >/dev/null 2>&1 || true
            fi
            if [[ -z "${HERDR_ENV:-}" ]]; then
                herdr
            fi
            ;;
    esac
}

mux_create_session() {
    local session="$1" path="$2" target="${3:-shell}" command="${4:-}"

    case "$VAIBHAV_MUX_BACKEND" in
        tmux)
            if [[ -n "$command" ]]; then
                tmux new-session -d -s "$session" -c "$path" -n "$target" "$command"
                tmux new-window -t "$session" -n "shell" -c "$path"
                tmux select-window -t "${session}:${target}"
            else
                tmux new-session -d -s "$session" -c "$path" -n "$target"
            fi
            ;;
        herdr)
            local create_output tab_id
            create_output="$(herdr workspace create --cwd "$path" --label "$session" --focus)"
            tab_id="$(sed -n 's/.*"tab_id":"\([^"]*\)".*/\1/p' <<<"$create_output" | head -1)"
            if [[ -n "$tab_id" ]]; then
                if [[ -n "$command" ]]; then
                    herdr tab rename "$tab_id" "shell" >/dev/null 2>&1 || true
                else
                    herdr tab rename "$tab_id" "$target" >/dev/null 2>&1 || true
                fi
            fi
            if [[ -n "$command" ]]; then
                mux_create_target "$session" "$target" "$path" "$command"
            fi
            ;;
    esac
}

mux_create_target() {
    local session="$1" target="$2" path="$3" command="${4:-}"

    case "$VAIBHAV_MUX_BACKEND" in
        tmux)
            if [[ -n "$command" ]]; then
                tmux new-window -t "$session" -n "$target" -c "$path" "$command"
            else
                tmux new-window -t "$session" -n "$target" -c "$path"
            fi
            ;;
        herdr)
            local workspace_id tab_id pane_id
            workspace_id="$(_mux_herdr_workspace_id_by_label "$session")"
            [[ -n "$workspace_id" ]] || return 1
            tab_id="$(herdr tab create --workspace "$workspace_id" --cwd "$path" --label "$target" --focus \
                | sed -n 's/.*"tab_id":"\([^"]*\)".*/\1/p')"
            [[ -n "$tab_id" ]] || return 1
            if [[ -n "$command" ]]; then
                herdr agent start "$target" --cwd "$path" --workspace "$workspace_id" --tab "$tab_id" -- "$command" >/dev/null
            else
                pane_id="$(herdr pane list --workspace "$workspace_id" \
                    | _mux_herdr_json_objects \
                    | grep -F "\"tab_id\":\"${tab_id}\"" \
                    | sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p' \
                    | head -1 || true)"
                if [[ -n "$pane_id" ]]; then
                    herdr pane focus --pane "$pane_id" >/dev/null 2>&1 || true
                fi
            fi
            ;;
    esac
}

mux_select_target() {
    local session="$1" target="$2"

    case "$VAIBHAV_MUX_BACKEND" in
        tmux)
            tmux select-window -t "${session}:${target}"
            ;;
        herdr)
            local workspace_id tab_id
            workspace_id="$(_mux_herdr_workspace_id_by_label "$session")"
            [[ -n "$workspace_id" ]] || return 1
            tab_id="$(_mux_herdr_tab_id_by_label "$workspace_id" "$target")"
            [[ -n "$tab_id" ]] || return 1
            herdr tab focus "$tab_id" >/dev/null
            ;;
    esac
}

mux_kill_session() {
    local session="$1"

    case "$VAIBHAV_MUX_BACKEND" in
        tmux)
            tmux kill-session -t "$session"
            ;;
        herdr)
            local workspace_id
            workspace_id="$(_mux_herdr_workspace_id_by_label "$session")"
            [[ -n "$workspace_id" ]] && herdr workspace close "$workspace_id" >/dev/null
            ;;
    esac
}

mux_kill_target() {
    local session="$1" target="$2"

    case "$VAIBHAV_MUX_BACKEND" in
        tmux)
            tmux kill-window -t "${session}:${target}"
            ;;
        herdr)
            local workspace_id tab_id
            workspace_id="$(_mux_herdr_workspace_id_by_label "$session")"
            [[ -n "$workspace_id" ]] || return 1
            tab_id="$(_mux_herdr_tab_id_by_label "$workspace_id" "$target")"
            [[ -n "$tab_id" ]] || return 1
            herdr tab close "$tab_id" >/dev/null
            ;;
    esac
}
