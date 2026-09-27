import { error, json } from '@sveltejs/kit';
import { FileError, listDir, places, saveText } from '$lib/server/files';
import type { RequestHandler } from './$types';

function fail(e: unknown): never {
	if (e instanceof FileError) error(e.status, e.message);
	throw e;
}

/** ?path= lists a folder (default: the pipeline checkout); ?places=1 the starting points. */
export const GET: RequestHandler = async ({ url }) => {
	try {
		if (url.searchParams.get('places')) return json({ places: places() });
		return json(listDir(url.searchParams.get('path')));
	} catch (e) {
		fail(e);
	}
};

/** Body: { path, content } saves a text file. */
export const PUT: RequestHandler = async ({ request }) => {
	const body = await request.json().catch(() => null);
	if (!body || typeof body.path !== 'string' || typeof body.content !== 'string') {
		error(400, 'Expected { path, content }.');
	}
	try {
		saveText(body.path, body.content);
		return json({ saved: true });
	} catch (e) {
		fail(e);
	}
};
