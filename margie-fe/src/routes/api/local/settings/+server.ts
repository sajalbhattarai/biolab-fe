import { error, json } from '@sveltejs/kit';
import { getSettings, readOverrides, writeOverrides } from '$lib/server/pipeline';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async () => json(getSettings());

/**
 * Body: { values: { KEY: value }, merge?: true }. Empty or default values drop
 * the override. Without merge the body is the complete set of settings (keys
 * left out lose their override); with merge only the keys sent change.
 */
export const PUT: RequestHandler = async ({ request }) => {
	const body = await request.json().catch(() => null);
	if (!body || typeof body.values !== 'object') error(400, 'Expected { values: { KEY: value } }.');
	const current = getSettings().settings;
	const overrides: Record<string, string> = body.merge === true ? readOverrides() : {};
	for (const s of current) {
		const v = body.values[s.key];
		if (typeof v !== 'string') continue;
		const value = v.trim();
		// Licences are accepted via POST /api/licences; here they can only stay or be cleared.
		if (s.key === 'LICENCE_STATEMENT' && value !== s.value && value !== '') {
			error(403, 'Accept licences in the licence form, by typing the licence statement.');
		}
		if (s.key.startsWith('LICENCE_AGREED_') && value === '1' && s.value !== '1') {
			error(403, 'Accept licences in the licence form, by typing the licence statement.');
		}
		if (s.type === 'int' && value && !/^\d+$/.test(value)) error(400, `${s.label} must be a whole number.`);
		if (s.type === 'flag' && value && !['0', '1'].includes(value)) error(400, `${s.label} must be 0 or 1.`);
		if (s.type === 'choice' && value && !s.choices?.includes(value)) error(400, `${s.label} must be one of ${s.choices?.join(', ')}.`);
		// Keeps only values that differ from the default.
		if (value !== s.default) overrides[s.key] = value;
		else delete overrides[s.key];
	}
	writeOverrides(overrides);
	return json(getSettings());
};
