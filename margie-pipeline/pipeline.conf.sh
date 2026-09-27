# pipeline.conf.sh — central settings, sourced (not run) by every script.
# Edit a value here to change it everywhere. Override for one run with:
#   DB_ROOT=/scratch/dbs ./annotate.sh --tool kegg
# `: "${VAR:=default}"` means: keep VAR if already set, else use default.

# section 1 — repo location (auto-resolved, do not edit)
pipeline_conf_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO_ROOT:=$pipeline_conf_dir}"

# section 1b — local user identity: PIPELINE_USER, else id -un, else $USER
: "${PIPELINE_USER:=$(id -un 2>/dev/null || echo "${USER:-unknown}")}"

# section 2 — core folders (point to a fast disk if needed)
: "${USER_INPUT_DIR:=$REPO_ROOT/user-input}"     # raw user-supplied genome FASTAs
: "${INPUT_RASTTK:=$REPO_ROOT/input}"           # genomes copied flat (<genome>.fna) + genomes.tsv; gene-caller input
: "${OUTPUT_ROOT:=$REPO_ROOT/output}"           # per-tool results
: "${DB_ROOT:=$REPO_ROOT/db}"                   # parent of per-tool databases
: "${SIF_DIR:=$REPO_ROOT/processing/containers/sifs}"     # apptainer .sif cache
: "${BUILD_DIR:=$REPO_ROOT/processing/containers/build}"  # per-tool Dockerfiles
: "${scripts_dir:=$REPO_ROOT/processing/scripts}"
: "${postproc_dir:=$scripts_dir/post-processing-raw-container-outputs}"

# section 2b — classification: each genome's domain and genetic code
# RUN_GTDBTK=1  classify every genome with GTDB-Tk first. It needs a
#               high-memory machine (HPC); on a laptop it can exhaust memory.
# RUN_GTDBTK=0  skip GTDB-Tk; take each genome's domain and genetic code from
#               GENOME_METADATA instead.
: "${RUN_GTDBTK:=1}"
# One row per genome: genome<TAB>domain<TAB>genetic_code, where domain is
# Bacteria or Archaea and genetic_code an NCBI translation table (e.g. 11);
# either may be blank when unknown.
: "${GENOME_METADATA:=$USER_INPUT_DIR/genome-metadata.tsv}"

# section 3 — runtime settings
: "${RUNTIME:=auto}"            # docker | podman | container (Apple, macOS) | apptainer | auto (prefers apptainer)
: "${PLATFORM:=linux/amd64}"    # docker --platform target

# ---- what this pipeline may use on this computer ----
# LOCAL_MAX_CORES and LOCAL_MAX_MEMORY_GB are the whole budget, split evenly
# across LOCAL_PARALLEL_TOOLS (e.g. 8 cores, 64 GB, 2 tools -> 4 cores, 32 GB
# each). Defaults: three quarters of the machine, one tool at a time. OCI
# runtimes enforce the share; under Apptainer it is advisory.
# Prints the machine's CPU count (Linux or macOS).
_margie_cores() {
    local n
    n="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    echo $(( n > 1 ? n : 1 ))
}
# Prints the machine's memory in GB (Linux or macOS).
_margie_memory_gb() {
    local kb bytes
    if [[ -r /proc/meminfo ]]; then
        kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
        echo $(( kb / 1024 / 1024 ))
    elif bytes="$(sysctl -n hw.memsize 2>/dev/null)"; then
        echo $(( bytes / 1024 / 1024 / 1024 ))
    else
        echo 8
    fi
}
: "${LOCAL_MAX_CORES:=$(( $(_margie_cores) * 3 / 4 > 0 ? $(_margie_cores) * 3 / 4 : 1 ))}"
: "${LOCAL_MAX_MEMORY_GB:=$(( $(_margie_memory_gb) * 3 / 4 > 0 ? $(_margie_memory_gb) * 3 / 4 : 1 ))}"
: "${LOCAL_PARALLEL_TOOLS:=1}"
# Each running tool's share, worked out from the three above.
LOCAL_TOOL_CORES=$(( LOCAL_MAX_CORES / LOCAL_PARALLEL_TOOLS ))
(( LOCAL_TOOL_CORES > 0 )) || LOCAL_TOOL_CORES=1
LOCAL_TOOL_MEMORY_GB=$(( LOCAL_MAX_MEMORY_GB / LOCAL_PARALLEL_TOOLS ))
(( LOCAL_TOOL_MEMORY_GB > 0 )) || LOCAL_TOOL_MEMORY_GB=1
export LOCAL_MAX_CORES LOCAL_MAX_MEMORY_GB LOCAL_PARALLEL_TOOLS LOCAL_TOOL_CORES LOCAL_TOOL_MEMORY_GB

