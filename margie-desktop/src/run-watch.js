/**
 * Polls GET /api/local/runs and reflects local runs in macOS: Dock badge and progress,
 * finish/fail notifications, and a sleep blocker while a run is going.
 */

import { app, BrowserWindow, Notification, powerSaveBlocker } from './electron.js';
import { localApi, quiet } from './local-api.js';
import { prefs } from './app-prefs.js';
import { log } from './log.js';

/** Poll intervals while a run is going and while idle. */
const BUSY_MS = 4000;
const IDLE_MS = 15000;

const isActive = (r) => r.status === 'running';

/**
 * Creates the run watcher; start() begins polling and onChange() subscribes to run lists.
 * @param {{ appUrl: string, getWindow: () => Electron.BrowserWindow|null }} ctx
 */
export function createRunWatch({ appUrl, getWindow }) {
	const api = localApi(appUrl);

	let timer = null;
	let stopped = false;
	/** Statuses from the previous poll, to spot the moment one changes. */
	let previous = new Map();
	/** False until the first poll, which records state without announcing it. */
	let seeded = false;
	let blocker = null;
	/** Latest runs, for the menu bar item to read. */
	let runs = [];
	const listeners = new Set();

	const emit = () => {
		for (const fn of listeners) {
			try {
				fn(runs);
			} catch (err) {
				log.warn('a run-watch listener threw:', err);
			}
		}
	};

	// ---------------------------------------------------------------- sleep

	/**
	 * Holds or releases a 'prevent-app-suspension' blocker (the display may still sleep),
	 * honouring the keepAwake setting.
	 */
	function holdSleep(wanted) {
		const active = wanted && prefs().keepAwake;
		if (active && blocker === null) {
			blocker = powerSaveBlocker.start('prevent-app-suspension');
			log.info('a run is going: holding the Mac awake');
		} else if (!active && blocker !== null) {
			powerSaveBlocker.stop(blocker);
			blocker = null;
			log.info('nothing running: letting the Mac sleep again');
		}
	}

	// ----------------------------------------------------------------- dock

	// Shows the running count as the Dock badge and their mean progress as the window's progress bar.
	function showOnDock(active) {
		if (process.platform !== 'darwin' || !app.dock) return;
		app.dock.setBadge(active.length ? String(active.length) : '');

		const win = getWindow();
		if (!win || win.isDestroyed()) return;
		if (!active.length) return win.setProgressBar(-1);

		// Runs without a percentage yet count as zero, so the bar never jumps backwards.
		const total = active.reduce((sum, r) => sum + (Number(r.progress) || 0), 0);
		win.setProgressBar(Math.min(1, total / (active.length * 100)));
	}

	// -------------------------------------------------------- notifications

	// Posts a notification for a finished or failed run; cancelled runs are not announced.
	function announce(run) {
		if (!prefs().notifications || !Notification.isSupported()) return;

		const done = run.status === 'completed';
		const cancelled = run.status === 'cancelled';
		if (cancelled) return;

		const what = run.label || run.kind;
		const notification = new Notification({
			title: done ? 'MARGIE finished' : 'MARGIE run failed',
			body: done ? what : `${what}\n${run.reason || 'See the run log for what happened.'}`,
			subtitle: run.files?.length ? `${run.files.length} genome${run.files.length === 1 ? '' : 's'}` : undefined,
			// A failure should not be as easy to miss as a success.
			sound: done ? undefined : 'Basso',
			timeoutType: done ? 'default' : 'never'
		});

		notification.on('click', () => openRuns());
		notification.show();
		log.info(`notified: ${run.status} — ${what}`);
	}

	/**
	 * Brings the window up on the runs list of the current shell (read from the page URL);
	 * on any other page the window is only focused.
	 */
	function openRuns() {
		let win = getWindow();
		if (!win || win.isDestroyed()) {
			const made = BrowserWindow.getAllWindows()[0];
			if (!made) return;
			win = made;
		}
		if (win.isMinimized()) win.restore();
		win.show();
		win.focus();
		app.focus({ steal: true });

		const here = win.webContents.getURL();
		const shell = ['/crisp'].find((p) => here.includes(`${p}/`) || here.endsWith(p));
		if (shell) win.loadURL(`${appUrl}${shell}/runs`);
	}

	// ----------------------------------------------------------------- poll

	// Polls the runs once, updates sleep/Dock/listeners, announces finished runs and schedules the next poll.
	async function tick() {
		// Windows has no local mode, so there are no local runs to watch.
		if (stopped || process.platform === 'win32') return;

		const data = await quiet(api('/api/local/runs'), 'polling runs');
		// A failed poll (e.g. no pipeline yet) just retries at the idle interval.
		if (data?.runs) {
			runs = data.runs;
			const active = runs.filter(isActive);

			if (seeded) {
				for (const run of runs) {
					const before = previous.get(run.id);
					// Only a transition out of 'running' is announced.
					if (before === 'running' && run.status !== 'running') announce(run);
				}
			}
			previous = new Map(runs.map((r) => [r.id, r.status]));
			seeded = true;

			holdSleep(active.length > 0);
			showOnDock(active);
			emit();

			schedule(active.length ? BUSY_MS : IDLE_MS);
			return;
		}

		schedule(IDLE_MS);
	}

	function schedule(ms) {
		if (stopped) return;
		clearTimeout(timer);
		timer = setTimeout(tick, ms);
		// The poll loop never keeps the process alive.
		timer.unref?.();
	}

	return {
		start() {
			stopped = false;
			void tick();
		},
		stop() {
			stopped = true;
			clearTimeout(timer);
			holdSleep(false);
			if (process.platform === 'darwin' && app.dock) app.dock.setBadge('');
		},
		/** The latest runs, for the menu bar item. */
		get runs() {
			return runs;
		},
		get active() {
			return runs.filter(isActive);
		},
		onChange(fn) {
			listeners.add(fn);
			return () => listeners.delete(fn);
		},
		openRuns
	};
}
