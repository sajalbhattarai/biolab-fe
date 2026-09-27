#!/usr/bin/env python3
"""
dockerfile-to-def.py — convert this repo's Dockerfiles to apptainer .def files.

Handles the dialect actually used here:
  - multi-stage builds (FROM ... AS <name>) → apptainer Stage blocks
  - COPY --from=<stage>                     → %files from <stage>
  - ARG <NAME>[=default]                    → resolved inline by substituting
  - ENV KEY=val                              → %environment + %post export
  - RUN ...                                  → %post (with set -e)
  - ENTRYPOINT ["a","b"]                     → %runscript exec a b "$@"
  - LABEL k=v ...                            → %labels
  - WORKDIR / USER / EXPOSE                  → preserved as %post or comments
  - line continuations (trailing \)          → joined before parsing

Not handled (Docker-specific): RUN --mount, heredocs, ONBUILD, HEALTHCHECK,
multi-line LABEL with mixed quoting (best-effort), buildx-only features.

Usage:
  ./dockerfile-to-def.py <build_dir> [<build_dir> ...]
  ./dockerfile-to-def.py --all     # all tools under processing/containers/build
"""
from __future__ import annotations

import re
import shlex
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
BUILD_DIR = REPO_ROOT / "processing" / "containers" / "build"


def read_dockerfile(p: Path) -> list[str]:
    """Returns the Dockerfile as logical lines (continuations joined, comments and blanks dropped)."""
    raw = p.read_text().splitlines()
    out: list[str] = []
    buf = ""
    for line in raw:
        s = line.rstrip()
        if not s.strip() or s.lstrip().startswith("#"):
            if buf:
                continue
            continue
        if s.endswith("\\"):
            buf += s[:-1] + " "
            continue
        buf += s
        out.append(buf.strip())
        buf = ""
    if buf:
        out.append(buf.strip())
    return out


ARG_RE = re.compile(r"^ARG\s+([A-Z_][A-Z0-9_]*)(?:=(.*))?$", re.IGNORECASE)
FROM_RE = re.compile(r"^FROM\s+(?:--\S+\s+)*(\S+)(?:\s+AS\s+(\S+))?$", re.IGNORECASE)
COPY_RE = re.compile(r"^COPY(?:\s+--from=(\S+))?\s+(.+)$", re.IGNORECASE)
ADD_RE = re.compile(r"^ADD\s+(.+)$", re.IGNORECASE)
ENV_RE = re.compile(r"^ENV\s+(.+)$", re.IGNORECASE)
RUN_RE = re.compile(r"^RUN\s+(.+)$", re.IGNORECASE)
LABEL_RE = re.compile(r"^LABEL\s+(.+)$", re.IGNORECASE)
ENTRY_RE = re.compile(r"^ENTRYPOINT\s+(.+)$", re.IGNORECASE)
CMD_RE = re.compile(r"^CMD\s+(.+)$", re.IGNORECASE)
WORKDIR_RE = re.compile(r"^WORKDIR\s+(.+)$", re.IGNORECASE)
USER_RE = re.compile(r"^USER\s+(.+)$", re.IGNORECASE)
EXPOSE_RE = re.compile(r"^EXPOSE\s+(.+)$", re.IGNORECASE)


def substitute_args(text: str, args: dict[str, str]) -> str:
    """Replaces ${VAR} and $VAR with the known ARG defaults."""
    def repl(m: re.Match) -> str:
        name = m.group(1) or m.group(2)
        return args.get(name, m.group(0))
    text = re.sub(r"\$\{([A-Z_][A-Z0-9_]*)\}", repl, text)
    text = re.sub(r"\$([A-Z_][A-Z0-9_]*)", repl, text)
    return text


def parse_env(payload: str) -> list[tuple[str, str]]:
    """Parses `ENV KEY=val KEY2=val2` or `ENV KEY val`."""
    payload = payload.strip()
    if "=" not in payload.split()[0]:
        # Legacy `ENV KEY value` form.
        parts = payload.split(None, 1)
        return [(parts[0], parts[1] if len(parts) > 1 else "")]
    # `KEY=val KEY2="val with space"`, split with shlex.
    try:
        toks = shlex.split(payload, posix=True)
    except ValueError:
        toks = payload.split()
    out = []
    for t in toks:
        if "=" in t:
            k, _, v = t.partition("=")
            out.append((k, v))
    return out


