/**
 * Stops the HPC connection (scripts/hpc-connect.sh and its process group) when the app quits,
 * so its exit handler stops the cluster backend and the SSH tunnel.
 * Reads the pid and askpass files lib/connect/hpc.ts writes, since the server may already be closing.
 */

import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { STATE_DIR } from './paths.js';
import { log } from './log.js';

const PIDFILE = () => path.join(STATE_DIR, 'hpc-connect.pid');
const ASK = () => path.join(STATE_DIR, 'askpass');
const STOPFILE = () => path.join(STATE_DIR, 'hpc-connect.stop');
const IS_WINDOWS = process.platform === 'win32';

const alive = (pid) => {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
};

/** The pid of a live hpc-connect.sh, or null. */
export function hpcPid() {
	try {
		const pid = Number(fs.readFileSync(PIDFILE(), 'utf8').trim());
		return pid > 0 && alive(pid) ? pid : null;
	} catch {
		return null;
	}
}

export const hpcConnected = () => hpcPid() !== null;

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Stops the connection, giving the script time to run its own exit handler.
 * Pending ssh prompts are declined first by writing 'C' to the askpass helper's answer FIFO.
 */
export async function stopHpc() {
	const pid = hpcPid();
	if (!pid) return;
	log.info(`stopping the HPC connection (pid ${pid})`);

	try {
		for (const f of fs.readdirSync(ASK())) {
			if (!f.startsWith('prompt.')) continue;
			const pipe = path.join(ASK(), `answer.${f.slice(7)}`);
			// The helper holds the FIFO open read-write, so this does not block.
			// On Windows the helper watches for a plain file instead.
			try {
				if (IS_WINDOWS || fs.existsSync(pipe)) fs.writeFileSync(pipe, 'C\n');
			} catch {
				// Already answered, or gone.
			}
		}
	} catch {
		// No askpass folder: nothing was pending.
	}

	if (IS_WINDOWS) {
		// Windows cannot signal Git Bash's bash, so the script watches for the stop
		// file and exits through its own handler; taskkill follows after fifteen seconds.
		fs.writeFileSync(STOPFILE(), '');
		for (let i = 0; i < 60 && alive(pid); i++) await wait(250);
		if (alive(pid)) {
			log.warn(`HPC connection ${pid} did not stop in fifteen seconds; ending it`);
			await new Promise((r) => execFile('taskkill', ['/PID', String(pid), '/T', '/F'], { windowsHide: true }, r));
		}
		log.info('HPC connection closed');
		return;
	}

	try {
		// Negative pid signals the whole process group: script, ssh and tunnel.
		process.kill(-pid, 'SIGTERM');
	} catch {
		try {
			process.kill(pid, 'SIGTERM');
		} catch {
			return;
		}
	}

	for (let i = 0; i < 40 && alive(pid); i++) await wait(250);
	if (alive(pid)) {
		log.warn(`HPC connection ${pid} did not stop in ten seconds; killing it`);
		try {
			process.kill(-pid, 'SIGKILL');
		} catch {
			try {
				process.kill(pid, 'SIGKILL');
			} catch {
				// Gone between the check and the signal.
			}
		}
	}
	log.info('HPC connection closed');
}
