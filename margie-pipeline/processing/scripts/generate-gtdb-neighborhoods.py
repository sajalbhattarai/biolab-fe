#!/usr/bin/env python3
# Draws a mini tree per GTDB-Tk query with its closest reference genomes (patristic
# distance on the classify tree, matplotlib) and writes stats plus a manifest.

import argparse
import csv
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Pattern, Set, Tuple

import matplotlib.pyplot as plt


@dataclass(eq=False)
class Node:
    name: str = ""
    length: float = 0.0
    children: List["Node"] = field(default_factory=list)
    parent: Optional["Node"] = None
    depth: float = 0.0
    x: float = 0.0
    y: float = 0.0

    @property
    def is_leaf(self) -> bool:
        return not self.children


def tokenize(newick: str) -> List[str]:
    tokens: List[str] = []
    current: List[str] = []
    in_quote = False
    for char in newick.strip():
        if char == "'":
            current.append(char)
            in_quote = not in_quote
            continue
        if not in_quote and char in "(),:;":
            if current:
                tokens.append("".join(current).strip())
                current = []
            tokens.append(char)
        else:
            current.append(char)
    if current:
        tokens.append("".join(current).strip())
    return [token for token in tokens if token != ""]


def parse_label(token: str) -> str:
    if token.startswith("'") and token.endswith("'") and len(token) >= 2:
        return token[1:-1]
    return token


def parse_newick(text: str) -> Node:
    tokens = tokenize(text)
    index = 0

    def parse_subtree() -> Node:
        nonlocal index
        if tokens[index] == "(":
            index += 1
            children: List[Node] = []
            while True:
                child = parse_subtree()
                children.append(child)
                if tokens[index] == ",":
                    index += 1
                    continue
                if tokens[index] == ")":
                    index += 1
                    break
            node = Node(children=children)
            for child in children:
                child.parent = node
            if index < len(tokens) and tokens[index] not in ",):;":
                node.name = parse_label(tokens[index])
                index += 1
            if index < len(tokens) and tokens[index] == ":":
                index += 1
                node.length = float(tokens[index]) if tokens[index] else 0.0
                index += 1
            return node

        node = Node(name=parse_label(tokens[index]))
        index += 1
        if index < len(tokens) and tokens[index] == ":":
            index += 1
            node.length = float(tokens[index]) if tokens[index] else 0.0
            index += 1
        return node

    tree = parse_subtree()
    if index < len(tokens) and tokens[index] == ";":
        index += 1
    if index != len(tokens):
        raise ValueError("Unparsed tokens remain in Newick input")
    tree.parent = None
    tree.length = 0.0
    assign_depths(tree, 0.0)
    return tree


def assign_depths(node: Node, depth: float) -> None:
    node.depth = depth
    for child in node.children:
        child.parent = node
        assign_depths(child, depth + child.length)


def gather_leaves(node: Node) -> List[Node]:
    if node.is_leaf:
        return [node]
    leaves: List[Node] = []
    for child in node.children:
        leaves.extend(gather_leaves(child))
    return leaves


def ancestors(node: Node) -> List[Node]:
    lineage: List[Node] = []
    current: Optional[Node] = node
    while current is not None:
        lineage.append(current)
        current = current.parent
    return lineage


def lca(nodes: List[Node]) -> Node:
    if not nodes:
        raise ValueError("Cannot compute LCA of empty node list")
    ancestor_sets = [set(ancestors(node)) for node in nodes[1:]]
    for candidate in ancestors(nodes[0]):
        if all(candidate in ancestor_set for ancestor_set in ancestor_sets):
            return candidate
    return ancestors(nodes[0])[-1]


def patristic_distance(left: Node, right: Node) -> float:
    common = lca([left, right])
    return left.depth + right.depth - (2.0 * common.depth)


def assign_plot_coordinates(node: Node, current_x: float, leaf_index: List[int]) -> None:
    node.x = current_x
    if node.is_leaf:
        node.y = float(leaf_index[0])
        leaf_index[0] += 1
        return
    for child in node.children:
        assign_plot_coordinates(child, current_x + child.length, leaf_index)
    node.y = sum(child.y for child in node.children) / len(node.children)


def clone_pruned_subtree(node: Node, selected: Set[Node]) -> Optional[Node]:
    if node.is_leaf:
        if node in selected:
            return Node(name=node.name, length=node.length)
        return None

    cloned_children: List[Node] = []
    for child in node.children:
        cloned = clone_pruned_subtree(child, selected)
        if cloned is not None:
            cloned.parent = None
            cloned_children.append(cloned)
    if not cloned_children:
        return None

    cloned_node = Node(name=node.name, length=node.length, children=cloned_children)
    for child in cloned_children:
        child.parent = cloned_node
    return cloned_node


