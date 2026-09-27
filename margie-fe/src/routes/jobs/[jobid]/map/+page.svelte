<script lang="ts">
	import { page } from '$app/stores';
	import { onDestroy, untrack } from 'svelte';
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';
	import ChatPanel from '$lib/ChatPanel.svelte';
	import { getApiUrl } from '$lib/config';

	const jobId = $derived($page.params.jobid);
	// Path of FINAL_GENOME_VIEWER.html in the job dir, e.g. "<organism>/FINAL_GENOME_VIEWER.html".
	const filePath = $derived($page.url.searchParams.get('path') ?? '');
	// Display name only.
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

			// Re-types the octet-stream blob as text/html so the iframe renders it.
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

	// Reloads when jobId or filePath changes (the component is reused across query changes).
	// loadViewer runs untracked because it reads and writes blobUrl.
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
		<!-- Chat sits beside the sandboxed iframe, which cannot make authenticated calls. -->
		<div class="flex flex-1 gap-3 overflow-hidden">
			<!-- No allow-same-origin: viewer scripts cannot reach the token or storage. allow-downloads enables the "⤓ map" button. -->
			<iframe
				src={blobUrl}
				title="Interactive genome map for {organism}"
				class="h-full flex-1 rounded border border-surface-500/30 bg-white"
				sandbox="allow-scripts allow-downloads"
			></iframe>
			<div class="hidden h-full w-[300px] shrink-0 xl:w-[340px] lg:block">
				<ChatPanel {jobId} {organism} />
			</div>
		</div>
	{/if}
</div>
