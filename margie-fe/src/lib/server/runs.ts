/**
 * Starts and tracks GUI runs (annotate.sh, setup.sh, margie-build's build.sh)
 * detached in their own process group, logging to logs/gui/<id>.log with the
 * exit code in <id>.rc, so runs outlive the GUI and are read back from
 * logs/gui/runs.json.
 */

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { PIPELINE_ROOT, pipelineEnv } from './pipeline';
import { annotateProgress } from '$lib/workspace/progress';

const RUNS_DIR = path.join(PIPELINE_ROOT, 'logs', 'gui');
const INDEX = path.join(RUNS_DIR, 'runs.json');
const SCRIPTS = { annotate: 'annotate.sh', setup: 'setup.sh' } as const;

export type RunKind = keyof typeof SCRIPTS | 'build';
export type RunStatus = 'running' | 'completed' | 'failed' | 'cancelled';

export interface Run {
	id: string;
	kind: RunKind;
	label: string;
	args: string[];
	/** How the command reads on screen, e.g. "./annotate.sh --tool pfam". */
	command: string;
	started: string;
	finished?: string;
	pid?: number;
	status: RunStatus;
	exitCode?: number | null;
	/** The tools it is building or downloading, when it is that kind of run. */
	tools?: string[];
	/** The genome files it was started on, by name. */
	files?: string[];
	/** Where this run writes: the folder to open when someone asks where it went. */
	outputDir?: string;
	/** 0-100, worked out from the log; not stored, added when a run is read. */
	progress?: number;
	/** What the number means in the run's own words, e.g. "321 MB" or "62%". */
	progressText?: string;
	/** Why it failed, in its own words; empty unless it did. */
	reason?: string;
}

export class RunError extends Error {
	constructor(message: string, readonly status = 400) {
		super(message);
	}
}

const logPath = (id: string) => path.join(RUNS_DIR, `${id}.log`);
const rcPath = (id: string) => path.join(RUNS_DIR, `${id}.rc`);

function readIndex(): Run[] {
	try {
		return JSON.parse(fs.readFileSync(INDEX, 'utf8'));
	} catch {
		return [];
	}
}

function writeIndex(runs: Run[]): void {
	fs.mkdirSync(RUNS_DIR, { recursive: true });
	const tmp = `${INDEX}.tmp`;
	fs.writeFileSync(tmp, JSON.stringify(runs, null, 2) + '\n');
	fs.renameSync(tmp, INDEX);
}

function alive(pid: number | undefined): boolean {
	if (!pid) return false;
	try {
		process.kill(pid, 0);
		return true;
	} catch (e) {
		return (e as NodeJS.ErrnoException).code === 'EPERM';
	}
}

function readRc(id: string): number | null {
	try {
		const n = parseInt(fs.readFileSync(rcPath(id), 'utf8').trim(), 10);
		return Number.isNaN(n) ? null : n;
	} catch {
		return null;
	}
}

/** Settles a run the index still calls running: finished (.rc), or gone without one. */
function settle(run: Run): boolean {
	if (run.status !== 'running') return false;
	const rc = readRc(run.id);
	if (rc !== null) {
		run.status = rc === 0 ? 'completed' : 'failed';
		run.exitCode = rc;
	} else if (!alive(run.pid)) {
		run.status = 'failed';
		run.exitCode = null; // stopped without an exit code (e.g. a restart)
	} else {
		return false;
	}
	run.finished = new Date().toISOString();
	return true;
}

function loadRuns(): Run[] {
	const runs = readIndex();
	if (runs.map(settle).some(Boolean)) writeIndex(runs);
	return runs;
}

export function listRuns(): Run[] {
	return loadRuns().sort((a, b) => b.started.localeCompare(a.started));
}

export function getRun(id: string): Run | null {
	return loadRuns().find((r) => r.id === id) ?? null;
}

export function activeRun(): Run | null {
	return loadRuns().find((r) => r.status === 'running') ?? null;
}

function newId(): string {
	const d = new Date();
	const pad = (n: number) => String(n).padStart(2, '0');
	const stamp = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
	return `${stamp}-${Math.random().toString(36).slice(2, 6)}`;
}

export interface RunOptions {
	/** Script to run instead of the pipeline's own (build.sh in the setup repository). */
	script?: string;
	cwd?: string;
	env?: Record<string, string>;
	/** On-screen name for the script, e.g. "margie-build/build.sh". */
	shown?: string;
	/** Which tools this run touches, so two runs never write one folder. */
	tools?: string[];
	/** The genome files this run was started on, by name. */
	files?: string[];
	/** Where this run writes. */
	outputDir?: string;
}