def collapse_unary(node: Node) -> Node:
    collapsed_children = [collapse_unary(child) for child in node.children]
    node.children = collapsed_children
    for child in node.children:
        child.parent = node
    if len(node.children) == 1 and node.parent is not None and not node.name:
        child = node.children[0]
        child.length += node.length
        child.parent = node.parent
        return child
    return node


def draw_tree(ax, node: Node, query_pattern: Pattern[str], neighbor_labels: Set[str], taxonomy_lookup: Dict[str, str], ani_lookup: Dict[str, Tuple[str, str]] = None) -> None:
    for child in node.children:
        ax.plot([node.x, child.x], [child.y, child.y], color="0.25", linewidth=0.8)
        ax.plot([node.x, node.x], [node.y, child.y], color="0.25", linewidth=0.8)
        draw_tree(ax, child, query_pattern, neighbor_labels, taxonomy_lookup, ani_lookup)

    if not node.is_leaf:
        return

    if query_pattern.search(node.name):
        color = "#c0392b"
        weight = "bold"
        ax.scatter([node.x], [node.y], color=color, s=18, zorder=3)
    elif node.name in neighbor_labels:
        color = "#1f77b4"
        weight = "normal"
        ax.scatter([node.x], [node.y], color=color, s=12, zorder=3)
        # Draw ANI/AF on the branch leading to this reference leaf
        acc = normalize_reference_label(node.name)
        ani_entry = (ani_lookup or {}).get(node.name) or (ani_lookup or {}).get(acc)
        ani_val, af_val = ani_entry if ani_entry else ("N/A", "N/A")
        # Midpoint of the horizontal branch from parent to this leaf
        if node.parent is not None:
            mid_x = (node.parent.x + node.x) / 2.0
            ax.text(mid_x, node.y + 0.25, f"ANI={ani_val}%\nAF={af_val}",
                    ha="center", va="bottom", fontsize=4.5, color="#1f77b4",
                    fontstyle="italic", zorder=4)
    else:
        color = "0.15"
        weight = "normal"

    # Show species name from lookup, then tree topology, then accession only
    species = (taxonomy_lookup.get(node.name)
               or taxonomy_lookup.get(normalize_reference_label(node.name))
               or infer_species_from_tree(node))
    display_label = f"{normalize_reference_label(node.name)}  {species}" if species else node.name
    ax.text(node.x + 0.002, node.y, display_label, va="center", ha="left", fontsize=6, color=color, fontweight=weight)


def normalize_reference_label(label: str) -> str:
    return re.sub(r"^(GB_|RS_)", "", label)


def build_gtdb_taxonomy_lookup(taxonomy_tsv: Optional[Path]) -> Dict[str, str]:
    """Build accession (no GB_/RS_ prefix) -> species name from the GTDB taxonomy file.
    Also builds a no-prefix variant for matching against GTDB summary fields."""
    lookup: Dict[str, str] = {}
    if taxonomy_tsv is None or not taxonomy_tsv.exists():
        return lookup
    with taxonomy_tsv.open() as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            raw_acc = parts[0].strip()
            taxonomy = parts[1].strip()
            species = ""
            for part in taxonomy.split(";"):
                if part.startswith("s__") and part[3:]:
                    species = part[3:]
                    break
            if not species:
                for part in reversed(taxonomy.split(";")):
                    part = part.strip()
                    if part and not part.endswith("__"):
                        species = part.split("__", 1)[-1] if "__" in part else part
                        break
            # Store both raw (RS_GCF_xxx) and stripped (GCF_xxx) forms
            lookup[raw_acc] = species
            stripped = re.sub(r"^(GB_|RS_)", "", raw_acc)
            lookup[stripped] = species
    return lookup


def taxon_from_node_name(name: str) -> str:
    """Extract lowest-rank taxonomy string from a GTDB internal node label.
    Labels look like '100.0:g__Aliivibrio' or '100.0:f__Vibrionaceae;g__Aliivibrio'.
    Returns the species or genus name (without rank prefix) for the lowest rank found."""
    if not name:
        return ""
    # Strip bootstrap prefix (e.g. '100.0:' or '95.0:')
    clean = re.sub(r'^[\d.]+:', '', name)
    # Prefer species > genus > family > order > class > phylum
    for prefix in ("s__", "g__", "f__", "o__", "c__", "p__"):
        # May have multiple ranks separated by ;
        for part in clean.split(";"):
            part = part.strip()
            if part.startswith(prefix):
                value = part[len(prefix):].strip()
                if value:
                    return value
    return ""


