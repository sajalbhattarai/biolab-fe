#!/usr/bin/env bash
#
# hpc-connect -- signs in to the HPC, starts MARGIE's backend there and holds an
# SSH tunnel to it on localhost:$MARGIE_API_PORT; on exit it stops the backend.
# Called by margie --hpc (terminal prompts) or by the app (SSH_ASKPASS=margie-askpass.sh).
#
# Settings, from the environment:
#   HPC_HOST             you@cluster.address                   (required)
#   BACKEND_DIR          the backend's folder on the HPC       (required)
#   MODE                 1 reattach (safe, default) | 2 clean restart
#   MARGIE_SSH_KEY       a key to offer before asking for a password
#   MARGIE_API_PORT      the tunnel's port on this computer (8000)
#   BACKEND_REPO_URL     the backend's repository (default margie-backend)
#   BACKEND_BRANCH       its branch (default: the branch checked out in
#                        MARGIE_BACKEND_LOCAL, else margie-backend)
#   MARGIE_BACKEND_LOCAL a local checkout of that repository (found beside
#                        margie-frontend if not given); its branch must be on GitHub
#   BACKEND_ARCHIVE_URL  downloaded instead when the HPC has no git
#   MARGIE_QUESTION_DIR  where the app answers this script's questions
#   MARGIE_SSH_OPTS      extra options for every ssh call
#   MARGIE_COMPUTE       1: run the server as a SLURM job on a compute node
#   MARGIE_COMPUTE_CPUS / _MEM_GB / _HOURS / _PARTITION / _ACCOUNT
#                        that job's cores, memory, time limit, partition, account
#
# Progress goes to $MARGIE_STATE_DIR/hpc-connect.marks, one line per step:
#   step <id> <words>   ask <id>   answered <id> <value>
#   ready <node> <user@host> <socket>   fail <words>   closed
#
set -u
USER="${USER:-$(id -un 2>/dev/null || echo user)}"

: "${HPC_HOST:?not set -- choose the HPC in the app, or run ./setup.sh --hpc}"
: "${BACKEND_DIR:?not set -- choose the backend folder in the app, or run ./setup.sh --hpc}"
MODE="${MODE:-1}"
API_PORT="${MARGIE_API_PORT:-8000}"
API_URL="http://localhost:$API_PORT"
# The HPC clones this from GitHub, so it must be reachable from there.
BACKEND_REPO_URL="${BACKEND_REPO_URL:-https://github.com/sajalbhattarai/bioinformatics-tools.git}"
BACKEND_BRANCH="${BACKEND_BRANCH:-}"
BACKEND_ARCHIVE_URL="${BACKEND_ARCHIVE_URL:-}"

STATE="${MARGIE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/margie}"
mkdir -p "$STATE" && chmod 700 "$STATE"
MARKS="$STATE/hpc-connect.marks"
PIDFILE="$STATE/hpc-connect.pid"
: > "$MARKS"
# Writes the pid the app checks; under Git for Windows it is the Windows pid.
if [ -r "/proc/$$/winpid" ]; then cat "/proc/$$/winpid" > "$PIDFILE"; else echo $$ > "$PIDFILE"; fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# MARGIE_NO_MUX=1 (Windows): ssh cannot multiplex, so every call signs in again.
# MARGIE's key is created here and installed after the first sign-in (key_on).
if [ "${MARGIE_NO_MUX:-}" = 1 ] && [ -n "${MARGIE_SSH_KEY:-}" ] && [ ! -f "${MARGIE_SSH_KEY/#\~/$HOME}" ]; then
    bash "$SCRIPT_DIR/margie-key.sh" create "${MARGIE_SSH_KEY/#\~/$HOME}" >/dev/null 2>&1 || true
fi

# Wraps ssh with the extra options and MARGIE's key, when present.
read -r -a SSH_X <<< "${MARGIE_SSH_OPTS:-}"
if [ -n "${MARGIE_SSH_KEY:-}" ] && [ -f "${MARGIE_SSH_KEY/#\~/$HOME}" ]; then
    SSH_X+=(-i "${MARGIE_SSH_KEY/#\~/$HOME}")
fi
sshx() { ssh ${SSH_X[@]+"${SSH_X[@]}"} "$@"; }

# Remote paths use the HPC account name, so users do not collide on a shared /tmp.
HPC_USER="${HPC_HOST%%@*}"
REMOTE_LOG="/tmp/margie-dane-api-$HPC_USER.log"
# The local socket uses the local user name.
SOCKET="/tmp/margie-$HPC_HOST-$USER.sock"

mark() { printf '%s\n' "$*" >> "$MARKS"; }