/** Maximum concurrent runs; an annotate run never overlaps another annotate run. */
export const MAX_RUNS = 2;


export function startRun(kind: RunKind, args: string[], label: string, opts: RunOptions = {}): Run {
	const running = loadRuns().filter((r) => r.status === 'running');
	// Two annotate runs would share one results tree; a download beside one is fine.
	const annotating = running.find((r) => r.kind === 'annotate');
	if (kind === 'annotate' && annotating) {
		throw new RunError(`"${annotating.label}" is still running. Wait for it to finish or stop it first.`, 409);
	}
	if (running.length >= MAX_RUNS) {
		throw new RunError(
			`Two runs are already going (${running.map((r) => `"${r.label}"`).join(' and ')}). Wait for one to finish.`,
			409
		);
	}
	// Runs must not share a tool. An annotate run without a tool list covers every
	// default tool, unless it only calls genes and so reads no database.
	const reach = (r: { kind: RunKind; args: string[]; tools?: string[] }) =>
		r.kind === 'annotate' && !r.tools?.length ? (r.args.includes('--genes-only') ? [] : ['*']) : (r.tools ?? []);
	const mine = new Set(reach({ kind, args, tools: opts.tools }));
	const clash = running.find((r) => {
		const theirs = reach(r);
		return theirs.some((t) => mine.has(t) || t === '*' || mine.has('*'));
	});
	if (clash) {
		const theirs = reach(clash);
		const both = theirs.filter((t) => mine.has(t));
		throw new RunError(
			both.length
				? `${both.join(' and ')} is already being set up in "${clash.label}".`
				: `"${clash.label}" uses every tool, so it has to finish first.`,
			409
		);
	}
	if (kind === 'build' && !opts.script) throw new RunError('A build run needs the setup repository.', 400);
	fs.mkdirSync(RUNS_DIR, { recursive: true });
	const id = newId();
	const script = opts.script ?? path.join(PIPELINE_ROOT, SCRIPTS[kind as keyof typeof SCRIPTS]);
	const shown = opts.shown ?? `./${path.basename(script)}`;

	// stdin is /dev/null so a prompting script reads EOF instead of waiting.
	const child = spawn(
		'bash',
		['-c', 'bash "$0" "$@" > "$MARGIE_GUI_LOG" 2>&1 < /dev/null; echo $? > "$MARGIE_GUI_RC"', script, ...args],
		{
			cwd: opts.cwd ?? PIPELINE_ROOT,
			env: { ...pipelineEnv(), ...opts.env, MARGIE_GUI_LOG: logPath(id), MARGIE_GUI_RC: rcPath(id), NO_COLOR: '1' },
			detached: true,
			stdio: 'ignore'
		}
	);
	child.unref();

	const run: Run = {
		id,
		kind,
		label,
		args,
		command: [shown, ...args].join(' '),
		started: new Date().toISOString(),
		pid: child.pid,
		status: 'running',
		...(opts.tools?.length ? { tools: opts.tools } : {}),
		...(opts.files?.length ? { files: opts.files } : {}),
		...(opts.outputDir ? { outputDir: opts.outputDir } : {})
	};
	writeIndex([...readIndex(), run]);
	return run;
}

/**
 * Run progress (0-100) derived from the log, cached until the log grows; long
 * logs are read as head (genome list, totals) plus tail (current position).
 */
const progressSeen = new Map<string, { size: number; value: RunProgress }>();

/** Reads the head and tail of a log, or the whole log when it is small. */
function logEnds(id: string, size: number): { head: string; tail: string } {
	const WHOLE = 4 * 1024 * 1024;
	if (size <= WHOLE) {
		const { text } = readLog(id, 0, WHOLE);
		return { head: text, tail: text };
	}
	return { head: readLog(id, 0, 64 * 1024).text, tail: readLog(id, size - 256 * 1024, 256 * 1024).text };
}

/**
 * Returns the genomes a run worked on: its recorded file names, else those in
 * annotate.sh's "[annotate] N genome(s): ..." line (without extensions).
 */
export function runFiles(run: Run): string[] {
	if (run.files?.length) return run.files;
	if (run.kind !== 'annotate') return [];
	const { size } = readLog(run.id, 0, 0);
	if (!size) return [];
	return readLog(run.id, 0, 64 * 1024).text.match(/\[annotate\] \d+ genome\(s\): (.+)/)?.[1].trim().split(/\s+/) ?? [];
}