def infer_species_from_tree(leaf: Node) -> str:
    """Walk up from a reference leaf to find the nearest ancestor with a GTDB taxonomy label."""
    current: Optional[Node] = leaf.parent
    while current is not None:
        name = taxon_from_node_name(current.name)
        if name:
            return name
        current = current.parent
    return ""


def parse_related_refs(value: str) -> Dict[str, Dict[str, str]]:
    if not value or value == "N/A":
        return {}
    related: Dict[str, Dict[str, str]] = {}
    for entry in value.split(";"):
        parts = [part.strip() for part in entry.split(",")]
        if len(parts) < 5:
            continue
        accession, species_name, radius, ani, af = parts[:5]
        related[accession] = {
            "species_name": species_name,
            "radius": radius,
            "ani": ani,
            "af": af,
        }
    return related


def species_from_taxonomy(taxonomy: str) -> str:
    if not taxonomy or taxonomy == "N/A":
        return ""
    parts = taxonomy.split(";")
    for part in reversed(parts):
        if part.startswith("s__"):
            return part[3:]
    return ""


def safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", value)


def find_query_leaf(leaves_by_name: Dict[str, Node], query_name: str) -> Optional[Node]:
    candidates = [query_name]
    if not query_name.startswith("user-input_"):
        candidates.append(f"user-input_{query_name}")
    for candidate in candidates:
        if candidate in leaves_by_name:
            return leaves_by_name[candidate]
    return None


def render_neighborhood(query_leaf: Node, neighbors: List[Tuple[Node, float]], title: str, output_path: Path, taxonomy_lookup: Dict[str, str], classification_method: str = "", ani_lookup: Dict[str, Tuple[str, str]] = None) -> None:
    selected_nodes = [query_leaf] + [neighbor for neighbor, _ in neighbors]
    root = lca(selected_nodes)
    pruned = clone_pruned_subtree(root, set(selected_nodes))
    if pruned is None:
        raise ValueError(f"Failed to prune subtree for {query_leaf.name}")
    pruned.length = 0.0
    pruned.parent = None
    pruned = collapse_unary(pruned)
    assign_plot_coordinates(pruned, 0.0, [0])

    leaves = gather_leaves(pruned)
    width = max(14.0, min(28.0, max(14.0, max(leaf.x for leaf in leaves) * 6.0 + 10.0)))
    height = max(4.5, len(leaves) * 0.55 + 1.5)
    fig, ax = plt.subplots(figsize=(width, height))
    draw_tree(ax, pruned, re.compile(rf"^{re.escape(query_leaf.name)}$"), {neighbor.name for neighbor, _ in neighbors}, taxonomy_lookup, ani_lookup)
    ax.set_title(title, fontsize=10, fontweight="bold")

    # Subtitle explaining tree structure vs taxonomy labeling distinction
    tree_basis = "Tree structure: marker-gene alignment + pplacer phylogenetic placement (bac120/ar53)"
    if classification_method == "ani_screen":
        tax_basis = "Taxonomy label: ANI screen (GTDB short-circuit — no alignment taxonomy available)"
        tax_color = "#e67e22"
    elif classification_method and classification_method != "N/A":
        tax_basis = f"Taxonomy label: tree topology / {classification_method}"
        tax_color = "#27ae60"
    else:
        tax_basis = "Taxonomy label: tree topology (alignment-based placement)"
        tax_color = "#27ae60"
    fig.text(0.5, 0.005, tree_basis, ha="center", va="bottom", fontsize=6, color="0.4", style="italic")
    fig.text(0.5, 0.018, tax_basis, ha="center", va="bottom", fontsize=6.5, color=tax_color, fontweight="bold")
    fig.text(
        0.5,
        0.031,
        "ANI/AF label note: N/A means GTDB did not compute pairwise ANI/AF for that tree-nearest reference.",
        ha="center",
        va="bottom",
        fontsize=6,
        color="#1f77b4",
    )

    # Legend
    from matplotlib.lines import Line2D
    legend_elements = [
        Line2D([0], [0], marker="o", color="w", markerfacecolor="#c0392b", markersize=7, label="Query genome"),
        Line2D([0], [0], marker="o", color="w", markerfacecolor="#1f77b4", markersize=6, label="Closest reference genomes"),
    ]
    ax.legend(handles=legend_elements, loc="lower right", fontsize=7, framealpha=0.7)

    ax.set_xlabel("Patristic branch length (marker-gene alignment)")
    ax.set_yticks([])
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_visible(False)
    ax.margins(x=0.02, y=0.03)
    plt.tight_layout(rect=[0, 0.03, 1, 1])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)


