#!/usr/bin/env bash
# One-time setup: install the `margie` command and put it on your PATH.
# Run from the repo root after cloning:  ./scripts/setup-frontend.sh
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"     # the margie-fe repo root
BIN="$HOME/bin"
mkdir -p "$BIN"

chmod +x "$REPO/scripts/margie.sh"
cat > "$BIN/margie" <<EOF
#!/usr/bin/env bash
exec "$REPO/scripts/margie.sh" "\$@"
EOF
chmod +x "$BIN/margie"
echo "Installed 'margie' -> $REPO/scripts/margie.sh"

# add ~/bin to PATH in the right profile for your shell, if it isn't already there
case "${SHELL:-}" in
    */zsh)  PROFILE="$HOME/.zshrc" ;;
    */bash) PROFILE="$HOME/.bash_profile" ;;
    *)      PROFILE="$HOME/.profile" ;;
esac
LINE='export PATH="$HOME/bin:$PATH"'
if ! grep -qF "$LINE" "$PROFILE" 2>/dev/null; then
    echo "$LINE" >> "$PROFILE"
    echo "Added ~/bin to PATH in $PROFILE"
fi

echo "Done. Open a new terminal (or: source $PROFILE), then run:  margie"
