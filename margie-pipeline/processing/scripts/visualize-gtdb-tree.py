#!/usr/bin/env python3
# Renders a Newick tree as an SVG/PNG with matplotlib, highlighting leaves that
# match the given regexes.

import argparse
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Pattern

import matplotlib.pyplot as plt


@dataclass
class Node:
    name: str = ""
    length: float = 0.0
    children: List["Node"] = field(default_factory=list)
    x: float = 0.0
    y: float = 0.0

    @property
    def is_leaf(self) -> bool:
        return not self.children


def tokenize(newick: str):
    tokens = []
    current = []
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
            children = []
            while True:
                children.append(parse_subtree())
                if tokens[index] == ",":
                    index += 1
                    continue
                if tokens[index] == ")":
                    index += 1
                    break
            node = Node(children=children)
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
    return tree


def assign_coordinates(node: Node, current_x: float, leaf_index: List[int]) -> None:
    node.x = current_x
    if node.is_leaf:
        node.y = float(leaf_index[0])
        leaf_index[0] += 1
        return

    for child in node.children:
        assign_coordinates(child, current_x + child.length, leaf_index)
    node.y = sum(child.y for child in node.children) / len(node.children)


def gather_leaves(node: Node) -> List[Node]:
    if node.is_leaf:
        return [node]
    leaves = []
    for child in node.children:
        leaves.extend(gather_leaves(child))
    return leaves


def draw_tree(ax, node: Node, highlight_patterns: List[Pattern], show_all_labels: bool, max_labels: int, total_leaves: int) -> None:
    for child in node.children:
        ax.plot([node.x, child.x], [child.y, child.y], color="0.2", linewidth=0.6)
        ax.plot([node.x, node.x], [node.y, child.y], color="0.2", linewidth=0.6)
        draw_tree(ax, child, highlight_patterns, show_all_labels, max_labels, total_leaves)

    if not node.is_leaf:
        return

    is_highlight = any(pattern.search(node.name) for pattern in highlight_patterns)
    if is_highlight:
        ax.scatter([node.x], [node.y], color="#c0392b", s=10, zorder=3)

    should_label = is_highlight or show_all_labels or total_leaves <= max_labels
    if should_label:
        color = "#c0392b" if is_highlight else "0.1"
        fontweight = "bold" if is_highlight else "normal"
        ax.text(node.x + 0.01, node.y, node.name, va="center", ha="left", fontsize=5, color=color, fontweight=fontweight)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render a GTDB Newick tree as SVG or PNG.")
    parser.add_argument("tree", help="Input Newick tree file")
    parser.add_argument("output", help="Output image path (.svg or .png)")
    parser.add_argument("--highlight", action="append", default=[], help="Regex pattern for leaf labels to highlight; may be used multiple times")
    parser.add_argument("--show-all-labels", action="store_true", help="Always render all leaf labels")
    parser.add_argument("--max-labels", type=int, default=80, help="Automatically render all labels only when leaf count is <= this value")
    args = parser.parse_args()

    tree_text = Path(args.tree).read_text().strip()
    tree = parse_newick(tree_text)
    assign_coordinates(tree, tree.length, [0])
    leaves = gather_leaves(tree)

    width = max(12.0, min(42.0, max(12.0, tree.x * 4.0 + 8.0)))
    height = max(6.0, min(60.0, len(leaves) * 0.12 + 2.0))

    fig, ax = plt.subplots(figsize=(width, height))
    patterns = [re.compile(pattern) for pattern in args.highlight]
    draw_tree(ax, tree, patterns, args.show_all_labels, args.max_labels, len(leaves))

    ax.set_title(f"GTDB tree: {Path(args.tree).name}", fontsize=10)
    ax.set_xlabel("Branch length")
    ax.set_ylabel("Leaves")
    ax.set_yticks([])
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_visible(False)
    ax.margins(x=0.02, y=0.01)
    plt.tight_layout()

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    main()