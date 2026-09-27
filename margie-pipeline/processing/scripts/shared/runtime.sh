# shared/runtime.sh — detects the container runtime and builds image and SIF
# paths. Sourced after pipeline.conf.sh (uses REGISTRY, SIF_DIR).

# Picks the runtime from RUNTIME=auto|docker|podman|container|apptainer|singularity:
#   docker, podman       OCI images <registry>/<tool>:latest
#   container            Apple's native runtime on macOS (same images, its own store)
#   apptainer            .sif files under $SIF_DIR (singularity is treated the same)
# auto prefers Apptainer (an HPC host), then a running Docker, Podman, then
# Apple's container.
detect_runtime() {
    case "${RUNTIME:-auto}" in
        docker|podman|container) echo "$RUNTIME"; return ;;
        apptainer|singularity)   echo apptainer;  return ;;
        auto)
            if   command -v apptainer   >/dev/null 2>&1; then echo apptainer
            elif command -v singularity >/dev/null 2>&1; then echo apptainer
            elif command -v docker      >/dev/null 2>&1 \
                 && docker info --format '{{.ID}}' >/dev/null 2>&1; then echo docker
            elif command -v podman      >/dev/null 2>&1 \
                 && podman info >/dev/null 2>&1; then echo podman
            elif [[ "$(uname -s)" == Darwin ]] && command -v container >/dev/null 2>&1 \
                 && container system status >/dev/null 2>&1; then echo container
            else
                echo "[runtime] ERROR: no container runtime found (install Docker, Podman, Apple's container, or Apptainer)" >&2
                return 1
            fi
            ;;
        *)
            echo "[runtime] ERROR: invalid RUNTIME='${RUNTIME}' (use docker|podman|container|apptainer|auto)" >&2
            return 1
            ;;
    esac
}

# Prints the apptainer-family binary on this host (apptainer, else singularity).
apptainer_bin() {
    if command -v apptainer >/dev/null 2>&1; then echo apptainer; else echo singularity; fi
}

# Prints the OCI image name <registry>/<tool>:<tag>.
docker_image() {
    local tool="$1"
    local tag="${2:-latest}"
    printf '%s/%s:%s\n' "${REGISTRY}" "${tool}" "${tag}"
}

# Prints the Apptainer SIF path $SIF_DIR/<tool>.sif.
sif_path() {
    local tool="$1"
    printf '%s/%s.sif\n' "${SIF_DIR}" "${tool}"
}

# Prints the docker:// source URI for `apptainer pull`.
sif_source() {
    local tool="$1"
    local tag="${2:-latest}"
    printf 'docker://%s/%s:%s\n' "${REGISTRY}" "${tool}" "${tag}"
}
