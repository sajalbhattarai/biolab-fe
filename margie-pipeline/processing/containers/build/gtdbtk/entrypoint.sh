#!/usr/bin/env bash
# gtdbtk — self-contained GTDB-Tk taxonomy classification entrypoint
set -euo pipefail

# =============================================================================
# Usage
# =============================================================================
usage() {
    cat <<'EOF'

gtdbtk — GTDB-Tk genome taxonomy classification (self-contained)

USAGE
  apptainer run gtdbtk.sif \
      -i /input -o /output -d /db [-t THREADS] \
      [--sort-dir /sorted] [--top-n 20] [--extension fna] [--collection-name NAME]

REQUIRED
  -i DIR   Input genome FASTA directory (any depth, symlinks followed internally)
  -o DIR   Output root directory
  -d DIR   GTDB-Tk database root

OPTIONAL
  -t INT                CPU threads (default: 8)
  --sort-dir DIR        Copy each genome into taxonomy subdirs after classification:
                          <dir>/bacteria/gram-positive|gram-negative/
                          <dir>/archaea/  <dir>/unknown/
  --top-n INT           Closest neighbours per genome in pruned tree images (default: 20)
  --unknown-gram STR    Fallback for bacteria with unknown gram: gram-negative|unknown (default: gram-negative)
  --extension STR       FASTA extension (default: fna)
  --collection-name STR Label in processed output (default: basename of input)
  --help, -h            Show this help

ENVIRONMENT
  GTDBTK_PLACE_SPECIES=1|0      Force pplacer even for ANI-classified genomes (default: 1)
  GTDBTK_KEEP_INTERMEDIATES=1|0 Keep intermediate files (default: 1)

OUTPUTS  <output>/gtdbtk/
  raw/                  Native classify_wf output
  raw/gtdb-pipeline.log.txt  Run provenance
  raw/trees/            Newick files + full tree PNG/SVG + per-genome pruned PNG/SVG
  processed/            gtdbtk_results.tsv (normalised)

EOF
}

# =============================================================================
# Defaults
# =============================================================================
INPUT="" OUTPUT_ROOT="" DB_DIR=""
THREADS=8
PPLACER_CPUS="${GTDBTK_PPLACER_CPUS:-1}"
EXTENSION="fna"
COLLECTION_NAME=""
PLACE_SPECIES="${GTDBTK_PLACE_SPECIES:-1}"
KEEP_INTERMEDIATES="${GTDBTK_KEEP_INTERMEDIATES:-1}"
SORT_DIR=""
UNKNOWN_GRAM="gram-negative"
TOP_N=20

is_true() { case "${1:-}" in 1|yes|true|on|Y|y) return 0;; *) return 1;; esac; }

# =============================================================================
# Logging helpers
# =============================================================================
LOG_PATH="" LOG_STEP_INDEX=0 LOG_RUN_START_EPOCH="" LOG_RUN_START_ISO=""

