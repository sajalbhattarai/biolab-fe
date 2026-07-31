#!/usr/bin/env bash
# First-time setup for the MARGIE front-end.
#
# It remembers your HPC host + backend path, installs the `margie` command, then
# hands off to `margie` to start everything (backend on the HPC + tunnel + app)
# so you can register and connect the first time. Registration talks to the
# backend, so the backend has to be up — that is why this launches the full stack.
#
# From then on, just run:  margie
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
    echo "Two quick things (saved so you're never asked again):"
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

# hand off to margie: start backend on the HPC + tunnel + app, so you can register.
# (all the backend/login-node work lives in margie — setup adds none of its own.)
echo
echo "Starting MARGIE so you can register — this is exactly what 'margie' does every time."
echo "In future, just open a new terminal and run:  margie"
echo
exec "$MARGIE"
