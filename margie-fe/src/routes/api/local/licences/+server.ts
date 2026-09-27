import { error, json } from '@sveltejs/kit';
import { statementMatches } from '$lib/licence';
import { LICENCE_TOOLS, getSettings, readOverrides, recordLicenceAcceptance, writeOverrides } from '$lib/server/pipeline';
import type { RequestHandler } from './$types';

/**
 * Body: { intendedUse, accepted: { <tool>: boolean }, statement }. Saves the
 * licence settings (acceptance needs an intended use and the typed statement)
 * and records new acceptances in logs/.
 */
export const POST: RequestHandler = async ({ request }) => {
	const body = await request.json().catch(() => null);
	if (!body || typeof body.accepted !== 'object' || body.accepted === null) error(400, 'Expected { intendedUse, accepted, statement }.');
	const intendedUse = String(body.intendedUse ?? '').trim();
	const wanted = LICENCE_TOOLS.filter((t) => body.accepted[t] === true);

	const settings = getSettings().settings;
	const before = Object.fromEntries(settings.map((s) => [s.key, s.value]));
	const defaults = Object.fromEntries(settings.map((s) => [s.key, s.default]));
	const was = (t: string) => before[`LICENCE_AGREED_${t.toUpperCase()}`] === '1';
	const added = wanted.filter((t) => !was(t));

	if (wanted.length) {
		if (!intendedUse) error(400, 'Describe your intended use first.');
		// Newly accepted tools or a changed intended use require the typed statement.
		const changed = added.length > 0 || intendedUse !== (before.LICENCE_INTENDED_USE ?? '').trim();
		if (changed && !statementMatches(body.statement)) error(403, 'Type the licence statement exactly to accept.');
	}

	const overrides = readOverrides();
	overrides.LICENCE_INTENDED_USE = intendedUse;
	if (wanted.length && statementMatches(body.statement)) overrides.LICENCE_STATEMENT = String(body.statement).trim();
	if (!wanted.length) delete overrides.LICENCE_STATEMENT;
	for (const t of LICENCE_TOOLS) overrides[`LICENCE_AGREED_${t.toUpperCase()}`] = wanted.includes(t) ? '1' : '0';
	// Keeps only values that differ from the default, as PUT /api/settings does.
	for (const k of Object.keys(overrides)) if (k.startsWith('LICENCE_') && overrides[k] === defaults[k]) delete overrides[k];
	writeOverrides(overrides);
	recordLicenceAcceptance(added, intendedUse);
	return json({ ...getSettings(), added });
};
