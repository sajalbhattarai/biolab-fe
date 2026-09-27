# help/annotate-help.sh -- help text for annotate.sh: topic functions and the
# print_help_annotate dispatcher. Sourced after shared/colors.sh and shared/help-render.sh.

# ---- main help (--help with no topic) ----

print_help_annotate_main() {
    _help_h1 "annotate.sh -- run the annotation pipeline on input genomes"
    printf "  ${C_WHITE}Runs one or more annotation tools over every ${C_GREEN}*.fna${C_NC} ${C_WHITE}assembly in${C_NC}\n"
    printf "  ${C_GREEN}\$INPUT_RASTTK${C_NC} ${C_WHITE}(default ${C_GREEN}\$REPO_ROOT/input${C_NC}${C_WHITE}). Each tool runs inside its${C_NC}\n"
    printf "  ${C_WHITE}own container; per-tool results land under ${C_GREEN}\$OUTPUT_ROOT/<tool>/${C_NC}${C_WHITE}.${C_NC}\n"

    _help_h1 "AT A GLANCE"
    printf "  ${C_GREEN}+--------------+${C_NC}     ${C_GREEN}+--------------+${C_NC}     ${C_GREEN}+--------------+${C_NC}\n"
    printf "  ${C_GREEN}|${C_NC} ${C_BOLD}${C_CYAN}input/${C_NC}       ${C_GREEN}|${C_NC} --> ${C_GREEN}|${C_NC} ${C_BOLD}${C_CYAN}tier-1 tool${C_NC}  ${C_GREEN}|${C_NC} --> ${C_GREEN}|${C_NC} ${C_BOLD}${C_CYAN}output/${C_NC}      ${C_GREEN}|${C_NC}\n"
    printf "  ${C_GREEN}|${C_NC} ${C_WHITE}*.fna${C_NC}        ${C_GREEN}|${C_NC}     ${C_GREEN}|${C_NC} ${C_WHITE}container${C_NC}    ${C_GREEN}|${C_NC}     ${C_GREEN}|${C_NC} ${C_WHITE}<tool>/${C_NC}      ${C_GREEN}|${C_NC}\n"
    printf "  ${C_GREEN}+--------------+${C_NC}     ${C_GREEN}+--------------+${C_NC}     ${C_GREEN}+--------------+${C_NC}\n"
    printf "       ${C_DIM}per genome           one of 19              raw + processed${C_NC}\n"

    _help_h1 "USAGE"
    printf "  ${C_GREEN}./annotate.sh${C_NC} ${C_WHITE}[OPTIONS]${C_NC}\n"

    _help_h2 "PLACEHOLDER LEGEND"
    _help_kv "<name>" "a tool name (e.g. ${C_GREEN}pfam${C_NC}, ${C_GREEN}kegg${C_NC}, ${C_GREEN}rasttk${C_NC})"

    _help_h2 "OPTIONS"
    _help_label "(no flag)"        "run every tier-1 tool in the canonical order"
    _help_label "--tool <name>"    "run only this tool (repeat to chain a custom order)"
    _help_label "--list"           "show every chosen tool's resolved settings; do NOT run"
    _help_label "--prepare-only"   "GTDB-Tk (if ${C_GREEN}RUN_GTDBTK=1${C_NC}) + genome table, then stop"
    _help_label "--genes-only"     "call genes and stop; no annotation tools run"
    _help_label "-h, --help [topic]" "show help (see TOPICS below)"

    _help_h2 "HELP TOPICS  (try ${C_GREEN}./annotate.sh --help <topic>${C_NC})"
    _help_kv "tools"    "the full tier-1 tool list and what each does"
    _help_kv "order"    "default ordering rules and how to customize"
    _help_kv "outputs"  "where results land and the raw/processed convention"

    _help_h2 "LICENCE PRE-FLIGHT  (restricted-use tools are auto-skipped)"
    printf "  ${C_DIM}Before running, ${C_GREEN}annotate.sh${C_NC} ${C_DIM}checks each tool's licence acceptance${C_NC}\n"
    printf "  ${C_DIM}status. Restricted tools (${C_GREEN}merops tcdb tmbed interpro phobius psortb${C_NC}${C_DIM})${C_NC}\n"
    printf "  ${C_DIM}are SKIPPED if no acceptance is on record. Accepted tools get a${C_NC}\n"
    printf "  ${C_DIM}clearly-marked banner in the log showing the source (pipeline.conf /${C_NC}\n"
    printf "  ${C_DIM}cli-flag / interactive-setup), the timestamp, and your declared use.${C_NC}\n"
    printf "  ${C_DIM}To enable a skipped tool: edit ${C_GREEN}pipeline.conf.sh${C_NC} ${C_DIM}or re-run ${C_GREEN}./setup.sh${C_NC}${C_DIM}.${C_NC}\n\n"

    _help_h2 "EXAMPLES"
    _help_example "./annotate.sh"                            "run every tier-1 tool (default)"
    _help_example "./annotate.sh --tool pfam"                "run pfam only"
    _help_example "./annotate.sh --tool pfam --tool kegg"    "run pfam then kegg, in that order"
    _help_example "./annotate.sh --list"                     "preview every tool's resolved config without running"
    _help_example "./annotate.sh --list --tool pfam"         "preview just pfam's config"
    _help_example "THREADS=16 ./annotate.sh --tool kegg"     "one-shot thread override for this run"

    _help_h2 "PREREQUISITES"
    _help_step "1." "container images present  ${C_DIM}(see ${C_GREEN}./setup.sh --containers-only${C_NC}${C_DIM})${C_NC}"
    _help_step "2." "reference databases ready ${C_DIM}(see ${C_GREEN}./setup.sh --databases-only${C_NC}${C_DIM})${C_NC}"
    _help_step "3." "at least one ${C_GREEN}*.fna${C_NC} file under ${C_GREEN}\$INPUT_RASTTK${C_NC}"
    printf "\n  ${C_WHITE}Verify with: ${C_GREEN}./check.sh${C_NC}\n"

    _help_h2 "CONFIG"
    printf "  ${C_WHITE}Tool lists, paths, and per-tool overrides live in${C_NC}\n"
    printf "  ${C_GREEN}./pipeline.conf.sh${C_NC}${C_WHITE}. Notable variables:${C_NC}\n"
    _help_kv "all_tier1_tools" "default ordered list of tools annotate.sh runs"
    _help_kv "INPUT_RASTTK"    "where annotate.sh looks for input ${C_GREEN}*.fna${C_NC} files"
    _help_kv "OUTPUT_ROOT"     "parent of every per-tool output directory"
    _help_kv "THREADS"         "CPU threads passed to each tool"
    printf "\n"
}

