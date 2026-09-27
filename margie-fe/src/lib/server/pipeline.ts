/**
 * Locates the margie-pipeline checkout and manages its settings. pipeline.conf.sh
 * uses `: "${VAR:=default}"`, so the GUI passes LOCAL_DEFAULTS and the saved
 * gui/settings.local.json as environment variables and never edits the file.
 */

import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { LICENCE_LEGAL_NOTICE, LICENCE_STATEMENT, statementMatches } from '$lib/licence';

function findPipelineRoot(): string {
	const candidates = [
		process.env.MARGIE_PIPELINE_ROOT,
		// A copy baked into a front-end repo, beside the app (margie-frontend).
		path.resolve(process.cwd(), '..', 'margie-pipeline'),
		path.resolve(process.cwd(), 'margie-pipeline'),
		path.resolve(process.cwd(), '..'), // `npm run dev` from margie-pipeline/gui
		process.cwd()
	].filter(Boolean) as string[];
	for (const dir of candidates) {
		if (fs.existsSync(path.join(dir, 'annotate.sh')) && fs.existsSync(path.join(dir, 'pipeline.conf.sh'))) {
			return path.resolve(dir);
		}
	}
	throw new Error(
		'Could not find margie-pipeline (annotate.sh + pipeline.conf.sh). Start the GUI from ' +
			'margie-pipeline/gui, or set MARGIE_PIPELINE_ROOT.'
	);
}

export const PIPELINE_ROOT = findPipelineRoot();
const SETTINGS_FILE = path.join(PIPELINE_ROOT, 'gui', 'settings.local.json');

// ---------------------------------------------------------------- settings

export type SettingType = 'path' | 'text' | 'int' | 'choice' | 'flag';

export interface SettingDef {
	key: string;
	label: string;
	group: 'Setup' | 'Folders' | 'Other folders' | 'Runtime' | 'Licences' | 'Tools' | 'Cluster' | 'Phases' | 'Per tool' | 'LLM';
	type: SettingType;
	description: string;
	choices?: string[];
	/** Used when pipeline.conf.sh itself has no default (annotate.sh supplies it). */
	fallback?: string;
}

export const LICENCE_TOOLS = ['merops', 'tcdb', 'tmbed', 'interpro', 'phobius', 'psortb'];

/**
 * Local-mode defaults over pipeline.conf.sh: GTDB-Tk off (too memory-hungry for
 * a laptop; the genome table gives domain and code), and licence-gated tools off
 * until the licence statement is typed.
 */
const LOCAL_DEFAULTS: Record<string, string> = {
	RUN_GTDBTK: '0',
	LICENCE_INTENDED_USE: '',
	LICENCE_STATEMENT: '',
	...Object.fromEntries(LICENCE_TOOLS.map((t) => [`LICENCE_AGREED_${t.toUpperCase()}`, '0']))
};

/** Returns a margie-build checkout next to this pipeline, if there is one. */
function siblingSetupRepo(): string {
	const sibling = path.resolve(PIPELINE_ROOT, '..', 'margie-build');
	return fs.existsSync(path.join(sibling, 'build.sh')) ? sibling : '';
}

/**
 * SLURM resources per phase (SLURM_<PHASE>_* in pipeline.conf.sh). `sized`
 * marks single-node phases with CPUs and memory to set; the others fan out
 * over whole nodes.
 */
const PHASES: { id: string; name: string; note: string; sized: boolean }[] = [
	{ id: 'CONTAINERS', name: 'Building images', note: 'Builds or pulls every container image.', sized: false },
	{ id: 'DATABASES', name: 'Downloading databases', note: 'Fetches the reference databases.', sized: false },
	{ id: 'SETUP', name: 'Full setup', note: 'Images and databases in one job.', sized: false },
	{ id: 'ANNOTATE', name: 'Annotation', note: 'The run itself: the chosen tools across your genomes.', sized: true },
	{ id: 'CLASSIFY', name: 'Classification', note: "GTDB-Tk's classify step, which wants a lot of memory.", sized: true },
	{ id: 'DOWNSTREAM', name: 'Re-run downstream', note: 'Tier-1 tools again, normally the same size as annotation.', sized: true },
	{ id: 'META', name: 'Consolidation', note: 'Labelling, fingerprinting and scoring.', sized: true }
];