def write_stats(query_leaf: Node, query_row: Dict[str, str], neighbors: List[Tuple[Node, float]], output_path: Path, taxonomy_lookup: Dict[str, str]) -> Dict[str, Tuple[str, str]]:
    """Write stats TSV and return a per-accession ANI/AF lookup for figure annotation."""
    related_refs = parse_related_refs(query_row.get("other_related_references(genome_id,species_name,radius,ANI,AF)", ""))
    # Build ANI lookup: accession (raw and stripped) -> (ani, af)
    # Include closest_genome and closest_placement references
    ani_lookup: Dict[str, Tuple[str, str]] = {}
    cgr = query_row.get("closest_genome_reference", "")
    cgani = query_row.get("closest_genome_ani", "")
    cgaf = query_row.get("closest_genome_af", "")
    if cgr and cgr not in ("N/A", "") and cgani not in ("N/A", ""):
        ani_lookup[cgr] = (cgani, cgaf)
        ani_lookup[re.sub(r"^(GB_|RS_)", "", cgr)] = (cgani, cgaf)
    cpr = query_row.get("closest_placement_reference", "")
    cpani = query_row.get("closest_placement_ani", "")
    cpaf = query_row.get("closest_placement_af", "")
    if cpr and cpr not in ("N/A", "") and cpani not in ("N/A", ""):
        ani_lookup[cpr] = (cpani, cpaf)
        ani_lookup[re.sub(r"^(GB_|RS_)", "", cpr)] = (cpani, cpaf)
    for acc, ref in related_refs.items():
        ani_val = ref.get("ani", "")
        af_val = ref.get("af", "")
        if ani_val and ani_val not in ("N/A", ""):
            ani_lookup[acc] = (ani_val, af_val)

    closest_genome_ref = query_row.get("closest_genome_reference", "")
    closest_placement_ref = query_row.get("closest_placement_reference", "")
    closest_genome_taxonomy = query_row.get("closest_genome_taxonomy", "")
    closest_placement_taxonomy = query_row.get("closest_placement_taxonomy", "")
    selected_taxonomy = query_row.get("pplacer_taxonomy")
    if not selected_taxonomy or selected_taxonomy == "N/A":
        selected_taxonomy = query_row.get("classification", "")

    fieldnames = [
        "query_leaf",
        "query_classification_method",
        "query_selected_taxonomy",
        "query_msa_percent",
        "query_red_value",
        "neighbor_rank",
        "neighbor_leaf",
        "neighbor_accession",
        "neighbor_tree_distance",
        "neighbor_tree_depth",
        "neighbor_species_name",
        "neighbor_radius",
        "neighbor_ani",
        "neighbor_af",
        "neighbor_ani_status",
        "neighbor_ani_note",
        "is_closest_genome_reference",
        "is_closest_placement_reference",
        "closest_genome_species_name",
        "closest_placement_species_name",
    ]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        for rank, (neighbor, distance) in enumerate(neighbors, start=1):
            accession = normalize_reference_label(neighbor.name)
            related = related_refs.get(accession, {})
            ani_raw = related.get("ani", "")
            af_raw = related.get("af", "")
            ani_value = ani_raw or "N/A"
            af_value = af_raw or "N/A"
            ani_computed = ani_value != "N/A"
            # Priority: 1) GTDB taxonomy file (full 200K lookup), 2) ANI-related refs, 3) tree topology
            species_name = (
                taxonomy_lookup.get(neighbor.name)
                or taxonomy_lookup.get(accession)
                or related.get("species_name", "")
                or infer_species_from_tree(neighbor)
            )
            writer.writerow(
                {
                    "query_leaf": query_leaf.name,
                    "query_classification_method": query_row.get("classification_method", ""),
                    "query_selected_taxonomy": selected_taxonomy,
                    "query_msa_percent": query_row.get("msa_percent", "") or "N/A",
                    "query_red_value": query_row.get("red_value", "") or "N/A",
                    "neighbor_rank": rank,
                    "neighbor_leaf": neighbor.name,
                    "neighbor_accession": accession,
                    "neighbor_tree_distance": f"{distance:.6f}",
                    "neighbor_tree_depth": f"{neighbor.depth:.6f}",
                    "neighbor_species_name": species_name,
                    "neighbor_radius": related.get("radius", "") or "N/A",
                    "neighbor_ani": ani_value,
                    "neighbor_af": af_value,
                    "neighbor_ani_status": "computed" if ani_computed else "not_computed",
                    "neighbor_ani_note": (
                        "GTDB provided ANI/AF for this neighbor."
                        if ani_computed
                        else "N/A means this tree-nearest neighbor was not part of GTDB ANI comparisons."
                    ),
                    "is_closest_genome_reference": "yes" if accession == closest_genome_ref else "no",
                    "is_closest_placement_reference": "yes" if accession == closest_placement_ref else "no",
                    "closest_genome_species_name": species_from_taxonomy(closest_genome_taxonomy),
                    "closest_placement_species_name": species_from_taxonomy(closest_placement_taxonomy),
                }
            )
    return ani_lookup


