#!/usr/bin/env bash
#
# margie -- starts the MARGIE front-end locally and opens it in the browser.
#
#   margie          open the start page, which resumes the last choice (local or HPC)
#   margie --choose open the start page to choose again
#   margie --local  run on this computer
#   margie --hpc    connect to the HPC from this terminal (prompts appear here)
#   margie --sync   pull the latest front-end from the HPC first (dev only)
#
set -u

# ---- environment ----
# The WSL launcher may leave $USER unset and skip .bashrc, so both are filled in here.
USER="${USER:-$(id -un 2>/dev/null || echo user)}"
export USER

is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null
}

if ! command -v node >/dev/null 2>&1 && [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
fi

# ---- settings (from ~/.config/margie/margie.env, sourced by the ~/bin/margie launcher) ----
REPO="$(cd "$(dirname "$0")/.." && pwd)"

HOW="app"
SYNC="no"
for arg in "$@"; do
    case "$arg" in
        --sync)  SYNC="yes" ;;
        --hpc)    HOW="hpc" ;;
        --local)  HOW="local" ;;
        --choose) HOW="choose" ;;
        *) echo "unknown option: $arg  (options: --choose, --local, --hpc, --sync)" >&2; exit 2 ;;
    esac
done

HPC_HOST="${HPC_HOST:-}"
BACKEND_DIR="${BACKEND_DIR:-}"
if [ "$HOW" = "hpc" ]; then
    : "${HPC_HOST:?not set -- choose the HPC on the app's start page, or run ./setup.sh --hpc}"
    : "${BACKEND_DIR:?not set -- choose the HPC on the app's start page, or run ./setup.sh --hpc}"
fi

FRONTEND_URL="http://localhost:5173"
API_PORT="${MARGIE_API_PORT:-8000}"
API_URL="http://localhost:$API_PORT"
# Per-user log path, so another user's leftover file cannot block it.
VITE_LOG="${TMPDIR:-/tmp}/margie-vite-$USER.log"
# State folder where hpc-connect.sh keeps its pid and progress marks.
STATE="${MARGIE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/margie}"
export MARGIE_STATE_DIR="$STATE"

# ---- output helpers ----
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
row() { printf '  %-20s %s\n' "$1" "$2"; }

# Kills whatever holds a local port, using lsof, fuser or ss (whichever exists).
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

# Opens a URL in the browser; under WSL it asks Windows directly (explorer.exe's
# exit code is ignored because it reports failure even on success).
open_url() {
    url="$1"
    if is_wsl; then
        command -v wslview     >/dev/null 2>&1 && wslview "$url"     >/dev/null 2>&1 && return 0
        command -v explorer.exe >/dev/null 2>&1 && { explorer.exe "$url" >/dev/null 2>&1; return 0; }
        # Falls back to fixed paths when the Windows PATH is not appended.
        if [ -x /mnt/c/Windows/explorer.exe ]; then
            /mnt/c/Windows/explorer.exe "$url" >/dev/null 2>&1
            return 0
        fi
        if [ -x /mnt/c/Windows/System32/cmd.exe ]; then
            # The empty "" is start's window title argument.
            /mnt/c/Windows/System32/cmd.exe /c start "" "$url" >/dev/null 2>&1
            return 0
        fi
    fi
    command -v open     >/dev/null 2>&1 && open "$url"     >/dev/null 2>&1 && return 0
    command -v xdg-open >/dev/null 2>&1 && xdg-open "$url" >/dev/null 2>&1 && return 0
    return 0
}

# Installs dependencies and starts the vite dev server; sets FE_PID.
start_frontend() {
    section "Front-end"
    cd "$REPO"

    if ! command -v npm >/dev/null 2>&1; then
        echo "  Node.js is not on PATH, so the app cannot start."
        echo "  Run this once to sort it out:  $REPO/scripts/check-deps.sh"
        exit 1
    fi

    # Shows the tail of the npm log on failure.
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

    # Points the app at the API tunnel port.
    echo "VITE_PUBLIC_API_URL=$API_URL" > "$REPO/.env"

    npm run dev > "$VITE_LOG" 2>&1 &
    FE_PID=$!
    printf '  starting vite'
    fe_ok="no"
    for i in $(seq 1 60); do
        if grep -q "Local:" "$VITE_LOG" 2>/dev/null; then
            printf ' ok\n'; fe_ok="yes"; break
        fi
        # Stops waiting early if the dev server has exited.
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
}

