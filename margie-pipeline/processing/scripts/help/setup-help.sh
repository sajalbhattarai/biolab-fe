# help/setup-help.sh -- help text for setup.sh: print_help_<topic> functions and
# the print_help_setup dispatcher. Sourced after shared/colors.sh and shared/help-render.sh.

# ---- main help (--help with no topic) ----

print_help_main() {
    _help_h1 "setup.sh -- provision the annotation pipeline"
    printf "  ${C_WHITE}Downloads (or builds) container images and reference databases.${C_NC}\n"
    printf "  ${C_WHITE}Safe to re-run: every step is idempotent and resumable.${C_NC}\n"

    _help_h1 "AT A GLANCE"
    printf "  ${C_GREEN}+----------------------+${C_NC}     ${C_GREEN}+----------------------+${C_NC}\n"
    printf "  ${C_GREEN}|${C_NC} ${C_BOLD}${C_CYAN}phase 1${C_NC}              ${C_GREEN}|${C_NC} --> ${C_GREEN}|${C_NC} ${C_BOLD}${C_CYAN}phase 2${C_NC}              ${C_GREEN}|${C_NC}\n"
    printf "  ${C_GREEN}|${C_NC} ${C_WHITE}container images${C_NC}     ${C_GREEN}|${C_NC}     ${C_GREEN}|${C_NC} ${C_WHITE}reference databases${C_NC}  ${C_GREEN}|${C_NC}\n"
    printf "  ${C_GREEN}|${C_NC} ${C_DIM}(~25 GB)${C_NC}             ${C_GREEN}|${C_NC}     ${C_GREEN}|${C_NC} ${C_DIM}(~170 GB)${C_NC}            ${C_GREEN}|${C_NC}\n"
    printf "  ${C_GREEN}+----------------------+${C_NC}     ${C_GREEN}+----------------------+${C_NC}\n"
    printf "       ${C_YELLOW}--containers-only${C_NC}                  ${C_YELLOW}--databases-only${C_NC}\n"

    _help_h1 "USAGE"
    printf "  ${C_GREEN}./setup.sh${C_NC} ${C_WHITE}[PHASE] [MODE] [OPTIONS]${C_NC}\n"

    _help_h2 "PLACEHOLDER LEGEND"
    _help_kv "<name>"    "a tool or database name (e.g. ${C_GREEN}pfam${C_NC}, ${C_GREEN}kegg${C_NC}, ${C_GREEN}llm${C_NC})"
    _help_kv "<path>"    "an absolute or relative filesystem path"
    _help_kv "<runtime>" "one of: ${C_GREEN}docker${C_NC} | ${C_GREEN}apptainer${C_NC} | ${C_GREEN}auto${C_NC}"

    _help_h2 "PHASE (which half to run; default is BOTH)"
    _help_label "--containers-only"  "phase 1 only -- pull or build container images"
    _help_label "--databases-only"   "phase 2 only -- download reference databases"

    _help_h2 "CONTAINER MODE (mutually exclusive -- pick at most one)"
    _help_label "(no flag = BUILD)"  "build images locally from the per-tool Dockerfiles"
    _help_req   "${C_GREEN}docker${C_NC} on \$PATH (also exports .sif if ${C_GREEN}apptainer${C_NC} is present)"
    _help_label "--pull"             "skip building; download prebuilt images from \$REGISTRY"
    _help_req   "${C_GREEN}docker${C_NC} OR ${C_GREEN}apptainer${C_NC} (auto-detected)"
    _help_label "--build-and-push"   "${C_YELLOW}developer only${C_NC} -- multi-arch build + push to \$REGISTRY"
    _help_req   "${C_GREEN}docker${C_NC} + ${C_GREEN}buildx${C_NC} + a valid GitHub PAT (write:packages)"
    _help_label "--no-cache"         "(with build modes) force a clean rebuild -- bypasses layer cache"

    _help_h2 "COMMON OPTIONS"
    _help_label "--tool <name>"      "limit the run to a single tool / database"
    _help_label "--runtime <runtime>" "override RUNTIME from pipeline.conf.sh"
    _help_label "--redo"             "force re-download / re-pull even if already present"
    _help_label "--dry-run"          "print every action without executing"
    _help_label "-h, --help [topic]" "show help (see TOPICS below for deep dives)"

    _help_h2 "HUGGINGFACE OPTIONS  (only relevant to ${C_GREEN}--tool llm${C_NC})"
    printf "  ${C_DIM}HuggingFace hosts the AI model weights for 'llm' (language model).${C_NC}\n"
    printf "  ${C_DIM}Downloading them needs a free access token from huggingface.co IF you${C_NC}\n"
    printf "  ${C_DIM}have configured LLM_BASE_MODEL / LLM_TRAINED_MODEL in pipeline.conf.sh.${C_NC}\n"
    printf "  ${C_DIM}('tmbed' is also AI but its model is PUBLIC -- no token needed.)${C_NC}\n\n"
    _help_label "--hf-token-file FILE" "read the HF access token from FILE (chmod 600 recommended)"
    _help_note  "useful on SLURM / CI where an interactive prompt won't work"
    _help_label "--reset-hf-token"   "discard the cached token and prompt for a new one"

    _help_h2 "LICENCE OPTIONS  (academic / restricted-use tools and databases)"
    printf "  ${C_DIM}A few upstream tools and databases are free for ACADEMIC / non-commercial${C_NC}\n"
    printf "  ${C_DIM}use only -- commercial use requires a separate licence from the upstream${C_NC}\n"
    printf "  ${C_DIM}provider. They are all off until you accept them. The pipeline prints${C_NC}\n"
    printf "  ${C_DIM}each licence and asks you to ${C_GREEN}type this statement${C_NC}${C_DIM}:${C_NC}\n\n"
    printf "    ${C_GREEN}%s${C_NC}\n\n" "${LICENCE_REQUIRED_STATEMENT:-I accept that I am using these tools for non-commercial purposes and have received all permissions from the upstream developers.}"
    printf "  ${C_RED}This is a legally binding agreement. Once you accept, your use of these${C_NC}\n"
    printf "  ${C_RED}tools and their databases is entirely your own responsibility.${C_NC}\n"
    printf "  ${C_DIM}After the first tool, the rest of the run ask yes/no. ${C_YELLOW}Timeout = 5 minutes;${C_NC}\n"
    printf "  ${C_YELLOW}no answer means SKIP${C_NC} ${C_DIM}(safe). Skipped tools are listed at the end with${C_NC}\n"
    printf "  ${C_DIM}re-run instructions, and recorded under ${C_GREEN}logs/licence-skipped.*.tsv${C_NC}${C_DIM}.${C_NC}\n\n"
    _help_label "--licence-statement \"...\"" "the statement, for runs with no terminal (or ${C_GREEN}LICENCE_STATEMENT${C_NC})"
    _help_label "--accept-merops-licence"    "pre-accept MEROPS academic licence    (or ${C_GREEN}MEROPS_ACCEPT_LICENCE=1${C_NC})"
    _help_label "--accept-tcdb-licence"      "pre-accept TCDB academic licence      (or ${C_GREEN}TCDB_ACCEPT_LICENCE=1${C_NC})"
    _help_label "--accept-tmbed-licence"     "pre-accept ProtT5 CC-BY-NC-SA terms   (or ${C_GREEN}TMBED_ACCEPT_LICENCE=1${C_NC})"
    _help_label "--accept-interpro-licence"  "pre-accept InterPro mixed terms       (or ${C_GREEN}INTERPRO_ACCEPT_LICENCE=1${C_NC})"
    _help_label "--accept-phobius-licence"   "pre-accept Phobius academic licence   (or ${C_GREEN}PHOBIUS_ACCEPT_LICENCE=1${C_NC})"
    _help_label "--accept-psortb-licence" "pre-accept PSORTb                     (or ${C_GREEN}PSORTB_ACCEPT_LICENCE=1${C_NC})"
    _help_label "--accept-all-licences"      "pre-accept ALL of the above           (or ${C_GREEN}LICENCE_ACCEPT_ALL=1${C_NC})"
    _help_note  "the pre-accept flags count only together with --licence-statement;"
    _help_note  "use them only in CI / SLURM, for tools whose terms your use meets"
    printf "\n  ${C_DIM}You can ALSO declare consent persistently in ${C_GREEN}pipeline.conf.sh${C_NC} ${C_DIM}so${C_NC}\n"
    printf "  ${C_DIM}you are not re-prompted on every fresh setup:${C_NC}\n"
    printf "    ${C_GREEN}LICENCE_INTENDED_USE${C_NC}=${C_DIM}\"academic research at <your institution>\"${C_NC}\n"
    printf "    ${C_GREEN}LICENCE_STATEMENT${C_NC}=${C_DIM}\"<the statement above>\"${C_NC}\n"
    printf "    ${C_GREEN}LICENCE_AGREED_MEROPS${C_NC}=1   ${C_GREEN}LICENCE_AGREED_TCDB${C_NC}=1   ${C_DIM}(etc.)${C_NC}\n"
    printf "  ${C_DIM}Every acceptance (config OR interactive) is appended to${C_NC}\n"
    printf "  ${C_GREEN}logs/licence-acceptances.tsv${C_NC} ${C_DIM}and the matching record is re-printed at${C_NC}\n"
    printf "  ${C_DIM}the top of every pipeline log entry for the tool, naming the source${C_NC}\n"
    printf "  ${C_DIM}(pipeline.conf / cli-flag / interactive-setup / gui), the timestamp, and${C_NC}\n"
    printf "  ${C_DIM}your declared intended use. Tools without an acceptance record are${C_NC}\n"
    printf "  ${C_DIM}SKIPPED at annotate-time (annotate.sh pre-flight).${C_NC}\n"

    _help_h2 "HELP TOPICS  (try ${C_GREEN}./setup.sh --help <topic>${C_NC})"
    _help_kv "containers"      "the three container modes in detail (build/pull/push)"
    _help_kv "databases"       "where things land, what's shipped vs downloaded"
    _help_kv "runtime"         "how docker vs apptainer is detected and overridden"
    _help_kv "hf"              "HuggingFace token plumbing for the ${C_GREEN}llm${C_NC} model only"
    _help_kv "reproducibility" "provenance (image labels, version pins, license docs)"

    _help_h2 "EXAMPLES"
    _help_example "./setup.sh"                                        "default: BUILD images, then download databases"
    _help_example "./setup.sh --pull"                                 "legacy: reuse already-built local images"
    _help_example "./setup.sh --containers-only"                      "phase 1 only -- leave databases for later"
    _help_example "./setup.sh --databases-only --tool pfam --redo"    "re-download just the pfam database from scratch"
    _help_example "./setup.sh --containers-only --tool pfam"          "build (or rebuild) only the pfam image"
    _help_example "./setup.sh --containers-only --pull --tool pfam"   "pull only the pfam image"
    _help_example "./setup.sh --dry-run"                              "preview every action without doing anything"
    _help_example "DB_ROOT=/scratch/dbs ./setup.sh --databases-only"  "put databases on a different volume for this run"

    _help_h2 "CONFIG"
    printf "  ${C_WHITE}Edit ${C_GREEN}./pipeline.conf.sh${C_NC} ${C_WHITE}to change defaults:${C_NC}\n"
    _help_kv "REGISTRY"     "local image prefix used for source-built containers (default: margie)"
    _help_kv "DB_ROOT"      "where databases install (default: \$REPO_ROOT/db)"
    _help_kv "SIF_DIR"      "where apptainer .sif files cache"
    _help_kv "RUNTIME"      "docker | apptainer | auto"
    _help_kv "THREADS"      "CPU threads per tool"
    printf "\n  ${C_WHITE}Any variable can also be overridden on the command line:${C_NC}\n"
    _help_example "THREADS=16 RUNTIME=apptainer ./setup.sh" "one-shot override of two variables"
    printf "\n"
}

