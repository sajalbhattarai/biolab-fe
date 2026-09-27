#!/usr/bin/env bash
# bvbrc-env.sh — manages the BV-BRC CLI login session used by RASTtk.
# The session is ~/.patric_token (un=…), which Apptainer sees via its $HOME mount.
#
# Public API:
#   bvbrc_env_activate <image>   ensures a session, prompting a login if needed
#   bvbrc_reset_session          deletes the local session (forces re-login)
#
# Sources pipeline.conf.sh itself when it is not loaded yet.
#
# Return codes used throughout:
#   0  success / session ready
#   1  hard failure (login failed, unexpected error)
#   2  skipped (non-interactive TTY, or user declined)

# ── bootstrap: pipeline.conf.sh (detected by BVBRC_SESSION_DIR) ──
if [[ -z "${BVBRC_SESSION_DIR:-}" ]]; then
    _bvbrc_conf="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/pipeline.conf.sh"
    # shellcheck source=../../../pipeline.conf.sh
    [[ -f "$_bvbrc_conf" ]] && source "$_bvbrc_conf"
fi

# ── output helpers ──

_bvbrc_log()  { printf '[bvbrc] %s\n'         "$*" >&2; }
_bvbrc_warn() { printf '[bvbrc] WARNING: %s\n' "$*" >&2; }
_bvbrc_err()  { printf '[bvbrc] ERROR: %s\n'   "$*" >&2; }

# Prints the credential file path (plain-text token written by bvbrc-cli 1.048+).
_bvbrc_creds() { echo "${HOME}/.patric_token"; }

# Succeeds when the token file exists, is non-empty and starts with "un=" (no network check).
_bvbrc_session_valid() {
    local creds; creds="$(_bvbrc_creds)"
    [[ -f "$creds" ]] && [[ -s "$creds" ]] && grep -q '^un=' "$creds" 2>/dev/null
}

# Runs `p3-login` inside the rasttk container ($1: SIF file or registry URI).
# Returns 0 on login, 1 on failure, 2 when skipped (no TTY or BVBRC_NONINTERACTIVE=1).
_bvbrc_prompt_login() {
    local image="$1"

    # Resolves a registry URI to the local SIF, as run_container does.
    if [[ "$image" != *.sif && "$image" != /* && -n "${SIF_DIR:-}" ]]; then
        local _name _sif_local
        _name="$(basename "${image%%:*}")"
        _sif_local="${SIF_DIR}/${_name}.sif"
        [[ -f "$_sif_local" ]] && image="$_sif_local"
    fi

    # Without a TTY it warns and skips rather than blocking a SLURM job.
    if [[ "${BVBRC_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
        _bvbrc_warn "stdin is not a TTY — cannot run interactive p3-login."
        _bvbrc_warn "  To pre-cache credentials before a SLURM run:"
        _bvbrc_warn "    1. Set BVBRC_LOGIN=1 in pipeline.conf.sh"
        _bvbrc_warn "    2. Run from an interactive terminal: ./annotate.sh"
        _bvbrc_warn "  The session is then cached and reused automatically."
        return 2
    fi

    _bvbrc_log "───────────────────────────────────────────────────────────────"
    _bvbrc_log "BV-BRC login required (BVBRC_LOGIN=1)"
    _bvbrc_log "p3-login will run inside the rasttk container."
    _bvbrc_log "Enter your BV-BRC (PATRIC) username and password when prompted."
    _bvbrc_log "Credentials will be stored at: $(_bvbrc_creds)"
    _bvbrc_log "───────────────────────────────────────────────────────────────"
    printf '\n' >&2

    local runtime rc=0
    runtime="$(detect_runtime)" || {
        _bvbrc_err "could not detect a container runtime (RUNTIME=${RUNTIME:-auto})"
        return 1
    }

    # A preset username leaves only the password to prompt for.
    local p3_cmd=( p3-login )
    [[ -n "${BVBRC_USERNAME:-}" ]] && p3_cmd+=( "$BVBRC_USERNAME" )

    case "$runtime" in
        apptainer|singularity)
            # `script` gives p3-login a PTY, which apptainer exec lacks.
            local _tmpsh
            _tmpsh="$(mktemp /tmp/bvbrc-login-XXXXXX.sh)"
            {
                printf '#!/usr/bin/env bash\n'
                printf '%q ' "$runtime" exec --writable-tmpfs "$image" "${p3_cmd[@]+"${p3_cmd[@]}"}"
                printf '\n'
            } > "$_tmpsh"
            chmod +x "$_tmpsh"
            script -q -c "$_tmpsh" /dev/null || rc=$?
            rm -f "$_tmpsh"
            ;;
        docker)
            # Docker does not mount the host home; bind ~/.p3 explicitly.
            docker run --rm -it \
                --volume "${HOME}/.p3:/root/.p3:rw" \
                "$image" \
                "${p3_cmd[@]+"${p3_cmd[@]}"}" || rc=$?
            ;;
        *)
            _bvbrc_err "unknown RUNTIME '$runtime' (expected apptainer/singularity/docker)"
            return 1
            ;;
    esac

    if (( rc != 0 )); then
        _bvbrc_err "p3-login exited with code $rc — login failed."
        return 1
    fi

    if ! _bvbrc_session_valid; then
        _bvbrc_err "p3-login completed but no credentials were written."
        _bvbrc_err "  Expected: $(_bvbrc_creds)"
        return 1
    fi

    chmod 600 "$(_bvbrc_creds)"
    printf '\n' >&2
    _bvbrc_log "BV-BRC login successful. Session cached at: $(_bvbrc_creds)"
    printf '\n' >&2
    return 0
}

# ── public API ──

# bvbrc_env_activate <image> -- ensures a BV-BRC session, reusing a cached token
# or running p3-login in <image>. Returns 0 ready, 1 failed, 2 skipped.
bvbrc_env_activate() {
    local image="${1:-}"

    if _bvbrc_session_valid; then
        _bvbrc_log "cached BV-BRC session found — skipping login prompt."
        return 0
    fi

    if [[ -z "$image" ]]; then
        _bvbrc_warn "BVBRC_LOGIN=1 but no rasttk image path provided."
        _bvbrc_warn "  BV-BRC credentials will NOT be available in the container."
        return 2
    fi

    _bvbrc_prompt_login "$image"
}

# bvbrc_reset_session -- deletes the local credential file, forcing a re-login.
bvbrc_reset_session() {
    local creds; creds="$(_bvbrc_creds)"
    if [[ -f "$creds" ]]; then
        rm -f "$creds"
        _bvbrc_log "BV-BRC session cleared ($creds removed)."
    else
        _bvbrc_log "no cached BV-BRC session found — nothing to clear."
    fi
}
