#!/usr/bin/env bash
#
# MARGIE GUI — one-time setup. See the README for details.
#
set -e

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO="$(cd "$(dirname "$0")/margie-fe" && pwd)"
BIN="$HOME/bin"
MARGIE="$BIN/margie"

mkdir -p "$BIN"
chmod +x "$REPO/scripts/margie.sh"

# ---------------------------------------------------------------------------
# Load any settings that were saved on a previous run
# ---------------------------------------------------------------------------
HPC_HOST=""
BACKEND_DIR=""

if [ -f "$MARGIE" ]; then
    HPC_HOST="$(sed -n 's/^export HPC_HOST="\(.*\)"$/\1/p' "$MARGIE")"
    BACKEND_DIR="$(sed -n 's/^export BACKEND_DIR="\(.*\)"$/\1/p' "$MARGIE")"
fi

# ---------------------------------------------------------------------------
# Prompt helper: shows the current value as a default; Enter keeps it.
# ---------------------------------------------------------------------------
prompt_for() {
    local label="$1"
    local var="$2"
    local current="${!var:-}"
    local answer=""

    while true; do
        if [ -n "$current" ]; then
            printf "  %s [%s]: " "$label" "$current"
        else
            printf "  %s: " "$label"
        fi

        if ! read -r answer; then
            printf -v "$var" '%s' "$current"
            return
        fi

        answer="${answer:-$current}"

        if [ -n "$answer" ]; then
            printf -v "$var" '%s' "$answer"
            return
        fi

        echo "  (required — please enter a value)"
    done
}

# ---------------------------------------------------------------------------
# Ask for the host + backend path (only if we don't already have them)
# ---------------------------------------------------------------------------
if [ -n "$HPC_HOST" ] && [ -n "$BACKEND_DIR" ]; then
    echo "Using your saved settings:  $HPC_HOST : $BACKEND_DIR"
    echo "(to change them later, edit the top of $MARGIE)"
else
    echo "Two quick things (saved so you're never asked again):"
    prompt_for "HPC SSH host/alias (e.g. from ~/.ssh/config)" HPC_HOST
    prompt_for "Path to bioinformatics-tools on the HPC" BACKEND_DIR
fi

# ---------------------------------------------------------------------------
# Write the launcher (~/bin/margie) with the settings baked in
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Make sure ~/bin is on PATH for your shell
# ---------------------------------------------------------------------------
case "${SHELL:-}" in
    */zsh)
        PROFILE="$HOME/.zshrc"
        ;;
    */bash)
        PROFILE="$HOME/.bash_profile"
        ;;
    *)
        PROFILE="$HOME/.profile"
        ;;
esac

PATH_LINE='export PATH="$HOME/bin:$PATH"'

if ! grep -qF "$PATH_LINE" "$PROFILE" 2>/dev/null; then
    echo "$PATH_LINE" >> "$PROFILE"
fi

# ---------------------------------------------------------------------------
# Launch (starts backend + tunnel + app, so you can register)
# ---------------------------------------------------------------------------
echo
echo "Starting MARGIE so you can register — this is exactly what 'margie' does every time."
echo "In future, just open a new terminal and run:  margie"
echo

exec "$MARGIE"