# ---- topic: tools ----

print_help_annotate_tools() {
    _help_h1 "TOPIC: tier-1 annotation tools"
    printf "  ${C_WHITE}Every tool is invoked by ${C_GREEN}processing/scripts/run-individual-containers/run-<tool>.sh${C_NC}${C_WHITE}.${C_NC}\n"
    printf "  ${C_WHITE}All tools accept the same env-var conventions from ${C_GREEN}pipeline.conf.sh${C_NC}${C_WHITE}.${C_NC}\n"

    _help_h2 "GENE CALLER  (always first, per genome -- see input/genomes.tsv)"
    _help_kv "rasttk"   "RAST-tk -- gene calling + base annotation; needs domain AND genetic code"
    _help_kv "prodigal" "Prodigal -- gene calling for genomes without a known genetic code"

    _help_h2 "FUNCTIONAL ANNOTATION  (12)"
    _help_kv "kegg"     "KEGG Orthology assignment via KofamScan"
    _help_kv "cog"      "Clusters of Orthologous Groups (RPS-BLAST)"
    _help_kv "pfam"     "Protein domain families (HMMER hmmsearch)"
    _help_kv "pgap"     "NCBI Prokaryotic Genome Annotation HMMs"
    _help_kv "tigrfam"  "TIGRfam HMM library"
    _help_kv "dbcan"    "Carbohydrate-active enzymes (HMM + DIAMOND)"
    _help_kv "eggnog"   "Orthology + functional annotation (eggNOG-mapper)"
    _help_kv "merops"   "Peptidase classification (DIAMOND vs MEROPS)"
    _help_kv "tcdb"     "Transporter Classification DB (DIAMOND)"
    _help_kv "uniprot"  "UniProt-SwissProt reference search (DIAMOND)"
    _help_kv "interpro" "InterProScan signatures (multi-engine)"
    _help_kv "geneprop" "EBI Genome Properties (HMMER)"

    _help_h2 "ENVELOPE  (automatic, before the gram-dependent tools)"
    _help_kv "envelope" "diderm / monoderm / archaea from tigrfam, pgap, pfam, uniprot hits"

    _help_h2 "LOCALIZATION & TOPOLOGY  (4)"
    _help_kv "psortb"   "Subcellular localization (uses the envelope call)"
    _help_kv "deepsig"  "Signal peptide prediction (uses the envelope call)"
    _help_kv "tmbed"    "Transmembrane topology (ProtT5-based)"
    _help_kv "phobius"  "Combined signal-peptide / TM prediction"

    _help_h2 "STRUCTURAL  (1)"
    _help_kv "operon"    "Operon structure prediction (UniOP)  ${C_DIM}-- always runs; scoring reads it${C_NC}"

    _help_h2 "PER-GENOME RESULTS  (after each genome's tools)"
    printf "  ${C_GREEN}consolidation${C_NC}${C_WHITE}, ${C_GREEN}labeling${C_NC}${C_WHITE}, ${C_GREEN}scoring${C_NC}${C_WHITE}, ${C_GREEN}fingerprint${C_NC}${C_WHITE}, evidence, viewer, figures${C_NC}\n"
    printf "  ${C_WHITE}margie-backend's host scripts (processing/host-scripts/), run by${C_NC}\n"
    printf "  ${C_GREEN}processing/scripts/run-individual-containers/run-meta.sh${C_NC}${C_WHITE} into output/genomes/<organism>/.${C_NC}\n\n"
}

