import { error, json } from '@sveltejs/kit';
import { ChatError, ask, clearHistory, publicSettings, pullHpcKeys, readHistory, saveHpcKey, updateSettings, type Where } from '$lib/server/genome-chat';
import type { RequestHandler } from './$types';

/**
 * Chat with the genome (lib/server/genome-chat).
 *   GET    ?genome=g[&where=hpc]    -> { settings, keys (saved or not), providers, builtin, history }
 *   PUT    { provider?, model?, baseUrl?, budget?, answerTokens?, consented?, key?, keyFor? }
 *   POST   { genome, question, context?, remote? } -> the answer, with the evidence it read (context: what was open;
 *          remote: the genome's folders on the cluster and how to reach them, when it was annotated there)
 *   DELETE ?genome=g[&where=hpc]    -> forgets that genome's conversation
 * where=hpc is the conversation about a genome on the cluster, kept apart from one on this computer.
 */
const whereOf = (url: URL): Where => (url.searchParams.get('where') === 'hpc' ? 'hpc' : 'local');

const fail = (e: unknown): never => {
	if (e instanceof ChatError) error(e.status, e.message);
	throw e;
};

export const GET: RequestHandler = async ({ url }) => {
	try {
		const g = url.searchParams.get('genome');
		return json({ ...publicSettings(), history: g ? readHistory(g, whereOf(url)) : [] });
	} catch (e) {
		return fail(e);
	}
};

/**
 * PUT also takes the HPC's keys, through the app's connection (hpc: {api, token}):
 *   { hpcPull: true }                        read the keys kept in the HPC home
 *   { hpcKey: string | null, keyFor }        save (or remove) one there
 */
export const PUT: RequestHandler = async ({ request }) => {
	const body = (await request.json().catch(() => ({}))) ?? {};
	try {
		if (body.hpc && body.hpcPull) return json(await pullHpcKeys(body.hpc));
		if (body.hpc && 'hpcKey' in body) return json(await saveHpcKey(body.hpc, body.keyFor, body.hpcKey));
		return json(updateSettings(body));
	} catch (e) {
		return fail(e);
	}
};

export const POST: RequestHandler = async ({ request }) => {
	const body = await request.json().catch(() => ({}));
	try {
		return json({ answer: await ask(body?.genome, body?.question, body?.context, body?.remote ?? null) });
	} catch (e) {
		return fail(e);
	}
};

export const DELETE: RequestHandler = async ({ url }) => {
	try {
		clearHistory(url.searchParams.get('genome') ?? '', whereOf(url));
		return json({ ok: true });
	} catch (e) {
		return fail(e);
	}
};