: "${THREADS:=$LOCAL_TOOL_CORES}"   # CPU threads per tool (a tool's share of the cores)
: "${REGISTRY:=margie}"  # local image prefix for source-built containers

# section 3b — GPU settings
# USE_GPU decides whether GPU-capable tools request a GPU:
#   auto  → when nvidia-smi is visible (default)
#   1/yes → always (fails fast on CPU-only nodes)
#   0/no  → never
# Per run: USE_GPU=1 ./annotate.sh …   Per tool (section 7): TOOL_tmbed_GPU=1, TOOL_llm_GPU=0
# Only gpu_capable_tools get --nv / --gpus all; every other tool runs on CPU.
: "${USE_GPU:=auto}"

# GPU-capable tools; TOOL_<name>_GPU=1/0 overrides this list for that tool.
# signalp6 needs a CUDA build of its container before it is enabled here.
gpu_capable_tools=(
    tmbed       # ProtT5 encoder — ~50× faster on GPU
    llm         # LLaMA inference — GPU strongly recommended
    # signalp6  # CNN/transformer signal peptide predictor — uncomment when integrated
)

# HPC-only tools use cluster modules rather than pipeline-built containers and
# are skipped silently elsewhere:
#   signalp4  — SignalP 4.1 via `module load biocontainers/default signalp4/4.1`

# section 4 — folders for each pipeline stage
# stages: 1 gene caller -> 2 annotation -> 3 per-genome results (consolidation,
# labeling, scoring, fingerprint, evidence, viewer, figures).

# stage 1 — gene caller, RASTtk or Prodigal per genome (input/genomes.tsv).
# Each caller writes the same layout under $OUTPUT_ROOT/<caller>/<genome>/;
# later stages find it via gene_call_roots / genome_calls_dir (pipeline-lib.sh).
#
# GENE_CALLER (written per genome into genomes.tsv by run-prepare-genomes.sh):
#   prodigal  every genome; needs only the assembly (default)
#   rasttk    genomes with a known domain AND genetic code (typed in, or from
#             GTDB-Tk); the rest fall back to prodigal. Also reports RNAs and repeats.
#   auto      same as rasttk
: "${GENE_CALLER:=prodigal}"
: "${GENE_CALLERS:=rasttk prodigal}"                       # every caller with a folder of its own
: "${gene_caller_name:=rasttk}"
: "${gene_caller_input:=$INPUT_RASTTK}"                    # genome assemblies in
: "${gene_caller_output:=$OUTPUT_ROOT/$gene_caller_name}"  # RASTtk's folder; prodigal's is beside it

# stage 2 — annotation tools; each writes to $annotation_output_root/<tool>.
# They read every caller's folder (gene_call_roots); this is the first of them.
: "${annotation_input:=$gene_caller_output}"
: "${annotation_output_root:=$OUTPUT_ROOT}"

# stage 3 — per-genome results from the host scripts (processing/host-scripts/,
# run by run-meta.sh). Tool results are copied to
#   $GENOME_RESULTS_DIR/<genome>/<tool>/<tool>_results.tsv
# and consolidation, labeling, scoring, fingerprint, evidence, viewer and
# figures write beside them.
: "${GENOME_RESULTS_DIR:=$OUTPUT_ROOT/genomes}"
# Cross-run references that grow with every genome (fingerprint databases,
# operon co-occurrence reference).
: "${MARGIE_SHARED_DIR:=$DB_ROOT/margie-shared}"
# The operon co-occurrence reference the scoring step reads and grows.
: "${OPERON_DB:=$MARGIE_SHARED_DIR/operon-database/occ_reference.pkl}"
# Result cache: one SQLite file holding each tool's output under the genome's
# hash, so a genome is never computed twice. Portable by copying the file.
: "${MARGIE_DB:=$DB_ROOT/margie.db}"
# 0 turns the cache off: every tool runs again, nothing is stored.
: "${USE_RESULT_CACHE:=1}"
: "${RUN_EVIDENCE:=1}"             # per-gene evidence report
: "${RUN_GENOME_VIEWER:=1}"        # FINAL_GENOME_VIEWER.html + circular map
: "${RUN_REPORT_FIGURES:=1}"       # per-genome and pangenome report figures
: "${RUN_FULL_OPERON_MAP:=0}"      # every operon drawn (slow; off by default)
: "${RUN_REORGANIZE_OUTPUTS:=1}"   # final layout: FINAL table + Excel + diagrams/

