#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# pipeline_log.sh — shared provenance-log helper for every container's runner.
#
# Source this file from a runner and call:
#
#   pipeline_log_init  <tool> <organism> <output_dir> <log_path>
#       Open a new log. Writes header (tool name, organism, ISO date, container
#       image, runner path, host arch, tool version, working directory).
#       Subsequent pipeline_log_step / _kv / _close calls append to <log_path>.
#
#   pipeline_log_kv    <key> <value>
#       Append a left-aligned "<key>        : <value>" line to the current
#       section. Use this for inputs, DB paths, thresholds, etc.
#
#   pipeline_log_section <title>
#       Open a new section banner ("STEP N: <title>"). Auto-numbered.
#
#   pipeline_log_step  <label> <command...>
#       Open a "STEP N: <label>" section, run <command...>, capture stderr,
#       record elapsed seconds and exit code. Aborts the runner on non-zero
#       exit (preserves set -e semantics). For commands whose stdout needs to
#       go to a file, redirect inside a wrapper function — this helper does
#       NOT capture stdout (it lets it pass through, matching upstream UX).
#
#   pipeline_log_close [status_message]
#       Append a RUN SUMMARY section: start time, end time, total elapsed,
#       status (default "OK").
#
# ─────────────────────────────────────────────────────────────────────────────
# Environment variables the caller (docker run wrapper) can set so the log
# records HOST paths instead of opaque container mountpoints:
#
#   PIPELINE_HOST_REPO_ROOT   /absolute/path/to/container-setup
#                              When set, any host path under it is logged
#                              repo-relative (e.g. "input/foo.fna").
#   PIPELINE_HOST_INPUT       host path mounted at /input  (e.g. .../input)
#   PIPELINE_HOST_OUTPUT      host path mounted at /output (e.g. .../output)
#   PIPELINE_HOST_DB          host path mounted at /db     (e.g. .../db)
#
# Optional metadata env vars consumed by pipeline_log_init:
#   PIPELINE_LOG_TOOL_VERSION   free-form, e.g. "HMMER 3.4 (Pfam-A 36.0)"
#   PIPELINE_LOG_IMAGE          e.g. "ghcr.io/sajalbhattarai/pfam:latest"
#   PIPELINE_LOG_OPERATOR       e.g. $USER
#   PIPELINE_LOG_DOMAIN         Archaea | Bacteria | Eukaryota | Unknown | <empty>
#   PIPELINE_LOG_ORGANISM_NOTE  free-form extra organism descriptor
# ═══════════════════════════════════════════════════════════════════════════════

# Internal state (set by pipeline_log_init):
#   PIPELINE_LOG_PATH        absolute path to the log file
#   PIPELINE_LOG_TOOL        tool name (lowercase short id, e.g. "pfam")
#   PIPELINE_LOG_ORGANISM    organism name
#   PIPELINE_LOG_STEP_INDEX  monotonically increasing step counter
#   PIPELINE_LOG_START_EPOCH unix epoch seconds at init