const PHASE_SETTINGS: SettingDef[] = PHASES.flatMap(({ id, name, note, sized }): SettingDef[] => [
	{ key: `SLURM_${id}_NODES`, label: `${name}: nodes`, group: 'Phases', type: 'int', description: note },
	...(sized
		? ([
				{
					key: `SLURM_${id}_CPUS`,
					label: `${name}: CPUs`,
					group: 'Phases',
					type: 'int',
					description: `Cores asked of SLURM for this phase.`
				},
				{
					key: `SLURM_${id}_MEM`,
					label: `${name}: memory`,
					group: 'Phases',
					type: 'text',
					description: `Memory for this phase, written the way SLURM wants it: 128G, 64G.`
				}
			] as SettingDef[])
		: []),
	{
		key: `SLURM_${id}_TIME`,
		label: `${name}: time limit`,
		group: 'Phases',
		type: 'text',
		description: 'Wall-clock limit as HH:MM:SS. A job over it is killed, however far it got.'
	}
]);

/**
 * Per-tool thread counts for the three tools pipeline.conf.sh gives their own;
 * memory has no per-tool setting (it comes from the phase or the local budget).
 */
const PER_TOOL: SettingDef[] = (
	[
		['RASTTK', 'RASTtk', 'Runs sequentially, so four cores is usually plenty.'],
		['KEGG', 'KEGG', ''],
		['EGGNOG', 'eggNOG', '']
	] as [string, string, string][]
).map(([id, name, note]): SettingDef => ({
	key: `TOOL_${id}_THREADS`,
	label: `${name}: threads`,
	group: 'Per tool',
	type: 'int',
	description: note || `Cores ${name} asks for, instead of its share of the budget.`
}));

