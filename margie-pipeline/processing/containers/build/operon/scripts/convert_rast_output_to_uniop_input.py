#!/usr/bin/env python3
"""
convert_rast_output_to_uniop_input.py — Convert RAST GFF3 + FAA into Prodigal-style FAA
that UniOP (the operon caller) can consume.

UniOP expects FASTA headers in this exact Prodigal layout:

    >contig_name_genenum # start # stop # strand # ID=gene_id
    MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQAP...

USAGE
    convert_rast_output_to_uniop_input.py <input_gff> <input_faa> <output_faa>
"""

## Module docstring above (PEP 257). The "from __future__" import (PEP 563)
## allows modern type hints on older Python versions.
from __future__ import annotations

import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


## Module-level constant (UPPERCASE by convention, PEP 8): FASTA files
## traditionally wrap sequences at 60 characters per line. Named so the
## intent is obvious wherever it's used.
FASTA_SEQUENCE_LINE_WRAP_WIDTH = 60


## Structured record (dataclass): one parsed CDS feature plus the protein
## sequence we matched to it. A dataclass works like a NamedTuple but
## allows methods that depend on the fields — here, a method that formats
## the Prodigal-style FASTA header.
@dataclass
class coding_sequence_gene_record:
    contig_name: str
    gene_number_within_contig: int   ## 1-based, sequential per contig
    genomic_start_coordinate: int    ## 1-based, inclusive
    genomic_stop_coordinate: int     ## 1-based, inclusive
    strand_as_signed_integer: int    ## +1 = forward, -1 = reverse
    rast_gene_identifier: str
    protein_amino_acid_sequence: str

    def format_as_prodigal_fasta_header(self) -> str:
        return (f">{self.contig_name}_{self.gene_number_within_contig} "
                f"# {self.genomic_start_coordinate} "
                f"# {self.genomic_stop_coordinate} "
                f"# {self.strand_as_signed_integer} "
                f"# ID={self.rast_gene_identifier}")


## Compiled regex at module level (Python performance idiom): the pattern
## is compiled once when the module loads, rather than every time we call
## extract_gene_identifier_from_gff_attributes. `re` is the standard
## regular-expressions library.
GFF_ATTRIBUTE_ID_PATTERN = re.compile(r"ID=([^;]+)")


## Tiny single-purpose helper (uses GFF_ATTRIBUTE_ID_PATTERN above).
## GFF3 attribute columns look like "ID=fig|6666.peg.42;Name=...;...";
## we just want the ID= value.
def extract_gene_identifier_from_gff_attributes(gff_attribute_column: str) -> str | None:
    match_result = GFF_ATTRIBUTE_ID_PATTERN.search(gff_attribute_column)
    return match_result.group(1) if match_result else None


## Step 1 — read every protein sequence from the RAST FAA (FASTA parser
## by hand because biopython is overkill). The `with open(...)` block is
## a context manager — Python guarantees the file is closed even if an
## error occurs midway through reading.
def read_protein_sequences_from_faa_file(faa_file_path: Path) -> tuple[dict[str, str], list[str]]:
    sequences_keyed_by_gene_identifier: dict[str, str] = {}
    protein_sequences_in_input_order: list[str] = []
    current_gene_identifier: str | None = None
    current_sequence_chunks: list[str] = []

    def flush_current_record_into_dictionary() -> None:
        if current_gene_identifier is not None:
            assembled_sequence = "".join(current_sequence_chunks)
            sequences_keyed_by_gene_identifier[current_gene_identifier] = assembled_sequence
            protein_sequences_in_input_order.append(assembled_sequence)

    with open(faa_file_path) as input_file_handle:
        for raw_line in input_file_handle:
            if raw_line.startswith(">"):
                flush_current_record_into_dictionary()
                ## Header looks like ">fig|...peg.42 description..."; the
                ## first whitespace-separated token is the gene ID.
                current_gene_identifier = raw_line[1:].strip().split()[0]
                current_sequence_chunks = []
            else:
                current_sequence_chunks.append(raw_line.strip())
        flush_current_record_into_dictionary()

    return sequences_keyed_by_gene_identifier, protein_sequences_in_input_order