# ---- topic: containers ----

print_help_containers() {
    _help_h1 "TOPIC: container setup"

    _help_h2 "WHAT IS A CONTAINER, IN PLAIN ENGLISH?"
    printf "  ${C_WHITE}A 'container' is a self-contained, frozen mini-computer that holds${C_NC}\n"
    printf "  ${C_WHITE}one annotation tool plus every library that tool needs to run.${C_NC}\n"
    printf "  ${C_WHITE}You can think of it like a sealed lunchbox: you don't have to install${C_NC}\n"
    printf "  ${C_WHITE}anything on your real machine -- you just open the lunchbox and use${C_NC}\n"
    printf "  ${C_WHITE}what's inside. When you're done, you close it and nothing leaks out.${C_NC}\n\n"
    printf "  ${C_WHITE}This pipeline uses one container per tool (one for ${C_GREEN}pfam${C_NC}${C_WHITE}, one for${C_NC}\n"
    printf "  ${C_GREEN}kegg${C_NC}${C_WHITE}, etc.). They are all stored under:${C_NC}\n"
    printf "    ${C_GREEN}processing/containers/build/<tool>/${C_NC}\n"
    printf "  ${C_WHITE}Each folder has two recipe files that build the same container:${C_NC}\n"
    _help_kv "Dockerfile"     "the recipe for the Docker runtime (and the source of truth)"
    _help_kv "apptainer.def"  "the same recipe rewritten for the Apptainer runtime"

    _help_h2 "RUNTIMES (what runs the container)"
    printf "  ${C_WHITE}You need ONE of these installed on your machine to use any container:${C_NC}\n"
    _help_kv "Docker"    "the standard runtime on laptops and CI"
    _help_kv "Apptainer" "the standard runtime on HPC clusters (no admin rights needed)"
    printf "\n  ${C_WHITE}If you have both, that's fine. The pipeline picks one automatically.${C_NC}\n"
    printf "  ${C_WHITE}If you have neither, install one before going further.${C_NC}\n"

    _help_h2 "THE THREE WAYS TO GET CONTAINERS"
    printf "  ${C_WHITE}You have three ways to obtain the containers. Pick ONE.${C_NC}\n"

    _help_h2 "WAY 1 -- BUILD locally  ${C_DIM}(this is the default)${C_NC}"
    printf "  ${C_DIM}\$${C_NC} ${C_GREEN}./setup.sh${C_NC}                            ${C_DIM}# build everything${C_NC}\n"
    printf "  ${C_DIM}\$${C_NC} ${C_GREEN}./setup.sh --tool pfam${C_NC}                ${C_DIM}# build only pfam${C_NC}\n\n"
    printf "  ${C_WHITE}What this does:${C_NC}\n"
    printf "    ${C_WHITE}- reads each tool's ${C_GREEN}Dockerfile${C_NC} ${C_WHITE}(or ${C_GREEN}apptainer.def${C_NC}${C_WHITE})${C_NC}\n"
    printf "    ${C_WHITE}- downloads the upstream source code for that tool${C_NC}\n"
    printf "    ${C_WHITE}- compiles it on YOUR machine${C_NC}\n"
    printf "    ${C_WHITE}- packages it into a container that matches your CPU type${C_NC}\n\n"
    printf "  ${C_WHITE}Behaviour depends on which runtime you have installed:${C_NC}\n"
    _help_kv "docker only"        "builds a Docker image"
    _help_kv "apptainer only"     "builds a ${C_GREEN}.sif${C_NC} file into ${C_GREEN}\$SIF_DIR/<tool>.sif${C_NC}"
    _help_kv "docker + apptainer" "Docker builds the image; Apptainer exports a ${C_GREEN}.sif${C_NC} from it"
    _help_kv "neither"            "${C_RED}error${C_NC} -- install one first"
    printf "\n  ${C_WHITE}This is the default because the resulting container is guaranteed${C_NC}\n"
    printf "  ${C_WHITE}to work on YOUR CPU, and the source code is right there if a reviewer${C_NC}\n"
    printf "  ${C_WHITE}wants to inspect what got compiled.${C_NC}\n"
    printf "  ${C_WHITE}Downside: builds take time (a few minutes per tool the first time).${C_NC}\n"

    _help_h2 "WAY 2 -- PULL prebuilt  ${C_DIM}(fastest)${C_NC}"
    printf "  ${C_DIM}\$${C_NC} ${C_GREEN}./setup.sh --pull${C_NC}                     ${C_DIM}# pull everything${C_NC}\n"
    printf "  ${C_DIM}\$${C_NC} ${C_GREEN}./setup.sh --pull --tool pfam${C_NC}         ${C_DIM}# pull only pfam${C_NC}\n\n"
    printf "  ${C_WHITE}What this does:${C_NC}\n"
    printf "    ${C_WHITE}- skips building entirely${C_NC}\n"
    printf "    ${C_WHITE}- downloads ready-made containers from a public 'image registry'${C_NC}\n"
    printf "      ${C_WHITE}(a website that hosts containers, similar to how GitHub hosts code)${C_NC}\n"
    printf "    ${C_WHITE}- the registry address is ${C_GREEN}\$REGISTRY${C_NC} ${C_WHITE}(set in ${C_GREEN}pipeline.conf.sh${C_NC}${C_WHITE})${C_NC}\n\n"
    printf "  ${C_WHITE}Use this when:${C_NC}\n"
    printf "    ${C_WHITE}- you want to get started in minutes${C_NC}\n"
    printf "    ${C_WHITE}- you trust the published images${C_NC}\n"
    printf "    ${C_WHITE}- you have a stable internet connection${C_NC}\n\n"
    printf "  ${C_WHITE}The published containers are multi-architecture (${C_GREEN}linux/amd64${C_NC} ${C_WHITE}for${C_NC}\n"
    printf "  ${C_WHITE}most laptops and HPC nodes, ${C_GREEN}linux/arm64${C_NC} ${C_WHITE}for Apple Silicon Macs);${C_NC}\n"
    printf "  ${C_WHITE}the registry serves the right one for your machine automatically.${C_NC}\n"

    _help_h2 "WAY 3 -- BUILD-AND-PUSH  ${C_RED}(developer / maintainer only)${C_NC}"
    printf "  ${C_DIM}\$${C_NC} ${C_GREEN}./setup.sh --build-and-push${C_NC}\n\n"
    printf "  ${C_WHITE}Most users should NEVER run this. It is how the maintainer of this${C_NC}\n"
    printf "  ${C_WHITE}pipeline refreshes the public registry, so that everyone else can use${C_NC}\n"
    printf "  ${C_GREEN}--pull${C_NC}${C_WHITE}. It builds containers for BOTH CPU architectures at once${C_NC}\n"
    printf "  ${C_WHITE}(${C_GREEN}linux/amd64${C_NC} ${C_WHITE}+ ${C_GREEN}linux/arm64${C_NC}${C_WHITE}) and uploads them.${C_NC}\n\n"
    printf "  ${C_WHITE}Requirements:${C_NC}\n"
    printf "    ${C_WHITE}- Docker (with the ${C_GREEN}buildx${C_NC} ${C_WHITE}plugin)${C_NC}\n"
    printf "    ${C_WHITE}- a GitHub Personal Access Token (PAT) with the ${C_GREEN}write:packages${C_NC} ${C_WHITE}scope${C_NC}\n\n"
    printf "  ${C_WHITE}The PAT (a long secret string from your GitHub account) is read from${C_NC}\n"
    printf "  ${C_WHITE}the first source available, in this order:${C_NC}\n"
    _help_step "1." "the ${C_GREEN}GH_TOKEN${C_NC} ${C_WHITE}or ${C_GREEN}GITHUB_TOKEN${C_NC} ${C_WHITE}environment variable${C_NC}"
    _help_step "2." "${C_WHITE}a file named ${C_GREEN}.gh-token${C_NC} ${C_WHITE}at the repo root (chmod 600, gitignored)${C_NC}"
    _help_step "3." "${C_WHITE}an interactive silent prompt (the typed value is saved to ${C_GREEN}.gh-token${C_NC} ${C_WHITE}for next time)${C_NC}"

    _help_h2 "WHICH WAY SHOULD YOU PICK?"
    _help_kv "first-time user" "${C_GREEN}--pull${C_NC}  ${C_DIM}(fastest, easiest)${C_NC}"
    _help_kv "publishing a paper / reviewer" "${C_GREEN}(default build)${C_NC}  ${C_DIM}(source-traceable)${C_NC}"
    _help_kv "you ARE the maintainer" "${C_GREEN}--build-and-push${C_NC}  ${C_DIM}(refresh the registry)${C_NC}"

    _help_h2 "LICENSING -- IMPORTANT BEFORE YOU PUSH"
    printf "  ${C_WHITE}Each container directory also has a ${C_GREEN}LICENSE.md${C_NC} ${C_WHITE}file with the${C_NC}\n"
    printf "  ${C_WHITE}upstream tool's licence and a plain-English summary of what you${C_NC}\n"
    printf "  ${C_WHITE}can and can't do with it.${C_NC}\n"
    _help_kv "master table" "processing/containers/build/LICENSES-SUMMARY.md"
    _help_kv "per-tool"     "processing/containers/build/<tool>/LICENSE.md"
    printf "\n  ${C_YELLOW}WARNING:${C_NC} ${C_WHITE}some tools have academic-only licences. You MUST NOT push${C_NC}\n"
    printf "  ${C_WHITE}their containers to a public registry without first removing the${C_NC}\n"
    printf "  ${C_WHITE}restricted binaries or model files. These tools are:${C_NC}\n"
    _help_kv "phobius"   "academic licence -- strip the model files before push"
    _help_kv "signalP4"  "academic licence -- strip the binary before push"
    _help_kv "psortb"    "gated by this pipeline; off until accepted"
    printf "\n  ${C_WHITE}A few other tools have restricted DATABASES (the container is fine,${C_NC}\n"
    printf "  ${C_WHITE}but you must download the data yourself, registered to your name):${C_NC}\n"
    printf "    ${C_GREEN}merops${C_NC}, ${C_GREEN}tcdb${C_NC}, ${C_GREEN}tmbed${C_NC} ${C_WHITE}(ProtT5 weights)${C_NC}, ${C_GREEN}interpro${C_NC} ${C_WHITE}(ProSite + SMART subsets)${C_NC}\n"

    _help_h2 "WHERE THINGS LIVE ON DISK"
    _help_kv "container recipes" "processing/containers/build/<tool>/"
    _help_kv "Apptainer .sif files" "\$SIF_DIR  ${C_DIM}(default: processing/containers/sifs/)${C_NC}"
    _help_kv "Docker images"     "inside the Docker daemon, listed by ${C_GREEN}docker images${C_NC}"
    printf "\n"
}

