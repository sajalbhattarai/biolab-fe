<script lang="ts">
	import { goto } from '$app/navigation';

	// Use relative URL so it works in both dev and production
	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000' // Dev: connect to local backend
		: ''; // Production: use relative URL (same domain)

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

			const response = await fetch(`${API_URL}/v1/ssh/run_slurm`, {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json',
				},
				body: JSON.stringify({ script: scriptContent }),
			});

			if (!response.ok) throw new Error('Failed to submit job');

			const data = await response.json();
			const jobId = data.job_id;

			// Clear the input after successful submission
			scriptContent = '';

			// Redirect to the analyze page with the job ID
			goto(`/analyze/${jobId}`);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to submit SLURM job';
			console.error('Error submitting job:', e);
		} finally {
			loading = false;
		}
	}
</script>

<div class="w-full px-4 md:px-6 py-8 max-w-none">
	<div class="mb-8 text-center">
		<h1 class="text-4xl font-bold text-primary-500">Run SLURM</h1>
		<p class="text-sm text-surface-500 dark:text-surface-400 mt-2 max-w-2xl mx-auto">
			Paste a SLURM script here and submit it to the remote cluster as a batch job.
			The page sends the script as-is, similar to running a direct <code class="font-mono text-xs">sbatch</code> command on the cluster.
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
		<form onsubmit={handleSubmit} class="space-y-4">
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
</div>
