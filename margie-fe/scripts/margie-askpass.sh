#!/usr/bin/env bash
#
# margie-askpass -- SSH_ASKPASS helper: hands each ssh prompt ($1) to the app
# and prints the answer the app sends back through a named pipe.
#
#   MARGIE_ASKPASS_DIR  a private (0700) folder the app watches
#   MARGIE_ASKPASS_POLL 1 on Windows, where the answer arrives as a file
#
# The reply is one line: "A" plus the answer, or "C" to cancel (exits non-zero).
#
set -u
dir="${MARGIE_ASKPASS_DIR:?MARGIE_ASKPASS_DIR is not set}"
id="$$-$RANDOM$RANDOM"
pipe="$dir/answer.$id"

answer() {
    case "$1" in
        A*) printf '%s\n' "${1#A}" ;;
        *)  exit 1 ;;
    esac
}

if [ "${MARGIE_ASKPASS_POLL:-}" = 1 ]; then
    trap 'rm -f "$pipe" "$dir/prompt.$id" "$dir/.prompt.$id"' EXIT
    printf '%s' "${1:-}" > "$dir/.prompt.$id" && mv "$dir/.prompt.$id" "$dir/prompt.$id"
    for _ in $(seq 1 1800); do  # waits up to 15 minutes
        if [ -f "$pipe" ]; then
            IFS= read -r reply < "$pipe"
            rm -f "$pipe"
            answer "$reply"
            exit 0
        fi
        sleep 0.5
    done
    exit 1
fi

mkfifo -m 600 "$pipe" || exit 1
trap 'rm -f "$pipe" "$dir/prompt.$id" "$dir/.prompt.$id"' EXIT

# Opens read-write so the open does not block; the read below waits up to 15 minutes.
exec 3<>"$pipe"

# Writes the prompt, then renames it so the app never sees a partial file.
printf '%s' "${1:-}" > "$dir/.prompt.$id" && mv "$dir/.prompt.$id" "$dir/prompt.$id"

IFS= read -r -t 900 reply <&3 || exit 1
answer "$reply"
