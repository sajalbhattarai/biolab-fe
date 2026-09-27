#!/usr/bin/env bash
#
# check-deps.sh — checks the local tools MARGIE needs and offers to install missing ones.
#
#   ./check-deps.sh            report what is there, then offer to install the rest
#   ./check-deps.sh --check    report only (exit 1 if something required is missing)
#   ./check-deps.sh --yes      install what is missing without asking
#
# HPC-side requirements are checked by margie.sh at launch.
set -u

MODE="ask"
case "${1:-}" in
    --check)   MODE="check" ;;
    --yes|-y)  MODE="yes" ;;
    "")        ;;
    *) echo "usage: $(basename "$0") [--check|--yes]" >&2; exit 2 ;;
esac

# Matches @sveltejs/vite-plugin-svelte's engines field; .npmrc sets engine-strict=true.
NODE_REQUIREMENT='20.19+ | 22.12+ | 24 or newer'
NODE_LTS=24          # version installed when Node is missing
TMP="${TMPDIR:-/tmp}"

# ---- output helpers (same format as margie.sh) ----
line() {
    printf '  '
    printf '%.0s─' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
                   21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 \
                   39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56
    printf '\n'
}

section() {
    echo
    line
    printf '  %s\n' "$1"
    line
}

row() {
    printf '  %-20s %s\n' "$1" "$2"
}

# tool | verdict | detail
report() {
    printf '  %-10s %-9s %s\n' "$1" "$2" "$3"
}

# ---- platform and package manager detection (WSL flagged separately) ----
OS="$(uname -s 2>/dev/null || echo unknown)"
IS_WSL="no"
if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL="yes"
fi

PKG_MGR="none"
if [ "$OS" = "Darwin" ]; then
    command -v brew >/dev/null 2>&1 && PKG_MGR="brew"
else
    for m in apt dnf pacman zypper; do
        case "$m" in
            apt)    command -v apt-get >/dev/null 2>&1 && PKG_MGR="apt" ;;
            dnf)    command -v dnf     >/dev/null 2>&1 && PKG_MGR="dnf" ;;
            pacman) command -v pacman  >/dev/null 2>&1 && PKG_MGR="pacman" ;;
            zypper) command -v zypper  >/dev/null 2>&1 && PKG_MGR="zypper" ;;
        esac
        [ "$PKG_MGR" != "none" ] && break
    done
fi

PLATFORM="$OS"
# WSL_DISTRO_NAME may be unset (WSL 1, sudo), so it is defaulted under set -u.
[ "$IS_WSL" = "yes" ] && PLATFORM="Windows (WSL — ${WSL_DISTRO_NAME:-Linux})"

# Maps a tool to its package name for the detected package manager; empty means none.
pkg_for() {
    case "$1:$PKG_MGR" in
        git:*)              echo git ;;
        ssh:apt)            echo openssh-client ;;
        ssh:dnf|ssh:zypper) echo openssh-clients ;;
        ssh:pacman)         echo openssh ;;
        ssh:brew)           echo "" ;;               # macOS ships ssh
        npm:brew)           echo "" ;;               # comes with node
        npm:*)              echo npm ;;
        curl:*)             echo curl ;;
        rsync:*)            echo rsync ;;
        lsof:*)             echo lsof ;;
        *)                  echo "" ;;
    esac
}

# ---- detection ----
node_major() {
    command -v node >/dev/null 2>&1 || return 1
    local v
    v="$(node -v 2>/dev/null)" || return 1
    v="${v#v}"; v="${v%%.*}"
    case "$v" in ''|*[!0-9]*) return 1 ;; esac
    printf '%s' "$v"
}

node_minor() {
    local v
    v="$(node -v 2>/dev/null)" || return 1
    v="${v#v}"; v="${v#*.}"; v="${v%%.*}"
    case "$v" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$v" ;; esac
}

# Returns success for ^20.19 || ^22.12 || >=24; odd majors 21 and 23 are excluded.
node_version_ok() {
    local major="$1" minor="$2"
    [ "$major" -ge 24 ] && return 0
    [ "$major" -eq 22 ] && [ "$minor" -ge 12 ] && return 0
    [ "$major" -eq 20 ] && [ "$minor" -ge 19 ] && return 0
    return 1
}

# Space-separated strings, since bash 3.2 (macOS) fails on empty arrays under set -u.
MISSING_REQ=""
MISSING_OPT=""
PKGS=""
NEED_NODE="no"
WARNINGS=""
OPTIONAL_NOTES=""

