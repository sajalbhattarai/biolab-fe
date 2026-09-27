#!/usr/bin/env python3
"""Rewrite Prodigal's output into the RASTtk gene_calls contract.

Downstream tools pair a protein's FASTA header with the GFF record whose ID=
matches it (operon's converter does exactly this), so both files get the same
feature id: <contig>_<n>, n being Prodigal's gene number on that contig (the
same token Prodigal already puts first in its FASTA headers). Proteins lose
their trailing '*', as in RASTtk's output. The table starts with the columns
of RASTtk's rast.tsv, which consolidation, labeling and the genome viewer read
(organism, domain, feature_id, gene_id, strand, coordinates, lengths,
sequences, feature type, description); Prodigal gives no function, so
RAST_description is empty. gene_id is written as RASTtk writes it,
<contig>_<5' end><strand><length>, which the genome viewer and report figures
parse for the contig.
"""
import argparse
import csv
import re
from pathlib import Path

ID_RE = re.compile(r"(?:^|;)ID=([^;]+)")


def read_fasta(path: Path):
    header, seq = None, []
    with path.open() as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if header is not None:
                    yield header, "".join(seq)
                header, seq = line[1:], []
            elif line:
                seq.append(line.strip())
    if header is not None:
        yield header, "".join(seq)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gff", type=Path, required=True)
    ap.add_argument("--faa", type=Path, required=True)
    ap.add_argument("--ffn", type=Path, required=True)
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--table", type=Path, required=True)
    ap.add_argument("--genetic-code", default="")
    ap.add_argument("--mode", default="")
    ap.add_argument("--organism", default="")
    ap.add_argument("--domain", default="")
    a = ap.parse_args()

    # Prodigal GFF: ID=<seq index>_<gene number>; the FASTA uses <contig>_<gene number>.
    genes = []  # dicts in genome order
    gff_lines = ["##gff-version 3"]
    with a.gff.open() as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 9 or cols[2] != "CDS":
                continue
            m = ID_RE.search(cols[8])
            if not m:
                continue
            number = m.group(1).rsplit("_", 1)[-1]
            fid = f"{cols[0]}_{number}"
            attrs = dict(kv.split("=", 1) for kv in cols[8].strip(";").split(";") if "=" in kv)
            attrs["ID"] = fid
            cols[8] = ";".join(f"{k}={v}" for k, v in attrs.items())
            gff_lines.append("\t".join(cols))
            genes.append({"fid": fid, "contig": cols[0], "start": cols[3], "end": cols[4], "strand": cols[6], "attrs": attrs})

    by_id = {g["fid"]: g for g in genes}
    a.out_dir.mkdir(parents=True, exist_ok=True)
    (a.out_dir / "genome.gff").write_text("\n".join(gff_lines) + "\n")

    def write_fasta(src: Path, dest: Path, protein: bool) -> dict:
        seqs = {}
        with dest.open("w") as out:
            for header, seq in read_fasta(src):
                fid = header.split()[0]
                if protein:
                    seq = seq.rstrip("*")
                seqs[fid] = seq
                g = by_id.get(fid)
                if g:
                    header = f"{fid} # {g['start']} # {g['end']} # {'1' if g['strand'] == '+' else '-1'} # ID={fid};" + ";".join(
                        f"{k}={v}" for k, v in g["attrs"].items() if k != "ID")
                out.write(f">{header}\n")
                for i in range(0, len(seq), 60):
                    out.write(seq[i:i + 60] + "\n")
        return seqs

    aa = write_fasta(a.faa, a.out_dir / "genome.faa", protein=True)
    na = write_fasta(a.ffn, a.out_dir / "genome.ffn", protein=False)

    cols = ["organism", "domain", "feature_id", "gene_id", "RAST_strand", "gene_start", "gene_end",
            "na_length", "aa_length", "na_seq", "aa_seq", "RAST_feature_type", "RAST_description",
            "contig", "partial", "start_type", "rbs_motif", "gc_cont", "conf", "score",
            "gene_caller", "genetic_code", "prodigal_mode"]
    a.table.parent.mkdir(parents=True, exist_ok=True)
    with a.table.open("w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t", lineterminator="\n")
        w.writerow(cols)
        for g in genes:
            at = g["attrs"]
            nseq, pseq = na.get(g["fid"], ""), aa.get(g["fid"], "")
            start, end = int(g["start"]), int(g["end"])
            five_prime = start if g["strand"] == "+" else end
            gene_id = f'{g["contig"]}_{five_prime}{g["strand"]}{end - start + 1}'
            w.writerow([a.organism, a.domain, g["fid"], gene_id, g["strand"], g["start"], g["end"],
                        len(nseq) if nseq else "", len(pseq) if pseq else "", nseq, pseq, "CDS", "",
                        g["contig"], at.get("partial", ""), at.get("start_type", ""), at.get("rbs_motif", ""),
                        at.get("gc_cont", ""), at.get("conf", ""), at.get("score", ""),
                        "prodigal", a.genetic_code, a.mode])


if __name__ == "__main__":
    main()
