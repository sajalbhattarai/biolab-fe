/**
 * Finds the setup repository (margie-build), lists the images and databases
 * it can build, and compares them with what this pipeline needs.
 */

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { LICENCE_TOOLS, PIPELINE_ROOT, pipelineEnv } from './pipeline';

export interface BuildItem {
	name: string;
	/** Needs a licence accepted before it is built: gated by build.sh or by this pipeline. */
	gated: boolean;
	/** Gated by build.sh itself, which then takes --accept-<name>-licence. */
	buildGated: boolean;
}

export interface SetupRepoInfo {
	path: string;
	ok: boolean;
	reason?: string;
	containers: BuildItem[];
	databases: BuildItem[];
}

export interface Coverage {
	/** Needed by the pipeline but not buildable from the setup repository. */
	missingContainers: string[];
	missingDatabases: string[];
}

export function expandHome(p: string): string {
	const t = p.trim();
	if (t === '~' || t.startsWith('~/')) return path.join(os.homedir(), t.slice(1));
	return t;
}

export function inspectSetupRepo(raw: string): SetupRepoInfo {
	const dir = path.resolve(PIPELINE_ROOT, expandHome(raw || ''));
	const info: SetupRepoInfo = { path: dir, ok: false, containers: [], databases: [] };
	if (!raw.trim()) return { ...info, reason: 'No setup repository chosen yet.' };
	if (!fs.existsSync(dir)) return { ...info, reason: `Folder not found: ${dir}` };
	for (const need of ['build.sh', 'build-containers', 'build-databases']) {
		if (!fs.existsSync(path.join(dir, need))) {
			return { ...info, reason: `${dir} has no ${need}; it does not look like margie-build.` };
		}
	}
	// --list-tools only prints; it builds and accepts nothing. Its list goes to stderr.
	const res = spawnSync('bash', ['build.sh', '--list-tools'], {
		cwd: dir,
		env: { ...process.env, QUIET_NOTICE: '1', NO_COLOR: '1' },
		encoding: 'utf8',
		timeout: 30_000
	});
	const text = `${res.stdout ?? ''}${res.stderr ?? ''}`.replace(/\x1b\[[0-9;]*m/g, '');
	let section: 'containers' | 'databases' | null = null;
	for (const line of text.split('\n')) {
		if (line.startsWith('==> CONTAINERS')) section = 'containers';
		else if (line.startsWith('==> DATABASES')) section = 'databases';
		else if (line.startsWith('==>') || line.startsWith('[')) section = null;
		else if (section) {
			const m = line.match(/^\s{2}(\S+)\s+\S+(\s+\[licence-gated\])?\s*$/);
			if (m) info[section].push({ name: m[1], gated: !!m[2] || LICENCE_TOOLS.includes(m[1]), buildGated: !!m[2] });
		}
	}
	if (info.containers.length === 0 && info.databases.length === 0) {
		return { ...info, reason: `build.sh --list-tools listed nothing (exit ${res.status}).` };
	}
	return { ...info, ok: true };
}

/** Returns the images and databases the pipeline expects (pipeline.conf.sh's own lists). */
export function pipelineNeeds(): { containers: string[]; databases: string[] } {
	const res = spawnSync(
		'bash',
		[
			'-c',
			`set +u; . ./pipeline.conf.sh >/dev/null 2>&1; echo "\${all_tools[*]-}"; echo "\${all_dbs[*]-}"`
		],
		{ cwd: PIPELINE_ROOT, env: pipelineEnv(), encoding: 'utf8', timeout: 15_000 }
	);
	const [tools = '', dbs = ''] = (res.stdout ?? '').split('\n');
	const words = (s: string) => s.split(/\s+/).filter(Boolean);
	// Classification runs the gtdbtk image; llm and pangenome are optional (as in check.sh).
	const containers = [...new Set([...words(tools), 'gtdbtk'])];
	const databases = words(dbs).filter((d) => d !== 'llm' && d !== 'pangenome');
	return { containers, databases };
}

export function coverage(repo: SetupRepoInfo): Coverage {
	const needs = pipelineNeeds();
	const c = new Set(repo.containers.map((i) => i.name));
	const d = new Set(repo.databases.map((i) => i.name));
	return {
		missingContainers: needs.containers.filter((t) => !c.has(t)),
		missingDatabases: needs.databases.filter((t) => !d.has(t))
	};
}
