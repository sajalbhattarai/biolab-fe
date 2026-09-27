#!/usr/bin/env python3
"""
process_operon_raw_results.py — Post-process UniOP raw output into a
pipeline-friendly per-gene operon TSV.

INPUTS (written by the run step into <output_dir>/raw/):
    uniop_input.faa  Prodigal-style FAA produced by the preprocessing step.
                     Headers: >contig_genenum # start # stop # strand # ID=feature_id
                     Gene order in this file == 1-based index order UniOP uses.

    uniop.operon     CSV with header: idx_genes,idx_op
                     idx_genes: quoted Python list string, may use np.int64(X) notation.
                     All integers extracted are 1-based gene indices matching uniop.pred.

    uniop.pred       Pairwise adjacent-gene prediction scores.
                     Format (after 2 header lines):
                       Gene_A  Gene_B  Probability
                     Gene indices are 1-based. Some pairs have no prediction (empty).

OUTPUT (written under <output_dir>/processed/):
    operon_results.tsv  One row per gene.

    Columns:
      feature_id                          RAST gene identifier
      organism_name                       passed via --organism-name
      gram_stain                          passed via --gram-stain
      OPERON_id                           operon_XXXX or NOT_IN_AN_OPERON
      OPERON_member_count                 number of genes in the operon (1 = singleton)
    OPERON_gene_position_in_operon      1-based position of this gene within the operon
      OPERON_upstream_gene_id             feature_id of gene immediately upstream in operon
      OPERON_upstream_pairwise_probability  UniOP pairwise prob (upstream -> this gene)
      OPERON_downstream_gene_id           feature_id of gene immediately downstream in operon
      OPERON_downstream_pairwise_probability  UniOP pairwise prob (this gene -> downstream)
      OPERON_probability                  Operon-level summary probability:
                                          geometric mean of all N-1 internal adjacent-gene
                                          pair probabilities. Format: "<value>
                                          (geometric_mean_of_adjacent_pairs,
                                          operon_genes=<N>, n_adjacent_pairs=<N-1>)".
                                          Empty for singletons or when no
                                          pred scores are available.
      OPERON_tool_used                    Tool name / URL (provenance)
      OPERON_method_used                  Human-readable summary of UniOP scoring method
      OPERON_command_used                 Exact UniOP command that produced the raw input
      input_path                          Input FASTA path used for this run
      output_path                         Output directory path used for this run

    Genes not assigned to any multi-gene operon receive OPERON_id = NOT_IN_AN_OPERON
    and empty values for all pairwise / probability columns.
"""
from __future__ import annotations

import argparse
import csv
import math
import re
import sys
from pathlib import Path


# ── STEP 1: Parse the FAA to get the ordered gene list ───────────────────────
# Returns list of RAST feature IDs in FAA file order.
# Index 0 in this list = gene 1 in UniOP's 1-based indexing.

_ID_PATTERN = re.compile(r"ID=(\S+)")


def parse_faa_gene_list(faa_path: Path) -> list[str]:
    gene_ids: list[str] = []
    with open(faa_path) as fh:
        for line in fh:
            if not line.startswith(">"):
                continue
            m = _ID_PATTERN.search(line)
            gene_ids.append(m.group(1) if m else f"unknown_{len(gene_ids) + 1}")
    return gene_ids


# ── STEP 2: Parse uniop.operon ────────────────────────────────────────────────
# Format: CSV with header idx_genes,idx_op
# idx_genes may contain np.int64(X) notation — we extract all integers via regex.
# Returns a list of clusters, each being a sorted list of 1-based gene indices.
# Only clusters with >= 2 genes are returned (single-gene entries are not operons).

# Matches either np.int64(N) notation or a bare integer token.
# Group 1 captures the integer in either case.
_NP_INT64_PATTERN = re.compile(r"np\.int64\((\d+)\)")
_BARE_INT_PATTERN = re.compile(r"(?<![.\w])(\d+)(?![.\w])")


def _extract_gene_indices(cell: str) -> list[int]:
    """Extract gene index integers from an idx_genes cell.

    Handles both 'np.int64(X)' notation (NumPy serialisation) and plain
    integer lists.  np.int64 is matched first to avoid also capturing the
    '64' in 'int64'.
    """
    matches = _NP_INT64_PATTERN.findall(cell)
    if matches:
        return [int(x) for x in matches]
    # Fallback: bare integers not adjacent to letters/dots (avoids '64' in int64)
    return [int(x) for x in _BARE_INT_PATTERN.findall(cell)]


