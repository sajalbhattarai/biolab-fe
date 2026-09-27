/**
 * Electron main process for MARGIE: widens PATH, installs the bundled pipeline, starts the
 * margie-fe server on a loopback port and opens a window on it. All MARGIE logic stays in
 * margie-fe; this file handles the window, menu, tray, run watching and a clean quit.
 */

import { app, BrowserWindow, dialog, shell } from './electron.js';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { ensureDirs, DATA_DIR, LOG_DIR, STATE_DIR, PIPELINE_HOME, GUI_DIR } from './paths.js';
import { log } from './log.js';
import { restoreUserPath } from './shell-env.js';
import { readMargieEnv, expandHome, isPipeline } from './settings.js';
import { installBundledPipeline } from './pipeline.js';
import { startServer, stopServer } from './server.js';
import { stopHpc, hpcConnected } from './hpc.js';
import { buildMenu } from './menu.js';
import { loadWindowState, trackWindowState } from './window-state.js';
import { prefs } from './app-prefs.js';
import { createRunWatch } from './run-watch.js';
import { createTray } from './tray.js';
import { addGenomeFiles, pendingOpenFiles, rememberOpenFile } from './open-files.js';

/** Allows a single instance, which owns the state folder and the tunnel's port. */
if (!app.requestSingleInstanceLock()) {
	app.quit();
	process.exit(0);
}

let win = null;
let httpServer = null;
let appUrl = '';
let shuttingDown = false;
/** True while the quit question is on screen, so a second request does not stack another. */
let askingToQuit = false;
let watch = null;
let tray = null;

/**
 * Receives genomes opened from Finder or dropped on the Dock icon. Registered before
 * whenReady because macOS sends the launching file before the app is ready.
 */
app.on('open-file', (event, file) => {
	event.preventDefault();
	if (appUrl) void addGenomeFiles(appUrl, [file]);
	else rememberOpenFile(file);
});

/** Brings the window back, making one if it was closed. */
function showWindow() {
	if (!win || win.isDestroyed()) {
		if (appUrl) createWindow();
		return;
	}
	if (win.isMinimized()) win.restore();
	win.show();
	win.focus();
	app.focus({ steal: true });
}

// Shows the window and loads a route of the app.
function goTo(route) {
	showWindow();
	if (win && !win.isDestroyed()) win.loadURL(`${appUrl}${route}`);
}

/**
 * Returns back/forward helpers, using webContents.navigationHistory when present and the
 * older webContents.canGoBack()/goBack() otherwise.
 */
function nav() {
	const wc = win && !win.isDestroyed() ? win.webContents : null;
	if (!wc) return null;
	const h = wc.navigationHistory;
	return {
		canBack: () => (h?.canGoBack ? h.canGoBack() : (wc.canGoBack?.() ?? false)),
		back: () => (h?.goBack ? h.goBack() : wc.goBack?.()),
		canForward: () => (h?.canGoForward ? h.canGoForward() : (wc.canGoForward?.() ?? false)),
		forward: () => (h?.goForward ? h.goForward() : wc.goForward?.())
	};
}

export function goBack() {
	const n = nav();
	if (n?.canBack()) n.back();
}

export function goForward() {
	const n = nav();
	if (n?.canForward()) n.forward();
}

/** One rescue question at a time; stacked sheets freeze the window. */
let rescuing = false;

/**
 * Offers Go Back / Start Page / Stay Here for a page that cannot be shown,
 * since the window has no browser chrome.
 */
async function rescue(message, detail) {
	if (shuttingDown || rescuing || !win || win.isDestroyed()) return;
	const n = nav();
	const buttons = [...(n?.canBack() ? ['Go Back'] : []), 'Start Page', 'Stay Here'];
	rescuing = true;
	try {
		const { response } = await dialog.showMessageBox(win, {
			type: 'warning',
			message,
			detail,
			buttons,
			defaultId: 0,
			cancelId: buttons.length - 1
		});
		const choice = buttons[response];
		if (choice === 'Go Back') goBack();
		else if (choice === 'Start Page') goTo('/start');
	} catch (err) {
		log.warn('the rescue dialog failed:', err);
	} finally {
		rescuing = false;
	}
}

// ---- the environment the front-end runs in ----

/**
 * Returns the environment variables margie-fe reads (lib/connect/settings.ts, lib/server/pipeline.ts)
 * to use the app's state folder and pipeline.
 */