# ---- topic: databases ----

print_help_databases() {
    _help_h1 "TOPIC: database setup"

    _help_h2 "WHAT IS A DATABASE, IN PLAIN ENGLISH?"
    printf "  ${C_WHITE}A 'database' here is a folder of reference data that an annotation${C_NC}\n"
    printf "  ${C_WHITE}tool needs in order to do its job. It is NOT a server like MySQL.${C_NC}\n"
    printf "  ${C_WHITE}For example:${C_NC}\n"
    _help_kv "pfam"    "the Pfam database of known protein domain models (a few GB)"
    _help_kv "kegg"    "the KEGG list of known metabolic functions (~1 GB)"
    _help_kv "uniprot" "the UniProt-SwissProt reference protein collection (~1.3 GB)"
    printf "\n  ${C_WHITE}When ${C_GREEN}pfam${C_NC} ${C_WHITE}runs on your genome, it compares your genes against the${C_NC}\n"
    printf "  ${C_WHITE}Pfam database. So the database must be downloaded BEFORE annotation.${C_NC}\n"
    printf "  ${C_WHITE}Each database is downloaded by a small script under:${C_NC}\n"
    printf "    ${C_GREEN}processing/scripts/setup-scripts/setup-databases/download-<db>.sh${C_NC}\n"

    _help_h2 "HOW TO USE IT"
    _help_example "./setup.sh"                                          "download EVERY database (and build containers too)"
    _help_example "./setup.sh --databases-only"                         "download EVERY database, skip containers"
    _help_example "./setup.sh --databases-only --tool kegg"             "download ONLY the kegg database"
    _help_example "./setup.sh --databases-only --tool kegg --redo"      "delete the existing kegg database and re-download it"

    _help_h2 "WHAT THE SCRIPTS GUARANTEE"
    printf "  ${C_WHITE}Every download script is:${C_NC}\n"
    _help_kv "idempotent" "safe to re-run -- already-downloaded files are skipped"
    _help_kv "resumable"  "if you Ctrl-C halfway, the next run continues where it stopped"
    _help_kv "redo-able"  "${C_GREEN}--redo${C_NC} deletes everything first and downloads from scratch"
    printf "\n  ${C_WHITE}So if a download fails (network drops, etc.), just run the same${C_NC}\n"
    printf "  ${C_WHITE}command again -- it will pick up where it left off.${C_NC}\n"

    _help_h2 "DEPENDS ON CONTAINERS (a few DBs do)"
    printf "  ${C_WHITE}Most download scripts only need ${C_GREEN}wget${C_NC}/${C_GREEN}curl${C_NC} ${C_WHITE}+ ${C_GREEN}gunzip${C_NC}${C_WHITE}/${C_GREEN}tar${C_NC}${C_WHITE}, but a few use${C_NC}\n"
    printf "  ${C_WHITE}their own tool's container to do post-processing (hmmpress, diamond${C_NC}\n"
    printf "  ${C_WHITE}makedb, etc.) or to do the download itself. Those scripts REQUIRE${C_NC}\n"
    printf "  ${C_WHITE}the matching container image to exist BEFORE you run them:${C_NC}\n"
    _help_kv "pfam, pgap, tigrfam"  "need their image for ${C_GREEN}hmmpress${C_NC} indexing"
    _help_kv "tcdb, uniprot, merops" "need their image for ${C_GREEN}diamond makedb${C_NC}"
    _help_kv "dbcan, eggnog"        "need their image for the upstream download CLI"
    _help_kv "tmbed"                "uses the tmbed container itself to pull its ProtT5 model"
    printf "\n  ${C_WHITE}If you ran the default ${C_GREEN}./setup.sh${C_NC} ${C_WHITE}(containers phase first, then databases),${C_NC}\n"
    printf "  ${C_WHITE}this is automatic. If you ran ${C_GREEN}--databases-only${C_NC} ${C_WHITE}without building images${C_NC}\n"
    printf "  ${C_WHITE}first, those scripts will tell you exactly what to build:${C_NC}\n"
    _help_example "./setup.sh --containers-only --tool tmbed" "build only the tmbed image first"
    _help_example "./setup.sh --databases-only --tool tmbed"  "then run the tmbed database step"

    _help_h2 "WHERE THE DATA LANDS"
    printf "  ${C_WHITE}Default location: ${C_GREEN}\$DB_ROOT${C_NC} = ${C_GREEN}\$REPO_ROOT/db/${C_NC}\n"
    printf "  ${C_WHITE}(i.e. the ${C_GREEN}db/${C_NC} ${C_WHITE}folder next to ${C_GREEN}setup.sh${C_NC}${C_WHITE}).${C_NC}\n\n"
    printf "  ${C_WHITE}This grows large (~170 GB if you download everything). On laptops${C_NC}\n"
    printf "  ${C_WHITE}with little disk space, or on HPC where home is small, point ${C_GREEN}DB_ROOT${C_NC}\n"
    printf "  ${C_WHITE}somewhere with room:${C_NC}\n"
    _help_example "DB_ROOT=/scratch/\$USER/dbs ./setup.sh --databases-only" "send databases to a scratch volume"
    printf "\n  ${C_WHITE}The variable just needs to be set when ${C_GREEN}setup.sh${C_NC} ${C_WHITE}runs; later runs of${C_NC}\n"
    printf "  ${C_GREEN}annotate.sh${C_NC} ${C_WHITE}must use the SAME ${C_GREEN}DB_ROOT${C_NC} ${C_WHITE}so they find the data.${C_NC}\n"
    printf "  ${C_WHITE}Easiest way to make it permanent: set it in ${C_GREEN}pipeline.conf.sh${C_NC}${C_WHITE}.${C_NC}\n"

    _help_h2 "WHAT GETS DOWNLOADED"
    printf "  ${C_CYAN}15 databases downloaded as part of the annotation pipeline (required):${C_NC}\n"
    printf "    ${C_WHITE}cog, dbcan, eggnog, geneprop, interpro, kegg, merops, pfam, pgap,${C_NC}\n"
    printf "    ${C_WHITE}rasttk, tcdb, tigrfam, tmbed, uniprot, pangenome${C_NC}\n\n"
    printf "  ${C_CYAN}1 OPTIONAL model used after annotation (interpretation step):${C_NC}\n"
    printf "    ${C_GREEN}llm${C_NC}  ${C_WHITE}-- natural-language scoring/interpretation of the annotation results${C_NC}\n"
    printf "    ${C_DIM}only downloaded if you set LLM_BASE_MODEL / LLM_TRAINED_MODEL in pipeline.conf.sh${C_NC}\n\n"
    printf "  ${C_CYAN}4 databases bundled INSIDE their container (nothing to download):${C_NC}\n"
    printf "    ${C_GREEN}psortb${C_NC}, ${C_GREEN}deepsig${C_NC}, ${C_GREEN}signalP4${C_NC}, ${C_GREEN}phobius${C_NC}\n"
    printf "  ${C_WHITE}(these ship as part of the container image because their licences allow it)${C_NC}\n"

    _help_h2 "ONE SPECIAL DATABASE THAT NEEDS A LOGIN (OPTIONAL)"
    printf "  ${C_GREEN}llm${C_NC} ${C_WHITE}-- a large language model used to INTERPRET the annotation results${C_NC}\n"
    printf "  ${C_WHITE}     (it runs as a post-annotation scoring/explanation step; it does${C_NC}\n"
    printf "  ${C_WHITE}      NOT do annotation itself).${C_NC}\n\n"
    printf "  ${C_WHITE}If you have configured LLM_BASE_MODEL / LLM_TRAINED_MODEL in${C_NC}\n"
    printf "  ${C_GREEN}pipeline.conf.sh${C_NC}${C_WHITE} and they point at gated HuggingFace repos, the pipeline${C_NC}\n"
    printf "  ${C_WHITE}will need a free HuggingFace access token. It WILL prompt you for it.${C_NC}\n"
    printf "  ${C_WHITE}Leave those vars empty (the default) to skip llm entirely.${C_NC}\n\n"
    printf "  ${C_DIM}Note: ${C_GREEN}tmbed${C_NC} ${C_DIM}also uses an AI model, but it is PUBLIC and downloaded${C_NC}\n"
    printf "  ${C_DIM}automatically by the tmbed CONTAINER as part of normal setup -- no${C_NC}\n"
    printf "  ${C_DIM}token, no special steps. (See: tmbed in the regular DB list above.)${C_NC}\n"
    printf "  ${C_WHITE}Full HF explanation: ${C_GREEN}./setup.sh --help hf${C_NC}\n\n"
}

