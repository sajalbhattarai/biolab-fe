/**
 * Tracks where work runs: this computer (routes/api/local) or, when a token is stored,
 * the signed-in cluster (lib/cluster). margie-pipeline's GUI has a copy that is always local.
 */

import { browser } from '$app/environment';

const TOKEN_KEY = 'bsp_token';

function signedIn(): boolean {
	if (!browser) return false;
	try {
		return !!localStorage.getItem(TOKEN_KEY);
	} catch {
		return false;
	}
}

class Backend {
	/** True when a signed-in account's cluster does the work. */
	cluster = $state(signedIn());
	/** The cluster's login node, and the account on it, once known. */
	host = $state('');
	user = $state('');

	/** Re-reads the sign-in state after signing in or out. */
	refresh() {
		this.cluster = signedIn();
		if (!this.cluster) this.host = this.user = '';
	}

	/** Ends the session and goes to the sign-in page, where "Run MARGIE on this computer" also is. */
	signOut() {
		try {
			localStorage.removeItem(TOKEN_KEY);
		} catch {
			// nothing stored to remove
		}
		window.location.assign('/login');
	}

	/** "this computer" or "the cluster": how a sentence names where work runs. */
	get where() {
		return this.cluster ? 'the cluster' : 'this computer';
	}
}

export const backend = new Backend();
