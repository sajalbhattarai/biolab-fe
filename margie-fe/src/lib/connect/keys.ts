/**
 * Passwordless SSH for MARGIE: a dedicated key on this computer, its public half
 * on the HPC. Every step runs scripts/margie-key.sh, shared with setup.sh --hpc.
 */

import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { DEFAULT_KEY, SCRIPTS, expandHome } from './settings';
import { bashPath, scriptCommand } from './shell';

export interface KeyStatus {
	path: string;
	exists: boolean;
	/** The public half, as it appears in authorized_keys. */
	pub: string;
}

/** Runs margie-key.sh with the given arguments and collects its output. */
function run(args: string[], timeout = 45_000): Promise<{ ok: boolean; out: string }> {
	return new Promise((resolve, reject) => {
		let cmd: string, argv: string[];
		try {
			// Paths are converted to the form the script's bash reads.
			[cmd, argv] = scriptCommand(path.join(SCRIPTS, 'margie-key.sh'), args.map(bashPath));
		} catch (e) {
			return reject(e);
		}
		execFile(cmd, argv, { timeout, env: process.env, windowsHide: true }, (err, stdout, stderr) =>
			resolve({ ok: !err, out: `${stdout}${stderr}`.trim() })
		);
	});
}

/** Returns the key's path, whether it exists and its public half. */
export function keyStatus(key = DEFAULT_KEY): KeyStatus {
	const p = expandHome(key || DEFAULT_KEY);
	let pub = '';
	try {
		pub = fs.readFileSync(`${p}.pub`, 'utf8').trim();
	} catch {
		// Not made yet.
	}
	return { path: p, exists: fs.existsSync(p) && !!pub, pub };
}

/** Creates the key with ssh-keygen through margie-key.sh. */
export async function createKey(key = DEFAULT_KEY): Promise<KeyStatus> {
	const r = await run(['create', expandHome(key)]);
	if (!r.ok) throw new Error(r.out || 'ssh-keygen could not make the key.');
	return keyStatus(key);
}

/** Adds the key to the HPC over an open, signed-in connection: nothing more to type. */
export async function installKey(host: string, socket: string, key = DEFAULT_KEY): Promise<'added' | 'already'> {
	const r = await run(['install', host, expandHome(key), socket]);
	if (!r.ok) throw new Error(r.out || `Could not add the key on ${host}.`);
	return r.out.includes('already') ? 'already' : 'added';
}

/** Checks whether the key alone signs in, with no prompt. */
export async function verifyKey(host: string, key = DEFAULT_KEY): Promise<boolean> {
	return (await run(['verify', host, expandHome(key)])).ok;
}

/** Returns the private half for the backend's registration; never sent to the browser. */
export function privateKey(key = DEFAULT_KEY): string {
	return fs.readFileSync(expandHome(key), 'utf8');
}
