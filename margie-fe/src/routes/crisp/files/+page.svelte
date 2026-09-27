<script lang="ts">
	import FilesBoard from '$lib/crisp/FilesBoard.svelte';
	import type { FolderRoot } from '$lib/workspace/FolderView.svelte';
	import { page } from '$app/state';
	import { api } from '$lib/api';
	import { backend } from '$lib/workspace/backend.svelte';

	/** Plain file browser over home, mounted drives and the pipeline's folders. */
	let places = $state<FolderRoot[]>([]);
	/** Waits for the places so ?path= opens inside its place. */
	let loaded = $state(false);
	$effect(() => {
		api<{ places: FolderRoot[] }>('/files?places=1')
			.then((d) => (places = d.places))
			.catch(() => (places = []))
			.finally(() => (loaded = true));
	});

	/** ?path= opens straight at that folder (e.g. a run's output). */
	const start = $derived(page.url.searchParams.get('path') ?? '');
	const roots = $derived.by((): FolderRoot[] => {
		if (!loaded) return [];
		const known = places.some((r) => start === r.path || start.startsWith(r.path + '/'));
		return start && !known ? [{ label: start.split('/').filter(Boolean).at(-1) ?? start, path: start }, ...places] : places;
	});
</script>

<svelte:head><title>Files | MARGIE</title></svelte:head>

<div class="cr-page fill" data-shade="page-files">
	<div class="cr-head">
		<h1 class="cr-title">Files</h1>
		<p class="cr-lede">
			{#if backend.cluster}
				Browse your files on the cluster, and pick one to preview it. For a genome's report, see <a class="mg-link" href="/crisp/results">Results</a>.
			{:else}
				Browse your files on this computer, and pick one to preview it. For a genome's report, see <a class="mg-link" href="/crisp/results">Results</a>.
			{/if}
		</p>
		<span class="cr-meta">{roots.length ? `${roots.length} places` : ''}</span>
	</div>
	<FilesBoard {roots} {start} memory="crisp:all" empty={loaded ? 'Nothing here.' : 'Finding your folders…'} />
</div>

<style>
	.fill {
		height: 100%;
		min-height: 0;
		padding-bottom: 24px;
	}
</style>
