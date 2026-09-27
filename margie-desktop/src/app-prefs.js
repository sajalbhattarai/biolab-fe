/**
 * The desktop app's own settings (title bar, tray, keep-awake, zoom), stored in
 * desktop-prefs.json. Separate from margie-fe's UI prefs because the main
 * process reads them before any page exists.
 */

import fs from 'node:fs';
import path from 'node:path';
import { DATA_DIR } from './paths.js';
import { log } from './log.js';

const FILE = path.join(DATA_DIR, 'desktop-prefs.json');

const DEFAULTS = {
	/** 'hidden' puts the traffic lights over MARGIE's own header; 'native' keeps a title bar. */
	titleBar: 'hidden',
	/** macOS translucency behind the window, visible where the page lets it through. */
	vibrancy: true,
	/** The menu bar status item. */
	tray: true,
	/** Notifies when a run finishes or fails. */
	notifications: true,
	/** Keeps the Mac awake while a run is going. */
	keepAwake: true,
	/** Remembered zoom, as Electron's zoom level (0 = 100%). */
	zoom: 0
};

const ALLOWED = {
	titleBar: (v) => (v === 'native' || v === 'hidden' ? v : null),
	vibrancy: (v) => (typeof v === 'boolean' ? v : null),
	tray: (v) => (typeof v === 'boolean' ? v : null),
	notifications: (v) => (typeof v === 'boolean' ? v : null),
	keepAwake: (v) => (typeof v === 'boolean' ? v : null),
	zoom: (v) => (typeof v === 'number' && v >= -5 && v <= 5 ? v : null)
};

let cache = null;

// Returns the saved settings merged over the defaults, each value checked by ALLOWED.
export function prefs() {
	if (cache) return cache;
	let saved = {};
	try {
		saved = JSON.parse(fs.readFileSync(FILE, 'utf8'));
	} catch {
		// Missing or invalid file: the defaults apply.
	}
	cache = { ...DEFAULTS };
	for (const [key, check] of Object.entries(ALLOWED)) {
		const value = check(saved?.[key]);
		if (value !== null) cache[key] = value;
	}
	return cache;
}

// Validates and saves one setting; returns the updated settings.
export function setPref(key, value) {
	if (!(key in ALLOWED)) throw new Error(`unknown setting: ${key}`);
	const checked = ALLOWED[key](value);
	if (checked === null) throw new Error(`${key} cannot be ${JSON.stringify(value)}`);
	cache = { ...prefs(), [key]: checked };
	try {
		fs.mkdirSync(DATA_DIR, { recursive: true });
		fs.writeFileSync(FILE, JSON.stringify(cache, null, '\t') + '\n');
	} catch (err) {
		log.warn('could not save the desktop settings:', err);
	}
	return cache;
}
