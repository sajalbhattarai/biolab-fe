<script lang="ts">
	import { page } from '$app/stores';
	import { onDestroy, untrack } from 'svelte';
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';

	function getApiUrl() {
		if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
			return 'http://localhost:8000';
		}
		return '';
	}

	const jobId = $derived($page.params.jobid);
	// Relative path of FINAL_GENOME_VIEWER.html inside the job working dir,
	// e.g. "<organism>/FINAL_GENOME_VIEWER.html". Passed by the file browser.
	const filePath = $derived($page.url.searchParams.get('path') ?? '');
	// Display name only; the viewer prints its own organism title internally.
	const organism = $derived($page.url.searchParams.get('organism') ?? filePath.split('/')[0] ?? '');

	let blobUrl = $state('');
	let loading = $state(false);
	let error = $state('');
	let sizeMb = $state(0);

	function handle401() {
		clearToken();
		goto('/login');
	}

	function revoke() {
		if (blobUrl) {
			URL.revokeObjectURL(blobUrl);
			blobUrl = '';
		}
	}

	async function loadViewer() {
		if (!jobId || !filePath) {
			error = 'No viewer file specified.';
			return;
		}
		loading = true;
		error = '';
		revoke();
		try {
			const url = `${getApiUrl()}/v1/ssh/download_file/${jobId}?path=${encodeURIComponent(filePath)}`;
			const res = await fetch(url, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (res.status === 404) {
				error =
					'No genome viewer for this organism. It is generated when an ' +
					'organism finishes scoring, so runs completed before that step ' +
					'was added will not have one.';
				return;
			}
			if (!res.ok) throw new Error(`Failed to load viewer (HTTP ${res.status})`);

			// download_file streams application/octet-stream. Re-type the blob as
			// text/html so the iframe renders it instead of offering a download.
			const raw = await res.blob();
			sizeMb = raw.size / 1048576;
			blobUrl = URL.createObjectURL(new Blob([raw], { type: 'text/html' }));
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load viewer';
		} finally {
			loading = false;
		}
	}

	function downloadViewer() {
		if (!blobUrl) return;
		const a = document.createElement('a');
		a.href = blobUrl;
		a.download = filePath.split('/').pop() || 'genome_viewer.html';
		a.rel = 'noopener';
		document.body.appendChild(a);
		a.click();
		a.remove();
	}

	// Re-fetch whenever the job or the target file changes -- SvelteKit reuses
	// this component across query-param navigations, so onMount alone would miss
	// a switch to a different organism's map.
	//
	// loadViewer() must run untracked: it reads blobUrl (via revoke) and then
	// writes it, which would otherwise make this effect depend on its own output
	// and re-run forever. Only jobId and filePath are read as dependencies.
	$effect(() => {
		const j = jobId;
		const f = filePath;
		untrack(() => {
			if (j && f) loadViewer();
		});
	});

	onDestroy(revoke);
</script>

<svelte:head>
	<title>Genome map — {organism || jobId}</title>
</svelte:head>

<div class="flex h-[calc(100vh-4rem)] flex-col gap-3 p-4">
	<div class="flex flex-wrap items-center gap-3">
		<a href={`/jobs/${jobId}`} class="btn variant-ghost-surface btn-sm">← Back to job</a>
		<h1 class="text-lg font-semibold break-all">{organism || 'Genome map'}</h1>
		{#if sizeMb > 0}
			<span class="text-sm opacity-60">{sizeMb.toFixed(1)} MB</span>
		{/if}
		<div class="ml-auto flex gap-2">
			<button
				type="button"
				class="btn variant-ghost-surface btn-sm"
				onclick={loadViewer}
				disabled={loading}>↻ Reload</button
			>
			<button
				type="button"
				class="btn variant-filled-primary btn-sm"
				onclick={downloadViewer}
				disabled={!blobUrl}>⤓ Download HTML</button
			>
		</div>
	</div>

	{#if loading}
		<div class="flex flex-1 items-center justify-center opacity-70">
			Loading genome map…
		</div>
	{:else if error}
		<div class="alert variant-filled-warning">{error}</div>
	{:else if blobUrl}
		<!--
			sandbox WITHOUT allow-same-origin: the frame gets an opaque origin, so
			the viewer's inline scripts run but cannot reach this app's token,
			storage, or cookies. allow-downloads is required or the operon card's
			"⤓ map" button silently no-ops inside the frame.
		-->
		<iframe
			src={blobUrl}
			title="Interactive genome map for {organism}"
			class="flex-1 w-full rounded border border-surface-500/30 bg-white"
			sandbox="allow-scripts allow-downloads"
		></iframe>
	{/if}
</div>
