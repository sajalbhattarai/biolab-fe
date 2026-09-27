#!/usr/bin/env python3
"""A tool's results, kept under the hash of the genome they came from.

The same scheme margie-backend uses (workflow_tools/output_cache.py): the
first 16 hex characters of the SHA-256 of the input FASTA key every file a
tool wrote, in one SQLite file. Run the same genome again — under any name,
in any folder — and its finished tools are restored instead of recomputed.
Copy the .db file and the cache travels with it.

A genome's key is its sequence hash (genome_hash, as the backend's
genome_identity.py): the record ids and bases, whatever the file's line
width, case or line endings. Entries written before are keyed by the file's
byte hash (file_hash); they are still found, and new ones use the first.

Where it differs from the backend: the backend stores single files by their
base name, and this stores a tool's whole output folder, so `filename` is the
path relative to that folder. Nothing but the standard library is used, so it
runs with any Python 3.8+.

    result_cache.py has   <db> <fasta> <tool>          -> exit 0 if cached
    result_cache.py get   <db> <fasta> <tool> <dir>    -> restore into <dir>
    result_cache.py put   <db> <fasta> <tool> <dir>    -> store <dir>
    result_cache.py tools <db> <fasta>                 -> list cached tools
"""
from __future__ import annotations

import hashlib
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

CREATE_OUTPUT_CACHE_SQL = """
CREATE TABLE IF NOT EXISTS output_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    input_hash TEXT NOT NULL,
    tool TEXT NOT NULL,
    filename TEXT NOT NULL,
    content BLOB NOT NULL,
    size_bytes INTEGER NOT NULL,
    cached_at TEXT NOT NULL,
    UNIQUE(input_hash, tool, filename)
);
"""

# Anything bigger than this is left on disk rather than put in the database.
MAX_FILE_BYTES = 512 * 1024 * 1024


def file_hash(path: str) -> str:
    """Returns the first 16 hex characters of the SHA-256 of *path* (legacy key)."""
    sha256 = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(8192), b""):
            sha256.update(chunk)
    return sha256.hexdigest()[:16]


def genome_hash(path: str) -> str:
    """Returns a SHA-256 of the record ids and upper-case bases, independent of line
    width, case and line endings."""
    import gzip
    sha256 = hashlib.sha256()
    opener = gzip.open if str(path).endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith(">"):
                words = line[1:].split()
                sha256.update(b">" + (words[0] if words else "").encode() + b"\n")
            else:
                seq = "".join(line.split()).upper()
                if seq:
                    sha256.update(seq.encode())
    return "fa1:" + sha256.hexdigest()


def _keys(fasta: str) -> tuple[str, str]:
    """Returns (key for new entries, legacy key still looked up)."""
    return genome_hash(fasta), file_hash(fasta)


def _connect(db_path: str, timeout: float = 30.0) -> sqlite3.Connection:
    """Returns a connection that waits for locks, which network filesystems need."""
    path = Path(db_path).expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path), timeout=timeout)
    conn.execute(f"PRAGMA busy_timeout={int(timeout * 1000)}")
    return conn


def _ensure(conn: sqlite3.Connection) -> None:
    conn.execute(CREATE_OUTPUT_CACHE_SQL)


def cached_tools(db_path: str, fasta: str) -> set[str]:
    """Returns the tools with results for this genome; never raises."""
    try:
        if not Path(db_path).expanduser().exists():
            return set()
        conn = _connect(db_path)
        try:
            _ensure(conn)
            rows = conn.execute(
                "SELECT DISTINCT tool FROM output_cache WHERE input_hash IN (?, ?)",
                _keys(fasta),
            ).fetchall()
        finally:
            conn.close()
        return {r[0] for r in rows}
    except Exception:
        return set()


def restore(db_path: str, fasta: str, tool: str, dest: str) -> int:
    """Writes this tool's cached files into *dest* and returns how many it wrote."""
    if not Path(db_path).expanduser().exists():
        return 0
    conn = _connect(db_path)
    try:
        _ensure(conn)
        rows = []
        for key in _keys(fasta):
            rows = conn.execute(
                "SELECT filename, content FROM output_cache WHERE input_hash = ? AND tool = ?",
                (key, tool),
            ).fetchall()
            if rows:
                break
    finally:
        conn.close()
    if not rows:
        return 0
    root = Path(dest)
    for name, content in rows:
        out = root / name
        # A stored path is always relative and inside dest; refuse anything else.
        if not str(out.resolve()).startswith(str(root.resolve())):
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(content)
    return len(rows)


def store(db_path: str, fasta: str, tool: str, src: str) -> int:
    """Stores every file under *src* and returns how many it stored."""
    root = Path(src)
    if not root.is_dir():
        return 0
    files = [p for p in sorted(root.rglob("*")) if p.is_file() and p.stat().st_size <= MAX_FILE_BYTES]
    if not files:
        return 0
    now = datetime.now(timezone.utc).isoformat()
    digest = genome_hash(fasta)
    conn = _connect(db_path)
    try:
        _ensure(conn)
        for p in files:
            blob = p.read_bytes()
            conn.execute(
                "INSERT OR REPLACE INTO output_cache "
                "(input_hash, tool, filename, content, size_bytes, cached_at) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (digest, tool, str(p.relative_to(root)), blob, len(blob), now),
            )
        conn.commit()
    finally:
        conn.close()
    return len(files)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    action = argv[1]
    try:
        if action == "has" and len(argv) == 5:
            return 0 if argv[4] in cached_tools(argv[2], argv[3]) else 1
        if action == "tools" and len(argv) == 4:
            for t in sorted(cached_tools(argv[2], argv[3])):
                print(t)
            return 0
        if action == "get" and len(argv) == 6:
            n = restore(argv[2], argv[3], argv[4], argv[5])
            print(n)
            return 0 if n else 1
        if action == "put" and len(argv) == 6:
            print(store(argv[2], argv[3], argv[4], argv[5]))
            return 0
    except Exception as exc:  # a cache must never stop a run
        print(f"result_cache: {exc}", file=sys.stderr)
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
