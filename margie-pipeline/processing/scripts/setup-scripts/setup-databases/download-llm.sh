#!/usr/bin/env bash
# download-llm.sh — fetches the optional LLM artefacts (base / trained / adapters) with the
# HuggingFace CLI. Each slot in pipeline.conf.sh is empty, a HuggingFace id (downloaded
# into $LLM_ROOT/<slot>/) or a local path (only checked).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# LLM logs get their own subdirectory; := lets a caller override it.
: "${LOG_DIR:=$(cd "$here/../../../.." && pwd)/logs/databases/llm}"
source "$here/lib.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_DB/processing/scripts/shared/hf-env.sh"
tag="download-llm"
db_parse_args "$@"

mkdir -p "$LLM_ROOT"

# Returns 0 when the hf or huggingface-cli command is available.
_hf_available() { command -v hf >/dev/null 2>&1 || command -v huggingface-cli >/dev/null 2>&1; }

# _check_one <slot> <value> — checks a local path, or downloads a HuggingFace repo id.
_check_one() {
    local slot=$1 value=$2
    local target="$LLM_ROOT/$slot"

    if [[ -z "$value" ]]; then
        log "$slot: not configured (set $slot in pipeline.conf.sh or env to enable) — skipped"
        return 0
    fi

    # Local path.
    if [[ "$value" == /* || "$value" == ./* || "$value" == ~* ]]; then
        local resolved=${value/#~/$HOME}
        if [[ -e "$resolved" ]]; then
            ok "$slot: local path OK → $resolved"
        else
            err "$slot: local path NOT FOUND → $resolved"
            return 1
        fi
        return 0
    fi

    # Otherwise a HuggingFace repo id ('org/name').
    if [[ "$value" != */* ]]; then
        err "$slot: '$value' is neither a local path nor a HuggingFace repo id (expected 'org/name')"
        return 1
    fi

    # A directory counts as complete only with at least one .safetensors, .bin or .pt file.
    if [[ -d "$target" && "${REDO:-0}" -eq 0 ]]; then
        if find "$target" -maxdepth 3 \
               \( -name "*.safetensors" -o -name "*.bin" -o -name "*.pt" \) \
               -print -quit 2>/dev/null | grep -q .; then
            ok "$slot: already downloaded → $target (use --redo to refresh)"
            return 0
        else
            warn "$slot: directory exists but no weight files found — re-downloading"
        fi
    fi

    if ! _hf_available; then
        warn "$slot: hf CLI not in PATH — bootstrapping local venv"
        if ! hf_env_activate; then
            err "$slot: could not provision HF download env — aborting"
            return 1
        fi
    fi

    log "$slot: downloading $value → $target"
    run mkdir -p "$target"
    run hf_download "$value" "$target"
    ok "$slot: ready → $target"
}

log "LLM model download (optional — not part of automated database setup)"
log "  Invoke manually with: ./setup.sh --databases-only --tool llm [--redo]"

