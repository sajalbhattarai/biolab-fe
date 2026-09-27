/**
 * Folder locations for the desktop app. Everything writable lives under
 * Application Support and Logs, since the signed .app bundle is read-only.
 * ~/.config/margie/margie.env stays shared with the `margie` terminal launcher.
 */

import { app } from './electron.js';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));

/** ~/Library/Application Support/MARGIE */
export const DATA_DIR = app.getPath('userData');

/** hpc-connect.sh's pid, marks, log and its two question folders. */
export const STATE_DIR = path.join(DATA_DIR, 'state');

/** The margie-pipeline local mode drives: the app's own copy (src/pipeline.js), or a clone. */
export const PIPELINE_HOME = path.join(DATA_DIR, 'margie-pipeline');

/**
 * The margie-pipeline code this app carries (scripts/stage.mjs), copied to
 * PIPELINE_HOME by src/pipeline.js: Contents/Resources/pipeline, or the
 * staging folder unpackaged.
 */
export const PIPELINE_BUNDLE = app.isPackaged
	? path.join(process.resourcesPath, 'pipeline')
	: path.resolve(HERE, '..', '.stage', 'pipeline');

/** ~/Library/Logs/MARGIE */
export const LOG_DIR = app.getPath('logs');

/**
 * The staged front-end: build/ (adapter-node output), scripts/ and production node_modules.
 * Packaged: Contents/Resources/gui, outside the asar so scripts keep their exec bit.
 * Unpackaged: the staging folder `npm run stage` fills.
 */
export const GUI_DIR = app.isPackaged
	? path.join(process.resourcesPath, 'gui')
	: path.resolve(HERE, '..', '.stage', 'gui');

export const SCRIPTS_DIR = path.join(GUI_DIR, 'scripts');
export const HANDLER = path.join(GUI_DIR, 'build', 'handler.js');

/** Creates the writable folders, with the permissions hpc.ts expects of them. */
export function ensureDirs() {
	fs.mkdirSync(DATA_DIR, { recursive: true });
	fs.mkdirSync(LOG_DIR, { recursive: true });
	// 0700: the askpass folder underneath carries ssh's questions.
	fs.mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 });
	try {
		fs.chmodSync(STATE_DIR, 0o700);
	} catch {
		// A pre-existing folder not owned by this user; hpc.ts reports it.
	}
}
