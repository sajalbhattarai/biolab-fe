/** Helpers for the table viewer: colours, number formatting, saved layouts. */

import { TIER_NAMES } from '../vision';

export type ColumnKind = 'number' | 'category' | 'sequence' | 'text' | 'empty';

export interface ColumnInfo {
	name: string;
	kind: ColumnKind;
	min?: number;
	max?: number;
	values?: string[];
	width?: number;
}

export interface CellStyle {
	bg?: string;
	fg?: string;
	bold?: boolean;
	border?: string;
}

/** "Column-AS: CONFIDENCE_TIER" -> "CONFIDENCE_TIER". */
export const plainName = (c: string) => c.replace(/^(?:\[[A-Z]+\]-|Column-[A-Z]+:\s*)/i, '');

const EMPTY = new Set(['', '-', 'na', 'n/a', 'nan', 'none', 'null']);
export const isEmpty = (v: string | undefined) => EMPTY.has((v ?? '').trim().toLowerCase());

/** Confidence tier colours, drawn through --mg-tier-* so palettes and the theme editor apply. */
export const TIER_COLOURS: Record<string, string> = Object.fromEntries(TIER_NAMES.map((t, i) => [t, `var(--mg-tier-${i})`]));

/** Returns a category value's colour: fixed for tiers and yes/no, else cycling through `count` hues. */
export function categoryColour(value: string, col: ColumnInfo, count = 12): string {
	const v = value.trim().toLowerCase();
	if (TIER_COLOURS[v]) return TIER_COLOURS[v];
	if (['yes', 'true', 'y', '+'].includes(v) && col.values?.length === 2) return 'var(--mg-yes)';
	if (['no', 'false', 'n'].includes(v) && col.values?.length === 2) return 'var(--mg-no)';
	const i = col.values?.indexOf(value.trim()) ?? -1;
	return `var(--mg-cat-${(i < 0 ? 0 : i) % count})`;
}

/** Background and text colours for a chip or a tinted cell of `colour`. */
export const tint = (colour: string, amount = 18) => `color-mix(in srgb, ${colour} ${amount}%, var(--mg-surface))`;
/** The colour held to a lightness that reads on its tint. */
export const ink = (colour: string) => `oklch(from ${colour} clamp(var(--mg-ink-lo), l, var(--mg-ink-hi)) c h)`;

/** Formats numbers for reading (579,224, 0.1235); the exact value stays in the tooltip. */
export function formatNumber(v: string): string {
	const n = Number(v);
	if (!Number.isFinite(n) || !v.trim()) return v;
	if (Number.isInteger(n)) return Math.abs(n) >= 10000 ? n.toLocaleString('en-US') : v.trim();
	return n.toLocaleString('en-US', { maximumFractionDigits: Math.abs(n) < 1 ? 4 : 2, useGrouping: Math.abs(n) >= 10000 });
}

/** Returns where a number sits between the column's min and max, 0 to 1. */
export function heat(v: string, col: ColumnInfo): number | null {
	const n = Number(v);
	if (!v.trim() || !Number.isFinite(n) || col.min === undefined || col.max === undefined || col.max === col.min) return null;
	return (n - col.min) / (col.max - col.min);
}

/** Returns a starting width that fits the column's kind. */
export function defaultWidth(col: ColumnInfo): number {
	if (col.width) return col.width;
	const label = plainName(col.name).length * 7.5 + 40;
	const body = col.kind === 'number' ? 100 : col.kind === 'category' ? 130 : col.kind === 'sequence' ? 160 : col.kind === 'empty' ? 90 : 240;
	return Math.round(Math.min(360, Math.max(label, body)));
}

// ---------------------------------------------------------------- saved layouts

export type ColourMode = 'excel' | 'tier' | 'values' | 'off';

/** Columns are kept by their position: a layout only applies to a table with the same columns. */
export interface GridLayout {
	/** Column positions in display order. */
	order: number[];
	hidden: number[];
	widths: Record<number, number>;
	/** Columns kept in view when scrolling sideways. */
	pinned: number;
	density: 'compact' | 'comfortable';
	wrap: boolean;
	colour: ColourMode | null;
}

/** Tables with the same columns (every genome's FINAL table) share one layout. */
function layoutKey(kind: string, columns: ColumnInfo[]): string {
	let h = 0;
	for (const ch of kind + '|' + columns.map((c) => c.name).join('\t')) h = (Math.imul(31, h) + ch.charCodeAt(0)) | 0;
	return `margie.grid.${(h >>> 0).toString(36)}`;
}

export function loadLayout(kind: string, columns: ColumnInfo[]): Partial<GridLayout> {
	try {
		return JSON.parse(localStorage.getItem(layoutKey(kind, columns)) ?? '{}');
	} catch {
		return {};
	}
}

export function saveLayout(kind: string, columns: ColumnInfo[], layout: GridLayout): void {
	try {
		localStorage.setItem(layoutKey(kind, columns), JSON.stringify(layout));
	} catch {
		// Storage unavailable (private window or turned off).
	}
}

export function forgetLayout(kind: string, columns: ColumnInfo[]): void {
	try {
		localStorage.removeItem(layoutKey(kind, columns));
	} catch {
		// Nothing to forget.
	}
}