export const SETTINGS: SettingDef[] = [
	{
		key: 'SLURM_ACCOUNT',
		label: 'SLURM account',
		group: 'Cluster',
		type: 'text',
		description: 'The allocation every job is charged to.'
	},
	{
		key: 'SLURM_PARTITION',
		label: 'Partition',
		group: 'Cluster',
		type: 'text',
		description: 'The queue jobs are submitted to. GTDB-Tk normally needs a high-memory one.'
	},
	...PHASE_SETTINGS,
	...PER_TOOL,
	{ key: 'SETUP_REPO', label: 'Setup or build folder', group: 'Setup', type: 'path', fallback: siblingSetupRepo(), description: 'Your margie-build folder, which builds the container images and downloads the databases. Subject to additional licensing terms (see Install).' },
	// The six a run actually needs; everything else is derived from them and
	// lives under "Other folders".
	{ key: 'USER_INPUT_DIR', label: 'Genomes in', group: 'Folders', type: 'path', description: 'Where you keep your genomes: the .fna/.fa/.fasta assemblies to annotate.' },
	{ key: 'OUTPUT_ROOT', label: 'Results out', group: 'Folders', type: 'path', description: 'Where the results are written: each tool\'s output, and a folder per genome beneath it.' },
	{ key: 'SIF_DIR', label: 'Container images (sif)', group: 'Folders', type: 'path', description: 'Your .sif images, for Apptainer and Singularity only. Docker, Podman and Apple\'s container keep their images themselves.' },
	{ key: 'DB_ROOT', label: 'Databases (db)', group: 'Folders', type: 'path', description: 'Where the reference databases are kept, one folder per tool (~170 GB in all).' },
	{ key: 'OPERON_DB', label: 'Operon database', group: 'Folders', type: 'path', description: 'The operon co-occurrence reference the scoring step reads and grows with every genome.' },
	{ key: 'MARGIE_DB', label: 'Results cache (SQLite)', group: 'Folders', type: 'path', description: 'One file holding each tool\'s output under the hash of the genome it came from, so the same genome is never computed twice. Copy the file and its cache travels with it.' },
	{ key: 'PHOBIUS_TARBALL', label: 'Phobius download', group: 'Setup', type: 'path', description: "Phobius cannot be redistributed, so its image builds only from your own copy: the phobius101_linux.tgz you downloaded from phobius.sbc.su.se, or the folder you unpacked it into. Left empty, phobius is skipped." },
	// The built-in model (not set up yet): where it lives, and which one. Chat with the genome points here.
	{ key: 'LLM_ROOT', label: 'Model folder', group: 'LLM', type: 'path', description: 'Where the built-in language model is kept (./setup.sh --databases-only --tool llm downloads it here).' },
	{ key: 'LLM_BASE_MODEL', label: 'Base model', group: 'LLM', type: 'text', description: 'A Hugging Face id (e.g. meta-llama/Meta-Llama-3-8B) or a folder on this computer.' },
	{ key: 'LLM_TRAINED_MODEL', label: 'Fine-tuned model', group: 'LLM', type: 'text', description: 'Optional: a fine-tuned model, as a Hugging Face id or a folder.' },
	{ key: 'LLM_TRAINED_ADAPTERS', label: 'Adapters (LoRA)', group: 'LLM', type: 'text', description: 'Optional: LoRA or PEFT adapters for the model, as a Hugging Face id or a folder.' },
	{ key: 'INPUT_RASTTK', label: 'Prepared genomes', group: 'Other folders', type: 'path', description: 'Where each run copies the genomes, with genomes.tsv: each genome\'s domain, genetic code and gene caller.' },
	{ key: 'GENOME_RESULTS_DIR', label: 'Per-genome results', group: 'Other folders', type: 'path', description: "One folder per genome in margie-backend's layout: FINAL table, Excel copy, genome viewer, diagrams. Inside the results folder by default." },
	{ key: 'MARGIE_SHARED_DIR', label: 'Shared references', group: 'Other folders', type: 'path', description: 'Fingerprint databases and the operon reference, which grow with every genome annotated.' },
	{ key: 'GENOME_METADATA', label: 'Genome table', group: 'Other folders', type: 'path', description: 'Per-genome domain and genetic code, edited on the Analyze page.' },
	{ key: 'USE_RESULT_CACHE', label: 'Reuse finished results', group: 'Runtime', type: 'flag', description: 'On: a tool whose output for this exact genome is already in the results cache is restored instead of run again. Off: everything runs again.' },
	{ key: 'BVBRC_USERNAME', label: 'BV-BRC username', group: 'Runtime', type: 'text', description: 'Your BV-BRC account, used by RASTtk to sign in (the password is asked once and the session kept). Empty: RASTtk uses a session you already have.' },
	{ key: 'GENE_CALLER', label: 'Gene caller', group: 'Runtime', type: 'choice', choices: ['prodigal', 'rasttk', 'auto'], description: 'prodigal needs nothing but the assembly. rasttk also reports RNAs and repeats, but only for genomes whose domain and genetic code are known; the rest fall back to prodigal. auto picks between them per genome.' },
	{ key: 'RUN_GTDBTK', label: 'Classify with GTDB-Tk', group: 'Runtime', type: 'flag', description: 'Off: domain and genetic code come from the genome table. On: GTDB-Tk classifies every genome first (needs a high-memory machine).' },
	{ key: 'RUNTIME', label: 'Container runtime', group: 'Runtime', type: 'choice', choices: ['auto', 'container', 'docker', 'podman', 'apptainer'], description: "auto prefers Apptainer, then Docker, then Podman, then Apple's container." },
	{ key: 'PLATFORM', label: 'Docker platform', group: 'Runtime', type: 'text', description: 'Image platform for Docker, e.g. linux/amd64 (runs under emulation on Apple Silicon).' },
	{ key: 'LOCAL_MAX_CORES', label: 'Cores this pipeline may use', group: 'Runtime', type: 'int', description: 'The whole core budget on this computer. Three quarters of the machine by default; the rest stays free for you.' },
	{ key: 'LOCAL_MAX_MEMORY_GB', label: 'Memory this pipeline may use (GB)', group: 'Runtime', type: 'int', description: 'The whole memory budget on this computer, in gigabytes. Three quarters of the machine by default.' },
	{ key: 'LOCAL_PARALLEL_TOOLS', label: 'Tools at once', group: 'Runtime', type: 'int', description: 'How many tools run side by side on this computer. They share the budget above: two at once means each gets half the cores and half the memory. One at a time gives each tool everything.' },
	{ key: 'THREADS', label: 'Threads per tool', group: 'Runtime', type: 'int', description: "Threads a tool asks for. Left alone it follows the budget above: the cores divided by the tools running at once." },
	{ key: 'USE_GPU', label: 'Use GPU', group: 'Runtime', type: 'choice', choices: ['auto', '1', '0'], description: 'auto uses a GPU when nvidia-smi is available (tmbed, llm).' },
	{ key: 'PARALLEL_TOOLS', label: 'Parallel tools (HPC)', group: 'Runtime', type: 'int', fallback: '6', description: 'Tools run at once per organism under SLURM. On this computer, "Tools at once" above decides that instead.' },
	{ key: 'MIN_PHASE2_ORGS', label: 'Organisms before comparative phase', group: 'Runtime', type: 'int', fallback: '2', description: 'Scored organisms needed before AAI / ANI / closest / synteny run.' },
	{ key: 'LICENCE_INTENDED_USE', label: 'Intended use', group: 'Licences', type: 'text', description: 'Recorded verbatim with every licence acceptance and in run logs. Must be truthful.' },
	{ key: 'LICENCE_STATEMENT', label: 'Licence statement', group: 'Licences', type: 'text', description: 'The licence statement as typed when the gated tools were accepted. Set through the licence form only.' },
	...LICENCE_TOOLS.map(
		(t): SettingDef => ({
			key: `LICENCE_AGREED_${t.toUpperCase()}`,
			label: `${t} licence accepted`,
			group: 'Licences',
			type: 'flag',
			description: `Set to 1 only after reading ${t}'s licence terms. Tools left at 0 are skipped.`
		})
	),
	{ key: 'RUN_EVIDENCE', label: 'Evidence report', group: 'Tools', type: 'flag', description: 'Per-gene evidence report after scoring.' },
	{ key: 'RUN_GENOME_VIEWER', label: 'Genome viewer', group: 'Tools', type: 'flag', description: 'Interactive genome viewer and circular map for each genome.' },
	{ key: 'RUN_REPORT_FIGURES', label: 'Report figures', group: 'Tools', type: 'flag', description: 'Per-genome and pangenome report figures.' },
	{ key: 'RUN_FULL_OPERON_MAP', label: 'Full operon map', group: 'Tools', type: 'flag', description: 'Draw every operon of each genome (slow).' },
	{ key: 'TOOL_interpro_DB', label: 'InterProScan data folder', group: 'Tools', type: 'path', description: 'InterProScan data directory for the interpro tool.' },
	{ key: 'TOOL_RASTTK_THREADS', label: 'RASTtk threads', group: 'Tools', type: 'int', description: 'CPUs for RASTtk gene calling.' }
];

