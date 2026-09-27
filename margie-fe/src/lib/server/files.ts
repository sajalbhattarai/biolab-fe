/**
 * File access for the GUI: reading reaches anywhere this account can, while
 * writing (saving files, moving genomes) stays inside the pipeline checkout
 * and the folders its settings point at (allowedRoots).
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { PIPELINE_ROOT, getSettings } from './pipeline';

export class FileError extends Error {
	constructor(message: string, readonly status = 400) {
		super(message);
	}
}

const HIDDEN = new Set(['.git', 'node_modules', '.svelte-kit']);
const FASTA = /\.(fna|fa|fasta)$/i;

function settingPath(key: string): string {
	const value = getSettings().settings.find((s) => s.key === key)?.value || '';
	return value ? path.resolve(PIPELINE_ROOT, value) : '';
}

export function allowedRoots(): string[] {
	const keys = ['USER_INPUT_DIR', 'INPUT_RASTTK', 'OUTPUT_ROOT', 'GENOME_RESULTS_DIR', 'MARGIE_SHARED_DIR', 'DB_ROOT', 'SIF_DIR'];
	return [PIPELINE_ROOT, ...keys.map(settingPath).filter(Boolean)];
}

/** Resolves `p` (absolute, ~/... or relative to the pipeline) for reading; reads are not fenced in. */
export function resolveRead(p: string | null | undefined): string {
	let raw = (p ?? '').trim();
	if (!raw) return PIPELINE_ROOT;
	if (raw === '~' || raw.startsWith('~/')) raw = path.join(os.homedir(), raw.slice(1));
	return path.resolve(PIPELINE_ROOT, raw);
}

/** Resolves `p` for writing and rejects it unless it lies in the pipeline's own or the configured folders. */
export function resolveSafe(p: string | null | undefined): string {
	let raw = (p ?? '').trim();
	if (!raw) return PIPELINE_ROOT;
	if (raw === '~' || raw.startsWith('~/')) raw = path.join(os.homedir(), raw.slice(1));
	const abs = path.resolve(PIPELINE_ROOT, raw);
	const ok = allowedRoots().some((root) => abs === root || abs.startsWith(root + path.sep));
	if (!ok) throw new FileError('That path is outside the pipeline and its configured folders.', 403);
	return abs;
}

/** Lists the file browser's starting places that exist: home, mounted drives and the pipeline's folders. */
export function places(): { label: string; path: string }[] {
	const out: { label: string; path: string }[] = [];
	const add = (label: string, p: string) => {
		if (p && fs.existsSync(p) && !out.some((x) => x.path === p)) out.push({ label, path: p });
	};
	add('Home', os.homedir());
	// macOS mounts drives under /Volumes; Linux under /media or /mnt.
	for (const mounts of ['/Volumes', '/media', '/mnt']) {
		try {
			for (const name of fs.readdirSync(mounts)) add(name, path.join(mounts, name));
		} catch {
			// Not this system's mount point.
		}
	}
	add('Results', settingPath('OUTPUT_ROOT'));
	add('Genomes in', settingPath('USER_INPUT_DIR'));
	add('Databases', settingPath('DB_ROOT'));
	add('MARGIE', PIPELINE_ROOT);
	add('This computer', path.parse(os.homedir()).root);
	return out;
}

function statOrThrow(abs: string): fs.Stats {
	try {
		return fs.statSync(abs);
	} catch {
		throw new FileError(`Not found: ${abs}`, 404);
	}
}

export interface Entry {
	name: string;
	type: 'file' | 'directory';
	size: number;
	mtime: string;
}

export function listDir(p: string | null): { path: string; parent: string | null; entries: Entry[] } {
	const abs = resolveRead(p);
	if (!statOrThrow(abs).isDirectory()) throw new FileError('Not a folder.', 400);
	const entries: Entry[] = [];
	for (const name of fs.readdirSync(abs)) {
		if (HIDDEN.has(name)) continue;
		try {
			const st = fs.statSync(path.join(abs, name)); // follows symlinks, as classify's input/ uses them
			entries.push({
				name,
				type: st.isDirectory() ? 'directory' : 'file',
				size: st.size,
				mtime: st.mtime.toISOString()
			});
		} catch {
			// Dangling symlink.
		}
	}
	entries.sort((a, b) => (a.type === b.type ? a.name.localeCompare(b.name) : a.type === 'directory' ? -1 : 1));
	let parent: string | null = path.dirname(abs);
	if (parent === abs) parent = null;
	return { path: abs, parent, entries };
}

