/**
 * Workspace data store: genomes, tools, setup status, runs and results,
 * loaded from the GUI's API and polled while a run is going.
 */

import { untrack } from 'svelte';
import { api, del, formatBytes, post, put, type Run } from '$lib/api';
import { backend } from './backend.svelte';
import { installLock } from './install-lock.svelte';
import { ui } from './ui.svelte';
import { annotateProgress } from './progress';
import { selectByPattern } from './genome-select';

/** When a run started each tool on each genome, and each tool's usual seconds (the server's lib/server/toolClock). */
export interface ToolClock {
	typical: Record<string, number>;
	started: { tool: string; genome: string; start: number; last: number; ok: boolean; failed: boolean }[];
	now: number;
}

export interface Genome {
	name: string;
	size: number;
	domain: string;
	genetic_code: string;
}

export interface Tool {
	name: string;
	gated: boolean;
	licensed: boolean;
	gramDependent: boolean;
}

export interface CheckRow {
	status: 'ok' | 'missing' | 'warn' | 'optional' | 'unknown';
	name: string;
	kind: string;
	detail: string;
	section: string;
	/** From "Action required": the command that fixes an earlier row, not stock of its own. */
	advice: boolean;
}

export interface RuntimeInfo {
	id: 'docker' | 'podman' | 'container' | 'apptainer';
	label: string;
	installed: boolean;
	running: boolean;
	storesImages: 'runtime' | 'sif-folder';
	hint: string;
	install: string;
}

export interface Overview {
	user: string;
	runtime: { setting: string; active: string; label: string; ready: boolean };
	runtimes: RuntimeInfo[];
	recommended: string | null;
	repo: { ok: boolean; path: string; reason: string; containers: { name: string; gated: boolean }[]; databases: { name: string; gated: boolean }[] };
	python: { ready: boolean; version: string; path: string; base: { path: string; version: string } | null };
	licences: { tools: string[]; accepted: string[]; intendedUse: string };
	gtdbtk: boolean;
	machine: { os: string; arch: string; chip: string; cores: number; memory: number; diskFree: number | null; dbRoot: string };
	/** A backend that knows its own setup better (a cluster's) says so row by row, in place of the local reading below. */
	rows?: SetupRow[];
}

export interface OrganismResult {
	organism: string;
	tools: { tool: string; path: string; processed: boolean }[];
	/** The genome's own results folder, once it exists. */
	folder?: string;
	final?: { dir: string; viewer?: string; table?: string; excel?: string; diagrams?: string };
}

/** A genome file in a folder inside the genomes folder, where runs do not look. */
export interface NestedGenome {
	rel: string;
	folder: string;
	name: string;
	size: number;
	clashes: boolean;
}

export interface GenomeSummary {
	genome: string;
	final: { dir: string; viewer?: string; table?: string; excel?: string; diagrams?: string };
	domain: string;
	geneticCode: string;
	geneCaller: string;
	genes: number;
	operons: number;
	inOperons: number;
	withSupport: number;
	envelope: string;
	tiers: Record<string, number>;
	tools: string[];
	figures: string[];
	columns: string[];
	/** The genome's genes around a ring, by confidence tier (see GLYPH_TIERS on the server). */
	glyph: { length: number; contigs: number; plus: number[]; minus: number[] } | null;
}

export type Tone = 'ok' | 'warn' | 'danger' | 'neutral';

/** One line of the Setup panel and page. */
export interface SetupRow {
	/** runtime, repo, images, databases, python, licences, gtdbtk here; a cluster names its own. */
	id: string;
	label: string;
	value: string;
	detail: string;
	tone: Tone;
	/** Needed before a run can start (licences and GTDB-Tk are choices). */
	required: boolean;
	/** Where it is put right, inside the interface ("/settings#KEY"), when that is not Install. */
	href?: string;
}

export interface Setting {
	key: string;
	label: string;
	group: string;
	type: 'path' | 'text' | 'int' | 'choice' | 'flag';
	description: string;
	choices?: string[];
	value: string;
	default: string;
	overridden: boolean;
}

