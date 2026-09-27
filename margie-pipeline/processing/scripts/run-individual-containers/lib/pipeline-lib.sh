#!/usr/bin/env bash
# pipeline-lib.sh — shared helpers for the per-tool runners (gene-call folders, tool config,
# GPU choice, container launch, downstream tool loop). Sourced by run-<tool>.sh.
set -euo pipefail

# Per-invocation logging into logs/annotation/ (a no-op when a parent already set it up).
# shellcheck disable=SC1091
: "${LOG_DIR:=${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)}/logs/annotation}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../shared" && pwd)/logging.sh"
log_invocation "$0" "$@"

# MARGIE_ORG_FILTER is an alias for PIPELINE_ORGANISM_FILTER in job submissions.
if [[ -z "${PIPELINE_ORGANISM_FILTER:-}" && -n "${MARGIE_ORG_FILTER:-}" ]]; then
    export PIPELINE_ORGANISM_FILTER="$MARGIE_ORG_FILTER"
fi

# Expands ~ in user-supplied paths.
for _v in INPUT_RASTTK OUTPUT_ROOT DB_ROOT SIF_DIR postproc_dir \
          gene_caller_input gene_caller_output \
          annotation_input annotation_output_root \
          GENOME_RESULTS_DIR MARGIE_SHARED_DIR; do
    eval "$_v=\"\${$_v/#~/$HOME}\""
done
unset _v

# detect_runtime / apptainer_bin: one definition, shared with check.sh and setup.
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../shared" && pwd)/runtime.sh"
# genome_list / genome_field / genome_domain / envelope_flag: the per-genome table.
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../shared" && pwd)/genomes.sh"

# ── Where the gene calls are ──────────────────────────────────────────────────
# Each caller writes $OUTPUT_ROOT/<caller>/<genome>/ (gene_calls/, raw/, processed/,
# gene_caller.txt); later stages locate a genome's calls through the helpers below.

# gene_calls_root <caller> — the folder that caller writes to.
gene_calls_root() { echo "$OUTPUT_ROOT/$1"; }

# gene_call_roots — every caller folder holding at least one genome, in configured order.
gene_call_roots() {
    local c d
    for c in ${GENE_CALLERS:-rasttk prodigal}; do
        d="$OUTPUT_ROOT/$c"
        [[ -d "$d" ]] || continue
        find "$d" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null | grep -q . && echo "$d"
    done
    return 0
}

# genome_calls_dir <genome> — the folder holding the genome's gene calls; non-zero when none exist.
genome_calls_dir() {
    local g="$1" c d
    for c in ${GENE_CALLERS:-rasttk prodigal}; do
        d="$OUTPUT_ROOT/$c/$g"
        [[ -d "$d" ]] && { echo "$d"; return 0; }
    done
    return 1
}

# genome_caller_ran <genome> — the caller named in the genome's folder, or empty.
genome_caller_ran() {
    local d; d="$(genome_calls_dir "$1")" || return 1
    cat "$d/gene_caller.txt" 2>/dev/null || basename "$(dirname "$d")"
}

# migrate_gene_call_folders — moves each genome that sits under the wrong caller folder
# (per its gene_caller.txt) to its own; never overwrites a genome already in place.
migrate_gene_call_folders() {
    local c root g d said
    for c in ${GENE_CALLERS:-rasttk prodigal}; do
        root="$OUTPUT_ROOT/$c"
        [[ -d "$root" ]] || continue
        for d in "$root"/*/; do
            [[ -d "$d" ]] || continue
            g="$(basename "$d")"
            said="$(cat "$d/gene_caller.txt" 2>/dev/null || true)"
            [[ -n "$said" && "$said" != "$(basename "$root")" ]] || continue
            [[ -d "$OUTPUT_ROOT/$said/$g" ]] && continue
            mkdir -p "$OUTPUT_ROOT/$said"
            mv "$d" "$OUTPUT_ROOT/$said/$g"
            echo "[pipeline] $g: gene calls moved to ${OUTPUT_ROOT#$REPO_ROOT/}/$said/ (made by $said)" >&2
        done
        # An empty folder is not a caller that ran.
        rmdir "$root" 2>/dev/null || true
    done
    return 0
}

# reset_if_gene_caller_changed <genome> <rasttk|prodigal>
# Clears the genome's gene calls and every stage's output when the caller changes,
# since feature ids differ between callers and tools would otherwise skip re-running.
reset_if_gene_caller_changed() {
    local g="$1" caller="$2" was d
    was="$(genome_caller_ran "$g" 2>/dev/null || true)"
    [[ -n "$was" ]] || return 0
    [[ "$was" == "$caller" ]] && return 0
    echo "[pipeline] $g: gene caller changed ($was -> $caller); clearing its previous results" >&2
    # Removes the other caller's folder too; every stale result was built on its feature ids.
    for d in "$OUTPUT_ROOT"/*/"$g"; do
        [[ -d "$d" ]] && rm -rf "$d"
    done
    return 0
}

