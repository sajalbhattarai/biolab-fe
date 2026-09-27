/**
 * Restores the terminal's PATH for an app launched from Finder, which only gets launchd's
 * minimal PATH, so local mode can find Homebrew, Docker and Apple's `container`.
 */

import { execFile } from 'node:child_process';
import os from 'node:os';
import { log } from './log.js';

/** Places macOS tooling really lives, merged in even if the shell is unhelpful. */
const FALLBACKS = [
	'/opt/homebrew/bin', // Homebrew, Apple silicon
	'/opt/homebrew/sbin',
	'/usr/local/bin', // Homebrew on Intel, and Docker Desktop's CLI shims
	'/usr/local/sbin',
	'/System/Cryptexes/App/usr/bin', // where macOS keeps `container`-adjacent tooling
	`${os.homedir()}/.local/bin`
];

/**
 * Runs the login shell once and reads its PATH.
 * -i makes it read .zshrc; the marker keeps shell greetings out of the parsed value.
 */
function pathFromLoginShell(timeoutMs = 3000) {
	return new Promise((resolve) => {
		const shell = process.env.SHELL || '/bin/zsh';
		const marker = '__MARGIE_PATH__';
		execFile(
			shell,
			['-ilc', `printf '%s%s%s' "${marker}" "$PATH" "${marker}"`],
			{ timeout: timeoutMs, encoding: 'utf8', env: { ...process.env, TERM: 'dumb' } },
			(err, stdout) => {
				if (err && !stdout) return resolve('');
				const m = String(stdout).match(new RegExp(`${marker}(.*?)${marker}`, 's'));
				resolve(m ? m[1].trim() : '');
			}
		);
	});
}

/**
 * Widens process.env.PATH with the login shell's PATH and FALLBACKS, adding entries only.
 * Best-effort: a shell that fails leaves just the fallbacks.
 */
export async function restoreUserPath() {
	// Windows apps already get the user's PATH, which is ';'-separated.
	if (process.platform === 'win32') return process.env.PATH;
	let shellPath = '';
	try {
		shellPath = await pathFromLoginShell();
	} catch (e) {
		log.warn('could not read PATH from the login shell:', e);
	}

	const seen = new Set();
	const merged = [];
	for (const part of [...shellPath.split(':'), ...(process.env.PATH ?? '').split(':'), ...FALLBACKS]) {
		const p = part.trim();
		if (p && !seen.has(p)) {
			seen.add(p);
			merged.push(p);
		}
	}
	process.env.PATH = merged.join(':');
	log.info('PATH:', process.env.PATH);
	return process.env.PATH;
}
