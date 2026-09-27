/**
 * Starts, watches and stops scripts/hpc-connect.sh, reading its state files in
 * STATE_DIR (pid, marks, log, askpass prompts, questions). ssh prompts reach the
 * start page through SSH_ASKPASS; on Windows, files replace signals and pipes.
 */

import { execFile, spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { APP_DIR, DEFAULT_KEY, SCRIPTS, STATE_DIR, expandHome, readSettings } from './settings';
import { IS_WINDOWS, bashPath, scriptCommand } from './shell';

export type Phase = 'idle' | 'connecting' | 'ready' | 'failed';

export interface HpcStatus {
	phase: Phase;
	/** Who started it: this app (its log is here) or `margie --hpc` in a terminal. */
	by: 'app' | 'terminal' | null;
	/** The steps reached so far, in order; the last is the one under way. */
	steps: { id: string; text: string }[];
	node: string;
	/** user@login-node the connection landed on. */
	host: string;
	socket: string;
	error: string;
	/** Prompts ssh is waiting on. */
	prompts: { id: string; text: string }[];
	/** Questions the script is asking, with the answers it accepts. */
	questions: { id: string; text: string; choices: { value: string; label: string }[] }[];
	log: string[];
	mode: 1 | 2;
}

const PIDFILE = path.join(STATE_DIR, 'hpc-connect.pid');
const MARKS = path.join(STATE_DIR, 'hpc-connect.marks');
const LOG = path.join(STATE_DIR, 'hpc-connect.log');
const ASK = path.join(STATE_DIR, 'askpass');
const QUESTIONS = path.join(STATE_DIR, 'questions');
const STOPFILE = path.join(STATE_DIR, 'hpc-connect.stop');
const PROMPT_ID = /^\d+-\d+$/;
const QUESTION_ID = /^[a-z-]{1,40}$/;

/** The connection this app started, remembered across module reloads. */
const mine = globalThis as unknown as { __margieHpc?: { pid: number; mode: 1 | 2 } };

/** Reads a file, or '' when it is missing. */
const read = (file: string) => {
	try {
		return fs.readFileSync(file, 'utf8');
	} catch {
		return '';
	}
};

/** Checks whether a process exists (signal 0). */
function alive(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}

/** Returns the script's pid while it runs, else null. */
function running(): number | null {
	const pid = Number(read(PIDFILE).trim());
	return pid > 0 && alive(pid) ? pid : null;
}

// Strips ANSI colours, box-drawing and carriage returns from the script's output.
const plain = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, '').replace(/─+/g, '').replace(/\r/g, '');

/** Builds the connection status from the script's state files. */
export function hpcStatus(): HpcStatus {
	const pid = running();
	const lines = read(MARKS).split('\n').filter(Boolean);
	const steps: HpcStatus['steps'] = [];
	let ready: string[] | null = null;
	let error = '';
	for (const l of lines) {
		const [kind, ...rest] = l.split(' ');
		if (kind === 'step') steps.push({ id: rest[0], text: rest.slice(1).join(' ') });
		else if (kind === 'ready') ready = rest;
		else if (kind === 'fail') error = rest.join(' ');
	}
	const by = pid ? (mine.__margieHpc?.pid === pid ? 'app' : 'terminal') : mine.__margieHpc ? 'app' : null;
	const phase: Phase = pid ? (ready ? 'ready' : 'connecting') : error ? 'failed' : 'idle';
	let prompts: HpcStatus['prompts'] = [];
	if (pid) {
		try {
			prompts = fs
				.readdirSync(ASK)
				.filter((f) => f.startsWith('prompt.') && PROMPT_ID.test(f.slice(7)))
				.map((f) => ({ id: f.slice(7), text: read(path.join(ASK, f)) }));
		} catch {
			// No prompts yet.
		}
	}
	let questions: HpcStatus['questions'] = [];
	if (pid) {
		try {
			questions = fs
				.readdirSync(QUESTIONS)
				.filter((f) => f.startsWith('question.') && QUESTION_ID.test(f.slice(9)))
				.map((f) => {
					// First line: value=Label|value=Label; the rest is the question.
					const [first, ...rest] = read(path.join(QUESTIONS, f)).split('\n');
					const choices = first.split('|').map((c) => {
						const [value, ...label] = c.split('=');
						return { value, label: label.join('=') || value };
					});
					return { id: f.slice(9), text: rest.join('\n').trim(), choices };
				});
		} catch {
			// No questions yet.
		}
	}
	const log =
		by === 'app'
			? plain(read(LOG))
					.split('\n')
					.map((l) => l.trimEnd())
					.filter((l) => l.trim())
					.slice(-160)
			: [];
	return {
		phase,
		by,
		steps,
		node: ready?.[0] ?? '',
		host: ready?.[1] ?? '',
		socket: ready?.[2] ?? '',
		error,
		prompts,
		questions,
		log,
		mode: mine.__margieHpc?.mode ?? 1
	};
}

