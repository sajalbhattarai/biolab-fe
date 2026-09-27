/**
 * Builds the application menu: the standard Edit roles (needed for copy/paste on macOS),
 * navigation, run and results actions, and the desktop-only settings from app-prefs.js.
 */

import path from 'node:path';
import { app, Menu, shell, dialog } from './electron.js';
import { DATA_DIR, LOG_DIR, PIPELINE_HOME } from './paths.js';
import { prefs, setPref } from './app-prefs.js';
import { localApi, quiet } from './local-api.js';
import { addGenomeFiles } from './open-files.js';
import { log } from './log.js';

const isMac = process.platform === 'darwin';

/**
 * Builds and installs the menu; toggling a setting rebuilds it.
 * @param {{
 *   getWindow: () => Electron.BrowserWindow|null,
 *   appUrl: string,
 *   watch: any,
 *   showWindow: () => void,
 *   goTo: (route: string) => void,
 *   relook: () => void
 * }} ctx
 */
export function buildMenu(ctx) {
	const { getWindow, appUrl, watch, showWindow, goTo, relook, goBack, goForward } = ctx;
	const api = localApi(appUrl);
	const look = prefs();

	/** Saves a setting and rebuilds the menu so its check mark updates. */
	const toggle = (key, value, after) => {
		setPref(key, value);
		if (after) after();
		buildMenu(ctx);
	};

	// ------------------------------------------------------------ actions

	/** Opens the pipeline's output folder, read from the server's OUTPUT_ROOT setting. */
	async function revealResults() {
		const data = await quiet(api('/api/local/settings'), 'reading the settings');
		const value = data?.settings?.find((s) => s.key === 'OUTPUT_ROOT')?.value;
		const folder = value || path.join(PIPELINE_HOME, 'output');
		const problem = await shell.openPath(folder);
		if (problem) {
			dialog.showMessageBox({
				type: 'info',
				message: 'There are no results to show yet.',
				detail: `MARGIE looked in:\n${folder}\n\n${problem}`,
				buttons: ['OK']
			});
		}
	}

	async function addGenomes() {
		const win = getWindow();
		const { canceled, filePaths } = await dialog.showOpenDialog(win ?? undefined, {
			title: 'Add genomes',
			message: 'Choose the FASTA files to copy into MARGIE’s genome folder.',
			properties: ['openFile', 'multiSelections'],
			filters: [
				{ name: 'Genomes', extensions: ['fna', 'fa', 'fasta', 'fas', 'ffn', 'gz'] },
				{ name: 'All files', extensions: ['*'] }
			]
		});
		if (!canceled && filePaths.length) await addGenomeFiles(appUrl, filePaths);
	}

	/**
	 * Clears the run history after a confirmation. The server backs up what it removes
	 * to run-history/<when>/ and leaves running runs alone.
	 */
	async function clearHistory() {
		const running = watch?.active?.length ?? 0;
		const { response } = await dialog.showMessageBox(getWindow() ?? undefined, {
			type: 'question',
			message: 'Clear the run history?',
			detail:
				'Finished runs are moved out of the list. Nothing is thrown away: a copy is kept in run-history beside the pipeline, and MARGIE will show you where.' +
				(running ? `\n\n${running} run${running === 1 ? '' : 's'} still going will be left alone.` : ''),
			buttons: ['Clear', 'Cancel'],
			defaultId: 0,
			cancelId: 1
		});
		if (response === 1) return;

		try {
			const result = await api('/api/local/runs', { method: 'DELETE' });
			log.info(`cleared ${result?.removed ?? 0} run(s) to ${result?.backup ?? '?'}`);
			getWindow()?.webContents.reload();
			await dialog.showMessageBox({
				type: 'info',
				message: `Cleared ${result?.removed ?? 0} run${result?.removed === 1 ? '' : 's'}.`,
				detail: result?.backup ? `They were copied to:\n${result.backup}` : undefined,
				buttons: ['OK', 'Show in Finder'],
				defaultId: 0
			}).then(({ response: r }) => {
				if (r === 1 && result?.backup) void shell.openPath(result.backup);
			});
		} catch (err) {
			dialog.showErrorBox('Could not clear the history', String(err?.message ?? err));
		}
	}

	// ------------------------------------------------------------- template

	const template = [
		...(isMac
			? [
					{
						label: app.name,
						submenu: [
							{ role: 'about' },
							{ type: 'separator' },
							{ label: 'Where MARGIE Runs…', accelerator: 'CmdOrCtrl+,', click: () => goTo('/start') },
							{ type: 'separator' },
							{ role: 'services' },
							{ type: 'separator' },
							{ role: 'hide' },
							{ role: 'hideOthers' },
							{ role: 'unhide' },
							{ type: 'separator' },
							{ role: 'quit' }
						]
					}
				]
			: []),
		{
			label: 'File',
			submenu: [
				{ label: 'Start Page', accelerator: 'CmdOrCtrl+N', click: () => goTo('/start') },
				{ label: 'Add Genomes…', accelerator: 'CmdOrCtrl+O', click: () => void addGenomes() },
				{ type: 'separator' },
				{ label: 'Reveal Results in Finder', accelerator: 'CmdOrCtrl+Shift+R', click: () => void revealResults() },
				{ label: 'Show Pipeline Folder', click: () => void shell.openPath(PIPELINE_HOME) },
				{ label: 'Show Application Data', click: () => void shell.openPath(DATA_DIR) },
				{ type: 'separator' },
				isMac ? { role: 'close' } : { role: 'quit' }
			]
		},
		{
			label: 'Edit',
			submenu: [
				{ role: 'undo' },
				{ role: 'redo' },
				{ type: 'separator' },
				{ role: 'cut' },
				{ role: 'copy' },
				{ role: 'paste' },
				{ role: 'pasteAndMatchStyle' },
				{ role: 'delete' },
				{ role: 'selectAll' }
			]
		},
		{
			label: 'View',
			submenu: [
				{ role: 'reload' },
				{ role: 'forceReload' },
				{ type: 'separator' },
				{ role: 'resetZoom' },
				{ role: 'zoomIn' },
				{ role: 'zoomOut' },
				{ type: 'separator' },
				// Title bar and translucency are macOS window features.
				...(isMac
					? [
						{
							label: 'Window Style',
							submenu: [
								{
									label: 'Hidden Title Bar',
									type: 'radio',
									checked: look.titleBar === 'hidden',
									click: () => toggle('titleBar', 'hidden', relook)
								},
								{
									label: 'Native Title Bar',
									type: 'radio',
									checked: look.titleBar === 'native',
									click: () => toggle('titleBar', 'native', relook)
								},
								{ type: 'separator' },
								{
									label: 'Translucent Background',
									type: 'checkbox',
									checked: look.vibrancy,
									click: () => toggle('vibrancy', !prefs().vibrancy, relook)
								}
							]
						}
					]
					: []),
				{ type: 'separator' },
				{ role: 'togglefullscreen' },
				{ role: 'toggleDevTools' }
			]
		},
		{
			// The window has no toolbar, so a page that fails to load needs these to leave it.
			label: 'History',
			submenu: [
				{ label: 'Back', accelerator: 'CmdOrCtrl+[', click: goBack },
				{ label: 'Forward', accelerator: 'CmdOrCtrl+]', click: goForward },
				{ type: 'separator' },
				{ label: 'Start Page', accelerator: 'CmdOrCtrl+Shift+H', click: () => goTo('/start') },
				{ label: 'Reload', accelerator: 'CmdOrCtrl+Shift+Alt+R', click: () => getWindow()?.webContents.reload() }
			]
		},
		{
			label: 'Runs',
			submenu: [
				{ label: 'Show Runs', accelerator: 'CmdOrCtrl+R', click: () => watch?.openRuns() },
				{ label: 'Clear History…', click: () => void clearHistory() },
				{ type: 'separator' },
				{
					label: 'Notify When a Run Ends',
					type: 'checkbox',
					checked: look.notifications,
					click: () => toggle('notifications', !prefs().notifications)
				},
				{
					label: 'Keep the Mac Awake While Running',
					type: 'checkbox',
					checked: look.keepAwake,
					click: () => toggle('keepAwake', !prefs().keepAwake)
				},
				{
					label: 'Show in the Menu Bar',
					type: 'checkbox',
					checked: look.tray,
					click: () =>
						toggle('tray', !prefs().tray, () => {
							dialog.showMessageBox({
								type: 'info',
								message: 'The menu bar item changes when MARGIE next starts.',
								buttons: ['OK']
							});
						})
				}
			]
		},
		{
			label: 'Window',
			submenu: isMac
				? [{ role: 'minimize' }, { role: 'zoom' }, { type: 'separator' }, { label: 'Bring MARGIE Forward', click: showWindow }, { role: 'front' }]
				: [{ role: 'minimize' }, { role: 'zoom' }, { role: 'close' }]
		},
		{
			role: 'help',
			submenu: [
				{ label: 'Open Log Folder', click: () => void shell.openPath(LOG_DIR) },
				{ label: 'MARGIE on GitHub', click: () => void shell.openExternal('https://github.com/sajalbhattarai/biolab-fe') },
				{ type: 'separator' },
				{
					label: 'About This Build',
					click: () => {
						dialog.showMessageBox({
							type: 'info',
							message: `MARGIE ${app.getVersion()}`,
							detail: [
								`Electron ${process.versions.electron}`,
								`Node ${process.versions.node}`,
								'',
								`Data:      ${DATA_DIR}`,
								`Logs:      ${LOG_DIR}`,
								`Pipeline:  ${PIPELINE_HOME}`
							].join('\n'),
							buttons: ['OK']
						});
					}
				}
			]
		}
	];

	Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}
