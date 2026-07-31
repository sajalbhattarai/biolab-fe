#!/usr/bin/env bash
#
# margie — start the MARGIE backend on the HPC, tunnel to it, and run the front-end.
#
# Settings (HPC_HOST, BACKEND_DIR) are baked into ~/bin/margie by setup.sh —
# edit them at the top of that file if your backend location changes.
#   margie          start everything
#   margie --sync   also pull the latest front-end from the HPC first (dev only; optional)
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# HPC_HOST and BACKEND_DIR are set by the installed launcher (~/bin/margie);
# edit them there if your backend location on the HPC changes.
: "${HPC_HOST:?not set — run ./setup.sh (or set HPC_HOST at the top of ~/bin/margie)}"
: "${BACKEND_DIR:?not set — run ./setup.sh (or set BACKEND_DIR at the top of ~/bin/margie)}"
SYNC="no"; [ "${1:-}" = "--sync" ] && SYNC="yes"

FRONTEND_URL="http://localhost:5173"
API_URL="http://localhost:8000"
VITE_LOG="/tmp/margie-vite.log"
REMOTE_LOG="/tmp/margie-dane-api.log"
SOCKET="/tmp/margie-$HPC_HOST-$USER.sock"

line()    { printf '  '; printf '%.0s─' {1..56}; printf '\n'; }
section() { echo; line; printf '  %s\n' "$1"; line; }
row()     { printf '  %-20s %s\n' "$1" "$2"; }

cleanup() {
  [ -n "${FE_PID:-}" ]  && kill "$FE_PID"  2>/dev/null
  [ -n "${TUN_PID:-}" ] && kill "$TUN_PID" 2>/dev/null
  [ -n "${BE_PID:-}" ]  && ssh -S "$SOCKET" "$HPC_HOST" "kill $BE_PID 2>/dev/null" 2>/dev/null
  ssh -S "$SOCKET" -O exit "$HPC_HOST" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

section "MARGIE"
row "HPC host"  "$HPC_HOST"
row "Front-end" "$REPO"

# free local ports left over from a previous run (local processes only)
for p in 5173 8000; do lsof -ti tcp:$p 2>/dev/null | xargs kill 2>/dev/null; done

# optional, dev only: pull the latest front-end from the HPC — never fatal
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

section "Backend (on the HPC)"
rm -f "$SOCKET"
ssh -M -S "$SOCKET" -fN "$HPC_HOST"
NODE="$(ssh -S "$SOCKET" "$HPC_HOST" hostname 2>/dev/null)"
row "node" "$NODE"
BE_PID="$(ssh -S "$SOCKET" "$HPC_HOST" "
  cd '$BACKEND_DIR' || exit 1
  export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"
  uv sync >/dev/null 2>&1
  source .venv/bin/activate
  nohup dane-api > $REMOTE_LOG 2>&1 & echo \$!
" | tail -1)"
row "dane-api pid" "$BE_PID"
printf '  waiting for backend'
for i in $(seq 1 60); do
  ssh -S "$SOCKET" "$HPC_HOST" "curl -fsS http://localhost:8000 >/dev/null 2>&1" && { printf ' ready\n'; break; }
  printf '.'; sleep 1
done

section "Tunnel"
ssh -S "$SOCKET" -o ExitOnForwardFailure=yes -N -L 8000:localhost:8000 "$HPC_HOST" &
TUN_PID=$!
for i in $(seq 1 30); do curl -fsS "$API_URL" >/dev/null 2>&1 && break; sleep 1; done
row "API" "$API_URL"

section "Front-end"
cd "$REPO"
npm install >/dev/null 2>&1
npm run dev > "$VITE_LOG" 2>&1 &
FE_PID=$!
for i in $(seq 1 60); do grep -q "Local:" "$VITE_LOG" && break; sleep 1; done

section "MARGIE READY"
row "Front-end"   "$FRONTEND_URL"
row "Backend API" "$API_URL"
row "HPC node"    "$NODE"
echo
open "$FRONTEND_URL" 2>/dev/null || true
wait "$FE_PID"