# Asks a question and prints the chosen value:
#   ask ID "question" "value=Label|value=Label" DEFAULT
# Uses question/reply files in MARGIE_QUESTION_DIR, else /dev/tty, else the default.
QDIR="${MARGIE_QUESTION_DIR:-}"
ask() {
    local id="$1" text="$2" choices="$3" default="$4" reply="" i
    mark "ask $id"
    if [ -n "$QDIR" ] && [ -d "$QDIR" ]; then
        rm -f "$QDIR/reply.$id"
        printf '%s\n%s\n' "$choices" "$text" > "$QDIR/.question.$id" && mv "$QDIR/.question.$id" "$QDIR/question.$id"
        for i in $(seq 1 1800); do  # waits up to 15 minutes
            if [ -f "$QDIR/reply.$id" ]; then
                reply="$(head -n 1 "$QDIR/reply.$id")"
                break
            fi
            sleep 0.5
        done
        rm -f "$QDIR/question.$id" "$QDIR/reply.$id"
    elif { : < /dev/tty; } 2>/dev/null; then
        {
            echo
            printf '%s\n' "$text" | sed 's/^/  /'
            printf '%s\n' "$choices" | tr '|' '\n' | sed 's/^\([^=]*\)=\(.*\)$/    \1  -- \2/'
            printf '  Type one [%s]: ' "$default"
        } > /dev/tty
        read -r reply < /dev/tty || reply=""
    fi
    reply="${reply:-$default}"
    case "|$choices|" in
        *"|$reply="*) ;;
        *) reply="$default" ;;
    esac
    mark "answered $id $reply"
    printf '%s\n' "$reply"
}

# Runs a bash script from stdin on the HPC over the master socket, with %q-quoted arguments.
remote_sh() {
    local args="" a
    for a in "$@"; do args="$args $(printf '%q' "$a")"; done
    sshx -S "$SOCKET" "$HPC_HOST" "bash -s --$args"
}

# Normalises git URLs (https or ssh, with or without .git) for comparison.
norm_url() { printf '%s' "$1" | sed -E 's#^(ssh://)?(git@|https?://)##; s#:#/#; s#\.git/?$##; s#/$##' | tr 'A-Z' 'a-z'; }
same_repo() { [ -n "$1" ] && [ "$(norm_url "$1")" = "$(norm_url "$2")" ]; }
repo_name() { basename "$(norm_url "$1")"; }

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

fail() {
    mark "fail $*"
    echo "  $*"
    exit 1
}

# Kills whatever holds a local port, using lsof, fuser or ss (whichever exists).
free_port() {
    port="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -ti "tcp:$port" 2>/dev/null | xargs kill 2>/dev/null
    elif command -v fuser >/dev/null 2>&1; then
        fuser -k "$port/tcp" >/dev/null 2>&1
    elif command -v ss >/dev/null 2>&1; then
        ss -ltnp 2>/dev/null | sed -n "s/.*:$port .*pid=\([0-9]*\).*/\1/p" | xargs -r kill 2>/dev/null
    fi
    return 0
}

# ---- cleanup on exit: closes the tunnel and stops this user's dane-api ----
# The pattern matches 'bin/dane-api' only, so detached dane_wf runs keep going.
CLEANED=""
cleanup() {
    [ -n "$CLEANED" ] && return 0
    CLEANED=yes
    [ -n "${TUN_PID:-}" ] && kill "$TUN_PID" 2>/dev/null
    if [ -S "$SOCKET" ]; then
        sshx -S "$SOCKET" -o BatchMode=yes "$HPC_HOST" "
            pkill -u \$USER -f 'bin/dane-api' 2>/dev/null
            pkill -u \$USER -f 'L 127.0.0.1:8000:localhost:8000' 2>/dev/null
            ${API_JOB:+scancel $API_JOB 2>/dev/null}
            rm -f \$HOME/.local/share/bsp/api-endpoint.json
        " >/dev/null 2>&1 || true
    fi
    sshx -S "$SOCKET" -O exit "$HPC_HOST" 2>/dev/null || true
    rm -f "$PIDFILE"
    mark "closed"
}
# Signal handlers exit after cleanup so the script does not resume.
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# On Windows the app creates MARGIE_STOP_FILE instead of signalling; this turns it into a TERM.
if [ -n "${MARGIE_STOP_FILE:-}" ]; then
    rm -f "$MARGIE_STOP_FILE"
    ( while [ ! -e "$MARGIE_STOP_FILE" ] && kill -0 $$ 2>/dev/null; do sleep 1; done
      rm -f "$MARGIE_STOP_FILE"; kill -TERM $$ 2>/dev/null ) &
fi

section "MARGIE on the HPC"
row "HPC host" "$HPC_HOST"
row "backend folder" "$BACKEND_DIR"
case "$MODE" in
    2) row "mode" "clean restart (destructive: cancel jobs + refresh backend)" ;;
    *) MODE=1; row "mode" "reattach/relaunch (safe: keep jobs running)" ;;
esac

