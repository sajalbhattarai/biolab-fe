/**
 * The menu bar item: shows running runs with their progress and the last finished run,
 * so a run can be followed with the window closed.
 */

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Menu, Tray, app, nativeImage } from './electron.js';
import { log } from './log.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));

/**
 * Creates the tray icon and rebuilds its menu whenever the run watcher reports a change.
 * @param {{ watch: any, showWindow: () => void, goTo: (route: string) => void }} ctx
 */
export function createTray({ watch, showWindow, goTo }) {
	// "Template" in the file name marks the image as a mask macOS inverts for dark/light menu bars.
	const icon = nativeImage.createFromPath(path.join(HERE, 'assets', 'trayTemplate.png'));
	if (icon.isEmpty()) {
		log.warn('the menu bar icon is missing; run `npm run icon`');
		return null;
	}
	icon.setTemplateImage(true);

	const tray = new Tray(icon);

	function refresh(runs = watch.runs) {
		const active = runs.filter((r) => r.status === 'running');

		const heading = active.length
			? {
					label: `${active.length} run${active.length === 1 ? '' : 's'} going`,
					enabled: false
				}
			: { label: 'Nothing running', enabled: false };

		const items = active.slice(0, 5).map((r) => ({
			// The percentage is the useful part at a glance; the label says which.
			label: `   ${Number(r.progress) || 0}%  ${r.label || r.kind}`,
			click: () => watch.openRuns()
		}));

		// The last finished run.
		const done = runs.filter((r) => r.status !== 'running').slice(0, 1);
		const recent = done.map((r) => ({
			label: `   ${r.status === 'completed' ? 'Finished' : r.status === 'failed' ? 'Failed' : 'Cancelled'}: ${r.label || r.kind}`,
			click: () => watch.openRuns()
		}));

		tray.setToolTip(active.length ? `MARGIE — ${active.length} running` : 'MARGIE');

		tray.setContextMenu(
			Menu.buildFromTemplate([
				heading,
				...items,
				...(recent.length ? [{ type: 'separator' }, { label: 'Last run', enabled: false }, ...recent] : []),
				{ type: 'separator' },
				{ label: 'Open MARGIE', click: showWindow },
				{ label: 'Runs', click: () => watch.openRuns() },
				{ label: 'Where MARGIE Runs…', click: () => goTo('/start') },
				{ type: 'separator' },
				{ label: 'Quit MARGIE', click: () => app.quit() }
			])
		);
	}

	// Clicking the icon brings the window up.
	tray.on('click', () => showWindow());

	watch.onChange(refresh);
	refresh();

	return tray;
}
