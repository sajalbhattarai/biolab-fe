import { json } from '@sveltejs/kit';
import { runCheck } from '$lib/server/pipeline';
import type { RequestHandler } from './$types';

/** Readiness report from the pipeline's own read-only ./check.sh. */
export const GET: RequestHandler = async () => {
	const { rows, header, raw } = await runCheck();
	return json({ rows, header, raw });
};
