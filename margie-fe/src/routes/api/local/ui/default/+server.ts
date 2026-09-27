import { error, json } from '@sveltejs/kit';
import { readUiDefault, writeUiDefault } from '$lib/server/ui';
import type { RequestHandler } from './$types';

/**
 * Reads, sets and clears the default look ("Set as default").
 *   GET               -> the default look ({} when none is set)
 *   PUT { prefs }     -> keeps the look part of prefs as the default
 *   DELETE            -> forgets it
 */
export const GET: RequestHandler = async () => json(readUiDefault());

export const PUT: RequestHandler = async ({ request }) => {
	const body = await request.json().catch(() => null);
	if (!body || typeof body.prefs !== 'object') error(400, 'Expected { prefs: { ... } }.');
	return json(writeUiDefault(body.prefs));
};

export const DELETE: RequestHandler = async () => json(writeUiDefault(null));
