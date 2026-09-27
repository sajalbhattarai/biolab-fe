# help/check-help.sh -- help text for check.sh: topic functions and the
# print_help_check dispatcher. Sourced after shared/colors.sh and shared/help-render.sh.

# ---- main help ----

print_help_check_main() {
    _help_h1 "check.sh -- readiness report for databases and container images"
    printf "  ${C_WHITE}Read-only inspection. Tells you, file by file, what is ready to use,${C_NC}\n"
    printf "  ${C_WHITE}what's missing, what's incomplete, and what's optional. Useful before${C_NC}\n"
    printf "  ${C_WHITE}any ${C_GREEN}./annotate.sh${C_NC} ${C_WHITE}run and after every ${C_GREEN}./setup.sh${C_NC} ${C_WHITE}step.${C_NC}\n"

    _help_h1 "USAGE"
    printf "  ${C_GREEN}./check.sh${C_NC} ${C_WHITE}[SCOPE] [DEPTH]${C_NC}\n"

    _help_h2 "STATUS MARKS"
    _help_kv "${C_GREEN}[OK]${C_NC}"     "present and non-empty -- ready to use"
    _help_kv "${C_RED}[MISS]${C_NC}"     "missing -- run the corresponding ${C_GREEN}./setup.sh${C_NC} step"
    _help_kv "${C_YELLOW}[WARN]${C_NC}"  "incomplete -- exists but some pieces are missing or empty"
    _help_kv "${C_CYAN}[OPT]${C_NC}"     "optional -- absent on purpose, pipeline still works"
    _help_kv "${C_DIM}[?]${C_NC}"        "unknown / not inspected at this verbosity"

    _help_h2 "SCOPE  (default: BOTH)"
    _help_label "--databases"       "report databases only"
    _help_label "--containers"      "report container images only"
    _help_label "--tool <name>"     "restrict to one tool (e.g. ${C_GREEN}pfam${C_NC}, ${C_GREEN}tmbed${C_NC}, ${C_GREEN}llm${C_NC})"

    _help_h2 "DEPTH"
    _help_label "--runtime"         "smoke-test each image's entrypoint  ${C_DIM}(slower)${C_NC}"
    _help_label "-v, --verbose"     "list every key file looked at  ${C_DIM}(noisier)${C_NC}"

    _help_h2 "OPTIONS"
    _help_label "-h, --help [topic]" "show help (see TOPICS below)"

    _help_h2 "HELP TOPICS  (try ${C_GREEN}./check.sh --help <topic>${C_NC})"
    _help_kv "marks"     "what each status symbol means (also shown above)"
    _help_kv "hf"        "HuggingFace status banner for ${C_GREEN}llm${C_NC} model downloads"
    _help_kv "exit"      "exit codes used by ${C_GREEN}check.sh${C_NC}"

    _help_h2 "EXAMPLES"
    _help_example "./check.sh"                          "full report -- databases + containers"
    _help_example "./check.sh --databases"              "databases only"
    _help_example "./check.sh --containers --runtime"   "containers only, smoke-test entrypoints"
    _help_example "./check.sh --tool pfam --verbose"    "deep-dive on pfam, list every file checked"
    _help_example "./check.sh --tool llm"               "check llm model slots + HF venv/token"

    _help_h2 "NOTES"
    printf "  ${C_DIM}*${C_NC} ${C_GREEN}check.sh${C_NC} ${C_WHITE}never modifies anything; safe to run on read-only mounts.${C_NC}\n"
    printf "  ${C_DIM}*${C_NC} ${C_WHITE}Exit code is non-zero only if a REQUIRED artifact is missing or incomplete.${C_NC}\n"
    printf "  ${C_DIM}*${C_NC} ${C_WHITE}The HuggingFace banner is included automatically; see ${C_GREEN}--help hf${C_NC}${C_WHITE}.${C_NC}\n\n"
}

# ---- topic: marks ----