# Stops the HPC connection (whose exit handler stops the backend and tunnel) and waits for it.
stop_hpc_connection() {
    local pid
    pid="$(cat "$STATE/hpc-connect.pid" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 0
    kill -TERM "$pid" 2>/dev/null
    for i in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.5
    done
    kill -KILL "$pid" 2>/dev/null
    return 0
}

CLEANED=""
cleanup() {
    [ -n "$CLEANED" ] && return 0
    CLEANED=yes
    [ -n "${FE_PID:-}" ] && kill "$FE_PID" 2>/dev/null
    stop_hpc_connection
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

where_note() {
    if is_wsl; then
        row "running in" "WSL -- ${WSL_DISTRO_NAME:-Linux}"
        # /mnt/* is the Windows disk: npm is slow there and vite gets no file events.
        case "$REPO" in
            /mnt/*)
                echo
                echo "  NOTE: MARGIE is on the Windows disk, which makes it slow and stops"
                echo "        the page reloading when you edit. To move it into Linux:"
                echo "          cp -r \"$REPO/..\" ~/margie-frontend && cd ~/margie-frontend && ./setup.sh"
                ;;
        esac
    fi
}

# ---- margie / --local / --choose: starts the app, which handles any HPC connection itself ----
if [ "$HOW" != "hpc" ]; then
    section "MARGIE"
    row "Front-end" "$REPO"
    where_note
    free_port 5173
    start_frontend

    section "MARGIE READY"
    row "Front-end" "$FRONTEND_URL"
    if [ "$HOW" = "local" ]; then
        row "runs on" "this computer"
        open_path="/crisp"
    elif [ "$HOW" = "choose" ]; then
        row "next" "the start page: this computer or the HPC"
        open_path="/start"
    else
        # launch=1 resumes the last choice, if any.
        row "next" "the start page, which carries on with your last choice"
        open_path="/start?launch=1"
    fi
    row "stop" "Ctrl-C here (this also disconnects from the HPC)"
    is_wsl && row "in Windows" "if no browser opens, paste $FRONTEND_URL into it"
    echo
    open_url "$FRONTEND_URL$open_path"
    wait "$FE_PID"
    exit 0
fi

# ---- margie --hpc: connects via hpc-connect.sh, then starts the app over the tunnel ----
section "MARGIE (HPC, from this terminal)"
row "HPC host"  "$HPC_HOST"
row "Front-end" "$REPO"
where_note

MODE="${MARGIE_MODE:-}"
if [ -z "$MODE" ]; then
    if [ -t 0 ]; then
        echo
        echo "  1) Reattach / relaunch (safe)"
        echo "     - keeps running SLURM jobs untouched"
        echo "     - does NOT run git pull on HPC backend"
        echo "     - prefers reusing an already-running backend when possible"
        echo "  2) Clean restart (destructive)"
        echo "     - cancels ALL your running/pending SLURM jobs"
        echo "     - closes YOUR remote API sessions on login nodes"
        echo "     - runs git pull --ff-only on the HPC backend, then starts fresh"
        echo
        printf "  Choose [1]: "
        read -r MODE || MODE=1
    else
        MODE=1
    fi
fi
case "${MODE:-1}" in
    2) MODE=2 ;;
    *) MODE=1 ;;
esac
if [ "$MODE" = 2 ] && [ -t 0 ]; then
    echo
    echo "  WARNING: Option 2 will cancel ALL your SLURM jobs and restart backend services."
    printf "  Type YES to continue [default: no]: "
    read -r MODE2_CONFIRM || MODE2_CONFIRM=""
    if [ "$MODE2_CONFIRM" != "YES" ]; then
        echo "  Option 2 aborted by user. Falling back to option 1 (safe reattach/relaunch)."
        MODE=1
    fi
fi

# ---- backend code: the HPC pulls from GitHub, so it reports unpushed work and offers to push ----
BACKEND_LOCAL="${MARGIE_BACKEND_LOCAL:-$(cd "$REPO/../.." 2>/dev/null && pwd)/margie-backend}"
if [ -t 0 ] && [ -d "$BACKEND_LOCAL/.git" ]; then
    br="${BACKEND_BRANCH:-$(git -C "$BACKEND_LOCAL" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
    GIT_TERMINAL_PROMPT=0 git -C "$BACKEND_LOCAL" fetch -q origin "$br" 2>/dev/null
    if git -C "$BACKEND_LOCAL" rev-parse -q --verify "refs/remotes/origin/$br" >/dev/null; then
        ahead="$(git -C "$BACKEND_LOCAL" rev-list --count "refs/remotes/origin/$br..refs/heads/$br" 2>/dev/null || echo 0)"
    else
        ahead="new"
    fi
    changed="$(git -C "$BACKEND_LOCAL" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    section "Backend code"
    row "from" "$BACKEND_LOCAL ($br)"
    if [ "$changed" != 0 ]; then
        row "not committed" "$changed file(s) -- the HPC will not get these"
        echo "  To include them:  git -C \"$BACKEND_LOCAL\" add -A && git -C \"$BACKEND_LOCAL\" commit -m '...'"
        echo "  (then run margie --hpc again), or carry on with what is on GitHub."
    fi
    if [ "$ahead" = new ] || [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
        [ "$ahead" = new ] && row "GitHub" "does not have $br yet" || row "GitHub" "is $ahead commit(s) behind your copy"
        printf "  Push %s to GitHub now, so the HPC gets it? [Y/n]: " "$br"
        read -r push_now || push_now=""
        case "$push_now" in
            n|N|no) echo "  Not pushed." ;;
            *) git -C "$BACKEND_LOCAL" push -u origin "$br" || { echo "  The push did not work; see above."; exit 1; } ;;
        esac
    else
        row "GitHub" "has everything committed"
    fi
fi

# Frees the tunnel port from any connection the app started earlier.
stop_hpc_connection
free_port 5173

# ---- optional front-end sync from the HPC (dev only, never fatal) ----
if [ "$SYNC" = "yes" ]; then
    section "Sync front-end from HPC (optional)"
    if [ -n "${HPC_FRONTEND_DIR:-}" ] && rsync -az \
            --exclude .env --exclude node_modules --exclude .svelte-kit \
            --exclude .vite --exclude dist --exclude build --exclude .git \
            "$HPC_HOST:$HPC_FRONTEND_DIR/" "$REPO/"; then
        row "sync" "done"
    else
        row "sync" "skipped -- continuing with your local copy"
    fi
fi

# Runs in the background but in the terminal's foreground group, so ssh prompts appear here.
MODE="$MODE" "$REPO/scripts/hpc-connect.sh" &
CONNECT_PID=$!

connected="no"
while kill -0 "$CONNECT_PID" 2>/dev/null; do
    if grep -q '^ready ' "$STATE/hpc-connect.marks" 2>/dev/null; then
        connected="yes"
        break
    fi
    sleep 1
done
if [ "$connected" != "yes" ]; then
    echo
    echo "  Could not connect to the HPC; see above. Nothing was started."
    exit 1
fi
NODE="$(sed -n 's/^ready \([^ ]*\) .*/\1/p' "$STATE/hpc-connect.marks" | tail -1)"

start_frontend

# Confirms the API still answers before opening the browser.
if ! curl -fsS --max-time 5 "$API_URL/openapi.json" 2>/dev/null | grep -q '/v1/ssh/'; then
    echo "  The API stopped answering while the front-end was starting."
    echo "  Not opening the browser."
    exit 1
fi

section "MARGIE READY"
row "Front-end"   "$FRONTEND_URL"
row "Backend API" "$API_URL"
row "HPC node"    "$NODE"
row "stop"        "Ctrl-C here (this also stops the backend on the HPC)"
is_wsl && row "in Windows" "if no browser opens, paste $FRONTEND_URL into it"
echo
# The start page picks up this connection and continues to sign-in.
open_url "$FRONTEND_URL/start"
wait "$FE_PID"