def parse_label(payload: str) -> list[tuple[str, str]]:
    """Parses `LABEL k=v ...` into key/value pairs."""
    try:
        toks = shlex.split(payload, posix=True)
    except ValueError:
        toks = payload.split()
    out = []
    for t in toks:
        if "=" in t:
            k, _, v = t.partition("=")
            out.append((k, v))
    return out


def parse_json_array(payload: str) -> list[str] | None:
    """Parses the `["a","b"]` exec form; returns None for the shell form."""
    p = payload.strip()
    if not (p.startswith("[") and p.endswith("]")):
        return None
    import json
    try:
        arr = json.loads(p)
        if isinstance(arr, list) and all(isinstance(x, str) for x in arr):
            return arr
    except Exception:
        return None
    return None


class Stage:
    """One FROM stage, rendered as an Apptainer definition block."""
    def __init__(self, base: str, name: str | None):
        self.base = base
        self.name = name
        self.env: list[tuple[str, str]] = []
        self.post: list[str] = []           # plain shell lines for %post
        self.files: list[tuple[str, str, str | None]] = []  # (src, dst, from_stage)
        self.labels: list[tuple[str, str]] = []
        self.entrypoint: list[str] | str | None = None
        self.cmd: list[str] | str | None = None
        self.workdir: str | None = None

    def to_def(self, args: dict[str, str], is_final: bool) -> str:
        """Renders the stage as .def text (Bootstrap, %files, %environment, %post, %runscript, %labels)."""
        out: list[str] = []
        base = substitute_args(self.base, args)
        # "image:tag" becomes Bootstrap: docker, From: image:tag.
        if base.startswith("scratch"):
            out.append("Bootstrap: scratch")
        else:
            out.append("Bootstrap: docker")
            out.append(f"From: {base}")
        if self.name:
            out.append(f"Stage: {self.name}")
        out.append("")

        # %files for local files.
        local_files = [(s, d) for (s, d, fr) in self.files if fr is None]
        if local_files:
            out.append("%files")
            for s, d in local_files:
                out.append(f"    {s} {d}")
            out.append("")

        # %files from <stage>.
        from_groups: dict[str, list[tuple[str, str]]] = {}
        for s, d, fr in self.files:
            if fr is not None:
                from_groups.setdefault(fr, []).append((s, d))
        for stage_name, items in from_groups.items():
            out.append(f"%files from {stage_name}")
            for s, d in items:
                out.append(f"    {s} {d}")
            out.append("")

        if self.labels and is_final:
            out.append("%labels")
            for k, v in self.labels:
                out.append(f"    {k} {substitute_args(v, args)}")
            out.append("")

        if self.env and is_final:
            out.append("%environment")
            for k, v in self.env:
                out.append(f'    export {k}="{substitute_args(v, args)}"')
            out.append("")

        if self.post:
            out.append("%post")
            out.append("    set -eux")
            # ENV is also exported in %post so RUN steps see it, as in Docker.
            for k, v in self.env:
                out.append(f'    export {k}="{substitute_args(v, args)}"')
            if self.workdir:
                wd = substitute_args(self.workdir, args)
                out.append(f"    mkdir -p {wd}")
                out.append(f"    cd {wd}")
            for cmd in self.post:
                out.append(f"    {substitute_args(cmd, args)}")
            out.append("")

        if is_final and self.entrypoint is not None:
            out.append("%runscript")
            if isinstance(self.entrypoint, list):
                if self.cmd and isinstance(self.cmd, list):
                    argv = self.entrypoint + self.cmd
                else:
                    argv = self.entrypoint
                quoted = " ".join(shlex.quote(substitute_args(a, args)) for a in argv)
                out.append(f'    exec {quoted} "$@"')
            else:
                # Shell form.
                out.append(f"    exec {substitute_args(self.entrypoint, args)} \"$@\"")
            out.append("")

        return "\n".join(out)


