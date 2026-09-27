/**
 * Chat with the genome: a model answers questions about one genome's results
 * through three tools (list files, read one, search the report table), confined
 * to output/genomes/<genome>/ and output/<tool>/<genome>/ and capped by a token
 * budget; each read becomes cited evidence [E1], [E2]...
 *
 * Providers: Claude via the Anthropic SDK's tool runner; OpenAI, Gemini and
 * OpenAI-compatible services via chat completions. Keys and choices live in
 * ~/.config/margie/ai.json, history in logs/chat/<genome>.json. margie-frontend's
 * lib/server holds an identical copy.
 */

import Anthropic from '@anthropic-ai/sdk';
import { betaTool } from '@anthropic-ai/sdk/helpers/beta/json-schema';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { PIPELINE_ROOT, setting } from './pipeline';

// ------------------------------------------------------------------ providers

export type Provider = 'anthropic' | 'openai' | 'gemini' | 'custom' | 'builtin';

export const PROVIDERS: Record<Provider, { label: string; base: string; models: string[]; policy: string; keys: string }> = {
	anthropic: {
		label: 'Claude (Anthropic)',
		base: '',
		models: ['claude-opus-5', 'claude-sonnet-5', 'claude-haiku-4-5', 'claude-fable-5-1'],
		policy: 'https://www.anthropic.com/legal/commercial-terms',
		keys: 'https://console.anthropic.com/settings/keys'
	},
	openai: {
		label: 'OpenAI',
		base: 'https://api.openai.com/v1',
		models: ['gpt-5', 'gpt-5-mini', 'gpt-4.1'],
		policy: 'https://openai.com/enterprise-privacy/',
		keys: 'https://platform.openai.com/api-keys'
	},
	gemini: {
		label: 'Google Gemini',
		base: 'https://generativelanguage.googleapis.com/v1beta/openai',
		models: ['gemini-2.5-pro', 'gemini-2.5-flash'],
		policy: 'https://ai.google.dev/gemini-api/terms',
		keys: 'https://aistudio.google.com/app/apikey'
	},
	custom: {
		label: 'Other (OpenAI-compatible)',
		base: '',
		models: [],
		policy: '',
		keys: ''
	},
	builtin: { label: 'Built-in (on this computer)', base: '', models: [], policy: '', keys: '' }
};

export interface ChatSettings {
	provider: Provider;
	model: string;
	/** Base URL for 'custom' (e.g. https://openrouter.ai/api/v1, http://localhost:11434/v1). */
	baseUrl: string;
	/** How much of the results the model may read per question, in tokens. */
	budget: number;
	/** The longest answer, in tokens. */
	answerTokens: number;
	/** Providers whose data notice the user has accepted. */
	consented: Provider[];
}

const DEFAULTS: ChatSettings = { provider: 'anthropic', model: 'claude-opus-5', baseUrl: '', budget: 10000, answerTokens: 16000, consented: [] };

const CONFIG = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'margie', 'ai.json');

interface Stored {
	settings: ChatSettings;
	keys: Partial<Record<Provider, string>>;
}

function load(): Stored {
	try {
		const d = JSON.parse(fs.readFileSync(CONFIG, 'utf8'));
		return { settings: { ...DEFAULTS, ...(d.settings ?? {}) }, keys: d.keys ?? {} };
	} catch {
		return { settings: { ...DEFAULTS }, keys: {} };
	}
}

function save(s: Stored) {
	fs.mkdirSync(path.dirname(CONFIG), { recursive: true });
	fs.writeFileSync(CONFIG, JSON.stringify(s, null, 2) + '\n', { mode: 0o600 });
	fs.chmodSync(CONFIG, 0o600);
}

// ------------------------------------------------------------------ keys kept on the cluster

/**
 * Keys from the HPC home (~/.config/margie/ai-keys.json via /v1/ssh/ai-keys),
 * held in memory only and never written to this computer.
 */
const onHpc: Partial<Record<Provider, string>> = {};

/** The app's own connection to the cluster: its API behind the local tunnel, and the sign-in. */
export interface HpcLink {
	api: string;
	token: string;
}

