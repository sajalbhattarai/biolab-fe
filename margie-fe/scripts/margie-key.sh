#!/usr/bin/env bash
#
# margie-key -- passwordless SSH to the HPC for MARGIE.
#
#   margie-key.sh status  [KEY]                  is there a key here? prints its public half
#   margie-key.sh create  [KEY]                  make one (ed25519, no passphrase)
#   margie-key.sh install HOST [KEY] [SOCKET]    add its public half to HOST's authorized_keys
#   margie-key.sh verify  HOST [KEY]             can HOST be reached with the key alone?
#
# KEY defaults to ~/.ssh/margie_ed25519, a MARGIE-only key tagged "margie@<host>".
# SOCKET is a signed-in ssh master connection that install reuses.
# MARGIE_SSH_OPTS adds options to every ssh call.
#
set -u

KEY_DEFAULT="$HOME/.ssh/margie_ed25519"
read -r -a EXTRA <<< "${MARGIE_SSH_OPTS:-}"

die() { echo "$*" >&2; exit 1; }

cmd="${1:-}"
[ -n "$cmd" ] || die "usage: margie-key.sh status|create|install|verify ..."
shift

case "$cmd" in
    status)
        key="${1:-$KEY_DEFAULT}"
        key="${key/#\~/$HOME}"
        [ -f "$key" ] && [ -f "$key.pub" ] || { echo "none $key"; exit 3; }
        echo "found $key"
        cat "$key.pub"
        ;;

    create)
        key="${1:-$KEY_DEFAULT}"
        key="${key/#\~/$HOME}"
        if [ -f "$key" ]; then
            echo "exists $key"
            exit 0
        fi
        mkdir -p "$(dirname "$key")" && chmod 700 "$(dirname "$key")"
        # No passphrase, so the backend can use the key unattended.
        ssh-keygen -q -t ed25519 -N '' -C "margie@$(hostname -s 2>/dev/null || hostname)" -f "$key" \
            || die "ssh-keygen could not make $key"
        echo "created $key"
        ;;

    install)
        host="${1:-}"
        [ -n "$host" ] || die "install needs the HPC, as user@host"
        key="${2:-$KEY_DEFAULT}"
        key="${key/#\~/$HOME}"
        socket="${3:-}"
        [ -f "$key.pub" ] || die "no public key at $key.pub -- run: margie-key.sh create"
        via=()
        [ -n "$socket" ] && via=(-S "$socket")
        # Runs under sh whatever the remote login shell; the key arrives on stdin.
        # shellcheck disable=SC2016
        remote='sh -c '"'"'umask 077; mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/authorized_keys" && chmod 700 "$HOME/.ssh" && chmod 600 "$HOME/.ssh/authorized_keys" || exit 1; read k; if grep -qxF "$k" "$HOME/.ssh/authorized_keys"; then echo already; else printf "%s\n" "$k" >> "$HOME/.ssh/authorized_keys" && echo added; fi'"'"
        ssh ${EXTRA[@]+"${EXTRA[@]}"} ${via[@]+"${via[@]}"} -o ConnectTimeout=20 -o StrictHostKeyChecking=no "$host" "$remote" < "$key.pub" \
            || die "could not add the key to $host"
        ;;

    verify)
        host="${1:-}"
        [ -n "$host" ] || die "verify needs the HPC, as user@host"
        key="${2:-$KEY_DEFAULT}"
        key="${key/#\~/$HOME}"
        [ -f "$key" ] || die "no key at $key"
        # Opens a fresh connection using only this key, with no master socket or prompts.
        ssh ${EXTRA[@]+"${EXTRA[@]}"} -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
            -o PreferredAuthentications=publickey -o ControlMaster=no -o ControlPath=none \
            -o ConnectTimeout=20 -o StrictHostKeyChecking=no "$host" true 2>/dev/null \
            && echo "works" || { echo "refused"; exit 4; }
        ;;

    *) die "unknown command: $cmd" ;;
esac
