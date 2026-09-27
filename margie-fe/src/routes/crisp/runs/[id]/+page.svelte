<script lang="ts">
	import { page } from '$app/state';
	import RunLogPage from '$lib/workspace/pages/RunLogPage.svelte';
</script>

<svelte:head><title>Job log | MARGIE</title></svelte:head>

<div class="cr-page fill" data-shade="page-runs">
	<RunLogPage id={page.params.id ?? ''} />
</div>

<style>
	.fill {
		height: 100%;
		min-height: 0;
		padding-bottom: 24px;
	}
	.fill > :global(*) {
		flex-grow: 1;
		min-height: 0;
	}
	@media (max-width: 980px) {
		.fill {
			height: auto;
		}
	}
</style>
