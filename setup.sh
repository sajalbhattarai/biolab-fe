#!/usr/bin/env bash
#
# MARGIE GUI — one-time setup: checks dependencies, saves settings, installs the
# ~/bin/margie launcher and starts the app. See the README for details.
#
set -e

# ---- options ----
DEPS="ask"
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --check)     DEPS="check" ;;
        --yes|-y)    DEPS="yes" ;;
        --hpc)       TARGET="hpc" ;;
        --local)     TARGET="local" ;;
        -h|--help)
            echo "usage: ./setup.sh [--hpc | --local] [--check] [--yes]"
            echo "  (none)       set up this computer; the app's start page then asks where"
            echo "               MARGIE runs -- this computer or your HPC -- and remembers"
            echo "  --hpc        answer here instead: the HPC (asks for your HPC login, backend"
            echo "               folder, and offers passwordless SSH)"
            echo "  --local      answer here instead: this computer (checks for the pipeline)"
            echo "  --check      only report what is installed and what is missing"
            echo "  --yes        install anything missing without asking"
            exit 0 ;;
        *) echo "unknown option: $arg  (try --help)" >&2; exit 2 ;;
    esac
done

# ---- paths ----
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$ROOT/margie-fe"
BIN="$HOME/bin"
MARGIE="$BIN/margie"

# Under WSL, a clone on /mnt/* is copied into the Linux home and setup re-runs from there.
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
chmod +x "$REPO/scripts/margie.sh" "$REPO/scripts/check-deps.sh" "$REPO/scripts/hpc-connect.sh" \
    "$REPO/scripts/margie-askpass.sh" "$REPO/scripts/margie-key.sh"

# ---- local dependencies (checked first, via check-deps.sh) ----
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

# ---- settings: ~/.config/margie/margie.env, shared by the launcher and the app's start page ----
# Values are read from an older launcher that stored them inline, if no config exists.
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/margie"
CONFIG="$CONFIG_DIR/margie.env"
MARGIE_TARGET=""
HPC_HOST=""
BACKEND_DIR=""
MARGIE_SSH_KEY=""
MARGIE_PIPELINE_ROOT=""
BACKEND_REPO_URL=""
BACKEND_BRANCH=""
MARGIE_BACKEND_LOCAL=""

