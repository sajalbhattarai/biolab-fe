<script lang="ts">
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';

	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000'
		: '';

	function handle401() { clearToken(); goto('/login'); }

	let entries = $state<string[]>([]);
	let searchPath = $state('/depot/lindems/data/');
	let loading = false;
	let error = '';

	async function fetchFiles(e: Event) {
		e.preventDefault();
		if (!searchPath.trim()) return;

		try {
			loading = true;
			error = '';
			const response = await fetch(
				`${API_URL}/v1/ssh/all_genomes?path=${encodeURIComponent(searchPath)}`,
				{ headers: authHeaders() }
			);
			if (response.status === 401) { handle401(); return; }
			if (!response.ok) throw new Error('Failed to fetch files');
			const data = await response.json();
			entries = data.Genomes;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load files';
			console.error('Error fetching files:', e);
		} finally {
			loading = false;
		}
	}
</script>

<div class="container mx-auto p-8 max-w-2xl">
	<h1 class="text-4xl font-bold mb-8 text-center text-primary-500">Hi Dane</h1>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
			{error}
		</div>
	{/if}

	<div class="card p-6 bg-surface-100 dark:bg-surface-800 mb-8">
		<form on:submit={fetchFiles} class="flex gap-4">
			<input
				type="text"
				bind:value={searchPath}
				placeholder="Enter a path..."
				required
				disabled={loading}
				class="flex-1 px-4 py-2 rounded border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900"
			/>
			<button
				type="submit"
				disabled={loading || !searchPath.trim()}
				class="btn variant-filled-primary px-6"
			>
				{loading ? 'Loading...' : 'Fetch Files'}
			</button>
		</form>
	</div>

	<div class="card p-6 bg-surface-100 dark:bg-surface-800">
      <h2 class="text-2xl font-semibold mb-4">Genome Files</h2>

      {#if loading && entries.length === 0}
          <p class="text-surface-600 dark:text-surface-400">Loading...</p>
      {:else if entries.length === 0}
          <p class="text-surface-600 dark:text-surface-400">No files found</p>
      {:else}
          <ul class="space-y-2">
              {#each entries as genome}
                  <li class="p-3 bg-surface-200 dark:bg-surface-700 rounded font-mono text-sm">
                      {genome}
                  </li>
              {/each}
          </ul>
      {/if}
  </div>
</div>
