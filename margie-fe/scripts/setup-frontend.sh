#!/usr/bin/env bash
# First-time setup for the MARGIE front-end.
#
# All it does: remember your HPC host + backend path (for next time), install the
# `margie` command, then open the app so you can register and connect once. That
# first connection is what links your workstation to the backend — nothing is
# started on the HPC here.
#
# After this, just run:  margie   (that one starts the backend on the HPC for you).
# Run from the repo folder:  ./scripts/setup-frontend.sh
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$HOME/bin"; MARGIE="$BIN/margie"; mkdir -p "$BIN"
chmod +x "$REPO/scripts/margie.sh"

# reuse whatever your installed launcher already points at, so we don't ask again
HPC_HOST=""; BACKEND_DIR=""
if [ -f "$MARGIE" ]; then
    HPC_HOST="$(sed -n 's/^export HPC_HOST="\(.*\)"$/\1/p' "$MARGIE")"
    BACKEND_DIR="$(sed -n 's/^export BACKEND_DIR="\(.*\)"$/\1/p' "$MARGIE")"
fi

if [ -n "$HPC_HOST" ] && [ -n "$BACKEND_DIR" ]; then
    echo "Using your saved settings:  $HPC_HOST : $BACKEND_DIR"
    echo "(to change them later, edit the top of $MARGIE)"
else
    # first run — just note these two things down; nothing connects yet.
    ask() {
        local prompt="$1" var="$2" cur inp=""
        cur="${!var:-}"
        while :; do
            if [ -n "$cur" ]; then printf "  %s [%s]: " "$prompt" "$cur"
            else                   printf "  %s: " "$prompt"; fi
            if ! read -r inp; then printf -v "$var" '%s' "$cur"; return; fi
            inp="${inp:-$cur}"
            if [ -n "$inp" ]; then printf -v "$var" '%s' "$inp"; return; fi
            echo "  (required — please enter a value)"
        done
    }
    echo "Two quick things (saved for next time — nothing connects yet):"
    ask "HPC SSH host/alias (e.g. from ~/.ssh/config)" HPC_HOST
    ask "Path to bioinformatics-tools on the HPC"       BACKEND_DIR
fi

# save your settings into the installed launcher (this file lives only on your machine)
cat > "$MARGIE" <<EOF
#!/usr/bin/env bash
# margie launcher — EDIT THESE if your backend location on the HPC changes:
export HPC_HOST="$HPC_HOST"
export BACKEND_DIR="$BACKEND_DIR"
# export HPC_FRONTEND_DIR=""   # path to margie-fe on the HPC — only for: margie --sync (dev)
exec "$REPO/scripts/margie.sh" "\$@"
EOF
chmod +x "$MARGIE"
echo "Installed $MARGIE"

# put ~/bin on PATH for your shell
case "${SHELL:-}" in
    */zsh)  PROFILE="$HOME/.zshrc" ;;
    */bash) PROFILE="$HOME/.bash_profile" ;;
    *)      PROFILE="$HOME/.profile" ;;
esac
LINE='export PATH="$HOME/bin:$PATH"'
grep -qF "$LINE" "$PROFILE" 2>/dev/null || echo "$LINE" >> "$PROFILE"

# open the app so you can register + connect for the very first time
echo
echo "Opening the app — register there to link your workstation to the backend."
echo "Next time, in a new terminal, just run:  margie"
echo
cd "$REPO"
VITE_LOG="/tmp/margie-vite.log"
npm install >/dev/null 2>&1
npm run dev > "$VITE_LOG" 2>&1 &
FE_PID=$!
for i in $(seq 1 60); do grep -q "Local:" "$VITE_LOG" && break; sleep 1; done
open "http://localhost:5173" 2>/dev/null || xdg-open "http://localhost:5173" 2>/dev/null || true
echo "App running at http://localhost:5173   (press Ctrl-C here when you're done)"
wait "$FE_PID"
