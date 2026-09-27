/**
 * Decides which settings the Settings board draws as a slider (cores, memory,
 * threads, SLURM nodes, CPUs, time) and over what range. A slider writes the
 * value in the setting's own format ("128G", "24:00:00", a plain number).
 */

import type { Setting } from '$lib/workspace/data.svelte';

export interface Range {
	min: number;
	max: number;
	step: number;
	/** Shown after the number, e.g. "GB", "h". */
	unit: string;
	read: (value: string) => number | null;
	write: (n: number) => string;
}

const int = (v: string) => (/^\d+$/.test(v.trim()) ? Number(v.trim()) : null);
const gb = (v: string) => {
	const m = v.trim().match(/^(\d+)G$/i);
	return m ? Number(m[1]) : null;
};
const hours = (v: string) => {
	const m = v.trim().match(/^(\d+):(\d\d):(\d\d)$/);
	return m ? Number(m[1]) + Number(m[2]) / 60 + Number(m[3]) / 3600 : null;
};
const hms = (h: number) => `${String(Math.round(h)).padStart(2, '0')}:00:00`;

/** Returns the slider for `s`, or null; `budget` is the core count the pipeline may use. */
export function rangeOf(s: Setting, budget: number | null): Range | null {
	const k = s.key;
	const now = (read: (v: string) => number | null) => read(s.value) ?? read(s.default) ?? 0;
	const whole = (min: number, max: number, unit = '', step = 1): Range => ({
		min,
		max: Math.max(max, now(int)),
		step,
		unit,
		read: int,
		write: String
	});

	if (s.type === 'int') {
		// The defaults are three quarters of the machine, so the machine is 4/3 of them.
		if (k === 'LOCAL_MAX_CORES') return whole(1, Math.round(((int(s.default) ?? 8) * 4) / 3), 'cores');
		if (k === 'LOCAL_MAX_MEMORY_GB') return whole(1, Math.round(((int(s.default) ?? 16) * 4) / 3), 'GB');
		if (k === 'THREADS' || k === 'LOCAL_PARALLEL_TOOLS' || /^TOOL_\w+_THREADS$/.test(k)) return whole(1, budget ?? 64);
		if (k === 'PARALLEL_TOOLS') return whole(1, 16);
		if (/^SLURM_\w+_NODES$/.test(k)) return whole(1, 32, 'nodes');
		if (/^SLURM_\w+_CPUS$/.test(k)) return whole(1, 128, 'CPUs');
		// A cluster's workflow and compute settings (lib/cluster/backend.ts).
		if (/(^|\.)(default_)?threads$/.test(k)) return whole(1, 128);
		if (/(^|\.)(default_)?mem_mb$/.test(k)) return whole(0, 262144, 'MB', 1024);
		if (/(^|\.)(default_)?runtime$/.test(k)) return whole(0, 2880, 'min', 15);
		if (/(^|\.)max_jobs$/.test(k)) return whole(1, 100);
		if (/(^|\.)max_parallel_(genomes|tools)$/.test(k)) return whole(1, 32);
		return null;
	}
	if (s.type === 'text') {
		// Only when the value is already written that way: then the slider keeps the format.
		if (/^SLURM_\w+_MEM$/.test(k) && gb(s.value || s.default) !== null)
			return { min: 1, max: Math.max(512, now(gb)), step: 1, unit: 'GB', read: gb, write: (n) => `${Math.round(n)}G` };
		if ((/^SLURM_\w+_TIME$/.test(k) || /walltime$/.test(k)) && hours(s.value || s.default) !== null)
			return { min: 1, max: Math.max(72, Math.ceil(now(hours))), step: 1, unit: 'h', read: hours, write: hms };
	}
	return null;
}
