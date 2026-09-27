<script lang="ts">
	import type { Snippet } from 'svelte';
	import { SlidersHorizontal } from 'lucide-svelte';
	import MenuButton from './MenuButton.svelte';
	import ThemeMenu from './ThemeMenu.svelte';
	import UserMenu from './UserMenu.svelte';

	/**
	 * Top-right corner shared by every interface: Theme, Customize, account, in a fixed order.
	 * Interface-specific buttons go in `before`; Customize opens `oncustomize` or a `customize` panel.
	 */
	let {
		base = 'paper',
		colours = true,
		type = true,
		note = '',
		onmore,
		oncustomize,
		customizeOpen = false,
		customize,
		links = [],
		account = true,
		before,
		after
	}: {
		/** Passed to ThemeMenu: the interface's preset and its options. */
		base?: string;
		colours?: boolean;
		type?: boolean;
		note?: string;
		onmore?: () => void;
		oncustomize?: () => void;
		customizeOpen?: boolean;
		customize?: Snippet<[() => void]>;
		/** Interface-specific pages in the account menu. */
		links?: { href: string; label: string }[];
		/** Off where nobody is signed in; `after` then holds the sign-in. */
		account?: boolean;
		before?: Snippet;
		after?: Snippet;
	} = $props();
</script>

<span class="corner">
	{@render before?.()}
	<!-- One tray of pills. -->
	<span class="corner-tray">
		<ThemeMenu {base} {colours} {type} {note} {onmore} />
		{#if customize}
			<MenuButton label="Customize" width={340}>
				{#snippet icon()}<SlidersHorizontal size={15} />{/snippet}
				{#snippet children(close)}{@render customize(close)}{/snippet}
			</MenuButton>
		{:else}
			<MenuButton label="Customize" onpress={oncustomize} pressed={customizeOpen}>
				{#snippet icon()}<SlidersHorizontal size={15} />{/snippet}
			</MenuButton>
		{/if}
		{#if account}<UserMenu {links} />{/if}
	</span>
	{@render after?.()}
</span>

<style>
	.corner {
		display: flex;
		align-items: center;
		gap: 8px;
		flex-shrink: 0;
		margin-left: auto;
	}
	.corner-tray {
		display: flex;
		align-items: center;
		gap: 2px;
		padding: 4px;
		border: 1px solid var(--mg-border, #e2e4e8);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text, #15181d) 4%, var(--mg-surface, #fff));
	}
	/* Narrow windows show icons only. */
	@media (max-width: 900px) {
		.corner :global(.mb-label) {
			display: none;
		}
	}
</style>