def parse_operon_clusters(operon_path: Path) -> list[list[int]]:
    clusters: list[list[int]] = []
    with open(operon_path, newline="") as fh:
        reader = csv.reader(fh)
        for row in reader:
            if not row:
                continue
            first_cell = row[0].strip()
            # Skip header row and any blank / non-data rows
            if first_cell in ("idx_genes", ""):
                continue
            gene_indices = _extract_gene_indices(first_cell)
            if len(gene_indices) >= 2:
                clusters.append(sorted(gene_indices))
    return clusters


# ── STEP 3: Parse uniop.pred pairwise probabilities ──────────────────────────
# Lines after the two-line header: Gene_A  Gene_B  Probability
# Gene indices are 1-based.  Some lines have no probability (empty field).

def parse_pred_file(pred_path: Path | None) -> dict[tuple[int, int], float]:
    result: dict[tuple[int, int], float] = {}
    if pred_path is None or not pred_path.exists():
        return result
    with open(pred_path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) < 3:
                continue
            try:
                a = int(parts[0])
                b = int(parts[1])
                p = float(parts[2])
                result[(a, b)] = p
            except ValueError:
                continue
    return result


# ── STEP 4: Geometric mean helper ────────────────────────────────────────────

def geometric_mean(values: list[float]) -> float | None:
    if not values:
        return None
    log_sum = sum(math.log(max(v, 1e-300)) for v in values)
    return math.exp(log_sum / len(values))


# ── STEP 5: Build per-gene rows ───────────────────────────────────────────────

COLUMNS: list[str] = [
    "feature_id",
    "organism_name",
    "OPERON_id",
    "OPERON_member_count",
    "OPERON_gene_position_in_operon",
    "OPERON_upstream_gene_id",
    "OPERON_upstream_pairwise_probability",
    "OPERON_downstream_gene_id",
    "OPERON_downstream_pairwise_probability",
    "OPERON_probability",
    "OPERON_tool_used",
    "OPERON_method_used",
    "OPERON_command_used",
    "input_path",
    "output_path",
]