# ---- mode 2: cancels this user's SLURM jobs and stops their dane-api on every login node ----
# Scoped to -u $USER; unreachable nodes (BatchMode ssh) are skipped.
if [ "$MODE" = 2 ]; then
    mark "step clean Cancelling your jobs and closing old sessions"
    section "Cancelling my SLURM jobs"
    jobs_before="$(sshx -o BatchMode=yes -o ConnectTimeout=10 "$HPC_HOST" \
        "squeue -h -u \\\$USER 2>/dev/null | wc -l" 2>/dev/null || echo '?')"
    sshx -o BatchMode=yes -o ConnectTimeout=10 "$HPC_HOST" \
        "scancel -u \\\$USER >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
    jobs_after="$(sshx -o BatchMode=yes -o ConnectTimeout=10 "$HPC_HOST" \
        "squeue -h -u \\\$USER 2>/dev/null | wc -l" 2>/dev/null || echo '?')"
    row "jobs before" "$jobs_before"
    row "jobs after" "$jobs_after"

    section "Closing my remote sessions"
    _user="${HPC_HOST%%@*}"
    _dom="${HPC_HOST##*@}"
    killed=0
    for nn in 00 01 02 03 04 05 06 07 08 09; do
        node="login${nn}"
        out="$(sshx -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no \
               "${_user}@${node}.${_dom}" "
                   n=\$(pgrep -u \$USER -f 'bin/dane-api' 2>/dev/null | wc -l)
                   pkill -u \$USER -f 'bin/dane-api' 2>/dev/null
                   echo \$n
               " 2>/dev/null)" || continue
        case "$out" in
            ''|*[!0-9]*) continue ;;
        esac
        [ "$out" -gt 0 ] && { row "$node" "closed $out"; killed=$((killed + out)); }
    done
    sshx -o BatchMode=yes -o ConnectTimeout=10 "$HPC_HOST" \
        "rm -f \$HOME/.local/share/bsp/api-endpoint.json" >/dev/null 2>&1 || true
    row "total closed" "$killed"
fi

# ---- previous backend: reads host and pid from ~/.local/share/bsp/api-endpoint.json ----
# Used to try that node first, or in mode 2 to stop that process.
section "Previous backend"
ADVERT=".local/share/bsp/api-endpoint.json"
prev="$(sshx -o BatchMode=yes -o ConnectTimeout=15 "$HPC_HOST" \
        "cat \$HOME/$ADVERT 2>/dev/null" 2>/dev/null)"
prev_host="$(printf '%s' "$prev" | sed -n 's/.*"host": *"\([^"]*\)".*/\1/p')"
prev_pid="$(printf '%s' "$prev" | sed -n 's/.*"pid": *\([0-9]*\).*/\1/p')"

if [ "$MODE" = 2 ]; then
    if [ -z "$prev" ]; then
        row "previous" "none recorded"
    elif [ -n "$prev_host" ] && [ -n "$prev_pid" ]; then
        row "found" "pid $prev_pid on ${prev_host%%.*}"
        sshx -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=no \
            "${HPC_HOST%%@*}@$prev_host" "
                kill $prev_pid 2>/dev/null
                sleep 2
                kill -0 $prev_pid 2>/dev/null && kill -9 $prev_pid 2>/dev/null
                pkill -u \$USER -f 'bin/dane-api' 2>/dev/null
                rm -f \$HOME/$ADVERT
            " >/dev/null 2>&1 && row "terminated" "yes" || row "terminated" "could not reach ${prev_host%%.*}"
    else
        row "previous" "advert unreadable -- ignoring"
    fi
elif [ -n "$prev_host" ]; then
    row "previous" "recorded on ${prev_host%%.*} -- trying it first"
else
    row "previous" "none recorded"
fi

# With MARGIE_NO_MUX, installs MARGIE's key on the node right after the first sign-in.
key_on() {
    [ "${MARGIE_NO_MUX:-}" = 1 ] && [ -n "${MARGIE_SSH_KEY:-}" ] || return 0
    local key="${MARGIE_SSH_KEY/#\~/$HOME}"
    [ -f "$key" ] || return 0
    if bash "$SCRIPT_DIR/margie-key.sh" verify "$1" "$key" >/dev/null 2>&1; then
        row "key" "MARGIE's key signs in"
    else
        mark "step key Adding MARGIE's key on the HPC, so the next steps need no password"
        row "key" "adding MARGIE's key on the HPC (asked once more)"
        if bash "$SCRIPT_DIR/margie-key.sh" install "$1" "$key" >/dev/null 2>&1; then
            row "key" "added"
        else
            row "key" "could not add it -- the next steps may each ask again"
        fi
    fi
}

# ---- connect: finds a login node where port 8000 is free or held by this user's dane-api ----
# Tries the previous node first, then the cluster alias, then login00..09; each costs a sign-in.
mark "step connect Signing in to ${HPC_HOST#*@}"
_user="${HPC_HOST%%@*}"
_dom="${HPC_HOST##*@}"
CANDIDATES="$HPC_HOST"
case "$_dom" in
    login*) : ;;
    *) for nn in 00 01 02 03 04 05 06 07 08 09; do
           CANDIDATES="$CANDIDATES ${_user}@login${nn}.${_dom}"
       done ;;
esac
if [ -n "$prev_host" ]; then
    CANDIDATES="$_user@$prev_host $(printf '%s\n' $CANDIDATES | grep -v "@${prev_host}\$" | tr '\n' ' ')"
fi

