import { error, json } from '@sveltejs/kit';
import { FileError, readPage } from '$lib/server/files';
import type { RequestHandler } from './$types';

/** ?path=&page=&page_size= returns one page of a (tabular) text file. */
export const GET: RequestHandler = async ({ url }) => {
	const page = Math.max(1, Number(url.searchParams.get('page')) || 1);
	const pageSize = Math.min(1000, Math.max(1, Number(url.searchParams.get('page_size')) || 100));
	try {
		return json(await readPage(url.searchParams.get('path') ?? '', page, pageSize));
	} catch (e) {
		if (e instanceof FileError) error(e.status, e.message);
		throw e;
	}
};
