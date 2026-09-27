/**
 * Answers the interface's local API routes (routes/api/local shapes) from
 * MARGIE's cluster API: jobs, SFTP browsing, config.yaml and licence status.
 * Routes with no cluster meaning return 501 with an explanation.
 */

import { ApiError, type Run } from '$lib/api';
import { isWorkflowPathParam } from '$lib/configParams';
import { backend } from '$lib/workspace/backend.svelte';
import type { CheckRow, Genome, GenomeSummary, OrganismResult, Overview, Setting, SetupRow, Tool } from '$lib/workspace/data.svelte';
import { FinalTally, type FinalCounts } from '$lib/workspace/final-summary';
import { TABLE_EXT, extOf, parseDelimited, queryFromParams, queryLoaded, type CellStyle, type Table } from '$lib/workspace/viewers/table-query';
import { sheetsOf } from '$lib/workspace/viewers/excel-sheets';
import { call, fetchRaw, get } from './http';
import { getApiUrl } from '$lib/config';
import { getToken } from '$lib/auth';
import type { ChatRemote } from '$lib/workspace/cluster-parts';

/** The workflow a Crisp run starts on the cluster. */
export const WORKFLOW = 'margie_sb';
const GENOME_EXT = /\.(fasta|fa|fna)(\.gz)?$/i;
/**
 * Stages every run includes. "rasttk" is phase 3's key whichever gene caller
 * the genome gets (RASTtk or Prodigal).
 */
const ALWAYS = ['rasttk', 'operon', 'consolidation', 'labeling', 'fingerprint', 'fingerprint_database', 'scoring_heuristic'];
/** Tools the envelope stage reads; it runs when a later tool needs it. */
const ENVELOPE_INPUTS = ['tigrfam', 'pgap', 'pfam', 'uniprot'];
const ENVELOPE_PHASE = 7;

/** Throws a 501 for features the cluster does not offer. */
const notHere = (what: string): never => {
	throw new ApiError(what, 501);
};
const baseName = (p: string) => p.split('/').filter(Boolean).at(-1) ?? p;
const q = encodeURIComponent;

// ---- API response shapes ----

interface Me {
	username: string;
	cluster_host: string;
	cluster_username: string;
	home_dir: string;
}
interface Param {
	param: string;
	default: unknown;
	description: string;
	type: string;
	required?: boolean;
}
interface WorkflowTool {
	key?: string;
	phase?: number;
	name: string;
	purpose: string;
}
interface Workflow {
	id: string;
	label: string;
	tools: WorkflowTool[];
	configurable_params: Param[];
	/** The container images a run checks for before it starts. */
	containers?: { name: string }[];
}
interface LicenceStatus {
	accepted: boolean;
	usage_type: string | null;
	licensed_tools: string[];
	disabled_tools: string[];
}
interface JobRow {
	job_id: string;
	status: string;
	phase?: string | null;
	genome_path?: string | null;
	workflow?: string | null;
	work_dir?: string | null;
	selected_tools?: string | string[] | null;
	start_time?: string | null;
	end_time?: string | null;
	logs?: string | null;
	progress?: number | null;
	steps_done?: number | null;
	steps_total?: number | null;
	status_note?: string | null;
}
interface Entry {
	name: string;
	type: 'file' | 'directory';
	size: number;
	mtime?: number | null;
}

type Config = Record<string, any>;

