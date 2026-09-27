/**
 * Tallies a genome's report numbers (genes, operons, support, confidence tiers,
 * the Map's ring) from its FINAL table line by line; the server and cluster
 * pages feed it lines, so both count the same way.
 */

/**
 * A genome drawn as a ring: its length cut into `bins` equal arcs, each
 * coloured by the confidence tier most of its genes have (index into
 * GLYPH_TIERS, -1: no gene there), for each strand.
 */
export interface GenomeGlyph {
	length: number;
	contigs: number;
	plus: number[];
	minus: number[];
}

export const GLYPH_TIERS = ['highest', 'high', 'medium', 'fair', 'low', 'none'];
const GLYPH_BINS = 240;

/** FINAL table columns are named "Column-A: organism_name"; this gives "organism_name". */
export const plainName = (c: string) => c.replace(/^Column-[A-Z]+:\s*/, '');

export interface FinalCounts {
	columns: string[];
	genes: number;
	operons: number;
	inOperons: number;
	withSupport: number;
	envelope: string;
	tiers: Record<string, number>;
	glyph: GenomeGlyph | null;
}

/** Counts the table's lines passed in order to add(); result() returns the summary. */
export class FinalTally {
	#columns: string[] = [];
	#idx: Record<string, number> = {};
	#genes = 0;
	#inOperons = 0;
	#withSupport = 0;
	#envelope = '';
	#operons = new Set<string>();
	#tiers: Record<string, number> = {};
	#placed: { contig: string; start: number; end: number; strand: string; tier: number }[] = [];

	add(line: string) {
		if (!this.#columns.length) {
			this.#columns = line.split('\t');
			this.#idx = Object.fromEntries(this.#columns.map((c, i) => [plainName(c), i]));
			return;
		}
		if (!line) return;
		const cells = line.split('\t');
		const get = (name: string) => (this.#idx[name] !== undefined ? (cells[this.#idx[name]] ?? '').trim() : '');
		this.#genes++;
		if (/^yes$/i.test(get('IS_IN_OPERON?'))) this.#inOperons++;
		const op = get('UniOP_OPERON_id');
		if (op.startsWith('operon')) this.#operons.add(op);
		const desc = get('best_consensus_product_descriptor');
		if (desc && !/^no db hits$/i.test(desc)) this.#withSupport++;
		const tier = get('CONFIDENCE_TIER');
		if (tier) this.#tiers[tier] = (this.#tiers[tier] ?? 0) + 1;
		this.#envelope ||= get('ENVELOPE') || get('envelope');

		const start = Number(get('RAST_start') || get('gene_start'));
		const end = Number(get('RAST_end') || get('gene_end'));
		if (Number.isFinite(start) && Number.isFinite(end) && start > 0 && end > 0) {
			const id = get('gene_id');
			const contig = id.match(/^(.*)_\d+[+-]\d+$/)?.[1] ?? get('RAST_feature_id').match(/^(.*)_\d+$/)?.[1] ?? '';
			const t = (get('CONFIDENCE_TIER_hybrid') || tier).toLowerCase();
			const ti = GLYPH_TIERS.indexOf(t);
			this.#placed.push({ contig, start: Math.min(start, end), end: Math.max(start, end), strand: get('RAST_strand'), tier: ti < 0 ? 5 : ti });
		}
	}

	result(): FinalCounts {
		return {
			columns: this.#columns.map(plainName),
			genes: this.#genes,
			operons: this.#operons.size,
			inOperons: this.#inOperons,
			withSupport: this.#withSupport,
			envelope: this.#envelope,
			tiers: this.#tiers,
			glyph: glyphOf(this.#placed)
		};
	}
}

/** Bins a genome's genes around one ring, contigs end to end in the order they first appear. */
function glyphOf(genes: { contig: string; start: number; end: number; strand: string; tier: number }[]): GenomeGlyph | null {
	if (!genes.length) return null;
	const lengths = new Map<string, number>();
	for (const g of genes) lengths.set(g.contig, Math.max(lengths.get(g.contig) ?? 0, g.end));
	const offset = new Map<string, number>();
	let total = 0;
	for (const [contig, len] of lengths) {
		offset.set(contig, total);
		total += len;
	}
	const counts = { plus: [] as number[][], minus: [] as number[][] };
	for (const side of ['plus', 'minus'] as const) for (let i = 0; i < GLYPH_BINS; i++) counts[side].push(new Array(GLYPH_TIERS.length).fill(0));
	for (const g of genes) {
		const at = (offset.get(g.contig) ?? 0) + (g.start + g.end) / 2;
		const bin = Math.min(GLYPH_BINS - 1, Math.floor((at / total) * GLYPH_BINS));
		counts[g.strand === '-' ? 'minus' : 'plus'][bin][g.tier]++;
	}
	const dominant = (c: number[]) => (c.every((n) => n === 0) ? -1 : c.indexOf(Math.max(...c)));
	return { length: total, contigs: lengths.size, plus: counts.plus.map(dominant), minus: counts.minus.map(dominant) };
}
