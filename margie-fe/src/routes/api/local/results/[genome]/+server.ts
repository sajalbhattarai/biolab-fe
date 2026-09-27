import { error, json } from '@sveltejs/kit';
import { genomeSummary } from '$lib/server/results';
import type { RequestHandler } from './$types';

/** Returns one genome's report: FINAL-table counts, gene caller, figures and tools. */
export const GET: RequestHandler = async ({ params }) => {
	const summary = await genomeSummary(params.genome);
	if (!summary) error(404, `No final results for ${params.genome} yet.`);
	return json(summary);
};