# ---- topic: runtime ----

print_help_runtime() {
    _help_h1 "TOPIC: runtime selection"
    printf "  ${C_WHITE}Two container runtimes are supported. The pipeline auto-detects${C_NC}\n"
    printf "  ${C_WHITE}which one(s) are available and adapts. Override with the${C_NC}\n"
    printf "  ${C_GREEN}RUNTIME${C_NC} ${C_WHITE}variable or the ${C_GREEN}--runtime${C_NC} ${C_WHITE}flag.${C_NC}\n"

    _help_h2 "VALID VALUES"
    _help_kv "auto"      "${C_DIM}(default)${C_NC} prefer apptainer if installed, else docker"
    _help_kv "docker"    "force Docker -- images stay inside the Docker daemon"
    _help_kv "apptainer" "force Apptainer -- images live as ${C_GREEN}.sif${C_NC} files under \$SIF_DIR"

    _help_h2 "WHEN TO USE WHICH"
    _help_kv "laptop / desktop"   "${C_GREEN}docker${C_NC} (via Docker Desktop or Colima)"
    _help_kv "HPC cluster"        "${C_GREEN}apptainer${C_NC} (no root needed; preinstalled on most clusters)"
    _help_kv "CI runner"          "${C_GREEN}docker${C_NC} (universally available)"

    _help_h2 "OVERRIDE EXAMPLES"
    _help_example "RUNTIME=apptainer ./setup.sh --containers-only" "env-var override"
    _help_example "./setup.sh --runtime docker --containers-only"  "flag override"
    printf "\n"
}