if [ -f "$CONFIG" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG"
elif [ -f "$MARGIE" ]; then
    MARGIE_TARGET="$(sed -n 's/^export MARGIE_TARGET="\(.*\)"$/\1/p' "$MARGIE")"
    HPC_HOST="$(sed -n 's/^export HPC_HOST="\(.*\)"$/\1/p' "$MARGIE")"
    BACKEND_DIR="$(sed -n 's/^export BACKEND_DIR="\(.*\)"$/\1/p' "$MARGIE")"
fi
HPC_USER="${HPC_HOST%%@*}"
HPC_ADDR="${HPC_HOST#*@}"
[ "$HPC_USER" = "$HPC_HOST" ] && HPC_USER=""

# Writes one single-quoted export per setting, so the file is safe to source.
save_config() {
    mkdir -p "$CONFIG_DIR"
    {
        echo "# MARGIE's settings (setup.sh and the app's start page keep these up to date)."
        for key in MARGIE_TARGET HPC_HOST BACKEND_DIR MARGIE_SSH_KEY MARGIE_PIPELINE_ROOT \
                   BACKEND_REPO_URL BACKEND_BRANCH MARGIE_BACKEND_LOCAL; do
            val="$(printf '%s' "${!key}" | sed "s/'/'\\\\''/g")"
            printf "export %s='%s'\n" "$key" "$val"
        done
    } > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
}

# ---- prompt helpers: the current value is the default on Enter ----
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

# Reads a numbered choice and prints it (the default on Enter).
choose() {
    local default="$1" answer=""
    printf "  Choose [%s]: " "$default" >&2
    read -r answer || answer=""
    echo "${answer:-$default}"
}

KEY_SH="$REPO/scripts/margie-key.sh"

# ---- where MARGIE runs: --local / --hpc answer here; otherwise the app's start page asks ----
if [ "$TARGET" = "local" ]; then
    MARGIE_TARGET="local"
    echo "MARGIE will run on this computer. No HPC login is needed."
    echo
    # The pipeline defaults to margie-pipeline beside the app; MARGIE_PIPELINE_ROOT overrides it.
    PIPE="${MARGIE_PIPELINE_ROOT:-$ROOT/margie-pipeline}"
    PIPE="${PIPE/#\~/$HOME}"
    if [ -f "$PIPE/annotate.sh" ] && [ -f "$PIPE/pipeline.conf.sh" ]; then
        echo "  Pipeline found:  $PIPE"
    else
        echo "  MARGIE's pipeline is not on this computer yet (looked in $PIPE)."
        echo "    1) Download it there now (git clone)"
        echo "    2) I already have it somewhere else"
        echo "    3) Later -- the app will offer the same"
        case "$(choose 1)" in
            1)
                _dl="$(mktemp -d)"
                if git clone --depth 1 -b margie-frontend https://github.com/sajalbhattarai/biolab-fe.git "$_dl/biolab-fe" \
                    && mv "$_dl/biolab-fe/margie-pipeline" "$ROOT/margie-pipeline"; then
                    rm -rf "${_dl:?}"
                    MARGIE_PIPELINE_ROOT=""
                    echo "  Pipeline downloaded:  $ROOT/margie-pipeline"
                else
                    rm -rf "${_dl:?}"
                    echo "  The download did not work; the app's start page can try again, or"
                    echo "  point it at a copy you already have."
                fi ;;
            2)
                prompt_for "Folder that holds annotate.sh and pipeline.conf.sh" MARGIE_PIPELINE_ROOT
                _p="${MARGIE_PIPELINE_ROOT/#\~/$HOME}"
                [ -f "$_p/annotate.sh" ] || echo "  NOTE: no annotate.sh in $_p -- the app will ask again." ;;
            *) : ;;
        esac
    fi
    echo "  Containers, tools and their reference data are set up in the app, on Install."

elif [ "$TARGET" = "hpc" ]; then
    MARGIE_TARGET="hpc"
    echo "A few things about your HPC (saved, so you are not asked again):"
    echo
    prompt_for "Your HPC username, e.g. jdoe (may differ from your computer's username)" HPC_USER
    prompt_for "Your HPC address, e.g. cluster.university.edu" HPC_ADDR
    # Defaults the backend folder to one under /home/<user>.
    [ -z "$BACKEND_DIR" ] && BACKEND_DIR="/home/$HPC_USER/bioinformatics-tools"
    prompt_for "Folder on the HPC for MARGIE's backend; the HPC clones it there if it is missing" BACKEND_DIR
    HPC_HOST="$HPC_USER@$HPC_ADDR"

    # ---- passwordless SSH key, used by the backend and the launcher (margie-key.sh) ----
    echo
    echo "Passwordless SSH to $HPC_ADDR for MARGIE:"
    if [ -n "$MARGIE_SSH_KEY" ] && "$KEY_SH" verify "$HPC_HOST" "$MARGIE_SSH_KEY" >/dev/null 2>&1; then
        echo "  Already set up: $MARGIE_SSH_KEY works."
    else
        echo "    1) Set it up for me: make a MARGIE key (~/.ssh/margie_ed25519) and add it"
        echo "       to the HPC. You type your HPC password (and two-factor) once."
        echo "    2) Show me how, and I'll do it myself"
        echo "    3) Not now (the app's start page offers it again after you sign in)"
        case "$(choose 1)" in
            1)
                MARGIE_SSH_KEY="$HOME/.ssh/margie_ed25519"
                "$KEY_SH" create "$MARGIE_SSH_KEY" >/dev/null &&
                    "$KEY_SH" install "$HPC_HOST" "$MARGIE_SSH_KEY" >/dev/null &&
                    if "$KEY_SH" verify "$HPC_HOST" "$MARGIE_SSH_KEY" >/dev/null; then
                        echo "  Done: $MARGIE_SSH_KEY now signs you in to $HPC_ADDR."
                    else
                        echo "  The key was added, but $HPC_ADDR still asks for more (some clusters"
                        echo "  require two-factor even with a key). MARGIE will ask when it needs to."
                    fi ||
                    { echo "  Could not set it up. The app's start page can try again."; MARGIE_SSH_KEY=""; } ;;
            2)
                echo
                echo "    # 1. A key for MARGIE (no passphrase: the backend uses it unattended)"
                echo "    ssh-keygen -t ed25519 -N '' -f ~/.ssh/margie_ed25519 -C margie"
                echo "    # 2. Its public half onto the HPC (asks for your password once)"
                echo "    ssh-copy-id -i ~/.ssh/margie_ed25519.pub $HPC_HOST"
                echo "    # 3. Check it: this should print ok without asking for anything"
                echo "    ssh -i ~/.ssh/margie_ed25519 -o BatchMode=yes $HPC_HOST echo ok"
                echo
                echo "  When you create your MARGIE account, choose this key there."
                MARGIE_SSH_KEY="$HOME/.ssh/margie_ed25519" ;;
            *) : ;;
        esac
    fi

