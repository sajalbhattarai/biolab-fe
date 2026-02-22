<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';

	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000'
		: '';

	function handle401() { clearToken(); goto('/login'); }

	let genomePath = $state('');
	let outputDir = $state('');
	let homeDir = $state('');
	let selectedWorkflow = $state('margie');
	let availableWorkflows = $state<{id: string, label: string, description: string}[]>([]);
	let loading = $state(false);
	let quickLoading = $state(false);
	let freshLoading = $state(false);
	let error = $state('');

	// Live preview of the full output path (timestamp is illustrative — generated server-side)
	let outputPreview = $derived(
		`${(outputDir.trim() || homeDir || '~').replace(/\/$/, '')}/YYYY-MM-DD-HHMM`
	);

	onMount(async () => {
		// Fetch home_dir for the placeholder
		try {
			const res = await fetch(`${API_URL}/v1/auth/me`, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (res.ok) homeDir = (await res.json()).home_dir;
		} catch {}

		// Populate output_dir default from remote config if the user has set one
		try {
			const res = await fetch(`${API_URL}/v1/ssh/config`, { headers: authHeaders() });
			if (res.ok) {
				const config = await res.json();
				if (config?.base_output_dir) outputDir = config.base_output_dir;
			}
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

	async function runWorkflow(endpoint: string, setLoading: (v: boolean) => void) {
		try {
			setLoading(true);
			error = '';
			const response = await fetch(`${API_URL}/v1/workflows/${endpoint}`, {
				method: 'POST',
				headers: authHeaders(),
			});
			if (response.status === 401) { handle401(); return; }
			if (!response.ok) throw new Error(`Failed to run ${endpoint}`);
			const data = await response.json();
			console.log(`${endpoint} result:`, data);

			if (data.job_id) {
				goto(`/jobs/${data.job_id}`);
			}
		} catch (e) {
			error = e instanceof Error ? e.message : `Failed to run ${endpoint}`;
		} finally {
			setLoading(false);
		}
	}

	async function handleAnalyze() {
		if (!genomePath.trim()) {
			error = 'Please provide a genome file';
			return;
		}

		try {
			loading = true;
			error = '';

			const response = await fetch(`${API_URL}/v1/ssh/run_workflow`, {
				method: 'POST',
				headers: authHeaders(),
				body: JSON.stringify({
					genome_path: genomePath,
					output_dir: outputDir,
					workflow: selectedWorkflow,
				}),
			});

			if (response.status === 401) { handle401(); return; }
			if (!response.ok) throw new Error('Failed to start analysis');

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

<div class="container mx-auto p-8 max-w-4xl">
	<h1 class="text-4xl font-bold mb-8 text-center text-primary-500">Genome Analysis</h1>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
			{error}
		</div>
	{/if}

	<!-- Workflow Selection -->
	{#if availableWorkflows.length > 0}
	<div class="card p-6 bg-surface-100 dark:bg-surface-800 mb-8">
		<h2 class="text-2xl font-semibold mb-4">Workflow</h2>
		<div class="flex flex-wrap gap-3">
			{#each availableWorkflows as wf}
				<button
					type="button"
					onclick={() => selectedWorkflow = wf.id}
					class="flex flex-col items-start px-5 py-3 rounded-lg border-2 text-left transition-colors
						{selectedWorkflow === wf.id
							? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20 text-primary-700 dark:text-primary-300'
							: 'border-surface-300 dark:border-surface-600 hover:border-surface-400 dark:hover:border-surface-500'}"
				>
					<span class="font-semibold">{wf.label}</span>
					<span class="text-xs text-surface-500 dark:text-surface-400 mt-0.5">{wf.description}</span>
				</button>
			{/each}
		</div>
	</div>
	{/if}

	<!-- Genome Path -->
	<div class="card p-6 bg-surface-100 dark:bg-surface-800 mb-8">
		<h2 class="text-2xl font-semibold mb-4">Genome Path</h2>
		<input
			type="text"
			bind:value={genomePath}
			placeholder="Enter genome file path..."
			class="w-full px-4 py-2 rounded border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900"
		/>
	</div>

	<!-- Output Directory -->
	<div class="card p-6 bg-surface-100 dark:bg-surface-800 mb-8">
		<h2 class="text-2xl font-semibold mb-4">Output Directory</h2>
		<input
			type="text"
			bind:value={outputDir}
			placeholder={homeDir || 'Loading...'}
			class="w-full px-4 py-2 rounded border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900"
		/>
		<p class="text-sm text-surface-500 mt-2">
			A timestamp is appended automatically. Results will go to:
			<code class="font-mono text-xs bg-surface-200 dark:bg-surface-700 px-1 py-0.5 rounded ml-1">{outputPreview}</code>
		</p>
		<p class="text-xs text-surface-400 mt-1">
			Leave blank to use your home directory. Set <code class="font-mono">base_output_dir</code> in your config to save this as a default.
		</p>
	</div>

	<!-- Analyze Button -->
	<div class="card p-6 bg-surface-100 dark:bg-surface-800">
		<button
			type="button"
			onclick={handleAnalyze}
			disabled={loading}
			class="btn variant-filled-primary px-8 py-2"
		>
			{loading ? 'Starting Analysis...' : 'Analyze'}
		</button>
	</div>

	<!-- Quick Workflows -->
	<div class="card p-6 bg-surface-100 dark:bg-surface-800 mt-8">
		<h2 class="text-2xl font-semibold mb-4">Quick Workflows</h2>
		<p class="text-sm text-surface-500 mb-4">Touch-only workflows on Negishi — tests SSH, snakemake, and DB cache pipeline (no containers).</p>
		<div class="flex gap-4">
			<button
				type="button"
				onclick={() => runWorkflow('run_quick_example', (v) => quickLoading = v)}
				disabled={quickLoading}
				class="btn px-6 py-2 text-white bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50"
			>
				{quickLoading ? 'Running...' : 'Quick Example'}
			</button>
			<button
				type="button"
				onclick={() => runWorkflow('run_fresh_test', (v) => freshLoading = v)}
				disabled={freshLoading}
				class="btn px-6 py-2 text-white bg-amber-600 hover:bg-amber-700 disabled:opacity-50"
			>
				{freshLoading ? 'Running...' : 'Fresh Test'}
			</button>
		</div>
	</div>
</div>
