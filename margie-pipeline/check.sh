#!/usr/bin/env bash
# check.sh — prints a read-only readiness report for the reference databases and
# container images, with the fix command for each missing item.
set -euo pipefail

# step 1 of 11 — loads config and helpers, starts the log file
here=$(cd "$(dirname "$0")" && pwd)
. "$here/pipeline.conf.sh"
. "$here/processing/scripts/shared/colors.sh"
. "$here/processing/scripts/shared/help-render.sh"
. "$here/processing/scripts/shared/runtime.sh"
LOG_DIR="${REPO_ROOT}/logs/pre-setup"
. "$here/processing/scripts/shared/logging.sh"
. "$here/processing/scripts/help/check-help.sh"

tag=check
log_invocation "$0" "$@"

# step 2 of 11 — parses the command line (defaults: both checks, no runtime test, terse)
databases=yes containers=yes runtime_test=no verbose=no
tool= need=

usage() { print_help_check "${1:-main}"; }

for arg in "$@"; do
    [ -n "$need" ] && {
        case "$need" in
            tool)       tool="$arg" ;;
            help)       usage "$arg"; exit 0 ;;
        esac
        need=
        continue
    }

    case "$arg" in
        --databases)  containers=no ;;
        --containers) databases=no ;;
        --runtime)    runtime_test=yes ;;
        --tool)       need=tool ;;
        -v|--verbose) verbose=yes ;;
        -h|--help)    need=help ;;
        *) err "unknown option: $arg"; usage >&2; exit 2 ;;
    esac
done

[ "$need" = help ] && { usage; exit 0; }

[ -n "$need" ] && {
    err "--$need needs a name"
    exit 1
}

ok_mark="${C_GREEN}✓${C_NC}"
no_mark="${C_RED}✗${C_NC}"
warn_mark="${C_YELLOW}⚠${C_NC}"
opt_mark="${C_CYAN}–${C_NC}"
unk_mark="${C_DIM}?${C_NC}"

total=0 ok=0 miss=0 inc=0 unk=0 opt=0
missing_detail=() incomplete_detail=() opt_absent_detail=()
bump_total(){ total=$((total+1)); }

# Succeeds when $1 is a non-empty file or a non-empty directory.
present_nonempty() {
    local p=$1
    if   [[ -f "$p" && -s "$p" ]];                                then return 0
    elif [[ -d "$p" ]] && [[ -n "$(ls -A "$p" 2>/dev/null)" ]];   then return 0
    else                                                               return 1
    fi
}

# step 3 of 11 — sentinel files expected in each DB_ROOT/<tool>/ folder
db_sentinels() {
    case "$1" in
        cog)         echo "cddid.tbl Cog_LE cog-24.def.tab cog-24.fun.tab" ;;
        dbcan)       echo "CAZy.dmnd dbCAN.hmm" ;;
        eggnog)      echo "eggnog.db eggnog.taxa.db" ;;
        geneprop)    echo "flatfiles" ;;
        interpro)    echo "interproscan.sh" ;;
        kegg)        echo "ko_list profiles" ;;
        merops)      echo "pepunit.lib merops_scan.lib" ;;
        pfam)        echo "Pfam-A.hmm Pfam-A.hmm.h3i Pfam-A.hmm.dat" ;;
        pgap)        echo "hmm_PGAP.LIB hmm_PGAP.LIB.h3i hmm_PGAP.tsv" ;;
        # merge-rasttk-db.py folds subsystem_mapping.tsv into these two
        # files and deletes it, so that file is not a sentinel.
        rasttk)      echo "seed_database.json seed_database_long.tsv" ;;
        taxonomy)    echo "gtdb_ncbi_crosswalk.tsv" ;;
        tcdb)        echo "tcdb.fasta tcdb.dmnd" ;;
        tigrfam)     echo "TIGRFAMs_15.0_HMM.LIB TIGRFAMs_15.0_HMM.LIB.h3i" ;;
        tmbed)       echo "hub/models--Rostlab--prot_t5_xl_half_uniref50-enc" ;;
        type_strains) echo "type_strain_index.tsv type_strain_genomes.tsv" ;;
        uniprot)     echo "uniprot_sprot.fasta uniprot_sprot.dmnd" ;;
        *) return 1 ;;
    esac
}

row()     { printf '  %b  %-14s  %-9s  %s\n' "$1" "$2" "$3" "$4"; }
opt_row() { printf '  %b  %-22s  %-7s  %s\n' "$1" "$2" "$3" "$4"; }