/** Reads up to maxBytes of a text file for the file explorer's viewer/editor. */
export function readText(p: string, maxBytes = 1024 * 1024) {
	const abs = resolveRead(p);
	const st = statOrThrow(abs);
	if (st.isDirectory()) throw new FileError('That is a folder.', 400);
	const fd = fs.openSync(abs, 'r');
	try {
		const len = Math.min(st.size, maxBytes);
		const buf = Buffer.alloc(len);
		fs.readSync(fd, buf, 0, len, 0);
		// A NUL byte early on is a reliable "this is binary" signal.
		const binary = buf.subarray(0, 8192).includes(0);
		return {
			path: abs,
			content: binary ? '' : buf.toString('utf8'),
			binary,
			truncated: st.size > maxBytes,
			size: st.size
		};
	} finally {
		fs.closeSync(fd);
	}
}

export function saveText(p: string, content: string): void {
	const abs = resolveSafe(p);
	if (fs.existsSync(abs) && fs.statSync(abs).isDirectory()) throw new FileError('That is a folder.', 400);
	fs.mkdirSync(path.dirname(abs), { recursive: true });
	fs.writeFileSync(abs, content);
}

export function openDownload(p: string): { abs: string; size: number; name: string } {
	const abs = resolveRead(p);
	const st = statOrThrow(abs);
	if (st.isDirectory()) throw new FileError('That is a folder.', 400);
	return { abs, size: st.size, name: path.basename(abs) };
}

// Line counts are cached per (path, mtime, size): results do not change once written.
const lineCounts = new Map<string, { key: string; total: number }>();

/** Returns one page of a text file's lines (1-indexed, header excluded), plus its header and line count. */
export async function readPage(p: string, page: number, pageSize: number) {
	const abs = resolveRead(p);
	const st = statOrThrow(abs);
	if (st.isDirectory()) throw new FileError('That is a folder.', 400);
	const cacheKey = `${st.mtimeMs}:${st.size}`;
	const cached = lineCounts.get(abs);
	const start = 2 + (page - 1) * pageSize; // line 1 is the header
	const end = start + pageSize - 1;

	let header = '';
	const lines: string[] = [];
	let n = 0;
	const rl = readline.createInterface({ input: fs.createReadStream(abs), crlfDelay: Infinity });
	for await (const line of rl) {
		n++;
		if (n === 1) header = line;
		else if (n >= start && n <= end) lines.push(line);
		if (n > end && cached?.key === cacheKey) break;
	}
	rl.close();
	const total = cached?.key === cacheKey ? cached.total : n;
	lineCounts.set(abs, { key: cacheKey, total });
	const split = abs.toLowerCase().endsWith('.csv') ? splitCsv : (l: string) => l.split('\t');
	const totalRows = Math.max(0, total - 1);
	return {
		path: abs,
		columns: split(header),
		rows: lines.map(split),
		total_rows: totalRows,
		total_pages: Math.max(1, Math.ceil(totalRows / pageSize)),
		page,
		page_size: pageSize
	};
}

/** Splits one CSV line into fields, honouring "quoted, fields" and "" escapes. */
function splitCsv(line: string): string[] {
	const out: string[] = [];
	let field = '';
	let quoted = false;
	for (let i = 0; i < line.length; i++) {
		const c = line[i];
		if (quoted) {
			if (c === '"' && line[i + 1] === '"') {
				field += '"';
				i++;
			} else if (c === '"') quoted = false;
			else field += c;
		} else if (c === '"') quoted = true;
		else if (c === ',') {
			out.push(field);
			field = '';
		} else field += c;
	}
	out.push(field);
	return out;
}

// ---------------------------------------------------------------- genomes

export interface Genome {
	name: string;
	size: number;
	/** From the genome table; '' when not given. */
	domain: string;
	genetic_code: string;
}

// ---------------------------------------------------------------- genome table

export const DOMAINS = ['Bacteria', 'Archaea'];
/** NCBI translation tables Prodigal accepts (-g 1..25; 7, 8 and 17-20 do not exist). */
export const GENETIC_CODES = [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14, 15, 16, 21, 22, 23, 24, 25].map(String);

type GenomeMeta = { domain: string; genetic_code: string };

/** Exported so a run on a subset can point GENOME_METADATA back at the real table. */
export function metadataPath(): string {
	return settingPath('GENOME_METADATA');
}

