import { error, json } from '@sveltejs/kit';
import { cleanPlace, isUnlocked, passwordMatches, unlock } from '$lib/server/install-lock';
import type { RequestHandler } from './$types';

/** ?place=local|user@host -> { unlocked } */
export const GET: RequestHandler = async ({ url }) => {
	const place = cleanPlace(url.searchParams.get('place'));
	if (!place) error(400, 'Expected ?place=local or user@host.');
	return json({ unlocked: isUnlocked(place) });
};

/** Body: { place, password }. Unlocks Install for that place. */
export const POST: RequestHandler = async ({ request }) => {
	const body = await request.json().catch(() => null);
	const place = cleanPlace(body?.place);
	if (!place) error(400, 'Expected { place, password }.');
	if (!passwordMatches(body.password)) error(403, 'That does not match the statement. Type it exactly as shown.');
	unlock(place);
	return json({ unlocked: true });
};
