# shellcheck shell=bash
# hf-env.sh — HuggingFace download helper, sourced by download-llm.sh.
# Builds a venv at $HF_ENV_DIR with huggingface_hub and manages the HF token
# at $HF_TOKEN_FILE_PATH (chmod 600, gitignored).
#
# Public functions:
#   hf_env_activate          ensures venv + token, then exports PATH/env.
#                            Honors:
#                              HF_TOKEN_FILE  — read token from this file
#                              HF_RESET       — 1 = re-prompt + overwrite
#                              HF_NONINTERACTIVE — 1 = never prompt
#
# Locations (under $REPO_ROOT):
#   processing/.hf-env/              venv
#   processing/.hf-env/hf_token      stored token (chmod 600)

set -u

# Resolves the repo root when the caller has not.
if [[ -z "${REPO_ROOT_DB:-}" && -z "${REPO_ROOT:-}" ]]; then
    _HF_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "$_HF_HERE/../../.." && pwd)"
fi
: "${REPO_ROOT:=${REPO_ROOT_DB:-}}"

: "${HF_ENV_DIR:=$REPO_ROOT/processing/.hf-env}"
: "${HF_TOKEN_FILE_PATH:=$HF_ENV_DIR/hf_token}"

# ---- internal helpers -------------------------------------------------------

_hf_log()  { printf '  [hf-env] %s\n' "$*" >&2; }
_hf_warn() { printf '  [hf-env] WARN: %s\n' "$*" >&2; }
_hf_err()  { printf '  [hf-env] ERROR: %s\n' "$*" >&2; }

# Prints usable Python >= 3.8 interpreters, best first, one per line (also after
# `module load python` on clusters).
_hf_find_python() {
    _hf_try() {
        local p="$1"
        command -v "$p" >/dev/null 2>&1 || return 1
        "$p" -c 'import sys; sys.exit(0 if sys.version_info[:2] >= (3,8) else 1)' \
            >/dev/null 2>&1 || return 1
        command -v "$p"
    }

    local found cand
    local -a names=(python3.13 python3.12 python3.11 python3.10 python3.9 python3.8 python3 python)
    local seen="|"   # interpreters already listed (bash 3.2: no associative arrays)
    for cand in "${names[@]+"${names[@]}"}"; do
        if found="$(_hf_try "$cand")"; then
            [[ "$seen" == *"|$found|"* ]] && continue
            seen="$seen$found|"
            echo "$found"
        fi
    done

    if command -v module >/dev/null 2>&1; then
        module load python >/dev/null 2>&1 || true
        for cand in "${names[@]+"${names[@]}"}"; do
            if found="$(_hf_try "$cand")"; then
                [[ "$seen" == *"|$found|"* ]] && continue
                seen="$seen$found|"
                echo "$found"
            fi
        done
    fi
}

