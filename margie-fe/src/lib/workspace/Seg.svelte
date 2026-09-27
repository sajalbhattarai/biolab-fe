<script lang="ts" generics="T extends string | number">
	import { thumb } from './motion/thumb';

	/** A segmented choice: a row of buttons, one selected. */
	let {
		options,
		value,
		onpick,
		label
	}: {
		options: { value: T; label: string; disabled?: boolean; title?: string }[];
		value: T;
		onpick: (v: T) => void;
		label: string;
	} = $props();
</script>

<div class="mg-seg" role="radiogroup" aria-label={label} use:thumb>
	{#each options as o (o.value)}
		<button type="button" role="radio" aria-checked={o.value === value} disabled={o.disabled} title={o.title} onclick={() => onpick(o.value)}>
			{o.label}
		</button>
	{/each}
</div>

<style>
	/* Fallback shape at zero specificity for pages that do not load workspace.css. */
	:where(.mg-seg) {
		position: relative;
		isolation: isolate;
		display: flex;
		gap: 2px;
		padding: 3px;
		border: 1px solid var(--mg-border, #e2e4e8);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2, #f4f5f7);
	}
	:where(.mg-seg button) {
		position: relative;
		z-index: 1;
		flex: 1;
		height: 30px;
		padding: 0 12px;
		border: none;
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-text-2, #454c57);
		font: inherit;
		font-size: var(--mg-fs-sm, 14px);
		white-space: nowrap;
		cursor: pointer;
	}
	:where(.mg-seg button[aria-checked='true']) {
		background: var(--mg-seg-sel, #fff);
		box-shadow: 0 0 0 1px var(--mg-border, #e2e4e8);
		color: var(--mg-text, #15181d);
		font-weight: 600;
	}
	:where(.mg-seg) > :global(:where(.mo-thumb)) {
		position: absolute;
		top: 0;
		left: 0;
		border-radius: var(--mg-r-sm);
		background: var(--mg-seg-sel, #fff);
		pointer-events: none;
	}
</style>