function frontEndEnv() {
	// A pipeline folder chosen in margie.env wins, so the app and the terminal launcher agree.
	const chosen = expandHome(readMargieEnv().MARGIE_PIPELINE_ROOT || '');
	const pipelineRoot = chosen && isPipeline(chosen) ? chosen : PIPELINE_HOME;
	if (chosen && chosen !== pipelineRoot) {
		log.warn(`the pipeline folder in margie.env is not a pipeline any more: ${chosen}`);
	}

	return {
		// hpc-connect.sh's pid, marks, log and question folders.
		MARGIE_STATE_DIR: STATE_DIR,
		// Where lib/server/pipeline.ts looks for the checkout...
		MARGIE_PIPELINE_ROOT: pipelineRoot,
		// ...and where lib/connect/local.ts clones one; outside the .app, which is read-only and signed.
		MARGIE_PIPELINE_HOME: PIPELINE_HOME,
		// Marks the front-end as running in the desktop app.
		MARGIE_DESKTOP: '1'
	};
}

// ---- the window ----

/** Height of the draggable strip reserved for the traffic lights when the title bar is hidden. */
const TITLEBAR = 34;
/** Height of MARGIE's own header (the Modern interface), where the traffic lights sit. */
const HEADER = 48;

/** The hidden title bar and the translucent background are macOS's alone. */
const IS_MAC = process.platform === 'darwin';

/**
 * Returns assets/titlebar.png (made by scripts/make-icon.mjs) as a cached data URI, or '' if missing.
 */
let logoUri = null;
function logo() {
	if (logoUri !== null) return logoUri;
	try {
		const file = path.join(path.dirname(fileURLToPath(import.meta.url)), 'assets', 'titlebar.png');
		logoUri = `data:image/png;base64,${fs.readFileSync(file).toString('base64')}`;
	} catch (err) {
		log.warn('no title-bar logo; run `npm run icon`:', err?.message ?? err);
		logoUri = '';
	}
	return logoUri;
}

/**
 * Injects the desktop-only CSS into the loaded page: with a hidden title bar, the app header
 * becomes the drag region and clears room for the traffic lights; with vibrancy, the shell
 * root's background is made slightly translucent so the blur shows through.
 */
async function dressWindow(target) {
	if (!target || target.isDestroyed()) return;
	const look = prefs();
	const css = [];

	// Both are macOS window features.
	if (IS_MAC && look.titleBar === 'hidden') {
		// The Modern header is the drag region, padded for the traffic lights except in full
		// screen (html.mg-fullscreen). Pages without it get a TITLEBAR-high strip, exposed as --mg-titlebar.
		css.push(`
			.crisp > header.bar {
				-webkit-app-region: drag;
				padding-left: 86px !important;
			}
			html.mg-fullscreen .crisp > header.bar {
				padding-left: 16px !important;
			}
			.crisp > header.bar :is(a, button, input, select, textarea, label, [role='menu'], [role='menuitem'], .hist, .jumps) {
				-webkit-app-region: no-drag;
			}
			body:not(:has(.crisp > header.bar)) {
				--mg-titlebar: ${TITLEBAR}px;
			}
			body:not(:has(.crisp > header.bar)) [data-mg-root] {
				box-sizing: border-box !important;
				padding-top: ${TITLEBAR}px !important;
			}
			body:not(:has([data-mg-root])) {
				padding-top: ${TITLEBAR}px !important;
			}
			body:not(:has(.crisp > header.bar))::before {
				content: '';
				position: fixed;
				top: 0;
				left: 0;
				right: 0;
				height: ${TITLEBAR}px;
				-webkit-app-region: drag;
				z-index: 2147483000;
				pointer-events: auto;
			}
		`);
	}

	if (IS_MAC && look.vibrancy) {
		css.push(`
			html, body { background: transparent !important; }
			[data-mg-root] {
				background-color: color-mix(in srgb, var(--mg-bg) 82%, transparent) !important;
			}
		`);
	}

	if (!css.length) return;
	try {
		await target.webContents.insertCSS(css.join('\n'));
	} catch (err) {
		log.warn('could not apply the desktop styling:', err);
	}
}

