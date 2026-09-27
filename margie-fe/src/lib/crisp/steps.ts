/**
 * Reads the post-annotation steps from a run's log (annotate.sh, run-meta.sh):
 * each genome's result stages (Phase 1c, up to "<genome> scored.") and the
 * Phase 2 comparisons over the pool of scored genomes.
 */

export const RESULT_STAGES = ['consolidation', 'labeling', 'scoring', 'fingerprint', 'evidence', 'viewer', 'figures'] as const;
export const COMPARE_TOOLS = ['ani', 'aai', 'closest', 'synteny'] as const;

export type LogState = 'done' | 'wait' | 'failed' | 'partial' | 'na';

export interface LogSteps {
	/** `${step}\t${genome}` -> state, for result stages and comparisons. */
	state: Map<string, LogState>;
	/** Genomes whose result stages have all run. */
	scored: Set<string>;
}

const STAGE = new Set<string>(RESULT_STAGES);

/** Returns step states from `log`; once the run has ended, waiting steps take its outcome (Stop leaves them partial). */
export function logSteps(log: string, status: 'running' | 'completed' | 'failed' | 'cancelled'): LogSteps {
	const state = new Map<string, LogState>();
	const scored = new Set<string>();
	let genome = '';
	let stage = '';
	let pool: string[] = [];
	let reading = false;
	let compare = '';
	const set = (step: string, g: string, s: LogState) => {
		if (state.get(`${step}\t${g}`) !== 'failed') state.set(`${step}\t${g}`, s);
	};
	for (const raw of log.split('\n')) {
		const l = raw.trimEnd();
		let m: RegExpExecArray | null;
		if ((m = /^\[annotate\] Phase 1c per-genome results: (\S+)/.exec(l))) {
			genome = m[1];
			stage = '';
		} else if (genome && (m = /^\[meta\] ([a-z]+): /.exec(l)) && STAGE.has(m[1])) {
			if (stage && stage !== m[1]) set(stage, genome, 'done');
			stage = m[1];
			set(stage, genome, 'wait');
		} else if (genome && (m = /^\[meta\] WARN: ([a-z]+): .*failed/.exec(l))) {
			set(m[1], genome, 'failed');
		} else if (genome && /^\[meta\] ERROR/.test(l)) {
			set(stage || RESULT_STAGES[0], genome, 'failed');
		} else if ((m = /^\[annotate\] (\S+) scored\./.exec(l))) {
			const g = m[1];
			if (stage && g === genome) set(stage, g, 'done');
			// A stage that never ran for a scored genome is switched off.
			for (const s of RESULT_STAGES) if (!state.has(`${s}\t${g}`)) state.set(`${s}\t${g}`, 'na');
			scored.add(g);
			if (g === genome) genome = stage = '';
		} else if (/^\[annotate\] Phase 2 {1,2}\(scored pool/.test(l)) {
			pool = [];
			reading = true;
			compare = '';
		} else if (reading && (m = /^ {2}(\S+)$/.exec(l))) {
			pool.push(m[1]);
		} else if ((m = /^──── Phase 2: (\S+) ────/.exec(l))) {
			reading = false;
			if (compare) for (const g of pool) set(compare, g, 'done');
			compare = m[1];
			for (const g of pool) set(compare, g, 'wait');
		} else if (/^\[annotate\] Phase 2 complete\./.test(l)) {
			if (compare) for (const g of pool) set(compare, g, 'done');
			compare = '';
		} else if (reading && l.startsWith('═')) {
			if (pool.length) reading = false;
		}
	}
	if (status !== 'running') {
		for (const [k, v] of state) if (v === 'wait') state.set(k, status === 'failed' ? 'failed' : status === 'completed' ? 'done' : 'partial');
	}
	return { state, scored };
}
