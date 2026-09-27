import { error, json } from '@sveltejs/kit';
import { FileError, readText } from '$lib/server/files';
import type { RequestHandler } from './$types';

/** ?path= returns up to 1 MB of a text file, with a truncated flag. */
export const GET: RequestHandler = async ({ url }) => {
	try {
		return json(readText(url.searchParams.get('path') ?? ''));
	} catch (e) {
		if (e instanceof FileError) error(e.status, e.message);
		throw e;
	}
};
