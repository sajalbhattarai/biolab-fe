import { error, json } from '@sveltejs/kit';
import { readUiDefault, readUiPrefs, writeUiPrefs } from '$lib/server/ui';
import type { RequestHandler } from './$types';

/** Returns { prefs (null before the first save), default (the default look, or {}) }. */
export const GET: RequestHandler = async () => json({ prefs: readUiPrefs(), default: readUiDefault() });

/** Saves the preferences in body { prefs: { ... } }. */
export const PUT: RequestHandler = async ({ request }) => {
	const body = await request.json().catch(() => null);
	if (!body || typeof body.prefs !== 'object') error(400, 'Expected { prefs: { ... } }.');
	return json(writeUiPrefs(body.prefs));
};
