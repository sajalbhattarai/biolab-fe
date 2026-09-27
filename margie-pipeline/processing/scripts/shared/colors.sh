# shared/colors.sh -- terminal colour variables and log helpers (sourced, not run).
# Bright bold colours read on light and dark backgrounds; they turn off when
# stdout is not a TTY or NO_COLOR is set.

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    # $'...' stores the real ESC byte, so the codes also work inside a %s argument.
    C_RED=$'\033[1;91m'
    C_GREEN=$'\033[1;92m'
    C_YELLOW=$'\033[1;93m'
    C_BLUE=$'\033[1;94m'
    C_MAGENTA=$'\033[1;95m'
    C_CYAN=$'\033[1;96m'
    C_WHITE=$'\033[1;97m'
    C_BOLD=$'\033[1m'
    # Plain white instead of dim, which some terminals render nearly invisible.
    C_DIM=$'\033[0;37m'
    C_NC=$'\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
    C_MAGENTA=''; C_CYAN=''; C_WHITE=''; C_BOLD=''; C_DIM=''; C_NC=''
fi

# Caller may set tag="<phase>"; defaults to the basename of the calling script.
_tag() { echo "${tag:-$(basename "${BASH_SOURCE[1]:-${0}}" .sh)}"; }

log()  { echo -e "${C_CYAN}[$(_tag)]${C_NC} $*"; }
ok()   { echo -e "${C_GREEN}[$(_tag)]${C_NC} $*"; }
warn() { echo -e "${C_YELLOW}[$(_tag)]${C_NC} $*"; }
err()  { echo -e "${C_RED}[$(_tag)]${C_NC} $*" >&2; }
hr()   { printf '%.0s=' {1..70}; echo; }

# double_hr [label] -- prints a two-rule divider between major phases, with an
# optional label between the rules (stdout, so it also reaches the log file).
double_hr() {
    local label=${1:-}
    local bar
    bar=$(printf '%.0s=' {1..72})
    printf '\n%s%s%s\n' "${C_BOLD}${C_CYAN}" "$bar" "${C_NC}"
    if [[ -n "$label" ]]; then
        printf '%s== %s%s\n' "${C_BOLD}${C_CYAN}" "$label" "${C_NC}"
    fi
    printf '%s%s%s\n\n' "${C_BOLD}${C_CYAN}" "$bar" "${C_NC}"
}
