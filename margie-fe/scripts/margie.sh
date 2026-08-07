#!/usr/bin/env bash
#
# margie — start the backend on the HPC, tunnel to it, and open the front-end.
#   margie          start everything
#   margie --sync   pull the latest front-end from the HPC first (dev only)
#
set -u

# ---------------------------------------------------------------------------
# Where are we, and is everything on PATH?
#
# On Windows this runs inside WSL, started by the margie.cmd launcher rather
# than by a person at a prompt. That environment is thinner than a terminal's:
#
#   * $USER can be unset, and `set -u` would abort on the log and socket names
#     below before printing anything at all.
#   * a Node installed by nvm lives in .bashrc, which a non-interactive login
#     shell never reads, so `node` would appear to be missing.
# ---------------------------------------------------------------------------
USER="${USER:-$(id -un 2>/dev/null || echo user)}"

is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null
}

if ! command -v node >/dev/null 2>&1 && [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Settings (baked into ~/bin/margie by setup.sh)
# ---------------------------------------------------------------------------
REPO="$(cd "$(dirname "$0")/.." && pwd)"

: "${HPC_HOST:?not set — run ./setup.sh (or set HPC_HOST at the top of ~/bin/margie)}"
: "${BACKEND_DIR:?not set — run ./setup.sh (or set BACKEND_DIR at the top of ~/bin/margie)}"
# If BACKEND_DIR does not exist on the HPC yet, clone this repo there.
BACKEND_REPO_URL="${BACKEND_REPO_URL:-https://github.com/sajalbhattarai/bioinformatics-tools.git}"
# Optional override when git is missing on the HPC.
BACKEND_ARCHIVE_URL="${BACKEND_ARCHIVE_URL:-}"
BACKEND_PARENT="$(dirname "$BACKEND_DIR")"

SYNC="no"
if [ "${1:-}" = "--sync" ]; then
    SYNC="yes"
fi

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
FRONTEND_URL="http://localhost:5173"
API_URL="http://localhost:8000"
# Per-user log paths so a leftover file owned by someone else can't block us
# ($TMPDIR is private per-user on macOS; falls back to /tmp elsewhere).
VITE_LOG="${TMPDIR:-/tmp}/margie-vite-$USER.log"
# REMOTE paths must be named after the REMOTE account, not the local one.
# $USER expands on this laptop, so the log was landing on the cluster as
# margie-dane-api-<mac-username>.log under an HPC account with a different name
# -- confusing, and unsafe with several people: two users whose laptop accounts
# happen to match (both "admin", say) would collide on a shared login node's
# /tmp, while their actual HPC accounts differ. Deriving it from HPC_HOST makes
# the filename match the account that owns the file and unique per HPC user.
HPC_USER="${HPC_HOST%%@*}"
REMOTE_LOG="/tmp/margie-dane-api-$HPC_USER.log"
# Local socket: keeps the LOCAL user, since it lives on this laptop.
SOCKET="/tmp/margie-$HPC_HOST-$USER.sock"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
line() {
    printf '  '
    printf '%.0s─' {1..56}
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

# ---------------------------------------------------------------------------
# Kill whatever is holding a local port.
#
# lsof is the macOS answer but is NOT installed on a stock Ubuntu — including
# the one WSL gives Windows users — so a missing lsof silently stopped stale
# ports being freed there. Fall through to tools that distribution does ship.
# ---------------------------------------------------------------------------
free_port() {
    port="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -ti "tcp:$port" 2>/dev/null | xargs kill 2>/dev/null
    elif command -v fuser >/dev/null 2>&1; then
        fuser -k "$port/tcp" >/dev/null 2>&1
    elif command -v ss >/dev/null 2>&1; then
        ss -ltnp 2>/dev/null | sed -n "s/.*:$port .*pid=\([0-9]*\).*/\1/p" \
            | xargs -r kill 2>/dev/null
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Open the app in the user's browser.
#
# Under WSL the browser is on the Windows side, and xdg-open — which often
# exists — either does nothing or opens a Linux browser that isn't installed.
# Ask Windows directly instead. explorer.exe reports failure even when it
# worked, so its exit code is deliberately ignored.
# ---------------------------------------------------------------------------
open_url() {
    url="$1"
    if is_wsl; then
        command -v wslview     >/dev/null 2>&1 && wslview "$url"     >/dev/null 2>&1 && return 0
        command -v explorer.exe >/dev/null 2>&1 && { explorer.exe "$url" >/dev/null 2>&1; return 0; }
        # WSL can have interop switched on while appendWindowsPath=false keeps
        # the Windows PATH out of Linux -- explorer.exe is then unreachable by
        # name even though Windows is perfectly able to open the page. Its
        # install location is fixed, so reach it directly before giving up.
        if [ -x /mnt/c/Windows/explorer.exe ]; then
            /mnt/c/Windows/explorer.exe "$url" >/dev/null 2>&1
            return 0
        fi
        if [ -x /mnt/c/Windows/System32/cmd.exe ]; then
            # The empty "" is cmd's window title, not a stray argument: without
            # it, start treats the URL as the title and opens nothing.
            /mnt/c/Windows/System32/cmd.exe /c start "" "$url" >/dev/null 2>&1
            return 0
        fi
    fi
    command -v open     >/dev/null 2>&1 && open "$url"     >/dev/null 2>&1 && return 0
    command -v xdg-open >/dev/null 2>&1 && xdg-open "$url" >/dev/null 2>&1 && return 0
    return 0
}

# ---------------------------------------------------------------------------
# Shut everything down cleanly on exit
# ---------------------------------------------------------------------------
# Shut the session down on exit: front-end, tunnel, and every dane-api of ours
# on the node we were using.
#
# CRITICAL BOUNDARY: this must NOT touch dane_wf. Workflow runs are started
# detached (setsid + nohup) precisely so they survive the GUI closing -- an
# annotation runs for hours and killing the driver would silently stall it
# half-finished. The pattern below matches 'bin/dane-api' only; dane_wf's
# command line does not contain that string, so it is never selected. Do not
# loosen this to 'dane' or 'python'.
#
# Killing BE_PID alone was not enough: if the launcher reused an already-running
# backend (verdict "ours"), BE_PID is the pid of the second server that failed to
# bind and died, so the real one was left orphaned holding port 8000.
cleanup() {
    [ -n "${FE_PID:-}" ]  && kill "$FE_PID"  2>/dev/null
    [ -n "${TUN_PID:-}" ] && kill "$TUN_PID" 2>/dev/null
    if [ -S "$SOCKET" ]; then
        ssh -S "$SOCKET" -o BatchMode=yes "$HPC_HOST" "
            pkill -u \$USER -f 'bin/dane-api' 2>/dev/null
            rm -f \$HOME/.local/share/bsp/api-endpoint.json
        " >/dev/null 2>&1 || true
    fi
    ssh -S "$SOCKET" -O exit "$HPC_HOST" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

section "MARGIE"
row "HPC host"  "$HPC_HOST"
row "Front-end" "$REPO"
if is_wsl; then
    row "running in" "WSL — ${WSL_DISTRO_NAME:-Linux}"
    # /mnt/* is the Windows disk seen from Linux. It works, but npm crawls over
    # the filesystem bridge and vite's file watcher gets no events at all, so
    # the page never reloads -- which reads as "MARGIE is broken".
    case "$REPO" in
        /mnt/*)
            echo
            echo "  NOTE: MARGIE is on the Windows disk, which makes it slow and stops"
            echo "        the page reloading when you edit. To move it into Linux:"
            echo "          cp -r \"$REPO\" ~/biolab-fe && cd ~/biolab-fe && ./setup.sh"
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# What kind of launch?
#
# Non-interactive (no tty, or MARGIE_MODE set) defaults to 1, so this stays
# usable from a script or a CI job without hanging on a read.
# ---------------------------------------------------------------------------
MODE="${MARGIE_MODE:-}"
if [ -z "$MODE" ]; then
    if [ -t 0 ]; then
        echo
        echo "  1) Relaunch MARGIE          — reuse a healthy backend if one is already up"
        echo "  2) Clean restart            — close YOUR remote sessions on every login"
        echo "                                node first, then start everything fresh"
        echo
        printf "  Choose [1]: "
        read -r MODE || MODE=1
    else
        MODE=1
    fi
fi
case "${MODE:-1}" in
    2) MODE=2; row "mode" "clean restart (close all my remote sessions first)" ;;
    *) MODE=1; row "mode" "relaunch" ;;
esac

# ---------------------------------------------------------------------------
# Free local ports left over from a previous run
# ---------------------------------------------------------------------------
for port in 5173 8000; do
    free_port "$port"
done

# ---------------------------------------------------------------------------
# Optional: pull the latest front-end from the HPC (dev only, never fatal)
# ---------------------------------------------------------------------------
if [ "$SYNC" = "yes" ]; then
    section "Sync front-end from HPC (optional)"
    if [ -n "${HPC_FRONTEND_DIR:-}" ] && rsync -az \
            --exclude .env --exclude node_modules --exclude .svelte-kit \
            --exclude .vite --exclude dist --exclude build --exclude .git \
            "$HPC_HOST:$HPC_FRONTEND_DIR/" "$REPO/"; then
        row "sync" "done"
    else
        row "sync" "skipped — continuing with your local copy"
    fi
fi

echo "VITE_PUBLIC_API_URL=$API_URL" > "$REPO/.env"

# ---------------------------------------------------------------------------
# Start the backend on the HPC (uv sync -> activate -> dane-api)
# ---------------------------------------------------------------------------
section "Backend (on the HPC)"
# ---------------------------------------------------------------------------
# Terminate any previous dane-api first, wherever on the cluster it is.
#
# An abandoned dane-api holds port 8000 on whichever login node it was started
# on. ssh to the cluster address round-robins, so the next launch usually lands
# elsewhere and never sees it -- processes have been found still holding the port
# 26 days after their session ended, and each one makes that node unusable.
#
# The API records its host and pid in ~/.local/share/bsp/api-endpoint.json on
# startup ($HOME is shared across login nodes; /tmp is not). We read that and
# kill it at source. This is exact -- no hardcoded list of login node names to
# drift out of date -- and it costs one SSH.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Mode 2: close this user's backend processes on EVERY login node.
#
# Scoped to `-u $USER` and the dane-api entrypoint, so another user's work is
# never touched -- these are shared login nodes and that boundary matters.
#
# The node list is probed rather than assumed: each candidate gets a short
# BatchMode ssh and is skipped if unreachable, so a cluster with a different
# number of login nodes degrades quietly instead of erroring.
# ---------------------------------------------------------------------------
if [ "$MODE" = 2 ]; then
    section "Closing my remote sessions"
    _user="${HPC_HOST%%@*}"
    _dom="${HPC_HOST##*@}"
    killed=0
    for nn in 00 01 02 03 04 05 06 07 08 09; do
        node="login${nn}"
        out="$(ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no \
               "${_user}@${node}.${_dom}" "
                   n=\$(pgrep -u \$USER -f 'bin/dane-api' 2>/dev/null | wc -l)
                   pkill -u \$USER -f 'bin/dane-api' 2>/dev/null
                   echo \$n
               " 2>/dev/null)" || continue
        case "$out" in
            ''|*[!0-9]*) continue ;;                 # unreachable / odd reply
        esac
        [ "$out" -gt 0 ] && { row "$node" "closed $out"; killed=$((killed + out)); }
    done
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HPC_HOST" \
        "rm -f \$HOME/.local/share/bsp/api-endpoint.json" >/dev/null 2>&1 || true
    row "total closed" "$killed"
fi

section "Previous backend"
ADVERT=".local/share/bsp/api-endpoint.json"
prev="$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$HPC_HOST" \
        "cat \$HOME/$ADVERT 2>/dev/null" 2>/dev/null)"

if [ "$MODE" = 2 ]; then
    if [ -z "$prev" ]; then
        row "previous" "none recorded"
    else
        prev_host="$(printf '%s' "$prev" | sed -n 's/.*"host": *"\([^"]*\)".*/\1/p')"
        prev_pid="$(printf '%s' "$prev" | sed -n 's/.*"pid": *\([0-9]*\).*/\1/p')"
        if [ -n "$prev_host" ] && [ -n "$prev_pid" ]; then
            row "found" "pid $prev_pid on ${prev_host%%.*}"
            # Reach that specific node. ssh to the cluster address would round-robin
            # and probably miss it, so the recorded hostname is used directly.
            ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=no \
                "${HPC_HOST%%@*}@$prev_host" "
                    kill $prev_pid 2>/dev/null
                    sleep 2
                    kill -0 $prev_pid 2>/dev/null && kill -9 $prev_pid 2>/dev/null
                    # Sweep this node for any other stray dane-api of ours, then drop
                    # the advert so a failed kill cannot leave a phantom entry.
                    pkill -u \$USER -f 'bin/dane-api' 2>/dev/null
                    rm -f \$HOME/$ADVERT
                " >/dev/null 2>&1 && row "terminated" "yes" || row "terminated" "could not reach ${prev_host%%.*}"
        else
            row "previous" "advert unreadable — ignoring"
        fi
    fi
else
    row "previous" "kept (relaunch mode)"
fi

# ---------------------------------------------------------------------------
# Connect, and make sure we land on a node where port 8000 is actually ours.
#
# Login nodes are shared and 8000 is a popular port. If something else already
# holds it, uvicorn cannot bind, dane-api dies, and the tunnel then forwards
# every request into whatever IS listening -- which answers 404 for our routes.
# That failure is silent and looks exactly like a stale backend or a bad pull.
# (Seen in practice: a "HarnessWeb / OrgFlow" service on one node returning
# {"error": "not found"} for every /v1/... path.)
#
# The port is deliberately NOT changed -- it is the agreed backend port. Instead
# we detect the collision and reconnect: ssh to the cluster address round-robins
# across login nodes, so a fresh master connection usually lands elsewhere.
# ---------------------------------------------------------------------------
# Candidate hosts, tried in order: the cluster alias first (so a single-login
# cluster or a differently-named one still works), then explicit login nodes.
#
# Retrying the ALIAS does not move you. It was assumed to round-robin, but in
# practice macOS DNS caching and/or ControlPersist pin it -- observed landing on
# login03 six times in a row while login00 and login05 sat free. Explicit
# hostnames are the only reliable way to reach a different node.
_user="${HPC_HOST%%@*}"
_dom="${HPC_HOST##*@}"
CANDIDATES="$HPC_HOST"
case "$_dom" in
    login*) : ;;                                  # already a specific node
    *) for nn in 00 01 02 03 04 05 06 07 08 09; do
           CANDIDATES="$CANDIDATES ${_user}@login${nn}.${_dom}"
       done ;;
esac

NODE=""
TARGET=""
REUSE_BACKEND="no"
for cand in $CANDIDATES; do
    rm -f "$SOCKET"
    # -q silences the login banner, which otherwise prints on every probe.
    if ! ssh -q -M -S "$SOCKET" -o ConnectTimeout=15 -o StrictHostKeyChecking=no \
            -fN "$cand" 2>/dev/null; then
        continue                                   # node down or not resolvable
    fi

    _n="$(ssh -q -S "$SOCKET" "$cand" hostname 2>/dev/null)"
    # free  : nothing on 8000 -- we can bind
    # ours  : OUR OWN dane-api is already there
    # taken : someone/something else has it -- try the next node
    #
    # Ownership matters on a shared login node: `ss -ltnp` prints pid= only for
    # sockets you own and `pgrep -u` only matches your own processes, so another
    # user's MARGIE can never be mistaken for yours.
    verdict="$(ssh -q -S "$SOCKET" "$cand" '
        if ! ss -ltn 2>/dev/null | grep -q ":8000 "; then
            echo free
        elif ss -ltnp 2>/dev/null | grep ":8000 " | grep -q "pid=" \
             && pgrep -u "$USER" -f "bin/dane-api" >/dev/null 2>&1 \
             && curl -fsS --max-time 5 http://localhost:8000/openapi.json 2>/dev/null | grep -q "/v1/ssh/"; then
            echo ours
        else
            echo taken
        fi' 2>/dev/null)"

    case "$verdict" in
        free|ours)
            NODE="${_n:-$cand}"
            TARGET="$cand"
            row "node" "$NODE"
            if [ "$verdict" = ours ]; then
                row "backend" "already running (yours) — reusing"
                REUSE_BACKEND="yes"
            fi
            break
            ;;
        *)
            row "${_n:-$cand}" "port 8000 taken by another process — next node"
            ssh -q -S "$SOCKET" -O exit "$cand" 2>/dev/null || true
            ;;
    esac
