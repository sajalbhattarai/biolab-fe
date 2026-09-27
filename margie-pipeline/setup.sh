#!/usr/bin/env bash
# setup.sh — builds or pulls the container images and downloads the reference
# databases, behind the licence gates. Safe to re-run.
set -euo pipefail

# step 1 of 5 — loads config and helpers, starts the log file
here=$(cd "$(dirname "$0")" && pwd)
. "$here/pipeline.conf.sh"
LOG_DIR="${REPO_ROOT}/logs/setup"
. "$here/processing/scripts/shared/logging.sh"
. "$here/processing/scripts/shared/colors.sh"
. "$here/processing/scripts/shared/help-render.sh"
. "$here/processing/scripts/shared/runtime.sh"
. "$here/processing/scripts/shared/licence-gate.sh"
. "$here/processing/scripts/shared/license-agreement.sh"
. "$here/processing/scripts/help/setup-help.sh"

tag=setup
log_invocation "$0" "$@"

ok "running as: ${PIPELINE_USER}"

# Per-run skip ledger shared by every child licence gate; the skip report at
# the end reads it back.
export LICENCE_SKIP_LEDGER="$LOG_DIR/licence-skipped.${LOG_INVOCATION_ID:-$$}.tsv"
: > "$LICENCE_SKIP_LEDGER"
# Once the statement is typed at one gate, later gates in this run ask yes/no.
export LICENCE_SESSION_FILE="$LOG_DIR/.licence-session.${LOG_INVOCATION_ID:-$$}"
rm -f "$LICENCE_SESSION_FILE"

# step 2 of 5 — parses the command line (full list in help/setup-help.sh)
#   default           builds images from source (docker, else apptainer-native)
#   --pull            reuses already-built local images/SIFs
#   --redo            deletes cached images/SIFs/DB files first
#   --build-and-push  developer-only multi-arch docker build pushed to $REGISTRY
# `need` holds a flag (like --tool) whose value is the next argument.
containers=yes databases=yes mode=build generate_slurm=no
extra= build_extra= pull_extra= tools=() need= redo=no

for arg in "$@"; do
    [ -n "$need" ] && {
        case "$need" in
            runtime)        RUNTIME="$arg" ;;
            tool)           tools+=("$arg") ;;
            hf_token_file)  extra="$extra --hf-token-file $arg" ;;
            licence_statement)
                            licence_statement_matches "$arg" || {
                                err "--licence-statement: that is not the licence statement. It reads:"
                                err "  $LICENCE_REQUIRED_STATEMENT"
                                exit 1
                            }
                            export LICENCE_STATEMENT="$arg" ;;
            help)           print_help "$arg"; exit 0 ;;
        esac

        need=
        continue
    }

    case "$arg" in
        --containers-only) databases=no ;;
        --databases-only)  containers=no ;;
        --build)           : ;;                          # build is the default
        --pull)            mode=pull ;;
        --build-and-push)  mode=build_and_push; build_extra="$build_extra --build-and-push" ;;
        --no-cache)        build_extra="$build_extra --no-cache" ;;
        --redo)            redo=yes
                           extra="$extra --redo"
                           build_extra="$build_extra --redo"
                           pull_extra="$pull_extra --redo" ;;
        --dry-run)         extra="$extra --dry-run"
                           build_extra="$build_extra --dry-run"
                           pull_extra="$pull_extra --dry-run" ;;
        --hf-token-file)   need=hf_token_file ;;
        --reset-hf-token)  extra="$extra --reset-hf-token" ;;
        --licence-statement|--license-statement)
                           need=licence_statement ;;
        --accept-merops-licence|--accept-merops-license)
                           extra="$extra --accept-merops-licence" ;;
        --accept-tcdb-licence|--accept-tcdb-license)
                           extra="$extra --accept-tcdb-licence" ;;
        --accept-tmbed-licence|--accept-tmbed-license)
                           extra="$extra --accept-tmbed-licence" ;;
        --accept-interpro-licence|--accept-interpro-license)
                           extra="$extra --accept-interpro-licence" ;;
        --accept-phobius-licence|--accept-phobius-license)
                           export PHOBIUS_ACCEPT_LICENCE=1 ;;
        --accept-psortb-licence|--accept-psortb-license)
                           export PSORTB_ACCEPT_LICENCE=1 ;;
        --accept-all-licences|--accept-all-licenses)
                           export LICENCE_ACCEPT_ALL=1
                           export MEROPS_ACCEPT_LICENCE=1
                           export TCDB_ACCEPT_LICENCE=1
                           export TMBED_ACCEPT_LICENCE=1
                           export INTERPRO_ACCEPT_LICENCE=1
                           export PHOBIUS_ACCEPT_LICENCE=1
                           export PSORTB_ACCEPT_LICENCE=1
                           extra="$extra --accept-all-licences" ;;
        --generate-slurm)  generate_slurm=yes ;;
        --runtime|--tool)  need=${arg#--} ;;
        -h|--help)         need=help ;;
        *) err "huh? $arg"; exit 1 ;;
    esac
done

[ "$need" = help ] && {
    print_help main

    exit 0
}

[ -n "$need" ] && {
    err "--${need//_/-} needs a value"

    exit 1
}