print_help_check_marks() {
    _help_h1 "TOPIC: status marks"
    printf "  ${C_WHITE}Every row in ${C_GREEN}check.sh${C_NC} ${C_WHITE}output begins with one of five marks.${C_NC}\n"
    printf "  ${C_DIM}Note: the live report uses single-char Unicode glyphs (check/cross/etc);${C_NC}\n"
    printf "  ${C_DIM}      this help page uses bracketed ASCII labels for clarity.${C_NC}\n"

    _help_h2 "MEANING"
    _help_kv "${C_GREEN}[OK]${C_NC}     ok"          "the file or directory is present AND non-empty"
    _help_kv "${C_RED}[MISS]${C_NC}   missing"      "the file or directory does not exist at all"
    _help_kv "${C_YELLOW}[WARN]${C_NC}   incomplete" "exists but is empty or part of a multi-file set is gone"
    _help_kv "${C_CYAN}[OPT]${C_NC}    optional"    "absent on purpose -- the pipeline degrades gracefully"
    _help_kv "${C_DIM}[?]${C_NC}      unknown"     "this row wasn't actually inspected (e.g. ${C_GREEN}--runtime${C_NC} skipped)"

    _help_h2 "EXIT CODE IMPACT"
    printf "  ${C_WHITE}Only ${C_RED}[MISS]${C_NC} ${C_WHITE}and ${C_YELLOW}[WARN]${C_NC} ${C_WHITE}entries that are REQUIRED contribute to a non-zero exit.${C_NC}\n"
    printf "  ${C_WHITE}Optional (${C_CYAN}[OPT]${C_NC}${C_WHITE}) absences are always allowed.${C_NC}\n\n"
}

# ---- topic: hf ----

print_help_check_hf() {
    _help_h1 "TOPIC: HuggingFace status banner"
    printf "  ${C_GREEN}check.sh${C_NC} ${C_WHITE}prints a small banner describing the HuggingFace${C_NC}\n"
    printf "  ${C_WHITE}download environment used by ${C_GREEN}llm${C_NC} ${C_WHITE}model downloads.${C_NC}\n"
    printf "  ${C_DIM}(tmbed does NOT need a token -- its model is public.)${C_NC}\n"

    _help_h2 "WHAT IT REPORTS"
    _help_kv "venv"   "is ${C_GREEN}processing/.hf-env/${C_NC} present and usable?"
    _help_kv "token"  "is ${C_GREEN}processing/.hf-env/hf_token${C_NC} present (chmod 600)?"

    _help_h2 "WHEN BOTH ARE MISSING"
    printf "  ${C_WHITE}Run this to create them:${C_NC}\n"
    _help_example "./setup.sh --databases-only --tool llm"   "creates venv + prompts for token"

    _help_h2 "MORE"
    printf "  ${C_WHITE}Full HuggingFace help:  ${C_GREEN}./setup.sh --help hf${C_NC}\n\n"
}

# ---- topic: exit codes ----

print_help_check_exit() {
    _help_h1 "TOPIC: exit codes"
    _help_kv "0" "all required artifacts present and complete"
    _help_kv "1" "one or more required artifacts missing or incomplete"
    _help_kv "2" "invalid command-line usage"
    printf "\n  ${C_WHITE}Optional (${C_CYAN}[OPT]${C_NC}${C_WHITE}) entries never change the exit code.${C_NC}\n\n"
}

# ---- dispatcher ----

print_help_check() {
    case "${1:-main}" in
        main|"")     print_help_check_main ;;
        marks)       print_help_check_marks ;;
        hf)          print_help_check_hf ;;
        exit|codes)  print_help_check_exit ;;
        *)
            print_help_check_main
            printf "\n${C_RED}(unknown help topic: %s)${C_NC}\n" "$1" >&2
            printf "${C_DIM}Available topics: marks, hf, exit${C_NC}\n" >&2
            ;;
    esac
}
