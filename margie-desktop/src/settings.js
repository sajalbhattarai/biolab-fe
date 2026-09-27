/**
 * Reads ~/.config/margie/margie.env (written by margie-fe's connect/settings.ts and setup.sh)
 * so the server's MARGIE_PIPELINE_ROOT follows a pipeline folder chosen there.
 * Format: one `export KEY='value'` per line, with '\'' for a quote.
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const CONFIG_FILE = path.join(
	process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'),
	'margie',
	'margie.env'
);

export const expandHome = (p) => (p?.startsWith('~/') ? path.join(os.homedir(), p.slice(2)) : p || '');

// Parses margie.env into a key -> value object; {} when the file is missing.
export function readMargieEnv() {
	let text = '';
	try {
		text = fs.readFileSync(CONFIG_FILE, 'utf8');
	} catch {
		return {}; // Nothing chosen yet: the start page will ask.
	}
	const out = {};
	for (const line of text.split('\n')) {
		const m = line.match(/^\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)='((?:[^']|'\\'')*)'\s*$/);
		if (m) out[m[1]] = m[2].replaceAll(`'\\''`, `'`);
	}
	return out;
}

/** Tells whether a folder holds the pipeline, by the same two files lib/connect/local.ts checks. */
export const isPipeline = (dir) =>
	!!dir && fs.existsSync(path.join(dir, 'annotate.sh')) && fs.existsSync(path.join(dir, 'pipeline.conf.sh'));
