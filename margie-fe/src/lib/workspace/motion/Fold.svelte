<script lang="ts">
	import { untrack, type Snippet } from 'svelte';
	import { ui } from '../ui.svelte';
	import { foldDomId } from './fold';

	/**
	 * Collapsible section body toggled by the FoldTitle with the same `id`; the state is saved and
	 * the height eases to the content's height. Passing `open` drives it from the page instead.
	 */
	let {
		id,
		children,
		closed = false,
		class: cls = '',
		open: forced
	}: { id: string; children: Snippet; closed?: boolean; class?: string; open?: boolean } = $props();

	const open = $derived(forced ?? !ui.isFolded(id, closed));
	// Lets menus and popovers overflow only once fully open.
	let settled = $state(untrack(() => open));
	$effect(() => {
		if (!open) {
			settled = false;
			return;
		}
		const t = setTimeout(() => (settled = true), ui.ms(420) + 30);
		return () => clearTimeout(t);
	});
</script>

<div class="mo-fold {cls}" class:open class:settled id={foldDomId(id)} inert={!open}>
	<div class="mo-fold-inner">{@render children()}</div>
</div>

<style>
	.mo-fold {
		display: grid;
		grid-template-rows: 0fr;
		opacity: 0;
		transition:
			grid-template-rows var(--mo-3) var(--mo-ease),
			opacity var(--mo-2) var(--mo-ease);
	}
	.mo-fold.open {
		grid-template-rows: 1fr;
		opacity: 1;
	}
	.mo-fold-inner {
		min-height: 0;
		min-width: 0;
		overflow: hidden;
	}
	.mo-fold.settled > .mo-fold-inner {
		overflow: visible;
	}
</style>
