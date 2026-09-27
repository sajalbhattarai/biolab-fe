/**
 * Install-page lock: typing the install statement (the licences and MARGIE's terms)
 * unlocks one place ('local' or user@host), recorded in ~/.config/margie/install-unlocked.json.
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { INSTALL_STATEMENT, normaliseStatement } from '$lib/workspace/install-statement';

const FILE = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'margie', 'install-unlocked.json');

/** A place is 'local' or user@host; anything else is not one. */
export function cleanPlace(v: unknown): string | null {
	const s = String(v ?? '').trim();
	return s === 'local' || /^[\w.-]+@[\w.-]+$/.test(s) ? s : null;
}

function places(): string[] {
	try {
		const d = JSON.parse(fs.readFileSync(FILE, 'utf8'));
		return Array.isArray(d.places) ? d.places.filter((p: unknown) => typeof p === 'string') : [];
	} catch {
		return [];
	}
}

export const isUnlocked = (place: string) => places().includes(place);

/** Whether the text given is the install statement. */
export function passwordMatches(given: unknown): boolean {
	return normaliseStatement(given) === normaliseStatement(INSTALL_STATEMENT);
}

/** Records the place as unlocked. */
export function unlock(place: string) {
	const now = places();
	if (now.includes(place)) return;
	fs.mkdirSync(path.dirname(FILE), { recursive: true });
	fs.writeFileSync(FILE, JSON.stringify({ places: [...now, place] }, null, 2) + '\n');
}
