<script lang="ts">
	import type { Snippet } from 'svelte';

	/** A small uppercase caption above a control. */
	let { title, id, children }: { title: string; id?: string; children: Snippet } = $props();
</script>

<div class="field">
	{#if id}
		<label class="mg-label" for={id}>{title}</label>
	{:else}
		<span class="mg-label">{title}</span>
	{/if}
	{@render children()}
</div>

<style>
	.field {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
</style>