want() {   # want <tool> <required|optional> <why>
    local tool="$1" kind="$2" why="$3" pkg
    if command -v "$tool" >/dev/null 2>&1; then
        report "$tool" "found" "$(command -v "$tool")"
        return
    fi
    pkg="$(pkg_for "$tool")"
    if [ "$kind" = required ]; then
        report "$tool" "MISSING" "$why"
        MISSING_REQ="$MISSING_REQ $tool"
        [ -n "$pkg" ] && PKGS="$PKGS $pkg"
    else
        report "$tool" "missing" "$why (optional)"
        MISSING_OPT="$MISSING_OPT $tool"
        case "$tool" in
        esac
    fi
}

section "MARGIE — what this computer needs"
row "platform" "$PLATFORM"
row "installer" "$([ "$PKG_MGR" = none ] && echo "none detected" || echo "$PKG_MGR")"
echo

# Checks Node by version, not just presence.
if nm="$(node_major)"; then
    if node_version_ok "$nm" "$(node_minor)"; then
        report "node" "found" "$(node -v)"
    else
        report "node" "WRONG" "$(node -v) — MARGIE needs $NODE_REQUIREMENT"
        MISSING_REQ="$MISSING_REQ node"
        NEED_NODE="yes"
    fi
else
    report "node" "MISSING" "runs the MARGIE app on your computer"
    MISSING_REQ="$MISSING_REQ node"
    NEED_NODE="yes"
fi

if [ "$NEED_NODE" = "no" ]; then
    want npm required "installs the app's own dependencies"
else
    report "npm" "bundled" "installed together with Node"
fi

want git    required "gets MARGIE and its updates"
want ssh    required "the private connection to your HPC"
want curl   required "checks the backend is really answering"
want rsync  optional "only for: margie --sync"
want lsof   optional "frees a port left behind by a previous run"

# ---- environment warnings ----
APP_DIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || APP_DIR=""

# Warns when the repo is on the Windows disk under WSL, where npm is slow and vite cannot watch files.
if [ "$IS_WSL" = "yes" ] && case "$APP_DIR" in /mnt/*) true ;; *) false ;; esac; then
    echo
    report "location" "SLOW" "MARGIE is on the Windows disk ($APP_DIR)"
    WARNINGS="$WARNINGS location"
fi

echo
if [ -n "$MISSING_REQ" ]; then
    row "verdict" "missing: ${MISSING_REQ# }"
else
    row "verdict" "everything required is already here"
fi
[ -n "$MISSING_OPT" ] && row "also missing" "${MISSING_OPT# } (optional)"

if [ -n "$OPTIONAL_NOTES" ]; then
    section "Optional recommendations"
    # shellcheck disable=SC2059
    printf "$OPTIONAL_NOTES\n"
fi

if [ -n "$WARNINGS" ]; then
    section "Worth fixing"
    case " $WARNINGS " in *" location "*)
        echo "  MARGIE is on the Windows side of the filesystem. Installing it inside"
        echo "  Linux instead makes it much faster and lets the page reload as you work."
        echo
        echo "  Run ./setup.sh from the repo root and setup will move it automatically."
        ;;
    esac
fi

if [ "$MODE" = "check" ]; then
    [ -n "$MISSING_REQ" ] && exit 1
    exit 0
fi

# Missing optional tools alone never block setup or prompt to install.
if [ -z "$MISSING_REQ" ] && [ -n "$MISSING_OPT" ] && [ "$MODE" = "ask" ]; then
    echo
    row "verdict" "ready (optional tools skipped)"
    exit 0
fi

if [ -z "$MISSING_REQ" ] && [ -z "$MISSING_OPT" ]; then
    exit 0
fi

# ---- install what is missing ----
section "Install the missing pieces?"

[ "$NEED_NODE" = "yes" ] && echo "  * Node.js $NODE_LTS (LTS) — the app itself"
if [ -n "${PKGS# }" ]; then
    echo "  *${PKGS} — via $PKG_MGR"
fi
echo

if [ "$PKG_MGR" = "none" ]; then
    echo "  No package manager was found here, so this has to be done by hand:"
    echo
    case "$OS" in
        Darwin)
            echo "    Node.js   https://nodejs.org  (choose LTS)"
            echo "    Git       https://git-scm.com/downloads"
            echo "    or install Homebrew first:  https://brew.sh" ;;
        *)
            echo "    Node.js   https://nodejs.org  (choose LTS)"
            echo "    Git       your distribution's package manager" ;;
    esac
    echo
    [ -n "$MISSING_REQ" ] && exit 1
    exit 0
fi

if [ "$MODE" != "yes" ]; then
    if [ -t 0 ]; then
        printf "  Install these now? [Y/n]: "
        read -r ans || ans="n"
        case "${ans:-Y}" in
            [Nn]*) echo "  Skipped — nothing was installed."
                   [ -n "$MISSING_REQ" ] && exit 1
                   exit 0 ;;
        esac
    else
        echo "  Not a terminal, so nothing was installed. Re-run with --yes to install."
        [ -n "$MISSING_REQ" ] && exit 1
        exit 0
    fi
fi

sudo_run() {
    if [ "$(id -u)" = 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "  Need administrator rights for: $*" >&2
        return 1
    fi
}

APT_UPDATED="no"
apt_refresh() {
    [ "$APT_UPDATED" = "yes" ] && return 0
    sudo_run apt-get update -qq && APT_UPDATED="yes"
}

install_pkgs() {
    [ -z "${1:-}" ] && return 0
    case "$PKG_MGR" in
        apt)    apt_refresh; sudo_run apt-get install -y $1 ;;
        dnf)    sudo_run dnf install -y $1 ;;
        pacman) sudo_run pacman -S --noconfirm --needed $1 ;;
        zypper) sudo_run zypper --non-interactive install $1 ;;
        brew)   brew install $1 ;;
    esac
}

section "MARGIE launch modes"
echo "  When you run margie, you will choose one mode:"
echo
echo "  1) Reattach / relaunch (safe)"
echo "     - keeps your running/pending SLURM jobs untouched"
echo "     - does not run git pull on the HPC backend checkout"
echo "     - prefers reusing your already-running backend"
echo
echo "  2) Clean restart (destructive)"
echo "     - cancels ALL your running/pending SLURM jobs"
echo "     - closes your remote backend sessions on login nodes"
echo "     - runs git pull --ff-only on the HPC backend checkout"
echo "     - asks for explicit YES confirmation before proceeding"


# Prints the major and minor version of apt's nodejs candidate.
apt_node_major() {
    local cand major minor
    cand="$(apt-cache policy nodejs 2>/dev/null | sed -n 's/^ *Candidate: *//p')"
    cand="${cand#*:}"                 # drop the epoch, e.g. 2:18.19.1~dfsg-6
    major="${cand%%.*}"
    minor="${cand#*.}"; minor="${minor%%.*}"
    case "$major" in ''|*[!0-9]*) major=0 ;; esac
    case "$minor" in ''|*[!0-9]*) minor=0 ;; esac
    echo "$major $minor"
}

