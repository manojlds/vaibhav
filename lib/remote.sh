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

if [[ -n "$VAIBHAV_DESKTOP_HOST" ]] && [[ "$(hostname)" != "$VAIBHAV_DESKTOP_HOST" ]]; then
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
    if [[ -n "$VAIBHAV_MUX_OVERRIDE" ]]; then
        if [[ -n "$forwarded_args" ]]; then
            forwarded_args="--mux ${VAIBHAV_MUX_OVERRIDE} ${forwarded_args}"
        else
            forwarded_args="--mux ${VAIBHAV_MUX_OVERRIDE}"
        fi
    fi

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
