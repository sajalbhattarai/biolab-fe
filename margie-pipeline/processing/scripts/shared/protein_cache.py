#!/usr/bin/env python3
"""A tool's results kept per protein, so a protein is annotated only once.

result_cache.py keeps a tool's whole output per GENOME: one changed base and
every tool reruns on every protein. This keeps each tool's rows per PROTEIN,
keyed by the SHA-256 of its amino acids (upper case, no whitespace, no final
*), in the same SQLite file -- margie-backend's protein_cache.py, for this
pipeline's layout (<tool>/<genome>/processed/*.tsv and raw/tigrfam_domtbl.out).

  split  The genome's proteins the tool has done before, and the rest: the
         rest are written as <work>/input/<genome>/gene_calls/genome.faa, for
         the tool's runner to read (TOOL_<tool>_INPUT); the others' rows,
         under this genome's feature ids and name, to <work>/cached/.
  merge  After the runner (or instead of it, when nothing is new): the tool's
         rows and the cached rows, in the files everything after reads.
  store  Every protein of the genome not yet kept, from the final files --
         with no rows when the tool found nothing, which is an answer too.

Only tools whose rows depend on nothing but the protein (TOOLS). The key
(`key`) is the tool, its image and container file, its database folder and
its settings; any of them changing starts the tool afresh. Nothing is deleted.
Only the standard library is used.

    protein_cache.py key   <tool> <part>...                          -> key
    protein_cache.py split <db> <faa> <work> <genome> <tool> <key>   -> "<cached> <new>"
                          (<genome>: its folder under the tool, e.g. bucket/name; rows take its last part)
    protein_cache.py merge <work> <tooldir> <tool> <ran:0|1>
    protein_cache.py store <db> <faa> <tooldir> <tool> <key>         -> proteins added
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

TOOLS = ['cog', 'kegg', 'eggnog', 'uniprot', 'pfam', 'merops', 'tcdb', 'dbcan', 'pgap', 'tmbed',
         'tigrfam', 'phobius', 'interpro']

CREATE_SQL = """
CREATE TABLE IF NOT EXISTS protein_cache (
    aa_hash TEXT NOT NULL,
    tool TEXT NOT NULL,
    tool_key TEXT NOT NULL,
    filename TEXT NOT NULL,
    lines TEXT NOT NULL,
    cached_at TEXT NOT NULL,
    PRIMARY KEY (tool, tool_key, filename, aa_hash)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS protein_cache_header (
    tool TEXT NOT NULL,
    tool_key TEXT NOT NULL,
    filename TEXT NOT NULL,
    header TEXT NOT NULL,
    PRIMARY KEY (tool, tool_key, filename)
) WITHOUT ROWID;
"""


def tool_files(tool: str, tooldir: Path | None = None) -> list[tuple[str, str]]:
    """Returns the tool's result files as (path under <tool>/<genome>/, kind), primary first.
    InterPro's per-database tables are the ones found in tooldir."""
    main = (f'processed/{tool}_results.tsv', 'tsv')
    if tool == 'tigrfam':
        return [main, ('raw/tigrfam_domtbl.out', 'domtbl')]
    if tool == 'phobius':
        return [main, ('processed/phobius_top1.tsv', 'tsv')]
    if tool == 'interpro':
        extra = []
        if tooldir is not None and (tooldir / 'processed').is_dir():
            extra = sorted(f'processed/{p.name}' for p in (tooldir / 'processed').glob('interpro_*_results.tsv')
                           if p.name != 'interpro_results.tsv')
        return [main] + [(e, 'tsv?') for e in extra]
    return [main]


# ── proteins ────────────────────────────────────────────────────────────────

def protein_hash(seq: str) -> str:
    return hashlib.sha256(''.join(seq.split()).upper().rstrip('*').encode()).hexdigest()


def read_fasta(path: str):
    header, parts = None, []
    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            if line.startswith('>'):
                if header is not None:
                    yield header, ''.join(parts)
                header, parts = line[1:].rstrip('\n'), []
            else:
                parts.append(''.join(line.split()))
    if header is not None:
        yield header, ''.join(parts)


def proteins(faa: str) -> list[tuple[str, str, str, str]]:
    out = []
    for header, seq in read_fasta(faa):
        words = header.split()
        if words and seq:
            out.append((words[0], protein_hash(seq), header, seq))
    return out


# ── rows ────────────────────────────────────────────────────────────────────

_DOMTBL_ID = re.compile(r'^(\S+\s+\S+\s+\S+\s+)(\S+)')


def _cols(header: str):
    c = header.rstrip('\n').split('\t')
    return (c.index('feature_id') if 'feature_id' in c else None,
            c.index('organism_name') if 'organism_name' in c else None)


def _remap(line: str, kind: str, cols, fid: str, genome: str) -> str:
    if kind == 'domtbl':
        return _DOMTBL_ID.sub(lambda m: m.group(1) + fid, line, count=1)
    parts = line.split('\t')
    for i, v in ((cols[0], fid), (cols[1], genome)):
        if i is not None and i < len(parts):
            parts[i] = v
    return '\t'.join(parts)


def _read(path: Path, kind: str):
    """Returns (header, {feature id: lines}) of one results file; (None, {}) if absent or empty."""
    if not path.is_file() or path.stat().st_size == 0:
        return None, {}
    lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    rows: dict[str, list[str]] = {}
    if kind == 'domtbl':
        head = []
        for line in lines:
            if line.startswith('#'):
                if not rows:
                    head.append(line)
                continue
            m = _DOMTBL_ID.match(line)
            if m:
                rows.setdefault(m.group(2), []).append(line)
        return '\n'.join(head[:3]), rows
    fid_col, _ = _cols(lines[0])
    if fid_col is not None:
        for line in lines[1:]:
            parts = line.split('\t')
            if fid_col < len(parts):
                rows.setdefault(parts[fid_col], []).append(line)
    return lines[0], rows


# ── the database ────────────────────────────────────────────────────────────

def _connect(db: str) -> sqlite3.Connection:
    Path(db).expanduser().parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(Path(db).expanduser()), timeout=120)
    conn.execute('PRAGMA busy_timeout=120000')
    conn.executescript(CREATE_SQL)
    return conn


