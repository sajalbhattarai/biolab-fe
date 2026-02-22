<script lang="ts">
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';

	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000'
		: '';

	function handle401() { clearToken(); goto('/login'); }

	let scriptContent = $state('');
	let loading = $state(false);
	let error = $state('');
	let result = $state<{ job_id: string; message: string } | null>(null);

	async function handleSubmit(e: Event) {
		e.preventDefault();
		if (!scriptContent.trim()) {
			error = 'Please enter script content';
			return;
		}

		try {
			loading = true;
			error = '';
			result = null;

			const response = await fetch(`${API_URL}/v1/ssh/run_ssh`, {
				method: 'POST',
				headers: authHeaders(),
				body: JSON.stringify({ script: scriptContent }),
			});

			if (response.status === 401) { handle401(); return; }
			if (!response.ok) throw new Error('Failed to submit job');

			const data = await response.json();
			const jobId = data.job_id;

			scriptContent = '';

		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to submit SLURM job';
			console.error('Error submitting job:', e);
		} finally {
			loading = false;
		}
	}
</script>

<div class="container mx-auto p-8 max-w-2xl">
	<h1 class="text-4xl font-bold mb-8 text-center text-secondary-500">Run SSH</h1>

	<div class="bg-surface-200 dark:bg-surface-700 border-l-4 border-secondary-500 p-4 rounded mb-6">
		<p class="text-sm text-surface-600 dark:text-surface-300">
			This will run your script via SSH tunneling onto your remote server on the login node.
		</p>
	</div>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
			{error}
		</div>
	{/if}

	{#if result}
		<div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-4">
			<p class="font-semibold">{result.message}</p>
			<p class="text-sm mt-1">Job ID: <span class="font-mono">{result.job_id}</span></p>
		</div>
	{/if}

	<div class="card p-6 bg-surface-100 dark:bg-surface-800">
		<form on:submit={handleSubmit} class="space-y-4">
			<div>
				<label for="script" class="block text-sm font-semibold mb-2">
					Script Content
				</label>
				<textarea
					id="script"
					bind:value={scriptContent}
					placeholder="Enter your script content here..."
					rows="10"
					required
					disabled={loading}
					class="w-full px-4 py-2 rounded border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 font-mono text-sm"
				></textarea>
			</div>

			<button
				type="submit"
				disabled={loading || !scriptContent.trim()}
				class="btn variant-filled-primary w-full py-3"
			>
				{loading ? 'Submitting...' : 'Submit Job'}
			</button>
		</form>
	</div>

	<!-- Output Box -->
	<div class="mt-6">
		<h2 class="text-lg font-semibold mb-2">Output</h2>
		<div class="rounded bg-black p-4 min-h-[200px] font-mono text-sm">
			<p class="text-green-500 opacity-60">Not wired up yet</p>
		</div>
	</div>
</div>
