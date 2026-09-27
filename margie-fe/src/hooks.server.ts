import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type { HandleServerError } from '@sveltejs/kit';

/**
 * Logs an uncaught server error with its stack to ~/.local/state/margie/server-errors.log
 * and returns its message to the page instead of a bare "Internal Error".
 */
export const handleError: HandleServerError = ({ error, event, status, message }) => {
	const e = error instanceof Error ? error : new Error(String(error));
	try {
		const dir = path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state'), 'margie');
		fs.mkdirSync(dir, { recursive: true });
		fs.appendFileSync(
			path.join(dir, 'server-errors.log'),
			`${new Date().toISOString()} ${event.request.method} ${event.url.pathname} (${status})\n${e.stack ?? e.message}\n\n`
		);
	} catch {
		// Unwritable log: the page still gets the message.
	}
	console.error(e);
	return { message: status === 404 ? message : `Something went wrong: ${e.message}` };
};