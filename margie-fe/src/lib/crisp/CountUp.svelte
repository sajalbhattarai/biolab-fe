<script lang="ts">
	import { cubicOut } from 'svelte/easing';
	import { Tween } from 'svelte/motion';
	import { ui } from '$lib/workspace/ui.svelte';

	/** Counts a number up to its value (at once when motion is off). */
	let { value, format = (n: number) => Math.round(n).toLocaleString('en-US') }: { value: number; format?: (n: number) => string } = $props();

	const shown = new Tween(0, { easing: cubicOut });
	$effect(() => {
		shown.set(value, { duration: ui.ms(900) });
	});
</script>

<span class="rb-count">{format(shown.current)}</span>

<style>
	.rb-count {
		font-variant-numeric: tabular-nums;
	}
</style>