NODE=""
TARGET=""
REUSE_BACKEND="no"
for cand in $CANDIDATES; do
    rm -f "$SOCKET"
    # Names the node before ssh prompts for a password.
    row "connecting" "${cand#*@}"
    mark "step node Trying ${cand#*@}"
    if ! sshx -q -M -S "$SOCKET" -o ConnectTimeout=15 -o StrictHostKeyChecking=no \
            -fN "$cand" 2>/dev/null; then
        row "${cand#*@}" "unreachable or sign-in refused -- next node"
        continue
    fi
    key_on "$cand"

    _n="$(sshx -q -S "$SOCKET" "$cand" hostname 2>/dev/null)"
    # Classifies port 8000 as free, ours (this user's dane-api answers) or taken.
    verdict="$(sshx -q -S "$SOCKET" "$cand" '
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
        ours)
            NODE="${_n:-$cand}"; TARGET="$cand"; REUSE_BACKEND="yes"
            row "node" "$NODE"
            row "backend" "already running (yours) -- reusing"
            break ;;
        free)
            # Keeps this connection rather than searching further.
            NODE="${_n:-$cand}"; TARGET="$cand"
            row "node" "$NODE"
            row "backend" "starting fresh on free node"
            break ;;
        *)
            row "${_n:-$cand}" "port 8000 taken by another process -- next node"
            sshx -q -S "$SOCKET" -O exit "$cand" 2>/dev/null || true ;;
    esac
done

# Later calls reuse the master socket, so HPC_HOST becomes the node actually used.
[ -n "$TARGET" ] && HPC_HOST="$TARGET"

if [ -z "$NODE" ]; then
    echo
    echo "  No login node could be used: either none accepted the sign-in, or port"
    echo "  8000 is held on every one of them by a process that is not yours (the"
    echo "  port is fixed; with N login nodes, N people can run MARGIE at once)."
    echo "  Check what is holding it:  ssh $HPC_HOST 'ss -ltnp | grep :8000'"
    fail "Could not sign in to a login node with port 8000 free."
fi
mark "step signed-in Signed in on ${NODE%%.*}"

# ---- backend code: the HPC clones/fetches BACKEND_REPO_URL at BACKEND_BRANCH from GitHub ----
# A local checkout picks the branch and must already be pushed.
section "Backend (on the HPC)"
mark "step prepare Preparing MARGIE on the cluster"

LOCAL="${MARGIE_BACKEND_LOCAL:-}"
if [ -z "$LOCAL" ]; then
    guess="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)/margie-backend"
    [ -d "$guess/.git" ] && LOCAL="$guess"
fi
if [ -n "$LOCAL" ] && ! same_repo "$(git -C "$LOCAL" remote get-url origin 2>/dev/null)" "$BACKEND_REPO_URL"; then
    LOCAL=""  # ignores a checkout of a different repository
fi
if [ -n "$LOCAL" ]; then
    BACKEND_BRANCH="${BACKEND_BRANCH:-$(git -C "$LOCAL" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
    GIT_TERMINAL_PROMPT=0 git -C "$LOCAL" fetch -q origin "$BACKEND_BRANCH" 2>/dev/null
    git -C "$LOCAL" rev-parse -q --verify "refs/remotes/origin/$BACKEND_BRANCH^{commit}" >/dev/null 2>&1 \
        || fail "The branch $BACKEND_BRANCH is not on GitHub yet: push it first (the start page can), then connect again."
    ahead="$(git -C "$LOCAL" rev-list --count "refs/remotes/origin/$BACKEND_BRANCH..refs/heads/$BACKEND_BRANCH" 2>/dev/null || echo 0)"
    [ "${ahead:-0}" -gt 0 ] && row "not on GitHub" "$ahead commit(s) on this computer -- push them for the HPC to get them"
    [ -n "$(git -C "$LOCAL" status --porcelain 2>/dev/null)" ] && row "not on GitHub" "changes on this computer that are not committed"
fi
BACKEND_BRANCH="${BACKEND_BRANCH:-margie-backend}"
row "code" "$(repo_name "$BACKEND_REPO_URL") ($BACKEND_BRANCH), from GitHub"

# Inspects the backend folder on the HPC.
inspect="$(remote_sh "$BACKEND_DIR" <<'EOF'
d=$1
if [ -L "$d" ] && [ ! -e "$d" ]; then echo "dir=broken-link $(readlink "$d")"
elif [ -e "$d" ] && [ ! -d "$d" ]; then echo "dir=not-a-folder"
elif [ ! -e "$d" ]; then echo "dir=missing"
elif [ -z "$(ls -A "$d" 2>/dev/null)" ]; then echo "dir=empty"
elif [ ! -f "$d/pyproject.toml" ]; then echo "dir=not-backend"
else
    echo "dir=backend"
    if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "origin=$(git -C "$d" remote get-url origin 2>/dev/null)"
        echo "head=$(git -C "$d" rev-parse HEAD 2>/dev/null)"
        echo "branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)"
        [ -n "$(git -C "$d" status --porcelain --untracked-files=no 2>/dev/null)" ] && echo "dirty=yes"
    fi
fi
exit 0
EOF
)" || fail "Could not look in $BACKEND_DIR on the HPC."
got() { printf '%s\n' "$inspect" | sed -n "s/^$1=//p" | head -n 1; }
state="$(got dir)"
kind="${state%% *}"
case "$kind" in
    broken-link)  why="is a link to ${state#* }, which is no longer there" ;;
    not-a-folder) why="is a file, not a folder" ;;
    not-backend)  why="is a folder with other things in it, not MARGIE's backend (no pyproject.toml)" ;;
    backend)
        o="$(got origin)"
        if [ -z "$o" ]; then why="holds a copy of the backend that is not a git checkout, so it cannot be brought up to date"
        elif ! same_repo "$o" "$BACKEND_REPO_URL"; then why="holds a copy of $(repo_name "$o"), not $(repo_name "$BACKEND_REPO_URL")"
        else why=""; fi ;;
    *) why="" ;;
