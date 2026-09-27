/**
 * Table rules shared by server (lib/server/tables.ts) and browser: parses
 * delimited text, infers column kinds (number, category, sequence, text), and
 * returns one sorted, filtered page.
 */

export type ColumnKind = 'number' | 'category' | 'sequence' | 'text' | 'empty';

export interface ColumnInfo {
	name: string;
	kind: ColumnKind;
	min?: number;
	max?: number;
	/** For categories: the values, most common first. */
	values?: string[];
	/** Excel column width in pixels, when the workbook sets one. */
	width?: number;
}

/** An Excel cell's own look: fill, text colour, bold, and which edges have a border. */
export interface CellStyle {
	bg?: string;
	fg?: string;
	bold?: boolean;
	border?: string;
}

export interface Sheet {
	name: string;
	columns: ColumnInfo[];
	rows: string[][];
	/** Excel only: index into `palette` per cell (-1: none). */
	styles?: Int32Array[];
	headerStyle?: CellStyle;
	/** Excel's frozen columns. */
	frozen?: number;
}

export interface Table {
	kind: 'tsv' | 'csv' | 'gff' | 'xlsx';
	sheets: Sheet[];
	palette: CellStyle[];
}

export const TABLE_EXT: Record<string, Table['kind']> = {
	'.tsv': 'tsv',
	'.tab': 'tsv',
	'.txt': 'tsv',
	'.csv': 'csv',
	'.gff': 'gff',
	'.gff3': 'gff',
	'.gtf': 'gff',
	'.xlsx': 'xlsx'
};
const GFF_COLUMNS = ['seqid', 'source', 'type', 'start', 'end', 'score', 'strand', 'phase', 'attributes'];
const EMPTY = new Set(['', '-', 'na', 'n/a', 'nan', 'none', 'null']);

/** ".tsv" for "a/b.TSV"; "" when there is none. */
export const extOf = (p: string) => p.match(/\.[^./]+$/)?.[0].toLowerCase() ?? '';

// ---------------------------------------------------------------- reading

function splitCsv(line: string): string[] {
	const out: string[] = [];
	let field = '';
	let quoted = false;
	for (let i = 0; i < line.length; i++) {
		const c = line[i];
		if (quoted) {
			if (c === '"' && line[i + 1] === '"') {
				field += '"';
				i++;
			} else if (c === '"') quoted = false;
			else field += c;
		} else if (c === '"') quoted = true;
		else if (c === ',') {
			out.push(field);
			field = '';
		} else field += c;
	}
	out.push(field);
	return out;
}

/** Parses TSV, CSV or GFF text into a sheet named `name`. */
export function parseDelimited(text: string, kind: 'tsv' | 'csv' | 'gff', name: string): Sheet {
	const lines = text.split(/\r?\n/);
	while (lines.length && lines.at(-1) === '') lines.pop();
	// Leading "##" lines are metadata (GFF, HMMER); a single "#" line is often the header.
	let start = 0;
	while (start < lines.length && (lines[start].startsWith('##') || (kind === 'gff' && lines[start].startsWith('#')))) start++;
	const split = kind === 'csv' ? splitCsv : (l: string) => l.split('\t');
	let header: string[];
	if (kind === 'gff') header = GFF_COLUMNS;
	else {
		header = split((lines[start] ?? '').replace(/^#\s*/, ''));
		start++;
	}
	const rows: string[][] = [];
	for (let i = start; i < lines.length; i++) {
		const l = lines[i];
		if (!l || l.startsWith('#')) continue;
		rows.push(split(l));
	}
	const width = Math.max(header.length, ...rows.slice(0, 2000).map((r) => r.length));
	const names = Array.from({ length: width }, (_, i) => header[i]?.trim() || `Column ${i + 1}`);
	for (const r of rows) while (r.length < width) r.push('');
	return { name, columns: describe(names, rows), rows };
}

/** Works out each column's kind from its values. */
export function describe(names: string[], rows: string[][]): ColumnInfo[] {
	return names.map((name, c) => {
		const values = rows.map((r) => (r[c] ?? '').trim()).filter((v) => !EMPTY.has(v.toLowerCase()));
		if (!values.length) return { name, kind: 'empty' };
		const nums = values.map(Number).filter((n) => Number.isFinite(n));
		if (nums.length >= values.length * 0.95) {
			let min = Infinity;
			let max = -Infinity;
			for (const n of nums) {
				if (n < min) min = n;
				if (n > max) max = n;
			}
			return { name, kind: 'number', min, max };
		}
		const sample = values.slice(0, 200);
		const avg = sample.reduce((a, v) => a + v.length, 0) / sample.length;
		if (/seq|sequence/i.test(name) || (avg > 60 && sample.every((v) => /^[A-Z*\-]+$/.test(v)))) return { name, kind: 'sequence' };
		const counts = new Map<string, number>();
		for (const v of values) counts.set(v, (counts.get(v) ?? 0) + 1);
		if (counts.size <= 12 && values.length >= counts.size * 2 && avg < 40) {
			return { name, kind: 'category', values: [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([v]) => v) };
		}
		return { name, kind: 'text' };
	});
}

// ---------------------------------------------------------------- query

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });

