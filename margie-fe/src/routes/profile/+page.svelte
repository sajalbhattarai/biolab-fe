<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';
	import ConfigField from '$lib/ConfigField.svelte';
	import { isWorkflowPathParam, getNestedValue, setNestedValue } from '$lib/configParams';
	import { fetchLicenseStatus } from '$lib/license';

	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000'
		: '';

	let user = $state<{ username: string; cluster_username: string; cluster_host: string; home_dir: string } | null>(null);
	let config = $state<Record<string, any>>({});
	let workflows = $state<any[]>([]);
	let loading = $state(false);
	let saving = $state(false);
	let savingCredentials = $state(false);
	let creatingConfig = $state(false);
	let testingPath = $state(false);
	let pathTestResult = $state<{writable: boolean; error?: string} | null>(null);
	let selectedWorkflowPathId = $state('');
	let selectedToolKeys = $state<Set<string>>(new Set());
	let disabledTools = $state<Set<string>>(new Set());
	let generateFullOperonMap = $state(false);
	let error = $state('');
	let success = $state('');
	let credentialsError = $state('');
	let credentialsSuccess = $state('');
	let connected = $state(false);
	let checking = $state(true);
	// rasttk is the only true hard dependency: its rule always needs
	// GTDB-Tk's real classification (domain + genetic code) as an input
	// regardless of any flag. gtdbtk itself only controls whether that
	// classification also gets loaded into the database (margie_sb.smk's
	// run_rasttk docstring + rasttk_all's run_gtdbtk-gated input) -- the
	// underlying GTDB-Tk computation always runs either way, so it's safe
	// to let users deselect it independently.
	const REQUIRED_TOOL_KEYS = new Set(['rasttk']);
	const DEFAULT_ON_MAX_PHASE = 9;

	// Cluster credentials form
	let editClusterHost = $state('');
	let editClusterUsername = $state('');
	let editPrivateKey = $state('');
	let showPrivateKey = $state(false);

	// Form state for structured config
	let formValues = $state<Record<string, any>>({});

	// Check if required config fields are missing
	let missingRequiredFields = $derived.by(() => {
		const missing: string[] = [];

		// Check main_database
		if (!formValues.main_database || formValues.main_database.trim() === '') {
			missing.push('main_database');
		}

		// Check compute.cluster_default.account
		const account = formValues.compute?.['cluster_default']?.account;
		if (!account || account.trim() === '') {
			missing.push('SLURM account');
		}

		return missing;
	});

	onMount(async () => {
		await loadUser();
		await loadWorkflows();
		try {
			const s = await fetchLicenseStatus();
			disabledTools = new Set(s.disabled_tools ?? []);
		} catch {
			/* if we can't load it, tools stay enabled; the run path still enforces */
		}
	});

	async function loadUser() {
		try {
			const res = await fetch(`${API_URL}/v1/auth/me`, { headers: authHeaders() });
			if (res.status === 401) {
				clearToken();
				goto('/login');
				return;
			}
			if (!res.ok) throw new Error('Failed to load user profile');
			user = await res.json();

			// Populate credentials form with current values
			if (user) {
				editClusterHost = user.cluster_host;
				editClusterUsername = user.cluster_username;
			}

			await checkConnection();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load profile';
			checking = false;
		}
	}

	async function checkConnection() {
		checking = true;
		error = '';
		try {
			const res = await fetch(`${API_URL}/v1/ssh/status`, { headers: authHeaders() });
			if (res.status === 401) { clearToken(); goto('/login'); return; }
			if (!res.ok) throw new Error('Could not reach backend');
			const data = await res.json();
			connected = data.connected;
			if (connected) {
				await loadConfig();
			}
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to check SSH connection';
			connected = false;
		} finally {
			checking = false;
		}
	}

	async function loadWorkflows() {
		try {
			const res = await fetch(`${API_URL}/v1/ssh/workflows`, { headers: authHeaders() });
			if (res.ok) {
				workflows = await res.json();
			}
		} catch (e) {
			console.error('Failed to load workflows:', e);
		}
	}

	async function loadConfig() {
		loading = true;
		error = '';
		try {
			const res = await fetch(`${API_URL}/v1/ssh/config`, { headers: authHeaders() });
			if (res.status === 401) { clearToken(); goto('/login'); return; }
			if (!res.ok) throw new Error('Failed to load config');
			config = await res.json();

			// Populate form values from config
			formValues = { ...config };
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load config';
		} finally {
			loading = false;
		}
	}

	async function testPathWritable(path: string) {
		testingPath = true;
		pathTestResult = null;

		try {
			const res = await fetch(`${API_URL}/v1/ssh/test-path-writable`, {
				method: 'POST',
				headers: authHeaders(),
				body: JSON.stringify({ path }),
			});

			if (res.status === 401) { clearToken(); goto('/login'); return; }
			if (res.ok) {
				pathTestResult = await res.json();
			} else {
				pathTestResult = { writable: false, error: 'Failed to test path' };
			}
		} catch (e) {
			pathTestResult = { writable: false, error: e instanceof Error ? e.message : 'Failed to test path' };
		} finally {
			testingPath = false;
		}
	}

	// Per-workflow root-path settings, grouped by workflow, for the
	// "Workflow Specific Settings" section.
	function getWorkflowPathSettings(workflows: any[]): Array<{ id: string; label: string; params: any[] }> {
		return workflows
			.map(workflow => ({
				id: workflow.id,
				label: workflow.label,
				params: (workflow.configurable_params || []).filter((p: any) => isWorkflowPathParam(p.param)),
			}))
			.filter(entry => entry.params.length > 0);
	}

	let workflowPathSettings = $derived(getWorkflowPathSettings(workflows));
	let selectedWorkflowPathSettings = $derived(
		workflowPathSettings.find(entry => entry.id === selectedWorkflowPathId) ?? workflowPathSettings[0] ?? null
	);
	let selectedWorkflowDetails = $derived(
		workflows.find(workflow => workflow.id === selectedWorkflowPathId) ?? null
	);
	let selectableTools = $derived(
		(selectedWorkflowDetails?.tools ?? [])
			.filter((tool): tool is {key: string; phase: number; name: string; purpose: string; version: string; output: string} =>
				!!tool.key && tool.phase !== undefined)
	);
	let requiredToolKeys = $derived(
		selectableTools.filter(tool => REQUIRED_TOOL_KEYS.has(tool.key)).map(tool => tool.key)
	);
	let slurmParams = $derived.by(() => {
		const params = workflows.flatMap(wf => wf.configurable_params || []).filter((param: any) => param.param.startsWith('compute.'));
		const unique = new Map<string, any>();
		for (const param of params) {
			if (!unique.has(param.param)) unique.set(param.param, param);
		}
		return [...unique.values()];
	});

	// Build config to save - syncs YAML to match what's shown in the UI, while
	// PRESERVING any existing keys the UI doesn't know about (e.g. top-level
	// legacy paths like sif_path/db_root/base_input_dir that predate the
	// namespaced margie_sb.* convention). Without this, saving anything here
	// would silently drop those keys on the next write, since the PUT
	// endpoint overwrites the whole file rather than merging.
	function buildConfigToSave(): Record<string, any> {
		const configToSave: Record<string, any> = JSON.parse(JSON.stringify(config));
		const allParams = workflows.flatMap(wf => wf.configurable_params || []);

		// Write ALL parameters to YAML - what you see is what you get
		allParams.forEach((param: any) => {
			const parts = param.param.split('.');
			const value = getNestedValue(formValues, parts);

			// Use the value from form if set, otherwise use the default
			const finalValue = (value !== null && value !== undefined && value !== '')
				? value
				: param.default;

			// Write to config if we have a value (even if it's the default)
			if (finalValue !== null && finalValue !== undefined) {
				setNestedValue(configToSave, parts, finalValue);
			}
		});

		// Always include main_database - use value or default
		const mainDb = formValues.main_database?.trim();
		configToSave.main_database = mainDb || '~/.local/share/bioinformatics-tools/my-db.db';

		if (selectedWorkflowPathId) {
			if (!configToSave[selectedWorkflowPathId]) configToSave[selectedWorkflowPathId] = {};
			configToSave[selectedWorkflowPathId].default_selected_tools = Array.from(selectedToolKeys).join(',');
			// Persisted opt-in: the backend reads this server-side at run time
			// (does not depend on the Analyze-page payload), gating the full
			// per-genome operon atlas.
			configToSave[selectedWorkflowPathId].run_full_operon_map = generateFullOperonMap;
		}

		return configToSave;
	}

	function updateFormValue(param: string, value: any) {
		const parts = param.split('.');
		setNestedValue(formValues, parts, value);
		formValues = { ...formValues }; // Trigger reactivity
	}

	$effect(() => {
		const firstWorkflowId = workflowPathSettings[0]?.id ?? '';
		if (firstWorkflowId && !workflowPathSettings.some(entry => entry.id === selectedWorkflowPathId)) {
			selectedWorkflowPathId = firstWorkflowId;
		}
	});

	function enforceRequiredTools(tools: Set<string>) {
		const next = new Set(tools);
		for (const key of requiredToolKeys) next.add(key);
		return next;
	}

	function toggleWorkflowTool(key: string) {
		if (requiredToolKeys.includes(key) || disabledTools.has(key)) return;
		const next = new Set(selectedToolKeys);
		if (next.has(key)) next.delete(key); else next.add(key);
		selectedToolKeys = enforceRequiredTools(next);
	}

	function selectAllWorkflowTools() {
		selectedToolKeys = enforceRequiredTools(
			new Set(selectableTools.map(tool => tool.key).filter(key => !disabledTools.has(key)))
		);
	}

	function selectNoWorkflowTools() {
		selectedToolKeys = enforceRequiredTools(new Set());
	}

	$effect(() => {
		const saved: string | undefined = config[selectedWorkflowPathId]?.default_selected_tools;
		if (saved) {
			const savedKeys = new Set(saved.split(',').map(key => key.trim()).filter(Boolean));
			selectedToolKeys = enforceRequiredTools(new Set(selectableTools.filter(tool => savedKeys.has(tool.key) && !disabledTools.has(tool.key)).map(tool => tool.key)));
		} else {
			selectedToolKeys = enforceRequiredTools(new Set(
				selectableTools.filter(tool => tool.phase <= DEFAULT_ON_MAX_PHASE && !disabledTools.has(tool.key)).map(tool => tool.key)
			));
		}
	});

	// Load the persisted full-operon-map opt-in for the selected workflow, so the
	// toggle reflects what's saved (and is checked when it's on).
	$effect(() => {
		generateFullOperonMap = Boolean(config[selectedWorkflowPathId]?.run_full_operon_map);
	});

	async function saveConfig() {
		saving = true;
		error = '';
		success = '';

		const configToSave = buildConfigToSave();

		// If main_database exists, test it before saving
		if (configToSave.main_database) {
			await testPathWritable(configToSave.main_database);
			if (pathTestResult && !pathTestResult.writable) {
				error = `Cannot save: main_database path is not writable. ${pathTestResult.error || ''}`;
				saving = false;
				return;
			}
		}

		try {
			const res = await fetch(`${API_URL}/v1/ssh/config`, {
				method: 'PUT',
				headers: authHeaders(),
				body: JSON.stringify(configToSave),
			});
			if (res.status === 401) { clearToken(); goto('/login'); return; }
			if (!res.ok) throw new Error('Failed to save config');

			// Update local config state
			config = configToSave;

			success = 'Configuration saved successfully.';
			setTimeout(() => success = '', 3000);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to save config';
		} finally {
			saving = false;
		}
	}

	function isObject(val: any): val is Record<string, any> {
		return val !== null && typeof val === 'object' && !Array.isArray(val);
	}

	function removeItem(arr: any[], index: number) {
		arr.splice(index, 1);
		config = { ...config };
	}

	function addItem(arr: any[]) {
		arr.push('');
		config = { ...config };
	}

	async function createDefaultConfig() {
		creatingConfig = true;
		error = '';
		success = '';

		try {
			const res = await fetch(`${API_URL}/v1/ssh/config/create-default`, {
				method: 'POST',
				headers: authHeaders(),
			});

			if (res.status === 401) {
				clearToken();
				goto('/login');
				return;
			}

			if (!res.ok) {
				const errData = await res.json().catch(() => ({}));
				throw new Error(errData.detail || 'Failed to create default config');
			}

			success = 'Default configuration created successfully!';

			// Reload config to display it
			await loadConfig();

			setTimeout(() => success = '', 3000);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to create default config';
		} finally {
			creatingConfig = false;
		}
	}

	async function updateCredentials() {
		savingCredentials = true;
		credentialsError = '';
		credentialsSuccess = '';

		// Build the payload - only send fields that have values
		const payload: Record<string, string> = {};

		// Only send changed or non-empty values
		if (editClusterHost && editClusterHost !== user?.cluster_host) {
			payload.cluster_host = editClusterHost;
		}
		if (editClusterUsername && editClusterUsername !== user?.cluster_username) {
			payload.cluster_username = editClusterUsername;
		}
		if (editPrivateKey.trim()) {
			payload.private_key = editPrivateKey;
		}

		if (Object.keys(payload).length === 0) {
			credentialsError = 'No changes to save. Update at least one field.';
			savingCredentials = false;
			return;
		}

		try {
			const res = await fetch(`${API_URL}/v1/auth/update-credentials`, {
				method: 'PUT',
				headers: authHeaders(),
				body: JSON.stringify(payload),
			});

			if (res.status === 401) {
				clearToken();
				goto('/login');
				return;
			}

			if (!res.ok) {
				const errData = await res.json().catch(() => ({}));
				throw new Error(errData.detail || 'Failed to update credentials');
			}

			credentialsSuccess = 'Cluster credentials updated successfully! The connection will be retested.';

			// Clear the private key input after successful update
			editPrivateKey = '';

			// Reload user and recheck connection
			await loadUser();

			setTimeout(() => credentialsSuccess = '', 5000);
		} catch (e) {
			credentialsError = e instanceof Error ? e.message : 'Failed to update credentials';
		} finally {
			savingCredentials = false;
		}
	}
