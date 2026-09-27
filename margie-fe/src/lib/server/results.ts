/**
 * Lists results: per-tool output folders and each genome's results folder
 * (written by run-meta.sh), before or after the final reorganize step. Report
 * numbers come from lib/workspace/final-summary.ts.
 */

import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { getSettings } from './pipeline';
import { FinalTally, type FinalCounts } from '$lib/workspace/final-summary';

export interface FinalResults {
	dir: string;
	viewer?: string;
	table?: string;
	excel?: string;
	diagrams?: string;
}

export interface OrganismResult {
	organism: string;
	tools: { tool: string; path: string; processed: boolean }[];
	/** The genome's own results folder, as soon as it exists (before the final table). */
	folder?: string;
	final?: FinalResults;
}

const TABLE = 'FINAL_ANNOTATION_WITH_CONFIDENCE.tsv';
const EXCEL = 'FINAL_ANNOTATION_WITH_CONFIDENCE.xlsx';
/** Collection-level outputs, and the per-genome results folder itself. */
const NOT_PER_TOOL = new Set(['gtdbtk', 'aai', 'ani', 'closest', 'genomes']);
/** Folders in a genome's results that are steps, not tools. */
const NOT_TOOLS = new Set(['consolidation', 'labeling', 'scoring', 'fingerprint', 'evidence', 'figures', 'diagrams', 'per-tool-phased-output']);

function subdirs(dir: string): string[] {
	try {
		return fs
			.readdirSync(dir, { withFileTypes: true })
			.filter((e) => e.isDirectory() && !e.name.startsWith('.'))
			.map((e) => e.name);
	} catch {
		return [];
	}
}

function settingValue(key: string): string {
	return getSettings().settings.find((s) => s.key === key)?.value ?? '';
}

export function resultFolders() {
	const outputRoot = settingValue('OUTPUT_ROOT');
	return { outputRoot, genomesDir: settingValue('GENOME_RESULTS_DIR') || path.join(outputRoot, 'genomes') };
}

export function finalResults(dir: string): FinalResults | undefined {
	if (!fs.existsSync(dir)) return undefined;
	const first = (...candidates: string[]) => candidates.map((c) => path.join(dir, c)).find((p) => fs.existsSync(p));
	return {
		dir,
		viewer: first('FINAL_GENOME_VIEWER.html'),
		// run-meta.sh writes these under scoring/; the finalize step moves them up
		table: first(TABLE, path.join('scoring', TABLE)),
		excel: first(EXCEL, path.join('scoring', EXCEL)),
		diagrams: first('diagrams', path.join('scoring', 'figures'))
	};
}

/** Lists every organism with results, per tool and in its own results folder. */
export function listResults(): { outputRoot: string; genomesDir: string; organisms: OrganismResult[] } {
	const { outputRoot, genomesDir } = resultFolders();
	const byOrganism = new Map<string, OrganismResult>();
	for (const tool of subdirs(outputRoot)) {
		if (NOT_PER_TOOL.has(tool)) continue;
		for (const genome of subdirs(path.join(outputRoot, tool))) {
			const dir = path.join(outputRoot, tool, genome);
			const kids = subdirs(dir);
			if (!kids.includes('raw') && !kids.includes('processed')) continue;
			const entry = byOrganism.get(genome) ?? { organism: genome, tools: [] };
			entry.tools.push({ tool, path: dir, processed: kids.includes('processed') });
			byOrganism.set(genome, entry);
		}
	}
	// A genome's own folder counts once it has a final table, a tool's output,
	// or a row in the prepared genome table -- not the pangenome figures' scoring/.
	const prepared = preparedGenomes();
	for (const genome of subdirs(genomesDir)) {
		const dir = path.join(genomesDir, genome);
		const final = finalResults(dir);
		if (!final?.table && !byOrganism.has(genome) && !prepared.has(genome)) continue;
		const entry = byOrganism.get(genome) ?? { organism: genome, tools: [] };
		entry.folder = dir;
		if (final?.table) entry.final = final;
		byOrganism.set(genome, entry);
	}
	const organisms = [...byOrganism.values()].sort((a, b) => a.organism.localeCompare(b.organism));
	return { outputRoot, genomesDir, organisms };
}

/** Reads the genome names in input/genomes.tsv, the table a run prepares. */
function preparedGenomes(): Set<string> {
	try {
		const rows = fs.readFileSync(path.join(settingValue('INPUT_RASTTK'), 'genomes.tsv'), 'utf8').split('\n').slice(1);
		return new Set(rows.map((l) => l.split('\t')[0]).filter(Boolean));
	} catch {
		return new Set();
	}
}

/** Reads the genome's row in input/genomes.tsv (domain, genetic code, gene caller). */
function genomeTableRow(genome: string): Record<string, string> {
	const table = path.join(settingValue('INPUT_RASTTK'), 'genomes.tsv');
	try {
		const [head, ...rows] = fs.readFileSync(table, 'utf8').split('\n');
		const cols = head.split('\t');
		for (const line of rows) {
			const cells = line.split('\t');
			if (cells[0] === genome) return Object.fromEntries(cols.map((c, i) => [c, cells[i] ?? '']));
		}
	} catch {
		// No table yet.
	}
	return {};
}

export { GLYPH_TIERS, type GenomeGlyph } from '$lib/workspace/final-summary';

export interface GenomeSummary extends FinalCounts {
	genome: string;
	final: FinalResults;
	domain: string;
	geneticCode: string;
	geneCaller: string;
	tools: string[];
	figures: string[];
}

export async function genomeSummary(genome: string): Promise<GenomeSummary | null> {
	if (!/^[A-Za-z0-9._-]+$/.test(genome)) return null;
	const { genomesDir } = resultFolders();
	const dir = path.join(genomesDir, genome);
	const final = finalResults(dir);
	if (!final?.table) return null;

	const tally = new FinalTally();
	const rl = readline.createInterface({ input: fs.createReadStream(final.table), crlfDelay: Infinity });
	for await (const line of rl) tally.add(line);

	const toolRoot = fs.existsSync(path.join(dir, 'per-tool-phased-output')) ? path.join(dir, 'per-tool-phased-output') : dir;
	const tools = subdirs(toolRoot).filter((d) => !NOT_TOOLS.has(d)).sort();
	let figures: string[] = [];
	if (final.diagrams) {
		try {
			figures = fs
				.readdirSync(final.diagrams)
				.filter((f) => f.toLowerCase().endsWith('.png'))
				.sort()
				.map((f) => path.join(final.diagrams as string, f));
		} catch {
			// No figures.
		}
	}
	const row = genomeTableRow(genome);
	return {
		...tally.result(),
		genome,
		final,
		domain: row.domain ?? '',
		geneticCode: row.genetic_code ?? '',
		geneCaller: row.gene_caller ?? '',
		tools,
		figures
	};
}