log_init() {
    local start_iso gtdbtk_version container_image
    start_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    LOG_RUN_START_ISO="$start_iso"
    LOG_RUN_START_EPOCH="$(date +%s)"
    gtdbtk_version="$(gtdbtk --version 2>/dev/null | grep -m1 'version' | sed 's/^gtdbtk: //' || echo 'unknown')"
    container_image="${APPTAINER_CONTAINER:-${SINGULARITY_CONTAINER:-unknown}}"
    {
        printf '%s\n' "================================================================================"
        printf '%s\n' "GTDB-TK PIPELINE — PROVENANCE RECORD"
        printf '%s\n' "================================================================================"
        printf '%-20s: %s\n' "Tool"            "gtdbtk"
        printf '%-20s: %s\n' "Tool version"    "$gtdbtk_version"
        printf '%-20s: %s\n' "Collection"      "$COLLECTION_NAME"
        printf '%-20s: %s\n' "Genomes"         "$staged_count"
        printf '%-20s: %s\n' "Date (UTC)"      "$start_iso"
        printf '%-20s: %s\n' "Container image" "$container_image"
        printf '%-20s: %s\n' "Container arch"  "$(uname -m 2>/dev/null || echo unknown)"
        printf '%-20s: %s\n' "Runner"          "/usr/local/bin/run"
        printf '%-20s: %s\n' "Output dir"      "$OUTPUT_DIR"
        printf '%-20s: %s\n' "Working dir"     "$(pwd)"
        printf '%-20s: %s\n' "Operator"        "${PIPELINE_LOG_OPERATOR:-unknown}"
        printf '\n'

        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "MARGIE PIPELINE — LEGAL NOTICE AND PROVENANCE PREAMBLE"
        printf '%s\n' "================================================================================"
        printf '\n'
        cat << 'LEGAL'
NOTE: The MARGIE (Microbial Annotation with Robust Genomic Intelligence Engine)
pipeline is intended exclusively for research and educational purposes. MARGIE
itself is released under MIT License; however, MARGIE integrates multiple
third-party tools and databases, each subject to their own independent licensing
terms. Users are solely responsible for ensuring that their use of each
integrated tool and database complies with the respective license requirements.
MARGIE's MIT license does not grant, override, or subsume the rights or
restrictions imposed by these third-party licenses. Commercial use of any
integrated component must be independently verified against that component's
license. The MARGIE pipeline authors accept no liability for licensing
non-compliance by downstream users.

Full license text for all bundled components: /opt/gtdbtk/LICENSE.md

LEGAL

        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "REQUIRED LICENSING INFORMATION"
        printf '%s\n' "================================================================================"
        printf '\n'
        cat << 'LICENSING'
[1] GTDB-Tk 2.7.0 — GPL-3.0-or-later

  Full license reading link:
    https://github.com/Ecogenomics/GTDBTk/blob/master/LICENSE

  Excerpt (quoted — please verify from the link above):
    "GTDB-Tk is free software: you can redistribute it and/or modify it under
     the terms of the GNU General Public License as published by the Free
     Software Foundation, either version 3 of the License, or (at your option)
     any later version."

  Interpretation of license:
    GPL-3.0 — copyleft license. Free to use, modify, and distribute provided
    derivative works are also licensed under GPL-3.0. Commercial use permitted
    with GPL-3.0 compliance. Attribution and source disclosure required.

  Interpretation of usage in MARGIE pipeline:
    GTDB-Tk 2.7.0 is installed via conda inside the container and invoked to
    classify genome collections using marker gene phylogenetics (classify_wf).
    All execution is local; no data is transmitted to external servers.

[2] Prodigal 2.6.3 — GPL-3.0-or-later

  Full license reading link:
    https://github.com/hyattpd/Prodigal/blob/master/LICENSE

  Excerpt (quoted — please verify from the link above):
    "This program is free software: you can redistribute it and/or modify it
     under the terms of the GNU General Public License as published by the
     Free Software Foundation, either version 3 of the License, or (at your
     option) any later version."

  Interpretation of license:
    GPL-3.0 — same copyleft terms as GTDB-Tk above. Free for any use with
    GPL-3.0 compliance.

  Interpretation of usage in MARGIE pipeline:
    Prodigal is bundled inside the GTDB-Tk conda environment. It is invoked
    internally by GTDB-Tk to predict protein-coding genes from input genomes
    prior to marker gene identification with HMMER.

[3] HMMER 3.x — BSD-3-Clause

  Full license reading link:
    https://github.com/EddyRivasLab/hmmer/blob/master/LICENSE

  Excerpt (quoted — please verify from the link above):
    "HMMER is open source software, freely distributable under the BSD open
     source license. See the file LICENSE for details of the license."

  Interpretation of license:
    BSD-3-Clause — permissive license. Free for any use including commercial,
    with attribution. No copyleft requirements.

  Interpretation of usage in MARGIE pipeline:
    HMMER (hmmsearch) is bundled inside the GTDB-Tk conda environment and
    invoked internally to identify the 120 bacterial (bac120) and 53 archaeal
    (ar53) marker genes against HMM profiles derived from TIGRFAMs and Pfam.

[4] pplacer — BSD-3-Clause

  Full license reading link:
    https://github.com/matsen/pplacer/blob/master/LICENSE

  Excerpt (quoted — please verify from the link above):
    "Copyright (c) 2010-2012, Frederick A. Matsen, Nicholas T. Hoffman,
     Erick Bustamante, Avner Bar-Even, and Fred Hutchinson Cancer Research
     Center. All rights reserved. Redistribution and use in source and binary
     forms, with or without modification, are permitted provided that the
     following conditions are met: ..."

  Interpretation of license:
    BSD-3-Clause — permissive license. Free for any use including commercial,
    with attribution.

  Interpretation of usage in MARGIE pipeline:
    pplacer is bundled inside the GTDB-Tk conda environment. It performs
    maximum-likelihood phylogenetic placement of query genomes onto the GTDB
    reference tree using the identified marker genes.

[5] skani 0.3.2 — MIT License

  Full license reading link:
    https://github.com/bluenote-1577/skani/blob/main/LICENSE

  Excerpt (quoted — please verify from the link above):
    "MIT License. Copyright (c) 2022 Jim Shaw. Permission is hereby granted,
     free of charge, to any person obtaining a copy of this software and
     associated documentation files..."

  Interpretation of license:
    MIT — permissive open-source license. Free for any use, modification,
    and redistribution, provided the copyright notice is retained.

  Interpretation of usage in MARGIE pipeline:
    skani replaced FastANI as the ANI screening tool in GTDB-Tk v2.4+. It
    computes whole-genome average nucleotide identity (ANI) between query
    genomes and GTDB species representatives. Genomes passing the 95% ANI
    threshold are classified without pplacer; those below threshold proceed
    to phylogenetic placement.

[6] GTDB r232 Reference Database — CC-BY 4.0

  Full license reading link:
    https://gtdb.ecogenomics.org/about

  Excerpt (quoted — please verify from the link above):
    "The GTDB taxonomy is licensed under Creative Commons Attribution 4.0
     International (CC BY 4.0). You are free to share and adapt the material
     for any purpose, even commercially, provided you give appropriate credit."

  Interpretation of license:
    CC-BY 4.0 — free to share and adapt for any purpose, including commercial,
    with attribution. No share-alike requirement.

  Interpretation of usage in MARGIE pipeline:
    The GTDB r232 reference package (marker gene alignments, reference trees,
    taxonomy, ANI species representatives) is mounted read-only at /db inside
    the container. It is used solely as the reference data for classify_wf.
    The database files are NOT bundled in the container image; they must be
    downloaded separately using the MARGIE database setup scripts.

LICENSING

        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "USER LICENSE ACCEPTANCE RECORD"
        printf '%s\n' "================================================================================"
        printf '\n'
        printf '  %-42s: %s\n' "Current user of MARGIE-GTDB-Tk pipeline"  "${PIPELINE_LOG_OPERATOR:-unknown}"
        printf '  %-42s: %s\n' "Date and time (UTC) this step was run"    "$start_iso"
        printf '  %-42s: %s\n' "Container image"                          "$container_image"
        printf '\n'
        cat << 'ACCEPTANCE'
  How the user accepted the license:
    By executing this container the user affirms they have read, understood,
    and agree to the licensing terms of (a) the MARGIE pipeline (MIT),
    (b) all third-party tools bundled in this container as listed above, and
    (c) all databases mounted at /db as listed above.
    When run via the MARGIE pipeline, explicit acceptance is also recorded in
    the MARGIE license ledger (logs/licence-acceptances.tsv).

ACCEPTANCE
        printf '  %-42s:\n'  "Purpose of the work as declared by user"
        printf '    %s\n'    "${MARGIE_DECLARED_PURPOSE:-Not provided. Set env var MARGIE_DECLARED_PURPOSE before invoking the container to record intended use.}"
        printf '\n'
        cat << 'NOTICE'
  NOTICE: Falsification of the intended purpose in order to circumvent
  licensing requirements is strictly prohibited. Users are advised that
  the provenance record, including username and timestamp, is retained with
  the output and may be audited.
NOTICE

        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "REQUIRED CITATIONS AND REFERENCES"
        printf '%s\n' "================================================================================"
        printf '\n'
        cat << 'CITATIONS'
TOOLS:

  [GTDB-Tk]
    Chaumeil P-A, Mussig AJ, Hugenholtz P, Parks DH (2022).
    GTDB-Tk v2: memory friendly classification with the Genome Taxonomy Database.
    Bioinformatics 38(23):5315-5316. doi:10.1093/bioinformatics/btac672.

    Parks DH, Chuvochina M, Rinke C, Mussig AJ, Chaumeil P-A, Hugenholtz P (2022).
    GTDB: an ongoing census of bacterial and archaeal diversity through a
    phylogenetically consistent, rank normalised and complete genome-based taxonomy.
    Nucleic Acids Research 50(D1):D785-D794. doi:10.1093/nar/gkab776.

    Source: https://github.com/Ecogenomics/GTDBTk

  [Prodigal]
    Hyatt D, Chen G-L, Locascio PF, Land ML, Larimer FW, Hauser LJ (2010).
    Prodigal: prokaryotic gene recognition and translation initiation site
    identification. BMC Bioinformatics 11:119. doi:10.1186/1471-2105-11-119.

    Source: https://github.com/hyattpd/Prodigal

  [HMMER]
    Eddy SR (2011). Accelerated profile HMM searches.
    PLoS Computational Biology 7(10):e1002195. doi:10.1371/journal.pcbi.1002195.

    Source: http://hmmer.org/

  [pplacer]
    Matsen FA, Kodner RB, Armbrust EV (2010). pplacer: linear time
    maximum-likelihood and Bayesian phylogenetic placement of sequences onto
    a fixed reference tree. BMC Bioinformatics 11:538.
    doi:10.1186/1471-2105-11-538.

    Source: https://github.com/matsen/pplacer

  [skani]
    Shaw J, Yu YW (2023). Fast and robust metagenomic sequence comparison
    through sparse chaining with skani. Nature Methods 20:1661-1665.
    doi:10.1038/s41592-023-02018-3.

    Source: https://github.com/bluenote-1577/skani

DATABASES:

  [GTDB r232 Reference Database]
    Parks DH, Chuvochina M, Chaumeil P-A, Rinke C, Mussig AJ, Hugenholtz P
    (2020). A complete domain-to-species taxonomy for Bacteria and Archaea.
    Nature Biotechnology 38:1079-1086. doi:10.1038/s41587-020-0501-8.

    Source: https://gtdb.ecogenomics.org/

  [MARGIE pipeline (container configuration, entrypoints, post-processing)]
    GitHub: https://github.com/sajalbhattarai/margie-pipeline
    Author: Sajal Bhattarai (ORCID 0000-0002-3143-5483).
    License: MIT.
    Note: The MARGIE GitHub repository covers only the pipeline orchestration
    and first-party scripts. GTDB-Tk, Prodigal, HMMER, pplacer, skani, and
    the GTDB database are independent upstream components cited separately above.

CITATIONS

        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "INPUT ORGANIZATION NOTE"
        printf '%s\n' "================================================================================"
        printf '\n'
        cat << 'INPUTNOTE'
The GTDB-Tk container accepts a directory of genome FASTA files as input via -i.
Genome files are staged internally (symlinks resolved, flat temporary layout) so
that GTDB-Tk can locate them regardless of the bind-mount namespace.

When using this container independently (outside the full MARGIE pipeline):
  Supply any directory of .fna / .fa / .fasta genome files:
    apptainer run gtdbtk.sif \
        -i /genomes -o /output -d /path/to/gtdb_db \
        [-t THREADS] [--sort-dir /sorted] [--top-n 20] \
        [--collection-name NAME]

  --sort-dir places each classified genome into taxonomy-based subdirectories:
    <sort-dir>/bacteria/gram-positive/   (monoderm phyla)
    <sort-dir>/bacteria/gram-negative/   (diderm phyla + unknown bacteria)
    <sort-dir>/archaea/
    <sort-dir>/unknown/

  --top-n controls the size of per-genome pruned tree images (default: 20 closest
  neighbours by patristic distance). One PNG + SVG per genome, in their own subdir.

  Domain and gram stain are inferred from the GTDB classification string; gram
  stain uses GTDB phylum-level monoderm/diderm heuristics. Override gram fallback
  for unclassified bacteria with --unknown-gram gram-negative|unknown.

When running inside the full MARGIE pipeline:
  The pipeline supplies -i /input (bind-mounted user-input/) and --sort-dir /sort-input
  (bind-mounted input/) so that newly classified genomes are routed into the correct
  taxonomy-based input subdirectories for downstream per-genome tools.

Output structure:
  <output_root>/gtdbtk/
    raw/
      gtdbtk.bac120.summary.tsv    GTDB-Tk bacterial classification summary
      gtdbtk.ar53.summary.tsv      GTDB-Tk archaeal classification summary
      gtdb-pipeline.log.txt        Run provenance (this file)
      trees/
        tree_manifest.tsv          Map of source tree files to exported copies
        *.tree / *.nwk             Exported Newick trees
        *.png / *.svg              Full tree images
        <genome_name>/             Per-genome pruned tree images
          top<N>.png / top<N>.svg
    processed/
      gtdbtk_results.tsv           Normalised per-genome TSV (merge key: genome)

Merge key: genome (basename of input FASTA without extension).
  Join gtdbtk_results.tsv to other annotation tables on this key.
INPUTNOTE

        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "ANNOTATION STEPS (recorded below as they execute)"
        printf '%s\n' "================================================================================"
    } > "$LOG_PATH"
}