/** Reads genome file name -> { domain, genetic_code } from the TSV (missing file = empty). */
export function readGenomeMetadata(): Map<string, GenomeMeta> {
	const rows = new Map<string, GenomeMeta>();
	let text = '';
	try {
		text = fs.readFileSync(metadataPath(), 'utf8');
	} catch {
		return rows;
	}
	for (const line of text.split(/\r?\n/).slice(1)) {
		const [genome = '', domain = '', code = ''] = line.split('\t').map((c) => c.trim());
		if (genome) rows.set(genome, { domain, genetic_code: code });
	}
	return rows;
}

/** Normalises and checks one row; throws FileError with a readable reason. */
function cleanRow(name: string, domain: string, code: string): GenomeMeta {
	const d = domain.trim().toLowerCase();
	const dom = d === '' ? '' : d.startsWith('b') ? 'Bacteria' : d.startsWith('a') ? 'Archaea' : null;
	if (dom === null) throw new FileError(`${name}: domain must be Bacteria or Archaea, not "${domain}".`);
	const c = code.trim();
	if (c && !GENETIC_CODES.includes(c)) {
		throw new FileError(`${name}: genetic code ${c} is not an NCBI translation table Prodigal supports (${GENETIC_CODES.join(', ')}).`);
	}
	return { domain: dom, genetic_code: c };
}

/** Saves the table for the genomes in the input folder; rows for other genomes are kept. */
export function writeGenomeMetadata(rows: { name: string; domain?: string; genetic_code?: string }[]): void {
	const present = new Set(listGenomes().genomes.map((g) => g.name));
	const table = readGenomeMetadata();
	for (const r of rows) {
		if (!present.has(r.name)) throw new FileError(`${r.name} is not in the genome folder.`, 404);
		table.set(r.name, cleanRow(r.name, r.domain ?? '', r.genetic_code ?? ''));
	}
	const lines = ['genome\tdomain\tgenetic_code'];
	for (const [genome, m] of [...table].sort(([a], [b]) => a.localeCompare(b))) {
		if (m.domain || m.genetic_code) lines.push(`${genome}\t${m.domain}\t${m.genetic_code}`);
	}
	const file = metadataPath();
	fs.mkdirSync(path.dirname(file), { recursive: true });
	fs.writeFileSync(file, lines.join('\n') + '\n');
}

/** A genome file sitting in a folder inside the genomes folder, not in it. */
export interface NestedGenome {
	/** Path relative to the genomes folder, e.g. "batch1/Ecoli.fna". */
	rel: string;
	/** The folder it sits in, relative to the genomes folder. */
	folder: string;
	name: string;
	size: number;
	/** A file of the same name is already in the genomes folder. */
	clashes: boolean;
}

/** How deep to look: enough for a downloaded archive, not a whole disk. */
const NEST_DEPTH = 4;

/** Finds genome files in folders beneath the genomes folder, which runs do not read. */
function nestedGenomes(folder: string, top: Set<string>): NestedGenome[] {
	const found: NestedGenome[] = [];
	const walk = (dir: string, depth: number) => {
		if (depth > NEST_DEPTH || found.length >= 500) return;
		let entries: fs.Dirent[];
		try {
			entries = fs.readdirSync(dir, { withFileTypes: true });
		} catch {
			return;
		}
		for (const e of entries) {
			if (e.name.startsWith('.')) continue;
			const full = path.join(dir, e.name);
			if (e.isDirectory()) walk(full, depth + 1);
			else if (e.isFile() && FASTA.test(e.name)) {
				const rel = path.relative(folder, full);
				found.push({
					rel,
					folder: path.dirname(rel),
					name: e.name,
					size: fs.statSync(full).size,
					clashes: top.has(e.name)
				});
			}
		}
	};
	for (const e of fs.readdirSync(folder, { withFileTypes: true })) {
		if (e.isDirectory() && !e.name.startsWith('.')) walk(path.join(folder, e.name), 1);
	}
	return found.sort((a, b) => a.rel.localeCompare(b.rel));
}

/** Staging folders for runs on a subset of the genomes. */
const SELECTION_DIR = '.margie-selection';

/**
 * Builds a folder of symlinks to only the chosen genomes; the caller points
 * USER_INPUT_DIR (which the environment overrides) at it and passes
 * GENOME_METADATA at its real path.
 */