/** Clears old state and starts hpc-connect.sh detached, with its settings in the environment. */
export function startHpc(o: {
	host: string;
	backendDir: string;
	mode: 1 | 2;
	key?: string;
	repo?: string;
	branch?: string;
	local?: string;
}): void {
	if (running()) throw new Error('A connection to the HPC is already open or being made. Stop it first.');
	fs.mkdirSync(ASK, { recursive: true, mode: 0o700 });
	fs.chmodSync(STATE_DIR, 0o700);
	fs.chmodSync(ASK, 0o700);
	fs.mkdirSync(QUESTIONS, { recursive: true, mode: 0o700 });
	for (const dir of [ASK, QUESTIONS]) for (const f of fs.readdirSync(dir)) fs.rmSync(path.join(dir, f), { force: true });
	fs.writeFileSync(MARKS, '');
	fs.rmSync(STOPFILE, { force: true });
	const out = fs.openSync(LOG, 'w', 0o600);
	// On Windows ssh cannot multiplex (MARGIE_NO_MUX), so a key is always used.
	const key = o.key ? expandHome(o.key) : IS_WINDOWS ? expandHome(DEFAULT_KEY) : '';
	const [cmd, args] = scriptCommand(path.join(SCRIPTS, 'hpc-connect.sh'));
	const child = spawn(cmd, args, {
		cwd: APP_DIR,
		// Its own session: no terminal, so ssh asks through SSH_ASKPASS; and
		// its own process group, so stopping it stops everything it started.
		detached: true,
		// On Windows, detached would otherwise open a console window.
		windowsHide: true,
		stdio: ['ignore', out, out],
		env: {
			...process.env,
			HPC_HOST: o.host,
			BACKEND_DIR: o.backendDir,
			MODE: String(o.mode),
			MARGIE_SSH_KEY: key && (IS_WINDOWS || fs.existsSync(key)) ? bashPath(key) : '',
			MARGIE_STATE_DIR: bashPath(STATE_DIR),
			MARGIE_ASKPASS_DIR: bashPath(ASK),
			MARGIE_QUESTION_DIR: bashPath(QUESTIONS),
			...(o.repo ? { BACKEND_REPO_URL: o.repo } : {}),
			...(o.branch ? { BACKEND_BRANCH: o.branch } : {}),
			...(o.local ? { MARGIE_BACKEND_LOCAL: bashPath(o.local) } : {}),
			// A compute node, when chosen (the header's Login node | Compute node).
			...computeEnv(),
			// The group's settings for MARGIE's server, when set.
			...serverEnv(),
			...(IS_WINDOWS ? { MARGIE_ASKPASS_POLL: '1', MARGIE_STOP_FILE: bashPath(STOPFILE), MARGIE_NO_MUX: '1' } : {}),
			SSH_ASKPASS: bashPath(path.join(SCRIPTS, 'margie-askpass.sh')),
			SSH_ASKPASS_REQUIRE: 'force',
			// OpenSSH before 8.4 only uses SSH_ASKPASS when DISPLAY is set.
			DISPLAY: process.env.DISPLAY || ':0'
		}
	});
	fs.closeSync(out);
	child.unref();
	if (child.pid) mine.__margieHpc = { pid: child.pid, mode: o.mode };
}

