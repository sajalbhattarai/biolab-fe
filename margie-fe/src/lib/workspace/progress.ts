/**
 * Parses an annotate.sh run's progress from its log lines
 * ("[annotate] gene calling (prodigal): X", "[meta] scoring: ...", ...).
 */

export interface GenomeProgress {
	name: string;
	state: 'done' | 'running' | 'queued';
}

export interface AnnotateProgress {
	genomes: GenomeProgress[];
	current: string;
	/** Plain-words stage of the current genome. */
	stage: string;
	/** Tool or script running now, when the log names one. */
	detail: string;
	/** 0-1, over all genomes (a genome's own stages count as fractions). */
	fraction: number;
	/** Annotation tools the current genome has started, in order (the last one is running). */
	tools: string[];
}

/** A genome's stages, in order, as the run ring draws them. */
export const STAGE_NAMES = ['Finding genes', 'Annotating', 'Cell envelope', 'Combining results', 'Labelling', 'Scoring', 'Fingerprints', 'Map and figures'];

const STAGES: [RegExp, string, number][] = [
	[/^\[annotate\] gene calling \(([^)]+)\)/, 'Finding genes', 0.1],
	[/^\[annotate\] organism pipeline start:/, 'Annotating', 0.2],
	[/^\[annotate\] Phase 1b-mid envelope/, 'Cell envelope', 0.6],
	[/^\[annotate\] Phase 1c per-genome results/, 'Combining results', 0.7],
	[/^\[meta\] labeling:/, 'Labelling', 0.75],
	[/^\[meta\] scoring:/, 'Scoring', 0.8],
	[/^\[meta\] fingerprint:/, 'Fingerprints', 0.85],
	[/^\[meta\] (evidence|viewer|figures):/, 'Map and figures', 0.92]
];

export function annotateProgress(log: string): AnnotateProgress | null {
	const lines = log.split('\n');
	const list = log.match(/\[annotate\] \d+ (?:genome|organism)\(s\): (.+)/)?.[1]?.trim().split(/\s+/) ?? [];
	if (!list.length) return null;
	const done = new Set([...log.matchAll(/\[annotate\] (\S+) scored\./g)].map((m) => m[1]));
	const starts = [...log.matchAll(/\[annotate\] (?:gene calling \([^)]*\)|organism pipeline start): (\S+)/g)];
	const current = starts.at(-1)?.[1] ?? '';

	// Stage and detail: the last marker after the current genome started.
	let stage = current ? 'Starting' : 'Preparing genomes';
	let detail = '';
	let within = 0;
	const tools: string[] = [];
	const esc = current.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const startRe = new RegExp(`^\\[annotate\\] (?:gene calling \\([^)]*\\)|organism pipeline start): ${esc}$`);
	const from = current ? lines.findIndex((l) => startRe.test(l.trim())) : 0;
	for (const line of lines.slice(Math.max(0, from))) {
		const l = line.trim();
		for (const [re, name, f] of STAGES) {
			const m = l.match(re);
			if (m) {
				stage = name;
				within = f;
				detail = name === 'Finding genes' ? m[1] : '';
			}
		}
		const tool = l.match(/^\[annotate\] ([a-z0-9_-]+)$/);
		if (tool && tool[1] !== 'genomes' && tool[1] !== 'gtdbtk') {
			detail = tool[1];
			if (!tools.includes(tool[1])) tools.push(tool[1]);
		}
		const meta = l.match(/^\[meta\] [a-z]+: (\S+)/);
		if (meta) detail = meta[1].replace(/\.py$/, '');
	}
	const lastIndex = (re: RegExp) => lines.reduce((at, l, i) => (re.test(l) ? i : at), -1);
	if (lastIndex(/\[annotate\] Phase 2/) > lastIndex(/\[annotate\] \S+ scored\./)) stage = 'Comparing genomes';
	if (lastIndex(/\[meta\] (?:finalize|figures): (?:reorganize_outputs|make_global_report)/) >= 0) stage = 'Finishing';

	const genomes: GenomeProgress[] = list.map((name) => ({
		name,
		state: done.has(name) ? 'done' : name === current ? 'running' : 'queued'
	}));
	const running = current && !done.has(current) ? within : 0;
	return { genomes, current, stage, detail, fraction: Math.min(1, (done.size + running) / list.length), tools };
}