export function stageGenomes(names: string[]): string {
	const folder = settingPath('USER_INPUT_DIR');
	if (!folder || !fs.existsSync(folder)) throw new FileError('The genome folder is not there.', 400);

	const root = path.join(PIPELINE_ROOT, SELECTION_DIR);
	fs.mkdirSync(root, { recursive: true });

	// Old staging folders are kept for a while, as they record what a run was given.
	try {
		const old = fs
			.readdirSync(root)
			.filter((n) => n.startsWith('run-'))
			.sort()
			.slice(0, -9);
		for (const n of old) fs.rmSync(path.join(root, n), { recursive: true, force: true });
	} catch {
		// Tidying is optional.
	}

	const dir = path.join(root, `run-${new Date().toISOString().replace(/[:.]/g, '-')}`);
	fs.mkdirSync(dir, { recursive: true });

	for (const name of names) {
		// The name comes from the page, so it must be a plain FASTA file name.
		if (!name || name !== path.basename(name) || !FASTA.test(name)) {
			throw new FileError(`Not a genome file name: ${name}`, 400);
		}
		const src = path.join(folder, name);
		if (!fs.existsSync(src)) throw new FileError(`${name} is not in the genome folder any more.`, 409);
		fs.symlinkSync(src, path.join(dir, name));
	}
	return dir;
}

export function listGenomes(): { folder: string; genomes: Genome[]; nested: NestedGenome[] } {
	const folder = settingPath('USER_INPUT_DIR');
	if (!folder || !fs.existsSync(folder)) return { folder, genomes: [], nested: [] };
	const meta = readGenomeMetadata();
	const genomes = fs
		.readdirSync(folder)
		.filter((n) => FASTA.test(n))
		.sort()
		.map((name) => ({
			name,
			size: fs.statSync(path.join(folder, name)).size,
			domain: meta.get(name)?.domain ?? '',
			genetic_code: meta.get(name)?.genetic_code ?? ''
		}));
	return { folder, genomes, nested: nestedGenomes(folder, new Set(genomes.map((g) => g.name))) };
}

/**
 * Copies or moves nested genomes up into the genomes folder without
 * overwriting, optionally deleting the folders a move emptied.
 */
export function gatherGenomes(mode: 'copy' | 'move', removeEmpty: boolean): {
	moved: string[];
	skipped: string[];
	removed: string[];
} {
	const folder = settingPath('USER_INPUT_DIR');
	if (!folder || !fs.existsSync(folder)) throw new FileError('The genomes folder is not set.', 400);
	const root = fs.realpathSync(folder);
	const moved: string[] = [];
	const skipped: string[] = [];
	const touched = new Set<string>();

	for (const g of listGenomes().nested) {
		const from = path.join(root, g.rel);
		const to = path.join(root, g.name);
		// Never step outside the genomes folder, whatever the name looks like.
		if (!fs.realpathSync(path.dirname(from)).startsWith(root) || path.dirname(to) !== root) {
			skipped.push(g.rel);
			continue;
		}
		if (fs.existsSync(to)) {
			skipped.push(g.rel);           // same name already up here: leave both alone
			continue;
		}
		try {
			if (mode === 'copy') fs.copyFileSync(from, to, fs.constants.COPYFILE_EXCL);
			else fs.renameSync(from, to);
			moved.push(g.rel);
			touched.add(path.dirname(from));
		} catch {
			skipped.push(g.rel);
		}
	}

	const removed: string[] = [];
	if (mode === 'move' && removeEmpty) {
		// Removes empty folders deepest first, so a parent emptied by its children goes too.
		const prune = (dir: string): boolean => {
			let entries: fs.Dirent[];
			try {
				entries = fs.readdirSync(dir, { withFileTypes: true });
			} catch {
				return false;
			}
			let empty = true;
			for (const e of entries) {
				if (e.isDirectory()) {
					if (!prune(path.join(dir, e.name))) empty = false;
				} else empty = false;
			}
			if (!empty || dir === root) return empty;
			try {
				fs.rmdirSync(dir);
				removed.push(path.relative(root, dir));
				return true;
			} catch {
				return false;
			}
		};
		prune(root);
	}
	void touched;
	return { moved, skipped, removed };
}

function genomePath(name: string): string {
	const folder = settingPath('USER_INPUT_DIR');
	const base = path.basename(name);
	if (base !== name || !FASTA.test(base)) {
		throw new FileError('Genome files must be .fna, .fa or .fasta, with no folder in the name.', 400);
	}
	return path.join(folder, base);
}

export async function addGenome(file: File, overwrite: boolean): Promise<string> {
	const dest = genomePath(file.name);
	if (fs.existsSync(dest) && !overwrite) throw new FileError(`${file.name} is already in the input folder.`, 409);
	fs.mkdirSync(path.dirname(dest), { recursive: true });
	fs.writeFileSync(dest, Buffer.from(await file.arrayBuffer()));
	return file.name;
}

export function removeGenome(name: string): void {
	const target = genomePath(name);
	if (!fs.existsSync(target)) throw new FileError(`${name} is not in the input folder.`, 404);
	fs.rmSync(target);
}