/** Answers (or, with cancel, declines) one of ssh's prompts. */
export function answerPrompt(id: string, text: string, cancel = false): void {
	if (!PROMPT_ID.test(id)) throw new Error('No such question.');
	if (/[\r\n]/.test(text)) throw new Error('An answer is one line.');
	const pipe = path.join(ASK, `answer.${id}`);
	const reply = `${cancel ? 'C' : 'A' + text}\n`;
	if (IS_WINDOWS) {
		// Windows has no shared named pipe: writes a temp file and renames it into place.
		if (!fs.existsSync(path.join(ASK, `prompt.${id}`))) throw new Error('That question was already answered, or has gone.');
		const tmp = path.join(ASK, `.answer.${id}`);
		fs.writeFileSync(tmp, reply, { mode: 0o600 });
		fs.renameSync(tmp, pipe);
		return;
	}
	if (!fs.existsSync(pipe)) throw new Error('That question was already answered, or has gone.');
	// The askpass helper holds the pipe open for reading, so this never waits.
	fs.writeFileSync(pipe, reply);
}

/** Answers one of the script's questions with one of its offered choices. */
export function replyQuestion(id: string, value: string): void {
	const q = hpcStatus().questions.find((x) => x.id === id);
	if (!q) throw new Error('That question was already answered, or has gone.');
	if (!q.choices.some((c) => c.value === value)) throw new Error('That is not one of the answers offered.');
	fs.writeFileSync(path.join(QUESTIONS, `reply.${id}`), `${value}\n`);
}

/** Stops the script; its exit handler stops the backend on the HPC and closes the tunnel. */
export async function stopHpc(): Promise<void> {
	const pid = running();
	if (!pid) return;
	// Declines pending ssh prompts first so nothing blocks.
	try {
		for (const f of fs.readdirSync(ASK)) if (f.startsWith('prompt.')) answerPrompt(f.slice(7), '', true);
	} catch {
		// Nothing pending.
	}
	if (IS_WINDOWS) {
		// A signal would skip bash's exit handler: asks via the stop file, then kills the tree.
		fs.writeFileSync(STOPFILE, '');
		for (let i = 0; i < 60 && alive(pid); i++) await new Promise((r) => setTimeout(r, 250));
		if (alive(pid)) await new Promise((r) => execFile('taskkill', ['/PID', String(pid), '/T', '/F'], { windowsHide: true }, r));
		return;
	}
	try {
		// Signals the whole process group; falls back to the pid when started from a terminal.
		process.kill(-pid, 'SIGTERM');
	} catch {
		process.kill(pid, 'SIGTERM');
	}
	for (let i = 0; i < 40 && alive(pid); i++) await new Promise((r) => setTimeout(r, 250));
	if (alive(pid)) process.kill(pid, 'SIGKILL');
}

/** Returns the compute-node settings as script environment; empty for the login node. */
function computeEnv(): Record<string, string> {
	const s = readSettings();
	if (s.compute !== '1') return {};
	return {
		MARGIE_COMPUTE: '1',
		...(s.computeCpus ? { MARGIE_COMPUTE_CPUS: s.computeCpus } : {}),
		...(s.computeMemGb ? { MARGIE_COMPUTE_MEM_GB: s.computeMemGb } : {}),
		...(s.computeHours ? { MARGIE_COMPUTE_HOURS: s.computeHours } : {}),
		...(s.computePartition ? { MARGIE_COMPUTE_PARTITION: s.computePartition } : {}),
		...(s.computeAccount ? { MARGIE_COMPUTE_ACCOUNT: s.computeAccount } : {})
	};
}

/** The group settings passed to MARGIE's server on the HPC (hpc-connect.sh exports them); only those set. */
function serverEnv(): Record<string, string> {
	const s = readSettings();
	return Object.fromEntries(
		(
			[
				['MARGIE_SHARED_ROOT', s.sharedRoot],
				['LICENSE_RECORDS_DIR', s.licenceRecordsDir],
				['MARGIE_OPERATOR', s.operator]
			] as const
		).filter(([, v]) => v)
	);
}
