#!/usr/bin/env bash
#
# margie — start the backend on the HPC, tunnel to it, and open the front-end.
#   margie          start everything
#   margie --sync   pull the latest front-end from the HPC first (dev only)
#
set -u

# ---------------------------------------------------------------------------
# Settings (baked into ~/bin/margie by setup.sh)
# ---------------------------------------------------------------------------
REPO="$(cd "$(dirname "$0")/.." && pwd)"

: "${HPC_HOST:?not set — run ./setup.sh (or set HPC_HOST at the top of ~/bin/margie)}"
: "${BACKEND_DIR:?not set — run ./setup.sh (or set BACKEND_DIR at the top of ~/bin/margie)}"

SYNC="no"
if [ "${1:-}" = "--sync" ]; then
    SYNC="yes"
fi

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
FRONTEND_URL="http://localhost:5173"
API_URL="http://localhost:8000"
# Per-user log paths so a leftover file owned by someone else can't block us
# ($TMPDIR is private per-user on macOS; falls back to /tmp elsewhere).
VITE_LOG="${TMPDIR:-/tmp}/margie-vite-$USER.log"
REMOTE_LOG="/tmp/margie-dane-api-$USER.log"
SOCKET="/tmp/margie-$HPC_HOST-$USER.sock"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
line() {
    printf '  '
    printf '%.0s─' {1..56}
    printf '\n'
}

section() {
    echo
    line
    printf '  %s\n' "$1"
    line
}

row() {
    printf '  %-20s %s\n' "$1" "$2"
}

