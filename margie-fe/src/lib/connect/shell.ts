/**
 * Runs MARGIE's bash scripts (hpc-connect.sh, margie-key.sh). On Windows they go
 * through Git for Windows' bash (not WSL's), with paths converted to /c/... form.
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

export const IS_WINDOWS = process.platform === 'win32';

const GIT_BASH_HELP =
	'Connecting from Windows needs Git for Windows, whose bash runs the connection. Install it from https://git-scm.com/download/win and open MARGIE again.';

let found: string | null = null;

/** Returns Git for Windows' bash.exe, or throws with install instructions. */
export function gitBash(): string {
	if (found) return found;
	const candidates = [
		process.env.MARGIE_BASH,
		path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Git', 'bin', 'bash.exe'),
		path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Git', 'bin', 'bash.exe'),
		process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Programs', 'Git', 'bin', 'bash.exe')
	];
	// Also beside the git.exe on PATH: <Git>\cmd\git.exe -> <Git>\bin\bash.exe.
	try {
		const git = execFileSync('where', ['git'], { encoding: 'utf8', windowsHide: true }).split(/\r?\n/)[0]?.trim();
		if (git) candidates.push(path.join(path.dirname(path.dirname(git)), 'bin', 'bash.exe'));
	} catch {
		// No git on PATH.
	}
	found = candidates.find((c): c is string => !!c && fs.existsSync(c)) ?? null;
	if (!found) throw new Error(GIT_BASH_HELP);
	return found;
}

/** Converts a Windows path to Git Bash form (C:\a\b -> /c/a/b); other paths pass through. */
export function bashPath(p: string): string {
	if (!IS_WINDOWS || !p) return p;
	const m = /^([A-Za-z]):[\\/](.*)$/.exec(p);
	return m ? `/${m[1].toLowerCase()}/${m[2].replace(/\\/g, '/')}` : p.replace(/\\/g, '/');
}

/** Returns the command and argv that start a script (via Git Bash on Windows). */
export function scriptCommand(script: string, args: string[] = []): [string, string[]] {
	return IS_WINDOWS ? [gitBash(), [bashPath(script), ...args]] : [script, args];
}