const SETTING_KEYS = new Set(SETTINGS.map((s) => s.key));

export function readOverrides(): Record<string, string> {
	try {
		const data = JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8'));
		return Object.fromEntries(
			Object.entries(data).filter(([k, v]) => SETTING_KEYS.has(k) && typeof v === 'string')
		) as Record<string, string>;
	} catch {
		return {};
	}
}

export function writeOverrides(values: Record<string, string>): void {
	// A fresh copy of the pipeline has no gui/ folder to write into.
	fs.mkdirSync(path.dirname(SETTINGS_FILE), { recursive: true });
	const clean = Object.fromEntries(
		Object.entries(values).filter(([k, v]) => SETTING_KEYS.has(k) && typeof v === 'string' && v !== '')
	);
	fs.writeFileSync(SETTINGS_FILE, JSON.stringify(clean, null, 2) + '\n');
}

/** Environment for every pipeline script: local defaults, then the user's own settings. */
export function pipelineEnv(): NodeJS.ProcessEnv {
	return { ...process.env, ...LOCAL_DEFAULTS, ...readOverrides() };
}

/** Sources pipeline.conf.sh in bash and returns the values the scripts would see. */
function sourceConfig(env: NodeJS.ProcessEnv, script: string): string {
	const res = spawnSync(
		'bash',
		['-c', `set +u; . ./pipeline.conf.sh >/dev/null 2>&1; ${script}`],
		{ cwd: PIPELINE_ROOT, env, encoding: 'utf8', timeout: 15000 }
	);
	if (res.status !== 0) throw new Error(`Reading pipeline.conf.sh failed: ${res.stderr || res.error}`);
	return res.stdout;
}

function readVars(env: NodeJS.ProcessEnv): Record<string, string> {
	const keys = SETTINGS.map((s) => s.key).join(' ');
	const out = sourceConfig(env, `for v in ${keys}; do printf '%s\\t%s\\n' "$v" "\${!v-}"; done`);
	const values: Record<string, string> = {};
	for (const line of out.split('\n')) {
		const tab = line.indexOf('\t');
		if (tab > 0) values[line.slice(0, tab)] = line.slice(tab + 1);
	}
	return values;
}

export interface SettingsView {
	settings: (SettingDef & { value: string; default: string; overridden: boolean })[];
	pipelineRoot: string;
}