## Step 2 — read the GFF and build coding_sequence_gene_record objects (uses
## extract_gene_identifier_from_gff_attributes above and the protein
## sequences from Step 1). collections.defaultdict(int) is used as a
## per-contig counter that starts at 0 for any new contig key.
def read_coding_sequence_records_from_gff(
    gff_file_path: Path,
    protein_sequences_by_gene_identifier: dict[str, str],
    protein_sequences_in_input_order: list[str],
) -> list[coding_sequence_gene_record]:
    parsed_gene_records: list[coding_sequence_gene_record] = []
    sequential_gene_counter_per_contig: dict[str, int] = defaultdict(int)
    fallback_sequence_index = 0
    generic_protein_identifier_mode = (
        bool(protein_sequences_by_gene_identifier)
        and all(re.match(r"^protein_\d+$", identifier)
                for identifier in protein_sequences_by_gene_identifier)
    )

    with open(gff_file_path) as input_file_handle:
        for raw_line in input_file_handle:
            stripped_line = raw_line.strip()
            if not stripped_line or stripped_line.startswith("#"):
                continue

            tab_separated_columns = stripped_line.split("\t")
            if len(tab_separated_columns) < 9:
                continue

            contig_name        = tab_separated_columns[0]
            feature_type       = tab_separated_columns[2]
            genomic_start_text = tab_separated_columns[3]
            genomic_stop_text  = tab_separated_columns[4]
            strand_text        = tab_separated_columns[6]
            attribute_column   = tab_separated_columns[8]

            if feature_type != "CDS":
                continue   ## we only care about coding sequences

            gene_identifier = extract_gene_identifier_from_gff_attributes(attribute_column)
            if gene_identifier is None:
                print(f"[convert_rast_to_uniop] WARNING: no ID= in attributes: {attribute_column}",
                      file=sys.stderr)
                continue

            sequential_gene_counter_per_contig[contig_name] += 1

            protein_sequence = protein_sequences_by_gene_identifier.get(gene_identifier, "")
            if not protein_sequence and generic_protein_identifier_mode:
                if fallback_sequence_index < len(protein_sequences_in_input_order):
                    protein_sequence = protein_sequences_in_input_order[fallback_sequence_index]
                fallback_sequence_index += 1

            parsed_gene_records.append(coding_sequence_gene_record(
                contig_name=contig_name,
                gene_number_within_contig=sequential_gene_counter_per_contig[contig_name],
                genomic_start_coordinate=int(genomic_start_text),
                genomic_stop_coordinate=int(genomic_stop_text),
                strand_as_signed_integer=(1 if strand_text == "+" else -1),
                rast_gene_identifier=gene_identifier,
                protein_amino_acid_sequence=protein_sequence,
            ))

    ## Sort by (contig, start) so the output FAA is in genomic order, which
    ## downstream operon callers depend on. `sorted` with a `key=` lambda
    ## that returns a tuple does lexicographic multi-key sorting.
    parsed_gene_records.sort(key=lambda record: (record.contig_name, record.genomic_start_coordinate))
    return parsed_gene_records


## Step 3 — write the Prodigal-style FAA (uses
## format_as_prodigal_fasta_header on each record and the constant
## FASTA_SEQUENCE_LINE_WRAP_WIDTH). Returns a (written, missing) tuple so
## the caller can log both counts.
def write_prodigal_style_faa_file(
    parsed_gene_records: list[coding_sequence_gene_record],
    output_file_path: Path,
) -> tuple[int, int]:
    number_of_records_written = 0
    number_of_records_missing_sequence = 0

    with open(output_file_path, "w") as output_file_handle:
        for record in parsed_gene_records:
            if not record.protein_amino_acid_sequence:
                number_of_records_missing_sequence += 1
                print(f"[convert_rast_to_uniop] WARNING: no sequence for {record.rast_gene_identifier}",
                      file=sys.stderr)
                continue

            output_file_handle.write(record.format_as_prodigal_fasta_header() + "\n")
            for line_start_offset in range(0,
                                           len(record.protein_amino_acid_sequence),
                                           FASTA_SEQUENCE_LINE_WRAP_WIDTH):
                output_file_handle.write(
                    record.protein_amino_acid_sequence[
                        line_start_offset:line_start_offset + FASTA_SEQUENCE_LINE_WRAP_WIDTH
                    ] + "\n"
                )
            number_of_records_written += 1

    return number_of_records_written, number_of_records_missing_sequence


## Entry point (`if __name__ == "__main__"` guard, Python idiom): runs
## only when the file is executed as a script. CLI is positional (no
## argparse here) because the calling shell script in
## operon/scripts/run_tool_inside_container.sh already passes the three paths in order:
##     python3 convert_rast_output_to_uniop_input.py "$GFF" "$FAA" "$CONVERTED_FAA"
## Calls Step 1 → Step 2 → Step 3 in that order.
def main() -> None:
    if len(sys.argv) != 4:
        print("Usage: convert_rast_output_to_uniop_input.py <input_gff> <input_faa> <output_faa>",
              file=sys.stderr)
        sys.exit(1)

    gff_file_path    = Path(sys.argv[1])
    faa_file_path    = Path(sys.argv[2])
    output_file_path = Path(sys.argv[3])

    for human_label, file_path in [("GFF", gff_file_path), ("FAA", faa_file_path)]:
        if not file_path.exists():
            print(f"[convert_rast_to_uniop] ERROR: {human_label} not found: {file_path}",
                  file=sys.stderr)
            sys.exit(1)

    output_file_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"[convert_rast_to_uniop] Reading protein sequences from {faa_file_path}")
    protein_sequences_by_gene_identifier, protein_sequences_in_input_order = read_protein_sequences_from_faa_file(faa_file_path)
    print(f"[convert_rast_to_uniop] Loaded {len(protein_sequences_by_gene_identifier)} protein sequences")

    print(f"[convert_rast_to_uniop] Reading CDS features from {gff_file_path}")
    parsed_gene_records = read_coding_sequence_records_from_gff(
        gff_file_path, protein_sequences_by_gene_identifier, protein_sequences_in_input_order,
    )
    print(f"[convert_rast_to_uniop] Parsed {len(parsed_gene_records)} CDS features")

    number_of_records_written, number_of_records_missing_sequence = write_prodigal_style_faa_file(
        parsed_gene_records, output_file_path,
    )
    print(f"[convert_rast_to_uniop] Wrote {number_of_records_written} genes → {output_file_path}")
    if number_of_records_missing_sequence:
        print(f"[convert_rast_to_uniop] WARNING: {number_of_records_missing_sequence} "
              f"genes had no protein sequence", file=sys.stderr)


if __name__ == "__main__":
    main()
