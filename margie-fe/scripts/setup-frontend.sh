#!/bin/zsh
# One-time setup: install the `margie` command and put it on your PATH.
# Run from the repo root after cloning:  ./scripts/setup-frontend.sh
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"     # the margie-fe repo root
BIN="$HOME/bin"
mkdir -p "$BIN"

chmod +x "$REPO/scripts/margie.sh"
cat > "$BIN/margie" <<EOF
#!/bin/zsh
exec "$REPO/scripts/margie.sh" "\$@"
EOF
chmod +x "$BIN/margie"
echo "Installed 'margie' -> $REPO/scripts/margie.sh"

# add ~/bin to PATH in your shell profile if it isn't already there
LINE='export PATH="$HOME/bin:$PATH"'
if ! grep -qF "$LINE" "$HOME/.zshrc" 2>/dev/null; then
    echo "$LINE" >> "$HOME/.zshrc"
    echo "Added ~/bin to PATH in ~/.zshrc"
fi

echo "Done. Open a new terminal (or: source ~/.zshrc), then run:  margie"
