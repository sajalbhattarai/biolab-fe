/**
 * Requests to MARGIE's API as the signed-in account. A 401 ends the session
 * here and sends the browser to the sign-in page.
 */

import { HOSTED } from '$lib/hosted';
import { goto } from '$app/navigation';
import { ApiError } from '$lib/api';
import { authHeaders, clearToken } from '$lib/auth';
import { getApiUrl } from '$lib/config';
import { backend } from '$lib/workspace/backend.svelte';

/** Returns FastAPI's error `detail` (a string or a list of field errors) as text. */
function detailOf(data: unknown): string | null {
	const d = (data as { detail?: unknown })?.detail;
	if (typeof d === 'string') return d;
	if (Array.isArray(d)) return d.map((e) => (e as { msg?: string })?.msg ?? JSON.stringify(e)).join('; ');
	return null;
}

/** Clears the token, redirects to /login and throws a 401. */
function signedOut(): never {
	clearToken();
	backend.refresh();
	goto(HOSTED ? '/signin' : '/login');
	throw new ApiError('Your sign-in has ended. Sign in again to reach the cluster.', 401);
}

/** Returns the raw response (for files); throws on anything but success. */
export async function fetchRaw(path: string): Promise<Response> {
	const headers = authHeaders();
	delete headers['Content-Type'];
	const res = await fetch(`${getApiUrl()}${path}`, { headers });
	if (res.status === 401) signedOut();
	if (!res.ok) {
		const data = await res.json().catch(() => ({}));
		throw new ApiError(detailOf(data) ?? `Request failed (${res.status}).`, res.status);
	}
	return res;
}

/** Sends a JSON request and returns the parsed body; throws ApiError on failure. */
/** When the API last answered, ms. A POST after a quiet spell first wakes the connection (see call). */
let lastAnswer = 0;

export async function call<T = any>(method: string, path: string, body?: unknown): Promise<T> {
	let res: Response;
	// An idle connection may have been closed by the server; a GET is retried by the browser, a POST is
	// not. So before a POST after a quiet spell, a cheap GET takes the hit and leaves a fresh connection.
	if (method !== 'GET' && Date.now() - lastAnswer > 3000) {
		await fetch(`${getApiUrl()}/health`, { cache: 'no-store' }).catch(() => undefined);
	}
	const send = () =>
		fetch(`${getApiUrl()}${path}`, {
			method,
			headers: authHeaders(),
			body: body === undefined ? undefined : JSON.stringify(body)
		});
	try {
		try {
			res = await send();
		} catch (first) {
			// A tunnel refuses a connection now and then; one retry covers that. A repeat is reported.
			if (method !== 'GET') throw first;
			await new Promise((r) => setTimeout(r, 400));
			res = await send();
		}
	} catch (e) {
		const why = e instanceof Error && e.message && e.message !== 'Failed to fetch' ? ` (${e.message})` : '';
		throw new ApiError(`MARGIE’s API at ${getApiUrl() || location.origin} did not answer ${method} ${path}${why}. Is the HPC still connected? Reconnect from the start page.`, 503);
	}
	lastAnswer = Date.now();
	if (res.status === 401) signedOut();
	const data = await res.json().catch(() => ({}));
	if (!res.ok) throw new ApiError(detailOf(data) ?? `Request failed (${res.status}).`, res.status);
	return data as T;
}

export const get = <T = any>(path: string) => call<T>('GET', path);
