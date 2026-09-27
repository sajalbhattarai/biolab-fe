/**
 * Where MARGIE runs (local or HPC) and the paths it relies on. Server-side only.
 * Settings live in ~/.config/margie/margie.env, shared with setup.sh and the
 * launcher, one `export KEY='value'` line each.
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export type Target = '' | 'local' | 'hpc';

export interface ConnectSettings {
	target: Target;
	/** user@cluster.address */
	hpcHost: string;
	/** The backend's folder on the HPC. */
	backendDir: string;
	/** The key MARGIE signs in with, once one is set up. */
	sshKey: string;
	/** Keys used before, newest first, separated by | (offered on the start page). */
	recentKeys: string;
	/** A pipeline outside the app's own folder, if one was chosen. */
	pipelineRoot: string;
	/** The backend's repository and branch the HPC runs. */
	backendRepo: string;
	backendBranch: string;
	/** A checkout of that repository on this computer, to send the code from. */
	backendLocal: string;
	/** Where MARGIE's server runs on the HPC: '' the login node, '1' a compute node (a SLURM job). */
	compute: string;
	/** That job's cores, memory (GB), time limit (hours), partition and account. */
	computeCpus: string;
	computeMemGb: string;
	computeHours: string;
	computePartition: string;
	computeAccount: string;
	/** Passed to MARGIE's server on the HPC: the group's shared storage, where licence records are copied, and the operator named in them. */
	sharedRoot: string;
	licenceRecordsDir: string;
	operator: string;
}

const KEYS: Record<keyof ConnectSettings, string> = {
	target: 'MARGIE_TARGET',
	hpcHost: 'HPC_HOST',
	backendDir: 'BACKEND_DIR',
	sshKey: 'MARGIE_SSH_KEY',
	recentKeys: 'MARGIE_RECENT_KEYS',
	pipelineRoot: 'MARGIE_PIPELINE_ROOT',
	backendRepo: 'BACKEND_REPO_URL',
	backendBranch: 'BACKEND_BRANCH',
	backendLocal: 'MARGIE_BACKEND_LOCAL',
	compute: 'MARGIE_COMPUTE',
	computeCpus: 'MARGIE_COMPUTE_CPUS',
	computeMemGb: 'MARGIE_COMPUTE_MEM_GB',
	computeHours: 'MARGIE_COMPUTE_HOURS',
	computePartition: 'MARGIE_COMPUTE_PARTITION',
	computeAccount: 'MARGIE_COMPUTE_ACCOUNT',
	sharedRoot: 'MARGIE_SHARED_ROOT',
	licenceRecordsDir: 'LICENSE_RECORDS_DIR',
	operator: 'MARGIE_OPERATOR'
};

/** Default backend repository; hpc-connect.sh uses the same one. */
export const DEFAULT_BACKEND_REPO = 'https://github.com/sajalbhattarai/bioinformatics-tools.git';
/** The branch of DEFAULT_BACKEND_REPO the HPC runs unless another is chosen. */
export const DEFAULT_BACKEND_BRANCH = 'margie-backend';

export const CONFIG_FILE = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'margie', 'margie.env');
/** Holds hpc-connect.sh's pid, progress and ssh's pending prompts. */
export const STATE_DIR = process.env.MARGIE_STATE_DIR || path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state'), 'margie');
/** margie-fe, where the app runs from; its scripts sit beside it. */
export const APP_DIR = process.cwd();
export const SCRIPTS = path.join(APP_DIR, 'scripts');
export const DEFAULT_KEY = path.join(os.homedir(), '.ssh', 'margie_ed25519');

export const expandHome = (p: string) => (p.startsWith('~/') ? path.join(os.homedir(), p.slice(2)) : p);

/** Parses `export KEY='value'` lines into a map, undoing shell quoting. */
function parse(text: string): Record<string, string> {
	const out: Record<string, string> = {};
	for (const line of text.split('\n')) {
		const m = line.match(/^\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)='((?:[^']|'\\'')*)'\s*$/);
		if (m) out[m[1]] = m[2].replaceAll(`'\\''`, `'`);
	}
	return out;
}

