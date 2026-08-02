#!/usr/bin/env bash
#
# wsl-bootstrap.sh — the Linux half of the Windows installer (setup.ps1).
#
#   wsl-bootstrap.sh place <source-dir>       put MARGIE inside Linux, print where
#   wsl-bootstrap.sh ssh-import <windows-ssh> copy the user's SSH keys into WSL
#
# This is a file rather than a command string inside setup.ps1 because anything
# sent that way is quoted by PowerShell, then by wsl.exe, then by bash, and a
# path with a space in it (C:\Users\Jane Doe\...) does not survive the trip. A
# file has no quoting to survive.
set -u

usage() {
    echo "usage: $(basename "$0") place <source-dir>" >&2
    echo "       $(basename "$0") ssh-import <windows-ssh-dir>" >&2
    exit 2
}

# ---------------------------------------------------------------------------
# place — make sure MARGIE lives on the Linux disk
#
# /mnt/c is the Windows disk seen from Linux. Running from there does work, but
# npm has to cross the filesystem bridge for every one of ~40 000 files, and
# vite's file watcher receives no events at all, so the page never reloads.
# Both are slow, confusing failures rather than obvious ones, so the copy is
# made once here instead.
# ---------------------------------------------------------------------------
place() {
    src="$1"
    [ -f "$src/setup.sh" ] || { echo "  Not a MARGIE folder: $src"; exit 1; }

    case "$src" in
        /mnt/*) ;;
        *)  # Already on the Linux disk — nothing to move.
            chmod +x "$src/setup.sh" "$src"/margie-fe/scripts/*.sh 2>/dev/null
            echo "MARGIE_REPO=$src"
            return 0 ;;
    esac

    name="$(basename "$src")"
    [ -n "$name" ] || name="biolab-fe"
    dest="$HOME/$name"

    if [ -f "$dest/setup.sh" ]; then
        echo "  Found MARGIE already installed in Linux at $dest — using that."
    elif [ -d "$src/.git" ] && command -v git >/dev/null 2>&1; then
        echo "  Copying MARGIE from the Windows disk into Linux ($dest)"
        git clone -q "$src" "$dest" || { echo "  Copy failed."; exit 1; }
        # git clone points origin at the Windows folder we copied from, which
        # would make a later `git pull` read the stale Windows copy forever.
        url="$(git -C "$src" remote get-url origin 2>/dev/null)"
        [ -n "$url" ] && git -C "$dest" remote set-url origin "$url"
    else
        echo "  Copying MARGIE from the Windows disk into Linux ($dest)"
        mkdir -p "$dest" || { echo "  Could not create $dest"; exit 1; }
        ( cd "$src" && tar cf - --exclude node_modules --exclude .svelte-kit \
              --exclude .git --exclude build --exclude dist . ) \
            | ( cd "$dest" && tar xf - ) || { echo "  Copy failed."; exit 1; }
    fi

    chmod +x "$dest/setup.sh" "$dest"/margie-fe/scripts/*.sh 2>/dev/null
    echo "MARGIE_REPO=$dest"
}

# ---------------------------------------------------------------------------
# ssh-import — Windows and WSL keep separate home directories, so the SSH key
# already trusted by the HPC is invisible to the Linux side. Copy it across.
#
# Keys only: an existing ~/.ssh/config is left where it is, because a Windows
# one names Windows paths (C:\Users\...\id_ed25519) that mean nothing here and
# would break ssh rather than help it. Nothing already in Linux is overwritten.
# ---------------------------------------------------------------------------
ssh_import() {
    src="$1"
    if [ ! -d "$src" ]; then
        echo "  No .ssh folder on the Windows side ($src) — nothing to copy."
        echo "  MARGIE can make a key for you later; the Register page explains how."
        return 0
    fi

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    copied=0
    for f in "$src"/id_* "$src"/known_hosts; do
        [ -f "$f" ] || continue
        b="$(basename "$f")"
        if [ -e "$HOME/.ssh/$b" ]; then
            echo "  kept the ~/.ssh/$b you already had in Linux"
            continue
        fi
        cp "$f" "$HOME/.ssh/$b" 2>/dev/null || continue
        case "$b" in
            *.pub|known_hosts) chmod 644 "$HOME/.ssh/$b" ;;
            *)                 chmod 600 "$HOME/.ssh/$b" ;;   # ssh refuses a readable key
        esac
        echo "  copied $b"
        copied=$((copied + 1))
    done

    if [ "$copied" = 0 ]; then
        echo "  Nothing new to copy."
    else
        echo "  $copied file(s) copied into Linux's ~/.ssh"
    fi
}

case "${1:-}" in
    place)      [ $# -eq 2 ] || usage; place "$2" ;;
    ssh-import) [ $# -eq 2 ] || usage; ssh_import "$2" ;;
    *)          usage ;;
esac