# ---- topic: order ----

print_help_annotate_order() {
    _help_h1 "TOPIC: execution order"
    printf "  ${C_GREEN}annotate.sh${C_NC} ${C_WHITE}runs the chosen tools sequentially. ${C_GREEN}set -e${C_NC} ${C_WHITE}is on,${C_NC}\n"
    printf "  ${C_WHITE}so the first failure aborts the whole run.${C_NC}\n"

    _help_h2 "DEFAULT ORDER  (used when no ${C_GREEN}--tool${C_NC} is given)"
    printf "  ${C_GREEN}rasttk${C_NC}${C_WHITE}|${C_NC}${C_GREEN}prodigal${C_NC} -> ${C_WHITE}kegg -> cog -> pfam -> pgap -> tigrfam -> dbcan -> eggnog ->${C_NC}\n"
    printf "  ${C_WHITE}merops -> tcdb -> uniprot -> interpro -> geneprop -> tmbed ->${C_NC}\n"
    printf "  ${C_WHITE}phobius -> operon -> ${C_GREEN}envelope${C_NC} ${C_WHITE}-> psortb -> deepsig -> signalp4${C_NC}\n\n"
    printf "  ${C_WHITE}This order is hard-coded as ${C_GREEN}annotation_tools_default${C_NC} ${C_WHITE}near the top of${C_NC}\n"
    printf "  ${C_GREEN}annotate.sh${C_NC}${C_WHITE}. Gene calling is always first because every downstream tool${C_NC}\n"
    printf "  ${C_WHITE}consumes its ${C_GREEN}*.faa${C_NC} ${C_WHITE}output; psortb, deepsig and signalp4 always follow${C_NC}\n"
    printf "  ${C_GREEN}envelope${C_NC}${C_WHITE}, and selecting one of them also runs tigrfam, pgap, pfam, uniprot.${C_NC}\n"

    _help_h2 "CUSTOM ORDER"
    printf "  ${C_WHITE}Pass ${C_GREEN}--tool${C_NC} ${C_WHITE}once per stage. Tools run in the exact order given:${C_NC}\n"
    _help_example "./annotate.sh --tool pfam --tool kegg" "gene calling -> pfam -> kegg"

    _help_h2 "WHY SEQUENTIAL?"
    printf "  ${C_WHITE}Each tool is itself CPU-multithreaded via ${C_GREEN}THREADS${C_NC}${C_WHITE}. Running them in${C_NC}\n"
    printf "  ${C_WHITE}series keeps the host predictable; for parallelism across organisms,${C_NC}\n"
    printf "  ${C_WHITE}submit one job per organism (see ${C_GREEN}accessory-files/slurm/annotate.slurm${C_NC}${C_WHITE}).${C_NC}\n\n"
}