# step 2b — regenerates the *.slurm job scripts from pipeline.conf.sh section 9
# on every run (--generate-slurm stops after this step).
_gen_script="$here/processing/scripts/setup-scripts/generate-slurm-scripts.sh"
[[ -x "$_gen_script" ]] || { err "SLURM generator not found: $_gen_script"; exit 1; }
"$_gen_script"
log "SLURM job scripts written to repo root (containers / databases / llm / annotate / setup)"
log "  Edit pipeline.conf.sh section 9 to change cluster account, partition, or resource limits."
if [[ "$generate_slurm" == yes ]]; then
    ok "SLURM scripts refreshed."
    exit 0
fi

# step 3 of 5 — pipeline-level licence agreement
pipeline_licence_agreement "$extra" || exit 1

# step 4 of 5 — container images (skipped with --databases-only), by mode:
# build, pull, or build_and_push.
if [ "$containers" = yes ]; then
    double_hr "PHASE 1/2 :: CONTAINER IMAGES"
    log "containers"

    setup_dir="$here/processing/scripts/setup-scripts/setup-containers"

    case "$mode" in
      build_and_push)
        command -v docker >/dev/null 2>&1 || { err "--build-and-push requires docker"; exit 1; }

        # Registry token, in order:
        #   1. env var GH_TOKEN / GITHUB_TOKEN (never persisted)
        #   2. repo-root .gh-token (gitignored, chmod 600)
        #   3. interactive prompt (saved to .gh-token, chmod 600)
        token_file="$here/.gh-token"
        gh_user="${GH_USER:-$(git -C "$here" config user.name 2>/dev/null || true)}"
        [ -n "$gh_user" ] || { err "--build-and-push needs a registry user: set GH_USER"; exit 1; }
        gh_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

        if [ -z "$gh_token" ] && [ -f "$token_file" ]; then
            # Tightens a group/world-readable token file.
            perm=$(stat -f '%A' "$token_file" 2>/dev/null || stat -c '%a' "$token_file" 2>/dev/null || echo 600)
            if [ "$perm" != 600 ] && [ "$perm" != 400 ]; then
                warn "$token_file is mode $perm; tightening to 600"
                chmod 600 "$token_file"
            fi
            gh_token=$(cat "$token_file")
        fi

        if [ -z "$gh_token" ]; then
            # Prompts with echo off.
            printf 'GitHub PAT (write:packages) for %s: ' "$gh_user" >&2
            stty -echo 2>/dev/null || true
            IFS= read -r gh_token
            stty echo 2>/dev/null || true
            printf '\n' >&2
            [ -n "$gh_token" ] || { err "empty token"; exit 1; }
            ( umask 077; printf '%s' "$gh_token" >"$token_file" )
            ok "saved token to $token_file (chmod 600, gitignored)"
        fi

        log "docker login as $gh_user"
        printf '%s' "$gh_token" | docker login "$REGISTRY" -u "$gh_user" --password-stdin >/dev/null \
            || { err "docker login failed"; exit 1; }

        unset gh_token

        build_extra_with_tools="$build_extra"
        for tool in "${tools[@]+"${tools[@]}"}"; do
            build_extra_with_tools="$build_extra_with_tools --tool $tool"
        done
        "$setup_dir/build-all.sh" $build_extra_with_tools

        log "push"
        push_args=""
        case "$extra" in *--dry-run*) push_args="--dry-run" ;; esac
        push_extra_with_tools="$push_args"
        for tool in "${tools[@]+"${tools[@]}"}"; do
            push_extra_with_tools="$push_extra_with_tools --tool $tool"
        done
        "$setup_dir/push-all.sh" $push_extra_with_tools
        ;;

      build)
        build_extra_with_tools="$build_extra"
        for tool in "${tools[@]+"${tools[@]}"}"; do
            build_extra_with_tools="$build_extra_with_tools --tool $tool"
        done
        "$setup_dir/build-all.sh" $build_extra_with_tools
        ;;

      pull)
        runtime="$(detect_runtime)"
        if [ "$runtime" = docker ]; then
            runner="$setup_dir/pull-docker/pull-all.sh"
        else
            runner="$setup_dir/pull-apptainer/pull-all.sh"
        fi
        pull_extra_with_tools="$pull_extra"
        for tool in "${tools[@]+"${tools[@]}"}"; do
            pull_extra_with_tools="$pull_extra_with_tools --tool $tool"
        done
        $runner $pull_extra_with_tools
        ;;
    esac
fi

# step 5 of 5 — reference databases (skipped with --containers-only) via
# download-all-databases.sh; --tool narrows it.
if [ "$databases" = yes ]; then
    double_hr "PHASE 2/2 :: REFERENCE DATABASES"
    log "databases"

    runner="$here/processing/scripts/setup-scripts/setup-databases/download-all-databases.sh"
    db_args="$extra"

    for tool in "${tools[@]+"${tools[@]}"}"; do
        db_args="$db_args --tool $tool"
    done

    $runner $db_args
fi

# Reports licence-gated tools skipped this run.
print_licence_skip_report
rm -f "$LICENCE_SESSION_FILE"

ok "done. — sb"
