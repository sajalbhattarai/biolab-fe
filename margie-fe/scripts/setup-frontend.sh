#!/usr/bin/env bash
# One-time setup: install `margie`, ask for your HPC details, and add it to PATH.
# Run from the repo folder:  ./scripts/setup-frontend.sh
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# install the launcher as `margie`
BIN="$HOME/bin"; mkdir -p "$BIN"
chmod +x "$REPO/scripts/margie.sh"
printf '#!/usr/bin/env bash\nexec "%s/scripts/margie.sh" "$@"\n' "$REPO" > "$BIN/margie"
chmod +x "$BIN/margie"
echo "Installed 'margie'."

# ask for your HPC details — nothing is hardcoded
echo
echo "Point margie at your HPC (you need a cluster account and the backend cloned there):"
HPC_HOST=""; BACKEND_DIR=""
while [ -z "$HPC_HOST" ];    do printf "  HPC SSH host/alias (e.g. from ~/.ssh/config): "; read -r HPC_HOST; done
while [ -z "$BACKEND_DIR" ]; do printf "  Path to bioinformatics-tools on the HPC: ";      read -r BACKEND_DIR; done

# confirm the backend is really there (this also checks your cluster access)
echo "  checking $HPC_HOST:$BACKEND_DIR ..."
if ssh -o ConnectTimeout=15 "$HPC_HOST" "test -d '$BACKEND_DIR'" 2>/dev/null; then
    echo "  ok — backend found on the HPC"
else
    echo "  ! couldn't confirm it — make sure you can SSH to '$HPC_HOST' and have cloned the backend at '$BACKEND_DIR'"
fi

# save your settings (on your machine only — never committed)
CFG="$HOME/.config/margie"; mkdir -p "$CFG"
cat > "$CFG/config" <<EOF
# margie settings (written by setup-frontend.sh)
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
