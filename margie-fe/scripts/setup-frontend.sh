#!/usr/bin/env bash
# One-time setup: install the `margie` command, create its config, and add it to PATH.
# Run from the repo folder:  ./scripts/setup-frontend.sh
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# install the launcher as `margie`
BIN="$HOME/bin"; mkdir -p "$BIN"
chmod +x "$REPO/scripts/margie.sh"
printf '#!/usr/bin/env bash\nexec "%s/scripts/margie.sh" "$@"\n' "$REPO" > "$BIN/margie"
chmod +x "$BIN/margie"
echo "Installed 'margie'"

# create the config (you fill it in)
CFG="$HOME/.config/margie"; mkdir -p "$CFG"
if [ ! -f "$CFG/config" ]; then
    cat > "$CFG/config" <<'EOF'
# margie settings — fill these in, then run: margie
HPC_HOST=                 # your HPC SSH host/alias (an entry in ~/.ssh/config)
BACKEND_DIR=              # path to bioinformatics-tools on the HPC
# HPC_FRONTEND_DIR=       # path to margie-fe on the HPC — only for: margie --sync (dev)
EOF
    echo "Created $CFG/config — edit it before your first run"
fi

# put ~/bin on PATH for your shell
case "${SHELL:-}" in
    */zsh)  PROFILE="$HOME/.zshrc" ;;
    */bash) PROFILE="$HOME/.bash_profile" ;;
    *)      PROFILE="$HOME/.profile" ;;
esac
LINE='export PATH="$HOME/bin:$PATH"'
grep -qF "$LINE" "$PROFILE" 2>/dev/null || echo "$LINE" >> "$PROFILE"

echo "Done. Edit ~/.config/margie/config, open a new terminal, then run:  margie"
