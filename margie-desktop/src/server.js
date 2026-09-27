/**
 * Runs margie-fe's adapter-node server inside the main process on a free 127.0.0.1 port.
 * The handler is imported after the environment and cwd are set, since both are read at module load.
 * The window must use 127.0.0.1 (not a custom protocol): lib/config.ts only uses the HPC tunnel on loopback hosts.
 */

import http from 'node:http';
import net from 'node:net';
import { pathToFileURL } from 'node:url';
import { GUI_DIR, HANDLER } from './paths.js';
import { log } from './log.js';

/** Asks the OS for a free port and releases it again. */
function reservePort() {
	return new Promise((resolve, reject) => {
		const probe = net.createServer();
		probe.unref();
		probe.on('error', reject);
		probe.listen(0, '127.0.0.1', () => {
			const { port } = probe.address();
			probe.close(() => resolve(port));
		});
	});
}

// Resolves once the server is listening on the loopback port, or rejects with the bind error.
function listen(server, port) {
	return new Promise((resolve, reject) => {
		const onError = (err) => {
			server.removeListener('listening', onOk);
			reject(err);
		};
		const onOk = () => {
			server.removeListener('error', onError);
			resolve();
		};
		server.once('error', onError);
		server.once('listening', onOk);
		// Loopback only: the server exposes file browsing and run controls.
		server.listen(port, '127.0.0.1');
	});
}

/**
 * Starts the front-end server, retrying on a port taken between probe and bind.
 * @param {Record<string,string>} env  extra variables the server should see
 * @returns {Promise<{ server: http.Server, port: number, url: string }>}
 */
export async function startServer(env) {
	// lib/connect/settings.ts derives APP_DIR and SCRIPTS from process.cwd().
	process.chdir(GUI_DIR);
	Object.assign(process.env, env);

	let lastError;
	for (let attempt = 0; attempt < 5; attempt++) {
		const port = await reservePort();
		// adapter-node reads these once, when build/env.js is first imported.
		process.env.PORT = String(port);
		process.env.HOST = '127.0.0.1';
		process.env.ORIGIN = `http://127.0.0.1:${port}`;

		// Dynamic import, after the environment is set; cached on retries, where only listen repeats.
		const { handler } = await import(pathToFileURL(HANDLER).href);
		const server = http.createServer(handler);
		try {
			await listen(server, port);
			log.info(`front-end listening on http://127.0.0.1:${port} (cwd ${process.cwd()})`);
			return { server, port, url: `http://127.0.0.1:${port}` };
		} catch (err) {
			// The port was taken between probing and binding.
			lastError = err;
			if (err?.code !== 'EADDRINUSE') throw err;
			log.warn(`port ${port} was taken between probing and binding; trying another`);
		}
	}
	throw lastError ?? new Error('could not find a free port for the front-end');
}

// Closes the server, dropping keep-alive connections; resolves within two seconds.
export function stopServer(server) {
	return new Promise((resolve) => {
		if (!server) return resolve();
		server.close(() => resolve());
		server.closeAllConnections?.();
		setTimeout(resolve, 2000).unref?.();
	});
}