// Creates the main window with the saved bounds and look, and wires navigation, logging and rescue handlers.
function createWindow() {
	const state = loadWindowState();

	const look = prefs();
	const hiddenBar = IS_MAC && look.titleBar === 'hidden';
	const vibrancy = IS_MAC && look.vibrancy;

	win = new BrowserWindow({
		...state,
		minWidth: 960,
		minHeight: 640,
		show: false,
		title: 'MARGIE',
		// With the title bar hidden the traffic lights sit over MARGIE's own header.
		titleBarStyle: hiddenBar ? 'hiddenInset' : 'default',
		// Centred on MARGIE's header row (48px); the lights are about 14px tall.
		...(hiddenBar ? { trafficLightPosition: { x: 16, y: Math.round((HEADER - 14) / 2) } } : {}),
		// Vibrancy shows through where the injected CSS makes the shell translucent.
		...(vibrancy ? { vibrancy: 'sidebar', visualEffectState: 'followWindow' } : {}),
		// Transparent with vibrancy; otherwise dark, to avoid a white flash before the first paint.
		backgroundColor: vibrancy ? '#00000000' : '#0b0f14',
		webPreferences: {
			contextIsolation: true,
			nodeIntegration: false,
			sandbox: true,
			spellcheck: false,
			zoomFactor: 1
		}
	});

	if (state.maximized) win.maximize();
	trackWindowState(win);

	win.once('ready-to-show', () => win?.show());

	// Desktop styling is injected here, not in margie-fe (shared with the browser and pipeline GUI),
	// and re-applied on every load because insertCSS does not survive navigation.
	win.webContents.on('did-finish-load', () => {
		dressWindow(win);
		markFullScreen();
	});
	// Tells the page when full screen hides the traffic lights, so its header takes the room back.
	const markFullScreen = () => {
		if (!win || win.isDestroyed()) return;
		const on = win.isFullScreen();
		void win.webContents
			.executeJavaScript(`document.documentElement.classList.toggle('mg-fullscreen', ${on})`)
			.catch(() => {});
	};
	win.on('enter-full-screen', markFullScreen);
	win.on('leave-full-screen', markFullScreen);

	// External links open in the default browser.
	win.webContents.setWindowOpenHandler(({ url }) => {
		if (/^https?:\/\//i.test(url)) void shell.openExternal(url);
		return { action: 'deny' };
	});

	win.webContents.on('will-navigate', (event, url) => {
		if (!url.startsWith(appUrl)) {
			event.preventDefault();
			if (/^https?:\/\//i.test(url)) void shell.openExternal(url);
		}
	});

	// Renderer warnings and errors go to the log, the only place a client-side startup failure shows.
	win.webContents.on('console-message', (...args) => {
		const d = args[0];
		// Newer Electron passes one details object; older passes (event, level, message, line, sourceId).
		const isDetails = d && typeof d === 'object' && 'message' in d;
		const level = String(isDetails ? d.level : args[1]);
		const message = isDetails ? d.message : args[2];
		const source = isDetails ? `${d.sourceId}:${d.lineNumber}` : `${args[4]}:${args[3]}`;
		if (/error|warn|3|2/.test(level)) log.warn(`renderer [${level}] ${message}  (${source})`);
	});

	win.webContents.on('did-fail-load', (_e, code, description, url) => {
		if (code === -3) return; // an aborted load, which is normal on navigation
		log.error(`the page failed to load: ${description} (${code}) ${url}`);
		void rescue(`MARGIE could not open that page.`, `${description} (${code})`);
	});

	// A navigation that lands on an error status (e.g. 500 before the pipeline is fetched)
	// offers the rescue dialog, since the window has no Back button.
	win.webContents.on('did-navigate', (_e, url, httpResponseCode, httpStatusText) => {
		if (httpResponseCode < 400) return;
		log.warn(`navigated to ${url} which answered ${httpResponseCode} ${httpStatusText}`);
		void rescue(
			`That page is not available (${httpResponseCode}).`,
			httpResponseCode >= 500
				? 'This usually means MARGIE has not been set up for this computer yet — the pipeline it drives has not been fetched. The start page can do that.'
				: httpStatusText
		);
	});

	// Mouse back and forward buttons.
	win.on('app-command', (_e, command) => {
		if (command === 'browser-backward') goBack();
		if (command === 'browser-forward') goForward();
	});

	win.webContents.on('render-process-gone', (_e, details) => {
		log.error('the window crashed:', JSON.stringify(details));
		if (shuttingDown) return;
		dialog
			.showMessageBox({
				type: 'error',
				message: 'MARGIE stopped responding.',
				detail: `The window closed unexpectedly (${details.reason}). Reopening it will not affect a run already under way, on this computer or on the HPC.`,
				buttons: ['Reopen', 'Quit'],
				defaultId: 0
			})
			.then(({ response }) => (response === 0 ? createWindow() : app.quit()));
	});

	win.on('closed', () => (win = null));

	// launch=1 (as `margie` passes) makes the start page resume the last choice.
	win.loadURL(`${appUrl}/start?launch=1`);
}

// ---- starting up ----

// Prepares folders, PATH and pipeline, closes a leftover HPC connection, starts the server,
// run watcher, menu, window and tray, then adds any files opened at launch.
async function start() {
	ensureDirs();
	log.info('—'.repeat(60));
	log.info(`MARGIE ${app.getVersion()} starting (Electron ${process.versions.electron}, Node ${process.versions.node})`);
	log.info(`front-end   ${GUI_DIR}`);
	log.info(`data        ${DATA_DIR}`);

	// Before anything spawns git, ssh, docker or container.
	await restoreUserPath();

	// The pipeline local mode runs: the app's bundled copy.
	try {
		log.info(`pipeline    ${installBundledPipeline()}`);
	} catch (e) {
		log.warn(`could not put the bundled pipeline in place: ${e?.message ?? e}`);
	}

	// Every launch starts disconnected; a connection left by a crash or force-quit is closed.
	if (hpcConnected()) {
		log.info('an HPC connection from the last session is still open; closing it');
		try {
			await stopHpc();
		} catch (err) {
			log.warn('while closing the last session’s HPC connection:', err);
		}
	}

	const env = frontEndEnv();
	log.info(`pipeline    ${env.MARGIE_PIPELINE_ROOT}`);

	const started = await startServer(env);
	httpServer = started.server;
	appUrl = started.url;

	app.setAboutPanelOptions({
		applicationName: 'MARGIE',
		applicationVersion: app.getVersion(),
		version: `Electron ${process.versions.electron}`,
		credits: 'Mostly Automated Rapid Genome Inference Environment'
	});

	// One poll of the local API feeds the Dock badge, notifications, tray and keep-awake.
	watch = createRunWatch({ appUrl, getWindow: () => win });
	watch.start();

	buildMenu({ getWindow: () => win, appUrl, watch, showWindow, goTo, relook, goBack, goForward });
	createWindow();

	if (prefs().tray) tray = createTray({ watch, showWindow, goTo });

	// Files opened before the server was up.
	const opened = pendingOpenFiles();
	if (opened.length) void addGenomeFiles(appUrl, opened);
}

/**
 * Rebuilds the window at the same route after a look change, since titleBarStyle and
 * vibrancy are fixed when a BrowserWindow is created.
 */
function relook() {
	if (!win || win.isDestroyed()) {
		createWindow();
		return;
	}
	const here = win.webContents.getURL() || `${appUrl}/start?launch=1`;
	const old = win;
	win = null;
	old.destroy();
	createWindow();
	if (win && here.startsWith(appUrl)) win.loadURL(here);
}

app.whenReady().then(start).catch(fatal);

// Logs a startup failure, offers the log folder and exits.
function fatal(err) {
	log.error('MARGIE could not start:', err);
	dialog.showMessageBoxSync({
		type: 'error',
		message: 'MARGIE could not start.',
		detail: `${err?.message ?? err}\n\nThe details are in:\n${log.file}`,
		buttons: ['Open Log Folder', 'Quit'],
		defaultId: 0
	}) === 0 && shell.openPath(LOG_DIR);
	app.exit(1);
}

process.on('uncaughtException', (err) => {
	log.error('uncaught exception:', err);
	if (!shuttingDown && !app.isReady()) fatal(err);
});
process.on('unhandledRejection', (reason) => log.error('unhandled rejection:', reason));

// ---- shutting down ----
// Mirrors the EXIT trap in scripts/margie.sh: stopping hpc-connect.sh closes the tunnel and the cluster backend.

// Asks before disconnecting an HPC connection, then stops run watching, the HPC connection and the server, and exits.
async function shutdown() {
	// askingToQuit stops a second quit request from stacking a second modal sheet.
	if (shuttingDown || askingToQuit) return;

	if (hpcConnected()) {
		// A sheet on a hidden window would be invisible, so it attaches only to a visible one.
		const parent = win && !win.isDestroyed() && win.isVisible() ? win : undefined;
		askingToQuit = true;
		let response;
		try {
			({ response } = await dialog.showMessageBox(parent, {
				type: 'question',
				message: 'Quit MARGIE and disconnect from the HPC?',
				detail:
					'This closes the connection and stops MARGIE’s backend on the cluster. Jobs already queued or running under SLURM are not affected — they carry on, and will be there when you reconnect.',
				buttons: ['Quit', 'Cancel'],
				defaultId: 0,
				cancelId: 1
			}));
		} finally {
			askingToQuit = false;
		}
		if (response === 1) return;
	}

	shuttingDown = true;
	// Releases keep-awake and the Dock state first, in case a later step is slow.
	try {
		watch?.stop();
		tray?.destroy();
	} catch (err) {
		log.warn('while stopping the desktop services:', err);
	}
	try {
		await stopHpc();
	} catch (err) {
		log.error('while closing the HPC connection:', err);
	}
	try {
		await stopServer(httpServer);
	} catch (err) {
		log.error('while stopping the front-end:', err);
	}
	log.info('MARGIE stopped');
	app.exit(0);
}

app.on('before-quit', (event) => {
	if (shuttingDown) return;
	event.preventDefault();
	void shutdown();
});

// On macOS closing the window keeps the app (and any HPC connection) running.
app.on('window-all-closed', () => {
	if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
	if (!win && appUrl) createWindow();
});

app.on('second-instance', () => {
	if (win) {
		if (win.isMinimized()) win.restore();
		win.focus();
	} else if (appUrl) {
		createWindow();
	}
});

// Signal handlers for other platforms; on macOS Chromium swallows SIGINT/SIGTERM and every
// normal quit arrives as 'before-quit'. A connection left by a crash is closed on next launch.
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => void shutdown());