/** Builds a column filter from ">5", "<=0.5", "10..20", "=low", or text the value contains. */
function matcher(raw: string, kind: ColumnKind): (v: string) => boolean {
	const f = raw.trim();
	const range = f.match(/^(-?[\d.eE+-]+)\s*\.\.\s*(-?[\d.eE+-]+)$/);
	if (kind === 'number' && range) {
		const [a, b] = [Number(range[1]), Number(range[2])];
		return (v) => Number(v) >= a && Number(v) <= b;
	}
	const cmp = f.match(/^(<=|>=|<|>|=)\s*(.+)$/);
	if (cmp) {
		const n = Number(cmp[2]);
		if (cmp[1] === '=') return (v) => v.trim().toLowerCase() === cmp[2].trim().toLowerCase();
		if (Number.isFinite(n)) {
			const op = cmp[1];
			return (v) => {
				const x = Number(v);
				if (!v.trim() || !Number.isFinite(x)) return false;
				return op === '<' ? x < n : op === '<=' ? x <= n : op === '>' ? x > n : x >= n;
			};
		}
	}
	const needle = f.toLowerCase();
	return (v) => v.toLowerCase().includes(needle);
}

export interface TableQuery {
	sheet: number;
	page: number;
	size: number;
	q: string;
	sort: { col: number; dir: 'asc' | 'desc' } | null;
	filters: Record<number, string>;
}

/** Reads a table query from a URL's parameters, as the viewer sends it. */
export function queryFromParams(p: URLSearchParams): TableQuery {
	const sort = p.get('sort')?.match(/^(\d+):(asc|desc)$/);
	const filters: Record<number, string> = {};
	for (const [k, v] of p) {
		const m = k.match(/^f(\d+)$/);
		if (m && v.trim()) filters[Number(m[1])] = v;
	}
	return {
		sheet: Number(p.get('sheet')) || 0,
		page: Number(p.get('page')) || 1,
		size: Number(p.get('size')) || 100,
		q: p.get('q') ?? '',
		sort: sort ? { col: Number(sort[1]), dir: sort[2] as 'asc' | 'desc' } : null,
		filters
	};
}

/** Returns one sorted, filtered page of `table` for the viewer. */
export function queryLoaded(table: Table, query: TableQuery, where: { path: string; name: string }) {
	const sheetIndex = Math.min(Math.max(0, query.sheet), table.sheets.length - 1);
	const sheet = table.sheets[sheetIndex];

	let order = sheet.rows.map((_, i) => i);
	const q = query.q.trim().toLowerCase();
	if (q) order = order.filter((i) => sheet.rows[i].some((v) => v.toLowerCase().includes(q)));
	for (const [c, f] of Object.entries(query.filters)) {
		const col = Number(c);
		if (!f.trim() || !sheet.columns[col]) continue;
		const test = matcher(f, sheet.columns[col].kind);
		order = order.filter((i) => test(sheet.rows[i][col] ?? ''));
	}
	if (query.sort && sheet.columns[query.sort.col]) {
		const { col, dir } = query.sort;
		const sign = dir === 'desc' ? -1 : 1;
		const numeric = sheet.columns[col].kind === 'number';
		order.sort((a, b) => {
			const va = sheet.rows[a][col] ?? '';
			const vb = sheet.rows[b][col] ?? '';
			// Empty cells go last whichever way it sorts.
			const ea = EMPTY.has(va.trim().toLowerCase());
			const eb = EMPTY.has(vb.trim().toLowerCase());
			if (ea || eb) return ea === eb ? 0 : ea ? 1 : -1;
			return sign * (numeric ? Number(va) - Number(vb) : collator.compare(va, vb));
		});
	}

	const size = Math.min(1000, Math.max(10, query.size));
	const pages = Math.max(1, Math.ceil(order.length / size));
	const page = Math.min(Math.max(1, query.page), pages);
	const slice = order.slice((page - 1) * size, page * size);
	const used = new Set<number>();
	const rows = slice.map((i) => {
		const styles = sheet.styles?.[i];
		if (styles) for (const s of styles) if (s >= 0) used.add(s);
		return { i, cells: sheet.rows[i], styles: styles ? Array.from(styles) : undefined };
	});

	return {
		path: where.path,
		name: where.name,
		kind: table.kind,
		sheets: table.sheets.map((s) => ({ name: s.name, rows: s.rows.length })),
		sheet: sheetIndex,
		columns: sheet.columns,
		headerStyle: sheet.headerStyle,
		frozen: sheet.frozen,
		/** Only the styles this page uses, by their palette index. */
		palette: Object.fromEntries([...used].map((i) => [i, table.palette[i]])),
		total: sheet.rows.length,
		filtered: order.length,
		page,
		pages,
		size,
		rows
	};
}
