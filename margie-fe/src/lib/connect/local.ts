/**
 * MARGIE on this computer: finds the margie-pipeline checkout where
 * lib/server/pipeline.ts looks for it, or clones it there.
 */

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { APP_DIR, STATE_DIR, expandHome, readSettings } from './settings';

/** The pipeline is the margie-pipeline folder of this repository's public branch. */
export const PIPELINE_REPO = 'https://github.com/sajalbhattarai/biolab-fe.git';
export const PIPELINE_BRANCH = 'margie-frontend';
/**
 * Where the app looks first and where a clone goes: beside the app.
 * MARGIE_PIPELINE_HOME overrides it in the macOS app, whose bundle is read-only.
 */
export const PIPELINE_HOME =
	expandHome(process.env.MARGIE_PIPELINE_HOME || '') || path.resolve(APP_DIR, '..', 'margie-pipeline');
const CLONE_LOG = path.join(STATE_DIR, 'pipeline-clone.log');

/** Checks that a folder holds annotate.sh and pipeline.conf.sh. */
export const isPipeline = (dir: string) =>
	!!dir && fs.existsSync(path.join(dir, 'annotate.sh')) && fs.existsSync(path.join(dir, 'pipeline.conf.sh'));

export interface LocalStatus {
	/** The pipeline the app will use, or '' when there is none. */
	pipeline: string;
	/** Where it looked. */
	looked: string[];
	clone: { running: boolean; ok: boolean | null; log: string[] };
	/** Why this computer cannot run the pipeline at all, or ''. */
	unsupported: string;
}

/** Windows needs WSL, which the app does not set up, so local runs are refused there. */
const UNSUPPORTED =
	process.platform === 'win32'
		? 'On Windows, analyses run inside Linux (WSL 2). Below is what that needs, and what this computer already has. Running MARGIE through WSL is coming in an update; until then, use the HPC cluster.'
		: '';

// Clone state kept on globalThis so it survives module reloads.
const cloning = globalThis as unknown as { __margieClone?: { running: boolean; ok: boolean | null } };

/** Returns candidate folders in lib/server/pipeline.ts order, the chosen folder first. */
function candidates(): string[] {
	const chosen = readSettings().pipelineRoot || process.env.MARGIE_PIPELINE_ROOT || '';
	return [
		...(chosen ? [expandHome(chosen)] : []),
		PIPELINE_HOME,
		path.resolve(APP_DIR, 'margie-pipeline'),
		path.resolve(APP_DIR, '..')
	];
}

/** Reports the pipeline found, where it looked, the clone's state and its log tail. */
export function localStatus(): LocalStatus {
	const looked = [...new Set(candidates())];
	let log: string[] = [];
	try {
		log = fs.readFileSync(CLONE_LOG, 'utf8').replace(/\r/g, '\n').split('\n').filter((l) => l.trim()).slice(-12);
	} catch {
		// No download yet.
	}
	return {
		pipeline: looked.find(isPipeline) ?? '',
		looked,
		clone: { running: !!cloning.__margieClone?.running, ok: cloning.__margieClone?.ok ?? null, log },
		unsupported: UNSUPPORTED
	};
}

/** Clones the pipeline into PIPELINE_HOME in the background. */
export function clonePipeline(): void {
	if (cloning.__margieClone?.running) return;
	if (fs.existsSync(PIPELINE_HOME) && fs.readdirSync(PIPELINE_HOME).length)
		throw new Error(`${PIPELINE_HOME} already exists and is not the pipeline. Move it aside, or choose the folder you have.`);
	fs.mkdirSync(STATE_DIR, { recursive: true });
	const out = fs.openSync(CLONE_LOG, 'w');
	cloning.__margieClone = { running: true, ok: null };
	// Clones the branch shallowly into a scratch folder, then moves its margie-pipeline folder into place.
	const scratch = path.join(STATE_DIR, 'pipeline-download');
	fs.rmSync(scratch, { recursive: true, force: true });
	const child = spawn('git', ['clone', '--progress', '--depth', '1', '-b', PIPELINE_BRANCH, PIPELINE_REPO, scratch], {
		stdio: ['ignore', out, out],
		// Fails instead of waiting for a GitHub login prompt nobody can see.
		env: { ...process.env, GIT_TERMINAL_PROMPT: '0' }
	});
	fs.closeSync(out);
	child.on('close', (code) => {
		let ok = false;
		try {
			if (code === 0) {
				fs.rmSync(PIPELINE_HOME, { recursive: true, force: true });
				fs.mkdirSync(path.dirname(PIPELINE_HOME), { recursive: true });
				fs.cpSync(path.join(scratch, 'margie-pipeline'), PIPELINE_HOME, { recursive: true });
				ok = isPipeline(PIPELINE_HOME);
			}
		} catch {
			ok = false;
		} finally {
			fs.rmSync(scratch, { recursive: true, force: true });
		}
		cloning.__margieClone = { running: false, ok };
	});
	child.on('error', () => (cloning.__margieClone = { running: false, ok: false }));
}
