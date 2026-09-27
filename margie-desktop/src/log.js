/**
 * Writes the main process log to main.log in the Logs folder (and to stderr),
 * since a packaged app has no terminal. Help -> "Open Log Folder" opens it.
 */

import fs from 'node:fs';
import path from 'node:path';
import { LOG_DIR } from './paths.js';

const FILE = path.join(LOG_DIR, 'main.log');
const MAX_BYTES = 5 * 1024 * 1024;

let stream = null;

// Opens the log file for appending, rotating it to main.log.1 past MAX_BYTES.
function open() {
	if (stream) return stream;
	try {
		fs.mkdirSync(LOG_DIR, { recursive: true });
		// Keeps one previous log.
		try {
			if (fs.statSync(FILE).size > MAX_BYTES) fs.renameSync(FILE, `${FILE}.1`);
		} catch {
			// No log yet.
		}
		stream = fs.createWriteStream(FILE, { flags: 'a' });
	} catch {
		// A read-only or missing Logs folder must not stop the app starting.
		stream = null;
	}
	return stream;
}

// Formats one timestamped line and writes it to the file and stderr.
function write(level, args) {
	const line = `${new Date().toISOString()} ${level} ${args
		.map((a) => (a instanceof Error ? (a.stack ?? a.message) : typeof a === 'string' ? a : JSON.stringify(a)))
		.join(' ')}\n`;
	try {
		open()?.write(line);
	} catch {
		// Logging never makes the app fail.
	}
	// stderr is where `npm start` shows it during development.
	process.stderr.write(line);
}

export const log = {
	info: (...a) => write('INFO ', a),
	warn: (...a) => write('WARN ', a),
	error: (...a) => write('ERROR', a),
	file: FILE
};
