<script lang="ts">
	import ResultsBoard from '$lib/crisp/ResultsBoard.svelte';
	import { ws } from '$lib/workspace/data.svelte';
</script>

<svelte:head><title>Results | MARGIE</title></svelte:head>

<div class="cr-page fill" data-shade="page-results">
	<div class="cr-head">
		<h1 class="cr-title">Results</h1>
		<span class="cr-meta">{ws.results.length ? `${ws.finished.length} of ${ws.results.length} finished` : ''}</span>
	</div>

	<ResultsBoard />
</div>

<style>
	/* Window height, so the report scrolls inside itself. */
	.fill {
		height: 100%;
		min-height: 0;
		padding-bottom: 16px;
	}
</style>