install_node() {
    case "$PKG_MGR" in
        brew)
            brew install node ;;
        apt)
            apt_refresh
            # Uses the distribution package only when it meets the version rule; else NodeSource.
            if node_version_ok $(apt_node_major); then
                sudo_run apt-get install -y nodejs npm
            else
                echo "  This system's Node does not meet $NODE_REQUIREMENT — fetching Node $NODE_LTS from nodesource.com"
                curl -fsSL "https://deb.nodesource.com/setup_${NODE_LTS}.x" -o "$TMP/nodesource.sh" \
                    && sudo_run bash "$TMP/nodesource.sh" \
                    && sudo_run apt-get install -y nodejs
            fi ;;
        dnf)    sudo_run dnf install -y "nodejs:$NODE_LTS/common" 2>/dev/null || sudo_run dnf install -y nodejs npm ;;
        pacman) sudo_run pacman -S --noconfirm --needed nodejs npm ;;
        zypper) sudo_run zypper --non-interactive install nodejs npm ;;
    esac
}

# Installs a per-user Node through nvm as a fallback; margie.sh sources nvm itself.
install_node_nvm() {
    echo "  Falling back to nvm (installs Node just for you, no admin rights)"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash || return 1
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh" || return 1
    nvm install --lts
}

section "Installing"

FAILED=""
NON_FATAL=""

if [ "$NEED_NODE" = "yes" ]; then
    row "node" "installing…"
    if ! install_node; then
        install_node_nvm || FAILED="$FAILED node"
    fi
fi

if [ -n "${PKGS# }" ]; then
    row "packages" "installing…${PKGS}"
    install_pkgs "$PKGS" || NON_FATAL="$NON_FATAL packages"
fi

# ---- re-checks each tool, since installers can exit 0 without working ----
section "Result"

if nm="$(node_major)" && node_version_ok "$nm" "$(node_minor)"; then
    report "node" "ok" "$(node -v)"
else
    report "node" "STILL WRONG" "need $NODE_REQUIREMENT — get it from https://nodejs.org"
    FAILED="$FAILED node"
fi

for t in npm git ssh curl; do
    if command -v "$t" >/dev/null 2>&1; then
        report "$t" "ok" ""
    else
        report "$t" "STILL MISSING" ""
        FAILED="$FAILED $t"
    fi
done

if [ -n "$NON_FATAL" ]; then
    report "optional" "skipped" "some optional packages could not be installed"
fi

echo
if [ -n "$FAILED" ]; then
    row "verdict" "still missing: ${FAILED# }"
    exit 1
fi
row "verdict" "ready"
