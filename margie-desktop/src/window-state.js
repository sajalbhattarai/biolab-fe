/**
 * Saves and restores the main window's size, position and maximized state (window-state.json).
 */

import fs from 'node:fs';
import path from 'node:path';
import electron from './electron.js';
import { DATA_DIR } from './paths.js';

const FILE = path.join(DATA_DIR, 'window-state.json');
const DEFAULTS = { width: 1360, height: 900 };

// Returns the saved window bounds, dropping a position that is on no attached display.
export function loadWindowState() {
	let saved;
	try {
		saved = JSON.parse(fs.readFileSync(FILE, 'utf8'));
	} catch {
		return { ...DEFAULTS };
	}
	const state = {
		width: Number(saved.width) || DEFAULTS.width,
		height: Number(saved.height) || DEFAULTS.height,
		x: Number.isFinite(saved.x) ? saved.x : undefined,
		y: Number.isFinite(saved.y) ? saved.y : undefined,
		maximized: !!saved.maximized
	};

	if (state.x !== undefined && state.y !== undefined) {
		// `screen` is only valid once the app is ready, hence the namespace access.
		const onAScreen = electron.screen.getAllDisplays().some(({ workArea: a }) => {
			return state.x < a.x + a.width && state.x + state.width > a.x && state.y < a.y + a.height && state.y + state.height > a.y;
		});
		if (!onAScreen) {
			delete state.x;
			delete state.y;
		}
	}
	return state;
}

// Saves the window's bounds on resize/move (debounced) and on close.
export function trackWindowState(win) {
	let timer = null;

	const save = () => {
		try {
			const bounds = win.isMaximized() || win.isFullScreen() ? win.getNormalBounds() : win.getBounds();
			fs.mkdirSync(DATA_DIR, { recursive: true });
			fs.writeFileSync(FILE, JSON.stringify({ ...bounds, maximized: win.isMaximized() }, null, '\t'));
		} catch {
			// Failure to save is ignored.
		}
	};

	// Resize and move fire continuously while dragging.
	const debounced = () => {
		clearTimeout(timer);
		timer = setTimeout(save, 400);
	};

	for (const ev of ['resize', 'move', 'maximize', 'unmaximize']) win.on(ev, debounced);
	win.on('close', () => {
		clearTimeout(timer);
		save();
	});
}
