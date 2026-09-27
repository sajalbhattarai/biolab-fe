# shared/help-render.sh -- printf helpers that render the --help text (sourced,
# after shared/colors.sh for the C_* colours).
#
# Notation used by every help block (ASCII only):
#
#   <angle-brackets>   a value YOU supply (e.g. <name> = "pfam")
#   [square-brackets]  optional -- may be omitted
#   a | b | c          pick exactly ONE of the listed alternatives
#   $VAR               value comes from pipeline.conf.sh (overridable per-run)
#
# Helpers (all write to stdout):
#
#   _help_hr                      horizontal rule (70 '=')
#   _help_h1   "TITLE"            top-level header  (bold cyan, with rule)
#   _help_h2   "Subtitle"         section header    (bold yellow)
#   _help_label  "--flag"  "..."  left-aligned flag/option entry (green flag)
#   _help_kv     "key"     "..."  generic key/value row (bold cyan key)
#   _help_step   "1."      "..."  numbered step row
#   _help_req    "..."            indented "requires:" line (yellow value)
#   _help_note   "..."            indented dim note line
#   _help_example "cmd" "what it does"
#                                 "$ cmd" line + indented description

_help_hr()      { printf "${C_DIM}======================================================================${C_NC}\n"; }
_help_h1()      { printf "\n${C_BOLD}${C_CYAN}%s${C_NC}\n" "$*"; _help_hr; }
_help_h2()      { printf "\n${C_BOLD}${C_YELLOW}%s${C_NC}\n" "$*"; }
_help_label()   { printf "  ${C_GREEN}%-22s${C_NC} ${C_WHITE}%s${C_NC}\n" "$1" "$2"; }
_help_req()     { printf "    ${C_DIM}requires:${C_NC} ${C_YELLOW}%s${C_NC}\n" "$*"; }
_help_note()    { printf "    ${C_DIM}%s${C_NC}\n" "$*"; }
_help_kv()      { printf "  ${C_CYAN}%-22s${C_NC} ${C_WHITE}%s${C_NC}\n" "$1" "$2"; }
_help_step()    { printf "  ${C_CYAN}%-3s${C_NC} ${C_WHITE}%s${C_NC}\n" "$1" "$2"; }
_help_example() {
    printf "  ${C_DIM}\$${C_NC} ${C_GREEN}%s${C_NC}\n" "$1"
    printf "      ${C_WHITE}%s${C_NC}\n" "$2"
}
