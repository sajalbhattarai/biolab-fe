import { json } from '@sveltejs/kit';
import { setting } from '$lib/server/pipeline';
import { coverage, inspectSetupRepo } from '$lib/server/setupRepo';
import type { RequestHandler } from './$types';

/** ?path= checks a folder as the setup repository (default: the saved one) and lists what it can and cannot build. */
export const GET: RequestHandler = async ({ url }) => {
	const repo = inspectSetupRepo(url.searchParams.get('path') ?? setting('SETUP_REPO'));
	return json({ ...repo, coverage: repo.ok ? coverage(repo) : null });
};
