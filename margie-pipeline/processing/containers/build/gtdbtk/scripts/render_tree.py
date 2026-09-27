#!/usr/bin/env python3
# render_tree.py — render Newick trees to PNG/SVG (full tree or per-genome pruned)
import argparse
import copy
import sys
from pathlib import Path

try:
    from Bio import Phylo
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError as e:
    print(f"[render_tree] ERROR: missing dependency: {e}", file=sys.stderr)
    sys.exit(1)

# =============================================================================
# Helpers
# =============================================================================

def shorten_label(name: str, maxlen: int = 55) -> str:
    if not name:
        return name
    for prefix in ("GB_", "RS_"):
        if name.startswith(prefix):
            name = name[len(prefix):]
    return name if len(name) <= maxlen else name[:maxlen - 3] + "..."


def save_figure(fig, prefix: str):
    for ext in ("png", "svg"):
        out = f"{prefix}.{ext}"
        fig.savefig(out, dpi=150, bbox_inches="tight")
        print(f"[render_tree] wrote {out}")


# =============================================================================
# Full tree
# =============================================================================

def render_full(tree, title: str, out_prefix: str, width: float, height: float):
    for clade in tree.find_clades():
        if clade.name:
            clade.name = shorten_label(clade.name)
    fig, ax = plt.subplots(figsize=(width, height))
    Phylo.draw(tree, axes=ax, do_show=False)
    ax.set_title(title, fontsize=10, pad=8)
    plt.tight_layout()
    save_figure(fig, out_prefix)
    plt.close(fig)


# =============================================================================
# Per-genome pruned tree
# =============================================================================

def patristic_distances(tree, query_name: str) -> dict:
    # O(n) per query via Bio.Phylo.distance(); called once per genome so acceptable
    for clade in tree.find_clades():
        if clade.is_terminal() and clade.name == query_name:
            break
    else:
        return {}
    return {
        tip.name: tree.distance(query_name, tip.name)
        for tip in tree.get_terminals()
        if tip.name != query_name
    }


def prune_to_neighbourhood(tree, query_name: str, top_n: int):
    t = copy.deepcopy(tree)
    dists = patristic_distances(t, query_name)
    if not dists:
        return t
    keep = set(sorted(dists, key=dists.get)[:top_n]) | {query_name}
    for name in [tip.name for tip in t.get_terminals() if tip.name not in keep]:
        try:
            t.prune(name)
        except Exception:
            pass
    return t


def render_per_query(tree_path: str, out_dir: str, query_names: list,
                     top_n: int, width: float, height: float):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    tree = Phylo.read(str(tree_path), "newick")
    tree_stem = Path(tree_path).stem
    rendered = 0

    for qname in query_names:
        pruned = prune_to_neighbourhood(tree, qname, top_n)
        tips = pruned.get_terminals()
        if len(tips) < 2:
            print(f"[render_tree] WARNING: too few tips for '{qname}', skipping", file=sys.stderr)
            continue

        for clade in pruned.find_clades():
            if clade.name and clade.name != qname:
                clade.name = shorten_label(clade.name)

        safe = qname.replace("/", "_").replace(" ", "_")
        organism_dir = out_dir / safe
        organism_dir.mkdir(parents=True, exist_ok=True)

        fig, ax = plt.subplots(figsize=(width, max(height, len(tips) * 0.35)))
        Phylo.draw(pruned, axes=ax, do_show=False)
        ax.set_title(f"{shorten_label(qname)} — top {top_n} neighbours\n({tree_stem})",
                     fontsize=9, pad=8)
        plt.tight_layout()
        save_figure(fig, str(organism_dir / f"top{top_n}"))
        plt.close(fig)
        rendered += 1

    print(f"[render_tree] rendered {rendered} per-query tree image(s) (top-{top_n})")
    return rendered


# =============================================================================
# Entry point
# =============================================================================

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tree", help="Newick tree file")
    ap.add_argument("out",  help="Output prefix (full mode) or directory (per-query mode)")
    ap.add_argument("--query-names", nargs="+", metavar="NAME",
                    help="Query genome names — activates per-query mode")
    ap.add_argument("--top-n",  type=int,   default=20,
                    help="Closest neighbours per query (default: 20)")
    ap.add_argument("--width",  type=float, default=20)
    ap.add_argument("--height", type=float, default=14)
    args = ap.parse_args()

    tree_path = Path(args.tree)
    if not tree_path.exists():
        print(f"[render_tree] ERROR: tree file not found: {tree_path}", file=sys.stderr)
        sys.exit(1)

    if args.query_names:
        render_per_query(str(tree_path), args.out, args.query_names,
                         args.top_n, args.width, args.height)
    else:
        render_full(Phylo.read(str(tree_path), "newick"),
                    tree_path.stem, args.out, args.width, args.height)


if __name__ == "__main__":
    main()
