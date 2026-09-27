/**
 * Starts Electron for development with ELECTRON_RUN_AS_NODE removed.
 * Terminals hosted by Electron apps (e.g. VS Code) export that variable, which
 * would make the app start as plain Node with no window.
 */

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

// Required from Node, the npm package exports the path to the Electron binary.
const electronBinary = require('electron');

const env = { ...process.env };
if (env.ELECTRON_RUN_AS_NODE) {
	console.log('note: ELECTRON_RUN_AS_NODE was set in this shell; unsetting it for the app.');
	delete env.ELECTRON_RUN_AS_NODE;
}

const child = spawn(electronBinary, ['.', ...process.argv.slice(2)], { stdio: 'inherit', env });
child.on('close', (code, signal) => process.exit(code ?? (signal ? 1 : 0)));
