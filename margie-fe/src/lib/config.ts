/**
 * Where MARGIE's API lives: on the HPC, reached through the launcher's SSH
 * tunnel on localhost:8000, or same-origin when hosted. Local runs use /crisp
 * and routes/api/local instead, so getApiUrl() always means the cluster.
 */

import { browser } from '$app/environment';

export type BackendMode = 'cluster' | 'local';

const MODE_KEY = 'margie_mode';
/** Keys from an older version of this app, cleared when seen. */
const STALE_KEYS = ['margie_local_api', 'margie_local_backend_path'];

function read(key: string): string | null {
	try {
		return localStorage.getItem(key);
	} catch {
		return null;
	}
}

function write(key: string, value: string | null): void {
	try {
		if (value === null) localStorage.removeItem(key);
		else localStorage.setItem(key, value);
	} catch {
		// Private mode or blocked storage: the mode is not persisted.
	}
}

function clusterApiUrl(): string {
	const fromEnv = import.meta.env.VITE_PUBLIC_API_URL as string | undefined;
	if (fromEnv) return fromEnv;
	return ['localhost', '127.0.0.1', '0.0.0.0'].includes(window.location.hostname)
		? 'http://localhost:8000'
		: '';
}

/**
 * Returns 'cluster', clearing any stored "local" mode left by an older version.
 */
export function getBackendMode(): BackendMode {
	if (!browser) return 'cluster';
	if (read(MODE_KEY)) useClusterBackend();
	return 'cluster';
}

export function getApiUrl(): string {
	if (!browser) return '';
	return clusterApiUrl();
}

export function useClusterBackend(): void {
	write(MODE_KEY, null);
	for (const key of STALE_KEYS) write(key, null);
}
