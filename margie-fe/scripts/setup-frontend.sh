#!/usr/bin/env bash
# Set up (or update) `margie`. Safe to re-run any time — it shows your current
# HPC settings as defaults so you can change where the backend is cloned.
# Run from the repo folder:  ./scripts/setup-frontend.sh
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# install / refresh the launcher as `margie`
BIN="$HOME/bin"; mkdir -p "$BIN"
chmod +x "$REPO/scripts/margie.sh"
printf '#!/usr/bin/env bash\nexec "%s/scripts/margie.sh" "$@"\n' "$REPO" > "$BIN/margie"
chmod +x "$BIN/margie"
echo "Installed 'margie'."

# load current settings as defaults (re-running lets you UPDATE them; you can also
# edit ~/.config/margie/config first and just press Enter to keep those values)
CFG="$HOME/.config/margie"; mkdir -p "$CFG"
[ -f "$CFG/config" ] && . "$CFG/config"

# ask "<prompt>" <varname>: default = current value; Enter keeps it, else type a new one
ask() {
    local prompt="$1" var="$2" cur inp=""
    cur="${!var:-}"                      # (own line: indirect expansion needs var already set)
    while :; do
        if [ -n "$cur" ]; then printf "  %s [%s]: " "$prompt" "$cur"
        else                   printf "  %s: " "$prompt"; fi
        if ! read -r inp; then printf -v "$var" '%s' "$cur"; return; fi   # EOF -> keep current
        inp="${inp:-$cur}"
        if [ -n "$inp" ]; then printf -v "$var" '%s' "$inp"; return; fi
        echo "  (required — please enter a value)"
    done
}

echo
echo "Point margie at your HPC (you need a cluster account and the backend cloned there):"
ask "HPC SSH host/alias (e.g. from ~/.ssh/config)" HPC_HOST
ask "Path to bioinformatics-tools on the HPC"       BACKEND_DIR

# confirm the backend is really there (also checks your cluster access)
echo "  checking $HPC_HOST:$BACKEND_DIR ..."
if ssh -o ConnectTimeout=15 "$HPC_HOST" "test -d '$BACKEND_DIR'" 2>/dev/null; then
    echo "  ok — backend found on the HPC"
else
    echo "  ! couldn't confirm it — make sure you can SSH to '$HPC_HOST' and have cloned the backend at '$BACKEND_DIR'"
fi

# save (on your machine only — never committed)
cat > "$CFG/config" <<EOF
# margie settings (written by setup-frontend.sh; safe to edit by hand)
HPC_HOST=$HPC_HOST
BACKEND_DIR=$BACKEND_DIR
# HPC_FRONTEND_DIR=   # path to margie-fe on the HPC — only for: margie --sync (dev)
EOF
echo "Saved $CFG/config"

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
