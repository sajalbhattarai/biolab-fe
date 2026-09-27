#!/usr/bin/env bash
# setup-containers/lib.sh — shared build logic for the tool images.
# Sourced by build-all.sh; builds with docker buildx, or natively with Apptainer.
set -euo pipefail

HERE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_BD="$(cd "$HERE_LIB/../../../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT_BD/pipeline.conf.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_BD/processing/scripts/shared/colors.sh"
# shellcheck disable=SC1091
: "${LOG_DIR:=$REPO_ROOT_BD/logs/containers}"
# shellcheck disable=SC1091
source "$REPO_ROOT_BD/processing/scripts/shared/logging.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_BD/processing/scripts/shared/licence-gate.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_BD/processing/scripts/shared/license-agreement.sh"
log_invocation "$0" "$@"
# Asks for the pipeline licence agreement; a no-op when MARGIE_ACCEPT_TERMS=1.
pipeline_licence_agreement "" || exit 1

tag="build"

# Tools that ship x86_64-only binaries (BLAST+ tarball, InterProScan JVM bundle, Phobius decodeanhmm).
AMD64_ONLY=(cog interpro phobius)

# Exits unless docker, a running daemon and buildx are all available.
_require_docker_buildx() {
    command -v docker >/dev/null 2>&1 || { err "docker not in PATH"; exit 1; }
    docker info --format '{{.ID}}' >/dev/null 2>&1 \
        || { err "docker daemon not running (start Docker Desktop)"; exit 1; }
    docker buildx version >/dev/null 2>&1 \
        || { err "docker buildx not available — needed for multi-arch builds"; exit 1; }
}

# Creates or selects the multi-arch "margie-builder" buildx builder.
_ensure_builder() {
    local name="margie-builder"
    if ! docker buildx inspect "$name" >/dev/null 2>&1; then
        log "creating buildx builder: $name"
        docker buildx create --name "$name" --driver docker-container \
            --platform linux/amd64,linux/arm64 --use >/dev/null
        docker buildx inspect --bootstrap "$name" >/dev/null
    else
        docker buildx use "$name" >/dev/null
    fi
}

# Returns 0 when the tool is in AMD64_ONLY.
_is_amd64_only() {
    local t="$1"
    for x in "${AMD64_ONLY[@]+"${AMD64_ONLY[@]}"}"; do [[ "$x" == "$t" ]] && return 0; done
    return 1
}

# Runs "<image> --help" as a smoke check (cog only).
_post_build_smoke_docker() {
    local tool="$1" image="$2" dryrun="$3"
    [[ "$tool" == "cog" ]] || return 0
    log "── smoke-check $tool docker image (run --help)"
    if [[ "$dryrun" == yes ]]; then
        echo "  [dry-run] docker run --rm $image --help"
        return 0
    fi
    docker run --rm "$image" --help >/dev/null
}

# Runs "<sif> --help" as a smoke check (cog only).
_post_build_smoke_apptainer() {
    local tool="$1" sif="$2" apc="$3" dryrun="$4"
    [[ "$tool" == "cog" ]] || return 0
    log "── smoke-check $tool SIF (run --help)"
    if [[ "$dryrun" == yes ]]; then
        echo "  [dry-run] $apc run $sif --help"
        return 0
    fi
    "$apc" run "$sif" --help >/dev/null
}