export function getSettings(): SettingsView {
	const overrides = readOverrides();
	// Shell overrides of the same keys are dropped so "reset to default" shows the true default.
	const baseEnv: NodeJS.ProcessEnv = { ...process.env };
	for (const k of SETTING_KEYS) delete baseEnv[k];
	Object.assign(baseEnv, LOCAL_DEFAULTS);
	const defaults = readVars(baseEnv);
	const effective = readVars({ ...baseEnv, ...overrides });
	return {
		pipelineRoot: PIPELINE_ROOT,
		settings: SETTINGS.map((s) => ({
			...s,
			default: defaults[s.key] || s.fallback || '',
			value: effective[s.key] || s.fallback || '',
			overridden: s.key in overrides
		}))
	};
}

/** Returns the effective value of one setting, with the user's overrides. */
export function setting(key: string): string {
	return getSettings().settings.find((s) => s.key === key)?.value ?? '';
}

// ---------------------------------------------------------------- tools

export interface ToolInfo {
	name: string;
	gated: boolean;
	licensed: boolean;
	gramDependent: boolean;
}

/** Evaluates one array assignment from annotate.sh so the list stays in sync with it. */
function annotateArray(name: string): string[] {
	const text = fs.readFileSync(path.join(PIPELINE_ROOT, 'annotate.sh'), 'utf8');
	// One-line `name=(a b c)`, or a multi-line list closed by `)` on its own line
	// (its comments may contain parentheses, so match up to that line, not the first `)`).
	const match =
		text.match(new RegExp(`^${name}=\\(([^\\n]*)\\)[ \\t]*$`, 'm')) ??
		text.match(new RegExp(`^${name}=\\(([\\s\\S]*?)^\\)`, 'm'));
	if (!match) return [];
	return match[1]
		.split('\n')
		.map((l) => l.replace(/#.*/, '').trim())
		.join(' ')
		.split(/\s+/)
		.filter(Boolean);
}

/** run-meta.sh's per-genome steps (margie-backend's host scripts), in order. */
const RESULT_STEPS = ['consolidation', 'labeling', 'scoring', 'fingerprint', 'evidence report', 'genome viewer', 'report figures'];

export function getTools(): { annotation: ToolInfo[]; tier2: string[]; intendedUse: string } {
	const env = pipelineEnv();
	const out = sourceConfig(
		env,
		`printf 'gated\\t%s\\n' "\${LICENCE_GATED_TOOLS[*]-}"; ` +
			`printf 'use\\t%s\\n' "\${LICENCE_INTENDED_USE-}"; ` +
			`printf 'stmt\\t%s\\n' "\${LICENCE_STATEMENT-}"; ` +
			LICENCE_TOOLS.map((t) => `printf 'lic_${t}\\t%s\\n' "\${LICENCE_AGREED_${t.toUpperCase()}-0}"`).join('; ')
	);
	const kv: Record<string, string> = {};
	for (const line of out.split('\n')) {
		const tab = line.indexOf('\t');
		if (tab > 0) kv[line.slice(0, tab)] = line.slice(tab + 1);
	}
	const gated = new Set((kv.gated || '').split(/\s+/).filter(Boolean));
	const gramPost = new Set(annotateArray('_gram_post_tools_default'));
	const intendedUse = kv.use || '';
	return {
		annotation: annotateArray('annotation_tools_default').map((name) => ({
			name,
			gated: gated.has(name),
			// Mirrors licence_is_accepted's pipeline.conf.sh route: flag=1, an intended use and the statement.
			licensed: !gated.has(name) || (kv[`lic_${name}`] === '1' && intendedUse !== '' && statementMatches(kv.stmt)),
			gramDependent: gramPost.has(name)
		})),
		tier2: RESULT_STEPS,
		intendedUse
	};
}

// ---------------------------------------------------------------- readiness

export interface CheckRow {
	status: 'ok' | 'missing' | 'warn' | 'optional' | 'unknown';
	name: string;
	kind: string;
	detail: string;
	section: string;
	/** A row from "Action required": the command to fix an earlier row, not stock of its own. */
	advice: boolean;
}

const MARKS: Record<string, CheckRow['status']> = {
	'✓': 'ok',
	'✗': 'missing',
	'!': 'warn',
	'⚠': 'warn',
	'–': 'optional',
	'?': 'unknown'
};

/** Runs the read-only ./check.sh and parses its report tables. */
export function runCheck(): Promise<{ rows: CheckRow[]; header: Record<string, string>; raw: string }> {
	return new Promise((resolve) => {
		const child = spawn('bash', ['./check.sh'], {
			cwd: PIPELINE_ROOT,
			env: { ...pipelineEnv(), NO_COLOR: '1', TERM: 'dumb' },
			stdio: ['ignore', 'pipe', 'pipe']
		});
		let raw = '';
		child.stdout.on('data', (d) => (raw += d));
		child.stderr.on('data', (d) => (raw += d));
		const timer = setTimeout(() => child.kill('SIGTERM'), 120_000);
		child.on('close', () => {
			clearTimeout(timer);
			raw = raw.replace(/\x1b\[[0-9;]*m/g, '');
			const rows: CheckRow[] = [];
			const header: Record<string, string> = {};
			let section = '';
			for (const line of raw.split('\n')) {
				const h = line.match(/^(Repo|DB root|Images|Runtime|HF env)\s*:\s*(.*)$/);
				if (h) header[h[1]] = h[2].trim();
				const row = line.match(/^\s{2}(\S)\s+(\S+)\s+(database|image|llm)\s+(.*)$/);
				if (row && MARKS[row[1]]) {
					rows.push({
						status: MARKS[row[1]],
						name: row[2],
						kind: row[3],
						detail: row[4].trim(),
						section,
						advice: /^action required/i.test(section)
					});
				} else if (/^\S/.test(line) && !h && !line.startsWith('[log]')) {
					section = line.trim();
				}
			}
			resolve({ rows, header, raw });
		});
	});
}

/** Returns the runtime the scripts will use: runtime.sh's detect_runtime with the saved settings ('' if none). */
export function resolveRuntime(): string {
	const res = spawnSync(
		'bash',
		['-c', 'set +u; . ./pipeline.conf.sh >/dev/null 2>&1; . processing/scripts/shared/runtime.sh; detect_runtime'],
		{ cwd: PIPELINE_ROOT, env: pipelineEnv(), encoding: 'utf8', timeout: 20_000 }
	);
	return res.status === 0 ? (res.stdout ?? '').trim() : '';
}

/** Returns the image prefix the pipeline runs (<REGISTRY>/<tool>:latest). */
export function registry(): string {
	return sourceConfig(pipelineEnv(), 'printf %s "${REGISTRY-margie}"').trim() || 'margie';
}

// ---------------------------------------------------------------- licences

/** Whether `tool`'s licence is accepted in these settings: its flag, an intended use and the statement. */
export function licenceAccepted(tool: string, values: Record<string, string>): boolean {
	return (
		(values.LICENCE_INTENDED_USE ?? '').trim() !== '' &&
		statementMatches(values.LICENCE_STATEMENT) &&
		values[`LICENCE_AGREED_${tool.toUpperCase()}`] === '1'
	);
}

/**
 * Records licences accepted in the GUI the way licence-gate.sh does: a
 * statement=yes row per tool in logs/licence-acceptances.tsv and a full-text
 * record per tool in logs/licensing/.
 */
export function recordLicenceAcceptance(tools: string[], intendedUse: string): void {
	if (!tools.length) return;
	const logRoot = path.join(PIPELINE_ROOT, 'logs');
	fs.mkdirSync(path.join(logRoot, 'licensing'), { recursive: true });
	const now = new Date();
	const ts = now.toISOString().replace(/\.\d+Z$/, 'Z');
	const compact = ts.replace(/[-:]/g, '');
	const user = os.userInfo().username;
	const version = spawnSync('git', ['-C', PIPELINE_ROOT, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).stdout?.trim() || 'unknown';
	for (const tool of tools) {
		fs.appendFileSync(
			path.join(logRoot, 'licence-acceptances.tsv'),
			`${ts}\t${tool}\tgui\t${intendedUse}\tuser=${user}\tpipeline=${version}\tstatement=yes\n`
		);
		const bar = '='.repeat(64);
		fs.writeFileSync(
			path.join(logRoot, 'licensing', `${user}-${tool}-${compact}.txt`),
			[
				bar,
				'margie — Prokaryotic Genome Annotation Pipeline',
				'Per-Tool Licence Acceptance Record',
				bar,
				'',
				`${user} accepted the licence terms for ${tool}`,
				'via the setup GUI (Settings → Licences), by typing the licence statement.',
				'',
				`Date/Time (UTC):   ${ts}`,
				`Pipeline Version:  ${version}`,
				`Declared Use:      ${intendedUse}`,
				`Statement:         ${LICENCE_STATEMENT}`,
				'',
				LICENCE_LEGAL_NOTICE,
				'',
				bar,
				'End of Licence Acceptance Record',
				bar,
				''
			].join('\n')
		);
	}
}