/** Reads the settings file, falling back to environment variables of the same names. */
export function readSettings(): ConnectSettings {
	let file: Record<string, string> = {};
	try {
		file = parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
	} catch {
		// No file yet: environment values apply.
	}
	const get = (k: keyof ConnectSettings) => file[KEYS[k]] ?? process.env[KEYS[k]] ?? '';
	const target = get('target');
	return {
		target: target === 'local' || target === 'hpc' ? target : '',
		hpcHost: get('hpcHost'),
		backendDir: get('backendDir'),
		sshKey: get('sshKey'),
		recentKeys: get('recentKeys'),
		pipelineRoot: get('pipelineRoot'),
		backendRepo: get('backendRepo'),
		backendBranch: get('backendBranch'),
		backendLocal: get('backendLocal'),
		compute: get('compute') === '1' ? '1' : '',
		computeCpus: get('computeCpus'),
		computeMemGb: get('computeMemGb'),
		computeHours: get('computeHours'),
		computePartition: get('computePartition'),
		computeAccount: get('computeAccount'),
		sharedRoot: get('sharedRoot'),
		licenceRecordsDir: get('licenceRecordsDir'),
		operator: get('operator')
	};
}

const quote = (v: string) => `'${v.replaceAll(`'`, `'\\''`)}'`;

/** Merges changes into the settings and writes the file atomically (mode 600). */
export function writeSettings(changes: Partial<ConnectSettings>): ConnectSettings {
	const next = { ...readSettings(), ...changes };
	const lines = [
		"# MARGIE's settings (setup.sh and the app's start page keep these up to date).",
		...(Object.keys(KEYS) as (keyof ConnectSettings)[]).map((k) => `export ${KEYS[k]}=${quote(String(next[k] ?? ''))}`)
	];
	fs.mkdirSync(path.dirname(CONFIG_FILE), { recursive: true });
	const tmp = `${CONFIG_FILE}.tmp`;
	fs.writeFileSync(tmp, lines.join('\n') + '\n', { mode: 0o600 });
	fs.renameSync(tmp, CONFIG_FILE);
	return next;
}

/** Checks a user@host value before it reaches a shell script. */
export function validHost(v: string) {
	return /^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+$/.test(v);
}
/** Checks an absolute path with no quote or shell characters; ~ would not expand on the HPC. */
export function validRemotePath(v: string) {
	return /^\/[^\0'"`$\\\n]*$/.test(v);
}

/** Returns the recent-keys list with `key` moved to the front (at most five). */
export function withRecentKey(recent: string, key: string): string {
	return [key, ...recent.split('|')].filter((k, i, all) => k && all.indexOf(k) === i).slice(0, 5).join('|');
}

/** Validates the compute-node choice: whole numbers in range and plain SLURM names. */
export function cleanCompute(b: Record<string, unknown>): Partial<ConnectSettings> {
	const int = (v: unknown, lo: number, hi: number, name: string) => {
		const n = Number(v);
		if (!Number.isInteger(n) || n < lo || n > hi) throw new Error(`${name} should be a whole number from ${lo} to ${hi}.`);
		return String(n);
	};
	const name = (v: unknown, what: string) => {
		const s = String(v ?? '').trim();
		if (s && !/^[A-Za-z0-9_.-]{1,64}$/.test(s)) throw new Error(`The ${what} should be a SLURM name: letters, digits, _ . -`);
		return s;
	};
	return {
		compute: b.compute ? '1' : '',
		computeCpus: int(b.cpus ?? 4, 1, 256, 'Cores'),
		computeMemGb: int(b.memGb ?? 16, 1, 4096, 'Memory (GB)'),
		computeHours: int(b.hours ?? 8, 1, 336, 'Hours'),
		computePartition: name(b.partition, 'partition'),
		computeAccount: name(b.account, 'account')
	};
}
