/**
 * Loads Electron's API into the ESM main process through createRequire.
 * An ESM import would resolve to the `electron` npm package (the binary path)
 * instead of the built-in module, so this is the only place that loads it.
 */

import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

/** @type {typeof import('electron')} */
const electron = require('electron');

export const { app, BrowserWindow, Menu, MenuItem, Tray, Notification, dialog, shell, nativeImage, nativeTheme, powerSaveBlocker, systemPreferences } = electron;

/** The whole namespace, for `screen`, which may only be touched once the app is ready. */
export default electron;
