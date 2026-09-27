#!/usr/bin/env bash
# download-classify.sh — builds the reference databases of the classify container
# (domain / gram-stain detector): BamA and LtaS marker DIAMOND dbs, SILVA SSU NR99
# BLAST db and rpoB reference proteins. Needs the classify container, since
# diamond makedb runs inside it. Usage: ./download-classify.sh [--redo]

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-classify"
db_parse_args "$@"

skip classify gram_neg_markers.dmnd gram_pos_markers.dmnd silva_16s.nin rpob_refs.dmnd \
    && { ok "classify: already set up (use --redo to force)"; exit 0; }

d="$(db classify)"; run mkdir -p "$d"

# ── Helper: download FASTA from the UniProt Swiss-Prot REST API ──────────────
# Queries reviewed entries only; the 'size' limit keeps the marker set small.
_fetch_uniprot() {
    local label="$1" query="$2" out="$3" max_seqs="${4:-200}"
    log "fetching UniProt sequences: $label ..."
    local url="https://rest.uniprot.org/uniprotkb/stream"
    url+="?query=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query")"
    url+="&format=fasta"
    run wget -q --show-progress -O "$out" "$url"

    local n
    n=$(grep -c '^>' "$out" 2>/dev/null || echo 0)
    if [[ "$n" -eq 0 ]]; then
        warn "classify: UniProt returned 0 sequences for '$label' — check connectivity"
        return 1
    fi
    log "  $n sequences retrieved for $label"
}

# ── 1. Gram-negative marker: BamA (outer-membrane protein assembly) ───────────
# BamA (YaeT / Omp85) assembles outer-membrane proteins and is unique to diderm bacteria.
# Query: gene_exact:bamA AND reviewed:true AND taxonomy_name:Bacteria
_fetch_uniprot "BamA (gram-negative marker)" \
    "gene_exact:bamA AND reviewed:true AND taxonomy_name:Bacteria" \
    "$d/gram_neg_seeds.faa"

# ── 2. Gram-positive marker: LtaS (lipoteichoic acid synthase) ────────────────
# LtaS makes lipoteichoic acid, a gram-positive cell-wall component absent in gram-negatives.
# Query: gene_exact:ltaS AND reviewed:true AND taxonomy_name:Bacteria
_fetch_uniprot "LtaS (gram-positive marker)" \
    "gene_exact:ltaS AND reviewed:true AND taxonomy_name:Bacteria" \
    "$d/gram_pos_seeds.faa"

# ── 3. Build DIAMOND databases inside the classify container ──────────────────
log "building DIAMOND database: gram_neg_markers ..."
run_in_container classify \
    --entrypoint diamond \
    --bind "$d:/db/classify" \
    -- makedb \
        --in  /db/classify/gram_neg_seeds.faa \
        --db  /db/classify/gram_neg_markers \
        --quiet

log "building DIAMOND database: gram_pos_markers ..."
run_in_container classify \
    --entrypoint diamond \
    --bind "$d:/db/classify" \
    -- makedb \
        --in  /db/classify/gram_pos_seeds.faa \
        --db  /db/classify/gram_pos_markers \
        --quiet

# ── 4. SILVA SSU NR99 — 16S phylogenetic placement for gram-stain inference ───
# Phylum-level 16S reference for blastn-based gram-stain assignment.
# Licence: CC BY 4.0 | Citation: Quast C et al. (2013) Nucleic Acids Res 41(D1):D590-D596.
SILVA_VERSION="138.2"
SILVA_BASE="https://www.arb-silva.de/fileadmin/silva_databases/release_138_2/Exports"
silva_gz="$d/silva_ssu_nr99.fasta.gz"
silva_fasta="$d/silva_ssu_nr99.fasta"

log "downloading SILVA SSU NR99 ${SILVA_VERSION} (~1.3 GB compressed)..."
log "  source: ${SILVA_BASE}/SILVA_${SILVA_VERSION}_SSURef_NR99_tax_silva.fasta.gz"
run wget -q --show-progress \
    -O "$silva_gz" \
    "${SILVA_BASE}/SILVA_${SILVA_VERSION}_SSURef_NR99_tax_silva.fasta.gz"

log "decompressing SILVA FASTA..."
run gunzip -k "$silva_gz"

log "building BLAST nucleotide database from SILVA SSU NR99..."
run_in_container classify \
    --entrypoint makeblastdb \
    --bind "$d:/db/classify" \
    -- \
    -in    /db/classify/silva_ssu_nr99.fasta \
    -dbtype nucl \
    -out   /db/classify/silva_16s \
    -title "SILVA_SSU_NR99_${SILVA_VERSION}"

# Keeps the BLAST DB files and the .gz; removes the uncompressed FASTA.
run rm -f "$silva_fasta"

