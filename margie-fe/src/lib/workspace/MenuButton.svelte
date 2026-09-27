<script lang="ts">
	import type { Snippet } from 'svelte';

	/**
	 * Corner button that opens a popover (Theme, account); closes on Escape, outside click or `close`.
	 * Uses the surrounding --mg-* colours and sizes.
	 */
	let {
		label,
		title = label,
		showLabel = true,
		width = 300,
		icon,
		children,
		onpress,
		pressed = false
	}: {
		label: string;
		title?: string;
		/** Off: icon only, label kept for screen readers. */
		showLabel?: boolean;
		width?: number;
		icon: Snippet;
		/** Popover content; without it the button only calls `onpress`. */
		children?: Snippet<[() => void]>;
		/** For a button that opens its own drawer instead of a popover. */
		onpress?: () => void;
		/** Whether what `onpress` opens is open. */
		pressed?: boolean;
	} = $props();

	let open = $state(false);
	let root = $state<HTMLElement>();
	const close = () => (open = false);

	function outside(e: PointerEvent) {
		if (open && root && !root.contains(e.target as Node)) open = false;
	}
	function key(e: KeyboardEvent) {
		if (open && e.key === 'Escape') {
			open = false;
			root?.querySelector<HTMLElement>('.mb-btn')?.focus();
		}
	}
</script>

<svelte:document onpointerdown={outside} onkeydown={key} />

<span class="mb" bind:this={root}>
	<button
		type="button"
		class="mb-btn"
		aria-haspopup="dialog"
		aria-expanded={children ? open : pressed}
		aria-label={label}
		{title}
		onclick={() => (children ? (open = !open) : onpress?.())}
	>
		{@render icon()}
		{#if showLabel}<span class="mb-label">{label}</span>{/if}
	</button>
	{#if open && children}
		<div class="mb-pop" role="dialog" aria-label={label} style="width: min({width}px, calc(100vw - 24px))">
			{@render children(close)}
		</div>
	{/if}
</span>

<style>
	.mb {
		position: relative;
		display: inline-flex;
		flex-shrink: 0;
	}
	/* Pill in the corner tray, raised while its panel is open. */
	.mb-btn {
		display: inline-flex;
		align-items: center;
		gap: 7px;
		height: var(--mb-h, 34px);
		max-width: 22ch;
		padding: 0 13px;
		border: 0;
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-text-2, #454c57);
		font: inherit;
		font-size: var(--cr-fs-meta, var(--mg-fs-sm, 14px));
		font-weight: 500;
		line-height: 1;
		cursor: pointer;
		transition:
			background-color var(--mo-1, 120ms) var(--mo-ease, ease),
			color var(--mo-1, 120ms) var(--mo-ease, ease),
			box-shadow var(--mo-1, 120ms) var(--mo-ease, ease);
	}
	.mb-btn:hover {
		background: color-mix(in srgb, var(--mg-text, #15181d) 5%, transparent);
		color: var(--mg-text, #15181d);
	}
	.mb-btn[aria-expanded='true'] {
		background: var(--mg-seg-sel, var(--mg-surface, #fff));
		box-shadow:
			var(--mg-shadow-sm, 0 1px 2px rgba(16, 24, 40, 0.06)),
			0 0 0 1px var(--mg-border, #e2e4e8);
		color: var(--mg-accent-ink, var(--mg-text, #15181d));
		font-weight: 600;
	}
	.mb-btn :global(svg) {
		flex-shrink: 0;
		opacity: 0.8;
	}
	.mb-btn[aria-expanded='true'] :global(svg) {
		opacity: 1;
	}
	.mb-label {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	/* Rounded popover under the button. */
	.mb-pop {
		position: absolute;
		top: calc(100% + 10px);
		right: -4px;
		z-index: 80;
		display: flex;
		flex-direction: column;
		gap: 14px;
		max-height: min(600px, calc(100vh - 90px));
		overflow: auto;
		padding: 16px;
		border: 1px solid var(--mg-border, #e2e4e8);
		border-radius: calc(var(--mg-r, 8px) + 6px);
		background: var(--mg-surface, #fff);
		box-shadow: var(--cr-pop-shadow, var(--mg-shadow-lg, 0 8px 24px rgba(16, 24, 40, 0.14)));
		color: var(--mg-text, #15181d);
		font-family: var(--mg-font, inherit);
		font-size: var(--cr-fs-body, var(--mg-fs, 15px));
		font-weight: 400;
		line-height: 1.45;
		text-align: left;
		transform-origin: top right;
		animation: mb-in var(--mo-2, 180ms) var(--mo-ease, cubic-bezier(0.2, 0.7, 0.2, 1)) both;
	}
	@keyframes mb-in {
		from {
			opacity: 0;
			transform: translateY(-4px) scale(0.98);
		}
	}
	:global([data-motion='off']) .mb-pop {
		animation: none;
	}
	@media (prefers-reduced-motion: reduce) {
		.mb-pop {
			animation: none;
		}
	}
	/* On phones the popover spans the screen to avoid running off the left edge. */
	@media (max-width: 560px) {
		.mb-pop {
			position: fixed;
			top: 58px;
			right: 12px;
			left: 12px;
			width: auto !important;
			transform-origin: top center;
		}
	}
</style>
