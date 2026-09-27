#!/usr/bin/env python3
"""
Consolidate RASTtk annotation outputs into a single rast.tsv file.

This script merges CDS, RNA, and prophage annotations with sequences,
extracting EC numbers and parsing gene locations.
It also enriches the output with complete SEED Subsystem variant definitions,
including curator metadata, variant descriptions, notes, and versions.

Usage:
    python consolidate_rast_output.py <rast_output_dir> <organism_name>

Example:
    python consolidate_rast_output.py output/rasttk/theta "Bacteroides thetaiotaomicron"
"""

import sys
import os
import re
import csv
import json
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from collections import defaultdict

# -----------------------------------------------------------------------------
# Subsystem Enrichment Logic with SEED Variant Definitions
# -----------------------------------------------------------------------------

def load_subsystem_mapping(mapping_file: str) -> Dict[str, List[Dict[str, str]]]:
    """
    Loads subsystem mapping from a TSV file.
    Format: subsystem_id, roles (:: sep), subsystem_name, superclass, class, subclass
    Returns: Dict { role_name: [ {subsystem_name, superclass, class, subclass} ] }
    """
    role_to_subsystems = {}
    
    if not os.path.exists(mapping_file):
        print(f"Warning: Subsystem mapping file not found at {mapping_file}. Skipping enrichment.")
        return role_to_subsystems

    print(f"Loading subsystem mapping from {mapping_file}...")
    try:
        with open(mapping_file, 'r', encoding='utf-8') as f:
            reader = csv.reader(f, delimiter='\t')
            # Check header
            headers = next(reader, None)
            # Detect format. Two layouts are seen in the wild:
            #   (A) p3-all-subsystems wide format (6 cols):
            #        subsystem_id | roles (::-sep) | subsystem_name |
            #        superclass | class | subclass
            #   (B) repo-bundled long format (3 cols):
            #        subsystem | role | variant
            # The bundled db/rasttk/subsystem_mapping.tsv is layout (B),
            # so we treat anything with <= 3 cols as layout (B) and
            # populate only the subsystem name (super/class/subclass
            # left blank -- the host-side enrichment fills the rest).
            is_long_format = (headers is not None and len(headers) <= 3)
            if is_long_format:
                print("  format detected: long (subsystem,role,variant) -- 3-col")
            else:
                print("  format detected: wide (p3-all-subsystems) -- 6-col")
            
            for row in reader:
                if is_long_format:
                    # subsystem \t role \t variant
                    if len(row) < 2:
                        continue
                    subsystem_name = row[0].strip()
                    role_clean = row[1].strip()
                    if not subsystem_name or not role_clean:
                        continue
                    role_to_subsystems.setdefault(role_clean, []).append({
                        'name': subsystem_name,
                        'superclass': '',
                        'class': '',
                        'subclass': '',
                    })
                    continue

                if len(row) < 6:
                    continue
                
                # Parse row based on p3-all-subsystems output
                # 0: subsystem_id
                # 1: roles (:: separated)
                # 2: subsystem_name
                # 3: superclass
                # 4: class
                # 5: subclass
                
                roles_str = row[1]
                subsystem_info = {
                    'name': row[2],
                    'superclass': row[3],
                    'class': row[4],
                    'subclass': row[5]
                }
                
                # Split roles by '::'
                roles = roles_str.split('::')
                for role in roles:
                    role_clean = role.strip()
                    if not role_clean:
                        continue
                    
                    if role_clean not in role_to_subsystems:
                        role_to_subsystems[role_clean] = []
                    role_to_subsystems[role_clean].append(subsystem_info)
                    
    except Exception as e:
        print(f"Error loading subsystem mapping: {e}")

    print(f"Loaded subsystem mapping for {len(role_to_subsystems)} roles.")
    return role_to_subsystems