/** One of your databases: its working copy (scratch) and newest backup (depot). */
export interface StoreInfo {
	id: string;
	label: string;
	note: string;
	/** The working version, or null when it is not set up yet. */
	version: number | null;
	path: string;
	/** The copy every user starts from. */
	base: string;
	backup: { version: number; path: string } | null;
	backups: number;
}

/** A copy under way, or the last one: setting up, or backing up. */
export interface StoreOp {
	state: 'queued' | 'running' | 'done' | 'failed';
	op?: string;
	label?: string;
	percent: number;
	log: string[];
	message?: string;
	job?: string;
	slurm_out?: string[];
	/** On an HPC, the job's state in the queue, and why it waits (squeue's %r). */
	slurm_state?: string;
	slurm_reason?: string;
}

export interface StoresStatus {
	root: string;
	user: string;
	ready: boolean;
	stores: StoreInfo[];
	op: StoreOp | null;
}

/** What backing a database up would take, asked before Yes / No. */
export interface BackupCheck {
	id: string;
	label: string;
	version: number;
	size: number;
	/** Bytes left where the backup goes, or null when that cannot be told. */
	free: number | null;
	fits: boolean;
	target: string;
}

const STORES_NOT_READY = 'stores-not-ready';

export const STANDARD_TOOLS = ['kegg', 'cog', 'pfam', 'tigrfam', 'dbcan', 'eggnog', 'uniprot', 'geneprop', 'interpro', 'deepsig'];
/** What the envelope stage reads, run whenever a gram-dependent tool is chosen. */
export const ENVELOPE_INPUTS = ['tigrfam', 'pgap', 'pfam', 'uniprot'];

export type Depth = 'quick' | 'standard' | 'licensed' | 'custom';

const message = (e: unknown) => (e instanceof Error ? e.message : String(e));

class Workspace {
	genomes = $state<Genome[]>([]);
	genomeFolder = $state('');
	runGtdbtk = $state(false);
	/** Genome files found in folders inside the genomes folder. */
	nested = $state<NestedGenome[]>([]);
	geneticCodes = $state<string[]>([]);
	tools = $state<Tool[]>([]);
	overview = $state<Overview | null>(null);
	check = $state<CheckRow[] | null>(null);
	checking = $state(false);
	runs = $state<Run[]>([]);
	results = $state<OrganismResult[]>([]);
	/** The results folder (per-tool output) and the per-genome results folder inside it. */
	resultRoots = $state({ outputRoot: '', genomesDir: '' });
	settings = $state<Setting[]>([]);
	loaded = $state(false);
	savingGenomes = $state(false);

	/** How much the next run annotates; kept with the preferences (ui.prefs.toolDepth). */
	get depth(): Depth {
		return ui.prefs.toolDepth;
	}
	set depth(v: Depth) {
		ui.update({ toolDepth: v });
	}
	/** The tools picked by hand for Custom; kept with the preferences too. */
	get custom(): string[] {
		return ui.prefs.toolPick ?? [...STANDARD_TOOLS];
	}
	set custom(v: string[]) {
		ui.update({ toolPick: [...v] });
	}

	summaries = $state<Record<string, GenomeSummary>>({});

	/** Log of the run being watched (the active one, or the one on a run page). */
	log = $state('');
	/** While an annotation goes (on this computer): when it started each tool on each genome, and each tool's usual time. */
	clock = $state<ToolClock | null>(null);
	/** Which run `log` and `clock` are of. */
	logOf = $state('');
	#logRun = '';
	#logOffset = 0;
	#poll: ReturnType<typeof setInterval> | null = null;
	#saveTimer: ReturnType<typeof setTimeout> | null = null;
	#lastActive = '';