# Creates the venv at $HF_ENV_DIR if absent, trying each interpreter until one
# yields pip, then installs huggingface_hub.
_hf_ensure_venv() {
    if [[ -x "$HF_ENV_DIR/bin/python" && -x "$HF_ENV_DIR/bin/huggingface-cli" ]]; then
        return 0
    fi
    if [[ -x "$HF_ENV_DIR/bin/python" ]]; then
        _hf_log "venv exists but huggingface-cli missing — reinstalling"
        if "$HF_ENV_DIR/bin/python" -m pip install --quiet "huggingface_hub[cli]" \
           && [[ -x "$HF_ENV_DIR/bin/huggingface-cli" ]]; then
            return 0
        fi
        _hf_warn "reinstall failed — recreating venv from scratch"
        rm -rf "$HF_ENV_DIR"
    fi

    local -a candidates=()
    local cand
    while IFS= read -r cand; do candidates+=("$cand"); done < <(_hf_find_python)
    if (( ${#candidates[@]} == 0 )); then
        _hf_err "no python>=3.8 found. Install python3.8+ or 'module load python' first."
        return 1
    fi

    mkdir -p "$(dirname "$HF_ENV_DIR")"
    local py
    for py in "${candidates[@]+"${candidates[@]}"}"; do
        _hf_log "trying interpreter: $py"
        rm -rf "$HF_ENV_DIR"
        if ! "$py" -m venv "$HF_ENV_DIR" >/dev/null 2>&1; then
            _hf_warn "  venv creation failed with $py"
            continue
        fi
        if [[ ! -x "$HF_ENV_DIR/bin/pip" && ! -x "$HF_ENV_DIR/bin/pip3" ]]; then
            "$HF_ENV_DIR/bin/python" -m ensurepip --upgrade >/dev/null 2>&1 || true
        fi
        if ! "$HF_ENV_DIR/bin/python" -m pip --version >/dev/null 2>&1; then
            _hf_warn "  pip unavailable in venv from $py"
            continue
        fi
        _hf_log "  ok — using $py"
        break
    done

    if [[ ! -x "$HF_ENV_DIR/bin/python" ]]; then
        _hf_err "could not create a working venv with any of: ${candidates[*]}"
        return 1
    fi

    _hf_log "installing huggingface_hub into venv"
    "$HF_ENV_DIR/bin/python" -m pip install --quiet --upgrade pip      || return 1
    "$HF_ENV_DIR/bin/python" -m pip install --quiet huggingface_hub    || return 1
    if [[ ! -x "$HF_ENV_DIR/bin/hf" && ! -x "$HF_ENV_DIR/bin/huggingface-cli" ]]; then
        _hf_err "neither 'hf' nor 'huggingface-cli' present after install"
        return 1
    fi
}

# Checks a token against the HF whoami endpoint (curl, else urllib).
# Returns 0 accepted, 1 rejected (401/403), 2 inconclusive (callers proceed).
_hf_validate_token() {
    local tok="$1"
    local url="https://huggingface.co/api/whoami-v2"
    local http_code=""

    if command -v curl >/dev/null 2>&1; then
        http_code=$(curl -s -o /dev/null -w '%{http_code}' \
            --max-time 10 \
            -H "Authorization: Bearer $tok" \
            "$url" 2>/dev/null) || http_code=""
    elif [[ -x "$HF_ENV_DIR/bin/python" ]]; then
        http_code=$("$HF_ENV_DIR/bin/python" - "$tok" "$url" 2>/dev/null <<'PYEOF'
import sys, urllib.request, urllib.error
tok, url = sys.argv[1], sys.argv[2]
req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
try:
    urllib.request.urlopen(req, timeout=10)
    print("200")
except urllib.error.HTTPError as e:
    print(str(e.code))
except Exception:
    print("error")
PYEOF
        ) || http_code=""
    fi

    if [[ -z "$http_code" || "$http_code" == "error" ]]; then
        _hf_warn "token validation: network check inconclusive — proceeding without validation"
        return 2
    fi

    case "$http_code" in
        200)     return 0 ;;
        401|403) return 1 ;;
        *)       _hf_warn "token validation: unexpected HTTP $http_code — proceeding"; return 2 ;;
    esac
}

