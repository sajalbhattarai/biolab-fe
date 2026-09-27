import { error, json } from '@sveltejs/kit';
import { DOMAINS, FileError, GENETIC_CODES, addGenome, gatherGenomes, listGenomes, removeGenome, writeGenomeMetadata } from '$lib/server/files';
import { setting } from '$lib/server/pipeline';
import type { RequestHandler } from './$types';

function fail(e: unknown): never {
	if (e instanceof FileError) error(e.status, e.message);
	throw e;
}

function view() {
	return { ...listGenomes(), runGtdbtk: setting('RUN_GTDBTK') === '1', domains: DOMAINS, geneticCodes: GENETIC_CODES };
}

export const GET: RequestHandler = async () => json(view());

/** Body: { rows: [{ name, domain, genetic_code }] } -- saves the genome table. */
export const PUT: RequestHandler = async ({ request }) => {
	const body = await request.json().catch(() => null);
	if (!body || !Array.isArray(body.rows)) error(400, 'Expected { rows: [...] }.');
	try {
		writeGenomeMetadata(body.rows.map((r: any) => ({ name: String(r.name), domain: String(r.domain ?? ''), genetic_code: String(r.genetic_code ?? '') })));
		return json(view());
	} catch (e) {
		fail(e);
	}
};

/**
 * Uploads genomes (multipart "files", optional overwrite=1), or with JSON
 * { gather: 'copy' | 'move', removeEmpty? } gathers nested genomes into the genomes folder.
 */
export const POST: RequestHandler = async ({ request }) => {
	if ((request.headers.get('content-type') ?? '').includes('application/json')) {
		const body = await request.json().catch(() => null);
		const mode = body?.gather;
		if (mode !== 'copy' && mode !== 'move') error(400, "Expected { gather: 'copy' | 'move' }.");
		try {
			const result = gatherGenomes(mode, body.removeEmpty === true);
			return json({ ...result, ...view() });
		} catch (e) {
			fail(e);
		}
	}
	const form = await request.formData();
	const files = form.getAll('files').filter((f): f is File => f instanceof File);
	if (files.length === 0) error(400, 'No files were sent.');
	const overwrite = form.get('overwrite') === '1';
	try {
		const added = [];
		for (const f of files) added.push(await addGenome(f, overwrite));
		return json({ added, ...view() });
	} catch (e) {
		fail(e);
	}
};

export const DELETE: RequestHandler = async ({ url }) => {
	try {
		removeGenome(url.searchParams.get('name') ?? '');
		return json(view());
	} catch (e) {
		fail(e);
	}
};