done

# Everything downstream reuses the master socket, so point HPC_HOST at whichever
# host we actually connected to.
[ -n "$TARGET" ] && HPC_HOST="$TARGET"

if [ -z "$NODE" ]; then
    echo
    echo "  Port 8000 is already in use on every login node tried, by a process"
    echo "  that is not yours. The port is fixed, so MARGIE cannot work around it."
    echo
    echo "  The usual cause is other people running MARGIE at the same time:"
    echo "  the backend port is per-node, so only one user per login node can"
    echo "  hold it. With N login nodes, N users can run concurrently."
    echo
    echo "  Try again shortly, or check what is holding it:"
    echo "    ssh $HPC_HOST 'ss -ltnp | grep :8000'"
    exit 1
fi

# Prepare the environment on the HPC -- errors are shown (not hidden), so a wrong
# BACKEND_DIR or a uv failure is obvious instead of a silent missing venv.
if ! ssh -S "$SOCKET" "$HPC_HOST" "
    if [ ! -d '$BACKEND_DIR' ]; then
        echo '  BACKEND_DIR not found on the HPC: $BACKEND_DIR'
        mkdir -p '$BACKEND_PARENT' || { echo '  Could not create parent directory for BACKEND_DIR.' >&2; exit 3; }
        if command -v git >/dev/null 2>&1; then
            echo '  Cloning backend there from: $BACKEND_REPO_URL'
            git clone '$BACKEND_REPO_URL' '$BACKEND_DIR' || { echo '  Backend clone failed.' >&2; exit 3; }
        elif command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
            echo '  git not found on HPC; using archive download fallback.'
            tmpdir=\$(mktemp -d /tmp/margie-backend-XXXXXX 2>/dev/null || mktemp -d) || { echo '  Could not create temp directory.' >&2; exit 3; }
            archive="\$tmpdir/backend.tar.gz"
            fetched=no
            if [ -n '$BACKEND_ARCHIVE_URL' ]; then
                curl -fsSL '$BACKEND_ARCHIVE_URL' -o "\$archive" && fetched=yes
            else
                for u in \
                    https://codeload.github.com/sajalbhattarai/bioinformatics-tools/tar.gz/refs/heads/main \
                    https://codeload.github.com/sajalbhattarai/bioinformatics-tools/tar.gz/refs/heads/master \
                    https://codeload.github.com/sajalbhattarai/bioinformatics-tools/tar.gz/refs/heads/under-development
                do
                    curl -fsSL "\$u" -o "\$archive" && fetched=yes && break
                done
            fi
            [ "\$fetched" = yes ] || { rm -rf "\$tmpdir"; echo '  Could not download backend archive. Set BACKEND_ARCHIVE_URL or install git on HPC.' >&2; exit 3; }
            tar -xzf "\$archive" -C "\$tmpdir" || { rm -rf "\$tmpdir"; echo '  Could not extract backend archive.' >&2; exit 3; }
            src=\$(find "\$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
            [ -n "\$src" ] || { rm -rf "\$tmpdir"; echo '  Backend archive is empty.' >&2; exit 3; }
            mv "\$src" '$BACKEND_DIR' || { rm -rf "\$tmpdir"; echo '  Could not place backend into BACKEND_DIR.' >&2; exit 3; }
            rm -rf "\$tmpdir"
        else
            echo '  Missing git on HPC, and no curl+tar fallback available. Install git or curl+tar.' >&2
            exit 2
        fi
    fi
    cd '$BACKEND_DIR' 2>/dev/null || { echo '  BACKEND_DIR not accessible on the HPC: $BACKEND_DIR' >&2; exit 3; }
    [ -f pyproject.toml ] || { echo '  No pyproject.toml in $BACKEND_DIR -- point BACKEND_DIR at the bioinformatics-tools folder itself.' >&2; exit 4; }
    export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"
    if ! command -v uv >/dev/null 2>&1; then
        echo '  uv is not installed on the HPC (or not on PATH). Trying to install it for this user...'
        # Preferred: the official standalone installer -- a static binary that
        # needs neither Python nor root, so it works even on a Python-less HPC.
        # It drops uv into ~/.local/bin, already on PATH from the export above.
        if command -v curl >/dev/null 2>&1; then
            curl -LsSf https://astral.sh/uv/install.sh | sh || true
        elif command -v wget >/dev/null 2>&1; then
            wget -qO- https://astral.sh/uv/install.sh | sh || true
        fi
        hash -r 2>/dev/null || true
        # Fallback: pip --user, for a locked-down HPC with no outbound curl/wget
        # but a working Python and package index.
        if ! command -v uv >/dev/null 2>&1; then
            if command -v python3 >/dev/null 2>&1; then
                PYTHON_BOOT=python3
            elif command -v python >/dev/null 2>&1; then
                PYTHON_BOOT=python
            else
                PYTHON_BOOT=''
            fi
            if [ -n "\$PYTHON_BOOT" ]; then
                "\$PYTHON_BOOT" -m pip install --user --upgrade uv || true
            fi
            hash -r 2>/dev/null || true
        fi
    fi
    command -v uv >/dev/null 2>&1 || { echo '  uv is still not available. Install uv on the HPC (or allow pip --user install) and re-run.' >&2; exit 5; }
    uv sync || { echo '  uv sync failed (see above).' >&2; exit 6; }
    if [ ! -f .env ]; then
        sk=\$(.venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(32))')
        ek=\$(.venv/bin/python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')
        printf 'BSP_SECRET_KEY=%s\\nBSP_ENCRYPTION_KEY=%s\\n' \"\$sk\" \"\$ek\" > .env
        chmod 600 .env
        echo '  created backend .env with fresh BSP_SECRET_KEY / BSP_ENCRYPTION_KEY'
    fi
"; then
    echo
    echo "  Backend could not be prepared on the HPC. Fix the above, then re-run."
    exit 1
fi

if [ "$REUSE_BACKEND" = "yes" ]; then
    row "dane-api pid" "reused"
else
    # Belt and braces: clear any dane-api of ours on THIS node before starting.
    # The advert-based kill above only finds processes that recorded themselves, so
    # it misses anything started by an older build -- and a leftover here would stop
    # the new one binding, leaving the tunnel pointed at the stale process.
    ssh -S "$SOCKET" "$HPC_HOST" "pkill -u \$USER -f 'bin/dane-api' 2>/dev/null; sleep 1" >/dev/null 2>&1 || true

    BE_PID="$(ssh -S "$SOCKET" "$HPC_HOST" "
        cd '$BACKEND_DIR' || exit 1
        export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"
        source .venv/bin/activate
        nohup dane-api > $REMOTE_LOG 2>&1 & echo \$!
    " | tail -1)"
    row "dane-api pid" "$BE_PID"

    printf '  waiting for backend'
    backend_ready="no"
    for i in $(seq 1 60); do
        # Assert it is OUR api, not merely "something answers on 8000". A bare
        # reachability check is what allowed an unrelated service to be mistaken
        # for the backend and reported as READY.
        if ssh -S "$SOCKET" "$HPC_HOST" \
            "curl -fsS --max-time 5 http://localhost:8000/openapi.json 2>/dev/null | grep -q '/v1/ssh/'"; then
            printf ' ready\n'
            backend_ready="yes"
            break
        fi
        printf '.'
        sleep 1
    done
    if [ "$backend_ready" != "yes" ]; then
        printf '\n'
        echo "  dane-api did not start. Last lines of its log:"
        ssh -S "$SOCKET" "$HPC_HOST" "tail -n 20 $REMOTE_LOG 2>/dev/null" | sed 's/^/    /'
        echo "  Two common causes:"
        echo "   * no .env with BSP_SECRET_KEY / BSP_ENCRYPTION_KEY"
        echo "     (see the backend's README / docs/LOCAL_DEV.md)"
        echo "   * port 8000 taken on this login node, so uvicorn could not bind."
        echo "     Check with:  ssh $HPC_HOST 'ss -ltnp | grep :8000'"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Open the SSH tunnel (local :8000 -> backend :8000)
# ---------------------------------------------------------------------------
section "Tunnel"
ssh -S "$SOCKET" -o ExitOnForwardFailure=yes -N -L 8000:localhost:8000 "$HPC_HOST" &
TUN_PID=$!

# The loop here used to `break` on success and then fall through regardless, so
# an exhausted wait started the front-end anyway and the browser opened onto a
# dead tunnel. It is now a gate: reachable AND identifiably ours, or we stop.
printf '  verifying tunnel'
tunnel_ok="no"
for i in $(seq 1 30); do
    if curl -fsS --max-time 5 "$API_URL/openapi.json" 2>/dev/null | grep -q '/v1/ssh/'; then
        printf ' ok\n'
        tunnel_ok="yes"
        break
    fi
    printf '.'
    sleep 1
done
if [ "$tunnel_ok" != "yes" ]; then
    printf '\n'
    echo "  The tunnel is up but MARGIE's API is not answering through it."
    echo "  Not opening the front-end -- it would show connection errors."
    echo "  Backend log on $NODE:"
    ssh -S "$SOCKET" "$HPC_HOST" "tail -n 20 $REMOTE_LOG 2>/dev/null" | sed 's/^/    /'
    exit 1
fi
row "API" "$API_URL"

# ---------------------------------------------------------------------------
# Start the front-end
# ---------------------------------------------------------------------------
section "Front-end"
cd "$REPO"

if ! command -v npm >/dev/null 2>&1; then
    echo "  Node.js is not on PATH, so the app cannot start."
    echo "  Run this once to sort it out:  $REPO/scripts/check-deps.sh"
    exit 1
fi

# This used to be silenced entirely. When it failed -- a half-written
# node_modules, no network, a disk full -- vite then died for a reason that had
# nothing to do with npm, and the log said so. Show the real cause instead.
NPM_LOG="${TMPDIR:-/tmp}/margie-npm-$USER.log"
printf '  installing dependencies'
if npm install > "$NPM_LOG" 2>&1; then
    printf ' ok\n'
else
    printf '\n'
    echo "  npm install failed. Last lines of $NPM_LOG:"
    tail -n 20 "$NPM_LOG" 2>/dev/null | sed 's/^/    /'
    exit 1
fi

npm run dev > "$VITE_LOG" 2>&1 &
FE_PID=$!
printf '  starting vite'
fe_ok="no"
for i in $(seq 1 60); do
    if grep -q "Local:" "$VITE_LOG" 2>/dev/null; then
        printf ' ok\n'; fe_ok="yes"; break
    fi
    # If the dev server died, stop waiting the full minute for nothing.
    kill -0 "$FE_PID" 2>/dev/null || break
    printf '.'
    sleep 1
done
if [ "$fe_ok" != "yes" ]; then
    printf '\n'
    echo "  The front-end dev server did not start. Last lines of its log:"
    tail -n 20 "$VITE_LOG" 2>/dev/null | sed 's/^/    /'
    exit 1
fi

# Final check before handing over a URL: the browser must not be pointed at a
# stack that is only partly up.
if ! curl -fsS --max-time 5 "$API_URL/openapi.json" 2>/dev/null | grep -q '/v1/ssh/'; then
    echo "  The API stopped answering while the front-end was starting."
    echo "  Not opening the browser."
    exit 1
fi

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
section "MARGIE READY"
row "Front-end"   "$FRONTEND_URL"
row "Backend API" "$API_URL"
row "HPC node"    "$NODE"
is_wsl && row "in Windows" "if no browser opens, paste $FRONTEND_URL into it"
echo
open_url "$FRONTEND_URL"
wait "$FE_PID"
