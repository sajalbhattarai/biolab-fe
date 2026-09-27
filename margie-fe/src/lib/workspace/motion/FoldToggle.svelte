<script lang="ts">
	import { ui } from '../ui.svelte';
	import { foldDomId } from './fold';

	/** Text toggle for a section: "Show"/"Hide" by default, or a custom pair ("Change"/"Done"). */
	let {
		id,
		closed = false,
		open: openWord = 'Show',
		shut: shutWord = 'Hide'
	}: { id: string; closed?: boolean; open?: string; shut?: string } = $props();

	const open = $derived(!ui.isFolded(id, closed));
</script>

<button type="button" class="mg-link quiet" aria-expanded={open} aria-controls={foldDomId(id)} onclick={() => ui.toggleFold(id, closed)}>
	{open ? shutWord : openWord}
</button>