# NOTE: Per-variant SEED metadata (curator / variant definition / notes /
# variant_roles / subsystem_variants) used to be loaded here from a local
# `variant_definitions/` tree. That layer has been retired -- the postproc
# enricher (postproc/enrich-rast-tsv.py) now handles all of that from
# seed_database_long.tsv, emitting the rich `subsystem_*` block. The four
# loader functions and their seven empty `SEED_*` columns were removed.


# -----------------------------------------------------------------------------
# Existing Logic Helper Functions
# -----------------------------------------------------------------------------

def parse_gene_location(gene_id: str) -> Tuple[int, int, str]:
    """
    Parse gene location from gene_id string.
    
    Examples:
        NODE_1_length_527240_cov_20.279845_15807+1122 -> (15807, 16929, '+')
        NODE_1_length_527240_cov_20.279845_15807-1122 -> (14685, 15807, '-')
    
    Returns:
        (start, end, strand)
    """
    # Extract the location part (last component after final underscore)
    match = re.search(r'_(\d+)([+-])(\d+)$', gene_id)
    if match:
        start = int(match.group(1))
        strand = match.group(2)
        length = int(match.group(3))
        
        if strand == '+':
            end = start + length
        else:  # strand == '-'
            end = start
            start = start - length
        
        return start, end, strand
    
    return 0, 0, '?'


def extract_ec_numbers(description: str) -> str:
    """
    Extract EC numbers from description string.
    
    Examples:
        "Aerotolerance protein BatE (EC 4.3.3.7)" -> "EC 4.3.3.7"
        "Some protein (EC 1.1.1.1) and (EC 2.2.2.2)" -> "EC 1.1.1.1; EC 2.2.2.2"
    """
    ec_pattern = r'\(EC[\s]+[\d\.\-]+\)'
    ec_matches = re.findall(ec_pattern, description)
    
    if ec_matches:
        # Clean up and join multiple EC numbers
        ec_numbers = [ec.strip('()').strip() for ec in ec_matches]
        return '; '.join(ec_numbers)
    
    return ''