export interface RunProgress {
	percent: number;
	/** What the number means in the run's own words: "62%", "321 MB", or ''. */
	text: string;
}

/** Returns why a run failed: the last error line in its log, else its last printed line. */
export function runReason(run: Run): string {
	if (run.status === 'cancelled') return 'Stopped by hand.';
	if (run.status !== 'failed') return '';
	const { size } = readLog(run.id, 0, 0);
	const code = run.exitCode == null ? 'It stopped without writing an exit code.' : `Exit code ${run.exitCode}.`;
	if (!size) return code;
	const tail = readLog(run.id, Math.max(0, size - 64 * 1024), 64 * 1024)
		.text.split('\n')
		.map((l) => l.trim())
		.filter(Boolean)
		.filter((l) => !l.startsWith('[gui]'));
	// An error block starts with the reason and follows with advice; the first line is kept.
	const bad = (l: string) =>
		/(ERROR|Error\b|error:|FAIL|fail(ed|s)\b|Traceback|no database|not found|No such file|missing|could not|cannot|unable|refus|denied|invalid|unknown option)/i.test(l);
	const near = tail.slice(-40);
	const said = near.find(bad);
	return (said ?? tail.at(-1) ?? code).slice(0, 400);
}

export function runProgressDetail(run: Run): RunProgress {
	if (run.status === 'completed') return { percent: 100, text: '' };
	const { size } = readLog(run.id, 0, 0);
	if (!size) return { percent: 0, text: '' };
	const seen = progressSeen.get(run.id);
	if (seen && seen.size === size) return seen.value;
	const { head, tail } = logEnds(run.id, size);
	const d = detailOf(run, head, tail);
	const value = { percent: Math.max(0, Math.min(99, Math.round(d.percent))), text: d.text };
	progressSeen.set(run.id, { size, value });
	return value;
}

export function runProgress(run: Run): number {
	return runProgressDetail(run).percent;
}

/** Returns the last match of a repeated pattern as a number. */
function lastNumber(text: string, re: RegExp): number | null {
	const all = [...text.matchAll(re)];
	if (!all.length) return null;
	const n = Number(all[all.length - 1][1].replace(/,/g, ''));
	return Number.isFinite(n) ? n : null;
}

/** Formats bytes as whole megabytes, e.g. "321 MB". */
function mb(bytes: number): string {
	const gb = bytes / 1024 ** 3;
	return gb >= 1 ? `${gb.toFixed(1)} GB` : `${Math.round(bytes / 1024 ** 2)} MB`;
}

function detailOf(run: Run, head: string, tail: string): RunProgress {
	if (run.kind === 'annotate') {
		const genomes = head.match(/\[annotate\] (\d+) genome\(s\): (.+)/);
		if (!genomes) return { percent: 3, text: 'preparing' }; // the genome table first
		const list = genomes[2].trim().split(/\s+/);
		// A gene-calls-only run has one step per genome and no scoring to count.
		if (run.args.includes('--genes-only')) {
			const started = [...tail.matchAll(/\[annotate\] gene calling \([^)]*\): (\S+)/g)].length;
			const at = Math.max(1, started);
			return { percent: ((at - 0.5) / list.length) * 100, text: `${Math.min(at, list.length)} of ${list.length} genomes` };
		}
		const p = annotateProgress(head === tail ? head : head + '\n' + tail);
		const done = p?.genomes.filter((g) => g.state === 'done').length ?? 0;
		return { percent: (p?.fraction ?? 0.03) * 100, text: p ? `${done} of ${p.genomes.length} genomes` : '' };
	}

	// Setup and build: one step per tool, from the tool list or the count the script prints.
	const planned = run.tools?.length || Number(head.match(/==> (\d+) (?:database|image)\(s\)/)?.[1]) || 0;
	// Counts over head and tail so progress never goes backwards on a long log.
	const seen = head === tail ? head : head + '\n' + tail;
	const done = new Set([...seen.matchAll(/^\[ *(?:ok|OK) *\] *([a-z0-9_-]+)/gm)].map((m) => m[1])).size;
	const started = [...seen.matchAll(/^==> (?:Fetching|Building): (\S+)/gm)].length;

	// wget prints a percentage only when the size is known; otherwise megabytes are shown.
	const pct = lastNumber(tail, /[\s.](\d{1,3})%\s/g);
	const kb = lastNumber(tail, /^\s*([\d,]+)K[\s.]/gm);
	const within = pct !== null ? Math.min(100, pct) / 100 : 0;
	const text = pct !== null ? `${Math.min(100, pct)}%` : kb !== null ? `${mb(kb * 1024)} fetched` : '';

	if (!planned) return { percent: run.status === 'running' ? (within || 0.5) * 100 : 0, text };
	// A download without a percentage counts as half its step.
	const at = Math.max(done, started ? started - 1 + (pct !== null ? within : 0.5) : 0);
	return { percent: (Math.min(planned, at) / planned) * 100, text };
}