	/** Up to two runs go at once (server: MAX_RUNS); annotating runs alone. */
	running = $derived(this.runs.filter((r) => r.status === 'running'));
	/** The one a page follows: the annotate run if there is one, else the first. */
	active = $derived(this.running.find((r) => r.kind === 'annotate') ?? this.running[0] ?? null);
	/** Whether another run may start now. */
	canStart = $derived(this.running.length < 2 && !this.running.some((r) => r.kind === 'annotate'));
	progress = $derived(this.active?.kind === 'annotate' ? annotateProgress(this.log) : null);
	// "Action required" rows repeat missing items as commands, so they are not counted.
	images = $derived((this.check ?? []).filter((r) => r.kind === 'image' && !r.advice));
	databases = $derived((this.check ?? []).filter((r) => r.kind === 'database' && !r.advice));
	missingImages = $derived(this.images.filter((r) => r.status === 'missing').map((r) => r.name));
	missingDatabases = $derived(this.databases.filter((r) => r.status === 'missing').map((r) => r.name));
	finished = $derived(this.results.filter((r) => r.final?.table));
	/** The last line the watched run printed, for a one-line status. */
	lastLine = $derived(
		this.log
			.slice(-4000)
			.split('\n')
			.map((l) => l.trim())
			.filter(Boolean)
			.at(-1)
			?.slice(0, 120) ?? ''
	);

	/** Setup at a glance: what is ready and what is not. */
	setup = $derived.by((): SetupRow[] => {
		const o = this.overview;
		if (!o) return [];
		if (o.rows) return o.rows;
		const installed = o.runtimes.filter((r) => r.installed);
		const count = (rows: CheckRow[]) => {
			const needed = rows.filter((r) => r.status !== 'optional');
			return { ok: needed.filter((r) => r.status === 'ok').length, total: needed.length };
		};
		const im = count(this.images);
		const db = count(this.databases);
		const checked = this.check !== null;
		const free = o.machine.diskFree;
		return [
			{
				id: 'runtime',
				label: 'Container app',
				value: o.runtime.active ? o.runtime.label : installed.length ? 'Not chosen' : 'None installed',
				detail: o.runtime.ready ? 'Running' : o.runtime.active ? 'Not running' : 'Docker, Podman, Apptainer or Apple container',
				tone: o.runtime.ready ? 'ok' : installed.length ? 'warn' : 'danger',
				required: true
			},
			{
				id: 'repo',
				label: 'Build folder',
				value: o.repo.ok ? o.repo.path.split('/').filter(Boolean).at(-1) ?? '' : 'Not found',
				detail: o.repo.ok ? `${o.repo.containers.length} tools, ${o.repo.databases.length} databases` : o.repo.reason,
				tone: o.repo.ok ? 'ok' : 'warn',
				required: true
			},
			{
				id: 'images',
				label: 'Tools',
				value: checked ? `${im.ok} / ${im.total}` : '…',
				detail: checked ? (im.ok === im.total ? 'All built' : `${im.total - im.ok} to build`) : 'Checking',
				tone: !checked ? 'neutral' : im.ok === im.total ? 'ok' : 'warn',
				required: true
			},
			{
				id: 'databases',
				label: 'Reference data',
				value: checked ? `${db.ok} / ${db.total}` : '…',
				detail: checked
					? db.ok === db.total
						? 'All downloaded'
						: `About 170 GB${free !== null ? ` | ${formatBytes(free)} free` : ''}`
					: 'Checking',
				tone: !checked ? 'neutral' : db.ok === db.total ? 'ok' : 'warn',
				required: true
			},
			{
				id: 'python',
				label: 'Python',
				value: o.python.ready ? o.python.version : o.python.base ? o.python.base.version : 'Missing',
				detail: o.python.ready
					? 'Combines, scores and draws the results'
					: o.python.base
						? 'Its packages install on the first run'
						: 'Needs Python 3.11 or newer',
				tone: o.python.ready || o.python.base ? 'ok' : 'warn',
				required: true
			},
			{
				id: 'licences',
				label: 'Licences',
				value: `${o.licences.accepted.length} / ${o.licences.tools.length}`,
				detail: 'Optional tools with extra terms',
				tone: 'neutral',
				required: false
			},
			{
				id: 'gtdbtk',
				label: 'GTDB-Tk',
				value: o.gtdbtk ? 'On' : 'Off',
				detail: o.gtdbtk ? 'Classifies genomes without a domain and code' : 'Needs a high-memory machine',
				tone: 'neutral',
				required: false
			}
		];
	});
	setupReady = $derived({
		ok: this.setup.filter((r) => r.required && r.tone === 'ok').length,
		total: this.setup.filter((r) => r.required).length
	});