/** Caches an async answer for `ms` and shares one in-flight request. */
class Cache<T> {
	#value: T | undefined;
	#at = 0;
	#pending: Promise<T> | null = null;
	constructor(
		private readonly load: () => Promise<T>,
		private readonly ms: number
	) {}
	get(): Promise<T> {
		if (this.#value !== undefined && Date.now() - this.#at < this.ms) return Promise.resolve(this.#value);
		this.#pending ??= this.load()
			.then((v) => {
				this.#value = v;
				this.#at = Date.now();
				return v;
			})
			.finally(() => (this.#pending = null));
		return this.#pending;
	}
	set(v: T) {
		this.#value = v;
		this.#at = Date.now();
	}
	drop() {
		this.#value = undefined;
	}
}

const me = new Cache<Me>(async () => {
	const m = await get<Me>('/v1/auth/me');
	backend.host = m.cluster_host;
	backend.user = m.cluster_username;
	return m;
}, 10 * 60_000);
const workflows = new Cache(() => get<Workflow[]>('/v1/ssh/workflows'), 10 * 60_000);
const config = new Cache(() => get<Config>('/v1/ssh/config'), 20_000);
const licence = new Cache(() => get<LicenceStatus>('/v1/license/status'), 60_000);
const status = new Cache(
	() => get<{ connected: boolean; host: string; detail?: string }>('/v1/ssh/status').catch((e) => ({ connected: false, host: '', detail: String(e.message ?? e) })),
	60_000
);
const jobs = new Cache(async () => {
	const d = await get<{ jobs: JobRow[] }>('/v1/ssh/jobs?page=1&page_size=50');
	return d.jobs ?? [];
}, 6_000);

/** Drops cached answers after the licence or config changes elsewhere (e.g. the Install page). */
export function forget(what: 'licence' | 'config' | 'all') {
	if (what === 'licence' || what === 'all') licence.drop();
	if (what === 'config' || what === 'all') {
		config.drop();
		installed.drop();
	}
	if (what === 'all') {
		jobs.drop();
		status.drop();
		resultList.drop();
	}
}

/** Returns the margie_sb workflow description from the API. */
async function workflow(): Promise<Workflow> {
	const w = (await workflows.get()).find((x) => x.id === WORKFLOW);
	if (!w) throw new ApiError(`This API does not offer the ${WORKFLOW} workflow.`, 404);
	return w;
}

/** Reads a dotted key from the config. */
function dig(obj: Config, dotted: string): unknown {
	return dotted.split('.').reduce<any>((o, k) => (o == null ? undefined : o[k]), obj);
}
/** Sets a dotted key in the config, creating objects on the way. */
function place(obj: Config, dotted: string, value: unknown) {
	const keys = dotted.split('.');
	const last = keys.pop() as string;
	let o = obj;
	for (const k of keys) {
		if (typeof o[k] !== 'object' || o[k] === null) o[k] = {};
		o = o[k];
	}
	o[last] = value;
}
const str = (v: unknown) => (v === null || v === undefined ? '' : typeof v === 'boolean' ? (v ? '1' : '0') : String(v));

/**
 * Per-genome domain and genetic code in config.yaml's margie_sb.genome_info.
 * Genomes missing either go to Prodigal unless GTDB-Tk is on. Set as one object,
 * not through place(), because file names contain dots.
 */
type GenomeInfo = Record<string, { domain?: string; genetic_code?: string | number }>;
const genomeInfo = (cfg: Config): GenomeInfo => {
	const v = dig(cfg, `${WORKFLOW}.genome_info`);
	return v && typeof v === 'object' ? (v as GenomeInfo) : {};
};
const genomeStem = (n: string) => n.replace(/\.gz$/i, '').replace(/\.(fasta|fna|fa)$/i, '');
/** Switch for running GTDB-Tk first; off by default as it needs a highmem node. */
const USE_GTDBTK = `${WORKFLOW}.use_gtdbtk`;
const useGtdbtk = (cfg: Config) => ['1', 'true'].includes(str(dig(cfg, USE_GTDBTK)).toLowerCase());

/** Expands a leading ~ to the cluster home, which SFTP does not do. */
async function expand(p: string): Promise<string> {
	if (!p.startsWith('~')) return p;
	return (await me.get()).home_dir + p.slice(1);
}

// ---- jobs ----

const STATUS: Record<string, Run['status']> = {
	completed: 'completed',
	success: 'completed',
	failed: 'failed',
	error: 'failed',
	cancelled: 'cancelled',
	canceled: 'cancelled'
};

/** Returns the first error-looking line in the last 60 lines of a log. */
function reasonIn(log: string): string {
	const lines = log.split('\n').slice(-60);
	const bad = /(ERROR|Error\b|error:|FAIL|fail(ed|s)\b|Traceback|not found|No such file|missing|could not|cannot|unable|refus|denied|invalid)/i;
	return lines.find((l) => bad.test(l))?.trim().slice(0, 240) ?? '';
}

/** Normalises selected_tools (list or comma/space string) to an array. */
function toList(v: string | string[] | null | undefined): string[] {
	if (!v) return [];
	if (Array.isArray(v)) return v.filter(Boolean).map(String);
	return String(v).split(/[,\s]+/).filter(Boolean);
}

/** Converts an API job row to the interface's Run shape. */
function toRun(j: JobRow): Run {
	const tools = toList(j.selected_tools);
	const input = j.genome_path ?? '';
	const status = STATUS[String(j.status || '').toLowerCase()] ?? 'running';
	const steps = j.steps_total ? `${j.steps_done ?? 0} of ${j.steps_total} steps` : '';
	const progress = status === 'completed' ? 100 : typeof j.progress === 'number' ? Math.round(j.progress) : undefined;
	const log = j.logs ?? '';
	return {
		id: j.job_id,
		kind: 'annotate',
		label: `Annotate ${baseName(input) || 'genomes'}${tools.length ? ` with ${tools.length} tools` : ''}`,
		args: [],
		command: `${j.workflow ?? WORKFLOW}${tools.length ? ` --tools ${tools.join(',')}` : ' (every tool)'}${input ? `  ${input}` : ''}`,
		started: j.start_time ?? '',
		finished: j.end_time ?? undefined,
		status,
		exitCode: null,
		tools,
		files: input ? [baseName(input)] : [],
		outputDir: j.work_dir ?? undefined,
		progress,
		progressText: [j.phase, steps].filter(Boolean).join(' | ') || undefined,
		reason: status === 'failed' || status === 'cancelled' ? reasonIn(log) || j.phase || '' : ''
	};
}

async function listRuns() {
	return { runs: (await jobs.get()).map(toRun) };
}

/**
 * Returns a job and the new part of its log. The API slices the log
 * (log_tail / log_offset); an older API sends it whole and it is sliced here.
 */
async function runDetail(id: string, params: URLSearchParams) {
	const tail = Number(params.get('tail')) || 0;
	const offset = Math.max(0, Number(params.get('offset')) || 0);
	const ask = tail ? `?log_tail=${tail}` : `?log_offset=${offset}`;
	const j = await get<JobRow & { logs_size?: number; logs_offset?: number }>(`/v1/ssh/job_status/${q(id)}${ask}`);
	const got = j.logs ?? '';
	if (typeof j.logs_size === 'number') {
		return { run: toRun(j), step: j.phase ?? '', log: { text: got, offset: j.logs_size, size: j.logs_size } };
	}
	const text = tail ? got.slice(-tail) : got.slice(Math.min(offset, got.length));
	return { run: toRun(j), step: j.phase ?? '', log: { text, offset: got.length, size: got.length } };
}

/** Builds the tool selection from the request and config, then submits the workflow. */
async function startRun(body: { kind?: string; tools?: string[]; all?: boolean; genomes?: string[] }) {
	if (body.kind !== 'annotate') return notHere('Tools and databases on the cluster are installed by its administrators, not from here.');
	const w = await workflow();
	const cfg = await config.get();
	const lic = await licence.get();
	const known = new Map(w.tools.filter((t) => t.key).map((t) => [t.key as string, t]));
	const disabled = new Set(lic.disabled_tools);
	// No tools chosen: only gene calling runs.
	const chosen = new Set(body.tools?.length ? [...ALWAYS, ...body.tools] : ['rasttk']);
	// GTDB-Tk follows its switch only, never the tool list.
	chosen.delete('gtdbtk');
	if (useGtdbtk(cfg)) chosen.add('gtdbtk');
	// Tools after the envelope stage need it and its inputs.
	if ([...chosen].some((k) => (known.get(k)?.phase ?? 0) > ENVELOPE_PHASE && !ALWAYS.includes(k))) {
		for (const k of ['envelope', ...ENVELOPE_INPUTS]) chosen.add(k);
	}
	const selected = [...chosen].filter((k) => known.has(k) && !disabled.has(k));
	// "Everything" is sent as no list, which also runs GTDB-Tk, so it requires the switch.
	const everything = !disabled.size && [...known.keys()].every((k) => chosen.has(k)) && useGtdbtk(cfg);
	const input = str(dig(cfg, `${WORKFLOW}.input_path`));
	const output = str(dig(cfg, `${WORKFLOW}.output_path`));
	if (!input) throw new ApiError('Type the folder your genomes are in first (step 1).', 400);
	// A subset is staged by the API into its own folder; omitted, the whole input folder runs.
	const genomes = body.genomes?.length ? body.genomes : null;
	const r = await call<{ job_id: string; output_dir?: string }>('POST', '/v1/ssh/run_workflow', {
		workflow: WORKFLOW,
		genome_path: input,
		output_dir: output || null,
		selected_tools: everything ? null : selected,
		...(genomes ? { genomes } : {})
	});
	jobs.drop();
	return {
		run: toRun({
			job_id: r.job_id,
			status: 'running',
			phase: 'Submitting',
			genome_path: input,
			workflow: WORKFLOW,
			work_dir: r.output_dir ?? null,
			selected_tools: everything ? null : selected,
			start_time: new Date().toISOString()
		})
	};
}

/** Cancels a job. */
async function stopRun(id: string) {
	await call('POST', `/v1/ssh/cancel_job/${q(id)}`);
	jobs.drop();
	return { ok: true };
}

/** Resumes (after what finished) or restarts a failed or stopped job. */
async function relaunchRun(id: string, how: 'resume' | 'restart') {
	await call('POST', `/v1/ssh/${how}_job/${q(id)}`);
	jobs.drop();
	return { ok: true };
}

// ---- genomes and tools ----

/** Lists a folder on the cluster over SFTP. */
async function browse(path: string): Promise<{ path: string; entries: Entry[] }> {
	return get(`/v1/ssh/browse?path=${q(await expand(path))}`);
}

/** Lists genome files in the input folder (or the single input file) with their genome_info. */
async function listGenomes() {
	const cfg = await config.get();
	const folder = str(dig(cfg, `${WORKFLOW}.input_path`));
	const empty = { folder, genomes: [] as Genome[], nested: [], runGtdbtk: useGtdbtk(cfg), geneticCodes: ['11', '4', '25'] };
	if (!folder) return empty;
	const info = genomeInfo(cfg);
	const infoOf = (name: string) => info[name] ?? info[genomeStem(name)] ?? {};
	const asGenome = (e: Entry): Genome => {
		const i = infoOf(e.name);
		const d = str(i.domain).toLowerCase();
		return {
			name: e.name,
			size: e.size,
			domain: d.startsWith('b') ? 'Bacteria' : d.startsWith('a') ? 'Archaea' : '',
			genetic_code: /^\d+$/.test(str(i.genetic_code)) ? str(i.genetic_code) : ''
		};
	};
	try {
		const d = await browse(folder);
		return { ...empty, genomes: d.entries.filter((e) => e.type === 'file' && GENOME_EXT.test(e.name)).map(asGenome) };
	} catch (e) {
		// The input may be a single genome file.
		if (e instanceof ApiError && e.status === 400 && GENOME_EXT.test(folder)) {
			const parent = folder.slice(0, folder.lastIndexOf('/')) || '/';
			const d = await browse(parent).catch(() => null);
			const one = d?.entries.find((x) => x.name === baseName(folder));
			return { ...empty, genomes: one ? [asGenome(one)] : [] };
		}
		if (e instanceof ApiError && e.status === 404) return empty;
		throw e;
	}
}

/**
 * Saves the Genomes table's domain and genetic code into margie_sb.genome_info.
 * Other entries are kept; a row with both fields cleared is removed.
 */
async function saveGenomeInfo(body: { rows?: { name: string; domain: string; genetic_code: string }[] }) {
	const cfg = structuredClone(await get<Config>('/v1/ssh/config'));
	const info: GenomeInfo = { ...genomeInfo(cfg) };
	for (const r of body.rows ?? []) {
		delete info[genomeStem(r.name)];
		if (r.domain || r.genetic_code) info[r.name] = { domain: r.domain, genetic_code: r.genetic_code };
		else delete info[r.name];
	}
	const section = (cfg[WORKFLOW] ??= {}) as Config;
	section.genome_info = info;
	await call('PUT', '/v1/ssh/config', cfg);
	config.set(cfg);
	return { ok: true };
}

/** Returns a stores answer and drops cached config and assets, which it may have changed. */
async function storesAnswer<T>(p: Promise<T>): Promise<T> {
	const r = await p;
	config.drop();
	installed.drop();
	return r;
}

/** Uploadable genome file names: the workflow's extensions, excluding gzipped (not text). */
const UPLOADABLE = /^[A-Za-z0-9._-]+\.(fasta|fa|fna)$/i;

/**
 * Uploads FASTA files into the cluster input folder via /browse_save.
 * Existing files are never overwritten.
 */
async function addGenomes(form: FormData) {
	const folder = await expand(str(dig(await config.get(), `${WORKFLOW}.input_path`)));
	if (!folder) throw new ApiError('Type the folder on the cluster that genomes go in first (step 1 on Analyze).', 400);
	if (GENOME_EXT.test(folder)) throw new ApiError('The input path is one genome file; make it a folder to add more.', 400);
	const there = new Set((await browse(folder).catch(() => ({ entries: [] as Entry[] }))).entries.map((e) => e.name));
	const added: string[] = [];
	const skipped: string[] = [];
	for (const f of form.getAll('files')) {
		if (!(f instanceof File)) continue;
		if (!UPLOADABLE.test(f.name)) {
			skipped.push(`${f.name}: the cluster reads .fasta, .fa and .fna`);
			continue;
		}
		if (there.has(f.name)) {
			skipped.push(`${f.name}: already there`);
			continue;
		}
		const content = await f.text();
		if (!content.trimStart().startsWith('>')) {
			skipped.push(`${f.name}: not FASTA`);
			continue;
		}
		await call('POST', '/v1/ssh/browse_save', { path: `${folder}/${f.name}`, content });
		added.push(f.name);
	}
	if (!added.length) throw new ApiError(skipped.length ? `Nothing added. ${skipped.join('; ')}.` : 'No files to add.', 400);
	const { genomes } = await listGenomes();
	return { added, skipped, genomes };
}

/** Lists optional annotation tools with their licence state. */
async function listTools(): Promise<{ annotation: Tool[] }> {
	const [w, lic] = await Promise.all([workflow(), licence.get()]);
	const disabled = new Set(lic.disabled_tools);
	const annotation = w.tools
		// GTDB-Tk is a separate switch, not a tool.
		.filter((t) => t.key && !ALWAYS.includes(t.key) && t.key !== 'envelope' && t.key !== 'gtdbtk')
		.map((t) => ({
			name: t.key as string,
			gated: disabled.has(t.key as string),
			licensed: !disabled.has(t.key as string),
			gramDependent: (t.phase ?? 0) > ENVELOPE_PHASE && (t.phase ?? 0) < 9
		}));
	return { annotation };
}

// ---- installed assets ----

/** One row of GET /v1/ssh/assets (the backend's services/tool_assets.py). */
interface AssetRow {
	id: string;
	kind: 'image' | 'database';
	tool: string;
	label: string;
	path: string;
	status: 'ok' | 'missing' | 'unknown';
	/** GTDB-Tk and the LLM layer: run only when chosen. */
	optional: boolean;
}

/**
 * Checks each container image and database where the workflow looks for it,
 * using the backend's pre-run check. Unreadable folders are "unknown", not "missing".
 */
const installed = new Cache(async (): Promise<CheckRow[]> => {
	const d = await get<{ rows: AssetRow[] }>('/v1/ssh/assets');
	return d.rows.map((r) => {
		const status: CheckRow['status'] = r.status === 'missing' && r.optional ? 'optional' : r.status;
		return {
			status,
			name: r.tool,
			kind: r.kind,
			detail: status === 'unknown' ? `${r.path} (its folder cannot be read from your account)` : r.path,
			section: r.kind === 'image' ? 'Containers' : 'Databases',
			advice: false
		};
	});
}, 60_000);

// ---- readiness ----

/** Builds the setup overview rows: connection, SLURM, licence, history, assets, output. */
async function overview(): Promise<Overview> {
	// Failing parts show as not ready instead of failing the whole answer.
	const [m, s, cfg, lic] = await Promise.all([
		me.get(),
		status.get(),
		config.get().catch((): Config => ({})),
		licence.get().catch((): LicenceStatus => ({ accepted: false, usage_type: null, licensed_tools: [], disabled_tools: [] }))
	]);
	const account = str(dig(cfg, 'compute.cluster_default.account'));
	const partition = str(dig(cfg, 'compute.cluster_default.partition'));
	const db = str(cfg.main_database);
	const output = str(dig(cfg, `${WORKFLOW}.output_path`));
	const rows: SetupRow[] = [
		{
			id: 'cluster',
			label: 'Cluster',
			value: m.cluster_host,
			detail: s.connected ? `Signed in as ${m.cluster_username}` : (s.detail ?? 'Not reachable'),
			tone: s.connected ? 'ok' : 'danger',
			required: true,
			href: '/setup'
		},
		// Account and partition are separate rows so neither reads as part of the other.
		{
			id: 'account',
			label: 'SLURM account',
			value: account || 'Not set',
			detail: account ? 'Every job is charged to this account' : 'Every job is charged to one; none is set yet',
			tone: account ? 'ok' : 'warn',
			required: true,
			href: '/settings#compute.cluster_default.account'
		},
		{
			id: 'partition',
			label: 'Partition',
			value: partition || 'Cluster default',
			detail: partition ? 'The queue jobs are submitted to' : 'Jobs go to whichever queue the cluster uses by default',
			// Optional: the cluster's default partition is a normal choice.
			tone: 'ok',
			required: false,
			href: '/settings#compute.cluster_default.partition'
		},
		{
			id: 'terms',
			label: 'Licence terms',
			value: lic.accepted ? 'Accepted' : 'Not accepted',
			detail: lic.accepted ? `For ${lic.usage_type ?? 'your'} use` : 'Accepted once, before the first run',
			tone: lic.accepted ? 'ok' : 'warn',
			required: true,
			href: '/setup#terms'
		},
		{
			id: 'history',
			label: 'Job history',
			value: db ? baseName(db) : 'Not set',
			detail: db ? 'Where the cluster records your runs' : 'Runs are not recorded without it',
			tone: db ? 'ok' : 'warn',
			required: true,
			href: '/settings#main_database'
		},
		...(await installed
			.get()
			.then((rows): SetupRow[] => {
				const tally = (kind: string) => {
					const of = rows.filter((r) => r.kind === kind && r.status !== 'optional');
					const ok = of.filter((r) => r.status === 'ok').length;
					const unknown = of.filter((r) => r.status === 'unknown').length;
					return { ok, total: of.length, unknown };
				};
				const im = tally('image');
				const db = tally('database');
				const line = (t: { ok: number; total: number; unknown: number }, all: string) =>
					t.ok === t.total ? all : t.unknown === t.total ? 'Their folder cannot be read from your account' : `${t.total - t.ok - t.unknown} not where the config points`;
				// Informational: the run's own pre-flight check decides.
				return [
					{ id: 'cluster-tools', label: 'Tools', value: `${im.ok} / ${im.total}`, detail: line(im, 'All in the containers folder'), tone: im.ok === im.total ? 'ok' : 'warn', required: false, href: '/setup#installed' },
					{ id: 'cluster-data', label: 'Reference data', value: `${db.ok} / ${db.total}`, detail: line(db, 'All in the databases folder'), tone: db.ok === db.total ? 'ok' : 'warn', required: false, href: '/setup#installed' }
				];
			})
			.catch((): SetupRow[] => [])),
		{
			id: 'output',
			label: 'Results folder',
			value: output ? baseName(output) : 'Home folder',
			detail: output || m.home_dir,
			tone: 'neutral',
			required: false,
			href: '/settings#margie_sb.output_path'
		}
	];
	return {
		user: m.cluster_username,
		runtime: { setting: 'apptainer', active: 'apptainer', label: 'Apptainer on the cluster', ready: s.connected },
		runtimes: [],
		recommended: null,
		repo: { ok: true, path: '', reason: '', containers: [], databases: [] },
		python: { ready: true, version: '', path: '', base: null },
		licences: { tools: lic.disabled_tools, accepted: lic.licensed_tools, intendedUse: lic.usage_type ?? '' },
		gtdbtk: false,
		machine: { os: 'linux', arch: '', chip: m.cluster_host, cores: 0, memory: 0, diskFree: null, dbRoot: str(dig(cfg, `${WORKFLOW}.db_root`)) },
		rows
	};
}

// ---- settings ----

const PATHS: Record<string, string> = {
	input_path: 'Genomes folder',
	output_path: 'Results folder',
	sif_path: 'Containers folder',
	db_root: 'Databases folder',
	// Where your own databases and run archives live, and where "Back up to depot" puts copies.
	stores_root: 'Working folder',
	backup_root: 'Backup location',
	// Where margie-build is, which builds containers and databases (Install).
	build_repo: 'Build recipes (margie-build)'
};
// Per-database paths are set by the API (services/user_stores.py), not edited here.
const EXTENDED: Record<string, string> = {};
const COMPUTE: Record<string, string> = {
	account: 'SLURM account',
	partition: 'Partition',
	default_runtime: 'Time per job (min)',
	default_mem_mb: 'Memory per job (MB)',
	max_jobs: 'Jobs at once',
	driver_walltime: 'Time limit for a run'
};
const FIELD: Record<string, string> = {
	threads: 'threads',
	mem_mb: 'memory (MB)',
	runtime: 'time (min)',
	partition: 'partition',
	db: 'database',
	sif: 'container'
};
const DEFAULTS: Record<string, string> = {
	default_threads: 'Threads per tool',
	default_mem_mb: 'Memory per tool (MB)',
	default_runtime: 'Time per tool (min)'
};
/** Local setting names mapped to cluster config keys, so the same controls work on both. */
const ALIASES: Record<string, string> = {
	USER_INPUT_DIR: `${WORKFLOW}.input_path`,
	OUTPUT_ROOT: `${WORKFLOW}.output_path`,
	LOCAL_PARALLEL_TOOLS: `${WORKFLOW}.phase4.max_parallel_tools`
};

const humanize = (s: string) => s.replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase());

/** Returns a setting's label and Settings group from its config key. */
function describeParam(p: Param, toolLabel: Map<string, string>): { label: string; group: string } {
	const key = p.param;
	if (key === 'main_database') return { label: 'Job history database', group: 'Cluster' };
	if (key.startsWith('compute.cluster_default.')) {
		const k = key.slice('compute.cluster_default.'.length);
		return { label: COMPUTE[k] ?? humanize(k), group: 'Cluster' };
	}
	// A per-tool database folder override.
	if (key.startsWith('db.')) {
		const t = key.slice(3);
		return { label: `${toolLabel.get(t) ?? humanize(t)} database`, group: 'Other folders' };
	}
	const rest = key.slice(WORKFLOW.length + 1);
	if (PATHS[rest]) return { label: PATHS[rest], group: 'Folders' };
	if (EXTENDED[rest] || isWorkflowPathParam(key)) return { label: EXTENDED[rest] ?? humanize(rest), group: 'Other folders' };
	const [head, field] = rest.split('.');
	if (!field) return { label: DEFAULTS[head] ?? humanize(head), group: 'Phases' };
	const phase = head.match(/^phase(\d+)$/);
	if (phase) {
		const what = field === 'partition' ? 'partition' : field === 'max_parallel_genomes' ? 'genomes at once' : field === 'max_parallel_tools' ? 'tools at once' : humanize(field);
		return { label: `Phase ${phase[1]} ${what}`, group: 'Phases' };
	}
	return { label: `${toolLabel.get(head) ?? humanize(head)} ${FIELD[field] ?? humanize(field)}`, group: 'Per tool' };
}

const TYPES: Record<string, Setting['type']> = { int: 'int', integer: 'int', path: 'path', bool: 'flag', boolean: 'flag' };

/** Lists workflow settings with values from config.yaml, plus alias and switch entries. */
async function settingsList(): Promise<{ settings: Setting[] }> {
	const [w, cfg] = await Promise.all([workflow(), config.get()]);
	const toolLabel = new Map(w.tools.filter((t) => t.key).map((t) => [t.key as string, t.name]));
	const params: Param[] = [
		{ param: 'main_database', default: '', description: 'The SQLite file on the cluster where your runs and cached results are kept.', type: 'path' },
		...w.configurable_params
	];
	const settings: Setting[] = params.map((p) => {
		const { label, group } = describeParam(p, toolLabel);
		const value = str(dig(cfg, p.param));
		const def = str(p.default);
		return {
			key: p.param,
			label,
			group,
			type: TYPES[p.type] ?? 'text',
			description: p.description,
			value,
			default: def,
			// The history database has no default to go back to: the API picks one per account.
			overridden: p.param !== 'main_database' && value !== '' && value !== def
		};
	});
	// Aliases have no group, so Settings lists each setting once.
	for (const [alias, real] of Object.entries(ALIASES)) {
		const s = settings.find((x) => x.key === real);
		settings.push({ key: alias, label: s?.label ?? alias, group: '', type: s?.type ?? 'text', description: '', value: s?.value ?? '', default: s?.default ?? '', overridden: false });
	}
	// Automatic: RASTtk where domain and code are known, Prodigal otherwise.
	settings.push({ key: 'GENE_CALLER', label: 'Gene caller', group: '', type: 'text', description: '', value: 'auto', default: 'auto', overridden: false });
	const gtdbtk = useGtdbtk(cfg) ? '1' : '0';
	settings.push({ key: 'RUN_GTDBTK', label: 'Classify with GTDB-Tk', group: '', type: 'flag', description: '', value: gtdbtk, default: '0', overridden: gtdbtk === '1' });
	return { settings };
}

/** Writes changed settings into config.yaml, converting by parameter type. */
async function saveSettings(body: { values?: Record<string, string> }) {
	const values = body.values ?? {};
	const w = await workflow();
	const types = new Map(w.configurable_params.map((p) => [p.param, p.type]));
	const cfg = structuredClone(await get<Config>('/v1/ssh/config'));
	for (const [key0, raw] of Object.entries(values)) {
		if (key0 === 'GENE_CALLER') continue;
		if (key0 === 'RUN_GTDBTK') {
			place(cfg, USE_GTDBTK, String(raw) === '1');
			continue;
		}
		const key = ALIASES[key0] ?? key0;
		const type = TYPES[types.get(key) ?? ''] ?? 'text';
		const text = String(raw).trim();
		const value = type === 'int' ? (text === '' ? null : Number.isFinite(Number(text)) ? Number(text) : text) : type === 'flag' ? text === '1' : text;
		place(cfg, key, value);
	}
	await call('PUT', '/v1/ssh/config', cfg);
	config.set(cfg);
	// Folders may have moved, so assets are checked again.
	installed.drop();
	return settingsList();
}

// ---- files ----

/** Returns the file browser's shortcut folders, deduplicated. */
async function places() {
	const [m, cfg] = await Promise.all([me.get(), config.get()]);
	const at = (k: string) => str(dig(cfg, `${WORKFLOW}.${k}`));
	const list = [
		{ label: 'Home', path: m.home_dir },
		// Your working folder (scratch) and where backups go (depot), as set under Folders.
		{ label: 'Scratch', path: at('stores_root') },
		{ label: 'Depot', path: at('backup_root') },
		{ label: 'Genomes in', path: at('input_path') },
		{ label: 'Results', path: at('output_path') },
		{ label: 'Databases', path: at('db_root') },
		{ label: 'Containers', path: at('sif_path') },
		{ label: 'The cluster', path: '/' }
	];
	const seen = new Set<string>();
	const out = [];
	for (const p of list) {
		const path = p.path ? await expand(p.path) : '';
		if (!path || seen.has(path)) continue;
		seen.add(path);
		out.push({ label: p.label, path });
	}
	return { places: out };
}

/** Lists a folder in the file browser's shape. */
async function listFolder(path: string) {
	const d = await browse(path);
	return {
		path: d.path,
		entries: d.entries.map((e) => ({
			name: e.name,
			type: e.type,
			size: e.size,
			mtime: e.mtime ? new Date(e.mtime * 1000).toISOString() : ''
		}))
	};
}

/**
 * Finds the job whose folder holds a path. Job files stream whole; elsewhere
 * the API returns only the first megabyte of a text file.
 */
async function jobFor(path: string): Promise<{ id: string; rel: string } | null> {
	const rows = await jobs.get().catch(() => [] as JobRow[]);
	for (const j of rows) {
		const dir = j.work_dir?.replace(/\/$/, '');
		if (dir && path.startsWith(dir + '/')) return { id: j.job_id, rel: path.slice(dir.length + 1) };
	}
	return null;
}

/** Returns a file as a Blob: a job's file in full, otherwise the head of a text file. */
export async function fileBlob(path: string): Promise<Blob> {
	const abs = await expand(path);
	const job = await jobFor(abs);
	if (job) return (await fetchRaw(`/v1/ssh/download_file/${q(job.id)}?path=${q(job.rel)}`)).blob();
	const d = await get<{ content: string; binary: boolean; truncated: boolean }>(`/v1/ssh/browse_view?path=${q(abs)}`);
	if (d.binary) throw new ApiError('Outside a job’s folder only text files can be opened from the cluster.', 415);
	return new Blob([d.content], { type: 'text/plain' });
}

/** Returns a text file's content from the cluster. */
async function readText(path: string) {
	const abs = await expand(path);
	const d = await get<{ content: string; binary: boolean; truncated: boolean }>(`/v1/ssh/browse_view?path=${q(abs)}`);
	return { path: abs, content: d.content, binary: d.binary, truncated: d.truncated, size: d.content.length };
}

/** Keeps the last four files read as text, so a FINAL table crosses the network once. */
const texts = new Map<string, Promise<string>>();
function fileText(path: string): Promise<string> {
	let text = texts.get(path);
	if (!text) {
		text = fileBlob(path).then((b) => b.text());
		text.catch(() => texts.delete(path));
		texts.set(path, text);
		while (texts.size > 4) texts.delete(texts.keys().next().value as string);
	}
	return text;
}

/** Parsed tables, the last four kept. */
const tables = new Map<string, Table>();

/** Loads a table (TSV/CSV/GFF or xlsx) and returns the requested page of it. */
async function tablePage(params: URLSearchParams) {
	const path = await expand(params.get('path') ?? '');
	const kind = TABLE_EXT[extOf(path)];
	if (!kind) throw new ApiError('Not a table file.', 400);
	let table = tables.get(path);
	if (!table && kind === 'xlsx') {
		// ExcelJS is large, so it is loaded only when a workbook opens.
		const ExcelJS = (await import('exceljs')).default;
		const wb = new ExcelJS.Workbook();
		await wb.xlsx.load(await (await fileBlob(path)).arrayBuffer());
		const palette: CellStyle[] = [];
		table = { kind, sheets: sheetsOf(wb, palette), palette };
	} else if (!table) {
		table = { kind, sheets: [parseDelimited(await fileText(path), kind as 'tsv' | 'csv' | 'gff', baseName(path))], palette: [] };
	}
	if (!tables.has(path)) {
		tables.set(path, table);
		while (tables.size > 4) tables.delete(tables.keys().next().value as string);
	}
	return queryLoaded(table, queryFromParams(params), { path, name: baseName(path) });
}

// ---- results ----

/**
 * Run output layout: <run>/<genome>/ beside run-level folders. The FINAL table
 * sits in scoring/, or at the genome's top once outputs are reorganised.
 */
const TABLE_NAME = 'FINAL_ANNOTATION_WITH_CONFIDENCE.tsv';
const EXCEL_NAME = 'FINAL_ANNOTATION_WITH_CONFIDENCE.xlsx';
const VIEWER_NAME = 'FINAL_GENOME_VIEWER.html';
const PER_TOOL = 'per-tool-phased-output';
/** Run-level folders (reorganize_outputs.py's list, and synteny). */
const RUN_LEVEL = new Set(['scoring', 'sqlite', 'ani', 'aai', 'closest', 'mauve', 'original_container_outputs', 'logs', 'genome_pool', 'synteny']);
/** Folders in a genome's results that are steps, not tools. */
const NOT_TOOLS = new Set(['consolidation', 'labeling', 'scoring', 'fingerprint', 'evidence', 'figures', 'diagrams', PER_TOOL]);
/** How many of the latest runs Results looks through. */
const RUNS_LOOKED_AT = 12;

/** Runs `work` over `items`, a few at a time: each is a trip to the cluster. */
async function few<T, R>(items: T[], work: (item: T) => Promise<R>, at = 6): Promise<R[]> {
	const out: R[] = new Array(items.length);
	let next = 0;
	await Promise.all(
		Array.from({ length: Math.min(at, items.length) }, async () => {
			while (next < items.length) {
				const i = next++;
				out[i] = await work(items[i]);
			}
		})
	);
	return out;
}

/** Names of entries of one type. */
const names = (entries: Entry[], type: Entry['type']) => new Set(entries.filter((e) => e.type === type).map((e) => e.name));

/** Reads a genome folder's finished results (table, Excel, viewer, diagrams), if any. */
async function readGenome(dir: string): Promise<OrganismResult & { jobDir: string }> {
	const organism = baseName(dir);
	const entries = (await browse(dir).catch(() => ({ entries: [] as Entry[] }))).entries;
	const files = names(entries, 'file');
	const dirs = names(entries, 'directory');
	const final: NonNullable<OrganismResult['final']> = { dir };
	if (files.has(VIEWER_NAME)) final.viewer = `${dir}/${VIEWER_NAME}`;
	if (files.has(TABLE_NAME)) {
		final.table = `${dir}/${TABLE_NAME}`;
		if (files.has(EXCEL_NAME)) final.excel = `${dir}/${EXCEL_NAME}`;
		if (dirs.has('diagrams')) final.diagrams = `${dir}/diagrams`;
	} else if (dirs.has('scoring')) {
		const scoring = await browse(`${dir}/scoring`).catch(() => ({ entries: [] as Entry[] }));
		const inside = names(scoring.entries, 'file');
		if (inside.has(TABLE_NAME)) final.table = `${dir}/scoring/${TABLE_NAME}`;
		if (inside.has(EXCEL_NAME)) final.excel = `${dir}/scoring/${EXCEL_NAME}`;
		if (names(scoring.entries, 'directory').has('figures')) final.diagrams = `${dir}/scoring/figures`;
	}
	return { organism, tools: [], folder: dir, final: final.table ? final : undefined, jobDir: dir.slice(0, dir.lastIndexOf('/')) };
}

/** Genome result folders across the latest runs, cached for 20 s. */
const resultList = new Cache(async () => {
	const rows = (await jobs.get()).filter((j) => j.work_dir).slice(0, RUNS_LOOKED_AT);
	// Newest run first, so a genome annotated twice shows its latest result.
	const perRun = await few(rows, async (j) => {
		const dir = (j.work_dir as string).replace(/\/$/, '');
		const d = await browse(dir).catch(() => null);
		return (d?.entries ?? [])
			.filter((e) => e.type === 'directory' && !e.name.startsWith('.') && !RUN_LEVEL.has(e.name))
			.map((e) => `${dir}/${e.name}`);
	});
	const seen = new Set<string>();
	const dirs: string[] = [];
	for (const run of perRun) {
		for (const dir of run) {
			if (seen.has(baseName(dir))) continue;
			seen.add(baseName(dir));
			dirs.push(dir);
		}
	}
	const organisms = await few(dirs, readGenome);
	return organisms.sort((a, b) => a.organism.localeCompare(b.organism));
}, 20_000);

/** Returns the Results page listing. */
async function results() {
	const [m, cfg] = await Promise.all([me.get(), config.get()]);
	const output = await expand(str(dig(cfg, `${WORKFLOW}.output_path`)) || m.home_dir);
	const organisms = await resultList.get().catch(() => [] as OrganismResult[]);
	return { outputRoot: output, genomesDir: '', organisms: organisms.map(({ organism, tools, folder, final }) => ({ organism, tools, folder, final })) };
}

/** Returns the API URL and token, for chat keys kept in the HPC home (lib/server/genome-chat). */
export function chatLink(): { api: string; token: string } | null {
	const token = getToken();
	return token ? { api: getApiUrl(), token } : null;
}

/**
 * Returns what genome chat needs to read a genome's results on the cluster:
 * API, token, folder, report table and owning jobs.
 */
export async function chatRemote(genome: string): Promise<ChatRemote | null> {
	const token = getToken();
	if (!token) return null;
	const organisms = await resultList.get().catch(() => [] as (OrganismResult & { jobDir: string })[]);
	const r = organisms.find((o) => o.organism === genome);
	if (!r?.folder) return null;
	const rows = await jobs.get().catch(() => [] as JobRow[]);
	const owning = rows
		.filter((j) => j.work_dir && r.folder!.startsWith((j.work_dir as string).replace(/\/$/, '') + '/'))
		.map((j) => ({ id: j.job_id, dir: (j.work_dir as string).replace(/\/$/, '') }));
	return { api: getApiUrl(), token, roots: [r.folder], table: r.final?.table ?? null, jobs: owning };
}

/**
 * Returns a FINAL table's report numbers, counted on the cluster via
 * /v1/ssh/final_summary; older APIs fall back to downloading and counting here.
 */
async function finalCounts(table: string): Promise<FinalCounts> {
	try {
		return await get<FinalCounts>(`/v1/ssh/final_summary?path=${q(table)}`);
	} catch (e) {
		if (!(e instanceof ApiError) || (e.status !== 404 && e.status !== 405)) throw e;
		// A 404 naming the table is a real miss; a bare 404 means an older API.
		if (e.status === 404 && /not found on cluster/i.test(e.message)) throw e;
	}
	const tally = new FinalTally();
	for (const line of (await fileText(table)).split(/\r?\n/)) tally.add(line);
	return tally.result();
}

/** Builds a genome's report summary: counts, figures and tools run. */
async function summary(genome: string): Promise<GenomeSummary> {
	const r = (await resultList.get()).find((x) => x.organism === genome);
	if (!r?.final?.table) throw new ApiError(`No finished results for ${genome} on the cluster.`, 404);
	const final = r.final;
	const [counts, figures, tools] = await Promise.all([
		finalCounts(final.table as string),
		final.diagrams
			? browse(final.diagrams)
					.then((d) => d.entries.filter((e) => e.type === 'file' && /\.png$/i.test(e.name)).map((e) => `${final.diagrams}/${e.name}`).sort())
					.catch(() => [] as string[])
			: Promise.resolve([] as string[]),
		browse(`${r.folder}/${PER_TOOL}`)
			.catch(() => browse(r.folder as string))
			.then((d) => [...names(d.entries, 'directory')].filter((n) => !NOT_TOOLS.has(n) && !n.startsWith('.')).sort())
			.catch(() => [] as string[])
	]);
	return {
		...counts,
		genome,
		final: final as GenomeSummary['final'],
		// The cluster works these out itself (GTDB-Tk, then RASTtk); the table does not repeat them.
		domain: '',
		geneticCode: '',
		geneCaller: 'rasttk',
		tools,
		figures
	};
}

// ---- router ----

/**
 * Answers `path` (with its query) as routes/api/local would. `init` carries
 * the method and a JSON body, as lib/api sends them.
 */
export async function clusterApi<T = any>(path: string, init: RequestInit = {}): Promise<T> {
	const url = new URL(path, 'http://x');
	const route = url.pathname.replace(/\/$/, '');
	const params = url.searchParams;
	const method = (init.method ?? 'GET').toUpperCase();
	const body = typeof init.body === 'string' ? JSON.parse(init.body || '{}') : init.body ? {} : undefined;
	const form = init.body instanceof FormData ? init.body : null;
	const answer = (async (): Promise<unknown> => {
		const run = route.match(/^\/runs\/([^/]+)(?:\/(stop|resume|restart))?$/);
		if (run) {
			const id = decodeURIComponent(run[1]);
			if (run[2] === 'stop') return stopRun(id);
			if (run[2] === 'resume' || run[2] === 'restart') return relaunchRun(id, run[2]);
			return runDetail(id, params);
		}
		const report = route.match(/^\/results\/([^/]+)$/);
		if (report && method === 'GET') return summary(decodeURIComponent(report[1]));
		switch (`${method} ${route}`) {
			case 'GET /runs':
				return listRuns();
			case 'POST /runs':
				return startRun(body ?? {});
			case 'DELETE /runs':
				return notHere('The cluster keeps its own job history; it is not cleared from here.');
			case 'GET /genomes':
				return listGenomes();
			// Your databases on scratch, their backups on depot, and the copy under way.
			case 'GET /stores':
				return storesAnswer(get('/v1/ssh/stores'));
			case 'GET /stores/progress':
				return get('/v1/ssh/stores/progress');
			case 'POST /results/refresh-map':
				// Regenerates the genome map with the backend's current viewer.
				return call('POST', '/v1/ssh/genome-viewer/refresh', { folder: String((body as { folder?: string })?.folder ?? '') });
			case 'POST /stores/run-here':
				return call('POST', '/v1/ssh/stores/run-here');
			case 'POST /stores/setup':
				return storesAnswer(call('POST', '/v1/ssh/stores/setup'));
			case 'GET /stores/check':
				return get(`/v1/ssh/stores/${q(params.get('id') ?? '')}/backup-check`);
			case 'POST /stores/backup':
				return storesAnswer(call('POST', `/v1/ssh/stores/${q(String((body as { id?: string })?.id ?? ''))}/backup`));
			case 'PUT /genomes':
				return saveGenomeInfo(body ?? {});
			case 'POST /genomes':
				if (form) return addGenomes(form);
				return notHere('Genomes in folders inside the input folder are gathered on the cluster itself, not from here.');
			case 'DELETE /genomes':
				return notHere('Genomes on the cluster are removed in their folder there, not from here.');
			case 'GET /tools':
				return listTools();
			case 'GET /overview':
				return overview();
			case 'GET /check':
				return { rows: await installed.get() };
			case 'GET /settings':
				return settingsList();
			case 'PUT /settings':
				return saveSettings(body ?? {});
			case 'GET /results':
				return results();
			case 'GET /files':
				return params.get('places') ? places() : listFolder(params.get('path') ?? '~');
			case 'GET /files/text':
				return readText(params.get('path') ?? '');
			case 'GET /files/table':
				return tablePage(params);
			case 'GET /preview':
				return { output: 'The cluster runs MARGIE (SB) through SLURM; the job page shows each step as it is submitted.' };
			case 'POST /licences':
				return notHere('On the cluster the licence terms are accepted on the Install page.');
			case 'POST /runtime/start':
				return notHere('The cluster’s container runtime is not started from here.');
		}
		throw new ApiError(`Not available on the cluster: ${route}`, 404);
	})();
	return answer as Promise<T>;
}
