<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';
	import ConfigSection from '$lib/ConfigSection.svelte';
	import ConfigField from '$lib/ConfigField.svelte';

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
	let error = $state('');
	let success = $state('');
	let credentialsError = $state('');
	let credentialsSuccess = $state('');
	let connected = $state(false);
	let checking = $state(true);

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

		// Check compute.cluster-default.account
		const account = formValues.compute?.['cluster-default']?.account;
		if (!account || account.trim() === '') {
			missing.push('SLURM account');
		}

		return missing;
	});

	onMount(async () => {
		await loadUser();
		await loadWorkflows();
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

	// Group configurable params by section
	function groupParamsBySection(workflows: any[]): Map<string, any[]> {
		const sections = new Map<string, any[]>();

		workflows.forEach(workflow => {
			workflow.configurable_params?.forEach((param: any) => {
				const parts = param.param.split('.');
				const section = parts[0]; // e.g., "compute", "prodigal", "pfam"

				if (!sections.has(section)) {
					sections.set(section, []);
				}
				sections.get(section)!.push(param);
			});
		});

		return sections;
	}

	// Build config to save - syncs YAML to exactly match what user sees in UI
	function buildConfigToSave(): Record<string, any> {
		const configToSave: Record<string, any> = {};
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

		return configToSave;
	}

	function getNestedValue(obj: any, path: string[]): any {
		return path.reduce((current, key) => current?.[key], obj);
	}

	function setNestedValue(obj: any, path: string[], value: any) {
		const lastKey = path[path.length - 1];
		const parent = path.slice(0, -1).reduce((current, key) => {
			if (!current[key]) current[key] = {};
			return current[key];
		}, obj);
		parent[lastKey] = value;
	}

	function updateFormValue(param: string, value: any) {
		const parts = param.split('.');
		setNestedValue(formValues, parts, value);
		formValues = { ...formValues }; // Trigger reactivity
	}

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

<div class="container mx-auto p-8 max-w-4xl space-y-8">
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
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<h2 class="text-2xl font-bold mb-4 text-primary-500">SSH Connection</h2>
		{#if checking}
			<p class="text-surface-500">Checking connection...</p>
		{:else if connected}
			<div class="flex items-center gap-2">
				<span class="inline-block w-3 h-3 rounded-full bg-green-500"></span>
				<span class="text-green-700 dark:text-green-400 font-semibold">Connected to {user?.cluster_host}</span>
			</div>
		{:else}
			<div class="flex items-center gap-2">
				<span class="inline-block w-3 h-3 rounded-full bg-red-500"></span>
				<span class="text-red-700 dark:text-red-400 font-semibold">Could not connect to {user?.cluster_host}</span>
			</div>
			<p class="text-sm text-surface-500 mt-2">Check that your cluster is reachable and your SSH key is still valid.</p>
			<button type="button" onclick={checkConnection} class="btn variant-outline-primary mt-4 px-4 py-2 text-sm">
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
			<h2 class="text-2xl font-bold mb-2 text-primary-500">CONFIG</h2>

			<!-- Important Note -->
			<div class="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4 mb-6">
				<div class="flex items-start gap-3">
					<span class="text-blue-600 dark:text-blue-400 text-xl font-bold">ℹ️</span>
					<div>
						<p class="text-sm text-blue-900 dark:text-blue-100 font-semibold mb-1">Database Configuration</p>
						<p class="text-sm text-blue-800 dark:text-blue-200">
							Make sure to set a <code class="font-mono bg-blue-100 dark:bg-blue-800 px-1 py-0.5 rounded">main_database</code> config key with the path to your database.
							If not set, the database defaults to <code class="font-mono bg-blue-100 dark:bg-blue-800 px-1 py-0.5 rounded">~/.local/share/bioinformatics-tools/my-db.db</code>
						</p>
					</div>
				</div>
			</div>

			<!-- Structured Configuration Forms -->
			<div class="space-y-4">
				{#each [...groupParamsBySection(workflows)].sort((a, b) => {
					// Sort: required sections first, then alphabetically
					const aRequired = a[1].some(p => p.required);
					const bRequired = b[1].some(p => p.required);
					if (aRequired && !bRequired) return -1;
					if (!aRequired && bRequired) return 1;
					return a[0].localeCompare(b[0]);
				}) as [sectionName, params]}
					{@const hasRequired = params.some(p => p.required)}
					{@const isCompute = sectionName === 'compute'}
					{@const sectionTitle = sectionName.charAt(0).toUpperCase() + sectionName.slice(1)}

					{#if isCompute}
						<!-- Special handling for compute.cluster-default -->
						<ConfigSection
							title="SLURM Configuration"
							description="Configure cluster execution settings"
							required={hasRequired}
							collapsible={false}
							defaultExpanded={true}
						>
							{#each params as param}
								{@const parts = param.param.split('.')}
								{@const value = getNestedValue(formValues, parts)}

								<ConfigField
									param={param.param}
									type={param.type}
									description={param.description}
									default={param.default}
									required={param.required || false}
									value={value}
									onchange={(newVal) => updateFormValue(param.param, newVal)}
								/>
							{/each}
						</ConfigSection>
					{:else}
						<!-- Tool-specific configuration sections -->
						<ConfigSection
							title={sectionTitle}
							description="Configure {sectionTitle} execution parameters"
							required={false}
							collapsible={true}
							defaultExpanded={false}
						>
							{#each params as param}
								{@const parts = param.param.split('.')}
								{@const value = getNestedValue(formValues, parts)}

								<ConfigField
									param={param.param}
									type={param.type}
									description={param.description}
									default={param.default}
									required={param.required || false}
									value={value}
									onchange={(newVal) => updateFormValue(param.param, newVal)}
								/>
							{/each}
						</ConfigSection>
					{/if}
				{/each}

				<!-- Special handling for main_database -->
				<div class="bg-amber-50 dark:bg-amber-900/20 border-2 border-amber-300 dark:border-amber-700 rounded-lg p-5">
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
							class="input w-full px-4 py-2 rounded bg-white dark:bg-amber-900/40 border-2 border-amber-300 dark:border-amber-600 font-mono text-sm"
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
							<h4 class="font-semibold text-primary-600 dark:text-primary-400">Hierarchical Config Pattern</h4>
							<p>
								Workflow rules follow a pattern where <code class="font-mono bg-surface-300 dark:bg-surface-600 px-1 py-0.5 rounded">run_&lt;tool&gt;</code>
								reads from config key <code class="font-mono bg-surface-300 dark:bg-surface-600 px-1 py-0.5 rounded">&lt;tool&gt;:</code>
							</p>
							<div class="bg-surface-100 dark:bg-surface-800 rounded p-3 font-mono text-xs">
								<pre># Example: rule run_prodigal reads from:
prodigal:
  threads: 1        # CPU threads
  mem_mb: 2048      # Memory in MB
  runtime: 30       # Runtime limit (minutes)</pre>
							</div>
						</div>

						<div class="bg-surface-200 dark:bg-surface-700 rounded-lg p-4 space-y-3">
							<h4 class="font-semibold text-primary-600 dark:text-primary-400">Customizing Tool Parameters</h4>
							<p>Each tool (prodigal, pfam, cog, dbcan, kofam) can be configured independently. Common parameters:</p>
							<ul class="list-disc list-inside space-y-1 ml-2">
								<li><code class="font-mono bg-surface-300 dark:bg-surface-600 px-1 py-0.5 rounded">threads</code> - Number of CPU threads</li>
								<li><code class="font-mono bg-surface-300 dark:bg-surface-600 px-1 py-0.5 rounded">mem_mb</code> - Memory limit in MB</li>
								<li><code class="font-mono bg-surface-300 dark:bg-surface-600 px-1 py-0.5 rounded">runtime</code> - Time limit in minutes</li>
								<li><code class="font-mono bg-surface-300 dark:bg-surface-600 px-1 py-0.5 rounded">db</code> - Database path (tool-specific)</li>
							</ul>
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
  cluster-default:
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
		<h2 class="text-2xl font-bold mb-2 text-primary-500">Cluster Credentials</h2>
		<p class="text-sm text-surface-500 mb-6">
			Update your HPC cluster connection details. Changes will be validated before saving.
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