# build_one <tool> [--build-and-push] [--no-cache] [--redo] [--dry-run]
# Runs the licence gate, then builds with docker buildx when available, otherwise with Apptainer.
build_one() {
    local tool="$1"; shift
    local push=no nocache=no dryrun=no redo=no
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --build-and-push|--push) push=yes; shift ;;
            --no-cache) nocache=yes; shift ;;
            --redo)     redo=yes; shift ;;
            --dry-run)  dryrun=yes; shift ;;
            *) warn "ignoring unknown arg: $1"; shift ;;
        esac
    done

    local ctx="$BUILD_DIR/$tool"
    [[ -d "$ctx" ]] || { err "$tool — no build dir at $ctx"; return 1; }

    # Licence gate for tools with restrictive upstream terms; exit code 77 marks a skip.
    case "$tool" in
        phobius)
            licence_gate phobius PHOBIUS_ACCEPT_LICENCE --accept-phobius-licence \
                "./setup.sh --containers-only --tool phobius --accept-phobius-licence" <<'NOTICE' || return 77
  ================================================================
  WHY LICENSING MATTERS FOR Phobius
  ================================================================
  Phobius was developed at the Stockholm Bioinformatics Centre (SBC)
  and predicts both transmembrane topology and signal peptides in a
  single model. It is provided FREE for academic users but is NOT
  redistributable, and commercial use requires a paid licence from
  DTU. The pipeline never bundles Phobius binaries in any pushed
  image — each user must download and affirm the terms themselves.

  ── TOOLS ────────────────────────────────────────────────────────

  ┌─ Phobius 1.01 (signal peptide + TM topology prediction) ── ⚠️
  │ Licence quoted from https://phobius.sbc.su.se/data.html:
  │
  │   "Phobius is available free of charge to academic users.
  │    Commercial users must contact us for a licence.
  │    You are NOT allowed to redistribute the program or to
  │    host it on another server. End users must download the
  │    software themselves from this page."
  │
  │ * ACADEMIC use: FREE. Citation REQUIRED.
  │ * COMMERCIAL use: REQUIRES a paid licence from DTU.
  │   Contact: software@cbs.dtu.dk
  │
  │ Phobius is NEVER bundled in any pushed Docker/Apptainer image.
  │ Each end user downloads phobius101_linux.tgz themselves.
  │
  │ Citation: Kall L. et al. (2007) NAR 35:W429-W432
  └────────────────────────────────────────────────────────────────

  By agreeing below, you declare, on your own responsibility, that:
    (a) Your use is academic / non-commercial, OR
    (b) A commercial Phobius licence has already been obtained
        from DTU (software@cbs.dtu.dk).
  Licence compliance is the sole responsibility of the end user.

  All agreements are recorded and logged with the pipeline version
  (git commit hash). A copy of your acceptance record will be
  saved in: logs/licensing/

  ================================================================
NOTICE
            ;;
        psortb)
            licence_gate psortb PSORTB_ACCEPT_LICENCE --accept-psortb-licence \
                "./setup.sh --containers-only --tool psortb --accept-psortb-licence" <<'NOTICE' || return 77
  ================================================================
  PSORTb 3.0 IS GATED IN THIS PIPELINE
  ================================================================
  PSORTb (subcellular localization) is kept off until you accept it.
  Read its upstream terms before enabling it.

  ┌─ PSORTb 3.0 (Brinkman Laboratory, Simon Fraser University) ────
  │ Upstream: https://psort.org/
  │ Source:   https://github.com/brinkmanlab/psortb_commandline_docker
  │
  │ Citation: Yu N.Y. et al. (2010) Bioinformatics 26(13):1608-1615
  └────────────────────────────────────────────────────────────────

  By agreeing below, you declare that you have read PSORTb's upstream
  terms and that your use complies with them.
  Licence compliance is the sole responsibility of the end user.

  All agreements are recorded and logged with the pipeline version
  (git commit hash). A copy of your acceptance record will be
  saved in: logs/licensing/

  ================================================================
NOTICE
            ;;
    esac

    # Detects the available runtimes.
    local have_docker=no have_apptainer=no
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        have_docker=yes
    fi
    if command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1; then
        have_apptainer=yes
    fi

    if [[ "$push" == yes ]]; then
        [[ "$have_docker" == yes ]] || { err "$tool — --build-and-push requires docker"; return 1; }
        _docker_build_one "$tool" "$ctx" "$push" "$nocache" "$redo" "$dryrun"
        return $?
    fi

    local rc=0
    if [[ "$have_docker" == yes ]]; then
        _docker_build_one "$tool" "$ctx" no "$nocache" "$redo" "$dryrun"
        rc=$?
    elif [[ "$have_apptainer" == yes ]]; then
        _apptainer_build_one "$tool" "$ctx" "$nocache" "$redo" "$dryrun"
        rc=$?
    else
        err "$tool — neither docker nor apptainer found; cannot build"
        return 1
    fi

    return $rc
}

