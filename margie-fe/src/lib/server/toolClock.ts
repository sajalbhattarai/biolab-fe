/**
 * Reads the per-tool logs (logs/annotation/<n>-<user>-run-<tool>-<UTC start>.log)
 * for each tool's usual time (median of past successes) and when the current
 * run started each tool on each genome. margie-frontend's lib/server holds an
 * identical copy.
 */

import fs from 'node:fs';
import path from 'node:path';
import { PIPELINE_ROOT } from './pipeline';

const DIR = path.join(PIPELINE_ROOT, 'logs', 'annotation');
const NAME = /-run-(.+)-(\d{8}T\d{6}Z)\.log$/;

interface Entry {
	tool: string;
	genome: string;
	start: number;
	/** Last write, ms. */
	last: number;
	ok: boolean;
	/** Ended on an error of its own. */
	failed: boolean;
	/** Restored from a cache or already there: says nothing about how long the tool takes. */
	skipped: boolean;
}

export interface ToolClock {
	/** Usual seconds per tool, from earlier successful runs. */
	typical: Record<string, number>;
	/** The tool runs the run started: which tool, which genome, when, and whether it finished well or failed. */
	started: { tool: string; genome: string; start: number; last: number; ok: boolean; failed: boolean }[];
	/** The server's clock, ms, so elapsed times do not depend on the viewer's. */
	now: number;
}

const seen = new Map<string, { size: number; mtime: number; entry: Entry | null }>();

const stamp = (s: string) =>
	Date.parse(`${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}T${s.slice(9, 11)}:${s.slice(11, 13)}:${s.slice(13, 15)}Z`);

function slice(fd: number, from: number, len: number): string {
	const buf = Buffer.alloc(len);
	const n = fs.readSync(fd, buf, 0, len, from);
	return buf.subarray(0, n).toString('utf8');
}

/** Parses one log, re-reading it only when it has grown. */
function read(file: string): Entry | null {
	const m = NAME.exec(file);
	if (!m) return null;
	const full = path.join(DIR, file);
	const st = fs.statSync(full, { throwIfNoEntry: false });
	if (!st) return null;
	const was = seen.get(file);
	if (was && was.size === st.size && was.mtime === st.mtimeMs) return was.entry;
	let head = '';
	let tail = '';
	const fd = fs.openSync(full, 'r');
	try {
		head = slice(fd, 0, 4096);
		tail = st.size > 4096 ? slice(fd, st.size - 4096, 4096) : head;
	} finally {
		fs.closeSync(fd);
	}
	const genome =
		/^\[pipeline\] \S+ :: ([^/\s]+)\//m.exec(head)?.[1] ?? /^\[(?:rasttk|prodigal)\] ([^\s:]+):/m.exec(head + '\n' + tail)?.[1] ?? '';
	const entry = genome
		? {
				tool: m[1],
				genome,
				start: stamp(m[2]),
				last: st.mtimeMs,
				ok: /processed\/\s*:|\] Done:/.test(tail) && !/^Error:/m.test(tail),
				failed: !/processed\/\s*:|\] Done:/.test(tail) && /^Error:|\bERROR\b|Traceback|exited with|exit code [1-9]/m.test(tail),
				skipped: /skipping|not run again|already done|restored/i.test(head + tail)
			}
		: null;
	seen.set(file, { size: st.size, mtime: st.mtimeMs, entry });
	return entry;
}

const median = (xs: number[]) => {
	const s = [...xs].sort((a, b) => a - b);
	return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
};

/** Returns the usual times and the tool runs started between `since` and `until` (ms). */
export function toolClock(since: number, until = Infinity): ToolClock {
	let files: string[] = [];
	try {
		files = fs.readdirSync(DIR).filter((f) => NAME.test(f));
	} catch {
		// No logs yet.
	}
	const entries = files.map(read).filter((e): e is Entry => !!e);
	const took = new Map<string, number[]>();
	for (const e of entries) {
		const secs = (e.last - e.start) / 1000;
		if (e.ok && !e.skipped && secs > 5) took.set(e.tool, [...(took.get(e.tool) ?? []), secs]);
	}
	return {
		typical: Object.fromEntries([...took].map(([t, xs]) => [t, Math.round(median(xs))])),
		// A second of slack: the log's name is stamped to the second.
		// Skipped (already there) counts as finished: there is nothing left for it to do.
		started: entries
			.filter((e) => e.start >= since - 1000 && e.start <= until + 1000)
			.map(({ tool, genome, start, last, ok, failed, skipped }) => ({ tool, genome, start, last, ok: ok || skipped, failed: failed && !skipped })),
		now: Date.now()
	};
}
