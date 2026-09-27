import { error, json } from '@sveltejs/kit';
import { currentStep, getRun, readLog, runProgressDetail } from '$lib/server/runs';
import { toolClock } from '$lib/server/toolClock';
import type { RequestHandler } from './$types';

/**
 * Returns the run, its latest step, and its log from ?offset= or its last
 * ?tail= bytes; annotation runs also carry their tool clock.
 */
export const GET: RequestHandler = async ({ params, url }) => {
	const run = getRun(params.id);
	if (!run) error(404, 'Run not found.');
	const offset = Number(url.searchParams.get('offset') ?? 0) || 0;
	const tail = Number(url.searchParams.get('tail') ?? 0) || 0;
	const size = tail ? readLog(run.id, 0, 0).size : 0;
	const log = tail ? readLog(run.id, Math.max(0, size - tail), tail) : readLog(run.id, offset);
	const p = runProgressDetail(run);
	const clock = run.kind === 'annotate' ? toolClock(Date.parse(run.started), run.finished ? Date.parse(run.finished) : undefined) : null;
	return json({ run: { ...run, progress: p.percent, progressText: p.text }, step: currentStep(run.id), log, clock });
};