# _docker_build_one <tool> <ctx> <push:yes|no> <nocache:yes|no> <redo:yes|no> <dryrun:yes|no>
# Builds with docker buildx, then exports a .sif through docker-daemon:// when Apptainer is present.
_docker_build_one() {
    local tool="$1" ctx="$2" push="$3" nocache="$4" redo="$5" dryrun="$6"
    [[ -f "$ctx/Dockerfile" ]] || { err "$tool — no Dockerfile under $ctx"; return 1; }



    _require_docker_buildx
    _ensure_builder

    local image="$REGISTRY/$tool:latest"
    local platforms="${PLATFORMS:-linux/amd64,linux/arm64}"
    _is_amd64_only "$tool" && platforms="linux/amd64"

    # --redo removes the local image and any .sif so the rebuild is fresh.
    if [[ "$redo" == yes && "$dryrun" != yes ]]; then
        docker image rm -f "$image" >/dev/null 2>&1 || true
        rm -f "$SIF_DIR/$tool.sif"
    fi

    # Multi-arch images cannot be --load'ed, so a local build uses the host architecture only.
    if [[ "$push" != yes && "$platforms" == *,* ]]; then
        local host_arch
        case "$(uname -m)" in
            arm64|aarch64) host_arch=linux/arm64 ;;
            *)             host_arch=linux/amd64 ;;
        esac
        platforms="$host_arch"
    fi

    # OCI provenance labels.
    local git_commit; git_commit="$(git -C "$REPO_ROOT_BD" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    local build_date; build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local -a args=(
        docker buildx build
        --platform "$platforms"
        --label "org.opencontainers.image.revision=$git_commit"
        --label "org.opencontainers.image.created=$build_date"
        -t "$image"
        "$ctx"
    )
    [[ "$nocache" = yes ]] && args+=( --no-cache )
    if [[ "$push" = yes ]]; then
        args+=( --push )
    else
        args+=( --load )
    fi

    log "── building $tool  →  $image  ($platforms)"
    if [[ "$dryrun" = yes ]]; then
        echo "  [dry-run] ${args[*]}"
        return 0
    fi

    if ! "${args[@]+"${args[@]}"}"; then
        err "$tool build failed"
        return 1
    fi
    ok "$tool built ($image)"
    if ! _post_build_smoke_docker "$tool" "$image" "$dryrun"; then
        err "$tool docker smoke-check failed"
        return 1
    fi

    # Exports an Apptainer .sif from the local daemon image (offline, no registry pull).
    if [[ "$push" != yes ]]; then
        local apc=""
        if   command -v apptainer   >/dev/null 2>&1; then apc=apptainer
        elif command -v singularity >/dev/null 2>&1; then apc=singularity
        fi
        if [[ -n "$apc" ]]; then
            local sif="$SIF_DIR/$tool.sif"
            mkdir -p "$SIF_DIR"
            log "── exporting $tool  →  $sif  (via $apc + docker-daemon://)"
            if [[ "$dryrun" = yes ]]; then
                echo "  [dry-run] $apc build --force $sif docker-daemon://$image"
            else
                if ! "$apc" build --force "$sif" "docker-daemon://$image"; then
                    warn "$tool — SIF export failed; docker image is fine but apptainer users will need to pull/build the SIF manually"
                else
                    ok "$tool SIF ready ($sif)"
                    if ! _post_build_smoke_apptainer "$tool" "$sif" "$apc" "$dryrun"; then
                        err "$tool SIF smoke-check failed"
                        return 1
                    fi
                fi
            fi
        fi
    fi
}

