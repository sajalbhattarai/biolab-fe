/**
 * Requests to MARGIE's API as the signed-in account. A 401 ends the session
 * here and sends the browser to the sign-in page.
 */

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
	goto('/login');
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
export async function call<T = any>(method: string, path: string, body?: unknown): Promise<T> {
	let res: Response;
	try {
		res = await fetch(`${getApiUrl()}${path}`, {
			method,
			headers: authHeaders(),
			body: body === undefined ? undefined : JSON.stringify(body)
		});
	} catch {
		throw new ApiError('MARGIE’s API cannot be reached. Is it running, and is the tunnel to it open?', 503);
	}
	if (res.status === 401) signedOut();
	const data = await res.json().catch(() => ({}));
	if (!res.ok) throw new ApiError(detailOf(data) ?? `Request failed (${res.status}).`, res.status);
	return data as T;
}

export const get = <T = any>(path: string) => call<T>('GET', path);
