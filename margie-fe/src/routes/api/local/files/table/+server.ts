import { error, json } from '@sveltejs/kit';
import { FileError } from '$lib/server/files';
import { queryTable } from '$lib/server/tables';
import { queryFromParams } from '$lib/workspace/viewers/table-query';
import type { RequestHandler } from './$types';

/**
 * ?path=&sheet=&page=&size=&q=&sort=<col>:<asc|desc>&f<col>=<filter>
 * Returns one sorted, filtered page of a TSV, CSV, GFF or Excel file, with
 * column kinds and (Excel) cell colours.
 */
export const GET: RequestHandler = async ({ url }) => {
	try {
		return json(await queryTable(url.searchParams.get('path') ?? '', queryFromParams(url.searchParams)));
	} catch (e) {
		if (e instanceof FileError) error(e.status, e.message);
		throw e;
	}
};