def process_domain(summary_path: Path, tree_path: Path, output_root: Path, domain_label: str, top_n: int, manifest_rows: List[Dict[str, str]], taxonomy_lookup: Dict[str, str]) -> None:
    if not summary_path.exists() or not tree_path.exists():
        return

    tree = parse_newick(tree_path.read_text().strip())
    leaves = gather_leaves(tree)
    leaves_by_name = {leaf.name: leaf for leaf in leaves}
    reference_leaves = [leaf for leaf in leaves if not leaf.name.startswith("user-input_")]

    with summary_path.open() as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            query_name = row.get("user_genome", "")
            if not query_name:
                continue
            query_leaf = find_query_leaf(leaves_by_name, query_name)
            if query_leaf is None:
                continue

            ranked_neighbors = sorted(
                ((leaf, patristic_distance(query_leaf, leaf)) for leaf in reference_leaves),
                key=lambda item: item[1],
            )[:top_n]

            n = len(ranked_neighbors)
            query_dir = output_root / safe_name(query_leaf.name)
            svg_path = query_dir / f"closest{n}.tree.svg"
            png_path = query_dir / f"closest{n}.tree.png"
            stats_path = query_dir / f"closest{n}.stats.tsv"
            classification_method = row.get("classification_method", "")
            title = f"{query_leaf.name} — closest {n} GTDB references"
            ani_lookup = write_stats(query_leaf, row, ranked_neighbors, stats_path, taxonomy_lookup)
            render_neighborhood(query_leaf, ranked_neighbors, title, svg_path, taxonomy_lookup, classification_method, ani_lookup)
            render_neighborhood(query_leaf, ranked_neighbors, title, png_path, taxonomy_lookup, classification_method, ani_lookup)

            manifest_rows.append(
                {
                    "query_leaf": query_leaf.name,
                    "domain": domain_label,
                    "classification_method": row.get("classification_method", ""),
                    "tree_file": str(tree_path),
                    "svg_file": str(svg_path),
                    "png_file": str(png_path),
                    "stats_file": str(stats_path),
                }
            )


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate per-query GTDB mini trees with the closest reference organisms.")
    parser.add_argument("--bac-summary", default="output/gtdbtk/gtdbtk/raw/gtdbtk.bac120.summary.tsv")
    parser.add_argument("--arc-summary", default="output/gtdbtk/gtdbtk/raw/gtdbtk.ar53.summary.tsv")
    parser.add_argument("--bac-tree", default="output/gtdbtk/gtdbtk/raw/classify/gtdbtk.backbone.bac120.classify.tree")
    parser.add_argument("--arc-tree", default="output/gtdbtk/gtdbtk/raw/classify/gtdbtk.ar53.classify.tree")
    parser.add_argument("--output-dir", default="output/gtdbtk/gtdbtk/processed/neighborhoods")
    parser.add_argument("--taxonomy-tsv", default="db/gtdbtk/release232/taxonomy/gtdb_taxonomy.tsv",
                        help="GTDB taxonomy file mapping accessions to full lineage (used for species name lookup)")
    parser.add_argument("--top-n", type=int, default=20)
    args = parser.parse_args()

    taxonomy_lookup = build_gtdb_taxonomy_lookup(Path(args.taxonomy_tsv))
    print(f"[neighborhoods] Loaded {len(taxonomy_lookup)} accession→species entries from GTDB taxonomy file.")

    output_root = Path(args.output_dir)
    manifest_rows: List[Dict[str, str]] = []
    process_domain(Path(args.bac_summary), Path(args.bac_tree), output_root, "Bacteria", args.top_n, manifest_rows, taxonomy_lookup)
    process_domain(Path(args.arc_summary), Path(args.arc_tree), output_root, "Archaea", args.top_n, manifest_rows, taxonomy_lookup)

    manifest_path = output_root / "manifest.tsv"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["query_leaf", "domain", "classification_method", "tree_file", "svg_file", "png_file", "stats_file"],
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerows(manifest_rows)


if __name__ == "__main__":
    main()
