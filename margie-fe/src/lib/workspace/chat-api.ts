/**
 * Client calls for "Chat with the genome". The model call and keys stay on this
 * app's server (lib/server/genome-chat); for a cluster genome the question also
 * carries how to read its results there (clusterParts.chat).
 */

import { ApiError, api } from '$lib/api';
import { backend } from './backend.svelte';
import { clusterParts } from './cluster-parts';

const onCluster = () => backend.cluster && !!clusterParts.chat;

async function local<T>(method: string, query: string, body?: unknown): Promise<T> {
	const res = await fetch(`${clusterParts.chat!.url}${query}`, {
		method,
		headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
		body: body === undefined ? undefined : JSON.stringify(body)
	});
	const data = await res.json().catch(() => ({}));
	if (!res.ok) throw new ApiError(data.message ?? `Request failed (${res.status}).`, res.status);
	return data as T;
}

const g = (genome: string) => `?genome=${encodeURIComponent(genome)}`;

/** Whether chat can be used where MARGIE is working now. */
export const chatAvailable = () => !backend.cluster || !!clusterParts.chat;

/** Returns the app's HPC connection for keys kept there, or null when not connected. */
const link = () => (onCluster() ? (clusterParts.chat!.link?.() ?? null) : null);
/** Whether keys can be kept in the HPC home (connected to one, in the app). */
export const hpcKeysAvailable = () => !!link();

export async function chatGet<T extends object>(genome: string): Promise<T> {
	if (!onCluster()) return api<T>(`/genome-chat${g(genome)}`);
	const d = await local<T>('GET', `${g(genome)}&where=hpc`);
	// Keys in the HPC home are read once connected and held in server memory.
	const l = link();
	if (!l) return d;
	try {
		return { ...d, ...(await local<object>('PUT', '', { hpc: l, hpcPull: true })) } as T;
	} catch {
		return d;
	}
}

/** Saves (or, with null, removes) a key in the HPC home. */
export function chatHpcKey<T>(provider: string, key: string | null): Promise<T> {
	const l = link();
	if (!l) throw new ApiError('Not connected to the HPC.', 400);
	return local<T>('PUT', '', { hpc: l, hpcKey: key, keyFor: provider });
}

/** Reads the HPC home's keys again (after editing the file there by hand). */
export function chatHpcReload<T>(): Promise<T> {
	const l = link();
	if (!l) throw new ApiError('Not connected to the HPC.', 400);
	return local<T>('PUT', '', { hpc: l, hpcPull: true });
}

export function chatSettings<T>(body: unknown): Promise<T> {
	return onCluster() ? local<T>('PUT', '', body) : api<T>('/genome-chat', { method: 'PUT', body: JSON.stringify(body) });
}

export async function chatAsk<T>(genome: string, question: string, context: string): Promise<T> {
	if (!onCluster()) return api<T>('/genome-chat', { method: 'POST', body: JSON.stringify({ genome, question, context }) });
	const remote = await clusterParts.chat!.remote(genome);
	if (!remote) throw new ApiError(`No results for ${genome} on the cluster yet.`, 404);
	return local<T>('POST', '', { genome, question, context, remote });
}

export function chatForget(genome: string): Promise<unknown> {
	return onCluster() ? local('DELETE', `${g(genome)}&where=hpc`) : api(`/genome-chat${g(genome)}`, { method: 'DELETE' });
}