# ─────────────────────────────────────────────────────────────────────────────
# Translate a container path (/input/.., /output/.., /db/..) into the host
# path that was bind-mounted there, then optionally rewrite it relative to
# PIPELINE_HOST_REPO_ROOT. If no mapping env vars are set, returns the path
# unchanged. Always emits on stdout (use $(pipeline_log_host_path ...)).
# ─────────────────────────────────────────────────────────────────────────────
pipeline_log_host_path() {
    local container_path="$1"
    local translated="$container_path"

    case "$container_path" in
        /input)     [[ -n "${PIPELINE_HOST_INPUT:-}"  ]] && translated="$PIPELINE_HOST_INPUT" ;;
        /input/*)   [[ -n "${PIPELINE_HOST_INPUT:-}"  ]] && translated="${PIPELINE_HOST_INPUT}${container_path#/input}" ;;
        /output)    [[ -n "${PIPELINE_HOST_OUTPUT:-}" ]] && translated="$PIPELINE_HOST_OUTPUT" ;;
        /output/*)  [[ -n "${PIPELINE_HOST_OUTPUT:-}" ]] && translated="${PIPELINE_HOST_OUTPUT}${container_path#/output}" ;;
        /db)        [[ -n "${PIPELINE_HOST_DB:-}"     ]] && translated="$PIPELINE_HOST_DB" ;;
        /db/*)      [[ -n "${PIPELINE_HOST_DB:-}"     ]] && translated="${PIPELINE_HOST_DB}${container_path#/db}" ;;
    esac

    if [[ -n "${PIPELINE_HOST_REPO_ROOT:-}" && "$translated" == "${PIPELINE_HOST_REPO_ROOT}"* ]]; then
        local repo_relative="${translated#$PIPELINE_HOST_REPO_ROOT}"
        translated="${repo_relative#/}"
        [[ -z "$translated" ]] && translated="."
    fi
    printf '%s' "$translated"
}

# Convenience: log a key/value where the value is a path (gets translated).
pipeline_log_kv_path() {
    pipeline_log_kv "$1" "$(pipeline_log_host_path "$2")"
}

# Resolve container image reference for provenance without exposing remote dev registries.
pipeline_log_detect_image_ref() {
  local tool="$1"

  if [[ -n "${PIPELINE_LOG_IMAGE:-}" ]]; then
    printf '%s' "$PIPELINE_LOG_IMAGE"
    return 0
  fi
  if [[ -n "${APPTAINER_CONTAINER:-}" ]]; then
    printf '%s' "$APPTAINER_CONTAINER"
    return 0
  fi
  if [[ -n "${SINGULARITY_CONTAINER:-}" ]]; then
    printf '%s' "$SINGULARITY_CONTAINER"
    return 0
  fi
  if [[ -n "${PIPELINE_LOCAL_DOCKER_IMAGE:-}" ]]; then
    printf '%s' "$PIPELINE_LOCAL_DOCKER_IMAGE"
    return 0
  fi
  if [[ -n "${PIPELINE_DOCKER_IMAGE:-}" ]]; then
    printf '%s' "$PIPELINE_DOCKER_IMAGE"
    return 0
  fi

  printf 'local-%s-container' "$tool"
}

pipeline_log_init() {
    local tool="$1"
    local organism="$2"
    local output_dir="$3"
    local log_path="$4"

    PIPELINE_LOG_PATH="$log_path"
    PIPELINE_LOG_TOOL="$tool"
    PIPELINE_LOG_ORGANISM="$organism"
    PIPELINE_LOG_STEP_INDEX=0
    PIPELINE_LOG_START_EPOCH="$(date +%s)"
    export PIPELINE_LOG_PATH PIPELINE_LOG_TOOL PIPELINE_LOG_ORGANISM \
           PIPELINE_LOG_STEP_INDEX PIPELINE_LOG_START_EPOCH

    mkdir -p "$(dirname "$log_path")"

    local start_iso host_arch tool_version
    start_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    host_arch="$(uname -m 2>/dev/null || echo unknown)"
    tool_version="${PIPELINE_LOG_TOOL_VERSION:-unknown}"

    {
        printf '%s\n' "================================================================================"
        printf '%s\n' "$(printf '%s' "$tool" | tr '[:lower:]' '[:upper:]') PIPELINE — PROVENANCE RECORD"
        printf '%s\n' "================================================================================"
        printf '%-20s: %s\n' "Tool"             "$tool"
        printf '%-20s: %s\n' "Tool version"     "$tool_version"
        printf '%-20s: %s\n' "Organism"         "$organism"
        if [[ -n "${PIPELINE_LOG_DOMAIN:-}" ]]; then
            printf '%-20s: %s\n' "Domain"       "$PIPELINE_LOG_DOMAIN"
        fi
        if [[ -n "${PIPELINE_LOG_ORGANISM_NOTE:-}" ]]; then
            printf '%-20s: %s\n' "Organism note" "$PIPELINE_LOG_ORGANISM_NOTE"
        fi
        printf '%-20s: %s\n' "Date (UTC)"       "$start_iso"
        printf '%-20s: %s\n' "Container image"  "$(pipeline_log_detect_image_ref "$tool")"
        printf '%-20s: %s\n' "Container arch"   "$host_arch"
        printf '%-20s: %s\n' "Runner"           "${BASH_SOURCE[1]:-unknown}"
        if [[ -n "${PIPELINE_HOST_REPO_ROOT:-}" ]]; then
            printf '%-20s: %s\n' "Repo root"    "$PIPELINE_HOST_REPO_ROOT"
        fi
        printf '%-20s: %s\n' "Output dir"       "$(pipeline_log_host_path "$output_dir")"
        printf '%-20s: %s\n' "Working dir"      "$(pwd)"
        printf '%-20s: %s\n' "Operator"         "${PIPELINE_LOG_OPERATOR:-unknown}"
        printf '\n'
    } > "$log_path"
}

pipeline_log_kv() {
    [[ -z "${PIPELINE_LOG_PATH:-}" ]] && return 0
    printf '%-20s: %s\n' "$1" "$2" >> "$PIPELINE_LOG_PATH"
}

pipeline_log_note() {
    [[ -z "${PIPELINE_LOG_PATH:-}" ]] && return 0
    printf '%s\n' "$*" >> "$PIPELINE_LOG_PATH"
}

pipeline_log_section() {
    [[ -z "${PIPELINE_LOG_PATH:-}" ]] && return 0
    PIPELINE_LOG_STEP_INDEX=$((PIPELINE_LOG_STEP_INDEX + 1))
    {
        printf '\n'
        printf '%s\n' "================================================================================"
        printf 'STEP %d: %s\n' "$PIPELINE_LOG_STEP_INDEX" "$1"
        printf '%s\n' "================================================================================"
    } >> "$PIPELINE_LOG_PATH"
}

# Run a command, time it, log it, abort on failure.
# Usage: pipeline_log_step "label" command arg1 arg2 ...
pipeline_log_step() {
    local label="$1"; shift
    pipeline_log_section "$label"

    local cmd_str step_start step_end elapsed exit_code
    cmd_str="$*"
    pipeline_log_kv "Command" "$cmd_str"

    step_start="$(date +%s)"
    set +e
    "$@"
    exit_code=$?
    set -e
    step_end="$(date +%s)"
    elapsed=$((step_end - step_start))

    pipeline_log_kv "Elapsed (s)" "$elapsed"
    pipeline_log_kv "Exit code"   "$exit_code"

    if [[ "$exit_code" -ne 0 ]]; then
        pipeline_log_kv "Status" "FAILED"
        pipeline_log_close "FAILED at step $PIPELINE_LOG_STEP_INDEX: $label"
        exit "$exit_code"
    fi
}

# Run a heavy command with optional stdout/stderr capture to files.
# Usage:
#   pipeline_log_run_logged "<label>" "<stdout_path|''>" "<stderr_path|''>" command arg1 arg2 ...
#
#   - If stdout_path == stderr_path (and non-empty): combines via > file 2>&1
#   - If only stdout_path is set:                    redirects > stdout_path
#   - If only stderr_path is set:                    redirects 2> stderr_path
#   - If both empty:                                 lets streams pass through
#
# Records section header, full command, raw output paths, elapsed seconds,
# and exit code. Aborts the runner on non-zero exit.
pipeline_log_run_logged() {
    local label="$1" stdout_path="$2" stderr_path="$3"
    shift 3

    pipeline_log_section "$label"
    pipeline_log_kv "Command" "$*"
    [[ -n "$stdout_path" ]] && pipeline_log_kv_path "Raw stdout" "$stdout_path"
    [[ -n "$stderr_path" && "$stderr_path" != "$stdout_path" ]] \
        && pipeline_log_kv_path "Raw stderr" "$stderr_path"

    local step_start step_end elapsed exit_code
    step_start="$(date +%s)"
    set +e
    if [[ -n "$stdout_path" && "$stdout_path" == "$stderr_path" ]]; then
        "$@" > "$stdout_path" 2>&1
    elif [[ -n "$stdout_path" && -n "$stderr_path" ]]; then
        "$@" > "$stdout_path" 2> "$stderr_path"
    elif [[ -n "$stdout_path" ]]; then
        "$@" > "$stdout_path"
    elif [[ -n "$stderr_path" ]]; then
        "$@" 2> "$stderr_path"
    else
        "$@"
    fi
    exit_code=$?
    set -e
    step_end="$(date +%s)"
    elapsed=$((step_end - step_start))

    pipeline_log_kv "Elapsed (s)" "$elapsed"
    pipeline_log_kv "Exit code"   "$exit_code"

    if [[ "$exit_code" -ne 0 ]]; then
        pipeline_log_kv "Status" "FAILED"
        pipeline_log_close "FAILED at step $PIPELINE_LOG_STEP_INDEX: $label"
        exit "$exit_code"
    fi
    return 0
}

# Record a step that was skipped (e.g. because raw output already present
# and the runner has an idempotency guard).
# Usage: pipeline_log_skipped "<label>" "<command-string>" "<reason>"
pipeline_log_skipped() {
    local label="$1" cmd_str="$2" reason="${3:-skipped}"
    pipeline_log_section "$label"
    pipeline_log_kv "Command"     "$cmd_str"
    pipeline_log_kv "Elapsed (s)" "0"
    pipeline_log_kv "Status"      "SKIPPED ($reason)"
}

# ─────────────────────────────────────────────────────────────────────────────
# pipeline_log_attributions
#
# Emit the REQUIRED ATTRIBUTIONS & LICENSE NOTICES block for the current tool
# into the active pipeline log. Reproduces, verbatim where required, the
# notices each bundled component's license demands (BSD-3 copyright lines,
# GPL §6 source-mirror URLs, CC-BY/CC-BY-SA attribution lines, academic-only
# warnings, etc.) plus the canonical scholarly citations for academic re-use.
# Auto-invoked from pipeline_log_close so every run records what its outputs
# legally depend on. Safe to call directly too.
# ─────────────────────────────────────────────────────────────────────────────
pipeline_log_attributions() {
    [[ -z "${PIPELINE_LOG_PATH:-}" ]] && return 0
    local tool="${PIPELINE_LOG_TOOL:-unknown}"
    {
        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "REQUIRED ATTRIBUTIONS & LICENSE NOTICES"
        printf '%s\n' "Reproduced per the license terms of each bundled component."
        printf '%s\n' "Full text: /opt/${tool}/LICENSE.md (baked into the container image)."
        printf '%s\n' "================================================================================"
        case "$tool" in
            pfam)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[HMMER 3.4 — BSD-3-Clause, binary bundled]
  Copyright (C) 1992-2023 Sean R. Eddy
  Copyright (C) 1992-2023 The President and Fellows of Harvard College
  Copyright (C) 1992-2023 Howard Hughes Medical Institute
  Copyright (C) 1992-2023 Washington University School of Medicine
  Redistribution and use in source and binary forms, with or without
  modification, are permitted under the BSD-3-Clause license. Neither the
  names of the copyright holders nor the names of contributors may be used
  to endorse or promote products derived from this software without
  specific prior written permission.
  Citation: Eddy SR (2011) Accelerated Profile HMM Searches. PLoS Comput
            Biol 7(10):e1002195. doi:10.1371/journal.pcbi.1002195
  Source:   http://eddylab.org/software/hmmer/hmmer-3.4.tar.gz

[Pfam-A 37.0 — CC0 / Public Domain, mounted at /db]
  Pfam is released into the public domain (CC0). Attribution is requested
  as scholarly courtesy, not legally required.
  Citations: Sonnhammer ELL, Eddy SR, Durbin R (1997) Proteins 28(3):405-420
             Mistry J et al. (2021) NAR 49(D1):D412-D419. doi:10.1093/nar/gkaa913
             Paysan-Lafosse T et al. (2023) NAR 51(D1):D418-D427. doi:10.1093/nar/gkac993
  Source:    https://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam37.0/
PIPELINE_LOG_ATTRIB_EOF
                ;;
            cog)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[NCBI BLAST+ 2.16.0 — U.S. Government Work (Public Domain), binary bundled]
  Works produced by the U.S. Government are not subject to copyright
  protection in the United States. No restrictions on use or redistribution.
  Citations: Altschul SF et al. (1990) JMB 215(3):403-410 [original BLAST]
             Camacho C et al. (2009) BMC Bioinformatics 10:421 [BLAST+]
             doi:10.1186/1471-2105-10-421
  Source:    https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.16.0/

[COGclassifier 2.0.0 — MIT License, bundled via pip]
  Copyright (c) 2022 moshi4
  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software... [full MIT text in /opt/cog/LICENSE.md].
  Source:    https://github.com/moshi4/COGclassifier
  (No formal publication; cite the GitHub repository directly.)

[NCBI COG 2024 release — U.S. Government Work (Public Domain), mounted at /db]
  Citations: Tatusov RL, Koonin EV, Lipman DJ (1997) Science 278(5338):631-637.
             doi:10.1126/science.278.5338.631 [original COG]
             Galperin MY et al. (2021) NAR 49(D1):D274-D281.
             doi:10.1093/nar/gkaa1018 [2020/2024 update]
  Source:    https://ftp.ncbi.nlm.nih.gov/pub/COG/COG2024/data/

[MARGIE pipeline — MIT License]
  Source:    https://github.com/sajalbhattarai/margie-pipeline
  Author:    Sajal Bhattarai (ORCID 0000-0002-3143-5483)
  Note: MARGIE covers the container entrypoint and post-processing scripts
  only. BLAST+, COGclassifier, and the NCBI COG database are independent
  upstream components and must be cited separately (see preamble above).

Full licensing details, user acceptance record, and required citations are
recorded in the LEGAL NOTICE AND PROVENANCE PREAMBLE section above.
PIPELINE_LOG_ATTRIB_EOF
                ;;
            dbcan)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[run_dbcan 5.1.2 — GPL-3.0-or-later, bundled via pip]
  This program is free software under GPL v3 or later. NO WARRANTY.
  Per GPL §6: source code of the bundled version is available at:
  Source:   https://pypi.org/project/dbcan/5.1.2/
            https://github.com/linnabrown/run_dbcan
  Citation: Zheng J et al. (2023) NAR 51(W1):W115-W121.
            doi:10.1093/nar/gkad328 [dbCAN3]

[HMMER 3.4 — BSD-3-Clause, binary bundled]
  Copyright (C) 1992-2023 Sean R. Eddy / Harvard / HHMI / WashU.
  See /opt/dbcan/LICENSE.md for full BSD-3 text. Eddy SR (2011)
  PLoS Comput Biol 7(10):e1002195.

[DIAMOND 2.1.9 — GPL-3.0-or-later, binary bundled]
  Copyright Benjamin Buchfink and contributors. GPL v3 or later.
  Per GPL §6: source archive available at:
  Source:    https://github.com/bbuchfink/diamond/archive/refs/tags/v2.1.9.tar.gz
  Citations: Buchfink B, Xie C, Huson DH (2015) Nat Methods 12:59-60.
             doi:10.1038/nmeth.3176 [original DIAMOND]
             Buchfink B, Reuter K, Drost H-G (2021) Nat Methods 18:366-368.
             doi:10.1038/s41592-021-01101-x [DIAMOND2]

[Pyrodigal 3.5.2 — GPL-3.0-or-later, bundled via pip]
  Per GPL §6: source available at https://pypi.org/project/pyrodigal/3.5.2/
  Citation: Larralde M (2022) JOSS 7(72):4296. doi:10.21105/joss.04296

[dbCAN HMM database v13 — CC-BY-SA 4.0, mounted at /db]
  Attribution: Yin Lab, University of Nebraska–Lincoln.
  Share-alike: any derivative database MUST be released under CC-BY-SA 4.0.
  Citation:    Zheng J et al. (2023) NAR 51(W1):W115-W121.
  Source:      https://bcb.unl.edu/dbCAN2/download/Databases/
PIPELINE_LOG_ATTRIB_EOF
                ;;
            deepsig)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[DeepSig — GPL-3.0, upstream base image bolognabiocomp/deepsig (pinned by digest)]
  Copyright BolognaBiocomp / University of Bologna. GPL v3.
  Per GPL §6: source available at https://github.com/BolognaBiocomp/deepsig
  Citation: Savojardo C, Martelli PL, Fariselli P, Casadio R (2018)
            *DeepSig: deep learning improves signal peptide detection in
            proteins.* Bioinformatics 34(10):1690-1696.
            doi:10.1093/bioinformatics/btx818
  Base image pinned at:
            bolognabiocomp/deepsig@sha256:2d8ccba3406ec3814de3cc84b13047b70f26d5546acefb63a573fc20c009e9a9
PIPELINE_LOG_ATTRIB_EOF
                ;;
            eggnog)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[eggNOG-mapper 2.1.12 — AGPL-3.0-or-later, bundled via pip]
  ⚠️ AGPL §13: if you make this software's functionality available to users
  over a network (web service / SaaS), you MUST offer them the corresponding
  source code. Our pipeline only invokes it as a CLI, so the rest of the
  pipeline stays independent.
  Source:   https://pypi.org/project/eggnog-mapper/2.1.12/
            https://github.com/eggnogdb/eggnog-mapper
  Citations: Huerta-Cepas J et al. (2017) MBE 34(8):2115-2122.
             doi:10.1093/molbev/msx148 [original]
             Cantalapiedra CP et al. (2021) MBE 38(12):5825-5829.
             doi:10.1093/molbev/msab293 [v2 — this image]

[HMMER 3.4 — BSD-3-Clause; DIAMOND 2.1.9 — GPL-3.0-or-later]
  See dbcan/pfam attribution blocks above for full notices.

[eggNOG 5.0.2 database — CC-BY 4.0, mounted at /db]
  Attribution required if republished.
  Citations: Huerta-Cepas J et al. (2019) NAR 47(D1):D309-D314.
             doi:10.1093/nar/gky1085 [5.0 — this image]
             Hernández-Plaza A et al. (2023) NAR 51(D1):D389-D394.
             doi:10.1093/nar/gkac1022 [6.0, latest — not used here]
  Source:    http://eggnogdb.embl.de/download/emapperdb-5.0.2/
PIPELINE_LOG_ATTRIB_EOF
                ;;
            geneprop)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[Genome Properties — Apache-2.0 (flatfiles + scripts), mounted at /db]
  Upstream: EMBL-EBI InterPro / Genome Properties team.
  Source:   https://github.com/ebi-pf-team/genome-properties
  Citation: Richardson LJ et al. (2019) *Genome properties in 2019: a new
            companion database to InterPro for the inference of complete
            functional attributes.* NAR 47(D1):D564-D572.
            doi:10.1093/nar/gky1013
PIPELINE_LOG_ATTRIB_EOF
                ;;
            interpro)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[InterProScan 5.x — Apache-2.0, bundled]
  Free for any use, academic or commercial.
  Source:   https://github.com/ebi-pf-team/interproscan
            https://ftp.ebi.ac.uk/pub/software/unix/iprscan/5/
  Citations: Apweiler R et al. (2001) NAR 29(1):37-40 [original InterPro]
             Jones P et al. (2014) Bioinformatics 30(9):1236-1240.
             doi:10.1093/bioinformatics/btu031 [InterProScan 5]
             Paysan-Lafosse T et al. (2023) NAR 51(D1):D418-D427.
             doi:10.1093/nar/gkac993 [latest InterPro update]

[Member databases — mixed licenses]
  ⚠️ Pfam (CC0) / TIGRFAM (CC-BY-SA) / HAMAP (CC-BY) / SUPERFAMILY (free) /
     Gene3D (free) — bundled, unrestricted.
  ⚠️ ProSite — free academic; COMMERCIAL USE requires SIB licence.
       Contact: licensing@sib.swiss
  ⚠️ SMART — academic only; COMMERCIAL USE requires EMBL licence.
       Contact: smart@embl.de
  ⚠️ SignalP / TMHMM / Phobius — academic only, NOT bundled, NOT
       redistributable by us. End user must register separately if needed.
  Full breakdown: /opt/interpro/LICENSE.md
PIPELINE_LOG_ATTRIB_EOF
                ;;
            kegg)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[KofamScan 1.3.0 — MIT, bundled]
  Copyright (c) 2019 Takuya Aramaki. Permission granted to use, modify,
  redistribute under MIT terms (retain copyright notice).
  Source:   https://www.genome.jp/ftp/tools/kofam_scan/kofam_scan-1.3.0.tar.gz
            https://github.com/takaram/kofam_scan
  Citation: Aramaki T et al. (2020) *KofamKOALA: KEGG Ortholog assignment
            based on profile HMM and adaptive score threshold.* Bioinformatics
            36(7):2251-2252. doi:10.1093/bioinformatics/btz859

[HMMER 3.4 — BSD-3-Clause, binary bundled]
  See pfam attribution block above for full notice.

[GNU parallel — GPL-3.0-or-later, bundled via Debian apt]
  Per GPL §6: source available via `apt-get source parallel`.
  Citation requested: Tange O (2011) GNU Parallel — The Command-Line Power Tool.

[KOfam profiles + ko_list — Free release, mounted at /db]
  Source:   https://www.genome.jp/ftp/db/kofam/
  Citation: same as KofamScan (Aramaki et al. 2020).
PIPELINE_LOG_ATTRIB_EOF
                ;;
            merops)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[DIAMOND 2.1.9 — GPL-3.0-or-later, binary bundled]
  See dbcan attribution block above for full GPL §6 notice and DIAMOND
  citations (Buchfink 2015, 2021).

[MEROPS database 12.5 — Academic free, COMMERCIAL USE requires permission,
                         mounted at /db]
  ⚠️ Database NOT bundled in this image (downloaded by download-merops.sh).
  ⚠️ Database itself MUST NOT be redistributed.
  Academic use: free, citation required.
  Commercial use: contact rawlings@ebi.ac.uk
  Citation: Rawlings ND et al. (2018) *The MEROPS database of proteolytic
            enzymes, their substrates and inhibitors in 2017.* NAR
            46(D1):D624-D632. doi:10.1093/nar/gkx1134
  Source:   https://www.ebi.ac.uk/merops/download_list.shtml
PIPELINE_LOG_ATTRIB_EOF
                ;;
            operon)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[UniOP — MIT, vendored from github.com/hongsua/UniOP]
  Vendored commit: 68c55d2f8b890bd645f1fb0768137f6c09ba00e5 (2025-05-30)
  Source:    https://github.com/hongsua/UniOP
  Citation:  Hong S (2023) *UniOP: Predicting operons using intergenic
             distance.* GitHub repository (no formal publication).

[Prodigal 2.6.3 — GPL-3.0-or-later, bundled via Debian apt]
  Per GPL §6: source via `apt-get source prodigal` or
  https://github.com/hyattpd/Prodigal
  Citation: Hyatt D et al. (2010) *Prodigal: prokaryotic gene recognition
            and translation initiation site identification.* BMC
            Bioinformatics 11:119. doi:10.1186/1471-2105-11-119

[numpy / pandas / scikit-learn / scipy / joblib — BSD/BSD-derivative, bundled via pip]
  All permissively licensed. Retain upstream copyright notices (in their pip
  installation directories within /usr/local/lib/python3.11/).
PIPELINE_LOG_ATTRIB_EOF
                ;;
            pgap)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[HMMER 3.4 — BSD-3-Clause, binary bundled]
  See pfam attribution block above for full notice.

[NCBI PGAP HMM library (hmm_PGAP.LIB) — U.S. Government Work (Public Domain),
                                          mounted at /db]
  No restrictions on use or distribution. Citation requested as scholarly
  courtesy.
  Citation: Li W et al. (2021) *RefSeq: expanding the Prokaryotic Genome
            Annotation Pipeline reach with protein family model curation.*
            NAR 49(D1):D1020-D1028. doi:10.1093/nar/gkaa1105
  Source:   https://ftp.ncbi.nlm.nih.gov/hmm/current/
PIPELINE_LOG_ATTRIB_EOF
                ;;
            phobius)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[Phobius 1.01 — ACADEMIC LICENSE ONLY, NOT REDISTRIBUTABLE]
  ⚠️ ⚠️ ⚠️  COMPLIANCE CRITICAL  ⚠️ ⚠️ ⚠️
  Phobius is distributed by Stockholm Bioinformatics Center (SBC) under an
  academic-use-only license. The binary tarball MUST NOT be included in any
  publicly redistributed image. If this container was built from an
  end-user-obtained phobius101_linux.tgz, that copy is licensed only to the
  end user who registered with SBC.
  Commercial use requires a separate license: contact erik.sonnhammer@scilifelab.se
  Citation: Käll L, Krogh A, Sonnhammer ELL (2004) *A combined transmembrane
            topology and signal peptide prediction method.* JMB 338(5):1027-1036.
            doi:10.1016/j.jmb.2004.03.016
  Upstream: http://phobius.sbc.su.se/
PIPELINE_LOG_ATTRIB_EOF
                ;;
            psortb)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[PSORTb v3.0.2 — GPL-2.0-or-later, upstream base image brinkmanlab/psortb_commandline:1.0.2]
  Per GPL §6: source available at https://github.com/brinkmanlab/psortb_commandline_docker
  Citation: Yu NY et al. (2010) *PSORTb 3.0: improved protein subcellular
            localization prediction with refined localization subcategories
            and predictive capabilities for all prokaryotes.* Bioinformatics
            26(13):1608-1615. doi:10.1093/bioinformatics/btq249

[pftools3 (PFSEARCH/PFSCAN) — GPL-2.0, transitively bundled via base image]
  Source: https://github.com/sib-swiss/pftools3
  Same GPL-2.0 terms as PSORTb.

[Patched Perl modules — first-party patches (BSD-3-Clause) under patches/]
PIPELINE_LOG_ATTRIB_EOF
                ;;
            rasttk)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[BV-BRC CLI 1.040 — BSD-3-Clause-style, bundled as .deb]
  Copyright (C) the SEED / RAST / BV-BRC project authors.
  Source:    https://github.com/BV-BRC/BV-BRC-CLI/releases/tag/1.040
  Citations: Aziz RK et al. (2008) *The RAST Server: Rapid Annotations
             using Subsystems Technology.* BMC Genomics 9:75.
             doi:10.1186/1471-2164-9-75 [original RAST]
             Brettin T et al. (2015) *RASTtk: a modular and extensible
             implementation of the RAST algorithm…* Sci Reports 5:8365.
             doi:10.1038/srep08365 [RAST-TK algorithm]
             Olson RD et al. (2023) *Introducing the Bacterial and Viral
             Bioinformatics Resource Center (BV-BRC)…* NAR 51(D1):D678-D689.
             doi:10.1093/nar/gkac1003 [BV-BRC platform]

[SEED subsystems database — subject to SEED Project terms of use (academic +
                              commercial use permitted with citation),
                              mounted at /db/rasttk/]
  Source URL:  http://www.theseed.org/  (PubSEED + Sapling + ModelSEED)
  Citations:   Overbeek R et al. (2005) *The Subsystems Approach to Genome
               Annotation and its Use in the Project to Annotate 1000
               Genomes.* NAR 33(17):5691-5702. doi:10.1093/nar/gki866
               [original SEED]
               Overbeek R et al. (2014) *The SEED and the Rapid Annotation
               of microbial genomes using Subsystems Technology (RAST).*
               NAR 42(D1):D206-D214. doi:10.1093/nar/gkt1226 [SEED + RAST]
               Disz T et al. (2010) *Accessing the SEED Genome Databases
               via Web Services API: Tools for Programmers.* BMC
               Bioinformatics 11:319. doi:10.1186/1471-2105-11-319 [SAS /
               Sapling SOAP server bundle (sas.tgz) used by the build]

[SEED database snapshot — assembled by sajalbhattarai/seed-database-download (MIT)]
  The seed_database_long.tsv / seed_database_wide.tsv / seed_database.json
  files mounted at /db/rasttk/ are NOT a redistributable upstream release;
  they are a snapshot built by a first-party pipeline that pulls live data
  from the SEED servers and merges in ModelSEED + KEGG cross-references.
  Build pipeline:  https://github.com/sajalbhattarai/seed-database-download
  Build image:     ghcr.io/sajalbhattarai/seed-db:latest
  Build license:   MIT (the pipeline scripts only — the *data* it pulls
                   remains under the SEED Project terms of use).
  Compiled by:     Sajal Bhattarai (ORCID 0000-0002-3143-5483).
  Live sources scraped/queried by the build:
    - pubseed.theseed.org SOAP API (subsystem catalog, class hierarchy,
      role mappings, reaction data)
    - pubseed.theseed.org/subsys.cgi (author, last-modified, descriptions,
      curation notes; ISO-8859-1 decoded → UTF-8)
    - Sapling API (curator description texts)
    - svr_subsystem_spreadsheet (full variant spreadsheets per subsystem)
    - ModelSEED Biochemistry GitHub (compound names, formulas, InChIKey)
    - KEGG REST API (reaction/compound cross-references — see KEGG block
      in the kegg container's attributions for KEGG's own license terms)

[ModelSEED biochemistry — academic free, citation requested]
  Source:   https://github.com/ModelSEED/ModelSEEDDatabase
  Citation: Henry CS et al. (2010) *High-throughput generation,
            optimization and analysis of genome-scale metabolic models.*
            Nat Biotechnol 28:977-982. doi:10.1038/nbt.1672

[FIGfam protein family annotations — academic free, citation requested]
  Citation: Meyer F et al. (2009) *FIGfams: yet another set of protein
            families.* NAR 37(20):6643-6654. doi:10.1093/nar/gkp698
PIPELINE_LOG_ATTRIB_EOF
                ;;
            tatfinder)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[tat_find.pl + tat_find_reference.py — first-party reimplementation, BSD-3-Clause]
  Implements the TatFind 1.4 algorithm. The original TatFind 1.4 webserver
  (formerly cbs.dtu.dk / sas.upenn.edu) is offline; no canonical upstream
  source distribution exists. Published algorithms are not themselves
  copyrightable; only specific implementations are. The code here is a
  first-party implementation released under BSD-3-Clause.
  Algorithm citation: Rose RW, Brüser T, Kissinger JC, Pohlschröder M (2002)
            *Adaptation of protein secretion to extremely high-salt conditions
            by extensive use of the twin-arginine translocation pathway.*
            Mol Microbiol 45(4):943-950. doi:10.1046/j.1365-2958.2002.03090.x
PIPELINE_LOG_ATTRIB_EOF
                ;;
            tcdb)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[DIAMOND 2.1.9 — GPL-3.0-or-later, binary bundled]
  See dbcan attribution block above for full GPL §6 notice and DIAMOND
  citations (Buchfink 2015, 2021).

[TCDB (Transporter Classification Database) 2024 — Academic free,
                                  COMMERCIAL USE RESTRICTED, mounted at /db]
  ⚠️ Database NOT bundled (downloaded by download-tcdb.sh).
  ⚠️ Commercial redistribution requires permission.
  Acceptable use policy: https://www.tcdb.org/
  Academic use: free, citation required.
  Commercial use: contact saier@biomail.ucsd.edu
  Citation: Saier MH Jr et al. (2021) *The Transporter Classification
            Database (TCDB): 2021 update.* NAR 49(D1):D461-D467.
            doi:10.1093/nar/gkaa1004
  Source:   https://www.tcdb.org/download.php
PIPELINE_LOG_ATTRIB_EOF
                ;;
            tigrfam)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[HMMER 3.4 — BSD-3-Clause, binary bundled]
  See pfam attribution block above for full notice.

[TIGRFAMs 15.0 — CC-BY-SA 4.0, mounted at /db]
  Attribution required; derivatives MUST be released under CC-BY-SA 4.0.
  Note: TIGRFAMs maintenance transferred to NCBI ~2018 and is now part of
        NCBIfam at https://ftp.ncbi.nlm.nih.gov/hmm/current/. The 15.0
        release pinned here is the canonical legacy distribution.
  Citation: Haft DH, Selengut JD, White O (2013) *TIGRFAMs and Genome
            Properties in 2013.* NAR 41(D1):D387-D395.
            doi:10.1093/nar/gks1195
  Source:   https://ftp.ncbi.nlm.nih.gov/hmm/TIGRFAMs/release_15.0/
PIPELINE_LOG_ATTRIB_EOF
                ;;
            tmbed)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[TMbed 1.0.0 — Apache-2.0, bundled via pip from GitHub tag v1.0.0]
  Source:   https://github.com/BernhoferM/TMbed/releases/tag/v1.0.0
  Citation: Bernhofer M, Rost B (2022) *TMbed — Transmembrane proteins
            predicted through language model embeddings.* BMC Bioinformatics
            23:326. doi:10.1186/s12859-022-04873-x

[PyTorch 2.2.2 — BSD-3-Clause-style; transformers 4.36.2 — Apache-2.0;
 sentencepiece 0.2.0 — Apache-2.0] — all bundled via pip, permissive.

[ProtT5-XL-U50 encoder model — ⚠️ CC-BY-NC-SA 4.0 (NonCommercial)]
  ⚠️ ⚠️ ⚠️  COMPLIANCE CRITICAL  ⚠️ ⚠️ ⚠️
  Model weights are NOT bundled (downloaded on first run from Hugging Face).
  TMbed itself is Apache-2.0, but using TMbed produces outputs derived
  from the ProtT5 model — the NonCommercial restriction PROPAGATES TO YOUR
  PREDICTIONS. Commercial use of any TMbed output is PROHIBITED without
  explicit written permission from the Rost Lab (rostlab@in.tum.de).
  Citation: Elnaggar A et al. (2022) *ProtTrans: Toward Understanding the
            Language of Life Through Self-Supervised Learning.* IEEE TPAMI
            44(10):7112-7127. doi:10.1109/TPAMI.2021.3095381
  Source:   https://huggingface.co/Rostlab/prot_t5_xl_half_uniref50-enc
PIPELINE_LOG_ATTRIB_EOF
                ;;
            tmhmm)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[tmhmm.py 1.3.2 — MIT, bundled via pip]
  Copyright (c) 2017 Dan Søndergaard. Permission granted to use, copy,
  modify, merge, publish, distribute, sublicense, sell copies under MIT.
  ⚠️ This is NOT the proprietary DTU TMHMM 2.0 binary (which is academic-
     only and CANNOT be bundled). tmhmm.py re-implements the published HMM
     architecture from scratch.
  Upstream: https://github.com/dansondergaard/tmhmm.py (archived 2023-10-04)
  Source:   https://pypi.org/project/tmhmm.py/1.3.2/
  Cite the underlying TMHMM 2.0 algorithm:
            Krogh A, Larsson B, von Heijne G, Sonnhammer ELL (2001)
            *Predicting transmembrane protein topology with a hidden Markov
            model: application to complete genomes.* JMB 305(3):567-580.
            doi:10.1006/jmbi.2000.4315
PIPELINE_LOG_ATTRIB_EOF
                ;;
            uniprot)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[DIAMOND 2.1.9 — GPL-3.0-or-later, binary bundled]
  Per GPL §6: source archive available at:
  Source:    https://github.com/bbuchfink/diamond/archive/refs/tags/v2.1.9.tar.gz
  Citations: Buchfink B, Xie C, Huson DH (2015) Nat Methods 12:59-60.
             doi:10.1038/nmeth.3176 [original DIAMOND]
             Buchfink B, Reuter K, Drost H-G (2021) Nat Methods 18:366-368.
             doi:10.1038/s41592-021-01101-x [DIAMOND2]

[UniProt Swiss-Prot 2025_05 — CC-BY 4.0, mounted at /db]
  Attribution required if republished; indicate any changes made.
  Citations: UniProt Consortium (2025) NAR 53(D1):D609-D617.
             doi:10.1093/nar/gkae1010 [latest]
             UniProt Consortium (2023) NAR 51(D1):D523-D531.
             doi:10.1093/nar/gkac1052
  Source:    https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.fasta.gz
PIPELINE_LOG_ATTRIB_EOF
                ;;
            signalP4|signalp4)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[SignalP 4 — ⚠️ ACADEMIC LICENSE ONLY, NOT REDISTRIBUTABLE]
  ⚠️ ⚠️ ⚠️  COMPLIANCE CRITICAL  ⚠️ ⚠️ ⚠️
  SignalP 4 is distributed by DTU under an academic-use-only license. The
  binary MUST NOT be included in any publicly redistributed image.
  Commercial use requires a separate license from DTU.
  Citation: Petersen TN, Brunak S, von Heijne G, Nielsen H (2011) *SignalP
            4.0: discriminating signal peptides from transmembrane regions.*
            Nature Methods 8:785-786. doi:10.1038/nmeth.1701
  Upstream: https://services.healthtech.dtu.dk/
PIPELINE_LOG_ATTRIB_EOF
                ;;
            consolidation|fingerprint|labeling|llm)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[First-party utility — BSD-3-Clause]
  This container holds first-party scripts only; no third-party tools are
  bundled. The code is released under BSD-3-Clause.
PIPELINE_LOG_ATTRIB_EOF
                ;;
            aai)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[EzAAI 1.2.2 — MIT License, bundled as JAR from GitHub releases]
  Copyright (c) 2021-2024 Donghyun Kim (endixk), KAIST.
  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the "Software"),
  to deal in the Software without restriction, including without limitation
  the rights to use, copy, modify, merge, publish, distribute, sublicense,
  and/or sell copies of the Software, and to permit persons to whom the
  Software is furnished to do so, subject to the MIT License terms.
  Source:   https://github.com/endixk/ezaai/releases/download/v1.2.2/EzAAI.jar
  Citation: Kim D, Park S, Chun J (2021) *Introducing EzAAI: a pipeline for
            high throughput calculations of prokaryotic average amino acid
            identity.* J Microbiol 59(5):476-480.
            doi:10.1007/s12275-021-1154-0

[DIAMOND 2.1.9 — GPL-3.0-or-later, compiled from source]
  Used internally by EzAAI for protein-vs-protein alignments.
  Per GPL §6: source available at:
  Source:    https://github.com/bbuchfink/diamond/archive/refs/tags/v2.1.9.tar.gz
  Citations: Buchfink B, Xie C, Huson DH (2015) Nat Methods 12:59-60.
             doi:10.1038/nmeth.3176 [original DIAMOND]
             Buchfink B, Reuter K, Drost H-G (2021) Nat Methods 18:366-368.
             doi:10.1038/s41592-021-01101-x [DIAMOND2]
PIPELINE_LOG_ATTRIB_EOF
                ;;
            ani)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[FastANI 1.34 — Apache-2.0, compiled from source]
  Copyright © 2018 Chirag Jain, Georgia Tech / University of Chicago.
  Licensed under the Apache License, Version 2.0; you may not use this
  software except in compliance with the License.
  Source:   https://github.com/ParBLiSS/FastANI/archive/refs/tags/v1.34.tar.gz
  Citation: Jain C, Rodriguez-R LM, Phillippy AM, Konstantinidis KT,
            Aluru S (2018) *High throughput ANI analysis of 90K prokaryotic
            genomes reveals clear species boundaries.* Nat Commun 9:5114.
            doi:10.1038/s41467-018-07641-9
PIPELINE_LOG_ATTRIB_EOF
                ;;
            closest)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[First-party rank_closest.py — MIT License]
  Reads pre-computed all-vs-all AAI (from the 'aai' container) and ANI (from
  the 'ani' container) symmetric matrices and ranks the top-N closest
  organisms within the collection for each genome.  No external database
  required.
  This script is part of the margie-annotation pipeline.
PIPELINE_LOG_ATTRIB_EOF
                ;;
            synteny)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[Liftoff 1.6.3 — GPL-3.0-or-later, installed via pip from PyPI]
  Copyright © 2020 Alaina Shumate and Steven Salzberg, Johns Hopkins University.
  Source:   https://github.com/agshumate/Liftoff
  Citation: Shumate A, Salzberg SL (2021) *Liftoff: accurate mapping of gene
            annotations.* Bioinformatics 37(12):1639-1643.
            doi:10.1093/bioinformatics/btaa1016

[minimap2 2.28 — MIT, compiled from source]
  Copyright © 2018 Heng Li (Wellcome Sanger Institute / Dana-Farber Cancer Inst.).
  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the "Software"),
  to deal in the Software without restriction under the MIT License terms.
  Source:   https://github.com/lh3/minimap2/archive/refs/tags/v2.28.tar.gz
  Citation: Li H (2021) *New strategies to improve minimap2 alignment accuracy.*
            Bioinformatics 37(23):4572-4574.
            doi:10.1093/bioinformatics/btab705

[First-party merge_liftoff.py — BSD-3-Clause]
  Merges per-reference Liftoff GFF3 outputs into a single non-redundant GFF3.
  This script is part of the margie-annotation pipeline.
PIPELINE_LOG_ATTRIB_EOF
                ;;
            classify)
                cat <<'PIPELINE_LOG_ATTRIB_EOF'

[Prodigal 2.6.3 — GPL-3.0-or-later, compiled from source]
  Copyright (c) 2007-2016 University of Tennessee / Doug Hyatt.
  Source:   https://github.com/hyattpd/Prodigal
  Citation: Hyatt D et al. (2010) *Prodigal: prokaryotic gene recognition and
            translation initiation site identification.*
            BMC Bioinformatics 11:119.  doi:10.1186/1471-2105-11-119

[DIAMOND 2.1.9 — GPL-3.0-or-later, compiled from source]
  Copyright (c) 2016-2024 Benjamin Buchfink.
  Source:   https://github.com/bbuchfink/diamond
  Citation: Buchfink B, Reuter K, Drost HG (2021) *Sensitive protein alignments
            at tree-of-life scale using DIAMOND.* Nat Methods 18:366-368.
            doi:10.1038/s41592-021-01101-x

[HMMER 3.x (nhmmer) — BSD-3-Clause, installed from Debian apt]
  Copyright (c) 2011-2024 Howard Hughes Medical Institute / Sean Eddy lab.
  Source:   http://hmmer.org/

[Barrnap rRNA HMMs 0.9 — GPL-3.0, bundled from GitHub at build time]
  Copyright (c) 2013-2018 Torsten Seemann.
  HMM files: https://github.com/tseemann/barrnap/tree/0.9/db/
  Citation:  Seemann T. Barrnap 0.9 — Bacterial ribosomal RNA predictor.
             https://github.com/tseemann/barrnap

[First-party classify_genome.py — MIT License]
  Orchestrates nhmmer (Tier 1 rRNA domain detection) and Prodigal + DIAMOND
  (Tier 2 gram-stain detection) to classify raw nucleotide FASTA genomes as
  Archaea / Bacteria (gram-positive / gram-negative).
  This script is part of the margie-annotation pipeline.
PIPELINE_LOG_ATTRIB_EOF
                ;;
            *)
                printf '  (No attribution metadata registered for tool "%s".)\n' "$tool"
                ;;
        esac
    } >> "$PIPELINE_LOG_PATH"
}

# ─────────────────────────────────────────────────────────────────────────────
# pipeline_log_legal_preamble
#
# Emit the standardised MARGIE legal preamble block into the active log:
#   - MARGIE disclaimer (research-only; MIT does not subsume third-party terms)
#   - Tool-specific licensing requirements (link, excerpt, interpretation)
#   - User acceptance record (operator, timestamp, declared purpose)
#   - Required citations (tools + databases + MARGIE)
#   - Input organization note (standalone vs pipeline usage)
#
# Must be called AFTER pipeline_log_init (needs PIPELINE_LOG_PATH,
# PIPELINE_LOG_TOOL, PIPELINE_LOG_OPERATOR, PIPELINE_LOG_START_EPOCH).
# Called from each container's entrypoint.sh immediately after
# pipeline_log_init so the preamble precedes all step entries.
# ─────────────────────────────────────────────────────────────────────────────
pipeline_log_legal_preamble() {
    [[ -z "${PIPELINE_LOG_PATH:-}" ]] && return 0
    local tool="${PIPELINE_LOG_TOOL:-unknown}"
    local operator="${PIPELINE_LOG_OPERATOR:-${USER:-unknown}}"
    local ts; ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    local declared_purpose="${MARGIE_DECLARED_PURPOSE:-Not provided. Set env var MARGIE_DECLARED_PURPOSE before invoking the container to record intended use.}"

    {
        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "MARGIE PIPELINE — LEGAL NOTICE AND PROVENANCE PREAMBLE"
        printf '%s\n' "================================================================================"
        printf '\n'
        printf '%s\n' "NOTE: The MARGIE (Microbial Annotation with Robust Genomic Intelligence Engine)"
        printf '%s\n' "pipeline is intended exclusively for research and educational purposes. MARGIE"
        printf '%s\n' "itself is released under MIT License; however, MARGIE integrates multiple"
        printf '%s\n' "third-party tools and databases, each subject to their own independent licensing"
        printf '%s\n' "terms. Users are solely responsible for ensuring that their use of each"
        printf '%s\n' "integrated tool and database complies with the respective license requirements."
        printf '%s\n' "MARGIE's MIT license does not grant, override, or subsume the rights or"
        printf '%s\n' "restrictions imposed by these third-party licenses. Commercial use of any"
        printf '%s\n' "integrated component must be independently verified against that component's"
        printf '%s\n' "license. The MARGIE pipeline authors accept no liability for licensing"
        printf '%s\n' "non-compliance by downstream users."
        printf '\n'
        printf '%s\n' "Full license text for all bundled components: /opt/${tool}/LICENSE.md"
        printf '\n'
    } >> "$PIPELINE_LOG_PATH"

    # ── Tool-specific licensing block ─────────────────────────────────────────
    {
        printf '%s\n' "================================================================================"
        printf '%s\n' "REQUIRED LICENSING INFORMATION"
        printf '%s\n' "================================================================================"
        printf '\n'
    } >> "$PIPELINE_LOG_PATH"

    case "$tool" in
        cog)
            cat >> "$PIPELINE_LOG_PATH" <<'PREAMBLE_EOF'
[1] NCBI BLAST+ (rpsblast / blastdbcmd) — U.S. Government Work (Public Domain)

  Full license reading link:
    https://www.ncbi.nlm.nih.gov/books/NBK153387/ (BLAST+ release notes)
    https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.16.0/LICENSE

  Excerpt (quoted — please verify from the link above):
    "This software/database is a 'United States Government Work' under the
     terms of the United States Copyright Act. It was written as part of
     the author's official duties as a United States Government employee and
     thus cannot be copyrighted. This software/database is freely available
     to the public for use. The National Library of Medicine and the U.S.
     Government have not placed any restriction on its use or reproduction."

  Interpretation of license:
    U.S. Government Work — not subject to U.S. copyright protection. Free
    for any use, academic or commercial, without restriction. No attribution
    legally required, though citation is strongly encouraged as scholarly
    courtesy.

  Interpretation of usage in MARGIE pipeline:
    NCBI BLAST+ 2.16.0 (specifically rpsblast and blastdbcmd) is bundled
    inside the MARGIE COG container. It is invoked locally to align protein
    sequences against the NCBI COG CDD profiles (Cog_LE/). No data is
    transmitted to NCBI servers during annotation.

[2] COGclassifier 2.0.0 — MIT License

  Full license reading link:
    https://github.com/moshi4/COGclassifier/blob/main/LICENSE

  Excerpt (quoted — please verify from the link above):
    "Copyright (c) 2022 moshi4
     Permission is hereby granted, free of charge, to any person obtaining a
     copy of this software and associated documentation files (the 'Software'),
     to deal in the Software without restriction, including without limitation
     the rights to use, copy, modify, merge, publish, distribute, sublicense,
     and/or sell copies of the Software, and to permit persons to whom the
     Software is furnished to do so, subject to the following conditions:
     The above copyright notice and this permission notice shall be included
     in all copies or substantial portions of the Software."

  Interpretation of license:
    MIT License — permissive open-source license. Free for any use, including
    commercial use, modification, and redistribution, provided the copyright
    notice and permission notice are retained in copies or substantial portions.

  Interpretation of usage in MARGIE pipeline:
    COGclassifier 2.0.0 is installed via pip inside the container. It
    orchestrates rpsblast against the COG CDD profiles and post-processes
    the hits into per-protein COG category assignments. All execution is
    local; no network requests are made.

[3] NCBI COG 2024 Database — U.S. Government Work (Public Domain)

  Full license reading link:
    https://ftp.ncbi.nlm.nih.gov/pub/COG/COG2024/data/ (see README)
    https://www.ncbi.nlm.nih.gov/research/cog/

  Excerpt (quoted — please verify from the link above):
    "The COG database is provided by the National Center for Biotechnology
     Information (NCBI) and is a U.S. Government Work. It is freely available
     to the public for use without restriction."

  Interpretation of license:
    U.S. Government Work — not subject to U.S. copyright protection. Free
    for any academic or commercial use, redistribution, and derivative works
    without restriction. Citation is required as scholarly courtesy.

  Interpretation of usage in MARGIE pipeline:
    The NCBI COG 2024 release (cddid.tbl + Cog_LE/ profile database) is
    mounted read-only at /db inside the container. It is used solely as the
    reference database for rpsblast alignment. The database files are NOT
    bundled in the container image; they must be downloaded separately using
    the MARGIE database setup scripts.

PREAMBLE_EOF
            ;;
        *)
            printf '  (No detailed licensing preamble registered for tool "%s".)\n' "$tool" >> "$PIPELINE_LOG_PATH"
            printf '  Refer to /opt/%s/LICENSE.md inside the container.\n' "$tool" >> "$PIPELINE_LOG_PATH"
            ;;
    esac

    # ── User acceptance record ─────────────────────────────────────────────────
    {
        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "USER LICENSE ACCEPTANCE RECORD"
        printf '%s\n' "================================================================================"
        printf '\n'
        printf '  %-42s: %s\n' "Current user of MARGIE-$(printf '%s' "$tool" | tr '[:lower:]' '[:upper:]') pipeline" "$operator"
        printf '  %-42s: %s\n' "Date and time (UTC) this step was run"   "$ts"
        printf '  %-42s: %s\n' "Container image"                          "$(pipeline_log_detect_image_ref "$tool")"
        printf '\n'
        printf '%s\n' "  How the user accepted the license:"
        printf '%s\n' "    By executing this container the user affirms they have read, understood,"
        printf '%s\n' "    and agree to the licensing terms of (a) the MARGIE pipeline (MIT),"
        printf '%s\n' "    (b) all third-party tools bundled in this container as listed above, and"
        printf '%s\n' "    (c) all databases mounted at /db as listed above."
        printf '%s\n' "    When run via the MARGIE pipeline, explicit acceptance is also recorded in"
        printf '%s\n' "    the MARGIE license ledger (logs/licence-acceptances.tsv)."
        printf '\n'
        printf '  %-42s:\n' "Purpose of the work as declared by user"
        printf '    %s\n' "$declared_purpose"
        printf '\n'
        printf '%s\n' "  NOTICE: Falsification of the intended purpose in order to circumvent"
        printf '%s\n' "  licensing requirements is strictly prohibited. Users are advised that"
        printf '%s\n' "  the provenance record, including username and timestamp, is retained with"
        printf '%s\n' "  the output and may be audited."
        printf '\n'
    } >> "$PIPELINE_LOG_PATH"

    # ── Required citations ─────────────────────────────────────────────────────
    {
        printf '%s\n' "================================================================================"
        printf '%s\n' "REQUIRED CITATIONS AND REFERENCES"
        printf '%s\n' "================================================================================"
        printf '\n'
    } >> "$PIPELINE_LOG_PATH"

    case "$tool" in
        cog)
            cat >> "$PIPELINE_LOG_PATH" <<'PREAMBLE_EOF'
TOOLS:

  [NCBI BLAST+]
    Camacho C, Coulouris G, Avagyan V, Ma N, Papadopoulos J, Bealer K,
    Madden TL (2009). BLAST+: architecture and applications.
    BMC Bioinformatics 10:421. doi:10.1186/1471-2105-10-421.

    Altschul SF, Gish W, Miller W, Myers EW, Lipman DJ (1990).
    Basic local alignment search tool.
    J Mol Biol 215(3):403-410. doi:10.1016/S0022-2836(05)80360-2.

    Source: https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.16.0/

  [COGclassifier]
    moshi4 (2022). COGclassifier: A tool for classifying protein sequences
    into COG functional categories using RPS-BLAST and the NCBI COG database.
    GitHub: https://github.com/moshi4/COGclassifier
    (No formal journal publication; cite the GitHub repository directly.)

DATABASES:

  [NCBI COG 2024 database]
    Tatusov RL, Koonin EV, Lipman DJ (1997). A genomic perspective on
    protein families. Science 278(5338):631-637.
    doi:10.1126/science.278.5338.631. [original COG]

    Galperin MY, Wolf YI, Makarova KS, Vera Alvarez R, Landsman D,
    Koonin EV (2021). COG database update: focus on microbial diversity,
    model organisms, and widespread pathogens.
    NAR 49(D1):D274-D281. doi:10.1093/nar/gkaa1018. [2020 update]

    Source: https://ftp.ncbi.nlm.nih.gov/pub/COG/COG2024/data/

  [MARGIE pipeline (container configuration, entrypoints, post-processing)]
    GitHub: https://github.com/sajalbhattarai/margie-pipeline
    Author: Sajal Bhattarai (ORCID 0000-0002-3143-5483).
    License: MIT.
    Note: The MARGIE GitHub repository covers only the pipeline orchestration
    and first-party scripts. It does NOT cover BLAST+, COGclassifier, or the
    NCBI COG database — those must be cited independently per the above.

PREAMBLE_EOF
            ;;
        *)
            printf '  (No citation block registered for tool "%s". See /opt/%s/LICENSE.md.)\n' "$tool" "$tool" >> "$PIPELINE_LOG_PATH"
            ;;
    esac

    # ── Input organization note ────────────────────────────────────────────────
    {
        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "INPUT ORGANIZATION NOTE"
        printf '%s\n' "================================================================================"
        printf '\n'
    } >> "$PIPELINE_LOG_PATH"

    case "$tool" in
        cog)
            cat >> "$PIPELINE_LOG_PATH" <<'PREAMBLE_EOF'
The COG container accepts a single protein FASTA file (.faa) as input via -i.

When using this container independently (outside the full MARGIE pipeline):
  Supply any protein FASTA directly:
    apptainer run cog.sif -i /path/to/proteins.faa -o /output -d /path/to/cog_db

  The --domain flag is recorded for provenance only; it does NOT affect COG
  inference (COG functional categories are domain-agnostic).

  Domain is auto-detected from the input path hierarchy (deepest matching
  segment wins: archaea/, gram-negative/, gram-positive/, bacteria/, unknown/).
  Filename suffix fallback (_arch, _archaea, _bact_gram*, _bact) is used if
  path-based detection fails. Defaults to Unknown if still unresolved.
  Override explicitly with --domain if needed.

When running inside the full MARGIE pipeline:
  The pipeline-lib run_downstream_tool() helper automatically passes the
  correct --domain flag derived from the rasttk output directory structure
  (archaea/, bacteria/gram-negative/, etc.).
  The input is always gene_calls/genome.faa from the rasttk output.

Output structure:
  <output_root>/<organism_name>/
    raw/
      rpsblast.tsv              Raw RPS-BLAST tabular hits
      cog_classify.tsv          COGclassifier per-protein annotation
      cog_count.tsv             Per-category protein counts
      cog_count_barchart.*      Bar chart visualisation
      cog_count_piechart.*      Pie chart visualisation
      cogclassifier.log         Full COGclassifier run log
      cog.stderr                Captured stderr
    processed/
      cog_results.tsv           Normalised per-protein TSV (merge key: feature_id)

Merge key: feature_id (matches the RASTtk rast.tsv feature_id column).
  Join cog_results.tsv to the RASTtk annotation table on this key.

PREAMBLE_EOF
            ;;
        *)
            printf '  See the container --help output for input format details.\n' >> "$PIPELINE_LOG_PATH"
            ;;
    esac

    {
        printf '%s\n' "================================================================================"
        printf '%s\n' "ANNOTATION STEPS (recorded below as they execute)"
        printf '%s\n' "================================================================================"
    } >> "$PIPELINE_LOG_PATH"
}

pipeline_log_close() {
    [[ -z "${PIPELINE_LOG_PATH:-}" ]] && return 0
    local status_message="${1:-OK}"
    local end_epoch end_iso total_elapsed
    end_epoch="$(date +%s)"
    end_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    total_elapsed=$((end_epoch - PIPELINE_LOG_START_EPOCH))

    {
        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "RUN SUMMARY"
        printf '%s\n' "================================================================================"
        printf '%-20s: %s\n' "Started (UTC)"  "$(date -u -r "$PIPELINE_LOG_START_EPOCH" +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$PIPELINE_LOG_START_EPOCH" +'%Y-%m-%dT%H:%M:%SZ')"
        printf '%-20s: %s\n' "Finished (UTC)" "$end_iso"
        printf '%-20s: %ss\n' "Total elapsed" "$total_elapsed"
        printf '%-20s: %s\n' "Status"         "$status_message"
    } >> "$PIPELINE_LOG_PATH"

    # Emit license/attribution block AFTER the run summary so it always
    # accompanies the outputs and the log file itself becomes a redistributable
    # provenance + notice record.
    pipeline_log_attributions
}

# ─────────────────────────────────────────────────────────────────────────────
# pipeline_log_inject_domain_column <tsv_path>
#
# Insert a `domain` column right after the existing `gram_stain` column in
# the given TSV. Value used for every data row = $PIPELINE_LOG_DOMAIN
# (falls back to "Unknown" if unset). No-op if:
#   - file does not exist or is empty
#   - header has no `gram_stain` column
#   - a `domain` column is already present
#
# This is a structural post-write step so the per-tool python writers can
# remain unmodified; the domain provenance value lives in env, not in the
# python signatures.
# ─────────────────────────────────────────────────────────────────────────────
pipeline_log_inject_domain_column() {
    local tsv_path="$1"
    [[ -s "$tsv_path" ]] || return 0
    local domain_value="${PIPELINE_LOG_DOMAIN:-Unknown}"
    awk -F'\t' -v OFS='\t' -v dom="$domain_value" '
        NR==1 {
            # find gram_stain column (1-based); skip if domain already exists
            gram_col = 0
            for (i = 1; i <= NF; i++) {
                if ($i == "domain")     { print; skip=1; next }
                if ($i == "gram_stain") gram_col = i
            }
            if (gram_col == 0) { print; skip=1; next }
            insert_col = gram_col + 1
            # rebuild header with `domain` inserted at insert_col
            line = ""
            for (i = 1; i <= NF; i++) {
                if (i == insert_col) line = line "domain" OFS
                line = line $i (i < NF ? OFS : "")
            }
            if (insert_col == NF + 1) line = line OFS "domain"
            print line
            next
        }
        skip == 1 { print; next }
        {
            line = ""
            for (i = 1; i <= NF; i++) {
                if (i == insert_col) line = line dom OFS
                line = line $i (i < NF ? OFS : "")
            }
            if (insert_col == NF + 1) line = line OFS dom
            print line
        }
    ' "$tsv_path" > "${tsv_path}.tmp.$$" && mv "${tsv_path}.tmp.$$" "$tsv_path"
}