	/** Tools the chosen depth runs (before annotate.sh adds operon and the envelope inputs). */
	chosenTools = $derived.by(() => {
		const usable = new Set(this.tools.filter((t) => t.licensed).map((t) => t.name));
		if (this.depth === 'quick') return ['operon'];
		if (this.depth === 'standard') return STANDARD_TOOLS.filter((t) => usable.has(t));
		if (this.depth === 'licensed') return [...usable];
		return this.custom.filter((t) => usable.has(t));
	});

	/** Images and databases the chosen depth needs that are not there yet. */
	needs = $derived.by(() => {
		// With nothing chosen only the gene caller runs, so not even operon is needed.
		const chosen = new Set(this.chosenTools.length ? [...this.chosenTools, 'operon'] : []);
		const gram = this.tools.filter((t) => t.gramDependent).some((t) => chosen.has(t.name));
		if (gram) for (const t of [...ENVELOPE_INPUTS, 'envelope']) chosen.add(t);
		// Prodigal for all when chosen; otherwise RASTtk where domain and code are
		// known (or GTDB-Tk will find them) and Prodigal for the rest.
		const caller = this.setting('GENE_CALLER') || 'prodigal';
		const genomes = this.selectedGenomes.length ? this.genomes.filter((g) => this.isGenomeChosen(g.name)) : this.genomes;
		const known = genomes.filter((g) => g.domain && g.genetic_code).length;
		if (caller === 'prodigal' || (!this.runGtdbtk && known < genomes.length) || !genomes.length) chosen.add('prodigal');
		if (caller !== 'prodigal' && (known || this.runGtdbtk)) chosen.add('rasttk');
		if (this.runGtdbtk) chosen.add('gtdbtk');
		const images = this.missingImages.filter((n) => chosen.has(n));
		const databases = this.missingDatabases.filter((n) => chosen.has(n));
		return { images, databases, known: this.check !== null };
	});

	async loadAll() {
		await Promise.allSettled([this.loadGenomes(), this.loadTools(), this.loadOverview(), this.loadRuns(), this.loadResults(), this.loadSettings()]);
		this.loaded = true;
		this.loadCheck();
	}

	async loadGenomes() {
		const d = await api<{ folder: string; genomes: Genome[]; nested: NestedGenome[]; runGtdbtk: boolean; geneticCodes: string[] }>('/genomes');
		this.genomes = d.genomes;
		this.nested = d.nested ?? [];
		this.genomeFolder = d.folder;
		this.runGtdbtk = d.runGtdbtk;
		this.geneticCodes = d.geneticCodes;
	}