function hpcUrl(link: HpcLink, route: string): URL {
	let api: URL;
	try {
		api = new URL(String(link?.api ?? ''));
	} catch {
		throw new ChatError('Not connected to the HPC.', 400);
	}
	if (!['127.0.0.1', 'localhost', '[::1]'].includes(api.hostname) || !['http:', 'https:'].includes(api.protocol))
		throw new ChatError('Keys go to the HPC only through the app’s own connection.', 400);
	return new URL(route, api);
}

async function hpcCall(link: HpcLink, method: string, body?: unknown): Promise<{ keys?: Record<string, string> }> {
	const url = hpcUrl(link, '/v1/ssh/ai-keys');
	let res: Response;
	try {
		res = await fetch(url, {
			method,
			headers: { Authorization: `Bearer ${link.token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
			body: body ? JSON.stringify(body) : undefined
		});
	} catch {
		throw new ChatError('The HPC cannot be reached. Is it still connected?', 503);
	}
	if (res.status === 404) throw new ChatError('The server on the HPC is older than this app: reconnect to update it, then try again.', 409);
	if (!res.ok) throw new ChatError(`The HPC could not ${method === 'GET' ? 'read' : 'save'} the keys (${res.status}).`, 502);
	return res.json().catch(() => ({}));
}

/** Reads the keys kept on the HPC into memory. */
export async function pullHpcKeys(link: HpcLink) {
	const d = await hpcCall(link, 'GET');
	for (const p of Object.keys(onHpc) as Provider[]) delete onHpc[p];
	for (const [p, k] of Object.entries(d.keys ?? {})) if (p in PROVIDERS && typeof k === 'string' && k) onHpc[p as Provider] = k;
	return publicSettings();
}

/** Saves (or, with null, removes) one provider's key in the HPC home, keeping the others there. */
export async function saveHpcKey(link: HpcLink, provider: Provider, key: string | null) {
	if (!(provider in PROVIDERS)) throw new ChatError('Unknown provider.', 400);
	const d = await hpcCall(link, 'GET');
	const keys: Record<string, string> = { ...(d.keys ?? {}) };
	if (key && key.trim()) keys[provider] = key.trim();
	else delete keys[provider];
	await hpcCall(link, 'PUT', { keys });
	return pullHpcKeys(link);
}

/** Returns the settings the page may see, with each key shown only as its last four characters. */
export function publicSettings() {
	const s = load();
	const keys = Object.fromEntries(
		(Object.keys(PROVIDERS) as Provider[]).map((p) => {
			const here = s.keys[p];
			const hpc = onHpc[p];
			const key = here ?? hpc;
			return [p, key ? { saved: true, last4: key.slice(-4), here: !!here, hpc: !!hpc } : { saved: false }];
		})
	);
	return { settings: s.settings, keys, providers: PROVIDERS, builtin: builtinStatus() };
}

/** Saves the choices; `key` saves a key for the chosen provider, `key: null` forgets it. */
export function updateSettings(body: Partial<ChatSettings> & { key?: string | null; keyFor?: Provider }) {
	const s = load();
	const next: ChatSettings = { ...s.settings };
	if (body.provider && body.provider in PROVIDERS) next.provider = body.provider;
	if (typeof body.model === 'string') next.model = body.model.trim().slice(0, 120);
	if (typeof body.baseUrl === 'string') next.baseUrl = body.baseUrl.trim().slice(0, 300);
	if (Number.isFinite(body.budget)) next.budget = Math.max(1000, Math.min(400000, Math.round(body.budget!)));
	if (Number.isFinite(body.answerTokens)) next.answerTokens = Math.max(500, Math.min(64000, Math.round(body.answerTokens!)));
	if (Array.isArray(body.consented)) next.consented = body.consented.filter((p) => p in PROVIDERS);
	s.settings = next;
	const who = body.keyFor && body.keyFor in PROVIDERS ? body.keyFor : next.provider;
	if (body.key === null) delete s.keys[who];
	else if (typeof body.key === 'string' && body.key.trim()) s.keys[who] = body.key.trim();
	save(s);
	return publicSettings();
}

/** Returns the built-in model's LLM settings and whether it is set up. */
function builtinStatus() {
	const model = setting('LLM_TRAINED_MODEL') || setting('LLM_BASE_MODEL');
	return { ready: false, model, note: 'The built-in model is not set up yet. Its location is in Settings (LLM).' };
}

// ------------------------------------------------------------------ the genome's results, and nothing else

const TEXT = /\.(tsv|txt|log|csv|json|md|tab|gff|gff3|out|tbl|yaml|yml|faa|fna|fa|fasta)$/i;
const tokensOf = (s: string) => Math.ceil(s.length / 4);

function safeGenome(g: unknown): string {
	const s = String(g ?? '');
	if (!/^[\w.-]+$/.test(s) || s === '.' || s === '..') throw new ChatError('That is not a genome name.', 400);
	return s;
}

/** What the model reads through: a genome's folders, on this computer or on the cluster. */
interface Source {
	/** Absolute folders the model may read. */
	roots: string[];
	/** Paths are shown to the model relative to this. */
	base: string;
	/** The genome's report table, if it has one. */
	table: string | null;
	/** A path the model gave, if it lies inside the roots; otherwise null. */
	inside(p: string): Promise<string | null>;
	list(dir: string): Promise<{ name: string; dir: boolean; size: number }[]>;
	/** A directory? (Only asked of paths already inside.) */
	isDir(p: string): Promise<boolean>;
	read(file: string): Promise<string>;
	/** How deep list_files walks: less on the cluster, where each folder is a request. */
	depth: number;
}

/** Builds a Source over the genome's local folders: its results folder and each tool's folder for it. */
function localSource(genome: string): Source {
	const out = fs.realpathSync(setting('OUTPUT_ROOT') || path.join(PIPELINE_ROOT, 'output'));
	const roots: string[] = [];
	for (const d of fs.readdirSync(out, { withFileTypes: true })) {
		if (!d.isDirectory()) continue;
		const p = d.name === 'genomes' ? path.join(out, 'genomes', genome) : path.join(out, d.name, genome);
		if (fs.existsSync(p) && fs.statSync(p).isDirectory()) roots.push(fs.realpathSync(p));
	}
	if (!roots.length) throw new ChatError(`No results for ${genome} yet.`, 404);
	const table = path.join(out, 'genomes', genome, 'scoring', 'FINAL_ANNOTATION_WITH_CONFIDENCE.tsv');
	return {
		roots,
		base: out,
		table: fs.existsSync(table) ? table : null,
		depth: 3,
		async inside(rel) {
			const abs = path.resolve(out, String(rel ?? '').replace(/^\/+/, ''));
			let real: string;
			try {
				real = fs.realpathSync(abs);
			} catch {
				return null;
			}
			return roots.some((r) => real === r || real.startsWith(r + path.sep)) ? real : null;
		},
		async list(dir) {
			return fs
				.readdirSync(dir, { withFileTypes: true })
				.map((e) => ({ name: e.name, dir: e.isDirectory(), size: e.isDirectory() ? 0 : fs.statSync(path.join(dir, e.name)).size }));
		},
		async isDir(p) {
			return fs.statSync(p).isDirectory();
		},
		async read(file) {
			return fs.readFileSync(file, 'utf8');
		}
	};
}

/**
 * What the Results page knows of a cluster genome: the tunnelled API and
 * sign-in, the genome's folders, report table and jobs. Files inside a job's
 * folder are read whole, elsewhere only the first megabyte.
 */
export interface Remote {
	api: string;
	token: string;
	roots: string[];
	table?: string | null;
	jobs?: { id: string; dir: string }[];
}

function remoteSource(genome: string, r: Remote): Source {
	let api: URL;
	try {
		api = new URL(String(r?.api ?? ''));
	} catch {
		throw new ChatError('The cluster’s address is missing. Reconnect to the HPC and try again.', 400);
	}
	// The sign-in goes only to the app's own tunnel, never anywhere else.
	if (!['127.0.0.1', 'localhost', '[::1]'].includes(api.hostname) || !['http:', 'https:'].includes(api.protocol))
		throw new ChatError('Chat reads cluster results only through the app’s own connection.', 400);
	const clean = (p: unknown) => (typeof p === 'string' && p.startsWith('/') ? path.posix.normalize(p).replace(/\/+$/, '') : '');
	const roots = [...new Set((Array.isArray(r.roots) ? r.roots : []).map(clean).filter((p) => p.length > 1))];
	if (!roots.length) throw new ChatError(`No results for ${genome} on the cluster yet.`, 404);
	const jobs = (Array.isArray(r.jobs) ? r.jobs : []).map((j) => ({ id: String(j.id), dir: clean(j.dir) })).filter((j) => j.id && j.dir);
	// Shown relative to the deepest folder all of them share.
	const parts = roots.map((p) => p.split('/'));
	const common: string[] = [];
	for (let i = 0; parts.every((q) => q[i] !== undefined && q[i] === parts[0][i]); i++) common.push(parts[0][i]);
	let base = common.join('/') || '/';
	// One folder: shown from the folder above it, so paths start with its name.
	if (roots.includes(base)) base = path.posix.dirname(base);
	const within = (p: string) => roots.some((root) => p === root || p.startsWith(root + '/'));
	const table = clean(r.table);

	async function get(pathAndQuery: string): Promise<Response> {
		let res: Response;
		try {
			res = await fetch(new URL(pathAndQuery, api), { headers: { Authorization: `Bearer ${r.token}` } });
		} catch {
			throw new ChatError('The cluster cannot be reached. Is the HPC still connected?', 503);
		}
		if (res.status === 401) throw new ChatError('The cluster sign-in has ended. Sign in again, then ask.', 401);
		return res;
	}
	const q = encodeURIComponent;
	return {
		roots,
		base,
		table: table && within(table) ? table : null,
		depth: 2,
		async inside(p) {
			const s = String(p ?? '');
			const abs = path.posix.normalize(s.startsWith('/') ? s : path.posix.join(base, s)).replace(/\/+$/, '');
			return within(abs) ? abs : null;
		},
		async list(dir) {
			const res = await get(`/v1/ssh/browse?path=${q(dir)}`);
			if (!res.ok) throw new Error(`cannot list ${dir}`);
			const d = (await res.json()) as { entries: { name: string; type: string; size: number }[] };
			return d.entries.map((e) => ({ name: e.name, dir: e.type === 'directory', size: e.size ?? 0 }));
		},
		async isDir(p) {
			if (TEXT.test(p)) return false;
			try {
				await this.list(p);
				return true;
			} catch {
				return false;
			}
		},
		async read(file) {
			const job = jobs.find((j) => file.startsWith(j.dir + '/'));
			if (job) {
				const res = await get(`/v1/ssh/download_file/${q(job.id)}?path=${q(file.slice(job.dir.length + 1))}`);
				if (res.ok) return await res.text();
			}
			const res = await get(`/v1/ssh/browse_view?path=${q(file)}`);
			if (!res.ok) {
				const why = res.status === 404 ? 'it is not there (a link to a file that has moved, or one not written yet)' : res.status === 403 ? 'permission denied' : `the cluster said ${res.status}`;
				throw new ReadError(`Could not read ${file}: ${why}.`);
			}
			const d = (await res.json()) as { content: string; binary: boolean; truncated: boolean };
			if (d.binary) return '';
			return d.truncated ? `${d.content}\n[only the first megabyte of this file can be read from here]` : d.content;
		}
	};
}

// ------------------------------------------------------------------ one question

export interface Evidence {
	id: string;
	kind: 'list' | 'read' | 'search';
	/** As shown: relative to the folder the genome's results are in. */
	path: string;
	detail: string;
	/** Where it actually is (on the cluster, inside the run's own folder): what links open. */
	full?: string;
}

export interface Turn {
	role: 'user' | 'assistant';
	text: string;
	at: string;
	evidence?: Evidence[];
	provider?: Provider;
	model?: string;
	read?: number;
	/** What the researcher had open when asking (a gene, an operon, a contig, a tab or filter). */
	context?: string;
}

/** Formats a question for the model: what was open, then the question. */
const withContext = (t: Turn) => (t.role === 'user' && t.context ? `[Open in MARGIE when asked: ${t.context}]\n\n${t.text}` : t.text);

/** A file that could not be read; reported to the model, not the researcher. */
class ReadError extends Error {}

export class ChatError extends Error {
	constructor(
		message: string,
		readonly status: number
	) {
		super(message);
	}
}

/** Builds the three tools, bound to one genome's folders, one reading budget and one evidence list. */
function toolkit(genome: string, budget: number, src: Source) {
	const { roots, base: out } = src;
	const rel = (p: string) => path.posix.relative(out.split(path.sep).join('/'), p.split(path.sep).join('/'));
	const evidence: Evidence[] = [];
	let used = 0;
	const cite = (kind: Evidence['kind'], p: string, detail: string, full?: string) => {
		const id = `E${evidence.length + 1}`;
		evidence.push({ id, kind, path: p, detail, ...(full ? { full } : {}) });
		return id;
	};
	const spend = (text: string): string => {
		const left = budget - used;
		if (left <= 0) return '[reading budget used up: answer with what you have read]';
		const t = tokensOf(text);
		if (t <= left) {
			used += t;
			return text;
		}
		used = budget;
		return text.slice(0, left * 4) + '\n[cut off: the reading budget ran out here]';
	};
	const table = src.table;
	const join = (d: string, n: string) => (d.endsWith('/') || d.endsWith(path.sep) ? d + n : `${d}${out.includes('\\') ? path.sep : '/'}${n}`);

	async function listFiles(dir?: string): Promise<string> {
		const starts = dir ? [await src.inside(dir)] : roots;
		if (starts.some((s) => !s)) return `Not in ${genome}'s results: ${dir}`;
		const lines: string[] = [];
		const walk = async (d: string, depth: number) => {
			if (lines.length > 400) return;
			let entries: { name: string; dir: boolean; size: number }[];
			try {
				entries = await src.list(d);
			} catch {
				return;
			}
			for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
				const p = join(d, e.name);
				if (e.dir) {
					lines.push(`${rel(p)}/`);
					if (depth < src.depth) await walk(p, depth + 1);
				} else {
					lines.push(`${rel(p)}  (${e.size} bytes)`);
				}
			}
		};
		for (const s of starts) await walk(s!, 0);
		const id = cite('list', dir ?? `${genome}'s results`, `${lines.length} entries`, starts.length === 1 ? starts[0]! : undefined);
		return spend(`[${id}] files under ${dir ?? `${genome}'s results`}:\n${lines.join('\n')}`);
	}

	async function readFile(p: string, startLine = 1, maxLines = 200): Promise<string> {
		const real = await src.inside(p);
		if (!real) return `Not in ${genome}'s results: ${p}`;
		if (await src.isDir(real)) return listFiles(p);
		if (!TEXT.test(real)) return `${p} is not a text file (tables, logs and text only).`;
		const all = (await src.read(real)).split('\n');
		const from = Math.max(1, Math.floor(startLine));
		const n = Math.max(1, Math.min(2000, Math.floor(maxLines)));
		const chunk = all.slice(from - 1, from - 1 + n);
		const id = cite('read', rel(real), `lines ${from}-${from + chunk.length - 1} of ${all.length}`, real);
		return spend(`[${id}] ${rel(real)}, lines ${from}-${from + chunk.length - 1} of ${all.length}:\n${chunk.join('\n')}`);
	}

	const KEEP = ['gene_id', 'RAST_feature_id', 'FEATURE_TYPE', 'RAST_start', 'RAST_end', 'IS_IN_OPERON?', 'UniOP_OPERON_id', 'best_consensus_product_descriptor', 'best_consensus_product_descriptor_source', 'ADJUSTED_CONFIDENCE_WITH_OPERON_CONTEXT', 'CONFIDENCE_TIER', 'NEEDS_REVIEW?', 'NEEDS_REVIEW_REASON'];
	/** The table is read once per question, however many searches there are. */
	let tableText: Promise<string> | null = null;
	async function searchTable(query: string, maxRows = 20): Promise<string> {
		if (!table) return `${genome} has no report table yet.`;
		tableText ??= src.read(table);
		const [head, ...rows] = (await tableText).split('\n').filter(Boolean);
		if (!head) return `${genome}'s report table could not be read.`;
		const cols = head.split('\t').map((c) => c.replace(/^Column-[A-Z]+:\s*/, ''));
		const keep = KEEP.map((k) => cols.indexOf(k)).filter((i) => i >= 0);
		const q = String(query ?? '').toLowerCase().trim();
		const hits = rows.filter((r) => r.toLowerCase().includes(q));
		const shown = hits.slice(0, Math.max(1, Math.min(100, Math.floor(maxRows))));
		const id = cite('search', rel(table), `"${query}": ${hits.length} row${hits.length === 1 ? '' : 's'}`, table);
		const body = [keep.map((i) => cols[i]).join('\t'), ...shown.map((r) => keep.map((i) => r.split('\t')[i] ?? '').join('\t'))].join('\n');
		return spend(
			`[${id}] ${rel(table)}: ${hits.length} of ${rows.length} genes match "${query}"${hits.length > shown.length ? ` (first ${shown.length} shown)` : ''}; key columns only (read the file for all ${cols.length}):\n${body}`
		);
	}

	return { out, roots, rel, table, evidence, used: () => used, listFiles, readFile, searchTable };
}

function systemPrompt(genome: string, rootsRel: string[], tablePath: string) {
	return `You help a researcher understand the annotation of one prokaryotic genome, "${genome}", produced by MARGIE (gene calling, a dozen annotation tools, operon prediction, consolidation, labelling and confidence scoring into tiers highest/high/medium/fair/low).

You can read only this genome's results, with the tools list_files, read_file and search_table. Its folders are: ${rootsRel.join(', ')}. The report table is ${tablePath} (one row per gene; confidence columns C1-C4, CONFIDENCE_TIER, NEEDS_REVIEW?). Each tool's folder has a *-pipeline-log.txt with the commands it ran.

Every tool result starts with an evidence tag such as [E3]. Base your answer only on what you read, and cite the tags for each claim. If what you read does not settle the question, say so and say what would. Reading is limited by a budget, so search before reading whole files, and read only the lines you need.

A question may start with what the researcher had open in MARGIE (a gene, an operon, a contig, a table filter). Treat that as the subject when the question does not name one (\"this gene\", \"here\"), but you may read anything else in the genome's results.

Answer in well-structured Markdown: short headings where they help, bullet lists, and tables for tabular facts. Do not paste raw file contents or code blocks unless asked.`;
}

/** Asks one question about a genome; returns the answer and the evidence it read. */
export async function ask(genomeIn: unknown, question: string, contextIn?: unknown, remote?: Remote | null): Promise<Turn> {
	const genome = safeGenome(genomeIn);
	const q = String(question ?? '').trim();
	const context = String(contextIn ?? '').trim().slice(0, 600);
	if (!q) throw new ChatError('Ask a question first.', 400);
	const { settings, keys } = load();
	const p = settings.provider;
	if (p === 'builtin') throw new ChatError(builtinStatus().note, 400);
	if (!settings.consented.includes(p)) throw new ChatError('Read and accept the data notice for this provider first.', 400);
	const key = keys[p] ?? onHpc[p];
	if (!key && p !== 'custom') throw new ChatError(`Add your ${PROVIDERS[p].label} API key first.`, 400);

	const where = remote ? 'hpc' : 'local';
	const kit = toolkit(genome, settings.budget, remote ? remoteSource(genome, remote) : localSource(genome));
	const history = readHistory(genome, where).slice(-12);
	const system = systemPrompt(genome, kit.roots.map(kit.rel), kit.table ? kit.rel(kit.table) : `genomes/${genome}/scoring/FINAL_ANNOTATION_WITH_CONFIDENCE.tsv (not made yet)`);

	const asked: Turn = { role: 'user', text: q, at: new Date().toISOString(), ...(context ? { context } : {}) };
	const text =
		p === 'anthropic'
			? await askClaude(kit, settings, key!, system, history, withContext(asked))
			: await askOpenAI(kit, settings, p, key ?? '', system, history, withContext(asked));

	const now = new Date().toISOString();
	const answer: Turn = { role: 'assistant', text, at: now, evidence: kit.evidence, provider: p, model: settings.model, read: kit.used() };
	writeHistory(genome, [...readHistory(genome, where), asked, answer], where);
	return answer;
}

type Kit = ReturnType<typeof toolkit>;

const TOOL_DOCS = {
	list_files: {
		description: "List the files and folders in this genome's results (or under one folder of them), with sizes.",
		schema: { type: 'object', properties: { dir: { type: 'string', description: 'A folder path as listed, relative to the results folder. Leave out for all of the genome’s folders.' } }, additionalProperties: false } as const
	},
	read_file: {
		description: "Read lines of one text file in this genome's results (tables, logs, text).",
		schema: {
			type: 'object',
			properties: {
				path: { type: 'string', description: 'The file path as listed, relative to the results folder.' },
				start_line: { type: 'integer', description: 'First line to read (1-based). Default 1.' },
				max_lines: { type: 'integer', description: 'How many lines (default 200, at most 2000).' }
			},
			required: ['path'],
			additionalProperties: false
		} as const
	},
	search_table: {
		description: "Search the genome's report table (one row per gene) for a word, gene id, product name, EC number or operon id; returns matching genes with their key columns.",
		schema: {
			type: 'object',
			properties: { query: { type: 'string' }, max_rows: { type: 'integer', description: 'Default 20, at most 100.' } },
			required: ['query'],
			additionalProperties: false
		} as const
	}
};

/**
 * Runs one tool call. Read failures go back to the model as text; only a lost
 * sign-in or connection (ChatError 401 or 503) stops the answer.
 */
async function runTool(kit: Kit, name: string, input: Record<string, unknown>): Promise<string> {
	try {
		if (name === 'list_files') return await kit.listFiles(typeof input.dir === 'string' ? input.dir : undefined);
		if (name === 'read_file') return await kit.readFile(String(input.path ?? ''), Number(input.start_line ?? 1) || 1, Number(input.max_lines ?? 200) || 200);
		if (name === 'search_table') return await kit.searchTable(String(input.query ?? ''), Number(input.max_rows ?? 20) || 20);
		return `No tool named ${name}.`;
	} catch (e) {
		if (e instanceof ChatError && (e.status === 401 || e.status === 503)) throw e;
		return `[not read] ${e instanceof Error ? e.message : String(e)} Try another file, or answer with what you have.`;
	}
}

async function askClaude(kit: Kit, s: ChatSettings, key: string, system: string, history: Turn[], q: string): Promise<string> {
	const client = new Anthropic({ apiKey: key });
	const tools = [
		betaTool({ name: 'list_files', description: TOOL_DOCS.list_files.description, inputSchema: TOOL_DOCS.list_files.schema, run: (i) => runTool(kit, 'list_files', i) }),
		betaTool({ name: 'read_file', description: TOOL_DOCS.read_file.description, inputSchema: TOOL_DOCS.read_file.schema, run: (i) => runTool(kit, 'read_file', i) }),
		betaTool({ name: 'search_table', description: TOOL_DOCS.search_table.description, inputSchema: TOOL_DOCS.search_table.schema, run: (i) => runTool(kit, 'search_table', i) })
	];
	const model = s.model || 'claude-opus-5';
	// Haiku takes no adaptive thinking; Opus 5 and Fable 5.1 pass declined requests to a fallback model.
	const thinks = !model.startsWith('claude-haiku');
	const falls = model === 'claude-opus-5' || model === 'claude-fable-5-1';
	try {
		const message = await client.beta.messages.toolRunner({
			model,
			max_tokens: s.answerTokens,
			system,
			messages: [...history.map((t) => ({ role: t.role, content: withContext(t) })), { role: 'user' as const, content: q }],
			tools,
			max_iterations: 10,
			...(thinks ? { thinking: { type: 'adaptive' as const } } : {}),
			...(falls ? { betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default' as const } : {})
		});
		if (message.stop_reason === 'refusal') return '_The model declined to answer this question._';
		const text = message.content
			.filter((b): b is Anthropic.Beta.BetaTextBlock => b.type === 'text')
			.map((b) => b.text)
			.join('\n\n')
			.trim();
		if (message.stop_reason === 'max_tokens') return `${text}\n\n_The answer reached its length limit; raise "Answer length" to let it finish._`;
		return text || '_No answer came back._';
	} catch (e) {
		if (e instanceof Anthropic.AuthenticationError) throw new ChatError('Claude did not accept the API key.', 401);
		if (e instanceof Anthropic.PermissionDeniedError) throw new ChatError('This API key may not use that model.', 403);
		if (e instanceof Anthropic.NotFoundError) throw new ChatError(`No model named "${model}".`, 404);
		if (e instanceof Anthropic.RateLimitError) throw new ChatError('Claude is limiting requests from this key; try again in a moment.', 429);
		if (e instanceof Anthropic.BadRequestError) throw new ChatError(`Claude refused the request: ${e.message}`, 400);
		if (e instanceof Anthropic.APIError) throw new ChatError(`Claude answered with an error (${e.status}): ${e.message}`, 502);
		throw new ChatError(`Could not reach Claude: ${e instanceof Error ? e.message : String(e)}`, 502);
	}
}

/** Asks OpenAI, Gemini or an OpenAI-compatible service via chat completions, looping over the same three tools. */
async function askOpenAI(kit: Kit, s: ChatSettings, p: Provider, key: string, system: string, history: Turn[], q: string): Promise<string> {
	const base = (p === 'custom' ? s.baseUrl : PROVIDERS[p].base).replace(/\/+$/, '');
	if (!base) throw new ChatError('Give the service’s base URL first (it ends in /v1).', 400);
	if (!s.model) throw new ChatError('Choose a model first.', 400);
	const tools = (Object.keys(TOOL_DOCS) as (keyof typeof TOOL_DOCS)[]).map((name) => ({
		type: 'function',
		function: { name, description: TOOL_DOCS[name].description, parameters: TOOL_DOCS[name].schema }
	}));
	type Msg = Record<string, unknown>;
	const messages: Msg[] = [{ role: 'system', content: system }, ...history.map((t) => ({ role: t.role, content: withContext(t) })), { role: 'user', content: q }];
	for (let step = 0; step < 10; step++) {
		let r: Response;
		try {
			r = await fetch(`${base}/chat/completions`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json', ...(key ? { Authorization: `Bearer ${key}` } : {}) },
				body: JSON.stringify({
					model: s.model,
					messages,
					tools,
					...(p === 'openai' ? { max_completion_tokens: s.answerTokens } : { max_tokens: s.answerTokens })
				})
			});
		} catch (e) {
			throw new ChatError(`Could not reach ${PROVIDERS[p].label}: ${e instanceof Error ? e.message : String(e)}`, 502);
		}
		const d = await r.json().catch(() => ({}));
		if (!r.ok) {
			const why = d?.error?.message ?? d?.message ?? r.statusText;
			throw new ChatError(r.status === 401 ? `${PROVIDERS[p].label} did not accept the API key.` : `${PROVIDERS[p].label} answered with an error (${r.status}): ${why}`, r.status === 401 ? 401 : 502);
		}
		const m = d?.choices?.[0]?.message;
		if (!m) throw new ChatError('The service sent no answer.', 502);
		const calls: { id: string; function: { name: string; arguments: string } }[] = m.tool_calls ?? [];
		if (!calls.length) {
			const text = String(m.content ?? '').trim();
			return d.choices[0].finish_reason === 'length' ? `${text}\n\n_The answer reached its length limit; raise "Answer length" to let it finish._` : text || '_No answer came back._';
		}
		messages.push({ role: 'assistant', content: m.content ?? null, tool_calls: calls });
		for (const c of calls) {
			let input: Record<string, unknown> = {};
			try {
				input = JSON.parse(c.function.arguments || '{}');
			} catch {
				messages.push({ role: 'tool', tool_call_id: c.id, content: 'The arguments were not valid JSON; try again.' });
				continue;
			}
			messages.push({ role: 'tool', tool_call_id: c.id, content: await runTool(kit, c.function.name, input) });
		}
	}
	return '_The model kept reading without answering; ask a narrower question or raise the reading budget._';
}

// ------------------------------------------------------------------ the conversation, kept per genome

const CHATS = path.join(PIPELINE_ROOT, 'logs', 'chat');
/** Where the genome's results are; local and cluster histories stay apart, as one name may be two genomes. */
export type Where = 'local' | 'hpc';
const chatFile = (g: string, where: Where = 'local') => path.join(CHATS, `${where === 'hpc' ? 'hpc-' : ''}${safeGenome(g)}.json`);

export function readHistory(genome: string, where: Where = 'local'): Turn[] {
	try {
		return JSON.parse(fs.readFileSync(chatFile(genome, where), 'utf8'));
	} catch {
		return [];
	}
}

function writeHistory(genome: string, turns: Turn[], where: Where = 'local') {
	fs.mkdirSync(CHATS, { recursive: true });
	fs.writeFileSync(chatFile(genome, where), JSON.stringify(turns, null, 2) + '\n');
}

export function clearHistory(genome: string, where: Where = 'local') {
	fs.rmSync(chatFile(genome, where), { force: true });
}