def convert(dockerfile: Path) -> str:
    """Converts one Dockerfile into the text of an Apptainer .def file."""
    lines = read_dockerfile(dockerfile)
    args: dict[str, str] = {}  # global ARGs with defaults
    stages: list[Stage] = []
    cur: Stage | None = None

    for line in lines:
        m = ARG_RE.match(line)
        if m:
            name, default = m.group(1), m.group(2) or ""
            # Keeps the first default seen.
            if cur is None:
                args[name] = default.strip().strip('"').strip("'")
            else:
                # An ARG inside a stage re-declares the name and keeps the global default.
                if name not in args:
                    args[name] = default.strip().strip('"').strip("'") if default else ""
            continue

        m = FROM_RE.match(line)
        if m:
            base, stage_name = m.group(1), m.group(2)
            cur = Stage(base=base, name=stage_name)
            stages.append(cur)
            continue

        if cur is None:
            continue  # Global directives before the first FROM.

        m = COPY_RE.match(line)
        if m:
            from_stage = m.group(1)
            rest = shlex.split(m.group(2))
            if len(rest) < 2:
                continue
            *srcs, dst = rest
            for s in srcs:
                cur.files.append((s, dst, from_stage))
            continue

        m = ENV_RE.match(line)
        if m:
            cur.env.extend(parse_env(m.group(1)))
            continue

        m = LABEL_RE.match(line)
        if m:
            cur.labels.extend(parse_label(m.group(1)))
            continue

        m = WORKDIR_RE.match(line)
        if m:
            cur.workdir = m.group(1).strip()
            # Also changes directory in %post.
            cur.post.append(f"mkdir -p {cur.workdir} && cd {cur.workdir}")
            continue

        m = RUN_RE.match(line)
        if m:
            cmd = m.group(1).strip()
            arr = parse_json_array(cmd)
            if arr is not None:
                cmd = " ".join(shlex.quote(a) for a in arr)
            cur.post.append(cmd)
            continue

        m = ENTRY_RE.match(line)
        if m:
            payload = m.group(1).strip()
            arr = parse_json_array(payload)
            cur.entrypoint = arr if arr is not None else payload
            continue

        m = CMD_RE.match(line)
        if m:
            payload = m.group(1).strip()
            arr = parse_json_array(payload)
            cur.cmd = arr if arr is not None else payload
            continue

        m = USER_RE.match(line)
        if m:
            # Apptainer runs as the invoking user, so USER is kept only as a note.
            cur.post.append(f": # USER {m.group(1).strip()} (ignored — apptainer uses invoking user)")
            continue

        m = EXPOSE_RE.match(line)
        if m:
            # Informational only.
            continue

        # Unknown directives are kept as notes.
        cur.post.append(f": # unhandled: {line}")

    if not stages:
        raise SystemExit(f"no FROM in {dockerfile}")

    parts: list[str] = []
    header = [
        "# ──────────────────────────────────────────────────────────────────────────────",
        f"# Auto-generated from {dockerfile.relative_to(REPO_ROOT)} by",
        "# processing/scripts/setup-scripts/setup-containers/dockerfile-to-def.py",
        "# Hand-edit this file if the conversion needs tweaks; the build path",
        "# prefers apptainer.def over auto-generated output.",
        "# ──────────────────────────────────────────────────────────────────────────────",
        "",
    ]
    parts.append("\n".join(header))
    for i, st in enumerate(stages):
        parts.append(st.to_def(args, is_final=(i == len(stages) - 1)))
    return "\n".join(parts).rstrip() + "\n"


def main(argv: list[str]) -> int:
    """Converts the given build directories (or --all) and writes apptainer.def next to each Dockerfile."""
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    targets: list[Path] = []
    if argv[0] == "--all":
        targets = sorted(d for d in BUILD_DIR.iterdir() if d.is_dir() and (d / "Dockerfile").exists())
    else:
        for a in argv:
            p = Path(a).resolve()
            if p.is_dir():
                targets.append(p)
            elif p.name == "Dockerfile":
                targets.append(p.parent)
            else:
                print(f"skip {a}: not a build dir or Dockerfile", file=sys.stderr)

    rc = 0
    for d in targets:
        df = d / "Dockerfile"
        if not df.exists():
            print(f"skip {d.name}: no Dockerfile", file=sys.stderr)
            continue
        try:
            text = convert(df)
        except Exception as e:
            print(f"FAIL {d.name}: {e}", file=sys.stderr)
            rc = 1
            continue
        out = d / "apptainer.def"
        out.write_text(text)
        print(f"wrote {out.relative_to(REPO_ROOT)}")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
