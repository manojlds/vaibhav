# shellcheck shell=bash
# vaibhav/lib/remote.sh — Remote mode: SSH/mosh dispatch to desktop

VAIBHAV_DESKTOP_HOST="${VAIBHAV_DESKTOP_HOST:-}"
VAIBHAV_SSH_HOST="${VAIBHAV_SSH_HOST:-desktop}"
VAIBHAV_USE_MOSH="${VAIBHAV_USE_MOSH:-false}"
VAIBHAV_MOSH_NO_INIT="${VAIBHAV_MOSH_NO_INIT:-true}"
VAIBHAV_LAN_HOST="${VAIBHAV_LAN_HOST:-}"

# Resolve LAN host once — builds a global opts array used by all SSH calls
_VSSH_OPTS=()
if [[ -n "${VAIBHAV_LAN_HOST:-}" ]] && ping -c 1 -W 2 "$VAIBHAV_LAN_HOST" >/dev/null 2>&1; then
    _VSSH_OPTS=(-o "HostName=$VAIBHAV_LAN_HOST")
fi

vaibhav_is_current_host_desktop() {
    local configured="${VAIBHAV_DESKTOP_HOST:-}"
    [[ -z "$configured" ]] && return 1

    configured=$(printf '%s' "$configured" | tr '[:upper:]' '[:lower:]')
    configured="${configured%.}"
    local configured_short="${configured%%.*}"

    local current=""
    for current in "$(hostname 2>/dev/null || true)" "$(hostname -s 2>/dev/null || true)" "$(hostname -f 2>/dev/null || true)"; do
        [[ -z "$current" ]] && continue
        current=$(printf '%s' "$current" | tr '[:upper:]' '[:lower:]')
        current="${current%.}"
        local current_short="${current%%.*}"

        if [[ "$current" == "$configured" ]] || [[ "$current" == "$configured_short" ]] || [[ "$current_short" == "$configured" ]] || [[ "$current_short" == "$configured_short" ]]; then
            return 0
        fi
    done

    return 1
}

if [[ -n "$VAIBHAV_DESKTOP_HOST" ]] && ! vaibhav_is_current_host_desktop; then
    echo -e "${BOLD}vaibhav${NC} ${DIM}v${VAIBHAV_VERSION}${NC}"

    # Check for --mosh flag
    use_mosh="$VAIBHAV_USE_MOSH"
    args=()
    for arg in "$@"; do
        if [[ "$arg" == "--mosh" ]]; then
            use_mosh=true
        else
            args+=("$arg")
        fi
    done
    set -- "${args[@]+"${args[@]}"}"

    forwarded_args="$*"

    case "${1:-}" in
        init|update|setup|doctor|refresh)
            ;; # init, update, setup, doctor, and refresh always run locally
        list|ls|help|-h|--help|web)
            exec ssh "${_VSSH_OPTS[@]}" "$VAIBHAV_SSH_HOST" "\$SHELL -lic '\$HOME/bin/vaibhav ${forwarded_args}'"
            ;;
        *)
            if [[ "$use_mosh" == "true" ]] && command -v mosh &>/dev/null; then
                mosh_args=()
                if [[ "$VAIBHAV_MOSH_NO_INIT" == "true" ]]; then
                    mosh_args+=(--no-init)
                fi
                echo -e "  ${DIM}connecting via mosh...${NC}"
                exec mosh --ssh="ssh ${_VSSH_OPTS[*]}" "${mosh_args[@]}" "$VAIBHAV_SSH_HOST" -- sh -c "\$SHELL -lic \"\\\$HOME/bin/vaibhav ${forwarded_args}\""
            else
                if [[ "$use_mosh" == "true" ]]; then
                    echo -e "  ${YELLOW}!${NC} ${DIM}mosh not found, falling back to ssh${NC}"
                fi
                exec ssh -t "${_VSSH_OPTS[@]}" "$VAIBHAV_SSH_HOST" "\$SHELL -lic '\$HOME/bin/vaibhav ${forwarded_args}'"
            fi
            ;;
    esac
fi