def build_rows(
    gene_ids: list[str],
    clusters: list[list[int]],
    pairwise: dict[tuple[int, int], float],
    organism: str,
    tool_used: str,
    method_used: str,
    command_used: str,
    input_path: str,
    output_path: str,
) -> list[dict]:
    rows: list[dict] = []
    assigned: set[int] = set()  # 1-based indices of genes placed in a multi-gene operon

    for operon_num, cluster_1based in enumerate(clusters, start=1):
        n = len(cluster_1based)
        operon_id = f"operon_{operon_num:04d}"

        # Collect all N-1 internal pairwise probabilities for the geometric mean
        internal_probs: list[float] = []
        for i in range(n - 1):
            a = cluster_1based[i]
            b = cluster_1based[i + 1]
            p = pairwise.get((a, b))
            if p is not None:
                internal_probs.append(p)

        gm = geometric_mean(internal_probs)
        if gm is not None and internal_probs:
            operon_prob_str = (
                f"{gm:.6f} (geometric_mean_of_adjacent_pairs, "
                f"operon_genes={n}, n_adjacent_pairs={len(internal_probs)})"
            )
        else:
            operon_prob_str = ""

        for pos_in_operon, gene_idx_1based in enumerate(cluster_1based, start=1):
            faa_idx = gene_idx_1based - 1  # convert 1-based -> 0-based list index
            if not (0 <= faa_idx < len(gene_ids)):
                continue

            assigned.add(gene_idx_1based)
            feature = gene_ids[faa_idx]

            # Upstream neighbor (pos - 1 in operon)
            if pos_in_operon > 1:
                up_1based = cluster_1based[pos_in_operon - 2]
                up_faa = up_1based - 1
                up_feature = gene_ids[up_faa] if 0 <= up_faa < len(gene_ids) else ""
                up_p = pairwise.get((up_1based, gene_idx_1based))
                up_prob_str = f"{up_p:.6f}" if up_p is not None else ""
            else:
                up_feature = ""
                up_prob_str = ""

            # Downstream neighbor (pos + 1 in operon)
            if pos_in_operon < n:
                dn_1based = cluster_1based[pos_in_operon]  # pos_in_operon is 1-based -> next element
                dn_faa = dn_1based - 1
                dn_feature = gene_ids[dn_faa] if 0 <= dn_faa < len(gene_ids) else ""
                dn_p = pairwise.get((gene_idx_1based, dn_1based))
                dn_prob_str = f"{dn_p:.6f}" if dn_p is not None else ""
            else:
                dn_feature = ""
                dn_prob_str = ""

            rows.append({
                "feature_id":                            feature,
                "organism_name":                         organism,
                "OPERON_id":                             operon_id,
                "OPERON_member_count":                   n,
                "OPERON_gene_position_in_operon":        pos_in_operon,
                "OPERON_upstream_gene_id":               up_feature,
                "OPERON_upstream_pairwise_probability":  up_prob_str,
                "OPERON_downstream_gene_id":             dn_feature,
                "OPERON_downstream_pairwise_probability": dn_prob_str,
                "OPERON_probability":                    operon_prob_str,
                "OPERON_tool_used":                      tool_used,
                "OPERON_method_used":                    method_used,
                "OPERON_command_used":                   command_used,
                "input_path":                            input_path,
                "output_path":                           output_path,
            })

    # Genes not in any multi-gene operon -> NOT_IN_AN_OPERON
    for faa_idx, feature in enumerate(gene_ids):
        gene_idx_1based = faa_idx + 1
        if gene_idx_1based in assigned:
            continue
        rows.append({
            "feature_id":                            feature,
            "organism_name":                         organism,
            "OPERON_id":                             "NOT_IN_AN_OPERON",
            "OPERON_member_count":                   1,
            "OPERON_gene_position_in_operon":        1,
            "OPERON_upstream_gene_id":               "",
            "OPERON_upstream_pairwise_probability":  "",
            "OPERON_downstream_gene_id":             "",
            "OPERON_downstream_pairwise_probability": "",
            "OPERON_probability":                    "",
            "OPERON_tool_used":                      tool_used,
            "OPERON_method_used":                    method_used,
            "OPERON_command_used":                   command_used,
            "input_path":                            input_path,
            "output_path":                           output_path,
        })

    return rows


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input-faa",     required=True,
                   help="Prodigal-style FAA fed to UniOP (uniop_input.faa)")
    p.add_argument("--input-operon",  required=True,
                   help="UniOP operon cluster CSV (uniop.operon)")
    p.add_argument("--input-pred",    default=None,
                   help="UniOP pairwise prediction scores (uniop.pred)")
    p.add_argument("--output",        required=True,
                   help="Path to write the processed per-gene TSV")
    p.add_argument("--organism-name", required=True,
                   help="Organism name recorded on every row")
    p.add_argument("--gram-stain",    default="",
                   choices=["", "positive", "negative", "unknown"],
                   help="Gram stain label recorded on every row")
    p.add_argument("--command-used",  default="",
                   help="Exact UniOP command line that produced the raw input")
    p.add_argument("--tool-used",     default="https://github.com/hongsua/UniOP",
                   help="Tool name / URL for provenance column")
    p.add_argument("--method-used",   default="",
                   help="Human-readable method summary for OPERON_method_used")
    p.add_argument("--input-path",    default="",
                   help="Input FASTA path recorded for provenance")
    p.add_argument("--output-path",   default="",
                   help="Output directory path recorded for provenance")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    faa_path    = Path(args.input_faa)
    operon_path = Path(args.input_operon)
    pred_path   = Path(args.input_pred) if args.input_pred else None
    out_path    = Path(args.output)

    for path, label in [(faa_path, "FAA"), (operon_path, "operon file")]:
        if not path.exists():
            print(f"[process_operon] ERROR: {label} not found: {path}", file=sys.stderr)
            raise SystemExit(1)

    gene_ids = parse_faa_gene_list(faa_path)
    clusters = parse_operon_clusters(operon_path)
    pairwise = parse_pred_file(pred_path)

    print(
        f"[process_operon] {len(gene_ids)} genes, "
        f"{len(clusters)} multi-gene operons, "
        f"{len(pairwise)} pairwise probabilities"
    )

    rows = build_rows(
        gene_ids, clusters, pairwise,
        args.organism_name,
        args.tool_used, args.method_used, args.command_used,
        args.input_path, args.output_path,
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=COLUMNS, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)

    in_operon  = sum(1 for r in rows if r["OPERON_id"] != "NOT_IN_AN_OPERON")
    singletons = len(rows) - in_operon
    print(
        f"[process_operon] Wrote {len(rows)} rows -> {out_path}  "
        f"({in_operon} in operons, {singletons} NOT_IN_AN_OPERON)"
    )


if __name__ == "__main__":
    main()
