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
# Your HPC settings.
# OPTIONAL: fill these in to skip the questions below.
#   HPC_USER     your HPC username        (e.g. jdoe)
#   HPC_ADDR     your HPC address         (e.g. cluster.university.edu)
#   BACKEND_DIR  full path to the bioinformatics-tools folder on the HPC
#                (the folder that contains pyproject.toml)
# ---------------------------------------------------------------------------
HPC_USER=""
HPC_ADDR=""
BACKEND_DIR=""

# Reuse whatever a previous run saved in ~/bin/margie (unless set above).
if [ -f "$MARGIE" ]; then
    _saved_host="$(sed -n 's/^export HPC_HOST="\(.*\)"$/\1/p' "$MARGIE")"
    [ -z "$BACKEND_DIR" ] && BACKEND_DIR="$(sed -n 's/^export BACKEND_DIR="\(.*\)"$/\1/p' "$MARGIE")"
    case "$_saved_host" in
        *@*) [ -z "$HPC_USER" ] && HPC_USER="${_saved_host%@*}"
             [ -z "$HPC_ADDR" ] && HPC_ADDR="${_saved_host#*@}" ;;
        ?*)  [ -z "$HPC_ADDR" ] && HPC_ADDR="$_saved_host" ;;
    esac
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
if [ -n "$HPC_USER" ] && [ -n "$HPC_ADDR" ] && [ -n "$BACKEND_DIR" ]; then
    echo "Using your saved settings:  $HPC_USER@$HPC_ADDR : $BACKEND_DIR"
    echo "(to change them later, edit the top of $MARGIE)"
else
    echo "A few things about your HPC (saved so you're never asked again):"
    echo
    prompt_for "Your HPC username, e.g. jdoe (may differ from your computer's username)" HPC_USER
    prompt_for "Your HPC address, e.g. cluster.university.edu" HPC_ADDR
    prompt_for "Full path to the bioinformatics-tools folder on the HPC (contains pyproject.toml)" BACKEND_DIR
fi

# margie.sh logs in as user@host.
HPC_HOST="$HPC_USER@$HPC_ADDR"

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