def _chunks(items, n=500):
    for i in range(0, len(items), n):
        yield items[i:i + n]


def _kept(conn, tool, key, filename, hashes) -> set[str]:
    found = set()
    for c in _chunks(hashes):
        found.update(r[0] for r in conn.execute(
            'SELECT aa_hash FROM protein_cache WHERE tool=? AND tool_key=? AND filename=? '
            f'AND aa_hash IN ({",".join("?" * len(c))})', (tool, key, filename, *c)))
    return found


# ── commands ────────────────────────────────────────────────────────────────

def key(tool: str, parts: list[str]) -> str:
    """Returns a hash of the tool and its inputs; path parts add their size and mtime."""
    described = []
    for p in parts:
        q = Path(p)
        try:
            st = q.stat()
            described.append([p, 0 if q.is_dir() else st.st_size, int(st.st_mtime)])
        except OSError:
            described.append([p])
    return hashlib.sha256(json.dumps({'schema': 1, 'tool': tool, 'parts': described}).encode()).hexdigest()[:32]


def split(db: str, faa: str, work: str, genome: str, tool: str, tkey: str) -> tuple[int, int]:
    name = Path(genome).name
    prot = proteins(faa)
    hashes = sorted({h for _, h, _, _ in prot})
    w = Path(work)
    shutil.rmtree(w, ignore_errors=True)  # this step's own working files
    (w / 'cached').mkdir(parents=True)
    (w / 'input' / genome / 'gene_calls').mkdir(parents=True)
    conn = _connect(db)
    try:
        files = [(f, 'domtbl' if f.endswith('.out') else ('tsv' if i == 0 or tool != 'interpro' else 'tsv?'))
                 for i, (f,) in enumerate(conn.execute(
                     'SELECT filename FROM protein_cache_header WHERE tool=? AND tool_key=? ORDER BY filename',
                     (tool, tkey)).fetchall())]
        primary = tool_files(tool)[0][0]
        kept = _kept(conn, tool, tkey, primary, hashes)
        with open(w / 'input' / genome / 'gene_calls' / 'genome.faa', 'w') as fh:
            for _, h, header, seq in prot:
                if h not in kept:
                    fh.write(f'>{header}\n' + ''.join(seq[i:i + 60] + '\n' for i in range(0, len(seq), 60)))
        want = sorted(kept)
        for filename, kind in files:
            header = conn.execute('SELECT header FROM protein_cache_header WHERE tool=? AND tool_key=? AND filename=?',
                                  (tool, tkey, filename)).fetchone()[0]
            stored = {}
            for c in _chunks(want):
                stored.update(conn.execute(
                    'SELECT aa_hash, lines FROM protein_cache WHERE tool=? AND tool_key=? AND filename=? '
                    f'AND aa_hash IN ({",".join("?" * len(c))})', (tool, tkey, filename, *c)))
            cols = _cols(header) if kind != 'domtbl' else (None, None)
            out = w / 'cached' / filename
            out.parent.mkdir(parents=True, exist_ok=True)
            with open(out, 'w') as fh:
                fh.write(header + '\n')
                for fid, h, _, _ in prot:
                    for line in (stored.get(h) or '').splitlines():
                        fh.write(_remap(line, kind, cols, fid, name) + '\n')
    finally:
        conn.close()
    n_kept = sum(1 for p in prot if p[1] in kept)
    return n_kept, len(prot) - n_kept


