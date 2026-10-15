<script lang="ts">
	/**
	 * Explanatory text that Simple mode keeps out of the way: shown in Guided mode,
	 * or when Details (top bar) is on. Controls, statuses and errors never go in here.
	 */
	import type { Snippet } from 'svelte';
	import { ui } from './ui.svelte';

	let { children }: { children: Snippet } = $props();
</script>

{#if ui.explain}{@render children()}{/if}