else
    # No flag: reports the saved choice, if any; the app's start page asks otherwise.
    case "$MARGIE_TARGET" in
        local) echo "MARGIE runs on this computer (chosen before). Change it on the app's start page." ;;
        hpc)   echo "MARGIE runs on the HPC, $HPC_HOST (chosen before). Change it on the app's start page." ;;
        *)     echo "The app opens on its start page: choose there whether MARGIE runs on this"
               echo "computer or on your HPC. (Or answer here instead: ./setup.sh --local | --hpc)" ;;
    esac
fi

save_config
echo "Saved your settings in $CONFIG"

# ---- writes the ~/bin/margie launcher, which sources the settings file each run ----
cat > "$MARGIE" <<EOF
#!/usr/bin/env bash
# margie launcher (written by setup.sh). Where MARGIE runs, and the HPC's
# address and backend folder, are kept in the file below -- the app's start
# page updates it too. 'margie --local' or 'margie --hpc' overrides it for one
# run; 'margie --hpc' also signs in from this terminal instead of the browser.
CONFIG="\${XDG_CONFIG_HOME:-\$HOME/.config}/margie/margie.env"
# shellcheck disable=SC1090
[ -f "\$CONFIG" ] && . "\$CONFIG"
# The backend's repository and branch (BACKEND_REPO_URL, BACKEND_BRANCH) are in
# that file too; empty means margie-backend, and the branch checked out in
# your copy of it beside margie-frontend.
# export BACKEND_ARCHIVE_URL="https://codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/<branch>"   # when the HPC has no git
# export HPC_FRONTEND_DIR=""   # path to margie-fe on the HPC -- only for: margie --sync (dev)
exec "$REPO/scripts/margie.sh" "\$@"
EOF

chmod +x "$MARGIE"
echo "Installed $MARGIE"

# ---- puts ~/bin on PATH ----
PATH_LINE='export PATH="$HOME/bin:$PATH"'

# Appends to every existing startup file; creating ~/.bash_profile would make
# login bash skip ~/.profile (and with it ~/.bashrc).
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

# If none exists, creates the first candidate, which a login shell reads.
if [ -z "$TOUCHED" ]; then
    set -- $CANDIDATES
    add_path_line "$1"
fi

# ---- launch: opens the start page to choose, or the chosen target ----
echo
echo "Starting MARGIE. In future, just open a new terminal and run:  margie"
echo "(margie --choose brings this start page back.)"
echo

case "$TARGET" in
    local) exec "$MARGIE" --local ;;
    hpc)   exec "$MARGIE" ;;
    *)     exec "$MARGIE" --choose ;;
esac
