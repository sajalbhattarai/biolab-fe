import { error, json } from '@sveltejs/kit';
import { RunError, stopRun } from '$lib/server/runs';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ params }) => {
	try {
		return json({ run: await stopRun(params.id) });
	} catch (e) {
		if (e instanceof RunError) error(e.status, e.message);
		throw e;
	}
};