def merge(work: str, tooldir: str, tool: str, ran: bool) -> None:
    """Writes the tool's own rows (when it ran) followed by the cached rows into each file."""
    w, t = Path(work), Path(tooldir)
    names = {f for f, _ in tool_files(tool, t if ran else None)}
    names |= {str(p.relative_to(w / 'cached')) for p in (w / 'cached').rglob('*') if p.is_file()}
    for name in sorted(names):
        kind = 'domtbl' if name.endswith('.out') else 'tsv'
        dest, cached = t / name, w / 'cached' / name
        produced = dest if ran and dest.is_file() and dest.stat().st_size > 0 else None
        if not cached.is_file():
            if produced is None and not ran and name == tool_files(tool)[0][0]:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text('')
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        extra = cached.read_text().splitlines()
        if produced is None:
            dest.write_text(cached.read_text())
            continue
        rows = [l for l in extra if not l.startswith('#')] if kind == 'domtbl' else extra[1:]
        if rows:
            with open(dest, 'a') as fh:
                fh.write('\n'.join(rows) + '\n')


def store(db: str, faa: str, tooldir: str, tool: str, tkey: str) -> int:
    t = Path(tooldir)
    files = tool_files(tool, t)
    if not (t / files[0][0]).is_file():
        return 0
    prot = proteins(faa)
    first: dict[str, str] = {}
    for fid, h, _, _ in prot:
        first.setdefault(h, fid)
    tables = {}
    for name, kind in files:
        header, rows = _read(t / name, kind)
        if header is None and kind == 'tsv':
            return 0
        tables[name] = (header, rows)
    # Rows under foreign ids would store every protein as "nothing found", so they abort the store.
    ids = {fid for fid, _, _, _ in prot}
    rows = tables[files[0][0]][1]
    if rows and sum(1 for f in rows if f not in ids) > 0.01 * len(rows):
        print(f'protein cache: {t / files[0][0]} is not about {faa}; not kept', file=sys.stderr)
        return 0
    conn = _connect(db)
    try:
        new = sorted(set(first) - _kept(conn, tool, tkey, files[0][0], sorted(first)))
        if not new:
            return 0
        now = datetime.now(timezone.utc).isoformat()
        with conn:
            for name, (header, _) in tables.items():
                if header:
                    conn.execute('INSERT OR IGNORE INTO protein_cache_header VALUES (?,?,?,?)', (tool, tkey, name, header))
            for name, (_, rows) in tables.items():
                conn.executemany('INSERT OR IGNORE INTO protein_cache VALUES (?,?,?,?,?,?)',
                                 [(h, tool, tkey, name, '\n'.join(rows.get(first[h], [])), now) for h in new])
        return len(new)
    finally:
        conn.close()


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[0] == 'key':
        print(key(argv[1], argv[2:]))
    elif len(argv) == 7 and argv[0] == 'split':
        print(*split(*argv[1:7]))
    elif len(argv) == 5 and argv[0] == 'merge':
        merge(argv[1], argv[2], argv[3], argv[4] == '1')
    elif len(argv) == 6 and argv[0] == 'store':
        print(store(*argv[1:6]))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