esac

# Asks before replacing an unusable folder; replacing moves it aside, never deletes.
KEEP=""
if [ -n "$why" ]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    aside="$BACKEND_DIR.old-$stamp"
    if [ "$kind" = backend ]; then
        choices="replace=Replace it|keep=Keep using it as it is"; default=keep
    else
        choices="replace=Replace it|stop=Leave it, and stop"; default=stop
    fi
    answer="$(ask replace-backend "$BACKEND_DIR on the HPC $why.
Replace it with $(repo_name "$BACKEND_REPO_URL") ($BACKEND_BRANCH)? What is there now is moved aside to $aside, not deleted." "$choices" "$default")"
    case "$answer" in
        replace)
            remote_sh "$BACKEND_DIR" "$aside" <<'EOF' || fail "Could not move $BACKEND_DIR aside."
mv "$1" "$2" && echo "  moved aside: $2"
EOF
            kind=missing ;;
        keep)
            KEEP=yes
            row "backend" "keeping the copy that is there, as it is" ;;
        *)
            fail "Left $BACKEND_DIR as it is. Choose another backend folder, or let MARGIE replace it." ;;
    esac
fi

UPDATE="no"
[ "$MODE" = 2 ] && UPDATE="yes"
CHANGED="no"
CODE_STATE=""
if [ "$kind" = missing ] || [ "$kind" = empty ]; then
    mark "step prepare Downloading MARGIE's backend on the cluster"
    remote_sh "$BACKEND_DIR" "$BACKEND_BRANCH" "$BACKEND_REPO_URL" "$BACKEND_ARCHIVE_URL" <<'EOF' || fail "Could not put the backend in $BACKEND_DIR (see above)."
d=$1 br=$2 url=$3 archive_url=$4
mkdir -p "$(dirname "$d")" || exit 3
if command -v git >/dev/null 2>&1; then
    echo "  cloning $url ($br) into $d"
    GIT_TERMINAL_PROMPT=0 git clone -q -b "$br" "$url" "$d" && exit 0
    echo "  The HPC could not clone $url ($br): is the repository public, and is the branch on GitHub?" >&2
    exit 3
fi
# No git: the repository's archive, from GitHub or BACKEND_ARCHIVE_URL.
case "$url" in
    https://github.com/*) slug="${url#https://github.com/}"; slug="${slug%.git}"
                          archive_url="${archive_url:-https://codeload.github.com/$slug/tar.gz/refs/heads/$br}" ;;
esac
[ -n "$archive_url" ] && command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 \
    || { echo "  git is not installed on the HPC, and there is no archive to download instead." >&2; exit 2; }
echo "  git is not installed on the HPC; downloading $archive_url"
tmp=$(mktemp -d /tmp/margie-backend-XXXXXX) || exit 3
curl -fsSL "$archive_url" -o "$tmp/b.tar.gz" && tar -xzf "$tmp/b.tar.gz" -C "$tmp" \
    && mv "$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)" "$d"
status=$?
rm -rf "$tmp"
[ $status -eq 0 ] || { echo "  Could not download $archive_url." >&2; exit 3; }
EOF
    CHANGED="yes"; CODE_STATE="fresh"
elif [ "$kind" = backend ] && [ -z "$KEEP" ]; then
    # Compares the HPC copy with GitHub's branch and offers a fast-forward update
    # (automatic in mode 2); a copy with uncommitted changes is left alone.
    head="$(got head)"
    branch_now="$(got branch)"
    remote_sha="$(remote_sh "$BACKEND_DIR" "$BACKEND_BRANCH" <<'EOF'
cd "$1" 2>/dev/null && GIT_TERMINAL_PROMPT=0 git fetch -q origin "$2" 2>/dev/null \
    && git rev-parse -q --verify "refs/remotes/origin/$2^{commit}"
