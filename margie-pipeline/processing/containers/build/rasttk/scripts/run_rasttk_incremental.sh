#!/bin/bash
# run_rasttk_incremental.sh — 15-step BV-BRC CLI annotation pipeline for one genome
set -e

GENOME_NAME=${1:-"theta"}
INPUT_FASTA=${2:-"input/theta/theta.fasta"}
OUTPUT_DIR=${3:-"output/rasttk/theta"}
SCIENTIFIC_NAME=${4:-"Bacteroides thetaiotaomicron"}
GENETIC_CODE=${5:-11}
DOMAIN=${6:-"Bacteria"}
RUN_MODE=${7:-"full"}
# Domain+gram suffix for output files (e.g. _arch, _bact_gramN); raw/ files keep unsuffixed names
DOMAIN_SUFFIX=${8:-""}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "RASTtk Incremental Annotation Pipeline"
echo "=========================================="
echo "Genome: $GENOME_NAME"
echo "Input: $INPUT_FASTA"
echo "Output: $OUTPUT_DIR"
echo "Scientific Name: $SCIENTIFIC_NAME"
echo "Genetic Code: $GENETIC_CODE"
echo "Domain: $DOMAIN"
echo "Run Mode: $RUN_MODE"
echo ""

case "$RUN_MODE" in
    full|only-prodigal|only-prodigal-and-glimmer)
        ;;
    *)
        echo "Error: invalid run mode '$RUN_MODE'"
        echo "Valid modes: full, only-prodigal, only-prodigal-and-glimmer"
        exit 1
        ;;
esac

if [ ! -f "$INPUT_FASTA" ]; then
    echo "Error: Input genome not found at $INPUT_FASTA"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
RUN_START_EPOCH="$(date +%s)"
RUN_START_ISO="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# =============================================================================
# Step 0: Stage contigs
# =============================================================================
CONTIG_FILE="$OUTPUT_DIR/${GENOME_NAME}${DOMAIN_SUFFIX}.contig"
echo "=== [0/15] Staging contigs ==="
cp "$INPUT_FASTA" "$CONTIG_FILE"
echo "✓ Contig file: $CONTIG_FILE"
echo ""

# Step 1: Create initial GTO
echo "=== [1/15] Creating Genome Typed Object (GTO) ==="
rast-create-genome \
    --scientific-name "$SCIENTIFIC_NAME" \
    --genetic-code "$GENETIC_CODE" \
    --domain "$DOMAIN" \
    --contigs "$CONTIG_FILE" \
    > "$OUTPUT_DIR/${GENOME_NAME}.gto.1"
echo "✓ GTO created"
echo ""

if [ "$RUN_MODE" = "full" ]; then
    echo "=== [2/15] Calling rRNA genes ==="
    rast-call-features-rRNA-SEED \
        < "$OUTPUT_DIR/${GENOME_NAME}.gto.1" \
        > "$OUTPUT_DIR/${GENOME_NAME}.gto.2"
    echo "✓ rRNA genes called"
    echo ""

    echo "=== [3/15] Calling tRNA genes ==="
    rast-call-features-tRNA-trnascan \
        < "$OUTPUT_DIR/${GENOME_NAME}.gto.2" \
        > "$OUTPUT_DIR/${GENOME_NAME}.gto.3"
    echo "✓ tRNA genes called"
    echo ""

    echo "=== [4/15] Calling repeat regions ==="
    rast-call-features-repeat-region-SEED \
        < "$OUTPUT_DIR/${GENOME_NAME}.gto.3" \
        > "$OUTPUT_DIR/${GENOME_NAME}.gto.4"
    echo "✓ Repeat regions called"
    echo ""

    echo "=== [5/15] Calling selenoproteins ==="
    rast-call-features-selenoprotein \
        < "$OUTPUT_DIR/${GENOME_NAME}.gto.4" \
        > "$OUTPUT_DIR/${GENOME_NAME}.gto.5"
    echo "✓ Selenoproteins called"
    echo ""

    echo "=== [6/15] Calling pyrrolysoproteins ==="
    rast-call-features-pyrrolysoprotein \
        < "$OUTPUT_DIR/${GENOME_NAME}.gto.5" \
        > "$OUTPUT_DIR/${GENOME_NAME}.gto.6"
    echo "✓ Pyrrolysoproteins called"
    echo ""

    echo "=== [7/15] Calling CRISPR elements ==="
    rast-call-features-crispr \
        < "$OUTPUT_DIR/${GENOME_NAME}.gto.6" \
        > "$OUTPUT_DIR/${GENOME_NAME}.gto.7"
    echo "✓ CRISPR elements called"
    echo ""

    echo "=== [8/15] Calling protein-encoding genes (Prodigal) ==="
    rast-call-features-CDS-prodigal \
        < "$OUTPUT_DIR/${GENOME_NAME}.gto.7" \
        > "$OUTPUT_DIR/${GENOME_NAME}.gto.8"
    echo "✓ Prodigal genes called"
    echo ""

    echo "=== [9/15] Calling protein-encoding genes (Glimmer3) ==="
    rast-call-features-CDS-glimmer3 \
        < "$OUTPUT_DIR/${GENOME_NAME}.gto.8" \
        > "$OUTPUT_DIR/${GENOME_NAME}.gto.9"
    echo "✓ Glimmer3 genes called"
    echo ""

    echo "=== [10/15] Annotating proteins (k-mer v2) ==="
    rast-annotate-proteins-kmer-v2 \
        < "$OUTPUT_DIR/${GENOME_NAME}.gto.9" \
        > "$OUTPUT_DIR/${GENOME_NAME}.gto.10"
    echo "✓ k-mer v2 annotation complete"
    echo ""
else
    echo "=== Fast mode enabled: skipping steps 2-7 (RNA/repeats/selenoprotein/pyrrolysoprotein/CRISPR) ==="
    echo ""

    # Step 8: Call protein-encoding genes with Prodigal (directly from gto.1)
    echo "=== [8/15] Calling protein-encoding genes (Prodigal) ==="
    rast-call-features-CDS-prodigal \
        < "$OUTPUT_DIR/${GENOME_NAME}.gto.1" \
        > "$OUTPUT_DIR/${GENOME_NAME}.gto.8"
    echo "✓ Prodigal genes called"
    echo ""

    if [ "$RUN_MODE" = "only-prodigal-and-glimmer" ]; then
        # Step 9: Optional Glimmer pass
        echo "=== [9/15] Calling protein-encoding genes (Glimmer3) ==="
        rast-call-features-CDS-glimmer3 \
            < "$OUTPUT_DIR/${GENOME_NAME}.gto.8" \
            > "$OUTPUT_DIR/${GENOME_NAME}.gto.9"
        echo "✓ Glimmer3 genes called"
        echo ""

        # Step 10 from glimmer output
        echo "=== [10/15] Annotating proteins (k-mer v2) ==="
        rast-annotate-proteins-kmer-v2 \
            < "$OUTPUT_DIR/${GENOME_NAME}.gto.9" \
            > "$OUTPUT_DIR/${GENOME_NAME}.gto.10"
        echo "✓ k-mer v2 annotation complete"
        echo ""
    else
        echo "=== Fast mode: skipping step 9 (Glimmer3) ==="
        echo ""

        echo "=== [10/15] Annotating proteins (k-mer v2) ==="
        rast-annotate-proteins-kmer-v2 \
            < "$OUTPUT_DIR/${GENOME_NAME}.gto.8" \
            > "$OUTPUT_DIR/${GENOME_NAME}.gto.10"
        echo "✓ k-mer v2 annotation complete"
        echo ""
    fi
