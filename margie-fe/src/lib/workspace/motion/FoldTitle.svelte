<script lang="ts">
	import type { Snippet } from 'svelte';
	import { ui } from '../ui.svelte';
	import { foldDomId } from './fold';

	/** A section heading that opens and closes the Fold with the same `id`. */
	let {
		id,
		tag = 'h2',
		class: cls = '',
		headingId,
		closed = false,
		children
	}: { id: string; tag?: 'h1' | 'h2' | 'h3'; class?: string; headingId?: string; closed?: boolean; children: Snippet } = $props();

	const open = $derived(!ui.isFolded(id, closed));
</script>

<svelte:element this={tag} class="mo-fold-title {cls}" id={headingId}>
	<!-- No chevron; the FoldToggle word beside it says what it does. -->
	<button type="button" aria-expanded={open} aria-controls={foldDomId(id)} onclick={() => ui.toggleFold(id, closed)}>
		<span>{@render children()}</span>
	</button>
</svelte:element>

<style>
	button {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		margin: 0 0 0 -6px;
		padding: 2px 6px;
		border: none;
		border-radius: 8px;
		background: none;
		color: inherit;
		font: inherit;
		letter-spacing: inherit;
		text-align: left;
		cursor: pointer;
		transition: background-color var(--mo-1) var(--mo-ease);
	}
	button:hover {
		background: var(--at-track, var(--mg-surface-2));
	}
</style>