exit 0
EOF
)"
    if [ -z "$remote_sha" ]; then
        row "update" "the HPC could not fetch $BACKEND_BRANCH from GitHub -- running what is there"; CODE_STATE="nofetch"
    elif [ "$head" = "$remote_sha" ] && [ "$branch_now" = "$BACKEND_BRANCH" ]; then
        row "code" "up to date with GitHub (${remote_sha:0:9})"; CODE_STATE="latest"
    elif [ -n "$(got dirty)" ]; then
        row "update" "skipped: the copy on the HPC has uncommitted changes of its own"; CODE_STATE="dirty"
    else
        if [ "$UPDATE" != yes ]; then
            UPDATE="$(ask update-backend "The backend on the HPC is not what GitHub has (it is at ${head:0:9} on $branch_now; GitHub's $BACKEND_BRANCH is at ${remote_sha:0:9}).
Update it now? MARGIE's server restarts on the new code. Jobs already running are not stopped, but steps they start from now on use the new code." "yes=Update it|no=Not now" no)"
        fi
        if [ "$UPDATE" = yes ]; then
            mark "step prepare Updating MARGIE's backend on the cluster"
            remote_sh "$BACKEND_DIR" "$BACKEND_BRANCH" <<'EOF' || fail "Could not update the backend in $BACKEND_DIR (see above)."
set -e
cd "$1"
br=$2
if git show-ref -q --verify "refs/heads/$br"; then git checkout -q "$br"; else git checkout -q -b "$br" "origin/$br"; fi
git merge -q --ff-only "origin/$br" || { echo "  $br on the HPC has commits GitHub does not: left as it is." >&2; exit 8; }
git branch -q --set-upstream-to="origin/$br" "$br" 2>/dev/null || true
echo "  updated to $(git rev-parse --short HEAD) on $br"
EOF
            CHANGED="yes"; CODE_STATE="updated"
        else
            CODE_STATE="behind"
        fi
    fi
fi

# Reports which backend commit the HPC runs and whether it is GitHub's latest.
CODE_AT="$(remote_sh "$BACKEND_DIR" <<'EOF'
git -C "$1" log -1 --format='%h from %cs' 2>/dev/null
EOF
)"
CODE_AT="${CODE_AT:+ ($CODE_AT)}"
case "${CODE_STATE:-}" in
    fresh)   mark "step code The latest from GitHub, just downloaded$CODE_AT" ;;
    latest)  mark "step code Already the latest on GitHub's $BACKEND_BRANCH$CODE_AT" ;;
    updated) mark "step code Updated to the latest on GitHub's $BACKEND_BRANCH$CODE_AT" ;;
    behind)  mark "step code Older than GitHub's $BACKEND_BRANCH, not updated$CODE_AT: reconnect and choose Update to get the newest features" ;;
    dirty)   mark "step code Not updated: the copy on the HPC has changes of its own$CODE_AT" ;;
    nofetch) mark "step code Could not check GitHub; running what is there$CODE_AT" ;;
    *)       mark "step code Running the copy in $BACKEND_DIR$CODE_AT" ;;
esac

# ---- installs uv if needed, runs uv sync and creates the backend's .env keys once ----
remote_sh "$BACKEND_DIR" <<'EOF' || fail "The backend could not be prepared on the HPC (see the details above)."
cd "$1" 2>/dev/null || { echo "  $1 is not accessible on the HPC." >&2; exit 3; }
[ -f pyproject.toml ] || { echo "  No pyproject.toml in $1 -- it should be the backend's folder itself." >&2; exit 4; }
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
    echo "  uv is not installed on the HPC (or not on PATH). Installing it for this user..."
    # The standalone installer needs neither Python nor root; pip --user is
    # the fallback for a locked-down HPC with no outbound curl/wget.
    if command -v curl >/dev/null 2>&1; then curl -LsSf https://astral.sh/uv/install.sh | sh || true
    elif command -v wget >/dev/null 2>&1; then wget -qO- https://astral.sh/uv/install.sh | sh || true; fi
    hash -r 2>/dev/null || true
    if ! command -v uv >/dev/null 2>&1; then
        py=$(command -v python3 || command -v python || true)
        [ -n "$py" ] && "$py" -m pip install --user --upgrade uv || true
        hash -r 2>/dev/null || true
    fi
fi
command -v uv >/dev/null 2>&1 || { echo "  uv is still not available. Install uv on the HPC (or allow pip --user install) and re-run." >&2; exit 5; }
uv sync || { echo "  uv sync failed (see above)." >&2; exit 6; }
if [ ! -f .env ]; then
    sk=$(.venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(32))')
    ek=$(.venv/bin/python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')
    printf 'BSP_SECRET_KEY=%s\nBSP_ENCRYPTION_KEY=%s\n' "$sk" "$ek" > .env
    chmod 600 .env
    echo "  created backend .env with fresh BSP_SECRET_KEY / BSP_ENCRYPTION_KEY"
fi
EOF

# ---- jobs run from ~/bioinformatics-tools, so it is linked to this backend ----
# A link or missing path is repointed; a real folder is only moved aside after asking.
pipe="$(remote_sh "$BACKEND_DIR" <<'EOF'
d=$1 p=$HOME/bioinformatics-tools
real() { (cd "$1" 2>/dev/null && pwd -P); }
if [ "$(real "$d")" = "$(real "$p")" ]; then echo same
elif [ -L "$p" ] || [ ! -e "$p" ]; then ln -sfn "$(real "$d")" "$p" && echo linked
else echo folder; fi
EOF
)"
case "$pipe" in
    same)   row "pipeline" "runs from $BACKEND_DIR" ;;
    linked) row "pipeline" "~/bioinformatics-tools -> $BACKEND_DIR" ;;
    folder)
        stamp="$(date +%Y%m%d-%H%M%S)"
        if [ "$(ask pipeline-folder "Jobs run the pipeline from ~/bioinformatics-tools on the HPC, which is a separate folder -- an older copy, not $BACKEND_DIR.
Point it at $BACKEND_DIR, so jobs run the code you deployed? The folder is moved aside to ~/bioinformatics-tools.old-$stamp, not deleted." "move=Point it at the new copy|keep=Leave it" keep)" = move ]; then
            remote_sh "$BACKEND_DIR" "$stamp" <<'EOF' || fail "Could not point ~/bioinformatics-tools at $BACKEND_DIR."