# ---------------------------------------------------------------------------
# Shut everything down cleanly on exit
# ---------------------------------------------------------------------------
cleanup() {
    [ -n "${FE_PID:-}" ]  && kill "$FE_PID"  2>/dev/null
    [ -n "${TUN_PID:-}" ] && kill "$TUN_PID" 2>/dev/null
    [ -n "${BE_PID:-}" ]  && ssh -S "$SOCKET" -o BatchMode=yes "$HPC_HOST" "kill $BE_PID 2>/dev/null" 2>/dev/null
    ssh -S "$SOCKET" -O exit "$HPC_HOST" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

section "MARGIE"
row "HPC host"  "$HPC_HOST"
row "Front-end" "$REPO"

# ---------------------------------------------------------------------------
# Free local ports left over from a previous run
# ---------------------------------------------------------------------------
for port in 5173 8000; do
    lsof -ti "tcp:$port" 2>/dev/null | xargs kill 2>/dev/null
done

# ---------------------------------------------------------------------------
# Optional: pull the latest front-end from the HPC (dev only, never fatal)
# ---------------------------------------------------------------------------
if [ "$SYNC" = "yes" ]; then
    section "Sync front-end from HPC (optional)"
    if [ -n "${HPC_FRONTEND_DIR:-}" ] && rsync -az \
            --exclude .env --exclude node_modules --exclude .svelte-kit \
            --exclude .vite --exclude dist --exclude build --exclude .git \
            "$HPC_HOST:$HPC_FRONTEND_DIR/" "$REPO/"; then
        row "sync" "done"
    else
        row "sync" "skipped — continuing with your local copy"
    fi
fi

echo "VITE_PUBLIC_API_URL=$API_URL" > "$REPO/.env"

# ---------------------------------------------------------------------------
# Start the backend on the HPC (uv sync -> activate -> dane-api)
# ---------------------------------------------------------------------------
section "Backend (on the HPC)"
rm -f "$SOCKET"
# One authenticated master connection; everything below reuses it. If this
# fails, stop immediately instead of re-prompting for every later SSH call.
if ! ssh -M -S "$SOCKET" -o ConnectTimeout=15 -fN "$HPC_HOST"; then
    echo
    echo "  Could not connect to '$HPC_HOST'."
    echo "  Check it is <your-hpc-username>@<your-hpc-address> and that you can SSH in,"
    echo "  then fix the top of ~/bin/margie (or re-run setup) and try again."
    exit 1
fi

NODE="$(ssh -S "$SOCKET" "$HPC_HOST" hostname 2>/dev/null)"
row "node" "$NODE"

# Prepare the environment on the HPC -- errors are shown (not hidden), so a wrong
# BACKEND_DIR or a uv failure is obvious instead of a silent missing venv.
if ! ssh -S "$SOCKET" "$HPC_HOST" "
    cd '$BACKEND_DIR' 2>/dev/null || { echo '  BACKEND_DIR not found on the HPC: $BACKEND_DIR' >&2; exit 3; }
    [ -f pyproject.toml ] || { echo '  No pyproject.toml in $BACKEND_DIR -- point BACKEND_DIR at the bioinformatics-tools folder itself.' >&2; exit 4; }
    export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"
    command -v uv >/dev/null 2>&1 || { echo '  uv is not installed on the HPC (or not on PATH).' >&2; exit 5; }
    uv sync || { echo '  uv sync failed (see above).' >&2; exit 6; }
    if [ ! -f .env ]; then
        sk=\$(.venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(32))')
        ek=\$(.venv/bin/python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')
        printf 'BSP_SECRET_KEY=%s\\nBSP_ENCRYPTION_KEY=%s\\n' \"\$sk\" \"\$ek\" > .env
        chmod 600 .env
        echo '  created backend .env with fresh BSP_SECRET_KEY / BSP_ENCRYPTION_KEY'
    fi
"; then
    echo
    echo "  Backend could not be prepared on the HPC. Fix the above, then re-run."
    exit 1
fi

BE_PID="$(ssh -S "$SOCKET" "$HPC_HOST" "
    cd '$BACKEND_DIR' || exit 1
    export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"
    source .venv/bin/activate
    nohup dane-api > $REMOTE_LOG 2>&1 & echo \$!
" | tail -1)"
row "dane-api pid" "$BE_PID"

printf '  waiting for backend'
backend_ready="no"
for i in $(seq 1 60); do
    if ssh -S "$SOCKET" "$HPC_HOST" "curl -fsS http://localhost:8000 >/dev/null 2>&1"; then
        printf ' ready\n'
        backend_ready="yes"
        break
    fi
    printf '.'
    sleep 1
done
if [ "$backend_ready" != "yes" ]; then
    printf '\n'
    echo "  dane-api did not start. Last lines of its log:"
    ssh -S "$SOCKET" "$HPC_HOST" "tail -n 20 $REMOTE_LOG 2>/dev/null" | sed 's/^/    /'
    echo "  A common cause: the backend has no .env with BSP_SECRET_KEY / BSP_ENCRYPTION_KEY"
    echo "  (see the backend's README / docs/LOCAL_DEV.md)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Open the SSH tunnel (local :8000 -> backend :8000)
# ---------------------------------------------------------------------------
section "Tunnel"
ssh -S "$SOCKET" -o ExitOnForwardFailure=yes -N -L 8000:localhost:8000 "$HPC_HOST" &
TUN_PID=$!
for i in $(seq 1 30); do
    curl -fsS "$API_URL" >/dev/null 2>&1 && break
    sleep 1
done
row "API" "$API_URL"

# ---------------------------------------------------------------------------
# Start the front-end
# ---------------------------------------------------------------------------
section "Front-end"
cd "$REPO"
npm install >/dev/null 2>&1
npm run dev > "$VITE_LOG" 2>&1 &
FE_PID=$!
for i in $(seq 1 60); do
    grep -q "Local:" "$VITE_LOG" && break
    sleep 1
done

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
section "MARGIE READY"
row "Front-end"   "$FRONTEND_URL"
row "Backend API" "$API_URL"
row "HPC node"    "$NODE"
echo
open "$FRONTEND_URL" 2>/dev/null || xdg-open "$FRONTEND_URL" 2>/dev/null || true
wait "$FE_PID"