# Prompts for a token (optional preamble $1) and saves it to $HF_TOKEN_FILE_PATH.
# Returns 0 saved, 2 skipped (Ctrl+C, 30 s timeout, empty input or no TTY).
_hf_prompt_token() {
    local preamble="${1:-}"

    if [[ "${HF_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
        _hf_warn "no HuggingFace token available and stdin is not a TTY -- skipping."
        _hf_warn "  to download later, rerun with --hf-token-file <path>"
        _hf_warn "  or export HUGGING_FACE_HUB_TOKEN before invoking."
        return 2
    fi

    printf '\n' >&2
    [[ -n "$preamble" ]] && printf '  %s\n\n' "$preamble" >&2

    printf '  A HuggingFace access token is required to download this model.\n' >&2
    printf '  Generate a new token (free, takes 30 sec) at:\n' >&2
    printf '    https://huggingface.co/settings/tokens\n' >&2
    printf '\n' >&2
    printf '  SECURITY NOTICE\n' >&2
    printf '  ──────────────────────────────────────────────────────────────────\n' >&2
    printf '  For your security, treat each token as single-use:\n' >&2
    printf '    1.  Generate a fresh token at https://huggingface.co/settings/tokens\n' >&2
    printf '    2.  Enter it below to complete this download.\n' >&2
    printf '    3.  After the download finishes, revoke it immediately at\n' >&2
    printf '        https://huggingface.co/settings/tokens\n' >&2
    printf '        A revoked token cannot be reused by anyone — even if it were\n' >&2
    printf '        intercepted, it would be worthless.\n' >&2
    printf '\n' >&2
    printf '  Your token is saved locally to:\n' >&2
    printf '    %s\n' "$HF_TOKEN_FILE_PATH" >&2
    printf '  It is stored with permissions 0600 (readable only by you), is listed\n' >&2
    printf '  in .gitignore, and NEVER leaves this machine. It is not transmitted\n' >&2
    printf '  to any pipeline server or third party. If you revoke it and need to\n' >&2
    printf '  run this step again, you will be prompted for a new token automatically.\n' >&2
    printf '  ──────────────────────────────────────────────────────────────────\n' >&2
    printf '\n' >&2
    printf '  To SKIP for now: press Ctrl+C, or wait 30 seconds without typing.\n' >&2
    printf '  You can download this model later by re-running the same command.\n\n' >&2

    local tok="" rc=0
    # A local INT trap lets Ctrl+C end the prompt without killing the set -e caller.
    trap 'rc=130' INT
    read -rsp "  HuggingFace token (Ctrl+C or wait 30s to skip): " -t 30 tok || rc=$?
    trap - INT
    echo >&2

    if (( rc == 130 )); then
        _hf_warn "skipped by user (Ctrl+C). Model NOT downloaded."
        _hf_warn "  to download later: ./setup.sh --databases-only --tool llm"
        return 2
    fi
    if (( rc != 0 )); then
        _hf_warn "no input within 30 seconds — skipping. Model NOT downloaded."
        _hf_warn "  to download later: ./setup.sh --databases-only --tool llm"
        return 2
    fi
    if [[ -z "$tok" ]]; then
        _hf_warn "empty token entered — skipping. Model NOT downloaded."
        _hf_warn "  to download later: ./setup.sh --databases-only --tool llm"
        return 2
    fi

    umask 077
    mkdir -p "$(dirname "$HF_TOKEN_FILE_PATH")"
    printf '%s\n' "$tok" > "$HF_TOKEN_FILE_PATH"
    chmod 600 "$HF_TOKEN_FILE_PATH" 2>/dev/null || true
    unset tok
    return 0
}

# Loads the token (file, env, cache, then prompt), validates it, re-prompts once
# if rejected, and exports HUGGING_FACE_HUB_TOKEN.
# Returns 0 ready, 2 skipped (callers continue), 1 hard error.
_hf_ensure_token() {
    local src=""

    if [[ "${HF_RESET:-0}" == "1" ]]; then
        rm -f "$HF_TOKEN_FILE_PATH"
    fi

    # 1. caller-supplied file
    if [[ -n "${HF_TOKEN_FILE:-}" ]]; then
        [[ -r "$HF_TOKEN_FILE" ]] || { _hf_err "HF_TOKEN_FILE not readable: $HF_TOKEN_FILE"; return 1; }
        install -m 600 "$HF_TOKEN_FILE" "$HF_TOKEN_FILE_PATH"
        src="file:$HF_TOKEN_FILE"
    fi

    # 2. environment override
    if [[ -z "$src" && -n "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
        umask 077
        printf '%s\n' "$HUGGING_FACE_HUB_TOKEN" > "$HF_TOKEN_FILE_PATH"
        src="env:HUGGING_FACE_HUB_TOKEN"
    fi

    # 3. already cached on disk
    if [[ -z "$src" && -s "$HF_TOKEN_FILE_PATH" ]]; then
        src="cache"
    fi

    # 4. interactive prompt (first time or after cache miss)
    if [[ -z "$src" ]]; then
        _hf_prompt_token "" || return $?   # 2 = skipped
        src="prompt"
    fi

    # ── load ──
    chmod 600 "$HF_TOKEN_FILE_PATH" 2>/dev/null || true
    HUGGING_FACE_HUB_TOKEN="$(<"$HF_TOKEN_FILE_PATH")"
    HUGGING_FACE_HUB_TOKEN="${HUGGING_FACE_HUB_TOKEN%$'\n'}"

    # ── validate ──
    local _val_rc=0
    _hf_validate_token "$HUGGING_FACE_HUB_TOKEN" || _val_rc=$?

    if (( _val_rc == 1 )); then
        _hf_warn "The HuggingFace token (source: $src) was rejected by HuggingFace."
        _hf_warn "It may have been revoked. Clearing the cached token."

        rm -f "$HF_TOKEN_FILE_PATH"
        unset HUGGING_FACE_HUB_TOKEN HF_TOKEN 2>/dev/null || true

        if [[ "${HF_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
            _hf_err "Cannot re-prompt in non-interactive mode. Provide a valid token via"
            _hf_err "  --hf-token-file <path>  or  export HUGGING_FACE_HUB_TOKEN=<token>"
            return 1
        fi

        # Re-prompt once with an explanatory preamble.
        _hf_prompt_token \
            "The previously stored token was rejected by HuggingFace (revoked or expired)." \
            || return $?   # 2 = skipped
        src="reprompt"

        # Load and re-validate the freshly entered token.
        chmod 600 "$HF_TOKEN_FILE_PATH" 2>/dev/null || true
        HUGGING_FACE_HUB_TOKEN="$(<"$HF_TOKEN_FILE_PATH")"
        HUGGING_FACE_HUB_TOKEN="${HUGGING_FACE_HUB_TOKEN%$'\n'}"

        local _val2_rc=0
        _hf_validate_token "$HUGGING_FACE_HUB_TOKEN" || _val2_rc=$?
        if (( _val2_rc == 1 )); then
            rm -f "$HF_TOKEN_FILE_PATH"
            _hf_err "The new token was also rejected by HuggingFace."
            _hf_err "Please verify the token is valid and has not been revoked:"
            _hf_err "  https://huggingface.co/settings/tokens"
            return 1
        fi
        # An inconclusive check (2) proceeds; the download surfaces any real error.
    fi

    export HUGGING_FACE_HUB_TOKEN
    export HF_TOKEN="$HUGGING_FACE_HUB_TOKEN"   # alias used by newer hf-hub
    _hf_log "HF token loaded ($src)"
}

# ---- model discovery --------------------------------------------------------

# Curated LLMs for the llm scoring stage, as "<repo_id>|<gated:yes|no>|<notes>".
# Gated models need their terms accepted on huggingface.co before download.
_HF_CURATED_MODELS=(
    # ── general-purpose ──
    # repo_id | gated | short description
    "meta-llama/Meta-Llama-3-8B|yes|Meta LLaMA 3 8B — strong baseline; requires Meta licence approval"
    "meta-llama/Meta-Llama-3-8B-Instruct|yes|Meta LLaMA 3 8B Instruct — instruction-tuned; requires Meta licence approval"
    "meta-llama/Meta-Llama-3-70B|yes|Meta LLaMA 3 70B — high-capacity; requires Meta licence approval"
    "mistralai/Mistral-7B-v0.3|no|Mistral 7B v0.3 — open weights, Apache-2.0"
    "mistralai/Mistral-7B-Instruct-v0.3|no|Mistral 7B Instruct v0.3 — open weights, Apache-2.0"
    "mistralai/Mixtral-8x7B-v0.1|no|Mixtral 8x7B MoE — open weights, Apache-2.0"
    "google/gemma-2-9b|yes|Google Gemma 2 9B — requires Google terms acceptance"
    "google/gemma-2-27b|yes|Google Gemma 2 27B — requires Google terms acceptance"
    "microsoft/Phi-3-mini-4k-instruct|no|Microsoft Phi-3 Mini — compact, MIT licence"
    "microsoft/Phi-3-medium-4k-instruct|no|Microsoft Phi-3 Medium — MIT licence"
    "Qwen/Qwen2.5-7B-Instruct|no|Qwen 2.5 7B Instruct — open weights, Apache-2.0"
    "Qwen/Qwen2.5-14B-Instruct|no|Qwen 2.5 14B Instruct — open weights, Apache-2.0"
    # ── biology-focused ──
    "BioMistral/BioMistral-7B|no|BioMistral 7B — biomedical fine-tune of Mistral, Apache-2.0"
    "allenai/Llama-3.1-Tulu-3-8B|no|Tulu 3 8B — RLVR instruction-tuned, open"
    "lmsys/vicuna-7b-v1.5|no|Vicuna 7B — open fine-tune, Llama Community Licence"
)

# Checks access to one HF repo via its metadata endpoint (gated repos give 403).
# Returns 0 accessible, 1 not approved, 2 inconclusive.
_hf_check_model_access() {
    local repo="$1" tok="$2"
    local url="https://huggingface.co/api/models/${repo}"
    local http_code=""

    if command -v curl >/dev/null 2>&1; then
        http_code=$(curl -s -o /dev/null -w '%{http_code}' \
            --max-time 10 \
            -H "Authorization: Bearer $tok" \
            "$url" 2>/dev/null) || http_code=""
    elif [[ -x "$HF_ENV_DIR/bin/python" ]]; then
        http_code=$("$HF_ENV_DIR/bin/python" - "$tok" "$url" 2>/dev/null <<'PYEOF'
import sys, urllib.request, urllib.error
tok, url = sys.argv[1], sys.argv[2]
req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
try:
    urllib.request.urlopen(req, timeout=10)
    print("200")
except urllib.error.HTTPError as e:
    print(str(e.code))
except Exception:
    print("error")
PYEOF
        ) || http_code=""
    fi

    case "${http_code:-error}" in
        200)         return 0 ;;
        401|403|404) return 1 ;;
        *)           return 2 ;;
    esac
}

# Prints the curated models with each one's access status (uses HUGGING_FACE_HUB_TOKEN).
hf_list_models() {
    local tok="${HUGGING_FACE_HUB_TOKEN:-}"

    printf '\n' >&2
    printf '  Checking access to curated models — please wait...\n' >&2
    printf '\n' >&2
    printf '  %-45s  %-7s  %s\n' "MODEL" "GATED" "ACCESS" >&2
    printf '  %s\n' "$(printf '─%.0s' {1..75})" >&2

    local row repo gated notes access_str access_url
    for row in "${_HF_CURATED_MODELS[@]+"${_HF_CURATED_MODELS[@]}"}"; do
        IFS='|' read -r repo gated notes <<< "$row"
        access_url="https://huggingface.co/${repo}"

        if [[ -z "$tok" ]]; then
            access_str="(no token)"
        else
            local _ac=0
            _hf_check_model_access "$repo" "$tok" || _ac=$?
            case $_ac in
                0) access_str="✓ approved / accessible" ;;
                1)
                    if [[ "$gated" == "yes" ]]; then
                        access_str="✗ approval needed  →  ${access_url}"
                    else
                        access_str="✗ not accessible (check token scopes)"
                    fi
                    ;;
                *) access_str="? network check inconclusive" ;;
            esac
        fi

        printf '  %-45s  %-7s  %s\n' "$repo" "$gated" "$access_str" >&2
        printf '      %s\n' "$notes" >&2
    done

    printf '  %s\n' "$(printf '─%.0s' {1..75})" >&2
    printf '\n' >&2
    printf '  For gated models marked "approval needed":\n' >&2
    printf '    1. Visit the model URL above and accept the terms on the model card.\n' >&2
    printf '    2. Approval is granted by the model owner (usually within seconds\n' >&2
    printf '       to a few hours for Meta / Google models).\n' >&2
    printf '    3. Once approved, set the model ID in pipeline.conf.sh:\n' >&2
    printf '         LLM_BASE_MODEL="<org>/<model>"\n' >&2
    printf '    4. Re-run: ./setup.sh --databases-only --tool llm\n' >&2
    printf '\n' >&2
}

# ---- public entry point -----------------------------------------------------

# Ensures venv and token, then puts the venv on PATH; passes through 2 on a skip.
hf_env_activate() {
    _hf_ensure_venv || return 1
    _hf_ensure_token
    local rc=$?
    (( rc != 0 )) && return $rc
    export PATH="$HF_ENV_DIR/bin:$PATH"
    export HF_HUB_DISABLE_TELEMETRY=1
    return 0
}

# hf_download <repo_id> <local_dir> -- downloads a repo with `hf`, else
# `huggingface-cli`, else huggingface_hub.snapshot_download.
hf_download() {
    local repo="$1" dest="$2"
    mkdir -p "$dest"
    if command -v hf >/dev/null 2>&1; then
        hf download "$repo" --local-dir "$dest"
    elif command -v huggingface-cli >/dev/null 2>&1 \
         && huggingface-cli --help 2>/dev/null | grep -q '^\s*download'; then
        huggingface-cli download "$repo" --local-dir "$dest"
    else
        "$HF_ENV_DIR/bin/python" - "$repo" "$dest" <<'PYEOF'
import sys
from huggingface_hub import snapshot_download
snapshot_download(sys.argv[1], local_dir=sys.argv[2])
PYEOF
    fi
}