# ── 5. rpoB reference proteins (Tier 2b cross-validation) ────────────────────────
# rpoB (single-copy, rarely transferred) cross-checks the SILVA calls and names the
# best-matching species. Swiss-Prot Bacteria + Archaea, headers rewritten to
# 'acc|phylum|organism' so DIAMOND hits carry taxonomy in sseqid. Licence: CC BY 4.0.
log "downloading rpoB reference proteins from UniProt Swiss-Prot..."
rpob_faa="$d/rpob_refs.faa"

python3 - "$rpob_faa" << 'PYEOF'
import sys, urllib.request, urllib.parse

# Known phyla used in PHYLUM_TO_GRAM and ARCHAEAL_PHYLA inside classify_genome.py.
# We search each UniProt lineage string for these tokens to assign phylum.
KNOWN_PHYLA = {
    # gram-positive bacteria
    "Firmicutes", "Bacillota", "Actinobacteria", "Actinobacteriota",
    "Actinomycetota", "Tenericutes", "Mycoplasmatota",
    # gram-negative bacteria
    "Proteobacteria", "Pseudomonadota", "Bacteroidetes", "Bacteroidota",
    "Spirochaetes", "Spirochaetota", "Cyanobacteria", "Cyanobacteriota",
    "Fusobacteria", "Fusobacteriota", "Planctomycetes", "Planctomycetota",
    "Verrucomicrobia", "Verrucomicrobiota", "Chlamydiae", "Chlamydiota",
    "Acidobacteria", "Acidobacteriota", "Nitrospirae", "Nitrospirota",
    "Chlorobi", "Chlorobiota", "Fibrobacteres", "Fibrobacterota",
    "Aquificae", "Aquificota", "Thermotogae", "Thermotogota",
    "Deferribacteres", "Deferribacterota", "Chloroflexi", "Chloroflexota",
    "Deinococcota", "Deinococci", "Thermi",
    # archaea
    "Crenarchaeota", "Euryarchaeota", "Thaumarchaeota", "Thermoproteota",
    "Methanobacteriota", "Halobacterota", "Thermoplasmatota",
    "Nanoarchaeota", "Korarchaeota", "Asgardarchaeota",
    "Nanohaloarchaeota", "Hydrothermarchaeota",
}

out_faa = sys.argv[1]
query   = "(gene_exact:rpoB) AND reviewed:true AND (taxonomy_name:Bacteria OR taxonomy_name:Archaea)"
url     = "https://rest.uniprot.org/uniprotkb/stream?" + urllib.parse.urlencode({
    "query":  query,
    "format": "tsv",
    "fields": "accession,organism_name,lineage,sequence",
})
print(f"  fetching rpoB sequences from UniProt ...", file=sys.stderr)
req  = urllib.request.Request(url, headers={"User-Agent": "margie-pipeline/1.0"})
resp = urllib.request.urlopen(req, timeout=300)
lines = resp.read().decode("utf-8", errors="replace").splitlines()

n_written = 0
with open(out_faa, "w") as fh:
    for line in lines[1:]:   # skip TSV header row
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        acc, organism, lineage, seq = parts[0], parts[1], parts[2], parts[3]
        seq = seq.replace(" ", "").replace("\r", "")
        if not seq:
            continue
        # Walk the comma-separated lineage to find the first known phylum token.
        # UniProt lineage format: "Pseudomonadota (phylum)" — strip the rank suffix.
        phylum = "Unknown"
        for token in lineage.split(","):
            token = token.strip()
            # Strip optional " (rank)" suffix e.g. " (phylum)", " (class)"
            if " (" in token:
                token = token[:token.index(" (")].strip()
            if token in KNOWN_PHYLA:
                phylum = token
                break
        # Sanitise organism name for use inside a FASTA header (no | or space).
        org_safe = (
            organism.replace(" ", "_")
                     .replace("|", "_")
                     .replace("(", "")
                     .replace(")", "")
        )
        fh.write(f">{acc}|{phylum}|{org_safe}\n{seq}\n")
        n_written += 1

print(f"  {n_written} rpoB sequences written to {out_faa}", file=sys.stderr)
if n_written == 0:
    print("ERROR: no rpoB sequences retrieved — check network connectivity", file=sys.stderr)
    sys.exit(1)
PYEOF

log "building DIAMOND database: rpob_refs ..."
run_in_container classify \
    --entrypoint diamond \
    --bind "$d:/db/classify" \
    -- makedb \
        --in  /db/classify/rpob_refs.faa \
        --db  /db/classify/rpob_refs \
        --quiet

ok "classify databases ready → $d"
ok "  silva_16s.*            (SILVA SSU NR99 ${SILVA_VERSION} — 16S phylo placement; primary gram-stain)"
ok "  gram_neg_markers.dmnd  (BamA — gram-negative marker; DIAMOND fallback)"
ok "  gram_pos_markers.dmnd  (LtaS — gram-positive marker; DIAMOND fallback)"
ok "  rpob_refs.dmnd         (rpoB — RNA pol beta subunit; Tier 2b cross-validation)"
