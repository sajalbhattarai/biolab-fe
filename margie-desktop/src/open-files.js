/**
 * Handles genomes dropped on the Dock icon or opened from Finder ('open-file' events).
 * Paths are buffered until the server is up, then posted to /api/local/genomes,
 * the same route the upload button uses.
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import { Notification } from './electron.js';
import { log } from './log.js';

/** What the genome folder is willing to take; the server checks the contents. */
const GENOME_EXTENSIONS = new Set(['.fna', '.fa', '.fasta', '.fas', '.ffn', '.seq', '.gz']);

const waiting = [];

export const rememberOpenFile = (file) => waiting.push(file);

/** Takes the buffered paths and empties the buffer. */
export function pendingOpenFiles() {
	return waiting.splice(0, waiting.length);
}

export const looksLikeGenome = (file) => GENOME_EXTENSIONS.has(path.extname(file).toLowerCase());

/**
 * Uploads the genome-looking files to the local server and notifies the result.
 *
 * @param {string} appUrl
 * @param {string[]} files
 */
export async function addGenomeFiles(appUrl, files) {
	const genomes = files.filter(looksLikeGenome);
	const ignored = files.length - genomes.length;
	if (!genomes.length) {
		if (ignored) notify('Not a genome file', `MARGIE takes FASTA files (${[...GENOME_EXTENSIONS].join(', ')}).`);
		return;
	}

	const form = new FormData();
	for (const file of genomes) {
		try {
			const bytes = await fs.readFile(file);
			form.append('files', new Blob([bytes]), path.basename(file));
		} catch (err) {
			log.warn(`could not read ${file}:`, err?.message ?? err);
		}
	}

	try {
		const res = await fetch(`${appUrl}/api/local/genomes`, { method: 'POST', body: form });
		if (!res.ok) {
			// Passes on the server's own error message.
			const body = await res.json().catch(() => null);
			throw new Error(body?.message ?? `the server answered ${res.status}`);
		}
		const added = (await res.json())?.added?.length ?? genomes.length;
		log.info(`added ${added} genome(s) from the Dock or Finder`);
		notify(
			`Added ${added} genome${added === 1 ? '' : 's'}`,
			genomes.map((f) => path.basename(f)).join(', ')
		);
	} catch (err) {
		log.error('could not add the dropped genomes:', err);
		notify('Could not add those genomes', String(err?.message ?? err));
	}
}

function notify(title, body) {
	if (!Notification.isSupported()) return;
	new Notification({ title, body }).show();
}