# section 5 — tools and databases (single source of truth)
# tier-1: one container per tool, once per genome.
# tier-2: host scripts, not containers (processing/host-scripts/, run-meta.sh).
# GTDB-Tk (optional, RUN_GTDBTK) is run by annotate.sh, not listed here.
# envelope runs between the annotation tools and psortb / deepsig / signalp4.
all_classify_tools=()
all_tier1_tools=(
    rasttk prodigal
    kegg cog pfam pgap tigrfam dbcan eggnog merops tcdb uniprot interpro geneprop
    envelope
    psortb deepsig tmbed phobius
    operon
)
all_tier2_tools=()
all_tools=( "${all_classify_tools[@]+"${all_classify_tools[@]}"}" "${all_tier1_tools[@]+"${all_tier1_tools[@]}"}" "${all_tier2_tools[@]+"${all_tier2_tools[@]}"}" )

# Comparative tools run once over the whole collection after per-genome
# annotation, via run-individual-containers/run-{aai,ani,closest,synteny}.sh.
#
#   aai      → all-vs-all Average Amino Acid Identity (EzAAI + DIAMOND)
#              input:  annotation_input/<genome>/gene_calls/genome.faa
#              output: annotation_output_root/aai/
#   ani      → all-vs-all Average Nucleotide Identity (FastANI)
#              input:  gene_caller_input/<genome>.fna
#              output: annotation_output_root/ani/
#   closest  → top-N closest organisms ranking from AAI + ANI matrices
#              input:  annotation_output_root/aai/processed/ + ani/processed/
#              output: annotation_output_root/closest/
#   synteny  → annotation transfer from top-N closest references (Liftoff)
#              input:  gene_caller_input (FNA) + annotation_input (GFF3) + closest TSV
#              output: annotation_output_root/synteny/<query_genome>/
all_comparative_tools=( aai ani closest synteny )

# Databases to download, fastest first (tools with built-in models are not listed).
# tmbed's ProtT5 encoder (~1.4 GB) is fetched by the tmbed container, so its
# image must exist first (./setup.sh does containers before databases).
# llm needs a HuggingFace token and model approval, so it is run separately:
#   ./setup.sh --databases-only --tool llm          (first download)
#   ./setup.sh --databases-only --tool llm --redo   (re-download / update)
all_dbs=(
    cog pgap tigrfam rasttk dbcan tcdb merops pfam geneprop pangenome uniprot
    eggnog
    interpro
    kegg
    tmbed
    gtdbtk
    taxonomy
    type_strains
)

# section 6 — optional large AI models (empty skips)
# A HuggingFace id ("org/name") downloads into $LLM_ROOT/<slot>/ on
# ./setup.sh --tool llm; an absolute path is used as is.
: "${LLM_BASE_MODEL:=meta-llama/Meta-Llama-3-8B}"            # foundation model (e.g. meta-llama/Meta-Llama-3-8B)
: "${LLM_TRAINED_MODEL:=}"         # fine-tuned model
: "${LLM_TRAINED_ADAPTERS:=}"      # LoRA / PEFT adapters
: "${LLM_ROOT:=$DB_ROOT/llm}"      # local cache folder

# section 7 — per-tool overrides (uncomment only when needed)
# format: TOOL_<name>_<KEY>=value  (KEY: IMAGE | DB | INPUT | OUTPUT | POSTPROC | THREADS)
# examples:
#   # TOOL_kegg_DB="/data/shared/kegg_db"
#   # TOOL_kegg_IMAGE="margie/kegg:v1.2"
#   # TOOL_kegg_THREADS=16
#   # TOOL_rasttk_POSTPROC="$postproc_dir/rasttk/postproc.sh"   (host-side post-processing)
#
# InterProScan: $DB_ROOT/interpro from the build recipes, unless TOOL_interpro_DB names a shared install.
: "${TOOL_interpro_DB:=interpro}"
# PROSITE_PATTERNS / PROSITE_PROFILES are left out: their binaries need libpcre,
# which the container lacks. An existing raw interpro.tsv is not re-run when this changes.
: "${TOOL_interpro_APPS:=CDD,COILS,GENE3D,HAMAP,PANTHER,PFAM,PIRSF,PIRSR,PRINTS,SFLD,SMART,SUPERFAMILY,TIGRFAM,NCBIfam,MobiDBLite}"