/**
 * Clears finished runs from the history after copying their index entries,
 * logs and exit codes to run-history/<when>/; running runs stay.
 */
export function clearHistory(): { backup: string; removed: number; kept: number } {
	const runs = loadRuns();
	const keep = runs.filter((r) => r.status === 'running');
	const drop = runs.filter((r) => r.status !== 'running');
	const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
	const backup = path.join(PIPELINE_ROOT, 'run-history', stamp);
	if (drop.length) {
		fs.mkdirSync(backup, { recursive: true });
		fs.writeFileSync(path.join(backup, 'runs.json'), JSON.stringify(drop, null, 2) + '\n');
		fs.writeFileSync(path.join(backup, 'runs.tsv'), asTable(drop));
		for (const r of drop) {
			for (const from of [logPath(r.id), rcPath(r.id)]) {
				if (fs.existsSync(from)) fs.copyFileSync(from, path.join(backup, path.basename(from)));
			}
		}
		for (const r of drop) {
			for (const f of [logPath(r.id), rcPath(r.id)]) fs.rmSync(f, { force: true });
		}
		writeIndex(keep);
	}
	return { backup, removed: drop.length, kept: keep.length };
}

/** Formats the history as a TSV table for reading outside this app. */
function asTable(runs: Run[]): string {
	const cols = ['id', 'kind', 'label', 'tools', 'files', 'status', 'exitCode', 'started', 'finished', 'outputDir', 'command'];
	const cell = (r: Run, c: string) => {
		const v = (r as unknown as Record<string, unknown>)[c];
		return (Array.isArray(v) ? v.join(' ') : (v ?? '')).toString().replace(/[\t\n]/g, ' ');
	};
	return [cols.join('\t'), ...runs.map((r) => cols.map((c) => cell(r, c)).join('\t'))].join('\n') + '\n';
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function stopRun(id: string): Promise<Run> {
	const runs = loadRuns();
	const run = runs.find((r) => r.id === id);
	if (!run) throw new RunError('Run not found.', 404);
	if (run.status !== 'running') return run;

	const signal = (sig: NodeJS.Signals) => {
		try {
			process.kill(-(run.pid as number), sig); // the whole run: script, tools, containers' CLIs
		} catch {
			// Already gone.
		}
	};
	signal('SIGTERM');
	for (let i = 0; i < 20 && alive(run.pid); i++) await sleep(250);
	if (alive(run.pid)) signal('SIGKILL');

	if (readRc(id) === null) fs.writeFileSync(rcPath(id), '143\n');
	fs.appendFileSync(logPath(id), '\n[gui] Stopped by user.\n');
	run.status = 'cancelled';
	run.exitCode = 143;
	run.finished = new Date().toISOString();
	writeIndex(runs);
	return run;
}

/** Reads the log from byte `offset`, at most `max` bytes, for incremental polling. */
export function readLog(id: string, offset = 0, max = 512 * 1024): { text: string; offset: number; size: number } {
	let fd: number;
	try {
		fd = fs.openSync(logPath(id), 'r');
	} catch {
		return { text: '', offset: 0, size: 0 };
	}
	try {
		const size = fs.fstatSync(fd).size;
		const start = Math.min(Math.max(0, offset), size);
		const length = Math.min(max, size - start);
		const buf = Buffer.alloc(length);
		fs.readSync(fd, buf, 0, length, start);
		// Cut at the last newline so a line is never split across two polls.
		const cut = length === size - start ? length : buf.lastIndexOf(0x0a) + 1 || length;
		return { text: buf.subarray(0, cut).toString('utf8').replace(/\x1b\[[0-9;]*m/g, ''), offset: start + cut, size };
	} finally {
		fs.closeSync(fd);
	}
}

/** Returns the most recent step the run announced, from the end of its log. */
export function currentStep(id: string): string {
	const { size } = readLog(id, 0, 0);
	const { text } = readLog(id, Math.max(0, size - 64 * 1024), 64 * 1024);
	const lines = text.split('\n').reverse();
	const step = lines.find((l) => /^\[(annotate|setup|margie)\]\s/.test(l.trim()) || /^==> /.test(l.trim()));
	return step?.trim() ?? '';
}
