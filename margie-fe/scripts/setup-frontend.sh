#!/usr/bin/env bash
# Set up the `margie` command. Run from the repo folder:  ./scripts/setup-frontend.sh
# Re-run any time — it keeps your saved settings. To change where your backend lives,
# edit the two lines at the top of ~/bin/margie.
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
    # first run — ask once. Enter keeps a shown default; typing replaces it.
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
    echo "Point margie at your HPC (you need a cluster account and the backend cloned there):"
    ask "HPC SSH host/alias (e.g. from ~/.ssh/config)" HPC_HOST
    ask "Path to bioinformatics-tools on the HPC"       BACKEND_DIR
    # confirm the backend is really there (also checks your cluster access)
    echo "  checking $HPC_HOST:$BACKEND_DIR ..."
    if ssh -o ConnectTimeout=15 "$HPC_HOST" "test -d '$BACKEND_DIR'" 2>/dev/null; then
        echo "  ok — backend found on the HPC"
    else
        echo "  ! couldn't confirm — make sure you can SSH to '$HPC_HOST' and cloned the backend at '$BACKEND_DIR'"
    fi
fi

# write the launcher with your settings baked in (this file lives only on your machine)
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

echo
echo "Done. Open a new terminal (or: source $PROFILE), then run:  margie"