# Per-tool thread defaults; every other tool uses THREADS (section 3).
: "${TOOL_RASTTK_THREADS:=4}"   # RASTtk runs sequentially; 4 CPUs is sufficient
: "${TOOL_KEGG_THREADS:=16}"
: "${TOOL_EGGNOG_THREADS:=16}"

# section 7b — comparative tool overrides (uncomment to use); the *_MATRIX
# values point run-closest.sh at other matrix files.
#
#   # TOOL_aai_IMAGE="margie/aai:v1.0"
#   # TOOL_ani_IMAGE="margie/ani:v1.0"
#   # TOOL_closest_IMAGE="margie/closest:v1.0"
#   # TOOL_synteny_IMAGE="margie/synteny:v1.0"
#   # TOOL_closest_AAI_MATRIX="$annotation_output_root/aai/processed/aai_results.tsv"
#   # TOOL_closest_ANI_MATRIX="$annotation_output_root/ani/processed/ani_results.tsv"
#   # TOOL_synteny_CLOSEST_TSV="$annotation_output_root/closest/processed/closest_organisms.tsv"

# section 8 — LICENCE DECLARATIONS  (read this carefully)
# A few upstream tools / databases are free for non-commercial use only and
# may NOT be redistributed. The pipeline does not bundle them; each user fetches
# them from upstream after accepting the terms. All are OFF by default.
#
# Accepting means typing this statement:
#
#   I accept that I am using these tools for non-commercial purposes and
#   have received all permissions from the upstream developers.
#
# This is a legally binding agreement. Once you accept, your use of these
# tools and their databases is entirely your own responsibility.
#
# Type it in either place:
#   1. Interactively during ./setup.sh -- each gated tool prints its terms
#      and asks for the statement (5-minute timeout); after the first, the
#      rest of that run ask yes/no. Declining or timing out skips the tool.
#   2. HERE, for runs with no terminal (SLURM, CI): LICENCE_INTENDED_USE, the
#      statement in LICENCE_STATEMENT, and the per-tool LICENCE_AGREED_<TOOL>
#      flag set to 1. The setup GUI writes these for you when you type the
#      statement there.
# A flag without the statement accepts nothing (that includes setup.sh's
# --accept-*-licence flags, which take --licence-statement "<statement>").
#
# Every acceptance is appended to $LOG_DIR/licence-acceptances.tsv and shown
# at the top of each tool's log. Tools not accepted are skipped at annotate time.
#
# Full upstream licence links:
#   MEROPS     https://www.ebi.ac.uk/merops/about/terms_of_use.shtml
#   TCDB       https://www.tcdb.org/about.php
#   TMbed      https://huggingface.co/Rostlab/prot_t5_xl_half_uniref50-enc  (CC-BY-NC-SA 4.0)
#   InterPro   https://www.ebi.ac.uk/interpro/about/  (mixed member-DB terms; ProSite / SMART require commercial licences)
#   Phobius    https://phobius.sbc.su.se/data.html
#   PSORTb     https://psort.org/  (gated by this project)
#
# A SHORT, TRUTHFUL description of your intended use, logged verbatim with
# every acceptance, e.g. "academic research at <your institution>".
: "${LICENCE_INTENDED_USE=}"
# The statement above, typed out, for acceptance without a terminal.
: "${LICENCE_STATEMENT=}"

# Set to 1 ONLY for tools whose upstream licence you have read and whose
# terms your use meets. Each counts only with the two values above.
: "${LICENCE_AGREED_MEROPS:=0}"
: "${LICENCE_AGREED_TCDB:=0}"
: "${LICENCE_AGREED_TMBED:=0}"
: "${LICENCE_AGREED_INTERPRO:=0}"
: "${LICENCE_AGREED_PHOBIUS:=0}"
: "${LICENCE_AGREED_PSORTB:=0}"

# Tools that need a recorded acceptance before they run.
LICENCE_GATED_TOOLS=(merops tcdb tmbed interpro phobius psortb)

# section 9 — SLURM cluster settings
# Used to generate the *.slurm job scripts; regenerate after a change with
#   ./setup.sh --generate-slurm
#
# SLURM_ACCOUNT   your HPC allocation / charge account (required on a cluster; empty: no job scripts are written)
# SLURM_PARTITION the queue to submit to (e.g. cpu, gpu, shared)
# Per-job knobs: NODES (number of nodes), TIME (wall-clock limit hh:mm:ss),
#                CPUS (cpus-per-task, single-node jobs only),
#                MEM  (memory limit, e.g. 64G, single-node jobs only)

