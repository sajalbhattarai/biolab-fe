#!/usr/bin/env bash
#
# MARGIE GUI — one-time setup. See the README for details.
#
set -e

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
DEPS="ask"
for arg in "$@"; do
    case "$arg" in
        --check)     DEPS="check" ;;
        --yes|-y)    DEPS="yes" ;;
        -h|--help)
            echo "usage: ./setup.sh [--check] [--yes]"
            echo "  --check      only report what is installed and what is missing"
            echo "  --yes        install anything missing without asking"
            exit 0 ;;
        *) echo "unknown option: $arg  (try --help)" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$ROOT/margie-fe"
BIN="$HOME/bin"
MARGIE="$BIN/margie"

# On Windows, a repo on /mnt/c works but is very slow and file watching is
# unreliable. Auto-relocate into Linux home so users can just run ./setup.sh.
IS_WSL="no"
if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL="yes"
fi

if [ "$IS_WSL" = "yes" ] && case "$ROOT" in /mnt/*) true ;; *) false ;; esac; then
    DEST="$HOME/$(basename "$ROOT")"

    echo
    echo "MARGIE detected a Windows-disk clone at: $ROOT"
    echo "It will continue from a Linux copy for speed and reliable reloads."

    if [ -f "$DEST/setup.sh" ]; then
        echo "Using existing Linux copy: $DEST"
    elif [ -e "$DEST" ]; then
        DEST="$HOME/$(basename "$ROOT")-wsl"
        echo "Linux destination already exists; using: $DEST"
        cp -a "$ROOT" "$DEST"
    else
        echo "Copying into Linux home: $DEST"
        cp -a "$ROOT" "$DEST"
    fi

    echo "Continuing setup in: $DEST"
    exec bash "$DEST/setup.sh" "$@"
fi

mkdir -p "$BIN"
chmod +x "$REPO/scripts/margie.sh" "$REPO/scripts/check-deps.sh"

# ---------------------------------------------------------------------------
# Does this computer have what MARGIE needs?
#
# Asked first, and asked out loud: a missing Node only shows up otherwise as a
# vite crash several minutes later, long after the HPC questions below.
# ---------------------------------------------------------------------------
if [ "$DEPS" = "check" ]; then
    exec "$REPO/scripts/check-deps.sh" --check
fi

DEP_ARGS=""
[ "$DEPS" = "yes" ] && DEP_ARGS="--yes"

if ! "$REPO/scripts/check-deps.sh" $DEP_ARGS; then
    echo
    echo "  Setup stops here — MARGIE cannot run until the pieces above are installed."
    exit 1
fi

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
PATH_LINE='export PATH="$HOME/bin:$PATH"'

# Every startup file the shell ALREADY has gets the line, rather than one file
# picked from $SHELL. Picking one was wrong on Ubuntu (so, on every Windows
# machine running this under WSL): $SHELL is /bin/bash but ~/.bash_profile does
# not exist there, and creating it makes login bash read that instead of
# ~/.profile -- which is the file that pulls in ~/.bashrc. Setup would have
# quietly cost the user their own shell setup to add one PATH entry.
case "${SHELL:-}" in
    */zsh)  CANDIDATES="$HOME/.zshrc $HOME/.zprofile" ;;
    */bash) CANDIDATES="$HOME/.profile $HOME/.bashrc $HOME/.bash_profile" ;;
    *)      CANDIDATES="$HOME/.profile" ;;
esac

add_path_line() {
    grep -qF "$PATH_LINE" "$1" 2>/dev/null && return 0
    printf '\n# added by MARGIE setup\n%s\n' "$PATH_LINE" >> "$1"
}

TOUCHED=""
for f in $CANDIDATES; do
    [ -e "$f" ] || continue
    add_path_line "$f"
    TOUCHED="$TOUCHED $f"
done

# Nothing existed to append to — create the first one, which is deliberately
# the file a LOGIN shell reads, since that is how the Windows launcher starts.
if [ -z "$TOUCHED" ]; then
    set -- $CANDIDATES
    add_path_line "$1"
fi

# ---------------------------------------------------------------------------
# Launch (starts backend + tunnel + app, so you can register)
# ---------------------------------------------------------------------------
echo
echo "Starting MARGIE so you can register — this is exactly what 'margie' does every time."
echo "In future, just open a new terminal and run:  margie"
echo

exec "$MARGIE"