# _apptainer_build_one <tool> <ctx> <nocache:yes|no> <redo:yes|no> <dryrun:yes|no>
# Builds a .sif natively (no docker) from $ctx/apptainer.def, or from the Dockerfile
# converted with spython; never falls back to a prebuilt image.
_apptainer_build_one() {
    local tool="$1" ctx="$2" nocache="$3" redo="$4" dryrun="$5"
    local sif="$SIF_DIR/$tool.sif"
    mkdir -p "$SIF_DIR"

    local apc=""
    if   command -v apptainer   >/dev/null 2>&1; then apc=apptainer
    elif command -v singularity >/dev/null 2>&1; then apc=singularity
    else err "$tool — apptainer/singularity not in PATH"; return 1
    fi

    # An existing .sif is kept unless --redo is given.
    if [[ -f "$sif" && "$redo" != yes ]]; then
        warn "$tool — $sif exists; pass --redo to rebuild"
        return 0
    fi
    [[ "$redo" == yes && "$dryrun" != yes ]] && rm -f "$sif"

    # Picks the hand-written apptainer.def, or converts the Dockerfile with spython.
    local def="" generated=""
    if [[ -f "$ctx/apptainer.def" ]]; then
        def="$ctx/apptainer.def"
        log "── building $tool  →  $sif  (via $apc + hand-written apptainer.def)"
    elif [[ -f "$ctx/Dockerfile" ]] && command -v spython >/dev/null 2>&1; then
        generated="$ctx/.apptainer.def.auto"
        log "── converting $tool Dockerfile → $generated (spython)"
        if [[ "$dryrun" = yes ]]; then
            echo "  [dry-run] spython recipe $ctx/Dockerfile > $generated"
        else
            if ! spython recipe "$ctx/Dockerfile" >"$generated" 2>/dev/null; then
                err "$tool — spython conversion failed; refusing to pull prebuilt image (build from source only)"
                rm -f "$generated"
                return 1
            fi
        fi
        def="$generated"
        log "── building $tool  →  $sif  (via $apc + auto-converted def)"
    elif [[ -f "$ctx/Dockerfile" ]]; then
        err "$tool — no apptainer.def and spython not installed; refusing to pull prebuilt image (build from source only)"
        err "      install spython (pip install spython) to auto-convert the Dockerfile"
        return 1
    else
        err "$tool — no apptainer.def or Dockerfile under $ctx"
        return 1
    fi

    local -a args=( "$apc" build )
    [[ "$nocache" == yes ]] && args+=( --disable-cache )
    args+=( --force "$sif" "$def" )

    if [[ "$dryrun" = yes ]]; then
        echo "  [dry-run] ${args[*]}"
        [[ -n "$generated" ]] && rm -f "$generated"
        return 0
    fi

    if ! (cd "$ctx" && "${args[@]+"${args[@]}"}"); then
        err "$tool — apptainer build failed"
        [[ -n "$generated" ]] && rm -f "$generated"
        return 1
    fi
    [[ -n "$generated" ]] && rm -f "$generated"
    ok "$tool SIF ready ($sif)"
    if ! _post_build_smoke_apptainer "$tool" "$sif" "$apc" "$dryrun"; then
        err "$tool SIF smoke-check failed"
        return 1
    fi
}


# build_all [--build-and-push] [--no-cache] [--redo] [--dry-run] [--accept-all-licenses] [tool ...]
# Builds the listed tools (default: every recipe under $BUILD_DIR) and prints a summary.
build_all() {
    local -a tools=() passthrough=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --accept-all-licenses|--accept-all-licences)
                export LICENCE_ACCEPT_ALL=1
                shift
                ;;
            --build-and-push|--push|--no-cache|--redo|--dry-run) passthrough+=("$1"); shift ;;
            *) tools+=("$1"); shift ;;
        esac
    done

    # Defaults to every tool with a Dockerfile or apptainer.def.
    if ! (( ${#tools[@]} )); then
        for d in "$BUILD_DIR"/*/; do
            [[ -f "$d/Dockerfile" || -f "$d/apptainer.def" ]] && tools+=( "$(basename "$d")" )
        done
    fi
    (( ${#tools[@]} )) || { warn "no build recipes under $BUILD_DIR"; return 0; }

    local total=${#tools[@]}
    log "building $total image(s): ${tools[*]}"
    local -a built=() failed=() skipped=()
    local i=0
    for t in "${tools[@]+"${tools[@]}"}"; do
        i=$((i+1))
        local remaining=$((total - i))
        double_hr "build [$i/$total] :: $t"
        log "[$i/$total] starting: $t  (built=${#built[@]}  failed=${#failed[@]}  skipped=${#skipped[@]}  remaining=$remaining)"
        local _rc=0
        build_one "$t" ${passthrough[@]+"${passthrough[@]+"${passthrough[@]}"}"} || _rc=$?
        if   (( _rc == 0  )); then
            built+=("$t")
            ok  "[$i/$total] OK     : $t  (built=${#built[@]}/$total  failed=${#failed[@]}  skipped=${#skipped[@]}  remaining=$remaining)"
        elif (( _rc == 77 )); then
            skipped+=("$t")
            warn "[$i/$total] SKIPPED: $t  (licence not confirmed; see final report)"
        else
            failed+=("$t")
            err "[$i/$total] FAILED : $t  (built=${#built[@]}/$total  failed=${#failed[@]}  skipped=${#skipped[@]}  remaining=$remaining)"
        fi
    done

    echo
    log "build summary"
    log "  total    : $total"
    log "  built    : ${#built[@]}${built[*]:+  (${built[*]})}"
    (( ${#skipped[@]} )) && warn "  skipped  : ${#skipped[@]}  (${skipped[*]})  -- licence not confirmed"
    if (( ${#failed[@]} )); then
        err "  failed   : ${#failed[@]}  (${failed[*]})"
        err "FAILED: ${failed[*]}"
        return 1
    fi
    ok "all done ($((${#built[@]}))/$total built, ${#skipped[@]} skipped)"
}