# step 4 of 11 — detects which container runtimes are installed and working
runtime_name="$(detect_runtime 2>/dev/null || echo unknown)"
docker_ok=0 apptainer_ok=0 apptainer_cmd=
command -v docker &>/dev/null && docker info &>/dev/null && docker_ok=1
# OCI images are checked with docker, podman or Apple's container.
oci="docker"; oci_ok=$docker_ok
case "$runtime_name" in
    podman)    oci=podman;    oci_ok=0; command -v podman &>/dev/null && podman info &>/dev/null && oci_ok=1 ;;
    container) oci=container; oci_ok=0; command -v container &>/dev/null && container system status &>/dev/null && oci_ok=1 ;;
esac
if   command -v apptainer   &>/dev/null; then apptainer_ok=1; apptainer_cmd=apptainer
elif command -v singularity &>/dev/null; then apptainer_ok=1; apptainer_cmd=singularity
fi

# step 5 of 11 — per-item checks; each prints a row and bumps ok / miss / inc / opt
check_db() {
    local tool=$1
    local d="$DB_ROOT/$tool"

    # gtdbtk: any release* subdirectory counts, since the name is version-specific.
    if [[ "$tool" == "gtdbtk" ]]; then
        bump_total
        if [[ ! -d "$d" ]]; then
            row "$no_mark" "$tool" "database" "$d not found"
            missing_detail+=("$tool|database|./setup.sh --databases-only --tool $tool")
            miss=$((miss+1)); return
        fi
        local release_dir
        release_dir=$(find "$d" -maxdepth 1 -type d -name "release*" -print -quit 2>/dev/null || true)
        if [[ -n "$release_dir" ]]; then
            local sz; sz="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
            row "$ok_mark" "$tool" "database" "$d ($(basename "$release_dir"), ${sz})"
            ok=$((ok+1))
        else
            row "$no_mark" "$tool" "database" "no release* directory found under $d"
            missing_detail+=("$tool|database|./setup.sh --databases-only --tool $tool")
            miss=$((miss+1))
        fi
        return
    fi

    # tmbed: any weight file under $d counts, the same test download-tmbed.sh uses.
    if [[ "$tool" == "tmbed" ]]; then
        bump_total
        if [[ ! -d "$d" ]]; then
            row "$no_mark" "$tool" "database" "$d not found"
            missing_detail+=("$tool|database|./setup.sh --databases-only --tool $tool")
            miss=$((miss+1)); return
        fi
        if find "$d" \( -name '*.safetensors' -o -name '*.bin' -o -name '*.pt' \) \
                -print -quit 2>/dev/null | grep -q .; then
            local sz; sz="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
            row "$ok_mark" "$tool" "database" "$d (${sz})"
            ok=$((ok+1))
        else
            row "$no_mark" "$tool" "database" "no ProtT5 weights (*.safetensors/*.bin/*.pt) under $d"
            missing_detail+=("$tool|database|./setup.sh --databases-only --tool $tool")
            miss=$((miss+1))
        fi
        return
    fi

    local sentinels
    if ! sentinels="$(db_sentinels "$tool")"; then
        row "$unk_mark" "$tool" "database" "no key-file list — skipped"
        unk=$((unk+1)); return
    fi
    bump_total
    if [[ ! -d "$d" ]]; then
        row "$no_mark" "$tool" "database" "$d not found"
        missing_detail+=("$tool|database|./setup.sh --databases-only --tool $tool")
        miss=$((miss+1)); return
    fi
    local missing=() ok_files=() f
    for f in $sentinels; do
        if present_nonempty "$d/$f"; then ok_files+=("$f")
        else missing+=("$f"); fi
    done
    local total_n=$(echo "$sentinels" | wc -w | tr -d ' ')
    if [[ ${#missing[@]} -eq 0 ]]; then
        local sz; sz="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
        row "$ok_mark" "$tool" "database" "$d (${sz})"
        ok=$((ok+1))
        if [[ "$verbose" = yes ]]; then
            for f in "${ok_files[@]+"${ok_files[@]+"${ok_files[@]}"}"}"; do printf '        · %s\n' "$f"; done
        fi
    elif [[ ${#missing[@]} -eq $total_n ]]; then
        row "$no_mark" "$tool" "database" "no expected files in $d"
        missing_detail+=("$tool|database|./setup.sh --databases-only --tool $tool")
        miss=$((miss+1))
    else
        row "$warn_mark" "$tool" "database" "incomplete — missing ${#missing[@]}/${total_n}: ${missing[*]}"
        incomplete_detail+=("$tool|database|missing: ${missing[*]}")
        inc=$((inc+1))
    fi
}

check_img() {
    local tool=$1
    if [[ "$runtime_name" == "apptainer" || "$runtime_name" == "singularity" ]]; then
        check_sif "$tool"; return
    fi
    bump_total
    if (( ! oci_ok )); then
        row "$unk_mark" "$tool" "image" "$oci unavailable"
        unk=$((unk+1)); return
    fi
    local image="$REGISTRY/$tool:latest"
    if "$oci" image inspect "$image" &>/dev/null; then
        local sz id detail
        if [[ "$oci" == container ]]; then
            detail="$image"          # Apple's inspect is JSON only, no --format
        else
            sz="$("$oci" image inspect "$image" --format '{{.Size}}' | awk '{printf "%.0f MB", $1/1024/1024}')"
            id="$("$oci" image inspect "$image" --format '{{.Id}}' | awk -F: '{print substr($2,1,12)}')"
            detail="$image  (${id}, ${sz})"
        fi
        if [[ "$runtime_test" = yes ]]; then
            if "$oci" run --rm --entrypoint /bin/true "$image" &>/dev/null; then
                row "$ok_mark" "$tool" "image" "$detail  · runtime ok"; ok=$((ok+1))
            else
                row "$warn_mark" "$tool" "image" "$detail  · runtime FAILED"
                incomplete_detail+=("$tool|image|present but runtime test failed")
                inc=$((inc+1))
            fi
        else
            row "$ok_mark" "$tool" "image" "$detail"; ok=$((ok+1))
        fi
    else
        row "$no_mark" "$tool" "image" "$image not built"
        missing_detail+=("$tool|image|./setup.sh --containers-only --tool $tool")
        miss=$((miss+1))
    fi
}

check_sif() {
    local tool=$1
    local sif="$SIF_DIR/$tool.sif"
    bump_total
    if [[ ! -s "$sif" ]]; then
        row "$no_mark" "$tool" "sif" "$sif not found"
        missing_detail+=("$tool|sif|./setup.sh --containers-only --tool $tool")
        miss=$((miss+1)); return
    fi
    local sz mtime detail
    sz="$(du -h "$sif" | awk '{print $1}')"
    mtime="$(date -r "$sif" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')"
    detail="$sif  (${sz}, ${mtime})"
    if [[ "$runtime_test" = yes && -n "$apptainer_cmd" ]]; then
        if "$apptainer_cmd" exec "$sif" /bin/true &>/dev/null; then
            row "$ok_mark" "$tool" "sif" "$detail  · runtime ok"; ok=$((ok+1))
        else
            row "$warn_mark" "$tool" "sif" "$detail  · runtime FAILED"
            incomplete_detail+=("$tool|sif|present but runtime test failed")
            inc=$((inc+1))
        fi
    else
        row "$ok_mark" "$tool" "sif" "$detail"; ok=$((ok+1))
    fi
}

# Prints "<path>|<kind>" for the first subfolder of $1 holding a usable model.
_find_model_subdir() {
    local parent=$1 sub wc
    for sub in "$parent"/*/; do
        [[ -d "$sub" ]] || continue
        if [[ -f "$sub/adapter_config.json" ]]; then
            printf '%s|lora-adapter\n' "$sub"; return 0
        fi
        if [[ -f "$sub/config.json" ]]; then
            wc=$(find "$sub" -maxdepth 2 \( -name '*.safetensors' -o -name '*.bin' -o -name '*.pth' \) 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$wc" -gt 0 ]]; then
                printf '%s|weights (%s file(s))\n' "$sub" "$wc"; return 0
            fi
        fi
    done
    return 1
}

# Checks one LLM slot: a configured local path, else a known folder under the DB root.
check_llm_slot() {
    local slot=$1
    local val=$2
    local d
    bump_total
    local slot_uc
    slot_uc="$(echo "$slot" | tr '[:lower:]' '[:upper:]')"

    # A local path takes precedence.
    if [[ -n "$val" && ( "$val" == /* || "$val" == ~* ) ]]; then
        local rv="${val/#~/$HOME}"
        if present_nonempty "$rv"; then
            local sz; sz="$(du -sh "$rv" 2>/dev/null | awk '{print $1}')"
            opt_row "$ok_mark" "llm/$slot" "llm" "$rv  ($sz)"; ok=$((ok+1))
        else
            opt_row "$no_mark" "llm/$slot" "llm" "$rv not found"
            missing_detail+=("llm/$slot|llm|local path $rv does not exist")
            miss=$((miss+1))
        fi
        return
    fi

    # otherwise look on disk under one of the known dir names for this slot
    local root="${LLM_ROOT:-$DB_ROOT/llm}"
    local -a candidates=()
    case "$slot" in
        base)     candidates=("$root/base"     "$root/base-model") ;;
        trained)  candidates=("$root/trained"  "$root/fused-model" "$root/trained-model") ;;
        adapters) candidates=("$root/adapters" "$root/lora" "$root/peft") ;;
        *)        candidates=("$root/$slot") ;;
    esac

    d=
    local c
    for c in "${candidates[@]+"${candidates[@]}"}"; do
        [[ -d "$c" && -n "$(ls -A "$c" 2>/dev/null)" ]] && { d="$c"; break; }
    done

    if [[ -z "$d" ]]; then
        if [[ -n "$val" ]]; then
            opt_row "$opt_mark" "llm/$slot" "llm" "pending — '$val' not yet downloaded"
            opt_absent_detail+=("llm/$slot|llm|./setup.sh --databases-only --tool llm  (downloads $val)")
        else
            opt_row "$opt_mark" "llm/$slot" "llm" "absent — searched: ${candidates[*]#$root/}"
            opt_absent_detail+=("llm/$slot|llm|place model under $root/$slot/  or set LLM_${slot_uc} in pipeline.conf.sh")
        fi
        opt=$((opt+1))
        return
    fi

    local found
    if found="$(_find_model_subdir "$d")"; then
        local name="$(basename "${found%|*}")" type="${found#*|}" sz
        sz="$(du -sh "${found%|*}" 2>/dev/null | awk '{print $1}')"
        opt_row "$ok_mark" "llm/$slot" "llm" "$(basename "$d")/$name  ($type, $sz)"; ok=$((ok+1))
    else
        # Content without a recognisable model is reported as incomplete.
        local sz; sz="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
        opt_row "$warn_mark" "llm/$slot" "llm" "$(basename "$d")/  present ($sz) but no recognisable weights/adapters"
        incomplete_detail+=("llm/$slot|llm|$d exists but no valid weights/adapter_config.json found")
        inc=$((inc+1))
    fi
}

check_tmbed_models() {
    : # unused; check_db tmbed covers tmbed
}

# step 6 of 11 — picks the items to check: every db in all_dbs (minus llm and
# pangenome) and every image in all_tools, or the one given with --tool.
selected_db=() selected_img=()
if [[ "$tool" == "llm" ]]; then
    containers=no
elif [[ -n "$tool" ]]; then
    selected_db=("$tool")
    selected_img=("$tool")
else
    # GTDB-Tk's image and database count only when RUN_GTDBTK is on.
    for db in "${all_dbs[@]+"${all_dbs[@]}"}"; do
        [[ "$db" == "llm" || "$db" == "pangenome" ]] && continue
        [[ "$db" == "gtdbtk" && "${RUN_GTDBTK:-0}" != "1" ]] && continue
        selected_db+=("$db")
    done
    selected_img=( "${all_tools[@]+"${all_tools[@]}"}" )
    [[ "${RUN_GTDBTK:-0}" == "1" ]] && selected_img+=(gtdbtk)
fi

# step 7 of 11 — prints the banner (repo, db root, runtime, image source)
printf '\n%bRepo     :%b  %s\n' "$C_CYAN" "$C_NC" "$here"
printf '%bDB root  :%b  %s\n'   "$C_CYAN" "$C_NC" "$DB_ROOT"
if [[ "$runtime_name" == "apptainer" || "$runtime_name" == "singularity" ]]; then
    printf '%bImages   :%b  SIF files under %s\n' "$C_CYAN" "$C_NC" "$SIF_DIR"
else
    printf '%bImages   :%b  %s/<tool>:latest\n' "$C_CYAN" "$C_NC" "$REGISTRY"
fi
printf '%bRuntime  :%b  %s' "$C_CYAN" "$C_NC" "$runtime_name"
(( docker_ok ))    && printf '  %b[docker ok]%b'    "$C_GREEN"  "$C_NC"
[[ "$oci" != docker ]] && (( oci_ok )) && printf '  %b[%s ok]%b' "$C_GREEN" "$oci" "$C_NC"
(( apptainer_ok )) && printf '  %b[apptainer ok]%b' "$C_GREEN"  "$C_NC"
echo

# HuggingFace download env status (used by --tool llm)
hf_env_dir="$here/processing/.hf-env"
hf_token_path="$hf_env_dir/hf_token"
hf_env_state="absent"
[[ -x "$hf_env_dir/bin/hf" || -x "$hf_env_dir/bin/huggingface-cli" ]] && hf_env_state="ready"
hf_token_state="none"
[[ -s "$hf_token_path" ]] && hf_token_state="cached"
printf '%bHF env   :%b  %s  (venv: %s, token: %s)\n' \
    "$C_CYAN" "$C_NC" "$hf_env_dir" "$hf_env_state" "$hf_token_state"
if [[ "$hf_env_state" != "ready" || "$hf_token_state" != "cached" ]]; then
    printf '            %bonly needed if you use llm (interpretation step)%b\n' \
        "$C_DIM" "$C_NC"
fi

# step 8 of 11 — checks each database and the optional llm model slots
if [[ "$databases" = yes ]]; then
    echo
    printf '%bDatabases%b\n' "$C_CYAN" "$C_NC"
    printf '  %-3s %-14s  %-9s  %s\n' "" "TOOL" "KIND" "DETAIL"
    for t in "${selected_db[@]+"${selected_db[@]+"${selected_db[@]}"}"}"; do check_db "$t"; done

    if [[ -z "$tool" || "$tool" == "llm" ]]; then
        echo
        printf '  %b-- Optional llm interpretation model (pipeline degrades gracefully if absent) --%b\n' "$C_DIM" "$C_NC"
        printf '  %-3s %-22s  %-7s  %s\n' "" "COMPONENT" "KIND" "DETAIL"
        check_llm_slot base     "${LLM_BASE_MODEL:-}"
        check_llm_slot trained  "${LLM_TRAINED_MODEL:-}"
        check_llm_slot adapters "${LLM_TRAINED_ADAPTERS:-}"
    fi
fi

# step 9 of 11 — checks each container image (OCI or SIF, per step 4)
if [[ "$containers" = yes ]]; then
    echo
    printf '%bContainer images%b\n' "$C_CYAN" "$C_NC"
    printf '  %-3s %-14s  %-9s  %s\n' "" "TOOL" "KIND" "DETAIL"
    for t in "${selected_img[@]+"${selected_img[@]+"${selected_img[@]}"}"}"; do check_img "$t"; done
fi

echo
# step 10 of 11 — prints totals (non-zero buckets only)
printf '%bSummary%b\n' "$C_CYAN" "$C_NC"
printf '  Total checked    : %d\n' "$total"
printf '  %b ok               : %d\n' "$ok_mark"   "$ok"
(( inc  > 0 )) && printf '  %b incomplete       : %d\n' "$warn_mark" "$inc"
(( miss > 0 )) && printf '  %b missing          : %d\n' "$no_mark"   "$miss"
(( unk  > 0 )) && printf '  %b unknown          : %d\n' "$unk_mark"  "$unk"
(( opt  > 0 )) && printf '  %b optional absent  : %d\n' "$opt_mark"  "$opt"

# step 11 of 11 — prints the fix command for each missing or incomplete item
if (( ${#missing_detail[@]} + ${#incomplete_detail[@]} > 0 )); then
    echo
    printf '%bAction required%b\n' "$C_CYAN" "$C_NC"
    printf '  %-3s %-22s  %-9s  %s\n' "" "TOOL" "KIND" "FIX"
    local_render() {
        local mark=$1; shift
        for d in "$@"; do
            IFS='|' read -r _t _k _a <<<"$d"
            printf '  %b  %-22s  %-9s  %s\n' "$mark" "$_t" "$_k" "$_a"
        done
    }
    (( ${#missing_detail[@]}    )) && local_render "$no_mark"   "${missing_detail[@]+"${missing_detail[@]}"}"
    (( ${#incomplete_detail[@]} )) && local_render "$warn_mark" "${incomplete_detail[@]+"${incomplete_detail[@]}"}"
fi

if (( ${#opt_absent_detail[@]} > 0 )); then
    echo
    printf '%bLarge models — optional, not required to run the pipeline%b\n' "$C_CYAN" "$C_NC"
    for d in "${opt_absent_detail[@]+"${opt_absent_detail[@]}"}"; do
        IFS='|' read -r _t _k _a <<<"$d"
        printf '  %b  %-22s  %s\n' "$opt_mark" "$_t" "$_a"
    done
    echo
    printf '  Notes: Base LLM are several GB each.\n'
    printf '         HuggingFace authentication (free account + token) may be required.\n'
fi
echo

(( miss > 0 || inc > 0 )) && exit 1 || exit 0