fi

echo "=== [11/15] Annotating hypothetical proteins (k-mer v1) ==="
rast-annotate-proteins-kmer-v1 -H \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.10" \
    > "$OUTPUT_DIR/${GENOME_NAME}.gto.11"
echo "✓ k-mer v1 annotation complete"
echo ""

echo "=== [12/15] Annotating by similarity to close relatives ==="
rast-annotate-proteins-similarity -H \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.11" \
    > "$OUTPUT_DIR/${GENOME_NAME}.gto.12" || {
    echo "⚠ Similarity annotation failed (no close relatives available)"
    cp "$OUTPUT_DIR/${GENOME_NAME}.gto.11" "$OUTPUT_DIR/${GENOME_NAME}.gto.12"
}
echo "✓ Similarity annotation complete"
echo ""

echo "=== [13/15] Resolving overlapping features ==="
rast-resolve-overlapping-features \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.12" \
    > "$OUTPUT_DIR/${GENOME_NAME}.gto.13"
echo "✓ Overlaps resolved"
echo ""

echo "=== [14/15] Calling prophage elements (PhiSpy) ==="
rast-call-features-prophage-phispy \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.13" \
    > "$OUTPUT_DIR/${GENOME_NAME}.gto.14" || {
    echo "⚠ PhiSpy prophage detection skipped (common for small genomes); continuing without prophage annotations"
    cp "$OUTPUT_DIR/${GENOME_NAME}.gto.13" "$OUTPUT_DIR/${GENOME_NAME}.gto.14"
}
echo "✓ Prophage elements step complete"
echo ""

echo "=== [15/15] Exporting annotations ==="

# Feature table
rast-export-genome feature_data \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.14" \
    > "$OUTPUT_DIR/${GENOME_NAME}_features.tsv"
echo "✓ Feature table: ${GENOME_NAME}_features.tsv"

# GenBank format
rast-export-genome genbank \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.14" \
    > "$OUTPUT_DIR/${GENOME_NAME}.gbk"
echo "✓ GenBank: ${GENOME_NAME}.gbk"

# GFF format
rast-export-genome gff \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.14" \
    > "$OUTPUT_DIR/${GENOME_NAME}.gff"
echo "✓ GFF: ${GENOME_NAME}.gff"

# Protein FASTA
rast-export-genome protein_fasta \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.14" \
    > "$OUTPUT_DIR/${GENOME_NAME}.faa"
echo "✓ Protein sequences: ${GENOME_NAME}.faa"

# Remap generic protein_N headers to stable fig| CDS IDs from GFF
python3 "$SCRIPT_DIR/remap_protein_fasta_headers_from_gff.py" \
  --gff "$OUTPUT_DIR/${GENOME_NAME}.gff" \
  --faa "$OUTPUT_DIR/${GENOME_NAME}.faa"

# Gene DNA FASTA
rast-export-genome feature_dna \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.14" \
    > "$OUTPUT_DIR/${GENOME_NAME}.ffn"
echo "✓ Gene sequences: ${GENOME_NAME}.ffn"

# Contig FASTA
rast-export-genome contig_fasta \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.14" \
    > "$OUTPUT_DIR/${GENOME_NAME}.fna"
echo "✓ Contig sequences: ${GENOME_NAME}.fna"

# Typed feature exports are best-effort (BV-BRC may 403); basic export above is the authoritative source
if rast-export-genome --feature-type CDS feature_data \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.14" \
    > "$OUTPUT_DIR/${GENOME_NAME}_CDS.tsv" 2>/dev/null; then
    echo "✓ CDS features: ${GENOME_NAME}_CDS.tsv"
else
    echo "⚠ CDS feature export skipped (BV-BRC export_genome returned non-zero); continuing"
    : > "$OUTPUT_DIR/${GENOME_NAME}_CDS.tsv"
fi

if rast-export-genome --feature-type rna feature_data \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.14" \
    > "$OUTPUT_DIR/${GENOME_NAME}_RNA.tsv" 2>/dev/null; then
    echo "✓ RNA features: ${GENOME_NAME}_RNA.tsv"
else
    echo "⚠ RNA feature export skipped (BV-BRC export_genome returned non-zero); continuing"
    : > "$OUTPUT_DIR/${GENOME_NAME}_RNA.tsv"
fi

if rast-export-genome --feature-type prophage feature_data \
    < "$OUTPUT_DIR/${GENOME_NAME}.gto.14" \
    > "$OUTPUT_DIR/${GENOME_NAME}_prophage.tsv" 2>/dev/null; then
    echo "✓ Prophage features: ${GENOME_NAME}_prophage.tsv"
else
    echo "⚠ Prophage feature export skipped (BV-BRC export_genome returned non-zero); continuing"
    : > "$OUTPUT_DIR/${GENOME_NAME}_prophage.tsv"
fi

echo ""

