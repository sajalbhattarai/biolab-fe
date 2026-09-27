/**
 * Resolves the Python for the host scripts (run-meta.sh) as host-python.sh
 * does: $MARGIE_PYTHON, else the venv at processing/.host-env.
 */

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { PIPELINE_ROOT, pipelineEnv } from './pipeline';

export interface HostPython {
	ready: boolean;
	version: string;
	path: string;
	/** When not ready: the Python 3.11+ the first run will make the venv from, if there is one. */
	base: { path: string; version: string } | null;
}

/** Finds the newest Python >= 3.11 on PATH, as host-python.sh's _host_py_candidates does. */
function basePython(env: NodeJS.ProcessEnv): HostPython['base'] {
	for (const name of ['python3.13', 'python3.12', 'python3.11', 'python3', 'python']) {
		const res = spawnSync(name, ['-c', 'import sys; print(sys.executable); print(sys.version.split()[0]); sys.exit(0 if sys.version_info >= (3, 11) else 1)'], {
			encoding: 'utf8',
			env,
			timeout: 10_000
		});
		if (res.status === 0) {
			const [exe, version] = (res.stdout ?? '').trim().split('\n');
			return { path: exe, version };
		}
	}
	return null;
}

let cache: { at: number; value: HostPython } | null = null;

export function hostPython(): HostPython {
	if (cache && Date.now() - cache.at < 60_000) return cache.value;
	const env = pipelineEnv();
	const candidate = env.MARGIE_PYTHON || path.join(PIPELINE_ROOT, 'processing', '.host-env', 'bin', 'python');
	let value: HostPython = { ready: false, version: '', path: candidate, base: null };
	if (fs.existsSync(candidate)) {
		const res = spawnSync(
			candidate,
			['-c', 'import sys, numpy, pandas, scipy, matplotlib, openpyxl; print(sys.version.split()[0])'],
			{ encoding: 'utf8', timeout: 30_000 }
		);
		if (res.status === 0) value = { ready: true, version: (res.stdout ?? '').trim(), path: candidate, base: null };
	}
	if (!value.ready && !env.MARGIE_PYTHON) value.base = basePython(env);
	cache = { at: Date.now(), value };
	return value;
}
