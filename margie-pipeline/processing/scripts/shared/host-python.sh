# shellcheck shell=bash
# host-python.sh — finds or creates the Python that runs processing/host-scripts/.
# Sourced after pipeline.conf.sh.
#
#   host_python   prints the interpreter, creating it on first use
#
# Resolution, first that works:
#   1. $MARGIE_PYTHON, if it can import
#      the packages in processing/host-scripts/requirements.txt
#   2. the venv at $HOST_ENV_DIR (default processing/.host-env)
#   3. a new venv there, from the newest Python >= 3.11 found (on a cluster,
#      after `module load python` if none is on PATH), with the requirements
#      installed; needs network access once
# bash 3.2 safe.

: "${HOST_ENV_DIR:=$REPO_ROOT/processing/.host-env}"
HOST_REQUIREMENTS="$REPO_ROOT/processing/host-scripts/requirements.txt"

# Succeeds when the interpreter is Python 3.11+ with the host packages.
_host_py_ok() {
    "$1" -c 'import sys
if sys.version_info < (3, 11): sys.exit(1)
import numpy, pandas, scipy, matplotlib, openpyxl' >/dev/null 2>&1
}

# Prints every Python 3.11+ on PATH, newest first.
_host_py_candidates() {
    local n
    for n in python3.13 python3.12 python3.11 python3 python; do
        command -v "$n" >/dev/null 2>&1 || continue
        "$n" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1 \
            && command -v "$n"
    done
}

# Prints a working host interpreter, building the venv under a mkdir lock if needed.
host_python() {
    if [[ -n "${MARGIE_PYTHON:-}" ]]; then
        if _host_py_ok "$MARGIE_PYTHON"; then echo "$MARGIE_PYTHON"; return 0; fi
        echo "[host-python] ERROR: MARGIE_PYTHON=$MARGIE_PYTHON is not Python 3.11+ with $(tr '\n' ' ' < "$HOST_REQUIREMENTS")" >&2
        return 1
    fi
    local py="$HOST_ENV_DIR/bin/python"
    if [[ -x "$py" ]] && _host_py_ok "$py"; then echo "$py"; return 0; fi

    # One creator at a time (parallel genomes on a cluster share the venv).
    local lock="$HOST_ENV_DIR.lock" waited=0
    mkdir -p "$(dirname "$HOST_ENV_DIR")"
    until mkdir "$lock" 2>/dev/null; do
        (( waited++ > 900 )) && { echo "[host-python] ERROR: stale lock $lock" >&2; return 1; }
        sleep 1
    done
    if [[ -x "$py" ]] && _host_py_ok "$py"; then rmdir "$lock"; echo "$py"; return 0; fi

    local cands base
    cands="$(_host_py_candidates)"
    if [[ -z "$cands" ]] && command -v module >/dev/null 2>&1; then
        module load python >/dev/null 2>&1 || true
        cands="$(_host_py_candidates)"
    fi
    if [[ -z "$cands" ]]; then
        rmdir "$lock"
        echo "[host-python] ERROR: no Python 3.11 or newer found; install one, or set MARGIE_PYTHON" >&2
        return 1
    fi
    for base in $cands; do
        echo "[host-python] creating $HOST_ENV_DIR from $base ($($base -V 2>&1))" >&2
        rm -rf "$HOST_ENV_DIR"
        if "$base" -m venv "$HOST_ENV_DIR" >&2 \
           && "$py" -m pip install --quiet --upgrade pip >&2 \
           && "$py" -m pip install --quiet -r "$HOST_REQUIREMENTS" >&2 \
           && _host_py_ok "$py"; then
            rmdir "$lock"
            echo "$py"
            return 0
        fi
        echo "[host-python] WARN: could not set up the environment with $base" >&2
    done
    rm -rf "$HOST_ENV_DIR"
    rmdir "$lock"
    echo "[host-python] ERROR: could not create $HOST_ENV_DIR (the first run needs network access to install $(tr '\n' ' ' < "$HOST_REQUIREMENTS"))" >&2
    return 1
}
