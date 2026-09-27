/**
 * Client for the interface's API: the same-origin routes under routes/api/local,
 * or the cluster (lib/cluster) when an account is signed in, with the same shapes.
 */

import { clusterApi, fileBlob } from '$lib/cluster/backend';
import { backend } from '$lib/workspace/backend.svelte';

export class ApiError extends Error {
	constructor(message: string, readonly status: number) {
		super(message);
	}
}

/** Base of the local runner's routes, which drive the bundled margie-pipeline. */
const API_BASE = '/api/local';

export async function api<T = any>(path: string, init: RequestInit = {}): Promise<T> {
	if (backend.cluster) return clusterApi<T>(path, init);
	const headers: Record<string, string> = { ...(init.headers as Record<string, string>) };
	if (init.body && typeof init.body === 'string') headers['Content-Type'] ??= 'application/json';
	const res = await fetch(`${API_BASE}${path}`, { ...init, headers });
	const data = await res.json().catch(() => ({}));
	if (!res.ok) throw new ApiError(data.message ?? `Request failed (${res.status}).`, res.status);
	return data as T;
}

export const post = <T = any>(path: string, body?: unknown) =>
	api<T>(path, { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) });

export const put = <T = any>(path: string, body: unknown) =>
	api<T>(path, { method: 'PUT', body: JSON.stringify(body) });

export const del = <T = any>(path: string) => api<T>(path, { method: 'DELETE' });

/**
 * Marker path for cluster file links. Nothing serves it: clicks are intercepted and
 * fetched with the sign-in (lib/cluster/downloads.ts); viewers use viewableUrl().
 */
export const CLUSTER_FILE = '/api/cluster/file';

/** Returns the URL that downloads (or, with inline, displays) a file. */
export function fileUrl(path: string, inline = false): string {
	const base = backend.cluster ? CLUSTER_FILE : `${API_BASE}/files/download`;
	return `${base}?path=${encodeURIComponent(path)}${inline ? '&inline=1' : ''}`;
}

const TYPES: Record<string, string> = {
	png: 'image/png',
	jpg: 'image/jpeg',
	jpeg: 'image/jpeg',
	gif: 'image/gif',
	webp: 'image/webp',
	svg: 'image/svg+xml',
	html: 'text/html',
	htm: 'text/html',
	pdf: 'application/pdf'
};

/** Returns a URL an <img> or <iframe> can load: `url` itself, or a blob copy of a cluster file. */
export async function viewableUrl(url: string): Promise<string> {
	if (!url.startsWith(CLUSTER_FILE)) return url;
	const path = new URL(url, location.origin).searchParams.get('path') ?? '';
	const blob = await fileBlob(path);
	const type = TYPES[path.split('.').pop()?.toLowerCase() ?? ''] ?? blob.type;
	return URL.createObjectURL(new Blob([blob], { type }));
}

export function formatBytes(n: number): string {
	if (n < 1024) return `${n} B`;
	const units = ['KB', 'MB', 'GB', 'TB'];
	let v = n / 1024;
	let i = 0;
	while (v >= 1024 && i < units.length - 1) {
		v /= 1024;
		i++;
	}
	return `${v.toFixed(v < 10 ? 1 : 0)} ${units[i]}`;
}

export interface Run {
	id: string;
	kind: 'annotate' | 'setup' | 'build';
	label: string;
	args: string[];
	/** How the command reads on screen, e.g. "./annotate.sh --tool pfam". */
	command?: string;
	started: string;
	finished?: string;
	status: 'running' | 'completed' | 'failed' | 'cancelled';
	exitCode?: number | null;
	/** The tools this run builds, downloads or annotates with. */
	tools?: string[];
	/** The genome files it was started on, by name. */
	files?: string[];
	/** Output folder of the run. */
	outputDir?: string;
	/** 0-100, parsed from its log. */
	progress?: number;
	/** Progress as the run reports it, e.g. "62%" or "321 MB fetched". */
	progressText?: string;
	/** Failure reason from the run; empty unless it failed. */
	reason?: string;
}
