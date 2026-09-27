/**
 * Calls MARGIE's own HTTP API from the main process, the same API the pages use,
 * so run notifications, keep-awake and Dock progress need nothing from margie-fe.
 */

import { log } from './log.js';

/**
 * Returns a JSON fetcher bound to the local server, with a per-request timeout.
 * @param {string} baseUrl e.g. http://127.0.0.1:54321
 */
export function localApi(baseUrl) {
	/**
	 * @param {string} path
	 * @param {RequestInit & { timeoutMs?: number }} [init]
	 */
	return async function call(path, init = {}) {
		const { timeoutMs = 10000, ...rest } = init;
		// A hung request must not stall the poll loop.
		const abort = AbortSignal.timeout(timeoutMs);
		const res = await fetch(`${baseUrl}${path}`, { ...rest, signal: abort });
		if (!res.ok) throw new Error(`${path} returned ${res.status}`);
		return res.json();
	};
}

/** Awaits a promise and returns null on failure instead of throwing. */
export async function quiet(promise, what) {
	try {
		return await promise;
	} catch (err) {
		// Aborts and timeouts are expected (e.g. on quit) and go unlogged.
		if (err?.name !== 'AbortError' && err?.name !== 'TimeoutError') {
			log.warn(`${what} failed:`, err?.message ?? err);
		}
		return null;
	}
}
