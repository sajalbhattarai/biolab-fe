<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';

	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000'
		: '';

	function handle401() { clearToken(); goto('/login'); }

	interface Entry { name: string; type: 'file' | 'directory'; size: number; }

	// Start in the user's own home directory; the backend expands "~".
	// Depot/other shared paths remain reachable by typing or navigating to
	// them, but only work if the user's cluster account has permission.
	const START_PATH = '~';

	let currentPath = $state('');
	let pathInput = $state(START_PATH);
	let parent = $state('/');
	let entries = $state<Entry[]>([]);
	let loading = $state(false);
	let error = $state('');
	let copiedPath = $state('');

	// Breadcrumb segments with their cumulative absolute paths.
	let crumbs = $derived.by(() => {
		const parts = currentPath.split('/').filter(Boolean);
		let acc = '';
		return parts.map((name) => {
			acc += '/' + name;
			return { name, path: acc };
		});
	});

	async function browse(path: string) {
		try {
			loading = true;
			error = '';
			const res = await fetch(
				`${API_URL}/v1/ssh/browse?path=${encodeURIComponent(path)}`,
				{ headers: authHeaders() }
			);
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) {
				const body = await res.json().catch(() => null);
				throw new Error(body?.detail || 'Failed to open directory');
			}
			const data = await res.json();
			entries = data.entries;
			currentPath = data.path;
			pathInput = data.path;
			parent = data.parent;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load directory';
			console.error('Error browsing:', e);
		} finally {
			loading = false;
		}
	}

	function joinPath(dir: string, name: string): string {
		return dir.replace(/\/+$/, '') + '/' + name;
	}

	function openDir(name: string) { browse(joinPath(currentPath, name)); }
	function goUp() { if (currentPath !== '/') browse(parent); }
	function submitPath(e: Event) { e.preventDefault(); if (pathInput.trim()) browse(pathInput.trim()); }

	async function copyPath(name: string) {
		const path = joinPath(currentPath, name);
		try {
			await navigator.clipboard.writeText(path);
			copiedPath = path;
			setTimeout(() => { if (copiedPath === path) copiedPath = ''; }, 1500);
		} catch { /* clipboard unavailable — ignore */ }
	}

	function humanSize(bytes: number): string {
		if (bytes < 1024) return `${bytes} B`;
		const units = ['KB', 'MB', 'GB', 'TB'];
		let val = bytes / 1024, i = 0;
		while (val >= 1024 && i < units.length - 1) { val /= 1024; i++; }
		return `${val.toFixed(val >= 10 || i === 0 ? 0 : 1)} ${units[i]}`;
	}

	// Initial load.
	onMount(() => { browse(START_PATH); });
</script>

<div class="w-full px-4 md:px-6 py-8 max-w-none">
	<h1 class="text-4xl font-bold mb-6 text-center text-primary-500">File Explorer</h1>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
			{error}
		</div>
	{/if}

	<div class="card p-4 bg-surface-100 dark:bg-surface-800 mb-4">
		<form onsubmit={submitPath} class="flex gap-2">
			<button
				type="button"
				onclick={goUp}
				disabled={loading || currentPath === '/'}
				title="Up one level"
				class="btn variant-soft px-3"
			>↑ Up</button>
			<input
				type="text"
				bind:value={pathInput}
				placeholder="Enter a path..."
				disabled={loading}
				class="flex-1 px-4 py-2 rounded border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 font-mono text-sm"
			/>
			<button type="submit" disabled={loading || !pathInput.trim()} class="btn variant-filled-primary px-6">
				{loading ? 'Loading...' : 'Go'}
			</button>
		</form>

		<!-- Breadcrumbs -->
		<div class="flex flex-wrap items-center gap-1 mt-3 text-sm font-mono">
			<button type="button" onclick={() => browse('/')} class="text-primary-500 hover:underline">/</button>
			{#each crumbs as crumb, i}
				<button type="button" onclick={() => browse(crumb.path)} class="text-primary-500 hover:underline">
					{crumb.name}
				</button>
				{#if i < crumbs.length - 1}<span class="text-surface-400">/</span>{/if}
			{/each}
		</div>
	</div>

	<div class="card p-4 bg-surface-100 dark:bg-surface-800">
		{#if loading && entries.length === 0}
			<p class="text-surface-600 dark:text-surface-400 p-3">Loading...</p>
		{:else if entries.length === 0}
			<p class="text-surface-600 dark:text-surface-400 p-3">This folder is empty.</p>
		{:else}
			<ul class="divide-y divide-surface-300 dark:divide-surface-700">
				{#each entries as entry}
					<li class="flex items-center gap-3 py-2 px-2 hover:bg-surface-200 dark:hover:bg-surface-700 rounded">
						{#if entry.type === 'directory'}
							<button
								type="button"
								onclick={() => openDir(entry.name)}
								class="flex-1 flex items-center gap-2 text-left font-mono text-sm min-w-0"
							>
								<span>📁</span>
								<span class="font-medium truncate">{entry.name}/</span>
							</button>
							<span class="text-xs text-surface-500 w-20 text-right">—</span>
						{:else}
							<span class="flex-1 flex items-center gap-2 font-mono text-sm min-w-0">
								<span>📄</span>
								<span class="truncate">{entry.name}</span>
							</span>
							<span class="text-xs text-surface-500 w-20 text-right">{humanSize(entry.size)}</span>
						{/if}

						<button
							type="button"
							onclick={() => copyPath(entry.name)}
							title="Copy full path"
							class="btn btn-sm variant-soft px-2 text-xs"
						>
							{copiedPath === joinPath(currentPath, entry.name) ? '✓ Copied' : 'Copy path'}
						</button>
					</li>
				{/each}
			</ul>
		{/if}
	</div>
</div>
