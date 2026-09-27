<script lang="ts">
	import JobsBoard from '$lib/crisp/JobsBoard.svelte';
	import { ws } from '$lib/workspace/data.svelte';

	const count = (status: string) => ws.runs.filter((r) => r.status === status).length;
</script>

<svelte:head><title>Jobs | MARGIE</title></svelte:head>

<div class="cr-page" data-shade="page-runs">
	<div class="cr-head">
		<h1 class="cr-title">Jobs</h1>
		<p class="cr-lede">Jobs started from MARGIE, with their inputs, output folder and log.</p>
		<span class="cr-meta">{ws.runs.length ? `${ws.runs.length} job${ws.runs.length === 1 ? '' : 's'}` : ''}</span>
	</div>

	{#if ws.runs.length}
		<div class="cr-stats" aria-label="Jobs at a glance">
			<div class="cr-stat" style={ws.running.length ? '--stat: var(--mg-accent)' : undefined}><b>{ws.running.length}</b><span>running</span></div>
			<div class="cr-stat" style="--stat: var(--mg-ok)"><b>{count('completed')}</b><span>finished</span></div>
			<div class="cr-stat" style={count('failed') ? '--stat: var(--mg-danger)' : undefined}><b>{count('failed')}</b><span>failed</span></div>
			<div class="cr-stat"><b>{count('cancelled')}</b><span>stopped</span></div>
		</div>
	{/if}

	<JobsBoard />
</div>
