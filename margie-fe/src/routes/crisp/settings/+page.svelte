<script lang="ts">
	import { backend } from '$lib/workspace/backend.svelte';
	import SettingsBoard from '$lib/crisp/SettingsBoard.svelte';
</script>

<svelte:head><title>Settings | MARGIE</title></svelte:head>

<div class="cr-page" data-shade="page-settings">
	<div class="cr-head">
		<h1 class="cr-title">Settings</h1>
		<p class="cr-lede">
			{#if backend.cluster}
				The SLURM account, folders, and the threads, memory and time each step may use. Stored in your config file on the cluster.
			{:else}
				Folders, cores and memory, workflow steps and tool licences.
			{/if}
		</p>
		<span class="cr-meta">Changes apply to the next run</span>
	</div>
	<SettingsBoard />
</div>