# ── Determine whether any slot targets a HuggingFace repo ─────────────────
_needs_hf=0
_all_empty=1
for _v in "${LLM_BASE_MODEL:-}" "${LLM_TRAINED_MODEL:-}" "${LLM_TRAINED_ADAPTERS:-}"; do
    [[ -n "$_v" ]] && _all_empty=0
    [[ -n "$_v" && "$_v" != /* && "$_v" != ~* && "$_v" != ./* ]] && _needs_hf=1
done

# ── Case 1: no model configured at all ────────────────────────────────────
# Activates the HF env (asks for a token), then lists the available models.
if (( _all_empty )); then
    log "No LLM model configured (LLM_BASE_MODEL / LLM_TRAINED_MODEL / LLM_TRAINED_ADAPTERS are all empty)."
    log "Activate token to show available models, or press Ctrl+C to skip."

    set +e; hf_env_activate; _hf_rc=$?; set -e
    if (( _hf_rc == 2 )); then
        warn "llm: token skipped — no model list shown."
        warn "     Set LLM_BASE_MODEL in pipeline.conf.sh, then re-run:"
        warn "       ./setup.sh --databases-only --tool llm"
        exit 0
    elif (( _hf_rc != 0 )); then
        err "failed to set up HuggingFace env"; exit 1
    fi

    printf '\n' >&2
    printf '  No LLM model is configured for this pipeline. Below is a list of\n' >&2
    printf '  recommended models and your current access status.\n' >&2
    printf '\n' >&2
    printf '  IMPORTANT — Gated models require YOU to manually request access:\n' >&2
    printf '    1. Visit the model card URL shown below.\n' >&2
    printf '    2. Accept the model owner'"'"'s terms (Meta, Google, etc.).\n' >&2
    printf '    3. Approval is granted by the model owner, not by this pipeline.\n' >&2
    printf '       It typically takes seconds to a few hours.\n' >&2
    printf '    4. Once approved, set the model in pipeline.conf.sh:\n' >&2
    printf '         LLM_BASE_MODEL="<org>/<model-name>"\n' >&2
    printf '    5. Re-run: ./setup.sh --databases-only --tool llm\n' >&2

    hf_list_models
    exit 0
fi

# ── Case 2: at least one slot is configured ───────────────────────────────
if (( _needs_hf )); then
    # Asks for the token once, before any download.
    set +e; hf_env_activate; _hf_rc=$?; set -e
    if (( _hf_rc == 2 )); then
        warn "llm: HuggingFace token skipped — models NOT downloaded."
        warn "     re-run later with: ./setup.sh --databases-only --tool llm"
        exit 0
    elif (( _hf_rc != 0 )); then
        err "failed to set up HuggingFace download env"; exit 1
    fi

    # Notes that gated models need approval from their owners.
    printf '\n' >&2
    printf '  NOTE: Some HuggingFace models require prior access approval from\n' >&2
    printf '  the model owner (Meta, Google, etc.). If a download fails with a\n' >&2
    printf '  403 / "access denied" error:\n' >&2
    printf '    1. Visit https://huggingface.co/<org>/<model> and accept the terms.\n' >&2
    printf '    2. Wait for approval (usually instant for open-access gated models).\n' >&2
    printf '    3. Re-run: ./setup.sh --databases-only --tool llm\n' >&2
    printf '\n' >&2
    printf '  To see all available models and your current approval status, run:\n' >&2
    printf '    ./setup.sh --databases-only --tool llm  (with empty LLM_BASE_MODEL)\n' >&2
    printf '\n' >&2
fi

rc=0
_check_one base     "${LLM_BASE_MODEL:-}"        || rc=1
_check_one trained  "${LLM_TRAINED_MODEL:-}"     || rc=1
_check_one adapters "${LLM_TRAINED_ADAPTERS:-}"  || rc=1

if (( rc == 0 )); then
    ok "llm slots checked → $LLM_ROOT"
    # Reminds to revoke the HuggingFace token entered above.
    printf '\n' >&2
    printf '  ╔══════════════════════════════════════════════════════════════════╗\n' >&2
    printf '  ║  SECURITY REMINDER — ACTION REQUIRED                            ║\n' >&2
    printf '  ║                                                                  ║\n' >&2
    printf '  ║  If you entered a HuggingFace token above, please revoke it now  ║\n' >&2
    printf '  ║  to prevent misuse in the event it was captured anywhere:        ║\n' >&2
    printf '  ║    https://huggingface.co/settings/tokens                        ║\n' >&2
    printf '  ║                                                                  ║\n' >&2
    printf '  ║  The next time you need to re-download, simply generate a new    ║\n' >&2
    printf '  ║  token. The pipeline will prompt you for it automatically.       ║\n' >&2
    printf '  ╚══════════════════════════════════════════════════════════════════╝\n' >&2
    printf '\n' >&2
else
    err "llm: one or more slots failed — see messages above"
fi
exit $rc