def load_sequences(fasta_file: str) -> Dict[str, str]:
    """
    Load sequences from FASTA file.
    
    Returns:
        Dictionary mapping feature_id to sequence
    """
    sequences = {}
    current_id = None
    current_seq = []
    
    if not os.path.exists(fasta_file):
        return sequences
    
    with open(fasta_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('>'):
                # Save previous sequence
                if current_id:
                    sequences[current_id] = ''.join(current_seq)
                
                # Start new sequence
                # Header format: >fig|6666666.1476522.peg.1 function
                current_id = line[1:].split()[0]
                current_seq = []
            else:
                current_seq.append(line)
        
        # Save last sequence
        if current_id:
            sequences[current_id] = ''.join(current_seq)
    
    return sequences


def load_tsv_data(tsv_file: str) -> List[List[str]]:
    """Load TSV file data."""
    data = []
    if not os.path.exists(tsv_file):
        return data
    
    with open(tsv_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                data.append(line.split('\t'))
    
    return data


def consolidate_rast_annotations(rast_dir: str, organism_name: str, output_file: str,
                                 domain: str = ""):
    """
    Consolidate all RASTtk outputs into a single rast.tsv file with complete SEED enrichment.
    """
    rast_path = Path(rast_dir)
    
    # -------------------------------------------------------------------------
    # 1. Setup Enrichment - Load all SEED data
    # -------------------------------------------------------------------------
    script_dir = os.path.dirname(os.path.abspath(__file__))
    base_dir = os.path.abspath(os.path.join(script_dir, '../'))
    db_override = os.environ.get("RASTTK_DB_DIR", "").strip()
    
    # Paths for subsystem mapping and variant definitions
    # Priority: 1) RASTTK_DB_DIR override, 2) Container path, 3) Local bvbrc_container/database, 4) Legacy path
    # For each location we prefer the 6-col wide format (subsystem_mapping_wide.tsv)
    # which carries class/subclass; we fall back to the 3-col long format
    # (subsystem_mapping.tsv). load_subsystem_mapping() auto-detects layout.
    def _pick(*candidates):
        for c in candidates:
            if c and os.path.exists(c):
                return c
        return ""
    mapping_path_override = _pick(
        os.path.join(db_override, "subsystem_mapping_wide.tsv") if db_override else "",
        os.path.join(db_override, "subsystem_mapping.tsv")      if db_override else "",
    )
    variant_defs_override = os.path.join(db_override, "variant_definitions") if db_override else ""

    mapping_path_container = _pick("/db/subsystem_mapping_wide.tsv",
                                   "/db/subsystem_mapping.tsv")
    mapping_path_bvbrc = _pick(
        os.path.join(base_dir, "database/subsystem_mapping_wide.tsv"),
        os.path.join(base_dir, "database/subsystem_mapping.tsv"),
    )
    mapping_path_legacy = _pick(
        os.path.join(base_dir, "../processing/database/subsystem_mapping_wide.tsv"),
        os.path.join(base_dir, "../processing/database/subsystem_mapping.tsv"),
    )
    
    variant_defs_container = "/db/variant_definitions"
    variant_defs_bvbrc = os.path.join(base_dir, "database/variant_definitions")
    variant_defs_legacy = os.path.join(base_dir, "../processing/database/variant_definitions")
    
    # Check which paths exist
    if mapping_path_override and os.path.exists(mapping_path_override):
        mapping_file = mapping_path_override
        variant_defs_dir = variant_defs_override
        print(f"Using DB override from RASTTK_DB_DIR: {db_override}")
    elif os.path.exists(mapping_path_container):
        mapping_file = mapping_path_container
        variant_defs_dir = variant_defs_container
        print(f"Using container database paths")
    elif os.path.exists(mapping_path_bvbrc):
        mapping_file = mapping_path_bvbrc
        variant_defs_dir = variant_defs_bvbrc
        print(f"Using bvbrc_container database paths: {base_dir}/database/")
    elif os.path.exists(mapping_path_legacy):
        mapping_file = mapping_path_legacy
        variant_defs_dir = variant_defs_legacy
        print(f"Using legacy database paths")
    else:
        mapping_file = None
        variant_defs_dir = None
        print("Warning: No database paths found!")
    
    # Load subsystem mapping (role -> subsystem hierarchy)
    role_to_subsystems = {}
    if mapping_file:
        role_to_subsystems = load_subsystem_mapping(mapping_file)
    else:
        print("No subsystem mapping file found. Proceeding without enrichment.")
    
    # Load SEED variant data
    subsystem_metadata = {}
    variant_roles = {}
    subsystem_variants = {}
    
    if variant_defs_dir and os.path.exists(variant_defs_dir):
        print("Loading SEED variant definitions...")
        
        metadata_file = os.path.join(variant_defs_dir, 'local_references', 'subsystem_metadata.tsv')
        if os.path.exists(metadata_file):
            subsystem_metadata = load_subsystem_metadata(metadata_file)
            print(f"  Loaded metadata for {len(subsystem_metadata)} subsystems")
        
        roles_file = os.path.join(variant_defs_dir, 'structured_database', 'tsv_tables', 'variant_roles.tsv')
        if os.path.exists(roles_file):
            variant_roles = load_variant_roles_mapping(roles_file)
            print(f"  Loaded role assignments for {len(variant_roles)} variants")
        
        variants_file = os.path.join(variant_defs_dir, 'structured_database', 'tsv_tables', 'subsystem_variants.tsv')
        if os.path.exists(variants_file):
            subsystem_variants = load_subsystem_variants(variants_file)
            print(f"  Loaded {len(subsystem_variants)} variant definitions")
    else:
        print("SEED variant definitions not found. Will only include basic subsystem info.")

    # -------------------------------------------------------------------------
    # 2. Identify Input Files
    # -------------------------------------------------------------------------
    # Check if files are in 'raw' subdirectory (standard pipeline structure);
    # fall back to legacy 'native' for backward compatibility.
    search_path = rast_path / "raw"
    if not search_path.exists():
        legacy = rast_path / "native"
        search_path = legacy if legacy.exists() else rast_path

    # Find the genome prefix (e.g., "theta" from "theta_CDS.tsv")
    cds_files = list(search_path.glob('*_CDS.tsv'))
    if not cds_files:
        print(f"Error: No CDS.tsv file found in {search_path}", file=sys.stderr)
        return
    
    genome_prefix = cds_files[0].stem.replace('_CDS', '')
    
    # Define file paths in the correct directory
    cds_file = search_path / f"{genome_prefix}_CDS.tsv"
    rna_file = search_path / f"{genome_prefix}_RNA.tsv"
    prophage_file = search_path / f"{genome_prefix}_prophage.tsv"
    
    # Sequences might be in 'gene_calls' or 'raw' depending on when this is run.
    # Pipeline moves them to gene_calls at the end and may append a domain-tag
    # suffix (e.g. _gramN) to the filename, so glob is used to find them.
    def _find_seq(parent, ext):
        exact = parent / f"{genome_prefix}{ext}"
        if exact.exists():
            return exact
        matches = sorted(parent.glob(f"{genome_prefix}*{ext}"))
        return matches[0] if matches else exact

    gene_calls_path = rast_path / "gene_calls"
    if gene_calls_path.exists() and any(gene_calls_path.glob(f"{genome_prefix}*.faa")):
        faa_file = _find_seq(gene_calls_path, ".faa")
        ffn_file = _find_seq(gene_calls_path, ".ffn")
    else:
        # Fallback to search path (raw / native / root)
        faa_file = _find_seq(search_path, ".faa")
        ffn_file = _find_seq(search_path, ".ffn")
    
    print(f"Loading sequences from {faa_file}...")
    aa_sequences = load_sequences(str(faa_file))
    
    print(f"Loading sequences from {ffn_file}...")
    na_sequences = load_sequences(str(ffn_file))
    
    # Prepare output data
    all_rows = []
    
    # Helper to process features
    def process_features(file_path, feature_type_override=None):
        if not os.path.exists(file_path):
            return 0
            
        print(f"Processing features from {file_path}...")
        data = load_tsv_data(str(file_path))
        count = 0
        
        for row in data:
            if len(row) < 4:
                continue
            
            feature_id = row[0]
            gene_id = row[1] # Contains location
            gene_type = feature_type_override if feature_type_override else (row[2] if len(row) > 2 else '')
            description = row[3] if len(row) > 3 else ''
            feature_hash = row[5] if len(row) > 5 else ''
            
            # Parse location
            gene_start, gene_end, strand = parse_gene_location(gene_id)
            
            # Extract EC numbers
            ec_numbers = extract_ec_numbers(description)
            
            # Get sequences
            aa_seq = aa_sequences.get(feature_id, '')
            na_seq = na_sequences.get(feature_id, '')
            
            # Calculate lengths
            aa_length = len(aa_seq)
            na_length = len(na_seq)
            
            # --------------------------------
            # Subsystem hierarchy enrichment (BV-BRC mapping).
            # Per-variant SEED metadata (curator/definition/notes) is
            # populated by the postproc enricher, not here.
            # --------------------------------
            sub_superclass = []
            sub_class = []
            sub_subclass = []
            sub_name = []

            # Lookup role (description) in dictionary
            if description in role_to_subsystems:
                for sub in role_to_subsystems[description]:
                    if sub['superclass']: sub_superclass.append(sub['superclass'])
                    if sub['class']: sub_class.append(sub['class'])
                    if sub['subclass']: sub_subclass.append(sub['subclass'])
                    if sub['name']: sub_name.append(sub['name'])
            
            # Join unique values
            def join_unique(items):
                return "; ".join(sorted(list(set(items))))
            
            # NOTE: the order of values here MUST match the `header` list
            # written below (see consolidate_rast_annotations) verbatim.
            row_data = [
                # identity
                organism_name,
                domain,
                feature_id,
                gene_id,
                # coordinates + sequence
                str(gene_start),
                str(gene_end),
                str(na_length),
                str(aa_length),
                na_seq,
                aa_seq,
                # RAST feature attributes
                gene_type,
                strand,
                description,
                ec_numbers,
                feature_hash,
                os.path.basename(str(file_path)),
                json.dumps(row, ensure_ascii=False),
                # BV-BRC subsystem hierarchy
                join_unique(sub_superclass),
                join_unique(sub_class),
                join_unique(sub_subclass),
                join_unique(sub_name),
            ]
            all_rows.append(row_data)
            count += 1
            
        return count

    # Process all types
    n_cds = process_features(cds_file)
    n_rna = process_features(rna_file)
    n_prophage = process_features(prophage_file, feature_type_override='prophage')
    
    # Write output file
    print(f"\nWriting consolidated output to {output_file}...")
    with open(output_file, 'w', newline='') as f:
        # Header layout (logical, gene -> identity -> hierarchy -> SEED static -> enrichment):
        #   1) genome/feature identity
        #   2) coordinates + sequence
        #   3) RAST feature attributes
        #   4) BV-BRC subsystem hierarchy (per-role canonical 3-tier)
        #   5) SEED static metadata (variant definition / curation provenance)
        #
        # The post-processor (enrich-rast-tsv.py) then appends these blocks in
        # this order: SUBSYSTEM (local hierarchy + role coverage + variant
        # calls) -> CHEMISTRY -> REFERENCE evidence.
        header = [
            # ── identity ─────────────────────────────────────────────────────────
            'organism',
            'domain',
            'feature_id',
            'gene_id',
            # ── coordinates + sequence ─────────────────────────────────────────
            'gene_start',
            'gene_end',
            'na_length',
            'aa_length',
            'na_seq',
            'aa_seq',
            # ── RAST feature attributes ────────────────────────────────────────
            'RAST_feature_type',
            'RAST_strand',
            'RAST_description',
            'RAST_EC_numbers',
            'RAST_feature_hash',
            'RAST_source_file',
            'RAST_genecaller_raw_row',
            # ── BV-BRC subsystem hierarchy (per-role, canonical) ─────────────────────
            'RAST_BVBRC_Superclass',
            'RAST_BVBRC_Class',
            'RAST_BVBRC_Subclass',
            'RAST_BVBRC_Name',
        ]
        writer = csv.writer(f, delimiter='\t')
        writer.writerow(header)
        writer.writerows(all_rows)
            
    print(f"\nSuccessfully created {output_file}")
    print(f"  Total features: {len(all_rows)}")
    print(f"  - CDS: {n_cds}")
    print(f"  - RNA: {n_rna}")
    print(f"  - Prophage: {n_prophage}")


def main():
    # CLI:
    #   generate_rast_tsv.py <rast_output_dir> <organism_name> [<domain>]
    if len(sys.argv) < 3 or len(sys.argv) > 4:
        print("Usage: python generate_rast_tsv.py <rast_output_dir> <organism_name> [<domain>]", file=sys.stderr)
        print("\nExample:", file=sys.stderr)
        print('  python generate_rast_tsv.py output/rasttk/theta "Bacteroides thetaiotaomicron" Bacteria', file=sys.stderr)
        sys.exit(1)

    rast_dir = sys.argv[1]
    organism_name = sys.argv[2]
    domain = sys.argv[3] if len(sys.argv) >= 4 else ""

    output_file = os.path.join(rast_dir, 'rast.tsv')

    consolidate_rast_annotations(rast_dir, organism_name, output_file, domain)


if __name__ == '__main__':
    main()