# Resolves TOOL_<name>_<key>, with a default.
_lookup() { local var="$1" def="$2"; echo "${!var:-$def}"; }
tool_image()    { _lookup "TOOL_${1}_IMAGE"    "$REGISTRY/$1:latest"; }
tool_output()   { _lookup "TOOL_${1}_OUTPUT"   "$annotation_output_root/$1"; }
tool_postproc() { _lookup "TOOL_${1}_POSTPROC" ""; }
tool_threads() {
    local upper
    upper="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
    _lookup "TOOL_${upper}_THREADS" "$THREADS"
}
tool_db() {
    local v; v="$(_lookup "TOOL_${1}_DB" "$DB_ROOT/$1")"
    [[ "$v" == /* ]] && echo "$v" || echo "$DB_ROOT/$v"
}
tool_input_override() { _lookup "TOOL_${1}_INPUT" ""; }
tool_apps()         { _lookup "TOOL_${1}_APPS"  ""; }

# tool_use_gpu <tool> — returns 0 when the tool should get GPU flags: TOOL_<TOOL>_GPU (1/0)
# wins; otherwise a tool in gpu_capable_tools follows USE_GPU (auto probes nvidia-smi, 1 always, 0 never).
tool_use_gpu() {
    local tool="$1"
    local upper; upper="$(printf '%s' "$tool" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
    local per_tool_var="TOOL_${upper}_GPU"

    # Explicit per-tool override.
    if [[ -n "${!per_tool_var+x}" ]]; then
        [[ "${!per_tool_var}" == "1" || "${!per_tool_var}" == "yes" ]]
        return
    fi

    # gpu_capable_tools comes from pipeline.conf.sh.
    local capable=0
    local t; for t in "${gpu_capable_tools[@]-}"; do
        [[ "$t" == "$tool" ]] && { capable=1; break; }
    done
    (( capable == 0 )) && return 1   # not a GPU-capable tool

    # A capable tool follows USE_GPU.
    case "${USE_GPU:-auto}" in
        1|yes|true)  return 0 ;;
        0|no|false)  return 1 ;;
        auto)
            # nvidia-smi success means a GPU is present.
            nvidia-smi --query-gpu=name --format=csv,noheader >/dev/null 2>&1
            return
            ;;
        *)
            echo "[pipeline] WARN: unknown USE_GPU='${USE_GPU}'; treating as 0" >&2
            return 1
            ;;
    esac
}

# run_container <image_ref> <cmd...> — runs a tool container with the detected runtime.
# The caller sets MOUNTS=("HOST:CONTAINER:MODE" ...) and, for GPU, USE_GPU_FOR_RUN=1.
MOUNTS=()
USE_GPU_FOR_RUN=0
run_container() {
    local image="$1"; shift
    local rt; rt="$(detect_runtime)"

    if [[ "$rt" == "docker" || "$rt" == "podman" || "$rt" == "container" ]]; then
        # docker, podman and Apple's container share the run --rm / -e / -v flags; "$rt" is the command.
        if [[ "$rt" == "container" ]] && ! container system status >/dev/null 2>&1; then
            echo "[pipeline] ERROR: Apple's container service is not running. Start it with: container system start" >&2
            return 1
        fi
        # Uses a local image without --platform (it may be single-arch); pulls only when absent.
        local -a plat=()
        if "$rt" image inspect "$image" >/dev/null 2>&1; then
            # Apple's container still needs --platform for the amd64-only tools on Apple silicon.
            if [[ "$rt" == "container" ]]; then
                local arch
                arch="$(container image inspect "$image" 2>/dev/null \
                        | sed -n 's/.*"architecture"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
                [[ -n "$arch" ]] && plat=(--platform "linux/$arch")
            fi
        else
            echo "[pipeline] local image $image not found; pulling for platform $PLATFORM ..." >&2
            local -a pull=(pull)
            [[ "$rt" == "container" ]] && pull=(image pull)
            if ! "$rt" "${pull[@]}" --platform "$PLATFORM" "$image"; then
                echo "[pipeline] ERROR: $rt pull failed for $image on $PLATFORM." >&2
                echo "[pipeline]        hint: build it first (GUI Setup, or margie-build: ./build.sh --containers <tool> --runtime $rt)" >&2
                return 1
            fi
            plat=(--platform "$PLATFORM")
        fi
        local args; args=(run --rm ${plat[@]+"${plat[@]+"${plat[@]}"}"})
        # Caps each tool at its share of the machine (pipeline.conf.sh section 3); SLURM already does this.
        if [[ -z "${SLURM_JOB_ID:-}" && -n "${LOCAL_TOOL_CORES:-}" && -n "${LOCAL_TOOL_MEMORY_GB:-}" ]]; then
            args+=(--cpus "$LOCAL_TOOL_CORES" --memory "${LOCAL_TOOL_MEMORY_GB}g")
        fi
        # GPU needs the NVIDIA Container Toolkit (docker) or a CDI spec (podman); Apple's container runs on CPU.
        if (( USE_GPU_FOR_RUN )); then
            case "$rt" in
                docker)    args+=(--gpus all) ;;
                podman)    args+=(--device nvidia.com/gpu=all) ;;
                container) echo "[pipeline] note: Apple's container has no GPU passthrough; running on CPU" >&2 ;;
            esac
        fi
        [[ -n "${PIPELINE_HOST_INPUT:-}"  ]] && args+=(-e "PIPELINE_HOST_INPUT=$PIPELINE_HOST_INPUT")
        [[ -n "${PIPELINE_HOST_OUTPUT:-}" ]] && args+=(-e "PIPELINE_HOST_OUTPUT=$PIPELINE_HOST_OUTPUT")
        [[ -n "${PIPELINE_HOST_DB:-}"     ]] && args+=(-e "PIPELINE_HOST_DB=$PIPELINE_HOST_DB")
        [[ -n "${PIPELINE_LOG_OPERATOR:-}" ]] && args+=(-e "PIPELINE_LOG_OPERATOR=$PIPELINE_LOG_OPERATOR")
        local m; for m in "${MOUNTS[@]+"${MOUNTS[@]}"}"; do args+=(-v "$m"); done
        "$rt" "${args[@]+"${args[@]}"}" "$image" "$@"
    else
        local abin; abin="$(apptainer_bin)"
        local sif="$image"
        if [[ "$image" != *.sif && "$image" != /* ]]; then
            mkdir -p "$SIF_DIR"
            local name tag
            name="$(basename "${image%%:*}")"
            tag="${image##*:}"; [[ "$tag" == "$image" ]] && tag="latest"
            # Prefers the locally built SIF (<name>.sif) over the pulled one (<name>_<tag>.sif).
            local sif_local="$SIF_DIR/${name}.sif"
            local sif_pulled="$SIF_DIR/${name}_${tag}.sif"
            if [[ -f "$sif_local" ]]; then
                sif="$sif_local"
            elif [[ -f "$sif_pulled" ]]; then
                sif="$sif_pulled"
            else
                sif="$sif_pulled"
                echo "[pipeline] Pulling $image -> $sif" >&2
                "$abin" pull --force "$sif" "docker://$image" >&2
            fi
        fi
        local binds; binds=()
        local m; for m in "${MOUNTS[@]+"${MOUNTS[@]}"}"; do binds+=(--bind "$m"); done
        # --nv passes the host NVIDIA driver stack into the container.
        local -a nv_flag=()
        (( USE_GPU_FOR_RUN )) && nv_flag=(--nv)
        "$abin" run --cleanenv "${nv_flag[@]+"${nv_flag[@]}"}" "${binds[@]+"${binds[@]}"}" "$sif" "$@"
    fi
}

# run_postproc <tool> <out> — runs the tool's optional host-side post-processing script.
run_postproc() {
    local tool="$1" out="$2"
    local script; script="$(tool_postproc "$tool")"
    [[ -z "$script" ]] && return 0
    if [[ ! -x "$script" ]]; then
        echo "[pipeline] WARN: postproc for $tool not executable: $script" >&2
        return 0
    fi
    echo "[pipeline] post-processing $tool via $script"
    "$script" "$out"
}

# run_downstream_tool <tool> [extra container args] — runs a tool once per genome on the
# gene-caller .faa ($annotation_input/<genome>/gene_calls/), writing <tool output>/<genome>/.
# Domain comes from the genome table; the gram argument for psortb and deepsig from the envelope stage.
run_downstream_tool() {
    local tool="$1"; shift
    local image db out input_override input_root host_root threads_for_tool
    image="$(tool_image "$tool")"
    db="$(tool_db "$tool")"
    out="$(tool_output "$tool")"
    threads_for_tool="$(tool_threads "$tool")"
    input_override="$(tool_input_override "$tool")"
    mkdir -p "$out"

    [[ -d "$db" ]] || { echo "[pipeline] ERROR: DB for $tool not found: $db" >&2; return 1; }

    # Inputs come from every caller folder (mixed RASTtk / Prodigal runs); each file keeps
    # its root, which is mounted at /input and anchors the relative paths below.
    local roots; roots=()
    if [[ -n "$input_override" ]]; then
        roots=("$(cd "$input_override" && pwd)")
    else
        local _r
        while IFS= read -r _r; do roots+=("$(cd "$_r" && pwd)"); done < <(gene_call_roots)
    fi
    if [[ ${#roots[@]} -eq 0 ]]; then
        echo "[pipeline] WARN: no gene calls for $tool — no caller has written $OUTPUT_ROOT/<caller>/ yet" >&2
        return 0
    fi

    local faa_files; faa_files=()
    for input_root in "${roots[@]}"; do
        if [[ -n "$input_override" ]]; then
            while IFS= read -r -d '' f; do faa_files+=("$f"); done \
                < <(find "$input_root" -type f -name '*.faa' -print0)
        else
            while IFS= read -r -d '' f; do faa_files+=("$f"); done \
                < <(find -L "$input_root" -type f -path '*/gene_calls/*.faa' -not -path '*/.staging-*' -print0 2>/dev/null)
        fi
    done

    if [[ ${#faa_files[@]} -eq 0 ]]; then
        echo "[pipeline] WARN: no gene_calls/*.faa inputs for $tool — did the gene caller export protein FASTA?" >&2
        return 0
    fi

    # root_of <file> — the caller folder the file came from.
    _root_of() {
        local f="$1" r
        for r in "${roots[@]}"; do [[ "$f" == "$r"/* ]] && { echo "$r"; return 0; }; done
        echo "${roots[0]}"
    }

    echo "[pipeline] >>> $tool  runtime=$(detect_runtime)  image=$image  db=$db  out=$out  inputs=${#faa_files[@]}"
    # Resolves the GPU flag once per tool.
    USE_GPU_FOR_RUN=0
    if tool_use_gpu "$tool"; then
        USE_GPU_FOR_RUN=1
        echo "[pipeline] $tool — GPU requested (USE_GPU=${USE_GPU:-auto})"
    fi
    # One invocation per genome, even when gene_calls/ holds several .faa files
    # (tracked in a delimited list; bash 3.2 has no associative arrays).
    local seen_organisms="|"
    local f rel_input_path rel_input_dir organism_rel rel_bucket dst label
    local organism_name dom ps_k ds_k
    for f in "${faa_files[@]+"${faa_files[@]}"}"; do
        host_root="$(_root_of "$f")"
        rel_input_path="${f#$host_root/}"
        rel_input_dir="$(dirname "$rel_input_path")"
        if [[ "$rel_input_dir" == */gene_calls ]]; then
            organism_rel="$(dirname "$rel_input_dir")"
        else
            organism_rel="$rel_input_dir"
        fi

        # PIPELINE_ORGANISM_FILTER limits the run to one genome.
        if [[ -n "${PIPELINE_ORGANISM_FILTER:-}" && "$organism_rel" != "$PIPELINE_ORGANISM_FILTER" ]]; then
            continue
        fi

        if [[ "$organism_rel" == "." || -z "$organism_rel" ]]; then
            rel_bucket=""
        else
            rel_bucket="$(dirname "$organism_rel")"
            [[ "$rel_bucket" == "." ]] && rel_bucket=""
        fi

        [[ "$seen_organisms" == *"|$organism_rel|"* ]] && continue
        seen_organisms="$seen_organisms$organism_rel|"

        if [[ -n "$rel_bucket" ]]; then
            dst="$out/$rel_bucket"
            label="$rel_bucket/$(basename "$organism_rel")/$(basename "$f")"
        else
            dst="$out"
            if [[ "$organism_rel" == "." || -z "$organism_rel" ]]; then
                label="$(basename "$f")"
            else
                label="$organism_rel/$(basename "$f")"
            fi
        fi
        mkdir -p "$dst"

        # ── Genome name (= gene-call folder name), domain, envelope flags ──
        organism_name="$(basename "$organism_rel")"
        dom="$(genome_domain "$organism_name")"
        ps_k="$(envelope_flag "$organism_name" psortb)"
        ds_k="$(envelope_flag "$organism_name" deepsig)"
        if [[ ( "$tool" == psortb && -z "$ps_k" ) || ( "$tool" == deepsig && -z "$ds_k" ) ]]; then
            echo "[pipeline] WARN: $tool :: $organism_name has no envelope result yet (run-envelope.sh); skipping" >&2
            continue
        fi

        echo "[pipeline] $tool :: $label"
        if [[ "$tool" == "tmbed" ]]; then
            # TMbed 1.0.0 hardcodes its model path to <package>/models/, so $db shadows it:
            # $db/cnn/ holds the CNN weights seeded at setup, $db/t5/ the ProtT5 encoder cache.
            local _tmbed_pkg_models="/usr/local/lib/python3.11/site-packages/tmbed/models"
            mkdir -p "$db/cnn" "$db/t5"
            MOUNTS=(
                "$host_root:/input:ro"
                "$dst:/output:rw"
                "$db:/models:rw"
                "$db:$_tmbed_pkg_models:rw"
            )
            export PIPELINE_HOST_INPUT="$host_root"
            export PIPELINE_HOST_OUTPUT="$dst"
            export PIPELINE_HOST_DB="$db"
            export PIPELINE_LOG_OPERATOR="${USER:-${LOGNAME:-unknown}}"
            export APPTAINERENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export APPTAINERENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export APPTAINERENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export APPTAINERENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            export SINGULARITYENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export SINGULARITYENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export SINGULARITYENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export SINGULARITYENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            run_container "$image" \
                -i "/input/$rel_input_path" -o /output -d /models -t "$threads_for_tool" \
                --organism-name "$organism_name" --domain "$dom" "$@"
        elif [[ "$tool" == "psortb" ]]; then
            local _psortb_ep="$REPO_ROOT/processing/containers/build/psortb/entrypoint.sh"
            local _psortb_py="$REPO_ROOT/processing/containers/build/psortb/scripts/process_psortb_raw_results.py"
            MOUNTS=(
                "$host_root:/input:ro"
                "$dst:/output:rw"
                "$db:/db:ro"
            )
            [[ -f "$_psortb_ep" ]] && MOUNTS+=("$_psortb_ep:/opt/psortb/entrypoint.sh:ro")
            [[ -f "$_psortb_py" ]] && MOUNTS+=("$_psortb_py:/opt/psortb/scripts/process_psortb_raw_results.py:ro")
            export PIPELINE_HOST_INPUT="$host_root"
            export PIPELINE_HOST_OUTPUT="$dst"
            export PIPELINE_HOST_DB="$db"
            export PIPELINE_LOG_OPERATOR="${USER:-${LOGNAME:-unknown}}"
            export APPTAINERENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export APPTAINERENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export APPTAINERENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export APPTAINERENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            export SINGULARITYENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export SINGULARITYENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export SINGULARITYENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export SINGULARITYENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            run_container "$image" \
                -i "/input/$rel_input_path" -o /output -d /db -t "$threads_for_tool" \
                -k "$ps_k" --domain "$dom" \
                --organism-name "$organism_name" "$@"
        elif [[ "$tool" == "deepsig" ]]; then
            MOUNTS=(
                "$host_root:/input:ro"
                "$dst:/output:rw"
                "$db:/db:ro"
            )
            export PIPELINE_HOST_INPUT="$host_root"
            export PIPELINE_HOST_OUTPUT="$dst"
            export PIPELINE_HOST_DB="$db"
            export PIPELINE_LOG_OPERATOR="${USER:-${LOGNAME:-unknown}}"
            export APPTAINERENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export APPTAINERENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export APPTAINERENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export APPTAINERENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            export SINGULARITYENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export SINGULARITYENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export SINGULARITYENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export SINGULARITYENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            run_container "$image" \
                -i "/input/$rel_input_path" -o /output -d /db -t "$threads_for_tool" \
                -k "$ds_k" --domain "$dom" \
                --organism-name "$organism_name" "$@"
        elif [[ "$tool" == "operon" ]]; then
            local rel_gff_path; rel_gff_path="${rel_input_path%.faa}.gff"
            MOUNTS=(
                "$host_root:/input:ro"
                "$dst:/output:rw"
            )
            export PIPELINE_HOST_INPUT="$host_root"
            export PIPELINE_HOST_OUTPUT="$dst"
            export PIPELINE_HOST_DB="$db"
            export PIPELINE_LOG_OPERATOR="${USER:-${LOGNAME:-unknown}}"
            export APPTAINERENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export APPTAINERENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export APPTAINERENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export APPTAINERENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            export SINGULARITYENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export SINGULARITYENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export SINGULARITYENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export SINGULARITYENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            run_container "$image" \
                -i "/input/$rel_input_path" -g "/input/$rel_gff_path" \
                -o /output -t "$threads_for_tool" \
                --domain "$dom" \
                --organism-name "$organism_name" "$@"
        elif [[ "$tool" == "interpro" ]]; then
            # Mounts the host entrypoint over the image's one, so entrypoint fixes apply without a rebuild.
            local _interpro_ep="$REPO_ROOT/processing/containers/build/interpro/entrypoint.sh"
            local _interpro_py="$REPO_ROOT/processing/containers/build/interpro/scripts/process_interpro_raw_results.py"
            local _interpro_apps; _interpro_apps="$(tool_apps interpro)"
            MOUNTS=(
                "$host_root:/input:ro"
                "$dst:/output:rw"
                "$db:/db:ro"
            )
            [[ -f "$_interpro_ep" ]] && MOUNTS+=("$_interpro_ep:/opt/interpro/entrypoint.sh:ro")
            [[ -f "$_interpro_py" ]] && MOUNTS+=("$_interpro_py:/opt/interpro/scripts/process_interpro_raw_results.py:ro")
            export PIPELINE_HOST_INPUT="$host_root"
            export PIPELINE_HOST_OUTPUT="$dst"
            export PIPELINE_HOST_DB="$db"
            export PIPELINE_LOG_OPERATOR="${USER:-${LOGNAME:-unknown}}"
            export APPTAINERENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export APPTAINERENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export APPTAINERENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export APPTAINERENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            export SINGULARITYENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export SINGULARITYENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export SINGULARITYENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export SINGULARITYENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            local _apps_flag=()
            [[ -n "$_interpro_apps" ]] && _apps_flag=(-a "$_interpro_apps")
            run_container "$image" \
                -i "/input/$rel_input_path" -o /output -d /db -t "$threads_for_tool" \
                --domain "$dom" \
                --organism-name "$organism_name" \
                "${_apps_flag[@]+"${_apps_flag[@]+"${_apps_flag[@]}"}"}" "$@"
        elif [[ "$tool" == "geneprop" ]]; then
            # geneprop reads the TIGRFAMs domtblout; the tigrfam output tree is mounted at /tigrfam.
            local _geneprop_ep="$REPO_ROOT/processing/containers/build/geneprop/entrypoint.sh"
            local _geneprop_py="$REPO_ROOT/processing/containers/build/geneprop/scripts/process_geneprop_raw_results.py"
            local _tigrfam_root="$annotation_output_root/tigrfam"
            MOUNTS=(
                "$host_root:/input:ro"
                "$dst:/output:rw"
                "$db:/db:ro"
                "$_tigrfam_root:/tigrfam:ro"
            )
            [[ -f "$_geneprop_ep" ]] && MOUNTS+=("$_geneprop_ep:/opt/geneprop/entrypoint.sh:ro")
            [[ -f "$_geneprop_py" ]] && MOUNTS+=("$_geneprop_py:/opt/geneprop/scripts/process_geneprop_raw_results.py:ro")
            export PIPELINE_HOST_INPUT="$host_root"
            export PIPELINE_HOST_OUTPUT="$dst"
            export PIPELINE_HOST_DB="$db"
            export PIPELINE_LOG_OPERATOR="${USER:-${LOGNAME:-unknown}}"
            export APPTAINERENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export APPTAINERENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export APPTAINERENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export APPTAINERENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            export SINGULARITYENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export SINGULARITYENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export SINGULARITYENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export SINGULARITYENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            run_container "$image" \
                -i "/input/$rel_input_path" -o /output -d /db -t "$threads_for_tool" \
                --tigrfam-domtbl "/tigrfam/$organism_rel/raw/tigrfam_domtbl.out" \
                --domain "$dom" \
                --organism-name "$organism_name" "$@"
        elif [[ "$tool" == "phobius" ]]; then
            local _phobius_ep="$REPO_ROOT/processing/containers/build/phobius/entrypoint.sh"
            local _phobius_py="$REPO_ROOT/processing/containers/build/phobius/scripts/process_phobius_raw_results.py"
            MOUNTS=(
                "$host_root:/input:ro"
                "$dst:/output:rw"
                "$db:/db:ro"
            )
            [[ -f "$_phobius_ep" ]] && MOUNTS+=("$_phobius_ep:/opt/phobius/entrypoint.sh:ro")
            [[ -f "$_phobius_py" ]] && MOUNTS+=("$_phobius_py:/opt/phobius/scripts/process_phobius_raw_results.py:ro")
            export PIPELINE_HOST_INPUT="$host_root"
            export PIPELINE_HOST_OUTPUT="$dst"
            export PIPELINE_HOST_DB="$db"
            export PIPELINE_LOG_OPERATOR="${USER:-${LOGNAME:-unknown}}"
            export APPTAINERENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export APPTAINERENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export APPTAINERENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export APPTAINERENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            export SINGULARITYENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export SINGULARITYENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export SINGULARITYENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export SINGULARITYENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            run_container "$image" \
                -i "/input/$rel_input_path" -o /output -d /db -t "$threads_for_tool" \
                --domain "$dom" \
                --organism-name "$organism_name" "$@"
        else
            MOUNTS=(
                "$host_root:/input:ro"
                "$dst:/output:rw"
                "$db:/db:ro"
            )
            export PIPELINE_HOST_INPUT="$host_root"
            export PIPELINE_HOST_OUTPUT="$dst"
            export PIPELINE_HOST_DB="$db"
            export PIPELINE_LOG_OPERATOR="${USER:-${LOGNAME:-unknown}}"
            export APPTAINERENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export APPTAINERENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export APPTAINERENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export APPTAINERENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            export SINGULARITYENV_PIPELINE_HOST_INPUT="$PIPELINE_HOST_INPUT"
            export SINGULARITYENV_PIPELINE_HOST_OUTPUT="$PIPELINE_HOST_OUTPUT"
            export SINGULARITYENV_PIPELINE_HOST_DB="$PIPELINE_HOST_DB"
            export SINGULARITYENV_PIPELINE_LOG_OPERATOR="$PIPELINE_LOG_OPERATOR"
            run_container "$image" \
                -i "/input/$rel_input_path" -o /output -d /db -t "$threads_for_tool" \
                --domain "$dom" \
                --organism-name "$organism_name" "$@"
        fi
    done
    run_postproc "$tool" "$out"
}

# Prints the resolved tool config (used by --list).
print_tool_config() {
    local tool="$1"
    echo "Tool          = $tool"
    echo "Runtime       = $(detect_runtime)"
    echo "Image         = $(tool_image "$tool")"
    echo "DB            = $(tool_db "$tool")"
    echo "Input         = $(tool_input_override "$tool" || true)"
    [[ -z "$(tool_input_override "$tool")" ]] && \
        echo "                (defaults to .faa under $annotation_input)"
    echo "Output        = $(tool_output "$tool")"
    echo "Postproc      = $(tool_postproc "$tool")"
    echo "Threads       = $(tool_threads "$tool") (default=$THREADS)"
    echo "GPU           = $(tool_use_gpu "$tool" && echo "yes (USE_GPU=${USE_GPU:-auto})" || echo "no")"
    echo "Platform      = $PLATFORM"
    echo "SifDir        = $SIF_DIR  (Apptainer .sif cache)"
}
