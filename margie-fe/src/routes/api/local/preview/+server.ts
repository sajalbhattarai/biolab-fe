import { json } from '@sveltejs/kit';
import { spawnSync } from 'node:child_process';
import { PIPELINE_ROOT, pipelineEnv } from '$lib/server/pipeline';
import type { RequestHandler } from './$types';

/** Runs `./annotate.sh --list` to show the settings and organisms a run would use. */
export const GET: RequestHandler = async () => {
	const res = spawnSync('bash', ['./annotate.sh', '--list'], {
		cwd: PIPELINE_ROOT,
		env: { ...pipelineEnv(), NO_COLOR: '1' },
		encoding: 'utf8',
		timeout: 60_000
	});
	const output = `${res.stdout ?? ''}${res.stderr ?? ''}`
		.replace(/\x1b\[[0-9;]*m/g, '')
		.split('\n')
		.filter((l) => !l.startsWith('[log] '))
		.join('\n');
	return json({ ok: res.status === 0, output });
};
