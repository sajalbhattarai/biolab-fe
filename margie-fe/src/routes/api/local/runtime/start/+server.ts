import { error, json } from '@sveltejs/kit';
import { detectPlatform, startRuntime, type RuntimeId } from '$lib/server/platform';
import type { RequestHandler } from './$types';

/** Body: { id }. Starts an installed container runtime that is not running. */
export const POST: RequestHandler = async ({ request }) => {
	const { id } = await request.json().catch(() => ({}));
	const platform = await detectPlatform();
	const rt = platform.runtimes.find((r) => r.id === id);
	if (!rt) error(400, 'Unknown runtime.');
	if (!rt.installed) error(400, `${rt.label} is not installed.`);
	if (rt.running) return json({ ok: true, message: `${rt.label} is already running.` });
	return json(await startRuntime(id as RuntimeId));
};
