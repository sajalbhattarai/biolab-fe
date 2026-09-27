<script lang="ts">
	import { ChevronRight, LogOut, Monitor, UserRound } from 'lucide-svelte';
	import { backend } from './backend.svelte';
	import { clusterParts } from './cluster-parts';
	import MenuButton from './MenuButton.svelte';

	/**
	 * Account button in the corner: signed-in user, where work runs, switching, and sign-out.
	 * `links` adds interface-specific pages.
	 */
	let { links = [], showLabel = true }: { links?: { href: string; label: string }[]; showLabel?: boolean } = $props();

	const label = $derived(backend.cluster ? backend.user || 'Account' : 'This computer');
</script>

<MenuButton {label} title={backend.cluster ? `Signed in as ${backend.user || 'you'} on ${backend.host || 'the cluster'}` : 'Working on this computer'} {showLabel} width={280}>
	{#snippet icon()}<UserRound size={16} />{/snippet}
	{#snippet children(close)}
		<div class="um-who">
			<span class="um-avatar" aria-hidden="true">
				{#if backend.cluster}{(backend.user || '?').slice(0, 1).toUpperCase()}{:else}<Monitor size={18} />{/if}
			</span>
			<span class="um-text">
				{#if backend.cluster}
					<b>{backend.user || 'Signed in'}</b>
					<span>on {backend.host || 'the cluster'}. Jobs run there as this account.</span>
				{:else}
					<b>This computer</b>
					<span>Analyses run here. No account needed.</span>
				{/if}
			</span>
		</div>
		{#if links.length || clusterParts.switchHref || backend.cluster}
			<div class="um-list">
				{#each links as l (l.href)}
					<a class="um-row" href={l.href} onclick={close}><span>{l.label}</span><ChevronRight size={15} /></a>
				{/each}
				{#if clusterParts.switchHref}
					<a class="um-row" href={clusterParts.switchHref} onclick={close}><span>Change where MARGIE runs</span><ChevronRight size={15} /></a>
				{/if}
				{#if backend.cluster}
					<button
						type="button"
						class="um-row out"
						onclick={() => {
							close();
							backend.signOut();
						}}><span>Sign out</span><LogOut size={15} /></button
					>
				{/if}
			</div>
		{/if}
	{/snippet}
</MenuButton>

<style>
	.um-who {
		display: flex;
		align-items: center;
		gap: 12px;
		min-width: 0;
		overflow-wrap: anywhere;
	}
	.um-avatar {
		display: grid;
		place-items: center;
		flex-shrink: 0;
		width: 40px;
		height: 40px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--mg-accent-base, var(--mg-accent, #0f766e)) 14%, var(--mg-surface, #fff));
		color: var(--mg-accent-ink, var(--mg-accent, #0f766e));
		font-weight: 700;
	}
	.um-text {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.um-text b {
		font-weight: 600;
	}
	.um-text span {
		font-size: var(--cr-fs-meta, var(--mg-fs-sm, 14px));
		color: var(--mg-text-2, #454c57);
	}
	.um-list {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding-top: 10px;
		border-top: 1px solid var(--mg-border, #e2e4e8);
	}
	.um-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 10px;
		min-height: 38px;
		padding: 0 12px;
		border: 0;
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text, #15181d);
		font: inherit;
		font-size: var(--cr-fs-meta, var(--mg-fs-sm, 14px));
		text-align: left;
		text-decoration: none;
		cursor: pointer;
	}
	.um-row :global(svg) {
		flex-shrink: 0;
		color: var(--mg-text-3, #646b76);
	}
	.um-row:hover {
		background: color-mix(in srgb, var(--mg-text, #15181d) 5%, transparent);
	}
	.um-row.out:hover,
	.um-row.out:hover :global(svg) {
		color: var(--mg-danger, #b42318);
	}
</style>