	/**
	 * Brings genomes out of folders inside the genomes folder and into it,
	 * where a run reads them. Never overwrites a file already there.
	 */
	async gatherGenomes(mode: 'copy' | 'move', removeEmpty = false): Promise<{ moved: string[]; skipped: string[]; removed: string[] } | null> {
		this.savingGenomes = true;
		try {
			const d = await api<{ moved: string[]; skipped: string[]; removed: string[]; genomes: Genome[]; nested: NestedGenome[] }>('/genomes', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ gather: mode, removeEmpty })
			});
			this.genomes = d.genomes;
			this.nested = d.nested ?? [];
			return { moved: d.moved, skipped: d.skipped, removed: d.removed };
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
			return null;
		} finally {
			this.savingGenomes = false;
		}
	}

	async loadTools() {
		this.tools = (await api<{ annotation: Tool[] }>('/tools')).annotation;
	}

	async loadOverview() {
		this.overview = await api<Overview>('/overview');
	}

	async loadSettings() {
		this.settings = (await api<{ settings: Setting[] }>('/settings')).settings;
	}

	async loadCheck() {
		if (this.checking) return;
		this.checking = true;
		try {
			this.check = (await api<{ rows: CheckRow[] }>('/check')).rows;
		} catch (e) {
			ui.notify(`Could not check tools and databases: ${message(e)}`, 'error');
		} finally {
			this.checking = false;
		}
	}

	async loadRuns() {
		this.runs = (await api<{ runs: Run[] }>('/runs')).runs;
	}

	/** `fresh` drops the cached report numbers: a run has just rewritten the tables. */
	async loadResults(fresh = true) {
		const d = await api<{ outputRoot: string; genomesDir: string; organisms: OrganismResult[] }>('/results');
		this.results = d.organisms;
		this.resultRoots = { outputRoot: d.outputRoot, genomesDir: d.genomesDir };
		if (fresh) {
			this.summaries = {};
			this.#summaryRequests.clear();
		}
	}

	#summaryRequests = new Map<string, Promise<GenomeSummary | null>>();

	/**
	 * A genome's report numbers, fetched once per results reload. Asking again
	 * while a request is on its way shares it; a failure is remembered until
	 * the next reload, so it is not asked for again on every refresh.
	 */
	loadSummary(genome: string): Promise<GenomeSummary | null> {
		const known = untrack(() => this.summaries[genome]);
		if (known) return Promise.resolve(known);
		let request = this.#summaryRequests.get(genome);
		if (!request) {
			request = api<GenomeSummary>(`/results/${encodeURIComponent(genome)}`)
				.then((s) => {
					this.summaries[genome] = s;
					return s;
				})
				.catch(() => null);
			this.#summaryRequests.set(genome, request);
		}
		return request;
	}

	/** Reads the log of `id` incrementally (restarting when the run changes). */
	async readLog(id: string) {
		if (id !== this.#logRun) {
			this.#logRun = id;
			this.logOf = id;
			this.clock = null;
			this.#logOffset = 0;
			this.log = '';
		}
		for (let i = 0; i < 20; i++) {
			const d = await api<{ run: Run; log: { text: string; offset: number; size: number }; clock?: ToolClock | null }>(
				`/runs/${id}?offset=${this.#logOffset}`
			);
			if (d.log.text) this.log = (this.log + d.log.text).slice(-2_000_000);
			this.clock = d.clock ?? null;
			this.#logOffset = d.log.offset;
			if (d.log.offset >= d.log.size) return d.run;
		}
	}

	startPolling() {
		if (this.#poll) return;
		let ticks = 0;
		const tick = async () => {
			try {
				await this.loadRuns();
				const active = this.active;
				if (active) {
					await this.readLog(active.id);
					this.#lastActive = active.id;
					// Picks up new genomes and tool folders the run has written.
					if (active.kind === 'annotate' && ticks++ % 2 === 0) await this.loadResults(false);
				} else if (this.#lastActive) {
					// A run just ended, so its output is now on disk.
					const ended = this.runs.find((r) => r.id === this.#lastActive);
					this.#lastActive = '';
					if (ended) ui.notify(`${ended.label}: ${ended.status}`, ended.status === 'completed' ? 'ok' : 'error');
					await Promise.allSettled([this.loadResults(), this.loadOverview(), this.loadGenomes()]);
					this.loadCheck();
				}
			} catch {
				// The next tick tries again.
			}
		};
		tick();
		this.#poll = setInterval(tick, 3000);
	}

	stopPolling() {
		if (this.#poll) clearInterval(this.#poll);
		this.#poll = null;
	}

	// ------------------------------------------------------------ genomes

	/** Edits one genome's domain or genetic code; saved a moment later. */
	edit(name: string, field: 'domain' | 'genetic_code', value: string) {
		this.genomes = this.genomes.map((g) => (g.name === name ? { ...g, [field]: value } : g));
		this.queueSave();
	}

	/** Applies rows of "genome, domain, code" (from a paste or a table file). Returns how many matched. */
	applyRows(text: string): number {
		const stem = (n: string) => n.replace(/\.(fna|fa|fasta)$/i, '').toLowerCase();
		const normDomain = (v: string) => (/^b/i.test(v) ? 'Bacteria' : /^a/i.test(v) ? 'Archaea' : '');
		let matched = 0;
		const next = this.genomes.map((g) => ({ ...g }));
		for (const line of text.replace(/\r/g, '').split('\n')) {
			const cells = line.split(/\t|,/).map((c) => c.trim());
			if (!cells[0]) continue;
			const g = next.find((x) => x.name.toLowerCase() === cells[0].toLowerCase() || stem(x.name) === stem(cells[0]));
			if (!g) continue;
			if (cells[1] !== undefined) g.domain = normDomain(cells[1]);
			if (cells[2] !== undefined) g.genetic_code = this.geneticCodes.includes(cells[2]) ? cells[2] : '';
			matched++;
		}
		if (matched) {
			this.genomes = next;
			this.queueSave();
		}
		return matched;
	}

	fillEmpty(domain: string, code: string) {
		this.genomes = this.genomes.map((g) => ({ ...g, domain: g.domain || domain, genetic_code: g.genetic_code || code }));
		this.queueSave();
	}

	queueSave() {
		if (this.#saveTimer) clearTimeout(this.#saveTimer);
		this.#saveTimer = setTimeout(() => this.saveGenomes(), 600);
	}

	async saveGenomes() {
		this.savingGenomes = true;
		try {
			await put('/genomes', { rows: this.genomes.map((g) => ({ name: g.name, domain: g.domain, genetic_code: g.genetic_code })) });
		} catch (e) {
			ui.notify(message(e), 'error');
		} finally {
			this.savingGenomes = false;
		}
	}

	async upload(files: FileList | File[]) {
		if (!files.length) return;
		const form = new FormData();
		for (const f of Array.from(files)) form.append('files', f);
		try {
			const d = await api<{ added: string[]; skipped?: string[]; genomes: Genome[] }>('/genomes', { method: 'POST', body: form });
			this.genomes = d.genomes;
			ui.notify(`Added ${d.added.join(', ')}${d.skipped?.length ? `. Not added: ${d.skipped.join('; ')}` : ''}`, 'ok');
		} catch (e) {
			ui.notify(message(e), 'error');
		}
	}

	async remove(name: string) {
		try {
			this.genomes = (await api<{ genomes: Genome[] }>(`/genomes?name=${encodeURIComponent(name)}`, { method: 'DELETE' })).genomes;
		} catch (e) {
			ui.notify(message(e), 'error');
		}
	}

	// ------------------------------------------------------------ runs

	async start(body: Record<string, unknown>): Promise<Run | null> {
		try {
			const { run } = await post<{ run: Run }>('/runs', body);
			await this.loadRuns();
			return run;
		} catch (e) {
			// On a cluster's first run the databases are copied to scratch first; the run starts after.
			if (message(e).startsWith(STORES_NOT_READY)) {
				this.#runAfterSetup = body;
				ui.notify('Setting up your databases first (a one-time copy). The run starts when it finishes.', 'ok');
				if (!this.storesBusy) await this.setupStores();
				else this.#watchStores();
				return null;
			}
			ui.notify(message(e), 'error');
			return null;
		}
	}

	// ------------------------------------------------------------ your databases (cluster)

	/** Where your databases are, and the copy under way; null until read, or where there are none (this computer). */
	stores = $state<StoresStatus | null>(null);
	storesOp = $state<StoreOp | null>(null);
	#storesTimer: ReturnType<typeof setTimeout> | null = null;
	/** A run that asked for the databases first, started once they are copied. */
	#runAfterSetup: Record<string, unknown> | null = null;

	get storesBusy() {
		return this.storesOp?.state === 'queued' || this.storesOp?.state === 'running';
	}

	async loadStores() {
		try {
			this.stores = await api<StoresStatus>('/stores');
			this.storesOp = this.stores.op;
			if (this.storesBusy) this.#watchStores();
		} catch {
			this.stores = null;
		}
	}

	/** Copies whichever databases are missing on scratch (from your newest backup, else the base). */
	async setupStores() {
		// Copying the databases is installing too: it waits for the install statement.
		if (!(await installLock.confirm('Copy your databases to your working folder (a one-time copy)'))) {
			this.#runAfterSetup = null;
			return;
		}
		try {
			this.stores = await post<StoresStatus>('/stores/setup', {});
			this.storesOp = this.stores.op;
			this.#watchStores();
		} catch (e) {
			this.#runAfterSetup = null;
			ui.notify(message(e), 'error');
		}
	}

	checkBackup(id: string) {
		return api<BackupCheck>(`/stores/check?id=${encodeURIComponent(id)}`);
	}

	/** Copies one database to depot; its working copy moves on to the next version. */
	async backupStore(id: string) {
		try {
			this.stores = await post<StoresStatus>('/stores/backup', { id });
			this.storesOp = this.stores.op;
			this.#watchStores();
			return true;
		} catch (e) {
			ui.notify(message(e), 'error');
			return false;
		}
	}

	/** Follows the copy every two seconds until it is done, then read everything it changed. */
	#watchStores() {
		if (this.#storesTimer) return;
		const tick = async () => {
			this.#storesTimer = null;
			try {
				const { op } = await api<{ op: StoreOp | null }>('/stores/progress');
				this.storesOp = op;
			} catch {
				// A missed poll is retried, not treated as a failed copy.
			}
			if (this.storesBusy) {
				this.#storesTimer = setTimeout(tick, 2000);
				return;
			}
			await Promise.all([this.loadStores(), this.loadSettings()]);
			const op = this.storesOp;
			if (op?.state === 'failed') {
				this.#runAfterSetup = null;
				ui.notify(op.message || 'The copy did not finish.', 'error');
			} else if (op?.state === 'done') {
				const body = this.#runAfterSetup;
				this.#runAfterSetup = null;
				if (body) {
					const run = await this.start(body);
					if (run) ui.notify('Your databases are ready: the run has started.', 'ok');
				}
			}
		};
		this.#storesTimer = setTimeout(tick, 1000);
	}

	/**
	 * Which genomes the next run annotates; null means all of them and keeps
	 * following the folder, so genomes added later are included.
	 */
	chosenGenomes = $state<string[] | null>(null);

	/** The chosen genomes that are actually still in the folder, in its order. */
	get selectedGenomes(): string[] {
		const names = this.genomes.map((g) => g.name);
		if (this.chosenGenomes === null) return names;
		const keep = new Set(this.chosenGenomes);
		return names.filter((n) => keep.has(n));
	}

	get everyGenomeChosen(): boolean {
		return this.chosenGenomes === null || this.selectedGenomes.length === this.genomes.length;
	}

	isGenomeChosen(name: string): boolean {
		return this.chosenGenomes === null || this.chosenGenomes.includes(name);
	}

	/** Settles on null whenever the choice covers everything, so it keeps following the folder. */
	chooseGenomes(names: string[]): void {
		const all = this.genomes.map((g) => g.name);
		const wanted = new Set(names);
		const keep = all.filter((n) => wanted.has(n));
		this.chosenGenomes = keep.length === all.length ? null : keep;
	}

	setGenomeChosen(name: string, on: boolean): void {
		const now = new Set(this.selectedGenomes);
		if (on) now.add(name);
		else now.delete(name);
		this.chooseGenomes([...now]);
	}

	chooseAllGenomes(): void {
		this.chosenGenomes = null;
	}

	chooseNoGenomes(): void {
		this.chosenGenomes = [];
	}

	invertGenomes(): void {
		const on = new Set(this.selectedGenomes);
		this.chooseGenomes(this.genomes.map((g) => g.name).filter((n) => !on.has(n)));
	}

	/** Adds everything matching a pattern like "a-c, 1-9" to the choice. */
	addGenomesByPattern(pattern: string): number {
		const found = selectByPattern(
			this.genomes.map((g) => g.name),
			pattern
		);
		if (found.length) this.chooseGenomes([...new Set([...this.selectedGenomes, ...found])]);
		return found.length;
	}

	/** Replaces the choice with everything matching the pattern. */
	onlyGenomesByPattern(pattern: string): number {
		const found = selectByPattern(
			this.genomes.map((g) => g.name),
			pattern
		);
		this.chooseGenomes(found);
		return found.length;
	}

	async annotate() {
		if (this.#saveTimer) {
			clearTimeout(this.#saveTimer);
			await this.saveGenomes();
		}
		if (!this.selectedGenomes.length) {
			ui.notify('No genomes are selected, so there is nothing to annotate.', 'error');
			return null;
		}
		// An empty choice means gene calling only, but only once the tool list has loaded.
		if (!this.tools.length) {
			ui.notify('Still reading which tools are available. Try again in a moment.', 'error');
			return null;
		}
		if (!this.chosenTools.length) ui.notify('No tools are chosen: this run calls genes and stops there.', 'ok');
		// Omitted when every genome is chosen, so the server runs the folder without staging.
		return this.start({
			kind: 'annotate',
			tools: this.chosenTools,
			...(this.everyGenomeChosen ? {} : { genomes: this.selectedGenomes })
		});
	}

	/** Builds or downloads, once the install statement is typed (installLock.confirm). */
	async build(what: 'containers' | 'databases' | 'all', tools?: string[]) {
		const noun = what === 'containers' ? 'Build' : what === 'databases' ? 'Download' : 'Install';
		const password = await installLock.confirm(`${noun} ${tools?.length ? tools.join(', ') : what === 'all' ? 'what is missing' : `all missing ${what}`}`);
		if (!password) return null;
		return this.start({ kind: 'build', what, tools: tools?.length ? tools : undefined, password });
	}

	/**
	 * Empties the history. The server copies everything it removes into
	 * run-history/<when>/ first, and says where, so nothing is ever only
	 * deleted. A run still going stays in the list.
	 */
	async clearRuns() {
		try {
			const r = await del<{ backup: string; removed: number; kept: number }>('/runs');
			await this.loadRuns();
			ui.notify(
				r.removed
					? `Cleared ${r.removed} job${r.removed === 1 ? '' : 's'}. Backup: ${r.backup}`
					: 'Nothing to clear.',
				'ok'
			);
			return r;
		} catch (e) {
			ui.notify(message(e), 'error');
			return null;
		}
	}

	async stop(id: string) {
		try {
			await post(`/runs/${id}/stop`);
			await this.loadRuns();
		} catch (e) {
			ui.notify(message(e), 'error');
		}
	}

	/**
	 * Runs a failed or stopped annotation again: the same genomes and tools.
	 * On this computer that is a new run, and the caches hand back everything
	 * the first one finished, so it picks up where it stopped. A cluster
	 * resumes the job itself.
	 */
	async resume(run: Run): Promise<boolean> {
		if (backend.cluster) return this.#relaunch(run, 'resume');
		const present = new Set(this.genomes.map((g) => g.name));
		const genomes = (run.files ?? []).filter((n) => present.has(n));
		const tools = run.tools ?? [];
		const everything = !tools.length && !run.args.includes('--genes-only');
		const started = await this.start({
			kind: 'annotate',
			tools,
			...(everything ? { all: true } : {}),
			...(genomes.length && genomes.length < present.size ? { genomes } : {})
		});
		return !!started;
	}

	/** Starts a cluster job again from the beginning, with the same genomes and tools. */
	restart(run: Run): Promise<boolean> {
		return this.#relaunch(run, 'restart');
	}

	async #relaunch(run: Run, how: 'resume' | 'restart'): Promise<boolean> {
		try {
			await post(`/runs/${encodeURIComponent(run.id)}/${how}`);
			await this.loadRuns();
			return true;
		} catch (e) {
			ui.notify(message(e), 'error');
			return false;
		}
	}

	async startRuntime(id: string) {
		try {
			const r = await post<{ ok: boolean; message: string }>('/runtime/start', { id });
			ui.notify(r.message, r.ok ? 'ok' : 'error');
			await this.loadOverview();
		} catch (e) {
			ui.notify(message(e), 'error');
		}
	}

	// ------------------------------------------------------------ settings

	setting(key: string): string {
		return this.settings.find((s) => s.key === key)?.value ?? '';
	}

	/** Saves the licence choices; accepting a tool needs the typed licence statement. */
	async saveLicences(intendedUse: string, accepted: Record<string, boolean>, statement: string) {
		try {
			const d = await post<{ settings: Setting[]; added: string[] }>('/licences', { intendedUse, accepted, statement });
			this.settings = d.settings;
			await Promise.allSettled([this.loadOverview(), this.loadTools()]);
			return d.added;
		} catch (e) {
			ui.notify(message(e), 'error');
			return null;
		}
	}

	async saveSettings(values: Record<string, string>) {
		try {
			this.settings = (await put<{ settings: Setting[] }>('/settings', { values, merge: true })).settings;
			await Promise.allSettled([this.loadOverview(), this.loadTools(), this.loadGenomes()]);
			return true;
		} catch (e) {
			ui.notify(message(e), 'error');
			return false;
		}
	}
}

export const ws = new Workspace();