p=$HOME/bioinformatics-tools
mv "$p" "$p.old-$2" && ln -s "$(cd "$1" && pwd -P)" "$p" && echo "  ~/bioinformatics-tools -> $1 (the old folder is $p.old-$2)"
EOF
        else
            row "pipeline" "still runs from the separate ~/bioinformatics-tools"
        fi ;;
esac

# Branch passed to the backend as BSP_MARGIE_SB_REF.
RUN_BRANCH="$(remote_sh "$BACKEND_DIR" <<'EOF'
git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null
EOF
)"
[ "$RUN_BRANCH" = HEAD ] && RUN_BRANCH=""
# Restarts the server when the code changed.
[ "$CHANGED" = yes ] && REUSE_BACKEND="no"
# Reuses a running server only if it was started for this branch.
if [ "$REUSE_BACKEND" = yes ]; then
    started_for="$(remote_sh "${RUN_BRANCH:-for-website-deployment}" <<'EOF'
pid=$(pgrep -u "$USER" -f 'bin/dane-api' | head -n 1)
have=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^BSP_MARGIE_SB_REF=//p')
[ "${have:-for-website-deployment}" = "$1" ] && echo same || echo other
EOF
)"
    [ "$started_for" = same ] || { row "backend" "restarting it, for $RUN_BRANCH"; REUSE_BACKEND="no"; }
fi

# ---- compute node (MARGIE_COMPUTE=1): runs dane-api as a SLURM job ----
# The login node relays its localhost:8000 to the job's node over ssh. After a
# minute in the queue, it asks whether to fall back to the login node.
# Group settings for MARGIE's server, from the app's private settings: plain paths or names only.
SERVER_ENV=""
for _v in MARGIE_SHARED_ROOT LICENSE_RECORDS_DIR MARGIE_OPERATOR; do
    _val="${!_v:-}"
    [ -n "$_val" ] || continue
    case "$_val" in *[!A-Za-z0-9_./-]*) fail "$_v may contain only letters, digits and _ . / -";; esac
    SERVER_ENV="${SERVER_ENV}export $_v=$_val; "
done

API_JOB=""
if [ "${MARGIE_COMPUTE:-}" = 1 ]; then
    section "Compute node"
    mark "step start Asking SLURM for a compute node"
    C_CPUS="${MARGIE_COMPUTE_CPUS:-4}"; C_MEM="${MARGIE_COMPUTE_MEM_GB:-16}"; C_HOURS="${MARGIE_COMPUTE_HOURS:-8}"
    # Log on shared storage, so the login node can read it.
    C_LOG="$BACKEND_DIR/.margie-api.log"
    # Any earlier server is stopped below, so nothing is reused.
    REUSE_BACKEND="no"
    sshx -S "$SOCKET" "$HPC_HOST" "pkill -u \$USER -f 'bin/dane-api' 2>/dev/null; pkill -u \$USER -f 'L 127.0.0.1:8000:localhost:8000' 2>/dev/null; scancel -u \$USER -n margie-api 2>/dev/null; true" >/dev/null 2>&1
    API_JOB="$(sshx -S "$SOCKET" "$HPC_HOST" "
        cd '$BACKEND_DIR' || exit 1
        sbatch --parsable --job-name=margie-api --cpus-per-task='$C_CPUS' --mem='${C_MEM}G' --time='$C_HOURS:00:00' \
            ${MARGIE_COMPUTE_PARTITION:+--partition='$MARGIE_COMPUTE_PARTITION'} ${MARGIE_COMPUTE_ACCOUNT:+--account='$MARGIE_COMPUTE_ACCOUNT'} \
            --output='$C_LOG' \
            --wrap='export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"; ${RUN_BRANCH:+export BSP_MARGIE_SB_REF=$RUN_BRANCH;} ${SERVER_ENV}. .venv/bin/activate && exec dane-api'
    " 2>&1 | tail -1)"
    case "$API_JOB" in
        ''|*[!0-9]*)
            row "compute node" "SLURM refused the job: $API_JOB"
            if [ "$(ask compute-refused "SLURM did not accept a job for MARGIE's server:
$API_JOB

Use the login node instead?" "login=Use the login node|stop=Stop" login)" = stop ]; then fail "SLURM did not accept the job for MARGIE's server."; fi
            API_JOB="" ;;
        *)
            row "slurm job" "$API_JOB ($C_CPUS cores, ${C_MEM} GB, $C_HOURS h)"
            C_NODE=""; waited=0; asked=""
            while :; do
                st="$(sshx -S "$SOCKET" "$HPC_HOST" "squeue -h -j $API_JOB -o '%T|%N|%r' 2>/dev/null" | tail -1)"
                state="${st%%|*}"; rest="${st#*|}"; node="${rest%%|*}"; reason="${rest#*|}"
                case "$state" in
                    RUNNING) C_NODE="$node"; break ;;
                    PENDING|CONFIGURING)
                        mark "step start Waiting for a compute node: $(printf '%s' "$state" | tr 'A-Z' 'a-z')${reason:+ ($reason)}, ${waited}s so far"
                        if [ -z "$asked" ] && [ "$waited" -ge 60 ]; then
                            asked=yes
                            if [ "$(ask compute-wait "MARGIE's server is still waiting in the SLURM queue for a compute node (${reason:-no reason given}).

Keep waiting, or use the login node for now? The login node is shared with other users: follow your institution's policy on what may run there." "wait=Keep waiting|login=Use the login node" wait)" = login ]; then
                                sshx -S "$SOCKET" "$HPC_HOST" "scancel $API_JOB" >/dev/null 2>&1; API_JOB=""; break
                            fi
                        fi ;;
                    *) row "slurm job" "ended (${state:-gone})"; sshx -S "$SOCKET" "$HPC_HOST" "tail -n 20 '$C_LOG' 2>/dev/null" | sed 's/^/    /'
                       fail "The SLURM job for MARGIE's server ended before it started (${state:-gone})." ;;
                esac
                sleep 5; waited=$((waited + 5))
            done
            if [ -n "$API_JOB" ]; then
                row "compute node" "$C_NODE"
                mark "step start Starting MARGIE's server on $C_NODE"
                # Starts the relay from the login node's localhost:8000 to the job's node.
                sshx -S "$SOCKET" "$HPC_HOST" "nohup ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -N -L 127.0.0.1:8000:localhost:8000 '$C_NODE' > /tmp/margie-api-relay-\$USER.log 2>&1 < /dev/null & echo started" >/dev/null 2>&1
                relay_ok=no
                for i in $(seq 1 90); do
                    if sshx -S "$SOCKET" "$HPC_HOST" "curl -fsS --max-time 5 http://localhost:8000/openapi.json 2>/dev/null | grep -q '/v1/ssh/'"; then relay_ok=yes; break; fi
                    sleep 2
                done
                if [ "$relay_ok" != yes ]; then
                    sshx -S "$SOCKET" "$HPC_HOST" "tail -n 5 /tmp/margie-api-relay-\$USER.log; tail -n 15 '$C_LOG'" 2>/dev/null | sed 's/^/    /'
                    sshx -S "$SOCKET" "$HPC_HOST" "scancel $API_JOB; pkill -u \$USER -f 'L 127.0.0.1:8000:localhost:8000'" >/dev/null 2>&1; API_JOB=""
                    if [ "$(ask compute-unreachable "MARGIE's server was started on $C_NODE but could not be reached from the login node. The cluster may not allow ssh to compute nodes.

Use the login node instead?" "login=Use the login node|stop=Stop" login)" = stop ]; then fail "MARGIE's server on the compute node could not be reached."; fi
                else
                    row "dane-api" "on $C_NODE, job $API_JOB"
                    REUSE_BACKEND="compute"
                fi
            fi ;;
    esac
