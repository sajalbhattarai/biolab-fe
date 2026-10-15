/**
 * Client state for the Install lock of the current place ('local' or
 * user@host), checked by the server at clusterParts.lockApi. Every
 * installation asks for the password again via confirm() and InstallGate.
 */

import { HOSTED } from '$lib/hosted';
import { backend } from './backend.svelte';
import { clusterParts } from './cluster-parts';
import { INSTALL_STATEMENT, normaliseStatement } from './install-statement';

/** Hosted: places unlocked in this browser (the site has no server to keep them). */
const UNLOCKED_KEY = 'margie_install_unlocked';
function browserPlaces(): string[] {
	try {
		const v = JSON.parse(localStorage.getItem(UNLOCKED_KEY) ?? '[]');
		return Array.isArray(v) ? v.filter((p) => typeof p === 'string') : [];
	} catch {
		return [];
	}
}

class InstallLock {
	unlocked = $state(false);
	/** An installation waiting for the password: what it is, and how to answer. */
	request = $state<{ what: string; resolve: (password: string | null) => void } | null>(null);
	/** False until the server has answered for the place in use now. */
	known = $state(false);
	#asked = '';

	/** 'local', user@host once the cluster account is known, or '' until then. */
	get place(): string {
		if (!backend.cluster) return 'local';
		return backend.user && backend.host ? `${backend.user}@${backend.host}` : '';
	}

	/** Asks the server about the place in use now (once per place). */
	async check() {
		const place = this.place;
		if (!place || place === this.#asked) return;
		this.#asked = place;
		this.known = false;
		if (HOSTED) {
			this.unlocked = browserPlaces().includes(place);
			this.known = true;
			return;
		}
		try {
			const r = await fetch(`${clusterParts.lockApi}?place=${encodeURIComponent(place)}`);
			this.unlocked = r.ok && !!(await r.json()).unlocked;
		} catch {
			this.unlocked = false;
		}
		if (place === this.place) this.known = true;
	}

	/** Asks for the password before an installation; the password, or null when it was cancelled. */
	confirm(what: string): Promise<string | null> {
		this.request?.resolve(null);
		return new Promise((resolve) => {
			this.request = {
				what,
				resolve: (password) => {
					this.request = null;
					resolve(password);
				}
			};
		});
	}

	/** Tries a password; on success Install stays unlocked for this place. Returns an error to show, or ''. */
	async unlock(password: string): Promise<string> {
		const place = this.place;
		if (!place) return 'Still reaching the cluster; try again in a moment.';
		if (HOSTED) {
			if (normaliseStatement(password) !== normaliseStatement(INSTALL_STATEMENT)) return 'That does not match the statement. Type it exactly as shown.';
			try {
				localStorage.setItem(UNLOCKED_KEY, JSON.stringify([...new Set([...browserPlaces(), place])]));
			} catch {
				// Not remembered: the next installation asks again.
			}
			this.unlocked = true;
			this.known = true;
			return '';
		}
		try {
			const r = await fetch(clusterParts.lockApi, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ place, password })
			});
			if (r.ok) {
				this.unlocked = true;
				this.known = true;
				return '';
			}
			return r.status === 403 ? 'That does not match the statement. Type it exactly as shown.' : `Could not unlock (${r.status}).`;
		} catch {
			return 'Could not reach MARGIE to unlock.';
		}
	}
}

export const installLock = new InstallLock();
