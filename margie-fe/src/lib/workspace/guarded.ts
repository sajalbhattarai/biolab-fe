/**
 * Settings that ask before they change, such as the margie-build folder. The
 * browser-side phrase check guards against accidents, not attackers; the phrase
 * is stored as a SHA-256 digest because the repositories have public forks.
 */

/** Setting keys that need unlocking, and what to say when asking. */
export const GUARDED: Record<string, { title: string; why: string }> = {
	SETUP_REPO: {
		title: 'Unlock the build folder',
		why: 'This is where MARGIE looks for margie-build, which builds the container images and downloads the databases. Changing it redirects every build.'
	}
};

export const isGuarded = (key: string) => key in GUARDED;

/** Settings that unlock with a click after the page explains why and what is recommended. */
export const CONFIRMED: Record<string, { title: string; why: string }> = {
	'margie_sb.build_repo': {
		title: 'Change where margie-build is',
		why: 'Empty, MARGIE uses the lab’s copy on depot, or your own clone when the cluster has none (Install). Pointing it elsewhere changes how every container and database you set up is built.'
	},
	'margie_sb.backup_root': {
		title: 'Change where backups go',
		why: 'Backups of your databases go beside the base copies on depot. On a shared cluster, for a laboratory’s in-house studies, keeping them there is recommended: everyone’s work stays in one place, and depot is kept.'
	}
};

export const isConfirmed = (key: string) => key in CONFIRMED;

/** sha256('...'), so the phrase itself is not in a repository with public forks. */
const DIGEST = 'e31002dc901d5b260633f5f00e934a9bdd4b4e51ccd21b2972791ba0f8697444';

/** Checks whether the trimmed phrase unlocks the guarded settings. */
export async function unlocks(phrase: string): Promise<boolean> {
	const text = phrase.trim();
	if (!text) return false;
	try {
		const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
		const hex = [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join('');
		return hex === DIGEST;
	} catch {
		// No Web Crypto (e.g. an insecure origin): refusing keeps the field locked.
		return false;
	}
}
