/**
 * Reads and writes the interface's look and layout preferences in ~/.config/margie.
 * Browser storage does not survive launches because the app gets a new port each time.
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { lookOf, sanitizePrefs, type UiPrefs } from '$lib/workspace/prefs';

const DIR = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'margie');
const UI_FILE = path.join(DIR, 'ui.json');
/** The look saved with "Set as default", applied on every launch. */
const DEFAULT_FILE = path.join(DIR, 'ui-default.json');

function write(file: string, data: unknown) {
	fs.mkdirSync(DIR, { recursive: true });
	fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
}

/** Returns the saved preferences, or null when nothing has been saved. */
export function readUiPrefs(): UiPrefs | null {
	try {
		return sanitizePrefs(JSON.parse(fs.readFileSync(UI_FILE, 'utf8')));
	} catch {
		return null;
	}
}

/** Saves the full preference set and returns it as sanitized. */
export function writeUiPrefs(prefs: unknown): UiPrefs {
	const next = sanitizePrefs(prefs, readUiPrefs() ?? undefined);
	write(UI_FILE, next);
	return next;
}

/** Returns the default look, or {} when none is set. */
export function readUiDefault(): Partial<UiPrefs> {
	try {
		return lookOf(JSON.parse(fs.readFileSync(DEFAULT_FILE, 'utf8')));
	} catch {
		return {};
	}
}

/** Saves the look part of `prefs` as the default; `null` removes it. */
export function writeUiDefault(prefs: unknown): Partial<UiPrefs> {
	if (prefs === null) {
		fs.rmSync(DEFAULT_FILE, { force: true });
		return {};
	}
	const look = lookOf(prefs);
	write(DEFAULT_FILE, look);
	return look;
}
