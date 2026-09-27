/**
 * The backend code the HPC will fetch from GitHub: repository, branch and the
 * local checkout, if any. Reports whether local work is pushed, and commits or
 * pushes only on request.
 */

import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { APP_DIR, DEFAULT_BACKEND_BRANCH, DEFAULT_BACKEND_REPO, expandHome, readSettings } from './settings';

export interface SourceStatus {
	repo: string;
	/** Short name, e.g. margie-backend. */
	name: string;
	branch: string;
	/** A checkout of it on this computer, whose branch is the one used; '' if none. */
	local: string;
	/** Whether GitHub has the branch at all; null when it could not be asked. */
	onGitHub: boolean | null;
	/** Commits here that GitHub does not have, and the other way round. */
	ahead: number;
	behind: number;
	/** Files changed or added and not committed, as `git status --short` puts them. */
	changes: string[];
	/** The commit the HPC will get. */
	target: string;
	/** Why GitHub could not be asked, if it could not. */
	note: string;
}

/** Normalises a git URL to host/owner/repo for comparison. */
const norm = (u: string) =>
	u
		.replace(/^(ssh:\/\/)?(git@|https?:\/\/)/, '')
		.replace(':', '/')
		.replace(/\.git\/?$/, '')
		.replace(/\/$/, '')
		.toLowerCase();
export const sameRepo = (a: string, b: string) => !!a && norm(a) === norm(b);

/** Runs git in a folder without ever prompting for credentials. */
function git(dir: string, args: string[], timeout = 60_000): Promise<{ ok: boolean; out: string }> {
	return new Promise((resolve) => {
		execFile('git', ['-C', dir, ...args], { timeout, env: { ...process.env, GIT_TERMINAL_PROMPT: '0' } }, (err, stdout, stderr) =>
			resolve({ ok: !err, out: `${stdout}${err ? stderr : ''}`.replace(/\s+$/, '') })
		);
	});
}

/** Returns a local checkout of the repository (chosen, or beside margie-frontend), or ''. */
async function localCheckout(repo: string): Promise<string> {
	const chosen = readSettings().backendLocal;
	for (const dir of [chosen ? expandHome(chosen) : '', path.resolve(APP_DIR, '..', '..', 'margie-backend')]) {
		if (!dir || !fs.existsSync(path.join(dir, '.git'))) continue;
		const origin = await git(dir, ['remote', 'get-url', 'origin']);
		if (origin.ok && sameRepo(origin.out, repo)) return dir;
	}
	return '';
}

/** Compares the local branch with origin; with `fetch`, asks GitHub for the latest first. */
export async function sourceStatus(fetch = false): Promise<SourceStatus> {
	const s = readSettings();
	const repo = s.backendRepo || DEFAULT_BACKEND_REPO;
	const local = await localCheckout(repo);
	const status: SourceStatus = {
		repo,
		name: norm(repo).split('/').at(-1) ?? repo,
		branch: s.backendBranch || DEFAULT_BACKEND_BRANCH,
		local,
		onGitHub: null,
		ahead: 0,
		behind: 0,
		changes: [],
		target: '',
		note: ''
	};
	if (!local) return status;

	if (!s.backendBranch) {
		const b = await git(local, ['rev-parse', '--abbrev-ref', 'HEAD']);
		if (b.ok && b.out !== 'HEAD') status.branch = b.out;
	}
	const br = status.branch;
	if (fetch) {
		const f = await git(local, ['fetch', '-q', 'origin', br]);
		if (!f.ok && !/couldn't find remote ref/i.test(f.out)) status.note = f.out.split('\n').at(-1) ?? 'GitHub could not be reached.';
	}
	const remote = await git(local, ['rev-parse', '-q', '--verify', `refs/remotes/origin/${br}^{commit}`]);
	status.onGitHub = remote.ok ? true : status.note ? null : false;
	status.target = remote.ok ? remote.out.slice(0, 9) : '';
	if (remote.ok) {
		const counts = await git(local, ['rev-list', '--left-right', '--count', `refs/heads/${br}...refs/remotes/origin/${br}`]);
		if (counts.ok) [status.ahead, status.behind] = counts.out.split(/\s+/).map(Number);
	} else {
		const all = await git(local, ['rev-list', '--count', `refs/heads/${br}`]);
		status.ahead = all.ok ? Number(all.out) : 0;
	}
	const changes = await git(local, ['status', '--short']);
	status.changes = changes.ok ? changes.out.split('\n').filter(Boolean).slice(0, 60) : [];
	return status;
}

/** Pushes the branch to GitHub, creating it there if new. */
export async function pushSource(): Promise<SourceStatus> {
	const st = await sourceStatus();
	if (!st.local) throw new Error('There is no checkout of the backend on this computer to push from.');
	const r = await git(st.local, ['push', '-u', 'origin', st.branch], 180_000);
	if (!r.ok) throw new Error(`git push did not work: ${r.out.split('\n').slice(-3).join(' ')}`);
	return sourceStatus(true);
}

/** Commits all changes with the given message, then pushes. */
export async function commitAndPush(message: string): Promise<SourceStatus> {
	const msg = message.trim();
	if (!msg) throw new Error('A commit needs a message saying what changed.');
	const st = await sourceStatus();
	if (!st.local) throw new Error('There is no checkout of the backend on this computer.');
	if (!st.changes.length) return pushSource();
	for (const args of [['add', '-A'], ['commit', '-q', '-m', msg]]) {
		const r = await git(st.local, args);
		if (!r.ok) throw new Error(`git ${args[0]} did not work: ${r.out.split('\n').slice(-3).join(' ')}`);
	}
	return pushSource();
}
