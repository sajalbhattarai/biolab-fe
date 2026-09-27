/**
 * Copies the bundled margie-pipeline to PIPELINE_HOME (it writes inside its own folder,
 * so it cannot run from the read-only bundle) on first start and whenever the bundle's
 * commit differs. Files are overwritten, never deleted; a git clone or non-pipeline folder is left alone.
 */

import fs from 'node:fs';
import path from 'node:path';
import { PIPELINE_BUNDLE, PIPELINE_HOME } from './paths.js';
import { isPipeline } from './settings.js';

const STAMP = 'margie-bundle.json';

const readStamp = (dir) => {
	try {
		return JSON.parse(fs.readFileSync(path.join(dir, STAMP), 'utf8'));
	} catch {
		return null;
	}
};

/** Installs or refreshes the bundled pipeline. Returns what happened, for the log. */
export function installBundledPipeline() {
	const bundled = readStamp(PIPELINE_BUNDLE);
	if (!bundled || !isPipeline(PIPELINE_BUNDLE)) return 'this build carries no pipeline';
	const exists = fs.existsSync(PIPELINE_HOME) && fs.readdirSync(PIPELINE_HOME).length > 0;
	if (exists && fs.existsSync(path.join(PIPELINE_HOME, '.git'))) return `a git clone is there; left as it is (${PIPELINE_HOME})`;
	if (exists && !isPipeline(PIPELINE_HOME)) return `${PIPELINE_HOME} is not a pipeline; left as it is`;
	const installed = readStamp(PIPELINE_HOME);
	if (installed?.commit === bundled.commit) return `up to date (${bundled.describe})`;
	fs.cpSync(PIPELINE_BUNDLE, PIPELINE_HOME, { recursive: true, force: true });
	// Its data folders are empty in git (placeholders only), so the bundle has none.
	for (const d of ['db', 'input', 'logs', 'output', 'user-input']) {
		fs.mkdirSync(path.join(PIPELINE_HOME, d), { recursive: true });
	}
	return `${installed ? 'updated' : 'installed'}: ${bundled.describe}`;
}