log_section() {
    LOG_STEP_INDEX=$((LOG_STEP_INDEX + 1))
    { printf '\n'; printf '%s\n' "================================================================================";
      printf 'STEP %d: %s\n' "$LOG_STEP_INDEX" "$1";
      printf '%s\n' "================================================================================"; } >> "$LOG_PATH"
}

log_kv()    { printf '%-20s: %s\n' "$1" "$2" >> "$LOG_PATH"; }

log_close() {
    local end_epoch end_iso elapsed
    end_epoch="$(date +%s)"; end_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    elapsed=$((end_epoch - LOG_RUN_START_EPOCH))
    {
        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "RUN SUMMARY"
        printf '%s\n' "================================================================================"
        printf '%-20s: %s\n' "Started (UTC)"  "$LOG_RUN_START_ISO"
        printf '%-20s: %s\n' "Finished (UTC)" "$end_iso"
        printf '%-20s: %s\n' "Total elapsed"  "${elapsed}s"
        printf '%-20s: %s\n' "Status"         "${1:-OK}"
        printf '\n'
        printf '%s\n' "================================================================================"
        printf '%s\n' "REQUIRED ATTRIBUTIONS & LICENSE NOTICES"
        printf '%s\n' "Reproduced per the license terms of each bundled component."
        printf '%s\n' "Full text: /opt/gtdbtk/LICENSE.md (baked into the container image)."
        printf '%s\n' "================================================================================"
        printf '\n'
        cat << 'ATTRIBUTIONS'
[GTDB-Tk 2.7.0 — GPL-3.0-or-later, bundled via conda]
  Copyright (c) 2017 Pierre-Alain Chaumeil, Aaron Mussig and Donovan Parks.
  GPL-3.0 — free to use, modify, and distribute with GPL-3.0 compliance.
  Citations: Chaumeil P-A et al. (2022) Bioinformatics 38(23):5315-5316.
             doi:10.1093/bioinformatics/btac672
  Source:    https://github.com/Ecogenomics/GTDBTk

[Prodigal 2.6.3 — GPL-3.0-or-later, bundled via conda (GTDB-Tk dependency)]
  GPL-3.0 — free to use, modify, and distribute with GPL-3.0 compliance.
  Citations: Hyatt D et al. (2010) BMC Bioinformatics 11:119.
             doi:10.1186/1471-2105-11-119
  Source:    https://github.com/hyattpd/Prodigal

[HMMER 3.x — BSD-3-Clause, bundled via conda (GTDB-Tk dependency)]
  Copyright (c) Sean R. Eddy and colleagues, Howard Hughes Medical Institute.
  BSD-3-Clause — permissive, free for any use with attribution.
  Citations: Eddy SR (2011) PLoS Comput Biol 7(10):e1002195.
             doi:10.1371/journal.pcbi.1002195
  Source:    http://hmmer.org/

[pplacer — BSD-3-Clause, bundled via conda (GTDB-Tk dependency)]
  Copyright (c) 2010-2012 Frederick A. Matsen and Fred Hutchinson Cancer
  Research Center. BSD-3-Clause — permissive, free for any use with attribution.
  Citations: Matsen FA et al. (2010) BMC Bioinformatics 11:538.
             doi:10.1186/1471-2105-11-538
  Source:    https://github.com/matsen/pplacer

[skani 0.3.2 — MIT License, bundled via conda (GTDB-Tk dependency)]
  Copyright (c) 2022 Jim Shaw. MIT — free for any use with attribution.
  Citations: Shaw J, Yu YW (2023) Nature Methods 20:1661-1665.
             doi:10.1038/s41592-023-02018-3
  Source:    https://github.com/bluenote-1577/skani

[GTDB r232 Reference Database — CC-BY 4.0, mounted at /db]
  Copyright (c) Parks DH and colleagues. CC-BY 4.0 — free to share and adapt
  with attribution.
  Citations: Parks DH et al. (2020) Nature Biotechnology 38:1079-1086.
             doi:10.1038/s41587-020-0501-8
  Source:    https://gtdb.ecogenomics.org/

[MARGIE pipeline — MIT License]
  Source:    https://github.com/sajalbhattarai/margie-pipeline
  Author:    Sajal Bhattarai (ORCID 0000-0002-3143-5483)
  Note: MARGIE covers the container entrypoint and post-processing scripts
  only. GTDB-Tk, Prodigal, HMMER, pplacer, skani, and the GTDB database are
  independent upstream components and must be cited separately (see above).

Full licensing details, user acceptance record, and required citations are
recorded in the LEGAL NOTICE AND PROVENANCE PREAMBLE section above.
ATTRIBUTIONS
    } >> "$LOG_PATH"
}

