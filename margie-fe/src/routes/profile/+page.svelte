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
	let connDetail = $state('');
	let connAction = $state('');
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
			// The backend now says WHY it failed. Keep it, or the UI reduces a
			// precisely-diagnosed problem back to "could not connect" -- which is
			// what made an undecryptable stored key so hard to identify.
			connDetail = data.detail ?? '';
			connAction = data.action ?? '';
			if (connected) {
				connDetail = ''; connAction = '';
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
	let selectedToolCount = $derived(selectedToolKeys.size);
	let selectedWorkflowLabel = $derived(selectedWorkflowPathSettings?.label ?? 'Workflow');
	let globalMissingCount = $derived(missingRequiredFields.length);
	let slurmParams = $derived.by(() => {
		const params = workflows.flatMap(wf => wf.configurable_params || []).filter((param: any) => param.param.startsWith('compute.'));
		const unique = new Map<string, any>();
		for (const param of params) {
			if (!unique.has(param.param)) unique.set(param.param, param);
		}
		return [...unique.values()];
	});

	const CORE_WORKFLOW_PATH_KEYS = new Set(['sif_path', 'db_root', 'input_path', 'output_path']);
	const REQUIRED_SHARED_PATH_KEYS = new Set([
		'margie_sb.operon_database.occ_reference_pkl',
		'margie_sb.fingerprint_database.path',
		'margie_sb.genome_pool.path',
	]);
	const RECORD_KEEPING_SHARED_PATH_KEYS = new Set([
		'margie_sb.scoring_results_historical.path',
		'margie_sb.final_tables_depot.path',
		'margie_sb.sqlite_pipeline_snapshot.path',
	]);
	const REPORTING_SHARED_PATH_KEYS = new Set([
		'margie_sb.report_figures.operon_db',
	]);

	function isCoreWorkflowPath(paramKey: string): boolean {
		const leaf = paramKey.split('.').pop() || '';
		return CORE_WORKFLOW_PATH_KEYS.has(leaf);
	}

	function pathParamPriority(paramKey: string): number {
		const leaf = paramKey.split('.').pop() || '';
		const order = ['sif_path', 'db_root', 'input_path', 'output_path'];
		const idx = order.indexOf(leaf);
		return idx >= 0 ? idx : 100;
	}

	function prettyPathLabel(paramKey: string): string {
		const humanize = (value: string): string =>
			value
				.replace(/_/g, ' ')
				.replace(/\b\w/g, ch => ch.toUpperCase());

		const fullKeyLabels: Record<string, string> = {
			'margie_sb.fingerprint_database.path': 'Fingerprint Database TSV',
			'margie_sb.genome_pool.path': 'Genome Pool Root',
			'margie_sb.final_tables_depot.path': 'Final Tables Export Root',
			'margie_sb.scoring_results_historical.path': 'Historical Scoring Archive Root',
			'margie_sb.sqlite_pipeline_snapshot.path': 'SQLite Snapshot Queue Root',
		};
		if (fullKeyLabels[paramKey]) return fullKeyLabels[paramKey];

		const parts = paramKey.split('.');
		const leaf = paramKey.split('.').pop() || paramKey;
		const labels: Record<string, string> = {
			sif_path: 'Container Root (SIF)',
			db_root: 'Database Root',
			input_path: 'Default Input Path',
			output_path: 'Default Output Path',
			operon_db: 'Report Figures Operon DB',
			occ_reference_pkl: 'OCC Reference Database',
		};
		if (labels[leaf]) return labels[leaf];
		if (leaf === 'path' && parts.length >= 2) return `${humanize(parts[parts.length - 2])} Path`;
		return humanize(leaf);
	}

	function handleWorkflowPathInput(paramKey: string, event: Event) {
		const target = event.currentTarget as HTMLInputElement;
		updateFormValue(paramKey, target.value);
	}

	function isRequiredSharedPath(paramKey: string): boolean {
		return REQUIRED_SHARED_PATH_KEYS.has(paramKey);
	}

	function isRecordKeepingSharedPath(paramKey: string): boolean {
		return RECORD_KEEPING_SHARED_PATH_KEYS.has(paramKey);
	}

	function isReportingSharedPath(paramKey: string): boolean {
		return REPORTING_SHARED_PATH_KEYS.has(paramKey);
	}

	let selectedWorkflowPathParamsOrdered = $derived.by(() => {
		const params = [...(selectedWorkflowPathSettings?.params ?? [])];
		return params.sort((a: any, b: any) => {
			const pa = pathParamPriority(a.param);
			const pb = pathParamPriority(b.param);
			if (pa !== pb) return pa - pb;
			return a.param.localeCompare(b.param);
		});
	});

	let selectedWorkflowCorePathParams = $derived.by(() =>
		selectedWorkflowPathParamsOrdered.filter((param: any) => isCoreWorkflowPath(param.param))
	);

	let selectedWorkflowSharedPathParams = $derived.by(() =>
		selectedWorkflowPathParamsOrdered.filter((param: any) => !isCoreWorkflowPath(param.param))
	);

	let selectedWorkflowRequiredPathParams = $derived.by(() =>
		selectedWorkflowPathParamsOrdered.filter((param: any) =>
			isCoreWorkflowPath(param.param) || isRequiredSharedPath(param.param)
		)
	);

	let selectedWorkflowRecordKeepingPathParams = $derived.by(() =>
		selectedWorkflowSharedPathParams.filter((param: any) => isRecordKeepingSharedPath(param.param))
	);

	let selectedWorkflowReportingPathParams = $derived.by(() =>
		selectedWorkflowSharedPathParams.filter((param: any) => isReportingSharedPath(param.param))
	);

	let selectedWorkflowOtherOptionalPathParams = $derived.by(() =>
		selectedWorkflowSharedPathParams.filter((param: any) =>
			!isRequiredSharedPath(param.param)
			&& !isRecordKeepingSharedPath(param.param)
			&& !isReportingSharedPath(param.param)
		)
	);

	// Build config to save as a canonical, workflow-segregated payload.
	// This intentionally does not preserve legacy top-level workflow keys;
	// save writes the structure shown by the current UI model.
	function buildConfigToSave(): Record<string, any> {
		const workflowSections: Record<string, any> = {};
		const computeSection: Record<string, any> = {};

		// Keep this stable for deterministic YAML order and easier diffs.
		const workflowOrder = workflows.map(wf => wf.id);

		// Write workflow params under each workflow section. If a param is already
		// namespaced (e.g. margie_sb.sif_path), keep that shape; otherwise scope it
		// to its workflow (e.g. prodigal.threads -> margie.prodigal.threads).
		for (const workflow of workflows) {
			const wfId = workflow.id;
			const wfParams = workflow.configurable_params || [];

			for (const param of wfParams) {
				if (!param?.param) continue;

				const parts = param.param.split('.');
				const scopedParts = parts[0] === wfId ? parts : [wfId, ...parts];
				// Read either legacy top-level values (prodigal.threads) or the
				// canonical workflow-scoped values (margie.prodigal.threads).
				const value = getNestedValue(formValues, parts) ?? getNestedValue(formValues, scopedParts);
				const finalValue = (value !== null && value !== undefined && value !== '')
					? value
					: param.default;

				if (finalValue === null || finalValue === undefined) continue;

				if (param.param.startsWith('compute.')) {
					setNestedValue(computeSection, parts.slice(1), finalValue);
					continue;
				}

				if (!workflowSections[wfId]) workflowSections[wfId] = {};
				setNestedValue(workflowSections[wfId], scopedParts.slice(1), finalValue);
			}
		}

		// Always include main_database - use value or default.
		const mainDb = formValues.main_database?.trim();
		const configToSave: Record<string, any> = {
			main_database: mainDb || '~/.local/share/bioinformatics-tools/my-db.db',
			compute: computeSection,
		};

		if (selectedWorkflowPathId) {
			if (!workflowSections[selectedWorkflowPathId]) workflowSections[selectedWorkflowPathId] = {};
			workflowSections[selectedWorkflowPathId].default_selected_tools = Array.from(selectedToolKeys).join(',');
			// Persisted opt-in: the backend reads this server-side at run time
			// (does not depend on the Analyze-page payload), gating the full
			// per-genome operon atlas.
			workflowSections[selectedWorkflowPathId].run_full_operon_map = generateFullOperonMap;
		}

		// When db_root is edited in Workflow Specific Settings, keep per-tool db
		// paths in sync so the saved YAML reflects the user's chosen root.
		const margieSbSection = workflowSections.margie_sb;
		if (margieSbSection && typeof margieSbSection.db_root === 'string') {
			const rawDbRoot = margieSbSection.db_root.trim();
			if (rawDbRoot) {
				const dbRoot = rawDbRoot.replace(/\/+$/, '');
				const margieSbWorkflow = workflows.find(wf => wf.id === 'margie_sb');
				const dbToolKeys = new Set<string>();
				for (const param of (margieSbWorkflow?.configurable_params || [])) {
					const key = String(param?.param || '');
					const match = key.match(/^margie_sb\.([a-z0-9_]+)\.db$/i);
					if (match?.[1]) dbToolKeys.add(match[1]);
				}

				for (const key of dbToolKeys) {
					if (!margieSbSection[key] || typeof margieSbSection[key] !== 'object') {
						margieSbSection[key] = {};
					}
					margieSbSection[key].db = `${dbRoot}/${key}`;
				}
			}
		}

		// Backward-compat migration for older configs that persisted GTDB-Tk with
		// stale low-resource defaults despite workflow-scoped settings.
		if (margieSbSection) {
			if (!margieSbSection.gtdbtk || typeof margieSbSection.gtdbtk !== 'object') {
				margieSbSection.gtdbtk = {};
			}
			if (!margieSbSection.phase2 || typeof margieSbSection.phase2 !== 'object') {
				margieSbSection.phase2 = {};
			}

			const g = margieSbSection.gtdbtk;
			const phase2 = margieSbSection.phase2;
			if (!g.partition || String(g.partition).trim().toLowerCase() === 'cpu') {
				g.partition = 'highmem';
			}
			if (!phase2.partition || String(phase2.partition).trim().toLowerCase() === 'cpu') {
				phase2.partition = 'highmem';
			}
			if (!g.threads || Number(g.threads) <= 8) {
				g.threads = 64;
			}
			if (!g.mem_mb || Number(g.mem_mb) <= 4000) {
				g.mem_mb = 460000;
			}
			if (!g.runtime || Number(g.runtime) <= 120) {
				g.runtime = 240;
			}
		}

		for (const wfId of workflowOrder) {
			if (workflowSections[wfId]) {
				configToSave[wfId] = workflowSections[wfId];
			}
		}

		return configToSave;
	}

	function updateFormValue(param: string, value: any) {
		const parts = param.split('.');
		setNestedValue(formValues, parts, value);
		formValues = { ...formValues }; // Trigger reactivity
	}

	$effect(() => {
		const preferredWorkflowId = workflowPathSettings.find(entry => entry.id === 'margie_sb')?.id
			?? workflowPathSettings[0]?.id
			?? '';
		if (preferredWorkflowId && !workflowPathSettings.some(entry => entry.id === selectedWorkflowPathId)) {
			selectedWorkflowPathId = preferredWorkflowId;
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

<div class="w-full px-4 md:px-6 py-8 space-y-6">
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
	<section class="card p-4 bg-surface-100 dark:bg-surface-800 border border-surface-300/70 dark:border-surface-700 shadow-sm w-full max-w-2xl">
		<div class="mb-2 flex items-center justify-between gap-2 flex-wrap">
			<h2 class="text-2xl font-bold text-primary-500">SSH Connection</h2>
			<div class="text-[11px] px-2 py-1 rounded-full border border-surface-300 dark:border-surface-600 bg-surface-200 dark:bg-surface-700 text-surface-700 dark:text-surface-300">
				{checking ? 'Checking' : connected ? 'Connected' : 'Disconnected'}
			</div>
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
			{#if connDetail}
				<p class="mt-2 text-sm text-red-700 dark:text-red-400">{connDetail}</p>
			{/if}
			{#if connAction === 're-register'}
				<!-- Fernet is authenticated encryption: without the original key the
				     stored credential is unrecoverable, so re-registering really is
				     the only way forward. Say so, and link there. -->
				<a href="/register" class="btn variant-filled-primary btn-sm mt-3 inline-block">Register a new account</a>
			{:else}
				<div class="mt-2 text-sm text-surface-500 leading-snug">
					Update cluster host, username, or SSH key under Cluster Credentials, then retry.
				</div>
			{/if}
			<button type="button" onclick={checkConnection} class="btn variant-outline-primary mt-3 px-4 py-2 text-sm">
				Retry
			</button>
		{/if}
	</section>

	<!-- Required Fields Warning -->
	{#if connected && Object.keys(config).length > 0 && missingRequiredFields.length > 0}
		<section class="card p-4 bg-red-50 dark:bg-red-900/20 border-2 border-red-500">
			<div class="flex items-start gap-3">
				<span class="text-red-600 dark:text-red-400 text-sm font-semibold uppercase tracking-wide">Warning</span>
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
		<section class="card p-4 bg-surface-100 dark:bg-surface-800 border border-surface-300/70 dark:border-surface-700 shadow-sm text-center">
			<p class="text-surface-500">Loading configuration...</p>
		</section>
	{:else if connected && Object.keys(config).length > 0}
		<section class="card p-4 bg-surface-100 dark:bg-surface-800 border border-surface-300/70 dark:border-surface-700 shadow-sm">
			<details class="group">
				<summary class="card p-4 bg-surface-100 dark:bg-surface-800 cursor-pointer list-none">
					<div class="flex items-center justify-between">
						<div>
							<h2 class="text-2xl font-semibold">Global Config</h2>
							<p class="text-xs text-surface-500 dark:text-surface-400 mt-1">
								Cluster-wide database and SLURM defaults used by all workflows.
							</p>
						</div>
						<div class="flex flex-col items-end gap-1">
							{#if globalMissingCount > 0}
								<div class="text-[11px] px-2 py-1 rounded-full border border-red-300/60 dark:border-red-700 bg-red-100/70 dark:bg-red-900/25 text-red-800 dark:text-red-200">
									{globalMissingCount} required missing
								</div>
							{/if}
							<span class="text-xs text-surface-500 group-open:hidden">Expand</span>
							<span class="text-xs text-surface-500 hidden group-open:inline">Collapse</span>
						</div>
					</div>
				</summary>
				<div class="mt-2 card p-4 bg-surface-100 dark:bg-surface-800">
					<p class="text-sm text-surface-500 dark:text-surface-400 mb-4">
						This section stores the global database and SLURM settings used by the backend.
						Workflow-specific roots and tool defaults live below in Workflow Specific Settings.
					</p>

					<!-- Important Note -->
					<div class="bg-surface-100 dark:bg-surface-800 border border-surface-300/70 dark:border-surface-700 rounded-lg p-4 mb-6 shadow-sm">
						<div class="flex items-start gap-3">
							<span class="text-primary-500 text-sm font-semibold uppercase tracking-wide">Info</span>
							<div>
								<p class="text-sm text-surface-900 dark:text-surface-100 font-semibold mb-1">Database Configuration</p>
								<p class="text-xs text-surface-600 dark:text-surface-400">
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
						<span class="text-amber-600 dark:text-amber-400 text-sm font-semibold uppercase tracking-wide">Warning</span>
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
									<div class="text-sm text-green-700 dark:text-green-300 font-semibold">Path is writable</div>
								{:else}
									<div class="text-sm text-red-700 dark:text-red-300 font-semibold">Path is not writable</div>
							{/if}
							{/if}
						</div>
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
						Configuration Guide
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
								<strong>Tip:</strong> You only need to specify parameters you want to override.
								Unspecified values use sensible defaults defined in each workflow rule.
							</p>
						</div>
							</div>
						</details>
					</div>
				</div>
			</details>
		</section>

		{#if workflowPathSettings.length > 0}
			<section class="card p-4 bg-surface-100 dark:bg-surface-800 mt-6 border border-surface-300/70 dark:border-surface-700 shadow-sm">
				<details class="group">
					<summary class="card p-4 bg-surface-100 dark:bg-surface-800 cursor-pointer list-none">
						<div class="flex items-center justify-between">
							<div>
								<div class="flex flex-wrap items-center gap-2">
									<h2 class="text-2xl font-semibold text-surface-900 dark:text-surface-100">Workflow Specific Config</h2>
									<div class="text-[11px] px-2 py-1 rounded-full border border-amber-300/60 dark:border-amber-700 bg-amber-100/70 dark:bg-amber-900/25 text-amber-800 dark:text-amber-200">{selectedWorkflowLabel}</div>
									<div class="text-[11px] px-2 py-1 rounded-full border border-surface-300 dark:border-surface-600 bg-surface-200 dark:bg-surface-700 text-surface-700 dark:text-surface-300">{selectedToolCount} tools selected</div>
								</div>
								<p class="text-xs text-surface-500 dark:text-surface-400 mt-1">
									Per-workflow container, database, input, and output defaults used by Analyze.
								</p>
							</div>
							<div class="text-xs text-surface-500">
								<span class="group-open:hidden">Expand</span>
								<span class="hidden group-open:inline">Collapse</span>
							</div>
						</div>
					</summary>

					<div class="card p-4 bg-surface-100 dark:bg-surface-800 mt-2 space-y-3">
						<p class="text-sm text-surface-700 dark:text-surface-300">
							Edit per-workflow roots and defaults in one place. This section is the source of truth for Analyze defaults.
						</p>
						<p class="text-xs text-surface-600 dark:text-surface-400">
							Workflow defaults and paths for <span class="font-semibold">{selectedWorkflowLabel}</span> are shown below.
						</p>
						<div class="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
							<div>
								<h3 class="text-lg font-semibold text-surface-900 dark:text-surface-100">
									{selectedWorkflowPathSettings?.label}
								</h3>
								<p class="mt-1 text-xs text-surface-600 dark:text-surface-400">SIF/database roots and default input/output paths for this workflow.</p>
							</div>
							<div class="min-w-[16rem]">
								<label class="block text-xs font-semibold uppercase tracking-wide text-surface-600 dark:text-surface-400 mb-2" for="workflow-path-picker">
									Workflow
								</label>
								<select
									id="workflow-path-picker"
									bind:value={selectedWorkflowPathId}
									class="input w-full rounded-lg bg-surface-100 dark:bg-surface-800 border border-surface-300 dark:border-surface-600 px-4 py-2 text-surface-900 dark:text-surface-100"
								>
									{#each workflowPathSettings as wfSettings}
										<option value={wfSettings.id}>{wfSettings.label}</option>
									{/each}
								</select>
							</div>
						</div>

						{#if selectedWorkflowPathSettings}
							<div class="space-y-5">
								<div class="rounded-xl border border-surface-300/70 dark:border-surface-700 bg-surface-100 dark:bg-surface-800 p-3">
									<h4 class="text-sm font-semibold uppercase tracking-wide text-surface-900 dark:text-surface-100">Required for Run</h4>
									<p class="mt-1 text-xs text-surface-600 dark:text-surface-400">Set these first. These are the core workflow roots plus required shared stores needed for normal execution.</p>
									<div class="mt-2">
										{#each selectedWorkflowRequiredPathParams as param}
											{@const parts = param.param.split('.')}
											{@const value = getNestedValue(formValues, parts)}
											<ConfigField
												param={param.param}
												label={prettyPathLabel(param.param)}
												type={param.type}
												description={param.description}
												default={param.default}
												required={true}
												compact={true}
												value={value}
												onchange={(newVal) => updateFormValue(param.param, newVal)}
											/>
										{/each}
									</div>
								</div>

								{#if selectedWorkflowRecordKeepingPathParams.length > 0}
									<details class="group rounded-xl border border-surface-300/70 dark:border-surface-700 bg-surface-100 dark:bg-surface-800 p-3">
										<summary class="cursor-pointer list-none">
											<div class="flex items-center justify-between">
												<span class="text-sm font-semibold uppercase tracking-wide text-surface-900 dark:text-surface-100">Optional Record-Keeping Paths</span>
												<span class="text-xs text-surface-500 group-open:hidden">Expand</span>
												<span class="text-xs text-surface-500 hidden group-open:inline">Collapse</span>
											</div>
										</summary>
										<p class="mt-2 text-xs text-surface-600 dark:text-surface-400">Archives and historical exports. Helpful for tracking and reproducibility, but not required for core execution.</p>
										<div class="mt-2">
											{#each selectedWorkflowRecordKeepingPathParams as param}
												{@const parts = param.param.split('.')}
												{@const value = getNestedValue(formValues, parts)}
												<ConfigField
													param={param.param}
													label={prettyPathLabel(param.param)}
													type={param.type}
													description={param.description}
													default={param.default}
													required={false}
													compact={true}
													value={value}
													onchange={(newVal) => updateFormValue(param.param, newVal)}
												/>
											{/each}
										</div>
									</details>
								{/if}

								{#if selectedWorkflowReportingPathParams.length > 0 || selectedWorkflowOtherOptionalPathParams.length > 0}
									<details class="group rounded-xl border border-surface-300/70 dark:border-surface-700 bg-surface-100 dark:bg-surface-800 p-3">
										<summary class="cursor-pointer list-none">
											<div class="flex items-center justify-between">
												<span class="text-sm font-semibold uppercase tracking-wide text-surface-900 dark:text-surface-100">Optional Reporting / Advanced Paths</span>
												<span class="text-xs text-surface-500 group-open:hidden">Expand</span>
												<span class="text-xs text-surface-500 hidden group-open:inline">Collapse</span>
											</div>
										</summary>
										<p class="mt-2 text-xs text-surface-600 dark:text-surface-400">Used by report/figure extras or advanced custom workflows. Keep defaults unless you have a specific reason to change.</p>
										<div class="mt-2">
											{#each [...selectedWorkflowReportingPathParams, ...selectedWorkflowOtherOptionalPathParams] as param}
												{@const parts = param.param.split('.')}
												{@const value = getNestedValue(formValues, parts)}
												<ConfigField
													param={param.param}
													label={prettyPathLabel(param.param)}
													type={param.type}
													description={param.description}
													default={param.default}
													required={false}
													compact={true}
													value={value}
													onchange={(newVal) => updateFormValue(param.param, newVal)}
												/>
											{/each}
										</div>
									</details>
								{/if}
							</div>
						{/if}

						{#if selectableTools.length > 0}
							<div class="rounded-xl border border-surface-300/70 dark:border-surface-700 bg-surface-100 dark:bg-surface-800 p-3 space-y-3">
								<div class="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
									<div>
										<h4 class="text-lg font-semibold text-surface-900 dark:text-surface-100">Tool Defaults</h4>
										<p class="text-xs text-surface-600 dark:text-surface-400 mt-1">
											Pick the tools you want selected by default for this workflow on Analyze.
											Required tools stay enabled, but the rest can be saved as your preferred starting point.
										</p>
									</div>
									<div class="flex flex-wrap gap-2">
										<button type="button" onclick={selectAllWorkflowTools} class="text-xs px-3 py-1 rounded border border-surface-300 dark:border-surface-600 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700">Select all</button>
										<button type="button" onclick={selectNoWorkflowTools} class="text-xs px-3 py-1 rounded border border-surface-300 dark:border-surface-600 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700">Select none</button>
									</div>
								</div>
								<div class="grid gap-2 md:grid-cols-2 xl:grid-cols-3">
									{#each selectableTools as tool}
										{@const isRequired = requiredToolKeys.includes(tool.key)}
										{@const isDisabled = disabledTools.has(tool.key)}
										<label class="flex items-start gap-2.5 rounded-lg border border-surface-300 dark:border-surface-600 px-2.5 py-1.5 bg-surface-100 dark:bg-surface-800 {isRequired ? 'opacity-90' : isDisabled ? 'opacity-60 cursor-not-allowed' : 'cursor-pointer hover:bg-surface-200 dark:hover:bg-surface-700'}">
											<input
												type="checkbox"
												checked={selectedToolKeys.has(tool.key) && !isDisabled}
												disabled={isRequired || isDisabled}
												onchange={() => toggleWorkflowTool(tool.key)}
												class="mt-1 accent-primary-500"
											/>
											<div class="min-w-0">
												<div class="flex items-center gap-2">
													<span class="text-sm font-semibold text-surface-900 dark:text-surface-100">{tool.name}</span>
													{#if isRequired}
														<span class="text-[10px] uppercase tracking-wide rounded-full bg-surface-200 text-surface-700 dark:bg-surface-800 dark:text-surface-300 px-2 py-0.5">Required</span>
													{/if}
													{#if isDisabled}
														<span class="text-[10px] uppercase tracking-wide rounded-full bg-surface-200 text-surface-700 dark:bg-surface-800 dark:text-surface-300 px-2 py-0.5">License required</span>
													{/if}
												</div>
												<p class="mt-1 text-xs text-surface-600 dark:text-surface-400 leading-snug">{tool.purpose}</p>
											</div>
										</label>
									{/each}
								</div>
							</div>
						{/if}

						{#if selectedWorkflowPathId === 'margie_sb'}
							<div class="rounded-xl border border-surface-300/70 dark:border-surface-700 bg-surface-100 dark:bg-surface-800 p-4">
								<label class="flex items-start gap-3 cursor-pointer">
									<input type="checkbox" bind:checked={generateFullOperonMap} class="mt-1 accent-primary-500" />
									<div class="min-w-0">
										<h4 class="text-lg font-semibold text-surface-900 dark:text-surface-100">Full-genome operon map</h4>
										<p class="mt-1 text-xs text-surface-600 dark:text-surface-400 leading-snug">
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
		<section class="card p-4 bg-surface-100 dark:bg-surface-800 border border-surface-300/70 dark:border-surface-700 shadow-sm text-center space-y-4">
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
					{creatingConfig ? 'Creating...' : 'Create Default Configuration'}
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
	<section class="card p-4 bg-surface-100 dark:bg-surface-800 border border-surface-300/70 dark:border-surface-700 shadow-sm">
		<details class="group">
			<summary class="card p-4 bg-surface-100 dark:bg-surface-800 cursor-pointer list-none">
				<div class="flex items-center justify-between">
					<div>
						<div class="flex items-center gap-2">
							<h2 class="text-2xl font-semibold text-surface-900 dark:text-surface-100">Cluster Credentials</h2>
							{#if user?.cluster_host}
								<div class="text-[11px] px-2 py-1 rounded-full border border-surface-300 dark:border-surface-600 bg-surface-200 dark:bg-surface-700 text-surface-700 dark:text-surface-300">{user.cluster_host}</div>
							{/if}
						</div>
						<p class="text-xs text-surface-500 dark:text-surface-400 mt-1">
							Host, username, and private key used for SSH access.
						</p>
					</div>
					<div class="text-xs text-surface-500">
						<span class="group-open:hidden">Expand</span>
						<span class="hidden group-open:inline">Collapse</span>
					</div>
				</div>
			</summary>
			<div class="mt-2 card p-4 bg-surface-100 dark:bg-surface-800">
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
		</div>
		</details>
	</section>
</div>