fi

if [ "$REUSE_BACKEND" = "compute" ]; then
    : # running as a SLURM job, relayed to the login node's localhost:8000
elif [ "$REUSE_BACKEND" = "yes" ]; then
    row "dane-api pid" "reused"
else
    mark "step start Starting MARGIE's server"
    # Stops any leftover dane-api of this user on this node so the new one can bind.
    sshx -S "$SOCKET" "$HPC_HOST" "pkill -u \$USER -f 'bin/dane-api' 2>/dev/null; sleep 1" >/dev/null 2>&1 || true

    BE_PID="$(sshx -S "$SOCKET" "$HPC_HOST" "
        cd '$BACKEND_DIR' || exit 1
        export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"
        ${RUN_BRANCH:+export BSP_MARGIE_SB_REF='$RUN_BRANCH'}
        ${SERVER_ENV}
        . .venv/bin/activate
        nohup dane-api > $REMOTE_LOG 2>&1 & echo \$!
    " | tail -1)"
    row "dane-api pid" "$BE_PID"

    printf '  waiting for backend'
    backend_ready="no"
    for i in $(seq 1 60); do
        # Checks for MARGIE's API specifically, not just any listener on 8000.
        if sshx -S "$SOCKET" "$HPC_HOST" \
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
        sshx -S "$SOCKET" "$HPC_HOST" "tail -n 20 $REMOTE_LOG 2>/dev/null" | sed 's/^/    /'
        echo "  Two common causes:"
        echo "   * no .env with BSP_SECRET_KEY / BSP_ENCRYPTION_KEY (see the backend's README)"
        echo "   * port 8000 taken on this login node, so uvicorn could not bind."
        fail "MARGIE's server did not start on ${NODE%%.*} (see the details above)."
    fi
fi

# ---- tunnel: localhost:$API_PORT -> the backend's 8000; fails unless MARGIE's API answers ----
section "Tunnel"
mark "step tunnel Opening the tunnel"
free_port "$API_PORT"
sshx -S "$SOCKET" -o ExitOnForwardFailure=yes -N -L "$API_PORT:localhost:8000" "$HPC_HOST" &
TUN_PID=$!

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
    echo "  Backend log on $NODE:"
    sshx -S "$SOCKET" "$HPC_HOST" "tail -n 20 $REMOTE_LOG 2>/dev/null" | sed 's/^/    /'
    fail "The tunnel to MARGIE's server did not work (see the details above)."
fi
row "API" "$API_URL"
mark "ready $NODE $HPC_HOST $SOCKET"

# Holds until stopped or until the master connection (which carries the tunnel)
# drops; the backgrounded sleep lets `wait` return at once on a signal.
while sshx -S "$SOCKET" -O check "$HPC_HOST" >/dev/null 2>&1; do
    sleep 5 &
    wait $!
done
fail "The connection to ${NODE%%.*} closed."