# =============================================================================
# Argument parsing
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i) INPUT="$2";            shift 2 ;;
        -o) OUTPUT_ROOT="$2";      shift 2 ;;
        -d) DB_DIR="$2";           shift 2 ;;
        -t) THREADS="$2";          shift 2 ;;
        --extension)       EXTENSION="$2";       shift 2 ;;
        --collection-name) COLLECTION_NAME="$2"; shift 2 ;;
        --sort-dir)        SORT_DIR="$2";        shift 2 ;;
        --unknown-gram)    UNKNOWN_GRAM="$2";    shift 2 ;;
        --top-n)           TOP_N="$2";           shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "[gtdbtk] ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$INPUT" ]]       && { echo "[gtdbtk] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[gtdbtk] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ -z "$DB_DIR" ]]      && { echo "[gtdbtk] ERROR: -d DB_DIR required" >&2; exit 1; }
[[ ! -d "$INPUT" ]]     && { echo "[gtdbtk] ERROR: input dir not found: $INPUT" >&2; exit 1; }
[[ ! -d "$DB_DIR" ]]    && { echo "[gtdbtk] ERROR: DB dir not found: $DB_DIR"   >&2; exit 1; }

[[ -z "$COLLECTION_NAME" ]] && COLLECTION_NAME="$(basename "$INPUT")"

# =============================================================================
# Internal staging — copy all FASTAs to a flat temp dir (avoids broken symlinks
# when the input mount contains paths outside the container namespace)
# =============================================================================
STAGING_DIR="/tmp/margie-gtdbtk-staging-$$"
mkdir -p "$STAGING_DIR"
STAGING_MAP="$STAGING_DIR/.name_map.tsv"
: > "$STAGING_MAP"

echo "[gtdbtk] Staging genome FASTA files from $INPUT ..."
staged_count=0
while IFS= read -r -d '' src; do
    base="$(basename "$src")"
    dest="$STAGING_DIR/$base"
    if [[ -e "$dest" ]]; then
        stem="${base%.*}" ext="${base##*.}"
        dest="$STAGING_DIR/${stem}_dup${staged_count}.${ext}"
        base="$(basename "$dest")"
    fi
    cp -f "$src" "$dest"
    printf '%s\t%s\n' "${base%.*}" "$src" >> "$STAGING_MAP"
    (( staged_count++ )) || true
done < <(find -L "$INPUT" -type f \
    \( -name "*.${EXTENSION}" -o -name '*.fa' -o -name '*.fasta' \) \
    -print0 | sort -z)

[[ "$staged_count" -lt 1 ]] && { echo "[gtdbtk] ERROR: no *.${EXTENSION} genomes found under $INPUT" >&2; exit 1; }
echo "[gtdbtk] Staged $staged_count genome(s)"

# =============================================================================
# Output directories and pipeline log
# =============================================================================
OUTPUT_DIR="$OUTPUT_ROOT/gtdbtk"
RAW_DIR="$OUTPUT_DIR/raw"
PROCESSED_DIR="$OUTPUT_DIR/processed"
mkdir -p "$RAW_DIR" "$PROCESSED_DIR"
LOG_PATH="$RAW_DIR/gtdb-pipeline.log.txt"

# =============================================================================
# Locate GTDB-Tk database root
# =============================================================================
DB_DATA_ROOT="$DB_DIR"
if [[ -s "$DB_DIR/.gtdbtk_data_root" ]]; then
    rel_root="$(head -n 1 "$DB_DIR/.gtdbtk_data_root")"
    [[ -n "$rel_root" && "$rel_root" != "." && -d "$DB_DIR/$rel_root" ]] && DB_DATA_ROOT="$DB_DIR/$rel_root"
fi
if [[ ! -s "$DB_DATA_ROOT/taxonomy/gtdb_taxonomy.tsv" ]]; then
    found_tax="$(find "$DB_DIR" -maxdepth 4 -type f -path '*/taxonomy/gtdb_taxonomy.tsv' -print -quit 2>/dev/null || true)"
    [[ -n "$found_tax" ]] && DB_DATA_ROOT="$(dirname "$(dirname "$found_tax")")"
fi
[[ ! -s "$DB_DATA_ROOT/taxonomy/gtdb_taxonomy.tsv" ]] && {
    echo "[gtdbtk] ERROR: could not locate taxonomy/gtdb_taxonomy.tsv under $DB_DIR" >&2; exit 1; }
export GTDBTK_DATA_PATH="$DB_DATA_ROOT"

# =============================================================================
# Activate micromamba conda environment
# =============================================================================
if command -v micromamba >/dev/null 2>&1; then
    eval "$(micromamba shell hook -s bash)"
    micromamba activate gtdbtk
elif [[ -x /usr/local/bin/micromamba ]]; then
    eval "$(/usr/local/bin/micromamba shell hook -s bash)"
    /usr/local/bin/micromamba activate gtdbtk
else
    echo "[gtdbtk] WARN: micromamba not found; assuming gtdbtk is in PATH"
fi

# =============================================================================
# Run GTDB-Tk classify_wf
# =============================================================================
log_init
log_section "Inputs"
log_kv "Tool"            "GTDB-Tk 2.7.0 | Prodigal 2.6.3 | HMMER 3.x | pplacer | skani 0.3.2"
log_kv "Input dir"       "$INPUT"
log_kv "Collection"      "$COLLECTION_NAME"
log_kv "Staged genomes"  "$staged_count"
log_kv "Database root"   "$DB_DATA_ROOT"
log_kv "Output dir"      "$OUTPUT_DIR"
log_kv "Threads"         "$THREADS"
log_kv "Pplacer CPUs"    "$PPLACER_CPUS"
log_kv "Extension"       "$EXTENSION"
log_kv "Place species"   "$PLACE_SPECIES"
log_kv "Keep intermediates" "$KEEP_INTERMEDIATES"
log_kv "Sort dir"        "${SORT_DIR:-<not set>}"
log_kv "Top-N"           "$TOP_N"

echo "[gtdbtk] Input:    $INPUT ($staged_count genome(s))"
echo "[gtdbtk] Output:   $OUTPUT_DIR"
echo "[gtdbtk] Database: $DB_DATA_ROOT"

classify_args=(
    --genome_dir "$STAGING_DIR"
    --out_dir    "$RAW_DIR"
    --extension  "$EXTENSION"
    --force
    --pplacer_cpus "$PPLACER_CPUS"
    --cpus         "$THREADS"
)
is_true "$PLACE_SPECIES"       && classify_args+=(--place_species)
is_true "$KEEP_INTERMEDIATES"  && classify_args+=(--keep_intermediates)

log_section "GTDB-Tk classify_wf"
log_kv "Command" "gtdbtk classify_wf ${classify_args[*]}"
classify_start="$(date +%s)"
set +e; gtdbtk classify_wf "${classify_args[@]}"; classify_rc=$?; set -e
log_kv "Elapsed (s)" "$(( $(date +%s) - classify_start ))"
log_kv "Exit code"   "$classify_rc"
if [[ "$classify_rc" -ne 0 ]]; then
    log_close "FAILED (classify_wf exit $classify_rc)"; exit "$classify_rc"
fi

BAC_SUMMARY="$RAW_DIR/gtdbtk.bac120.summary.tsv"
ARC_SUMMARY="$RAW_DIR/gtdbtk.ar53.summary.tsv"
PROCESSED_TSV="$PROCESSED_DIR/gtdbtk_results.tsv"

log_kv "Bac summary" "$BAC_SUMMARY"
log_kv "Arc summary" "$ARC_SUMMARY"

# =============================================================================
# De-symlink summary TSVs — GTDB-Tk writes these as symlinks; replace with real
# files so downstream tools work when the output dir is re-mounted or moved
# =============================================================================
for _summary in "$BAC_SUMMARY" "$ARC_SUMMARY"; do
    if [[ -L "$_summary" ]]; then
        _target="$(readlink -f "$_summary")"
        cp -f "$_target" "${_summary}.tmp" && mv "${_summary}.tmp" "$_summary"
    fi
done
unset _summary _target

# =============================================================================
# Tree artifact export and image rendering
# =============================================================================
TREE_DIR="$RAW_DIR/trees"
TREE_MANIFEST="$TREE_DIR/tree_manifest.tsv"
mkdir -p "$TREE_DIR"
printf 'source_relative_path\texported_path\n' > "$TREE_MANIFEST"
tree_count=0
log_section "Tree artifact export"
log_kv "Manifest" "$TREE_MANIFEST"

while IFS= read -r -d '' f; do
    rel="${f#$RAW_DIR/}"
    [[ "$rel" == trees/* ]] && continue
    safe_name="$(printf '%s' "${rel//\//__}" | tr -c 'A-Za-z0-9._-' '_')"
    dest="$TREE_DIR/$safe_name"
    cp -f "$f" "$dest"
    printf '%s\t%s\n' "$rel" "${dest#$RAW_DIR/}" >> "$TREE_MANIFEST"
    (( tree_count++ )) || true
done < <(find "$RAW_DIR" -type f \
    \( -name '*.tree' -o -name '*.treefile' -o -name '*.tre' -o -name '*.nwk' -o -name '*.newick' \
       -o -name '*pplacer*.json' -o -name '*placement*.json' \) \
    -print0 2>/dev/null)

log_kv "Exported artifacts" "$tree_count"

if [[ "$tree_count" -gt 0 ]]; then
    echo "[gtdbtk] Exported $tree_count tree artifact(s) → $TREE_DIR"

    RENDER_SCRIPT="/opt/gtdbtk/scripts/render_tree.py"
    if [[ -x "$RENDER_SCRIPT" ]]; then
        # Collect query genome names from summary TSVs
        query_names=()
        for _s in "$BAC_SUMMARY" "$ARC_SUMMARY"; do
            [[ -f "$_s" ]] || continue
            while IFS=$'\t' read -r _name _rest; do
                [[ "$_name" == "name" || -z "$_name" ]] && continue
                query_names+=("$_name")
            done < "$_s"
        done

        img_count=0
        while IFS=$'\t' read -r _rel exported_rel; do
            [[ "$_rel" == "source_relative_path" ]] && continue
            exported="$TREE_DIR/$exported_rel"
            [[ -f "$exported" ]] || continue
            case "$exported" in *.tree|*.treefile|*.tre|*.nwk|*.newick) ;; *) continue ;; esac
            prefix="${exported%.*}"

            # Full tree render
            python3 "$RENDER_SCRIPT" "$exported" "$prefix" && (( img_count++ )) || true

            # Per-genome pruned trees (top-N closest neighbours, one subdir per genome)
            if [[ "${#query_names[@]}" -gt 0 ]]; then
                python3 "$RENDER_SCRIPT" "$exported" "$TREE_DIR" \
                    --query-names "${query_names[@]}" \
                    --top-n "$TOP_N" && (( img_count++ )) || true
            fi
        done < "$TREE_MANIFEST"

        [[ "$img_count" -gt 0 ]] && echo "[gtdbtk] Rendered $img_count tree image set(s) (PNG + SVG)"
        log_kv "Tree images rendered" "$img_count"
        log_kv "Top-N neighbours"     "$TOP_N"
    fi
    log_kv "Tree export status" "OK"
else
    echo "[gtdbtk] WARNING: no tree files found — genomes may have been classified by ANI only"
    log_kv "Tree export status" "No tree files found (ANI-only classification)"
fi

# =============================================================================
# Post-processing — normalise raw summaries into pipeline TSV
# =============================================================================
POSTPROCESS_SCRIPT=""
for candidate in \
    /opt/gtdbtk/scripts/process_gtdbtk_raw_results.py \
    /opt/gtdbtk/scripts/scripts/process_gtdbtk_raw_results.py; do
    [[ -f "$candidate" ]] && { POSTPROCESS_SCRIPT="$candidate"; break; }
done
[[ -z "$POSTPROCESS_SCRIPT" ]] && {
    echo "[gtdbtk] ERROR: process_gtdbtk_raw_results.py not found" >&2; exit 1; }

log_section "post-process -> processed/gtdbtk_results.tsv"
post_start="$(date +%s)"
set +e
python3 "$POSTPROCESS_SCRIPT" \
    --bac-summary      "$BAC_SUMMARY" \
    --arc-summary      "$ARC_SUMMARY" \
    --output           "$PROCESSED_TSV" \
    --collection-name  "$COLLECTION_NAME" \
    --tool-used        "GTDB-Tk 2.7.0" \
    --database-used    "GTDB-Tk reference package | path(container): $DB_DATA_ROOT" \
    --input-path       "$INPUT" \
    --output-path      "$OUTPUT_DIR"
post_rc=$?
set -e
log_kv "Elapsed (s)" "$(( $(date +%s) - post_start ))"
log_kv "Exit code"    "$post_rc"
log_kv "Processed TSV" "$PROCESSED_TSV"
[[ "$post_rc" -ne 0 ]] && { log_close "FAILED (post-process exit $post_rc)"; exit "$post_rc"; }

# =============================================================================
# Genome sorting — place each FASTA into taxonomy-based subdirs under --sort-dir
# =============================================================================
if [[ -n "$SORT_DIR" ]]; then
    log_section "Genome sorting"
    log_kv "Sort dir"             "$SORT_DIR"
    log_kv "Unknown gram fallback" "$UNKNOWN_GRAM"

    MONODERM_PHYLA=(
        Bacillota Bacillota_A Bacillota_B Bacillota_C Bacillota_D
        Bacillota_E Bacillota_F Bacillota_G
        Bacillota_H   # Tenericutes/Mollicutes — wall-less but monoderm-derived
        Bacillota_I
        Actinomycetota Actinomycetota_A Actinomycetota_B
        Chloroflexota Eremiobacterota Thermosulfidibacterota
        Firmicutes Actinobacteria Tenericutes Mollicutes  # legacy names
    )
    _MONODERM_LOOKUP="|$(IFS='|'; echo "${MONODERM_PHYLA[*]}")|"

    is_monoderm()    { [[ "$_MONODERM_LOOKUP" == *"|${1}|"* ]]; }
    gtdb_domain()    { printf '%s' "$1" | cut -d';' -f1 | sed 's/^d__//'; }
    gtdb_phylum()    { printf '%s' "$1" | cut -d';' -f2 | sed 's/^p__//'; }

    resolve_sort_folder() {
        local domain="$1" phylum="$2"
        case "$domain" in
            Archaea)   echo "$SORT_DIR/archaea" ;;
            Bacteria)
                if [[ -z "$phylum" || "$phylum" == "unclassified" ]]; then
                    echo "$SORT_DIR/bacteria/$UNKNOWN_GRAM"
                elif is_monoderm "$phylum"; then
                    echo "$SORT_DIR/bacteria/gram-positive"
                else
                    echo "$SORT_DIR/bacteria/gram-negative"
                fi ;;
            *) echo "$SORT_DIR/unknown" ;;
        esac
    }

    sort_placed=0 sort_skipped=0 sort_missing=0

    sort_from_summary() {
        local tsv="$1"
        [[ -f "$tsv" ]] || return 0
        local header=1
        while IFS=$'\t' read -r genome_name classification rest; do
            (( header )) && { header=0; continue; }
            [[ -z "$genome_name" ]] && continue
            local staged_src
            staged_src="$(grep -Fm1 "${genome_name}"$'\t' "$STAGING_MAP" | cut -f2 || true)"
            if [[ -z "$staged_src" || ! -f "$staged_src" ]]; then
                echo "[gtdbtk-sort] WARNING: source not found for '$genome_name'" >&2
                (( sort_missing++ )) || true; continue
            fi
            local target_dir dest
            target_dir="$(resolve_sort_folder "$(gtdb_domain "$classification")" "$(gtdb_phylum "$classification")")"
            mkdir -p "$target_dir"
            dest="$target_dir/$(basename "$staged_src")"
            if [[ -e "$dest" ]]; then
                (( sort_skipped++ )) || true
            else
                cp -f "$staged_src" "$dest"
                echo "[gtdbtk-sort] placed: $(basename "$staged_src") → $target_dir"
                (( sort_placed++ )) || true
            fi
        done < "$tsv"
    }

    sort_from_summary "$BAC_SUMMARY"
    sort_from_summary "$ARC_SUMMARY"
    echo "[gtdbtk-sort] placed=$sort_placed  skipped=$sort_skipped  missing=$sort_missing"
    log_kv "Sort placed"  "$sort_placed"
    log_kv "Sort skipped" "$sort_skipped"
    log_kv "Sort missing" "$sort_missing"
fi

# =============================================================================
# Cleanup and summary
# =============================================================================
rm -rf "$STAGING_DIR"
log_close "OK"

echo "[gtdbtk] Done."
echo "[gtdbtk] Raw outputs:      $RAW_DIR"
echo "[gtdbtk] Tree exports:     $TREE_DIR"
echo "[gtdbtk] Processed output: $PROCESSED_TSV"
echo "[gtdbtk] Pipeline log:     $LOG_PATH"
[[ -n "$SORT_DIR" ]] && echo "[gtdbtk] Sorted genomes:   $SORT_DIR"