: "${SLURM_ACCOUNT:=}"                 # --account  (your HPC allocation)
: "${SLURM_PARTITION:=cpu}"            # --partition (queue name)

# containers job — build/pull all container images
: "${SLURM_CONTAINERS_NODES:=16}"
: "${SLURM_CONTAINERS_TIME:=06:00:00}"

# databases job — download all reference databases (excludes llm)
: "${SLURM_DATABASES_NODES:=16}"
: "${SLURM_DATABASES_TIME:=23:00:00}"

# full setup job — containers + databases combined
: "${SLURM_SETUP_NODES:=16}"
: "${SLURM_SETUP_TIME:=23:00:00}"

# annotate job — genome annotation run (single node, multi-core)
# Peak CPU usage = PARALLEL_TOOLS × THREADS + TOOL_RASTTK_THREADS
# Default: 6 × 8 + 4 = 52 CPUs (annotation sliding window + concurrent rasttk)
: "${SLURM_ANNOTATE_NODES:=1}"
: "${SLURM_ANNOTATE_CPUS:=52}"
: "${SLURM_ANNOTATE_MEM:=128G}"
: "${SLURM_ANNOTATE_TIME:=24:00:00}"

# classify job — GTDB-Tk classify step (one node, 16 cores, 64 GB)
: "${SLURM_CLASSIFY_NODES:=1}"
: "${SLURM_CLASSIFY_CPUS:=16}"
: "${SLURM_CLASSIFY_MEM:=64G}"
: "${SLURM_CLASSIFY_TIME:=24:00:00}"

# annotate-downstream job — re-run tier-1 tools only (same resources as annotate)
: "${SLURM_DOWNSTREAM_NODES:=1}"
: "${SLURM_DOWNSTREAM_CPUS:=52}"
: "${SLURM_DOWNSTREAM_MEM:=128G}"
: "${SLURM_DOWNSTREAM_TIME:=24:00:00}"

# meta job — consolidation → labeling → fingerprint → scoring
: "${SLURM_META_NODES:=1}"
: "${SLURM_META_CPUS:=4}"
: "${SLURM_META_MEM:=16G}"
: "${SLURM_META_TIME:=02:00:00}"

# gtdbtk-highmem job — GTDB-Tk on a high-memory node (requires highmem partition)
: "${SLURM_GTDBTK_PARTITION:=highmem}"
: "${SLURM_GTDBTK_NODES:=1}"
: "${SLURM_GTDBTK_CPUS:=64}"
: "${SLURM_GTDBTK_MEM:=256G}"
: "${SLURM_GTDBTK_TIME:=24:00:00}"

# llm job — LLM model weight download (~16 GB; requires pre-cached HF token)
: "${SLURM_LLM_NODES:=1}"
: "${SLURM_LLM_CPUS:=4}"
: "${SLURM_LLM_MEM:=16G}"
: "${SLURM_LLM_TIME:=10:00:00}"

# section 10 — orchestration concurrency
# PARALLEL_TOOLS   annotation tools run at once per genome in HPC mode (sliding
#                  window); peak cores ≈ PARALLEL_TOOLS × THREADS + TOOL_RASTTK_THREADS.
# MIN_PHASE2_ORGS  scored genomes needed before aai / ani / closest / synteny run (≥ 2).
: "${PARALLEL_TOOLS:=6}"
: "${MIN_PHASE2_ORGS:=2}"

# section 11 — BV-BRC login for the rasttk step (bvbrc-env.sh)
# With BVBRC_LOGIN=1, run-rasttk.sh runs `p3-login` in the rasttk container on
# first use and reuses the cached session afterwards. For SLURM jobs, log in once
# from an interactive terminal first. To force a new login:
#   source processing/scripts/shared/bvbrc-env.sh && bvbrc_reset_session
#
# BVBRC_LOGIN         0 = off, 1 = on
# BVBRC_USERNAME      BV-BRC account name passed to p3-login (empty: prompt for it)
# BVBRC_SESSION_DIR   where p3 credentials are cached (gitignored)
: "${BVBRC_LOGIN:=1}"
: "${BVBRC_USERNAME:=}"
: "${BVBRC_SESSION_DIR:=$REPO_ROOT/processing/.bvbrc}"