# ---- topic: hf ----

print_help_hf() {
    _help_h1 "TOPIC: HuggingFace setup (AI model downloads)"

    _help_h2 "WHAT IS HUGGINGFACE?"
    printf "  ${C_WHITE}HuggingFace (the website ${C_GREEN}huggingface.co${C_NC}${C_WHITE}) is the largest public${C_NC}\n"
    printf "  ${C_WHITE}repository of pre-trained AI models. Think of it as 'GitHub, but for${C_NC}\n"
    printf "  ${C_WHITE}AI model weights'. Anyone can publish a model there, and anyone with${C_NC}\n"
    printf "  ${C_WHITE}a free account can download one.${C_NC}\n"

    _help_h2 "WHY DOES THIS PIPELINE NEED IT?"
    printf "  ${C_WHITE}The OPTIONAL ${C_GREEN}llm${C_NC} ${C_WHITE}step uses a large language model to write a${C_NC}\n"
    printf "  ${C_WHITE}natural-language INTERPRETATION of the annotation results. It runs${C_NC}\n"
    printf "  ${C_WHITE}AFTER the heuristic scoring step; it does not annotate anything itself.${C_NC}\n\n"
    _help_kv "llm"   "interpretation/scoring of the finished annotation results"
    printf "\n  ${C_WHITE}If you've configured ${C_GREEN}LLM_BASE_MODEL${C_NC} ${C_WHITE}/ ${C_GREEN}LLM_TRAINED_MODEL${C_NC} ${C_WHITE}in${C_NC}\n"
    printf "  ${C_GREEN}pipeline.conf.sh${C_NC} ${C_WHITE}to point at a GATED HuggingFace repo (e.g. one of the${C_NC}\n"
    printf "  ${C_GREEN}meta-llama/*${C_NC} ${C_WHITE}models), the pipeline has to authenticate to download it.${C_NC}\n"
    printf "  ${C_WHITE}If those vars are empty, llm is skipped entirely and no token is needed.${C_NC}\n\n"
    printf "  ${C_DIM}Note: ${C_GREEN}tmbed${C_NC} ${C_DIM}also uses an AI model (ProtT5), but that one is PUBLIC --${C_NC}\n"
    printf "  ${C_DIM}it is downloaded by the tmbed container as part of the regular database${C_NC}\n"
    printf "  ${C_DIM}phase. No HuggingFace account needed.${C_NC}\n"

    _help_h2 "WHAT YOU NEED TO PROVIDE"
    printf "  ${C_WHITE}One thing: a HuggingFace ${C_GREEN}access token${C_NC}${C_WHITE}. This is a long random string${C_NC}\n"
    printf "  ${C_WHITE}that proves you have a HuggingFace account and have agreed to the${C_NC}\n"
    printf "  ${C_WHITE}model licences. You get one for free:${C_NC}\n\n"
    _help_step "1." "${C_WHITE}create a free account at ${C_GREEN}https://huggingface.co${C_NC}"
    _help_step "2." "${C_WHITE}go to ${C_GREEN}https://huggingface.co/settings/tokens${C_NC}"
    _help_step "3." "${C_WHITE}click 'New token', give it any name, choose 'Read' scope, copy it${C_NC}"
    printf "\n  ${C_WHITE}The token looks like:  ${C_GREEN}hf_AbCdEf...${C_NC}\n"
    printf "  ${C_WHITE}Some models also require you to click 'Agree to licence' on their${C_NC}\n"
    printf "  ${C_WHITE}HuggingFace page once (e.g. ${C_GREEN}meta-llama/Meta-Llama-3-*${C_NC}${C_WHITE}). The pipeline${C_NC}\n"
    printf "  ${C_WHITE}will tell you if a download fails because of this.${C_NC}\n"

    _help_h2 "WHEN WILL THE PIPELINE ASK FOR YOUR TOKEN?"
    printf "  ${C_WHITE}It asks the first time it actually needs to talk to HuggingFace${C_NC}\n"
    printf "  ${C_WHITE}for a GATED repo. Specifically:${C_NC}\n"
    _help_kv "${C_GREEN}yes${C_NC}, will prompt" "${C_GREEN}./setup.sh --tool llm${C_NC} ${C_DIM}IF a gated model is configured in pipeline.conf.sh${C_NC}"
    _help_kv "${C_GREEN}yes${C_NC}, will prompt" "vanilla ${C_GREEN}./setup.sh${C_NC} ${C_DIM}(reaches the llm step at the end)${C_NC}"
    printf "\n  ${C_WHITE}These will NOT prompt (HuggingFace token never required):${C_NC}\n"
    _help_kv "${C_RED}no${C_NC}, never asks"    "${C_GREEN}./setup.sh --tool tmbed${C_NC} ${C_DIM}(public model, downloaded by the container itself)${C_NC}"
    _help_kv "${C_RED}no${C_NC}, never asks"    "${C_GREEN}./setup.sh --tool pfam${C_NC} ${C_DIM}(or any other plain database)${C_NC}"
    _help_kv "${C_RED}no${C_NC}, never asks"    "${C_GREEN}./setup.sh --containers-only${C_NC} ${C_DIM}(database phase is skipped)${C_NC}"
    printf "\n  ${C_WHITE}Once you've provided the token once, it is cached and reused -- you${C_NC}\n"
    printf "  ${C_WHITE}won't be prompted again unless you ask to reset it.${C_NC}\n"

    _help_h2 "WHERE THE TOKEN IS STORED"
    _help_kv "file"       "processing/.hf-env/hf_token"
    _help_kv "permissions" "chmod 600  ${C_DIM}(only your user can read it)${C_NC}"
    _help_kv "git"        "gitignored  ${C_DIM}(will not be committed by accident)${C_NC}"

    _help_h2 "THE 'HF ENV' -- A SMALL PYTHON HELPER"
    printf "  ${C_WHITE}To talk to HuggingFace, the pipeline needs a small Python program${C_NC}\n"
    printf "  ${C_WHITE}called ${C_GREEN}huggingface_hub${C_NC}${C_WHITE}. We install it into a private folder, so${C_NC}\n"
    printf "  ${C_WHITE}it does NOT touch your system Python or your home directory:${C_NC}\n"
    _help_kv "location" "processing/.hf-env/  ${C_DIM}(an isolated Python virtual environment)${C_NC}"
    printf "\n  ${C_WHITE}This folder is created automatically the first time it is needed${C_NC}\n"
    printf "  ${C_WHITE}(same trigger as the token prompt above), and is reused after that.${C_NC}\n"
    printf "  ${C_WHITE}To get rid of everything HuggingFace-related: ${C_GREEN}rm -rf processing/.hf-env/${C_NC}\n"

    _help_h2 "WAYS TO PROVIDE THE TOKEN  (checked in this order)"
    _help_step "1." "${C_GREEN}--hf-token-file FILE${C_NC}             ${C_WHITE}best for SLURM / CI -- no prompt${C_NC}"
    _help_step "2." "${C_GREEN}\$HUGGING_FACE_HUB_TOKEN${C_NC}         ${C_WHITE}standard HuggingFace environment variable${C_NC}"
    _help_step "3." "${C_GREEN}processing/.hf-env/hf_token${C_NC}     ${C_WHITE}cached from a previous run${C_NC}"
    _help_step "4." "${C_GREEN}interactive prompt${C_NC}                ${C_WHITE}silent input (only works on a terminal)${C_NC}"

    _help_h2 "ROTATING / REPLACING YOUR TOKEN"
    _help_example "./setup.sh --databases-only --tool llm --reset-hf-token" "wipe the cached token and prompt for a new one"

    _help_h2 "RUNNING ON SLURM / CI  (no terminal available)"
    printf "  ${C_WHITE}Interactive prompts will not work on a compute node, so save the${C_NC}\n"
    printf "  ${C_WHITE}token to a file once on the login node and pass that file in:${C_NC}\n\n"
    printf "  ${C_DIM}\$${C_NC} ${C_GREEN}echo 'hf_AbCdEf...' > ~/.hf_token && chmod 600 ~/.hf_token${C_NC}\n"
    printf "  ${C_DIM}\$${C_NC} ${C_GREEN}sbatch accessory-files/slurm/databases.slurm --tool llm --hf-token-file ~/.hf_token${C_NC}\n"
    printf "\n"
}