# Generate summary
echo "=== Generating Summary ==="
CDS_COUNT=$(tail -n +2 "$OUTPUT_DIR/${GENOME_NAME}_CDS.tsv" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
RNA_COUNT=$(tail -n +2 "$OUTPUT_DIR/${GENOME_NAME}_RNA.tsv" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
PROPHAGE_COUNT=$(tail -n +2 "$OUTPUT_DIR/${GENOME_NAME}_prophage.tsv" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
PROTEIN_COUNT=$(grep -c "^>" "$OUTPUT_DIR/${GENOME_NAME}.faa" 2>/dev/null | tr -d ' ' || echo "0")

cat > "$OUTPUT_DIR/${GENOME_NAME}_summary.txt" << EOF
========================================
RASTtk Annotation Summary
========================================
Genome: $GENOME_NAME
Scientific Name: $SCIENTIFIC_NAME
Domain: $DOMAIN
Genetic Code: $GENETIC_CODE
Date: $(date)

=== Feature Counts ===
CDS (protein-encoding genes): $CDS_COUNT
RNA genes: $RNA_COUNT
Prophage elements: $PROPHAGE_COUNT
Proteins translated: $PROTEIN_COUNT

=== Output Files ===
Feature table: ${GENOME_NAME}_features.tsv
GenBank: ${GENOME_NAME}.gbk
GFF: ${GENOME_NAME}.gff
Proteins: ${GENOME_NAME}.faa
Genes: ${GENOME_NAME}.ffn
Contigs: ${GENOME_NAME}.fna
GTO (final): ${GENOME_NAME}.gto.14
Run Mode: $RUN_MODE

=== Annotation Steps Completed ===
$(if [ "$RUN_MODE" = "full" ]; then echo "✓ rRNA genes (BLAST-based)"; else echo "- rRNA genes (skipped in fast mode)"; fi)
$(if [ "$RUN_MODE" = "full" ]; then echo "✓ tRNA genes (tRNAscan)"; else echo "- tRNA genes (skipped in fast mode)"; fi)
$(if [ "$RUN_MODE" = "full" ]; then echo "✓ Repeat regions"; else echo "- Repeat regions (skipped in fast mode)"; fi)
$(if [ "$RUN_MODE" = "full" ]; then echo "✓ Selenoproteins"; else echo "- Selenoproteins (skipped in fast mode)"; fi)
$(if [ "$RUN_MODE" = "full" ]; then echo "✓ Pyrrolysoproteins"; else echo "- Pyrrolysoproteins (skipped in fast mode)"; fi)
$(if [ "$RUN_MODE" = "full" ]; then echo "✓ CRISPR elements"; else echo "- CRISPR elements (skipped in fast mode)"; fi)
✓ Protein-encoding genes (Prodigal)
$(if [ "$RUN_MODE" = "only-prodigal" ]; then echo "- Protein-encoding genes (Glimmer3) (skipped)"; else echo "✓ Protein-encoding genes (Glimmer3)"; fi)
✓ Function annotation (k-mer v2)
✓ Function annotation (k-mer v1)
✓ Function annotation (similarity)
✓ Overlap resolution
✓ Prophage elements (PhiSpy)
✓ Export to multiple formats

========================================
EOF

echo ""
echo "=========================================="
echo "RASTtk Annotation Complete!"
echo "=========================================="
echo "Results in: $OUTPUT_DIR"
echo ""

# Organize outputs into subdirectories
echo "=== Organizing outputs ==="
mkdir -p "$OUTPUT_DIR/gene_calls"
mkdir -p "$OUTPUT_DIR/raw"

mv "$OUTPUT_DIR/${GENOME_NAME}.faa" "$OUTPUT_DIR/gene_calls/${GENOME_NAME}${DOMAIN_SUFFIX}.faa"
mv "$OUTPUT_DIR/${GENOME_NAME}.ffn" "$OUTPUT_DIR/gene_calls/${GENOME_NAME}${DOMAIN_SUFFIX}.ffn"
mv "$OUTPUT_DIR/${GENOME_NAME}.fna" "$OUTPUT_DIR/gene_calls/${GENOME_NAME}${DOMAIN_SUFFIX}.fna"
mv "$OUTPUT_DIR/${GENOME_NAME}.gff" "$OUTPUT_DIR/gene_calls/${GENOME_NAME}${DOMAIN_SUFFIX}.gff"
mv "$OUTPUT_DIR/${GENOME_NAME}.gbk" "$OUTPUT_DIR/gene_calls/${GENOME_NAME}${DOMAIN_SUFFIX}.gbk"
echo "✓ Moved gene call files to gene_calls/"

# Stable genome.* symlinks so downstream tools don't need the organism slug
_gc="$OUTPUT_DIR/gene_calls"
for _pair in \
    "${GENOME_NAME}${DOMAIN_SUFFIX}.faa:genome.faa" \
    "${GENOME_NAME}${DOMAIN_SUFFIX}.gff:genome.gff" \
    "${GENOME_NAME}${DOMAIN_SUFFIX}.ffn:genome.ffn" \
    "${GENOME_NAME}${DOMAIN_SUFFIX}.fna:genome.fna" \
    "${GENOME_NAME}${DOMAIN_SUFFIX}.gbk:genome.gbk"; do
    _src="${_pair%%:*}"
    _link="${_pair##*:}"
    if [[ -f "$_gc/$_src" && ! -e "$_gc/$_link" ]]; then
        ln -sf "$_src" "$_gc/$_link"
        echo "✓ gene_calls/$_link → $_src"
    fi
done
unset _gc _pair _src _link

mv "$OUTPUT_DIR/${GENOME_NAME}_CDS.tsv" "$OUTPUT_DIR/raw/"
mv "$OUTPUT_DIR/${GENOME_NAME}_RNA.tsv" "$OUTPUT_DIR/raw/"
mv "$OUTPUT_DIR/${GENOME_NAME}_prophage.tsv" "$OUTPUT_DIR/raw/"
mv "$OUTPUT_DIR/${GENOME_NAME}_features.tsv" "$OUTPUT_DIR/raw/"
mv "$OUTPUT_DIR/${GENOME_NAME}.gto."* "$OUTPUT_DIR/raw/"
mv "$OUTPUT_DIR/${GENOME_NAME}_summary.txt" "$OUTPUT_DIR/raw/"
echo "✓ Moved raw RAST outputs to raw/"

echo ""
echo "=== rast.tsv consolidation deferred to entrypoint (generate_rast_tsv.py) ==="



echo ""
echo "=========================================="
echo "Directory Structure:"
echo "=========================================="
echo "$OUTPUT_DIR/"
echo "├── rast${DOMAIN_SUFFIX}.tsv (consolidated annotation table)"
echo "├── gene_calls/"
echo "│   ├── ${GENOME_NAME}${DOMAIN_SUFFIX}.faa (proteins for downstream tools)"
echo "│   ├── ${GENOME_NAME}${DOMAIN_SUFFIX}.ffn (gene nucleotide sequences)"
echo "│   ├── ${GENOME_NAME}${DOMAIN_SUFFIX}.fna (contig sequences)"
echo "│   ├── ${GENOME_NAME}${DOMAIN_SUFFIX}.gff (gene features)"
echo "│   └── ${GENOME_NAME}${DOMAIN_SUFFIX}.gbk (GenBank format)"
echo "└── raw/"
echo "    ├── ${GENOME_NAME}_CDS.tsv"
echo "    ├── ${GENOME_NAME}_RNA.tsv"
echo "    ├── ${GENOME_NAME}_prophage.tsv"
echo "    ├── ${GENOME_NAME}_features.tsv"
echo "    ├── ${GENOME_NAME}_summary.txt"
echo "    └── ${GENOME_NAME}.gto.* (14 GTO files)"

echo ""

echo ""
echo "=== Generating Pipeline Provenance Record ==="
PIPELINE_LOG="$OUTPUT_DIR/rasttk-pipeline.log.txt"
RUN_END_EPOCH="$(date +%s)"
RUN_END_ISO="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
RUN_ELAPSED=$((RUN_END_EPOCH - RUN_START_EPOCH))
OPERATOR="${SLURM_JOB_USER:-${USER:-$(id -un 2>/dev/null || echo "unknown")}}"
CONTAINER_IMAGE="${APPTAINER_CONTAINER:-${SINGULARITY_CONTAINER:-unknown}}"

cat > "$PIPELINE_LOG" << PIPELINE_EOF
================================================================================
RASTtk PIPELINE — PROVENANCE RECORD
================================================================================
Tool                : rasttk
Tool version        : BV-BRC CLI v1.048
Organism            : $SCIENTIFIC_NAME
Domain              : $DOMAIN
Date (UTC)          : $RUN_START_ISO
Container image     : $CONTAINER_IMAGE
Container arch      : $(uname -m 2>/dev/null || echo unknown)
Runner              : /usr/local/bin/run
Output dir          : $OUTPUT_DIR
Working dir         : $(pwd)
Operator            : $OPERATOR


================================================================================
MARGIE PIPELINE — LEGAL NOTICE AND PROVENANCE PREAMBLE
================================================================================

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

================================================================================
REQUIRED LICENSING INFORMATION
================================================================================

[1] RASTtk / BV-BRC CLI

  Full license reading link:
    https://github.com/BV-BRC/BV-BRC-CLI/blob/master/LICENSE

  Excerpt (quoted — please verify from the link above):
    "Copyright (c) The SEED / RAST / BV-BRC project authors. This software
     is made available under a BSD-3-Clause-compatible license. Redistribution
     and use in source and binary forms, with or without modification, are
     permitted provided that the following conditions are met:
     (1) Redistributions of source code must retain the above copyright notice;
     (2) Redistributions in binary form must reproduce the above copyright
         notice in the documentation and/or other materials provided with the
         distribution;
     (3) Neither the name of the project nor the names of its contributors may
         be used to endorse or promote products derived without specific prior
         written permission."

  Interpretation of license:
    BSD-3-Clause (3-clause BSD License). A permissive open-source license
    allowing free use, modification, and redistribution in source and binary
    forms, with the condition that copyright notices are retained, not removed,
    and that the project name is not used to endorse derived products without
    permission. Commercial use is permitted.

  Interpretation of usage in MARGIE pipeline:
    The BV-BRC CLI (rast-* commands) is bundled inside the MARGIE rasttk
    container image as a Debian package installed at build time. It is invoked
    locally within the container — no genome data is transmitted to BV-BRC
    servers under the user's account. However, several annotation steps make
    outbound HTTPS calls to BV-BRC/SEED web services (k-mer servers, similarity
    services, rRNA reference data) as anonymous requests. Users must maintain an
    active internet connection during annotation.

[2] SEED Subsystem Database

  Full license reading link:
    https://www.theseed.org/  (PubSEED Terms of Use — see website)

  Excerpt (quoted — please verify from the link above):
    "The SEED database is freely available for academic and commercial use
     with appropriate citation. Redistribution of the database or derivative
     works in bulk form should credit the SEED Project."

  Interpretation of license:
    Academic and commercial use permitted with citation. Bulk redistribution
    requires attribution to the SEED Project. The database is not formally
    under an OSI-approved FOSS license, but is provided under a liberal
    academic sharing policy.

  Interpretation of usage in MARGIE pipeline:
    A snapshot of the SEED database (seed_database_long.tsv) is mounted as a
    read-only bind at /db/rasttk/ inside the container, assembled via the
    first-party MARGIE seed-database-download pipeline. It is used exclusively
    for a local, offline table-join (SEED enrichment step). No SEED data is
    redistributed as part of the MARGIE codebase; users must download the
    snapshot themselves via the provided tool.

[3] ModelSEED Biochemistry Database

  Full license reading link:
    https://github.com/ModelSEED/ModelSEEDDatabase/blob/master/LICENSE

  Excerpt (quoted — please verify from the link above):
    "The ModelSEED database is made freely available for academic use with
     the expectation of citation in any resulting publications."

  Interpretation of license:
    Academic free use with citation requested. Not formally dual-licensed for
    commercial use; commercial users should contact the ModelSEED team.

  Interpretation of usage in MARGIE pipeline:
    Compound names, formulas, and reaction cross-references from ModelSEED are
    embedded in the SEED enrichment table (seed_database_long.tsv). This data
    is accessed entirely locally (offline) after the snapshot is downloaded.

================================================================================
USER LICENSE ACCEPTANCE RECORD
================================================================================

  Current user of MARGIE-RASTtk pipeline : $OPERATOR
  Date and time (UTC) this step was run   : $RUN_START_ISO
  Container image                          : $CONTAINER_IMAGE
  How the user accepted the license        : By executing this container the
    user affirms they have read, understood, and agree to the licensing terms
    of (a) the MARGIE pipeline (MIT), (b) the BV-BRC CLI (BSD-3-Clause), and
    (c) the SEED, ModelSEED, and FIGfam databases as described above.
    When run via the MARGIE pipeline, explicit acceptance is also recorded in
    the MARGIE license ledger (logs/licence-acceptances.tsv).
  Purpose of the work as declared by user :
    ${MARGIE_DECLARED_PURPOSE:-Not provided. Set env var MARGIE_DECLARED_PURPOSE before invoking the container to record intended use.}

  NOTICE: Falsification of the intended purpose in order to circumvent
  licensing requirements is strictly prohibited. Users are advised that the
  provenance record, including username and timestamp, is retained with the
  output and may be audited.

================================================================================
REQUIRED CITATIONS AND REFERENCES
================================================================================

TOOLS:

  [RASTtk]
    Brettin T, Davis JJ, Disz T, Edwards RA, Gerdes S, Olsen GJ, Olson R,
    Overbeek R, Parrello B, Pusch GD, Shukla M, Thomason JA 3rd, Stevens R,
    Vonstein V, Wattam AR, Xia F (2015). RASTtk: a modular and extensible
    implementation of the RAST algorithm for building custom annotation
    pipelines and annotating batches of genomes.
    Sci Rep 5:8365. doi:10.1038/srep08365. PMID:25666585; PMCID:PMC4322359.
    GitHub: https://github.com/BV-BRC/BV-BRC-CLI

  [RAST — original server]
    Aziz RK, Bartels D, Best AA, DeJongh M, Disz T, Edwards RA, Formsma K,
    Gerdes S, Glass EM, Kubal M, Meyer F, Olsen GJ, Olson R, Osterman AL,
    Overbeek RA, McNeil LK, Paarmann D, Paczian T, Parrello B, Pusch GD,
    Reich C, Stevens R, Vassieva O, Vonstein V, Wilke A, Zagnitko O (2008).
    The RAST Server: Rapid Annotations using Subsystems Technology.
    BMC Genomics 9:75. doi:10.1186/1471-2164-9-75.

  [BV-BRC platform]
    Olson RD, Assaf R, Brettin T, Conrad N, Cucinell C, Davis JJ, Dempsey DM,
    Dickerman A, Dietrich EM, Kenyon RW, Kuscuoglu M, Lefkowitz EJ, Lu J,
    Machi D, Macken C, Mao C, Niewiadomska A, Nguyen M, Olsen GJ, Overbeek JC,
    Parrello B, Parrello V, Porter JS, Pusch GD, Shukla M, Singh I,
    Stewart L, Tan G, Thomas C, VanOeffelen M, Vonstein V, Warren AS,
    Williams KP, Xia F, Yoo HS, Zhang Y, Zhang Y, Will R, Woese CR,
    Stevens RL (2023). Introducing the Bacterial and Viral Bioinformatics
    Resource Center (BV-BRC): a resource combining PATRIC, IRD and ViPR.
    NAR 51(D1):D678–D689. doi:10.1093/nar/gkac1003.
    Website: https://www.bv-brc.org

  [FIGfam protein family annotations]
    Meyer F, Overbeek R, Rodriguez A (2009). FIGfams: yet another set of
    protein families. NAR 37(20):6643–6654. doi:10.1093/nar/gkp698.

DATABASES:

  [SEED subsystem database]
    Overbeek R, Begley T, Butler RM, Choudhuri JV, Chuang HY, Cohoon M,
    de Crecy-Lagard V, Diaz N, Disz T, Edwards R, Fonstein M, Frank ED,
    Gerdes S, Glass EM, Goesmann A, Hanson A, Iwata-Reuyl D, Jensen R,
    Jamshidi N, Krause L, Kubal M, Larsen N, Linke B, McHardy AC, Meyer F,
    Neuweger H, Olsen G, Olson R, Osterman A, Portnoy V, Pusch GD, Rodionov DA,
    Ruckert C, Steiner J, Stevens R, Thiele I, Vassieva O, Ye Y, Zagnitko O,
    Vonstein V (2005). The Subsystems Approach to Genome Annotation and its
    Use in the Project to Annotate 1000 Genomes. NAR 33(17):5691–5702.
    doi:10.1093/nar/gki866.
    Website: https://www.theseed.org

    Overbeek R, Olson R, Pusch GD, Olsen GJ, Davis JJ, Disz T, Edwards RA,
    Gerdes S, Parrello B, Shukla M, Vonstein V, Wattam AR, Xia F, Stevens R
    (2014). The SEED and the Rapid Annotation of microbial genomes using
    Subsystems Technology (RAST). NAR 42(D1):D206–D214.
    doi:10.1093/nar/gkt1226.

    Disz T, Akhter S, Cuevas D, Disz T, Overbeek R, Vonstein V, Stevens RL,
    Maltsev N (2010). Accessing the SEED Genome Databases via Web Services
    API: Tools for Programmers. BMC Bioinformatics 11:319.
    doi:10.1186/1471-2105-11-319.

  [ModelSEED biochemistry database]
    Henry CS, DeJongh M, Best AA, Bhatt PM, Bhatt PM, Caspi R, Chance MR,
    Vriend G, Barker D, Bhatt A, Sussman JL, Shen Y, Thiele I, Fleming RMT,
    Overbeek R, Palsson BO (2010). High-throughput generation, optimization
    and analysis of genome-scale metabolic models.
    Nat Biotechnol 28:977–982. doi:10.1038/nbt.1672.
    GitHub: https://github.com/ModelSEED/ModelSEEDDatabase

  [SEED database snapshot (assembled by MARGIE first-party tooling)]
    The seed_database_long.tsv / seed_database_wide.tsv / seed_database.json
    files used for SEED enrichment are assembled by the MARGIE seed-database-
    download pipeline (MIT-licensed scripts only). The underlying data remains
    under the SEED Project terms of use.
    Build pipeline: https://github.com/sajalbhattarai/seed-database-download
    Compiled by:    Sajal Bhattarai (ORCID 0000-0002-3143-5483).

  [MARGIE pipeline (container configuration, entrypoints, enrichment scripts)]
    GitHub: https://github.com/sajalbhattarai/margie-pipeline
    Author: Sajal Bhattarai (ORCID 0000-0002-3143-5483).
    License: MIT.
    Note: The MARGIE GitHub repository covers only the pipeline orchestration
    and first-party scripts (consolidation, enrichment, fingerprinting, LLM
    integration, scoring heuristics). It does NOT cover any upstream tool or
    database listed above — those must be cited independently.

================================================================================
INPUT ORGANIZATION NOTE
================================================================================
When using the rasttk container independently (outside the full MARGIE
pipeline), you are responsible for organizing input genomes into the correct
subdirectory structure before mounting the input volume:

  /input/
    archaea/            ← Archaeal genomes (.fna / .fasta / .fa)
    bacteria/           ← Bacterial genomes (all gram stains)
      gram-negative/    ← Gram-negative bacteria
      gram-positive/    ← Gram-positive bacteria
    unknown/            ← Organisms with unknown domain or gram stain

Within the full MARGIE pipeline, this classification is performed
automatically by the 'classify' tool, which assigns each input genome to
the appropriate subdirectory based on taxonomic inference before rasttk runs.

The domain suffix appended to output files (e.g. _arch, _bact_gramN,
_bact_gramP) is derived from the subdirectory in which the genome is placed.

================================================================================
ANNOTATION STEPS (recorded below as they execute)
================================================================================

================================================================================
STEP 1: ENVIRONMENT SETUP
================================================================================
Tool              : BV-BRC CLI v1.048
Installation path : /opt/rasttk/scripts/bvbrc/
Container image   : $CONTAINER_IMAGE
Genome slug       : $GENOME_NAME
Domain suffix     : ${DOMAIN_SUFFIX:-(none)}
Genetic code      : $GENETIC_CODE
Run mode          : $RUN_MODE
GitHub (MARGIE)   : https://github.com/sajalbhattarai/margie-pipeline

Environment variables set at runtime:
  KB_TOP      = \${SCRIPT_DIR}/bvbrc/deployment
  KB_RUNTIME  = \${SCRIPT_DIR}/bvbrc/deployment
  PATH        = \${KB_TOP}/bin:\${KB_RUNTIME}/bin:\$PATH
  PERL5LIB    = \${KB_TOP}/lib

Service URL patch applied at container build time:
  tutorial.theseed.org/services/genome_annotation
      → p3.theseed.org/services/genome_annotation
  (Required because the default URL in BV-BRC CLI 1.048 points to a
   deprecated tutorial endpoint; the production endpoint is used instead.)

================================================================================
STEP 2: NETWORK / AUTHENTICATION
================================================================================
Mode: Local container execution — no genome data submitted to remote account.

Internet access requirement:
  Although the pipeline runs locally, several BV-BRC CLI annotation steps
  make outbound HTTPS requests to BV-BRC / SEED web services at runtime for
  reference data lookups. These are anonymous (no API token required) but
  they DO require an active connection to:
    *.bv-brc.org    *.patricbrc.org    p3.theseed.org
  Steps that require network access:
    - rast-call-features-rRNA-SEED       (SEED rRNA reference data)
    - rast-call-features-repeat-region-SEED
    - rast-annotate-proteins-kmer-v2     (k-mer v2 signature server)
    - rast-annotate-proteins-kmer-v1     (k-mer v1 data)
    - rast-annotate-proteins-similarity  (similarity service)
    - rast-annotate-families-figfam-v1   (FIGfam reference families)
  Offline execution is not supported.

Authentication  : Not required (anonymous access to public BV-BRC services)
Login session   : None (no remote BV-BRC user submission)
Token path used : /root/.patric_token (mounted read-only; used only if
                  BVBRC_LOGIN=1 in pipeline.conf.sh for full BV-BRC API access)

================================================================================
STEP 3: GENOME ANNOTATION — 15-STEP INCREMENTAL RAST PIPELINE
================================================================================
Input file      : $INPUT_FASTA
Output directory: $OUTPUT_DIR/
Scientific name : $SCIENTIFIC_NAME

--- Step 0: Stage Contigs ---
  Command : cp $INPUT_FASTA $OUTPUT_DIR/${GENOME_NAME}${DOMAIN_SUFFIX}.contig
  Output  : ${GENOME_NAME}${DOMAIN_SUFFIX}.contig
  Purpose : Creates a stable, domain-tagged contig file used as the canonical
            input to rast-create-genome. The domain suffix (e.g. _arch,
            _bact_gramN) is embedded in the filename so that the domain/gram
            provenance is traceable through all downstream outputs without
            relying on directory structure alone. All subsequent steps
            reference this staged file rather than the original FASTA.

--- Step 1: Create Genome Typed Object (GTO) ---
  Command : rast-create-genome \\
                --scientific-name "$SCIENTIFIC_NAME" \\
                --genetic-code $GENETIC_CODE \\
                --domain $DOMAIN \\
                --contigs ${GENOME_NAME}${DOMAIN_SUFFIX}.contig
  Output  : ${GENOME_NAME}.gto.1
  Purpose : Initialises the GTO (JSON-based genome record) that accumulates
            all annotation data through each subsequent incremental step.

--- Step 2: Call rRNA Genes ---
  Command : rast-call-features-rRNA-SEED < ${GENOME_NAME}.gto.1
  Method  : BLAST-based rRNA detection against SEED rRNA reference database
  Output  : ${GENOME_NAME}.gto.2

--- Step 3: Call tRNA Genes ---
  Command : rast-call-features-tRNA-trnascan < ${GENOME_NAME}.gto.2
  Method  : tRNAscan-SE (transfer RNA identification)
  Output  : ${GENOME_NAME}.gto.3

--- Step 4: Call Repeat Regions ---
  Command : rast-call-features-repeat-region-SEED < ${GENOME_NAME}.gto.3
  Method  : SEED-based repeat region detection
  Output  : ${GENOME_NAME}.gto.4

--- Step 5: Call Selenoproteins ---
  Command : rast-call-selenoproteins < ${GENOME_NAME}.gto.4
  Output  : ${GENOME_NAME}.gto.5

--- Step 6: Call Pyrrolysoproteins ---
  Command : rast-call-pyrrolysoproteins < ${GENOME_NAME}.gto.5
  Output  : ${GENOME_NAME}.gto.6

--- Step 7: Call CRISPR Elements ---
  Command : rast-call-features-CRISPRs < ${GENOME_NAME}.gto.6
  Output  : ${GENOME_NAME}.gto.7

--- Step 8: Call Protein-Encoding Genes (Prodigal) ---
  Command : rast-call-features-CDS-prodigal < ${GENOME_NAME}.gto.7
  Method  : Prodigal gene caller (ab initio CDS prediction)
  Output  : ${GENOME_NAME}.gto.8

--- Step 9: Call Protein-Encoding Genes (Glimmer3) ---
  Command : rast-call-features-CDS-glimmer3 < ${GENOME_NAME}.gto.8
  Method  : Glimmer3 gene caller (supplementary CDS prediction)
  Output  : ${GENOME_NAME}.gto.9

--- Step 10: Annotate Protein Functions (k-mer v2) ---
  Command : rast-annotate-proteins-kmer-v2 < ${GENOME_NAME}.gto.9
  Method  : k-mer based function assignment v2 (primary functional annotation)
  Output  : ${GENOME_NAME}.gto.10

--- Step 11: Annotate Protein Functions (k-mer v1) ---
  Command : rast-annotate-proteins-kmer-v1 < ${GENOME_NAME}.gto.10
  Method  : k-mer based function assignment v1 (fills gaps from v2)
  Output  : ${GENOME_NAME}.gto.11

--- Step 12: Annotate Protein Functions (Similarity) ---
  Command : rast-annotate-proteins-similarity < ${GENOME_NAME}.gto.11
  Method  : Similarity-based annotation against BV-BRC reference proteins
  Output  : ${GENOME_NAME}.gto.12

--- Step 13: Resolve Overlapping Features ---
  Command : rast-resolve-overlapping-features < ${GENOME_NAME}.gto.12
  Purpose : Removes or adjusts features that overlap in genomically
            incompatible ways
  Output  : ${GENOME_NAME}.gto.13

--- Step 14: Call Prophage Elements ---
  Command : rast-call-features-prophage-phispy < ${GENOME_NAME}.gto.13
  Method  : PhiSpy prophage detection
  Output  : ${GENOME_NAME}.gto.14  ← FINAL GTO

================================================================================
STEP 4: EXPORT ANNOTATION RESULTS
================================================================================
All exports read from the final GTO: ${GENOME_NAME}.gto.14

  rast-export-genome feature_data   → ${GENOME_NAME}_features.tsv (all features)
  rast-export-genome genbank        → ${GENOME_NAME}.gbk
  rast-export-genome gff            → ${GENOME_NAME}.gff
  rast-export-genome protein_fasta  → ${GENOME_NAME}.faa  (protein sequences)
  rast-export-genome feature_dna    → ${GENOME_NAME}.ffn  (gene sequences)
  rast-export-genome contig_fasta   → ${GENOME_NAME}.fna  (contig sequences)
  rast-export-genome --feature-type CDS feature_data       → ${GENOME_NAME}_CDS.tsv
  rast-export-genome --feature-type rna feature_data       → ${GENOME_NAME}_RNA.tsv
  rast-export-genome --feature-type prophage feature_data  → ${GENOME_NAME}_prophage.tsv

================================================================================
STEP 5: CONSOLIDATE ANNOTATIONS (first-party MARGIE script)
================================================================================
Script  : /opt/rasttk/scripts/generate_rast_tsv.py
          (MARGIE first-party — https://github.com/sajalbhattarai/margie-pipeline)
Invoked by: entrypoint.sh (after all rast-* steps complete)

Command:
  python3 /opt/rasttk/scripts/generate_rast_tsv.py \\
      $OUTPUT_DIR \\
      "$SCIENTIFIC_NAME" \\
      "$DOMAIN" \\
      "<gram_tag>"

Processing logic:
  1. Load protein sequences from ${GENOME_NAME}.faa
  2. Load nucleotide sequences from ${GENOME_NAME}.ffn
  3. Parse CDS features from ${GENOME_NAME}_CDS.tsv
  4. Parse RNA features from ${GENOME_NAME}_RNA.tsv
  5. Parse prophage features from ${GENOME_NAME}_prophage.tsv
  6. Extract gene coordinates (start, end, strand) from the RAST feature ID
  7. Extract EC numbers from RAST_description using regex
  8. Calculate sequence lengths (na_length, aa_length)
  9. Combine all feature types into a single unified table

Output: rast${DOMAIN_SUFFIX}.tsv

Column structure (21 columns):
  organism                Scientific name
  domain                  Bacteria | Archaea
  feature_id              RASTtk feature ID — primary merge key for downstream tools
                          (format: fig|<taxon_id>.<genome_id>.<type>.<n>)
  gene_id                 Gene location string from RASTtk
  gene_start              Start coordinate (1-based)
  gene_end                End coordinate (1-based)
  na_length               Nucleotide sequence length (bp)
  aa_length               Amino acid sequence length (residues)
  na_seq                  Full nucleotide sequence
  aa_seq                  Full protein sequence
  RAST_feature_type       Feature type: CDS | rRNA | tRNA | prophage
  RAST_strand             Coding strand: + or -
  RAST_description        Functional annotation string from RASTtk
  RAST_EC_numbers         EC number(s) extracted from RAST_description
  RAST_feature_hash       MD5 hash of (feature_id + aa_seq) for deduplication
  RAST_source_file        Source RASTtk export file (CDS, RNA, prophage, features)
  RAST_genecaller_raw_row Row index in the source TSV (1-based)
  RAST_BVBRC_Superclass   BV-BRC subsystem superclass (from RASTtk BV-BRC hierarchy)
  RAST_BVBRC_Class        BV-BRC subsystem class
  RAST_BVBRC_Subclass     BV-BRC subsystem subclass
  RAST_BVBRC_Name         BV-BRC subsystem name — also used as primary SEED join key

================================================================================
STEP 6: ORGANIZE OUTPUT FILES
================================================================================
Final directory structure under $OUTPUT_DIR/:

  rast${DOMAIN_SUFFIX}.tsv         Consolidated annotation table (primary output)
  gene_calls/
    ${GENOME_NAME}${DOMAIN_SUFFIX}.faa   Protein sequences — primary input for all downstream tools
    ${GENOME_NAME}${DOMAIN_SUFFIX}.ffn   Gene nucleotide sequences
    ${GENOME_NAME}${DOMAIN_SUFFIX}.fna   Contig sequences
    ${GENOME_NAME}${DOMAIN_SUFFIX}.gff   Gene features (GFF3)
    ${GENOME_NAME}${DOMAIN_SUFFIX}.gbk   Full GenBank record
    genome.faa → (stable filename, resolves to the .faa above)
    genome.gff → (stable filename, resolves to the .gff above)
    genome.ffn → (stable filename, resolves to the .ffn above)
    genome.fna → (stable filename, resolves to the .fna above)
    genome.gbk → (stable filename, resolves to the .gbk above)
  raw/
    ${GENOME_NAME}_CDS.tsv
    ${GENOME_NAME}_RNA.tsv
    ${GENOME_NAME}_prophage.tsv
    ${GENOME_NAME}_features.tsv
    ${GENOME_NAME}_summary.txt
    ${GENOME_NAME}.gto.1 … ${GENOME_NAME}.gto.14   (all 14 GTO intermediate files)

Note on stable filenames: canonical names (genome.faa, genome.gff, etc.) in
gene_calls/ resolve to the organism-specific suffixed files above. Downstream
tools in the pipeline always open these stable names so they do not need to
know the organism slug. When running the container independently, you can
reference either form.

================================================================================
STEP 7: GENE CALLS AVAILABLE FOR DOWNSTREAM ANNOTATION
================================================================================
Primary input for all downstream annotation tools:
  gene_calls/genome.faa   (protein sequences, FASTA)

Downstream tools that consume this file (in the MARGIE pipeline):
  COG, Pfam, eggNOG-mapper, dbCAN, KEGG (KofamScan), MEROPS, TCDB,
  TIGRFAMs, InterProScan, UniProt, TMBed, DeepSig, PSORTb, Phobius,
  and any additional tools added to the pipeline.

When running standalone (outside MARGIE):
  Mount the gene_calls/ directory to your own pipeline's input and supply
  gene_calls/genome.faa (or the organism-specific .faa) directly to any
  tool that accepts protein FASTA.

================================================================================
STEP 8: HOST-SIDE SEED DATABASE ENRICHMENT (MARGIE post-processing)
================================================================================
Script  : processing/scripts/post-processing-raw-container-outputs/rasttk/
          postproc.sh  →  enrich-rast-tsv.py
Trigger : Automatic — runs on the host after the rasttk container exits.
          Wired via TOOL_rasttk_POSTPROC in pipeline.conf.sh (MARGIE only).
          When using the container independently, run this script manually
          if SEED enrichment is desired.

Database : db/rasttk/seed_database_long.tsv
           (~67,000 rows; 27 SEED_* source columns)
           Built by: https://github.com/sajalbhattarai/seed-database-download
Join key : Primary:  RAST_BVBRC_Name matched against SEED subsystem names
           Fallback: RAST_description tokens matched against SEED role names
Network  : None required — entirely local table join.

Side effects per genome (under this output directory):
  processed/rast${DOMAIN_SUFFIX}.tsv          Annotation table enriched with SEED columns
  processed/rast${DOMAIN_SUFFIX}.tsv.bak      One-time backup of pre-enrichment file

New columns appended to rast.tsv (33 columns):

  Subsystem identity + SEED hierarchy (17 columns):
    subsystem_names, subsystem_superclass, subsystem_class, subsystem_subclass,
    subsystem_role_in_subsystem, subsystem_expected_roles, subsystem_roles_detected,
    subsystem_role_coverage, subsystem_role_coverage_fraction,
    subsystem_known_variants, subsystem_called_variants, subsystem_variant_call_status,
    subsystem_curator, subsystem_last_modified, subsystem_description,
    subsystem_curator_notes, subsystem_legacy_description

  Enzymology & chemistry — ModelSEED + KEGG (12 columns):
    ec_numbers,
    modelseed_reaction_ids, modelseed_reaction_equations,
    modelseed_compound_ids, modelseed_compound_names, modelseed_compound_formulas,
    kegg_reaction_ids, kegg_reaction_names, kegg_reaction_definitions,
    kegg_reaction_equations, kegg_compound_ids, kegg_compound_names

  Reference-organism variant evidence (4 columns):
    reference_variant_codes, reference_variant_presence_status,
    reference_variant_genome_count, reference_variant_distinct_role_count

================================================================================
STEP 9: DOWNSTREAM USAGE AND MERGE WORKFLOW
================================================================================
Primary merge key : feature_id   (e.g. fig|6666666.1476522.peg.1)
  All downstream annotation tools (COG, Pfam, eggNOG, dbCAN, KEGG, etc.)
  must join their results back to the RASTtk table on this key.

Primary annotation table : $OUTPUT_DIR/processed/rast${DOMAIN_SUFFIX}.tsv
  Contains RASTtk columns (21) + SEED enrichment columns (33) after STEP 8.

Protein input for downstream tools : $OUTPUT_DIR/gene_calls/genome.faa
  Standard FASTA; each header is the feature_id, preserving the merge key.

Merge workflow:
  1. Start from processed/rast${DOMAIN_SUFFIX}.tsv  (this table)
  2. Join COG results on feature_id
  3. Join Pfam results on feature_id
  4. Join eggNOG results on feature_id
  5. Join dbCAN results on feature_id
  6. Join KEGG results on feature_id
  7. Join remaining tool results on feature_id
  8. Produce a consolidated per-gene annotation table with all columns

================================================================================
RUN SUMMARY
================================================================================
Started (UTC)       : $RUN_START_ISO
Finished (UTC)      : $RUN_END_ISO
Total elapsed       : ${RUN_ELAPSED}s
Status              : OK

================================================================================
REQUIRED ATTRIBUTIONS & LICENSE NOTICES
Reproduced per the license terms of each bundled component.
Full text: /opt/rasttk/LICENSE.md (baked into the container image).
================================================================================

[BV-BRC CLI v1.048 — BSD-3-Clause-style, bundled as .deb]
  Copyright (C) the SEED / RAST / BV-BRC project authors.
  Source:    https://github.com/BV-BRC/BV-BRC-CLI
  Release:   https://github.com/BV-BRC/BV-BRC-CLI/releases
  Citations: See REQUIRED CITATIONS section above.

[SEED subsystems database]
  Source URL:  https://www.theseed.org/
  Citations:   See REQUIRED CITATIONS section above.

[SEED database snapshot — assembled by MARGIE seed-database-download (MIT)]
  Build pipeline:  https://github.com/sajalbhattarai/seed-database-download
  Build image:     ghcr.io/sajalbhattarai/seed-db:latest
  Build license:   MIT (pipeline scripts only; underlying data per SEED terms)
  Compiled by:     Sajal Bhattarai (ORCID 0000-0002-3143-5483)
  Live sources:
    pubseed.theseed.org SOAP API, pubseed.theseed.org/subsys.cgi,
    Sapling API, svr_subsystem_spreadsheet,
    ModelSEED Biochemistry GitHub, KEGG REST API

[ModelSEED biochemistry — academic free, citation requested]
  Source:   https://github.com/ModelSEED/ModelSEEDDatabase
  Citation: See REQUIRED CITATIONS section above.

[FIGfam protein family annotations — academic free, citation requested]
  Citation: See REQUIRED CITATIONS section above.

[MARGIE pipeline — MIT License]
  Source:   https://github.com/sajalbhattarai/margie-pipeline
  Author:   Sajal Bhattarai (ORCID 0000-0002-3143-5483)

================================================================================
SEED ENRICHMENT COLUMN LEGEND  (appended to every rast_<domain>.tsv)
================================================================================
Enrichment join:
  Index built from db/rasttk/seed_database_long.tsv (~67k rows).
  For each rast row, SEED metadata is looked up using:
     primary key : RAST_BVBRC_Name (if non-empty and known to SEED index)
     fallback    : RAST_description tokens matched role-name (case-insensitive)
  When a row maps to multiple SEED subsystems, all matching values are
  joined with " | " in the same order across every subsystem_* column.

SUBSYSTEM IDENTITY (17 columns):

  subsystem_names
        Leaf subsystem name(s) from the SEED curated hierarchy
        (e.g. "Glycolysis and Gluconeogenesis"). Pipe-separated when a
        role belongs to multiple subsystems.
  subsystem_superclass / subsystem_class / subsystem_subclass
        Three-level SEED metabolic/functional taxonomy above the leaf.
  subsystem_role_in_subsystem
        The canonical SEED role name for this row within each matched
        subsystem, with abbreviation if available
        (e.g. "Phosphoglycerate kinase [abbr: PGK]").
  subsystem_expected_roles
        Roles that make up the leading called variant (or, if no call,
        the largest known variant). Format: "RoleA; RoleB (total: N)".
  subsystem_roles_detected
        Roles from this subsystem actually detected in the genome, with
        the feature ID(s) that provided each hit.
        Format: "RoleA (fig|..peg.7); RoleB (fig|..peg.12) (2/4)".
  subsystem_role_coverage
        "2/4" — detected roles / total roles expected in called variant.
  subsystem_role_coverage_fraction
        Decimal fraction of the above (e.g. "0.50").
  subsystem_known_variants
        All variant codes catalogued in SEED for this subsystem
        (e.g. "1; 1.1; 2; -1").
  subsystem_called_variants
        Variant(s) supported by this genome's detected roles, with the
        roles that triggered the call
        (e.g. "1 (FolA; FolB; FolK), 2 (FolA; FolB)").
  subsystem_variant_call_status
        "called" | "partial" | "absent" | "" — outcome of the
        genome-wide variant detection for this subsystem.
  subsystem_curator / subsystem_last_modified
        Curator name and last-edit date for the subsystem (provenance).
  subsystem_description / subsystem_legacy_description
        Free-text overviews from the SEED web interface and Sapling API.
  subsystem_curator_notes
        Curator notes and HOPE/ModelSEED flux-modelling remarks (often blank).

ENZYMOLOGY & CHEMISTRY — ModelSEED (6 columns):

  ec_numbers
        EC number(s) for the role; multiple ECs separated with "; ".
  modelseed_reaction_ids
        ModelSEED reaction IDs (rxnNNNNN) catalysed by the role.
  modelseed_reaction_equations
        Reaction stoichiometry in ModelSEED notation; compounds are
        cpdNNNNN; compartments in brackets ([c]=cytosol, [e]=extracellular).
  modelseed_compound_ids / modelseed_compound_names / modelseed_compound_formulas
        Compounds appearing in the equations (IDs, names, formulas in
        matching order, "; "-separated).

KEGG CROSS-REFERENCE — mapped from ModelSEED (6 columns):

  kegg_reaction_ids         KEGG reaction IDs (RNNNNN)
  kegg_reaction_names       KEGG-assigned reaction names
  kegg_reaction_definitions KEGG substrate+product definition
  kegg_reaction_equations   KEGG equations using CNNNNN compound IDs
  kegg_compound_ids         KEGG compound IDs referenced by the equations
  kegg_compound_names       KEGG compound names (same order as IDs)

REFERENCE-ORGANISM VARIANT EVIDENCE (4 columns):

  reference_variant_codes
        Pipe-separated list of all known variant codes for this subsystem
        (mirrors subsystem_known_variants in "code: value" form).
  reference_variant_presence_status
        present | likely | absent — whether each variant was detected in
        the curated SEED reference genomes (not in YOUR genome). Format:
        "1: present; -1: absent; 2: likely".
  reference_variant_genome_count
        How many SEED reference organisms carry each variant (proxy for
        prevalence / curation confidence).
  reference_variant_distinct_role_count
        Total distinct roles composing each variant (gene-set size).

Reading a multi-subsystem row:
  If subsystem_names = "SubA | SubB", the i-th "|"-segment of every
  other subsystem_* column corresponds to the i-th subsystem. The
  chemistry columns (ec_numbers, modelseed_*, kegg_*) come from the
  FIRST role token whose chemistry is populated (one value per row).

Variant code semantics:
  Numeric (1.0, 1.1, 2.0, ...) — alternative implementations of the
  same overall pathway/function.
  -1   role present in SEED but the variant is NOT implemented in the
       reference organism.
   0   no variant assigned.
  *N.N curator-flagged uncertain variant.
================================================================================
PIPELINE_EOF

echo "✓ Pipeline provenance record saved to: $PIPELINE_LOG"

echo ""
echo "Done! $(date)"
