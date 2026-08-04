#!/usr/bin/env bash
#
# check-deps.sh — everything MARGIE needs on YOUR computer, checked in one place.
#
#   ./check-deps.sh            report what is there, then offer to install the rest
#   ./check-deps.sh --check    report only (exit 1 if something required is missing)
#   ./check-deps.sh --yes      install what is missing without asking
#
# Only the laptop side is covered here. What has to exist on the HPC (uv, the
# dane-api project, SLURM) is checked by margie.sh at launch, where the error can
# name the actual host and path instead of guessing from here.
#
# Nothing is reinstalled: anything already present is reported as found and left
# alone, so re-running this is cheap and safe.
set -u

MODE="ask"
case "${1:-}" in
    --check)   MODE="check" ;;
    --yes|-y)  MODE="yes" ;;
    "")        ;;
    *) echo "usage: $(basename "$0") [--check|--yes]" >&2; exit 2 ;;
esac

# What the app's own dependencies demand: @sveltejs/vite-plugin-svelte declares
# engines ^20.19 || ^22.12 || >=24, and .npmrc sets engine-strict=true, so npm
# does not warn about a wrong Node -- it refuses to install at all (EBADENGINE).
#
# This is NOT a simple "18 or newer". An 18, a 21 or a 23 all pass a floor check
# and then fail the install, which is a worse outcome than being told up front:
# setup reports everything is fine, and the first `margie` dies in npm with a
# message about a package nobody here has heard of. Checked properly below.
NODE_REQUIREMENT='20.19+ | 22.12+ | 24 or newer'
NODE_LTS=24          # what we install when we have to install Node ourselves
TMP="${TMPDIR:-/tmp}"

# ---------------------------------------------------------------------------
# Output helpers (same shape as margie.sh, so the two read as one tool)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Where are we?
#
# WSL matters on its own: it is Linux, but the browser, the clipboard and the
# home directory a Windows user thinks of all live on the other side of the
# boundary, and a few checks below only make sense there.
# ---------------------------------------------------------------------------
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
# Defaulted, because IS_WSL is also set by the /proc/version check above, and
# that path leaves WSL_DISTRO_NAME unset -- under `sudo`, and on WSL 1, which
# never exported it. `set -u` would then abort the whole dependency report on
# the one platform this line exists for.
[ "$IS_WSL" = "yes" ] && PLATFORM="Windows (WSL — ${WSL_DISTRO_NAME:-Linux})"

# ---------------------------------------------------------------------------
# Package names differ per distribution; keep the mapping in one place.
# An empty answer means "this platform ships it, or cannot install it for you".
# ---------------------------------------------------------------------------
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
        wslview:apt)        echo wslu ;;
        *)                  echo "" ;;
    esac
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------
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

# ^20.19 || ^22.12 || >=24, spelled out. The odd majors (21, 23) are not
# oversights: they are non-LTS releases the toolchain deliberately excludes,
# and a range check that let them through would be wrong in npm's favour.
node_version_ok() {
    local major="$1" minor="$2"
    [ "$major" -ge 24 ] && return 0
    [ "$major" -eq 22 ] && [ "$minor" -ge 12 ] && return 0
    [ "$major" -eq 20 ] && [ "$minor" -ge 19 ] && return 0
    return 1
}

# Bash 3.2 (still what macOS ships) trips over empty arrays under `set -u`,
# so these stay plain space-separated strings.
MISSING_REQ=""
MISSING_OPT=""
PKGS=""
NEED_NODE="no"
WARNINGS=""

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
    else
        report "$tool" "missing" "$why (optional)"
        MISSING_OPT="$MISSING_OPT $tool"
    fi
    [ -n "$pkg" ] && PKGS="$PKGS $pkg"
}

section "MARGIE — what this computer needs"
row "platform" "$PLATFORM"
row "installer" "$([ "$PKG_MGR" = none ] && echo "none detected" || echo "$PKG_MGR")"
echo

# Node is checked by version, not just by presence: an old Node on PATH is a
# worse failure than no Node at all, because vite starts and then dies with a
# syntax error nobody can read.
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
[ "$IS_WSL" = "yes" ] && want wslview optional "opens the app in your Windows browser"

# ---------------------------------------------------------------------------
# Things that are not missing packages, but will still ruin the day
# ---------------------------------------------------------------------------
APP_DIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || APP_DIR=""

# A repo living on the Windows disk (/mnt/c/...) technically works, but every
# npm install crawls across the filesystem bridge and vite's file watching does
# not fire at all, so the app never reloads. It reads as "MARGIE is broken".
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

# Optional tools should never block setup or trigger a noisy install prompt.
if [ -z "$MISSING_REQ" ] && [ -n "$MISSING_OPT" ] && [ "$MODE" = "ask" ]; then
    echo
    row "verdict" "ready (optional tools skipped)"
    exit 0
fi

if [ -z "$MISSING_REQ" ] && [ -z "$MISSING_OPT" ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Install what is missing — after saying exactly what that means
# ---------------------------------------------------------------------------
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

# Debian and Ubuntu pin `nodejs` to whatever was current when the release froze
# — 12.22 on Ubuntu 22.04, which cannot run this app. Use the distribution's
# package when it is new enough, and NodeSource only when it is not.
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
            # Ubuntu 24.04 offers 18.19 here, which engine-strict rejects, so
            # the distribution package is only used when it genuinely satisfies
            # the same rule the app is checked against.
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

# Last resort: a per-user Node, no administrator rights needed. margie.sh knows
# to source nvm, because a login shell started by the Windows launcher never
# reads .bashrc and would otherwise not see this Node at all.
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

# ---------------------------------------------------------------------------
# Say what actually happened — installers exit 0 far more often than they work
# ---------------------------------------------------------------------------
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
