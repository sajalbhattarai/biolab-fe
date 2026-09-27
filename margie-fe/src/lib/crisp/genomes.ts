/** Every genome Atlas knows of, from the input folder, the results and the run going on. */

import { ws, type Genome, type OrganismResult } from '$lib/workspace/data.svelte';

export type GenomeState = 'done' | 'running' | 'partial' | 'pending';

export interface AtlasGenome {
	name: string;
	state: GenomeState;
	/** The FASTA file in the input folder, when it is still there. */
	file?: Genome;
	result?: OrganismResult;
}

const STATE_ORDER: Record<GenomeState, number> = { running: 0, done: 1, partial: 2, pending: 3 };
export const stemOf = (file: string) => file.replace(/\.(fna|fa|fasta)$/i, '');

/** An annotate run is going but its log has not been read yet, so which genome it is on is not known. */
export const settling = () => ws.active?.kind === 'annotate' && !ws.log;

export function genomeList(): AtlasGenome[] {
	const byName = new Map<string, AtlasGenome>();
	for (const f of ws.genomes) byName.set(stemOf(f.name), { name: stemOf(f.name), state: 'pending', file: f });
	for (const r of ws.results) {
		const g = byName.get(r.organism) ?? { name: r.organism, state: 'pending' };
		g.result = r;
		g.state = r.final?.table ? 'done' : 'partial';
		byName.set(r.organism, g);
	}
	// The run going on: the genome it is on, and those still queued in it
	// (unless an earlier run already finished them).
	for (const p of ws.progress?.genomes ?? []) {
		if (p.state === 'done') continue;
		const g = byName.get(p.name) ?? { name: p.name, state: 'pending' };
		if (p.state === 'running') g.state = 'running';
		else if (g.state !== 'done') g.state = 'pending';
		byName.set(p.name, g);
	}
	return [...byName.values()].sort((a, b) => STATE_ORDER[a.state] - STATE_ORDER[b.state] || a.name.localeCompare(b.name));
}

export const STATE_WORDS: Record<GenomeState, string> = {
	done: 'annotated',
	running: 'annotating now',
	partial: 'not finished',
	pending: 'waiting'
};