# ---- topic: reproducibility ----

print_help_reproducibility() {
    _help_h1 "TOPIC: reproducibility & publication defensibility"
    printf "  ${C_WHITE}Every container image carries a provenance chain a reviewer can verify.${C_NC}\n"

    _help_h2 "1. PINNED UPSTREAM SOURCES"
    printf "  ${C_GREEN}processing/containers/build/<tool>/VERSIONS${C_NC}\n"
    printf "  ${C_WHITE}Lists exact upstream version + URL (tarball, git tag, or pip release).${C_NC}\n"

    _help_h2 "2. MULTI-STAGE FROM-SOURCE DOCKERFILE"
    printf "  ${C_GREEN}processing/containers/build/<tool>/Dockerfile${C_NC}\n"
    printf "  ${C_WHITE}Compiles upstream binaries from the URLs in VERSIONS. No opaque${C_NC}\n"
    printf "  ${C_WHITE}pre-built layers from third-party registries beyond ${C_GREEN}debian:12-slim${C_NC}\n"
    printf "  ${C_WHITE}and ${C_GREEN}python:3.11-slim${C_NC}${C_WHITE}.${C_NC}\n"

    _help_h2 "3. BUILD-TIME PROVENANCE FILE  (inside the image)"
    printf "  ${C_GREEN}/etc/pipeline-build.json${C_NC}\n"
    printf "  ${C_WHITE}Records tool name, upstream version, base image, build date.${C_NC}\n"

    _help_h2 "4. OCI IMAGE LABELS"
    _help_kv "org.opencontainers.image.revision" "short git SHA of this repo at build time"
    _help_kv "org.opencontainers.image.created"  "ISO UTC build timestamp"
    _help_kv "org.opencontainers.image.source"   "github.com/sajalbhattarai/containers"
    _help_kv "org.opencontainers.image.licenses" "SPDX expression"
    _help_kv "org.opencontainers.image.version"  "upstream version pin"
    printf "\n  ${C_WHITE}Inspect any image:${C_NC}\n"
    _help_example "docker buildx imagetools inspect \$REGISTRY/<tool>:latest" "show all labels + manifest"

    _help_h2 "5. VERBATIM LICENCE DOCUMENTATION"
    _help_kv "per-tool"     "processing/containers/build/<tool>/LICENSE.md"
    _help_kv "master table" "processing/containers/build/LICENSES-SUMMARY.md"

    _help_h2 "6. REPRODUCE A SINGLE TOOL END-TO-END"
    _help_example "./setup.sh --containers-only --tool pfam"                          "rebuild the image"
    _help_example "docker run --rm \$REGISTRY/pfam:latest cat /etc/pipeline-build.json" "inspect provenance"
    _help_example "docker run --rm \$REGISTRY/pfam:latest cat /opt/pfam/VERSIONS"     "inspect version pin"
    _help_example "docker run --rm \$REGISTRY/pfam:latest cat /opt/pfam/LICENSE.md"   "inspect licence"

    _help_h2 "7. MULTI-ARCH PARITY FOR CROSS-PLATFORM REVIEWERS"
    printf "  ${C_GREEN}./setup.sh --build-and-push${C_NC} ${C_WHITE}builds ${C_GREEN}linux/amd64${C_NC} ${C_WHITE}+ ${C_GREEN}linux/arm64${C_NC}\n"
    printf "  ${C_WHITE}simultaneously, so a reviewer on Apple Silicon and one on x86 Linux${C_NC}\n"
    printf "  ${C_WHITE}pull the same manifest list and run bit-identical (per-arch) binaries.${C_NC}\n\n"
}

# ---- dispatcher used by setup.sh ----

print_help_setup() {
    case "${1:-main}" in
        main|"")               print_help_main ;;
        containers)            print_help_containers ;;
        databases|db)          print_help_databases ;;
        runtime)               print_help_runtime ;;
        hf|huggingface)        print_help_hf ;;
        repro|reproducibility) print_help_reproducibility ;;
        *)
            print_help_main
            printf "\n${C_RED}(unknown help topic: %s)${C_NC}\n" "$1" >&2
            printf "${C_DIM}Available topics: containers, databases, runtime, hf, reproducibility${C_NC}\n" >&2
            ;;
    esac
}

# Alias for callers that use print_help.
print_help() { print_help_setup "$@"; }