# ---- topic: outputs ----

print_help_annotate_outputs() {
    _help_h1 "TOPIC: output layout"
    printf "  ${C_WHITE}Every tool writes under ${C_GREEN}\$OUTPUT_ROOT/<tool>/<organism>/${C_NC}${C_WHITE}, split into${C_NC}\n"
    printf "  ${C_GREEN}raw/${C_NC} ${C_WHITE}(untouched container output) and ${C_GREEN}processed/${C_NC} ${C_WHITE}(normalised TSV).${C_NC}\n"

    _help_h2 "LAYOUT"
    printf "  ${C_GREEN}\$OUTPUT_ROOT/${C_NC}\n"
    printf "  ${C_DIM}|--${C_NC} ${C_GREEN}rasttk/${C_NC}\n"
    printf "  ${C_DIM}|   |--${C_NC} <organism>/         ${C_DIM}# RASTtk or Prodigal (gene_caller.txt says which)${C_NC}\n"
    printf "  ${C_DIM}|       |--${C_NC} ${C_GREEN}gene_calls/${C_NC} ${C_DIM}# genome.faa .gff .ffn .fna${C_NC}\n"
    printf "  ${C_DIM}|       |--${C_NC} ${C_GREEN}raw/${C_NC}\n"
    printf "  ${C_DIM}|       \`--${C_NC} ${C_GREEN}processed/${C_NC}\n"
    printf "  ${C_DIM}|--${C_NC} ${C_GREEN}pfam/<organism>/{raw,processed}/${C_NC}\n"
    printf "  ${C_DIM}|--${C_NC} ${C_GREEN}kegg/<organism>/{raw,processed}/${C_NC}\n"
    printf "  ${C_DIM}|--${C_NC} ${C_GREEN}...${C_NC}\n"
    printf "  ${C_DIM}\`--${C_NC} ${C_GREEN}genomes/<organism>/${C_NC}   ${C_DIM}# per-genome results (margie-backend layout)${C_NC}\n"

    _help_h2 "POST-PROCESSING"
    printf "  ${C_WHITE}After a tool's container exits, any ${C_GREEN}TOOL_<name>_POSTPROC${C_NC} ${C_WHITE}from${C_NC}\n"
    printf "  ${C_GREEN}pipeline.conf.sh${C_NC} ${C_WHITE}runs (default: ${C_GREEN}rasttk${C_NC} ${C_WHITE}enriches its TSV with 23${C_NC}\n"
    printf "  ${C_WHITE}SEED columns). Disable with ${C_GREEN}TOOL_rasttk_POSTPROC=${C_NC}${C_WHITE}.${C_NC}\n"

    _help_h2 "LOGS"
    printf "  ${C_WHITE}Each invocation appends a timestamped log to ${C_GREEN}\$REPO_ROOT/logs/${C_NC}${C_WHITE}.${C_NC}\n"
    printf "  ${C_WHITE}Look for ${C_GREEN}annotate-YYYYMMDD-HHMMSS-<pid>.log${C_NC}${C_WHITE}.${C_NC}\n\n"
}

# ---- dispatcher ----

print_help_annotate() {
    case "${1:-main}" in
        main|"")          print_help_annotate_main ;;
        tools)            print_help_annotate_tools ;;
        order)            print_help_annotate_order ;;
        outputs|output)   print_help_annotate_outputs ;;
        *)
            print_help_annotate_main
            printf "\n${C_RED}(unknown help topic: %s)${C_NC}\n" "$1" >&2
            printf "${C_DIM}Available topics: tools, order, outputs${C_NC}\n" >&2
            ;;
    esac
}
