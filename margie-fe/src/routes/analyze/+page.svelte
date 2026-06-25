<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';
	import ConfigField from '$lib/ConfigField.svelte';
	import { isWorkflowPathParam, getNestedValue, setNestedValue } from '$lib/configParams';

	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000'
		: '';

	function handle401() { clearToken(); goto('/login'); }

	interface WorkflowDetails {
		id: string;
		label: string;
		description: string;
		full_description: string;
		tools: Array<{key?: string; phase?: number; name: string; purpose: string; version: string; output: string}>;
		configurable_params: Array<{param: string; default: any; description: string; type: string}>;
		database_deps: string[];
		docs_url: string | null;
		containers: Array<{name: string; version: string}>;
		// Backend also returns these fields
		cmd_identifier: string;
		snakemake_file: string;
		other: string[];
		sif_files: Array<[string, string]>;
	}

	let genomePath = $state('');
	let outputDir = $state('');
	let homeDir = $state('');
	let selectedWorkflow = $state('margie_sb');
	let userConfig = $state<Record<string, any>>({});
	let availableWorkflows = $state<WorkflowDetails[]>([]);
	let loading = $state(false);
	let quickLoading = $state(false);
	let freshLoading = $state(false);
	let error = $state('');
	let selectedTools = $state<Set<string>>(new Set());
	let savingPathSettings = $state(false);
	let pathSettingsSaved = $state(false);
	// Kept in sync with profile/+page.svelte's REQUIRED_TOOL_KEYS -- see its
	// comment for why gtdbtk isn't required here even though rasttk is.
	const REQUIRED_TOOL_KEYS = new Set(['rasttk']);

	// Live preview of the full output path (timestamp is illustrative — generated server-side)
	let outputPreview = $derived(
		`${(outputDir.trim() || homeDir || '~').replace(/\/$/, '')}/YYYY-MM-DD-HHMM`
	);

	// The currently-selected workflow's tools that carry a phase/key (i.e.
	// support per-tool selection at all), kept in a stable order for the grid.
	let selectableTools = $derived(
		(availableWorkflows.find(w => w.id === selectedWorkflow)?.tools ?? [])
			.filter((t): t is {key: string; phase: number; name: string; purpose: string; version: string; output: string} =>
				!!t.key && t.phase !== undefined)
	);
	let toolsByPhase = $derived.by(() => {
		const groups = new Map<number, typeof selectableTools>();
		for (const tool of selectableTools) {
			if (!groups.has(tool.phase)) groups.set(tool.phase, []);
			groups.get(tool.phase)!.push(tool);
		}
		return [...groups.entries()].sort((a, b) => a[0] - b[0]);
	});
	let requiredToolKeys = $derived(
		selectableTools.filter(t => REQUIRED_TOOL_KEYS.has(t.key)).map(t => t.key)
	);

	function enforceRequiredTools(tools: Set<string>) {
		const next = new Set(tools);
		for (const key of requiredToolKeys) next.add(key);
		return next;
	}

	// sif_path/db_root for the selected workflow -- input_path/output_path are
	// the same underlying params but already have their own dedicated Genome
	// Path / Output Directory cards below, so they're excluded here.
	let selectedWorkflowPathParams = $derived(
		(availableWorkflows.find(w => w.id === selectedWorkflow)?.configurable_params ?? [])
			.filter(p => isWorkflowPathParam(p.param) && !p.param.endsWith('.input_path') && !p.param.endsWith('.output_path'))
	);

	function updateWorkflowPathValue(param: string, value: any) {
		setNestedValue(userConfig, param.split('.'), value);
		userConfig = { ...userConfig };
	}

	async function savePathSettings() {
		savingPathSettings = true;
		pathSettingsSaved = false;
		try {
			const configToSave = JSON.parse(JSON.stringify(userConfig));
			const response = await fetch(`${API_URL}/v1/ssh/config`, {
				method: 'PUT',
				headers: authHeaders(),
				body: JSON.stringify(configToSave),
			});
			if (response.status === 401) { handle401(); return; }
			if (!response.ok) throw new Error('Failed to save workflow paths');

			userConfig = configToSave;
			pathSettingsSaved = true;
			setTimeout(() => pathSettingsSaved = false, 2000);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to save workflow paths';
		} finally {
			savingPathSettings = false;
		}
	}

	onMount(async () => {
		// Fetch home_dir for the placeholder
		try {
			const res = await fetch(`${API_URL}/v1/auth/me`, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (res.ok) homeDir = (await res.json()).home_dir;
		} catch {}

		// Fetch saved config so we can autofill this workflow's saved input/output paths
		try {
			const res = await fetch(`${API_URL}/v1/ssh/config`, { headers: authHeaders() });
			if (res.ok) userConfig = await res.json();
		} catch {}

		// Load available workflows
		try {
			const res = await fetch(`${API_URL}/v1/ssh/workflows`, { headers: authHeaders() });
			if (res.ok) {
				availableWorkflows = await res.json();
				if (availableWorkflows.length > 0 && !availableWorkflows.find(w => w.id === selectedWorkflow)) {
					selectedWorkflow = availableWorkflows[0].id;
				}
			}
		} catch {}
	});

	// Autofill Genome Path / Output Directory from the selected workflow's saved
	// defaults (set in Profile > Workflow Specific Settings) whenever the
	// workflow selection changes. Re-runs automatically once userConfig loads.
	$effect(() => {
		const wfConfig = userConfig[selectedWorkflow];
		genomePath = wfConfig?.input_path || '';
		outputDir = wfConfig?.output_path || '';
	});

	let selectedForRun = $derived(enforceRequiredTools(selectedTools));

	$effect(() => {
		const saved: string | undefined = userConfig[selectedWorkflow]?.default_selected_tools;
		const nextSelection = saved
			? new Set(saved.split(',').map(k => k.trim()).filter(Boolean))
			: new Set(
				selectableTools
					.filter(t => t.phase !== undefined && t.phase <= 9)
					.map(t => t.key)
				);

		selectedTools = enforceRequiredTools(nextSelection);
	});

	async function handleAnalyze() {
		if (selectableTools.length > 0 && selectedForRun.size === 0) {
			error = 'Select at least one tool to run, or check them all to run the full pipeline.';
			return;
		}

		try {
			loading = true;
			error = '';

			// Omit selected_tools entirely when every selectable tool is checked
			// (the common case) -- functionally identical to sending the full
			// list, but keeps the request payload matching the "run everything"
			// default the backend already understands.
			const allSelected = selectedForRun.size === selectableTools.length;

			const response = await fetch(`${API_URL}/v1/ssh/run_workflow`, {
				method: 'POST',
				headers: authHeaders(),
				body: JSON.stringify({
					genome_path: genomePath,
					output_dir: outputDir,
					workflow: selectedWorkflow,
					selected_tools: allSelected ? null : Array.from(selectedForRun),
				}),
			});

			if (response.status === 401) { handle401(); return; }
			if (!response.ok) {
				const errData = await response.json().catch(() => ({}));
				throw new Error(errData.detail || 'Failed to start analysis');
			}

			const data = await response.json();
			console.log('Analysis started:', data);

			if (data.job_id) {
				goto(`/jobs/${data.job_id}`);
			}
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to start analysis';
			console.error('Error starting analysis:', e);
		} finally {
			loading = false;
		}
	}
</script>

<div class="w-full px-4 md:px-6 py-8">
	<h1 class="text-4xl font-bold mb-8 text-center text-primary-500">Genome Analysis</h1>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
			{error}
		</div>
	{/if}

	<!-- Workflow Selection -->
	{#if availableWorkflows.length > 0}
	<div class="card p-6 bg-surface-100 dark:bg-surface-800 mb-8">
		<h2 class="text-2xl font-semibold">Workflow</h2>
		<p class="text-sm text-surface-500 dark:text-surface-400 mb-4">
			Choose the workflow you want to run. The selected workflow controls which tools, dependencies, and workflow-specific configuration fields are available on this page.
		</p>
		<div class="flex flex-wrap gap-3">
			{#each availableWorkflows as wf}
				<button
					type="button"
					onclick={() => selectedWorkflow = wf.id}
					class="flex flex-col items-start px-5 py-3 rounded-lg border-2 text-left transition-colors max-w-xs
						{selectedWorkflow === wf.id
							? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20 text-primary-700 dark:text-primary-300'
							: 'border-surface-300 dark:border-surface-600 hover:border-surface-400 dark:hover:border-surface-500'}"
				>
					<span class="font-semibold">{wf.label}</span>
					{#if wf.description}
						<span class="text-xs text-surface-500 dark:text-surface-400 mt-1">{wf.description}</span>
					{/if}
				</button>
			{/each}
		</div>
	</div>
	{/if}

	<!-- Tool Selection -->
	<!-- Tool defaults are managed in Profile > Workflow Specific Settings. -->

	<!-- Genome Path -->
	<div class="card p-6 bg-surface-100 dark:bg-surface-800 mb-8">
		<h2 class="text-2xl font-semibold">Genome Path</h2>
		<p class="text-sm text-surface-500 dark:text-surface-400 mb-4">
			Enter the genome file you want to analyze, or a folder of genomes if the selected workflow supports batch input.
			If left blank, Analyze will use your saved input_path default for this workflow from Profile.
		</p>
		<input
			type="text"
			bind:value={genomePath}
			placeholder={selectedWorkflow === 'margie_sb'
				? 'Enter a genome file or a folder of genomes...'
				: 'Enter genome file path...'}
			class="w-full px-4 py-2 rounded border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900"
		/>
	</div>

	<!-- Output Directory -->
	<div class="card p-6 bg-surface-100 dark:bg-surface-800 mb-8">
		<h2 class="text-2xl font-semibold">Output Directory</h2>
		<p class="text-sm text-surface-500 dark:text-surface-400 mb-4">
			This is the base folder where results will be written. Analyze appends a timestamp automatically so each run lands in its own folder.
			If left blank, Analyze uses your home directory, or your saved output_path default for this workflow.
		</p>
		<input
			type="text"
			bind:value={outputDir}
			placeholder={homeDir || 'Loading...'}
			class="w-full px-4 py-2 rounded border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900"
		/>
		<div class="mt-2 text-xs text-surface-400">
			<code class="font-mono text-xs bg-surface-200 dark:bg-surface-700 px-1 py-0.5 rounded">{outputPreview}</code>
		</div>
	</div>

	<!-- Workflow Paths (sif_path / db_root) -->
	{#if selectedWorkflowPathParams.length > 0}
	<details class="mb-8 group">
		<summary class="card p-4 bg-surface-100 dark:bg-surface-800 cursor-pointer list-none">
			<div class="flex items-center justify-between">
				<div>
					<h2 class="text-2xl font-semibold">Workflow Paths</h2>
					<p class="text-xs text-surface-500 dark:text-surface-400 mt-1">
						These are advanced path overrides for the selected workflow, such as container roots or database roots.
						You usually do not need to change these unless you are pointing the workflow at a custom installation or a non-default database location.
					</p>
				</div>
				<span class="text-xs text-surface-500 group-open:hidden">Expand</span>
				<span class="text-xs text-surface-500 hidden group-open:inline">Collapse</span>
			</div>
		</summary>
		<div class="card p-6 bg-surface-100 dark:bg-surface-800 mt-2">
			<div class="flex items-center justify-between mb-4">
				<button type="button" onclick={savePathSettings} disabled={savingPathSettings}
					class="text-xs px-3 py-1 rounded font-semibold bg-primary-500 text-white hover:bg-primary-600 disabled:opacity-50">
					{savingPathSettings ? 'Saving...' : pathSettingsSaved ? 'Saved!' : 'Save'}
				</button>
			</div>
			<div class="space-y-2">
				{#each selectedWorkflowPathParams as param}
					{@const value = getNestedValue(userConfig, param.param.split('.'))}
					<ConfigField
						param={param.param}
						type={param.type}
						description={param.description}
						default={param.default}
						required={false}
						value={value}
						onchange={(newVal) => updateWorkflowPathValue(param.param, newVal)}
					/>
				{/each}
			</div>
		</div>
	</details>
	{/if}

	<!-- Analyze Button -->
	<div class="card p-6 bg-surface-100 dark:bg-surface-800">
		<button
			type="button"
			onclick={handleAnalyze}
			disabled={loading}
			class="btn px-10 py-3 text-lg font-bold text-white bg-purple-500 hover:bg-green-500 disabled:opacity-50 shadow-lg transition-colors"
		>
			{loading ? 'Starting Analysis...' : 'Analyze'}
		</button>
	</div>

	<!-- Divider -->
	<details class="mt-8 group">
		<summary class="card p-4 bg-surface-100 dark:bg-surface-800 cursor-pointer list-none">
			<div class="flex items-center justify-between">
				<div>
					<h2 class="text-2xl font-semibold">Sanity Checks</h2>
					<p class="text-xs text-surface-500 dark:text-surface-400 mt-1">
						Use the built-in test workflows to verify SSH access, Snakemake execution, and the pipeline wiring before you launch a real job.
						Quick Example is a lightweight test that can cache hit. Fresh Test always forces a clean run in a temporary directory.
					</p>
				</div>
				<span class="text-xs text-surface-500 group-open:hidden">Expand</span>
				<span class="text-xs text-surface-500 hidden group-open:inline">Collapse</span>
			</div>
		</summary>

		<!-- Test Workflows -->
		<div class="card p-6 bg-surface-100 dark:bg-surface-800 mt-2">
			<h2 class="text-2xl font-semibold mb-6">Test Workflows</h2>

			<div class="flex flex-wrap gap-4">
			<!-- Quick Example -->
			<div class="flex flex-col gap-2 max-w-xs">
				<button
					type="button"
					onclick={() => runWorkflow('run_quick_example', (v) => quickLoading = v)}
					disabled={quickLoading}
					class="btn px-6 py-2 text-white bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50"
				>
					{quickLoading ? 'Running...' : 'Quick Example'}
				</button>
				<p class="text-xs text-surface-500 dark:text-surface-400">
					Runs a lightweight end-to-end test over SSH. It touches Snakemake and the DB cache pipeline without spinning up containers.
					If you have run it before, it will often cache hit and finish almost instantly.
				</p>
			</div>

			<!-- Fresh Test -->
			<div class="flex flex-col gap-2 max-w-xs">
				<button
					type="button"
					onclick={() => runWorkflow('run_fresh_test', (v) => freshLoading = v)}
					disabled={freshLoading}
					class="btn px-6 py-2 text-white bg-amber-600 hover:bg-amber-700 disabled:opacity-50"
				>
					{freshLoading ? 'Running...' : 'Fresh Test'}
				</button>
				<p class="text-xs text-surface-500 dark:text-surface-400">
					Always writes to a temporary directory and bypasses the cache, so you get a true fresh run every time.
					Use this when you want to verify the full pipeline works end-to-end without relying on any prior state.
				</p>
			</div>
		</div>
		</div>
	</details>
</div>