</script>

<div class="w-full px-4 md:px-6 py-8 space-y-8">
	<section class="text-center py-8">
		<h1 class="text-4xl font-bold text-primary-500 mb-4">Profile Settings</h1>
		<p class="text-lg text-surface-600 dark:text-surface-300">
			{#if user}
				Configuration for <code class="font-mono text-sm bg-surface-200 dark:bg-surface-700 px-2 py-1 rounded">{user.cluster_username}@{user.cluster_host}</code>
			{:else}
				Loading profile...
			{/if}
		</p>
	</section>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">{error}</div>
	{/if}

	{#if success}
		<div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded">{success}</div>
	{/if}

	<!-- SSH Connection Status -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800 w-full max-w-2xl">
		<div class="mb-2 flex items-center gap-2">
			<h2 class="text-2xl font-bold text-primary-500">SSH Connection</h2>
		</div>
		<p class="text-sm text-surface-500 mb-3">Checks whether the backend can reach your cluster using the saved credentials.</p>
		{#if checking}
			<p class="text-sm text-surface-500">Checking connection...</p>
		{:else if connected}
			<div class="flex items-center gap-2">
				<span class="inline-block w-2.5 h-2.5 rounded-full bg-green-500"></span>
				<span class="text-sm text-green-700 dark:text-green-400 font-semibold">Connected to {user?.cluster_host}</span>
			</div>
		{:else}
			<div class="flex items-center gap-2">
				<span class="inline-block w-2.5 h-2.5 rounded-full bg-red-500"></span>
				<span class="text-sm text-red-700 dark:text-red-400 font-semibold">Could not connect to {user?.cluster_host}</span>
			</div>
			<div class="mt-2 text-sm text-surface-500 leading-snug">
				Update cluster host, username, or SSH key under Cluster Credentials, then retry.
			</div>
			<button type="button" onclick={checkConnection} class="btn variant-outline-primary mt-3 px-4 py-2 text-sm">
				Retry
			</button>
		{/if}
	</section>

	<!-- Required Fields Warning -->
	{#if connected && Object.keys(config).length > 0 && missingRequiredFields.length > 0}
		<section class="card p-6 bg-red-50 dark:bg-red-900/20 border-2 border-red-500">
			<div class="flex items-start gap-3">
				<span class="text-red-600 dark:text-red-400 text-2xl">⚠️</span>
				<div class="flex-1">
					<h3 class="text-lg font-bold text-red-900 dark:text-red-100 mb-2">
						Required Configuration Missing
					</h3>
					<p class="text-red-800 dark:text-red-200 mb-3">
						The following required fields must be set before you can run workflows:
					</p>
					<ul class="list-disc list-inside space-y-1 text-red-700 dark:text-red-300 mb-3">
						{#each missingRequiredFields as field}
							<li class="font-mono">{field}</li>
						{/each}
					</ul>
					<p class="text-sm text-red-800 dark:text-red-200">
						Please scroll down and fill in these required fields in the configuration form below.
					</p>
				</div>
			</div>
		</section>
	{/if}

	<!-- Config Section -->
	{#if loading}
		<section class="card p-6 bg-surface-100 dark:bg-surface-800 text-center">
			<p class="text-surface-500">Loading configuration...</p>
		</section>
	{:else if connected && Object.keys(config).length > 0}
		<section class="card p-6 bg-surface-100 dark:bg-surface-800">
			<h2 class="text-2xl font-bold text-primary-500">CONFIG</h2>
			<p class="text-sm text-surface-500 dark:text-surface-400 mb-4">
				This section stores the global database and SLURM settings used by the backend.
				Workflow-specific roots and tool defaults live below in Workflow Specific Settings.
			</p>

			<!-- Important Note -->
			<div class="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4 mb-6">
				<div class="flex items-start gap-3">
					<span class="text-blue-600 dark:text-blue-400 text-xl font-bold">ℹ️</span>
					<div>
						<p class="text-sm text-blue-900 dark:text-blue-100 font-semibold mb-1">Database Configuration</p>
						<p class="text-xs text-blue-800 dark:text-blue-200">
							Set the main_database key to the writable database path you want the backend to use.
							If you leave it unset, the app falls back to ~/.local/share/bioinformatics-tools/my-db.db.
						</p>
					</div>
				</div>
			</div>

			<h3 class="text-xl font-semibold mb-4 text-secondary-500">SLURM Configuration</h3>
			<div class="grid gap-3 md:grid-cols-2">
				{#each slurmParams as param}
					{@const parts = param.param.split('.')}
					{@const value = getNestedValue(formValues, parts)}

					<ConfigField
						param={param.param}
						type={param.type}
						description={param.description}
						default={param.default}
						required={param.required || false}
						compact={true}
						value={value}
						onchange={(newVal) => updateFormValue(param.param, newVal)}
					/>
				{/each}

				<!-- Special handling for main_database -->
				<div class="md:col-span-2 rounded-2xl border-2 border-amber-300 dark:border-amber-700 bg-gradient-to-br from-amber-50 to-surface-50 dark:from-amber-950/20 dark:to-surface-900/60 p-5 shadow-sm">
					<div class="flex items-start gap-3 mb-3">
						<span class="text-amber-600 dark:text-amber-400 text-xl font-bold">⚠️</span>
						<div class="flex-1">
							<h3 class="text-lg font-semibold font-mono text-amber-900 dark:text-amber-100 mb-1">main_database</h3>
							<p class="text-sm text-amber-800 dark:text-amber-200">
								This path must be writable by your user. The database file will be created here if it doesn't exist.
							</p>
						</div>
					</div>

					<div class="space-y-3">
						<input
							type="text"
							bind:value={formValues.main_database}
							oninput={() => pathTestResult = null}
							class="input w-full px-4 py-2 rounded-xl bg-white dark:bg-amber-900/40 border-2 border-amber-300 dark:border-amber-600 font-mono text-sm"
							placeholder="~/.local/share/bioinformatics-tools/my-db.db"
						/>

						<div class="flex items-center gap-3">
							<button
								type="button"
								onclick={() => testPathWritable(formValues.main_database)}
								disabled={testingPath || !formValues.main_database}
								class="btn variant-filled-secondary px-4 py-2 text-sm"
							>
								{testingPath ? 'Testing...' : 'Test Writability'}
							</button>

							{#if pathTestResult}
								{#if pathTestResult.writable}
									<div class="flex items-center gap-2 text-green-700 dark:text-green-400">
										<span class="inline-block w-2 h-2 rounded-full bg-green-500"></span>
										<span class="text-sm font-semibold">Path is writable ✓</span>
									</div>
								{:else}
									<div class="flex items-center gap-2 text-red-700 dark:text-red-400">
										<span class="inline-block w-2 h-2 rounded-full bg-red-500"></span>
										<span class="text-sm font-semibold">Path is not writable ✗</span>
									</div>
								{/if}
							{/if}
						</div>

						{#if pathTestResult && !pathTestResult.writable && pathTestResult.error}
							<div class="text-xs text-red-700 dark:text-red-400 bg-red-100 dark:bg-red-900/30 rounded p-2 font-mono">
								{pathTestResult.error}
							</div>
						{/if}
					</div>
				</div>
			</div>

			<div class="flex justify-center mt-8">
				<button
					type="button"
					onclick={saveConfig}
					disabled={saving}
					class="btn variant-filled-primary btn-lg px-8 py-2"
				>
					{saving ? 'Saving...' : 'Save Configuration'}
				</button>
			</div>

			<!-- Configuration Guide -->
			<div class="mt-6 pt-6 border-t border-surface-300 dark:border-surface-600">
				<details class="text-left">
					<summary class="cursor-pointer text-sm text-primary-500 hover:text-primary-700 font-semibold mb-3">
						📖 Configuration Guide
					</summary>
					<div class="mt-3 space-y-3 text-sm text-surface-700 dark:text-surface-300">
						<div class="bg-surface-200 dark:bg-surface-700 rounded-lg p-4 space-y-3">
							<h4 class="font-semibold text-primary-600 dark:text-primary-400">Workflow-specific settings</h4>
							<p>
								The workflow selector above is where you edit per-workflow container, database, input, and output paths.
								Those values are stored separately for each workflow and reused automatically on Analyze.
							</p>
							<p class="text-xs text-surface-500">
								The lower config area is intentionally limited to SLURM and database settings; workflow-specific tool settings are no longer edited globally here.
							</p>
						</div>

						<div class="bg-surface-200 dark:bg-surface-700 rounded-lg p-4 space-y-3">
							<h4 class="font-semibold text-primary-600 dark:text-primary-400">Adding New Workflows</h4>
							<p class="text-xs">
								To add a new workflow: create a <code class="font-mono bg-surface-300 dark:bg-surface-600 px-1 py-0.5 rounded">.smk</code> file
								with a corresponding WorkflowKey. It will work with built-in defaults until you customize parameters here.
								All new workflows automatically support the hierarchical config pattern.
							</p>
						</div>

						<div class="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
							<p class="text-xs text-blue-900 dark:text-blue-100">
								<strong>💡 Tip:</strong> You only need to specify parameters you want to override.
								Unspecified values use sensible defaults defined in each workflow rule.
							</p>
						</div>
					</div>
				</details>
			</div>
		</section>

		{#if workflowPathSettings.length > 0}
			<section class="card p-6 bg-surface-100 dark:bg-surface-800 mt-8">
				<h2 class="text-2xl font-bold text-primary-500">Workflow Specific Settings</h2>
				<p class="text-sm text-surface-500 dark:text-surface-400 mb-4">
					Edit per-workflow roots and defaults in one place.
					This section stays collapsed until you need it, but it is the source of truth for Analyze defaults.
				</p>
				<details class="group">
					<summary class="cursor-pointer list-none rounded-2xl border border-primary-200/70 dark:border-primary-900/40 bg-gradient-to-br from-primary-50 to-surface-50 dark:from-primary-950/30 dark:to-surface-900/70 p-5 shadow-sm">
						<div class="flex flex-col gap-3 md:flex-row md:items-end md:justify-end">
							<div class="text-xs font-semibold uppercase tracking-wide text-surface-500 group-open:hidden">Expand</div>
							<div class="text-xs font-semibold uppercase tracking-wide text-surface-500 hidden group-open:block">Collapse</div>
						</div>
					</summary>

					<div class="mt-4 rounded-xl border border-surface-200 dark:border-surface-700 bg-white/80 dark:bg-surface-800/80 p-4 space-y-4">
						<div class="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
							<div>
								<h3 class="text-lg font-semibold text-primary-600 dark:text-primary-400">
									{selectedWorkflowPathSettings?.label}
								</h3>
								<p class="mt-1 text-xs text-surface-500">SIF/database roots and default input/output paths for this workflow.</p>
							</div>
							<div class="min-w-[16rem]">
								<label class="block text-xs font-semibold uppercase tracking-wide text-surface-500 mb-2" for="workflow-path-picker">
									Workflow
								</label>
								<select
									id="workflow-path-picker"
									bind:value={selectedWorkflowPathId}
									class="input w-full rounded-lg bg-white dark:bg-surface-700 border border-surface-300 dark:border-surface-600 px-4 py-2"
								>
									{#each workflowPathSettings as wfSettings}
										<option value={wfSettings.id}>{wfSettings.label}</option>
									{/each}
								</select>
							</div>
						</div>

						{#if selectedWorkflowPathSettings}
							<div class="space-y-1">
								{#each selectedWorkflowPathSettings.params as param}
									{@const parts = param.param.split('.')}
									{@const value = getNestedValue(formValues, parts)}

									<ConfigField
										param={param.param}
										type={param.type}
										description={param.description}
										default={param.default}
										required={false}
										value={value}
										onchange={(newVal) => updateFormValue(param.param, newVal)}
									/>
								{/each}
							</div>
						{/if}

						{#if selectableTools.length > 0}
							<div class="rounded-xl border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900/40 p-4 space-y-4">
								<div class="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
									<div>
										<h4 class="text-lg font-semibold text-secondary-500">Tool Defaults</h4>
										<p class="text-xs text-surface-500 dark:text-surface-400 mt-1">
											Pick the tools you want selected by default for this workflow on Analyze.
											Required tools stay enabled, but the rest can be saved as your preferred starting point.
										</p>
									</div>
									<div class="flex flex-wrap gap-2">
										<button type="button" onclick={selectAllWorkflowTools} class="text-xs px-3 py-1 rounded border border-surface-300 dark:border-surface-600 hover:bg-surface-200 dark:hover:bg-surface-700">Select all</button>
										<button type="button" onclick={selectNoWorkflowTools} class="text-xs px-3 py-1 rounded border border-surface-300 dark:border-surface-600 hover:bg-surface-200 dark:hover:bg-surface-700">Select none</button>
									</div>
								</div>
								<div class="grid gap-2 md:grid-cols-2 xl:grid-cols-3">
									{#each selectableTools as tool}
										{@const isRequired = requiredToolKeys.includes(tool.key)}
										{@const isDisabled = disabledTools.has(tool.key)}
										<label class="flex items-start gap-3 rounded-lg border border-surface-300 dark:border-surface-600 px-3 py-2 {isRequired ? 'bg-surface-200/60 dark:bg-surface-700/40 opacity-90' : isDisabled ? 'opacity-60 cursor-not-allowed' : 'cursor-pointer hover:bg-surface-200 dark:hover:bg-surface-700'}">
											<input
												type="checkbox"
												checked={selectedToolKeys.has(tool.key) && !isDisabled}
												disabled={isRequired || isDisabled}
												onchange={() => toggleWorkflowTool(tool.key)}
												class="mt-1 accent-primary-500"
											/>
											<div class="min-w-0">
												<div class="flex items-center gap-2">
													<span class="text-sm font-semibold">{tool.name}</span>
													{#if isRequired}
														<span class="text-[10px] uppercase tracking-wide rounded-full bg-primary-500/15 text-primary-700 dark:text-primary-300 px-2 py-0.5">Required</span>
													{/if}
													{#if isDisabled}
														<span class="text-[10px] uppercase tracking-wide rounded-full bg-amber-500/15 text-amber-700 dark:text-amber-300 px-2 py-0.5">License required</span>
													{/if}
												</div>
												<p class="mt-1 text-xs text-surface-500 leading-snug">{tool.purpose}</p>
											</div>
										</label>
									{/each}
								</div>
							</div>
						{/if}

						{#if selectedWorkflowPathId === 'margie_sb'}
							<div class="rounded-xl border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900/40 p-4">
								<label class="flex items-start gap-3 cursor-pointer">
									<input type="checkbox" bind:checked={generateFullOperonMap} class="mt-1 accent-primary-500" />
									<div class="min-w-0">
										<h4 class="text-lg font-semibold text-secondary-500">Full-genome operon map</h4>
										<p class="mt-1 text-xs text-surface-500 dark:text-surface-400 leading-snug">
											Draw operon diagrams for <span class="font-semibold">every</span> gene in each
											genome (all operon sizes, paginated) — not just the representative examples.
											Heavier (~3-4&nbsp;min/genome) and runs after scoring. Saved with this
											workflow, so every run applies it until you turn it off here.
										</p>
									</div>
								</label>
							</div>
						{/if}

						<div class="flex justify-center pt-2">
							<button
								type="button"
								onclick={saveConfig}
								disabled={saving}
								class="btn variant-filled-primary px-8 py-2"
							>
								{saving ? 'Saving...' : 'Save Workflow Settings'}
							</button>
						</div>
					</div>
				</details>
			</section>
		{/if}
	{:else if connected}
		<section class="card p-6 bg-surface-100 dark:bg-surface-800 text-center space-y-4">
			<p class="text-surface-600 dark:text-surface-300 text-lg">No configuration found</p>
			<p class="text-surface-500 text-sm">
				The file <code class="font-mono text-sm bg-surface-200 dark:bg-surface-700 px-2 py-1 rounded">~/.config/bioinformatics-tools/config.yaml</code> does not exist on {user?.cluster_host}.
			</p>
			<div class="pt-6 pb-2">
				<button
					type="button"
					onclick={createDefaultConfig}
					disabled={creatingConfig}
					class="btn variant-filled-success text-lg font-bold px-12 py-4 shadow-lg hover:shadow-xl transition-shadow"
				>
					{creatingConfig ? 'Creating...' : '✨ Create Default Configuration'}
				</button>
			</div>
			<div class="pt-2 px-8">
				<details class="text-left">
					<summary class="cursor-pointer text-sm text-primary-500 hover:text-primary-700 font-semibold">What will be created?</summary>
					<div class="mt-3 text-xs text-surface-600 dark:text-surface-400 bg-surface-200 dark:bg-surface-700 rounded p-3 font-mono">
						<pre>main_database: ~/.local/share/bioinformatics-tools/my-db.db
compute:
  cluster_default:
    accounts: []
    max_cpus: 0
    queues: none</pre>
					</div>
				</details>
			</div>
		</section>
	{/if}

	<!-- Cluster Credentials Section -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<h2 class="text-2xl font-bold text-primary-500">Cluster Credentials</h2>
		<p class="text-sm text-surface-500 dark:text-surface-400 mb-4">
			Update your HPC cluster connection details here.
			The backend validates changes before saving them, so you can confirm the new host, username, and key are working.
		</p>

		{#if credentialsError}
			<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">{credentialsError}</div>
		{/if}

		{#if credentialsSuccess}
			<div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-4">{credentialsSuccess}</div>
		{/if}

		<div class="space-y-4">
			<!-- Cluster Host -->
			<div>
				<label for="cluster-host" class="block text-sm font-semibold mb-2">Cluster Host</label>
				<input
					id="cluster-host"
					type="text"
					bind:value={editClusterHost}
					placeholder="e.g., negishi.rcac.purdue.edu"
					disabled={savingCredentials}
					class="input w-full px-4 py-2 rounded-lg bg-white dark:bg-surface-700 border border-surface-300 dark:border-surface-600 font-mono text-sm"
				/>
			</div>

			<!-- Cluster Username -->
			<div>
				<label for="cluster-username" class="block text-sm font-semibold mb-2">Cluster Username</label>
				<input
					id="cluster-username"
					type="text"
					bind:value={editClusterUsername}
					placeholder="e.g., your-hpc-username"
					disabled={savingCredentials}
					class="input w-full px-4 py-2 rounded-lg bg-white dark:bg-surface-700 border border-surface-300 dark:border-surface-600 font-mono text-sm"
				/>
			</div>

			<!-- Private Key -->
			<div>
				<div class="flex items-center justify-between mb-2">
					<label for="private-key" class="block text-sm font-semibold">SSH Private Key</label>
					<button
						type="button"
						onclick={() => showPrivateKey = !showPrivateKey}
						class="text-xs text-primary-500 hover:text-primary-700 font-semibold"
					>
						{showPrivateKey ? 'Hide' : 'Show'}
					</button>
				</div>
				<textarea
					id="private-key"
					bind:value={editPrivateKey}
					placeholder="Leave blank to keep current key, or paste new key here..."
					disabled={savingCredentials}
					rows="8"
					class="input w-full px-4 py-2 rounded-lg bg-white dark:bg-surface-700 border border-surface-300 dark:border-surface-600 font-mono text-xs resize-y"
					style={showPrivateKey ? '' : '-webkit-text-security: disc; text-security: disc;'}
				></textarea>
				<p class="text-xs text-surface-400 mt-1">
					Leave blank to keep your current private key. Only paste a new key if you need to update it.
				</p>
			</div>

			<!-- Save Button -->
			<div class="flex justify-center pt-4">
				<button
					type="button"
					onclick={updateCredentials}
					disabled={savingCredentials}
					class="btn variant-filled-secondary btn-lg px-8 py-2"
				>
					{savingCredentials ? 'Updating...' : 'Update Credentials'}
				</button>
			</div>
		</div>
	</section>
</div>
