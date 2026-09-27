<script lang="ts">
	import type { Snippet } from 'svelte';
	import { onMount } from 'svelte';
	import { cubicOut } from 'svelte/easing';
	import { fade, fly } from 'svelte/transition';
	import { page } from '$app/state';
	import { ChartPie, Dna, FolderOpen, House, ListChecks, Menu, Package, Play, SlidersHorizontal, Unplug, Wrench, X } from 'lucide-svelte';
	import Corner from '$lib/workspace/Corner.svelte';
	import GenomeDrop from '$lib/workspace/GenomeDrop.svelte';
	import InstallGate from '$lib/workspace/blocks/InstallGate.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { clusterParts } from '$lib/workspace/cluster-parts';
	import { styleString } from '$lib/workspace/prefs';
	import { ui } from '$lib/workspace/ui.svelte';
	import CrispMark from './CrispMark.svelte';
	import { crispVars } from './theme';
	import '@fontsource/ibm-plex-sans/400.css';
	import '@fontsource/ibm-plex-sans/500.css';
	import '@fontsource/ibm-plex-sans/600.css';
	import '@fontsource/ibm-plex-sans/700.css';
	import '@fontsource/ibm-plex-mono/400.css';
	import '$lib/workspace/workspace.css';
	import '$lib/workspace/motion/motion.css';
	import './crisp.css';
	import './legacy.css';

	/**
	 * Frames the older pages (scripts, SSH runs, historical results, methods,
	 * account) in MARGIE's header, side menu, colours and theme, fed into their
	 * Skeleton classes through legacy.css.
	 */
	let {
		tools,
		account = true,
		accountLinks = [],
		drop = true,
		after,
		children
	}: {
		/** The older pages, in the menu under MARGIE's own. */
		tools: { href: string; label: string }[];
		account?: boolean;
		accountLinks?: { href: string; label: string }[];
		/** Genomes can be dropped on the page (not on sign-in pages). */
		drop?: boolean;
		after?: Snippet;
		children: Snippet;
	} = $props();

	const NAV = [
		{ href: '/crisp/home', label: 'Home', icon: House },
		{ href: '/crisp', label: 'Analyze', icon: Play },
		{ href: '/crisp/genomes', label: 'Genomes', icon: Dna },
		{ href: '/crisp/results', label: 'Results', icon: ChartPie },
		{ href: '/crisp/files', label: 'Files', icon: FolderOpen },
		{ href: '/crisp/runs', label: 'Jobs', icon: ListChecks },
		{ href: '/crisp/setup', label: 'Install', icon: Package },
		{ href: '/crisp/settings', label: 'Settings', icon: SlidersHorizontal }
	];
	const path = $derived(page.url.pathname.replace(/\/$/, '') || '/');
	const current = (href: string) => path === href || path.startsWith(href + '/');
	const here = $derived(tools.find((t) => current(t.href))?.label ?? '');

	let open = $state(false);
	$effect(() => {
		void path;
		open = false;
	});

	// These pages open standalone, so they read the saved look themselves and
	// put .dark on the page for Skeleton's dark: classes.
	onMount(() => {
		if (page.data.ui) ui.init(page.data.ui);
		else if ('restore' in ui && typeof ui.restore === 'function') ui.restore();
		const dark = matchMedia('(prefers-color-scheme: dark)');
		ui.systemDark = dark.matches;
		const onDark = (e: MediaQueryListEvent) => (ui.systemDark = e.matches);
		dark.addEventListener('change', onDark);
		return () => dark.removeEventListener('change', onDark);
	});
	$effect(() => {
		document.documentElement.classList.toggle('dark', ui.dark);
	});

	const vars = $derived(styleString(crispVars(ui.prefs, ui.dark)) + '; ' + ui.motionStyle);

	/** Disconnects from the HPC (cluster runs keep going); the start page offers Connect again. */
	async function disconnectHpc() {
		if (!confirm('Disconnect from the HPC? Runs already on the cluster keep going.')) return;
		const ok = await clusterParts.disconnect?.();
		if (!ok) {
			ui.notify('Could not disconnect; try again from the start page.', 'error');
			return;
		}
		location.href = clusterParts.switchHref ?? '/start';
	}
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && (open = false)} />

<div class="crisp cr-legacy" data-mg-root data-theme={ui.dark ? 'dark' : 'light'} data-motion={ui.motion} style={vars}>
	{#if drop}<GenomeDrop toasts />{/if}
	<header class="bar">
		<button type="button" class="icon" aria-label="Pages" aria-expanded={open} aria-controls="cr-legacy-pages" onclick={() => (open = !open)}>
			<Menu size={20} />
		</button>
		<a class="brand" href="/crisp/home" aria-label="MARGIE, home">
			<CrispMark size={20} />
			<span class="word">MARGIE</span>
			<span class="where">{backend.cluster ? `on the HPC${backend.host ? `, ${backend.host.split('.')[0]}` : ''}` : 'on this computer'}</span>
		</a>
		{#if here}<span class="here">{here}</span>{/if}
		<span class="grow"></span>
		{#if backend.cluster && clusterParts.disconnect}
			<button type="button" class="disconnect" title="End the connection to the HPC; runs already on the cluster keep going" onclick={disconnectHpc}>
				<Unplug size={15} />Disconnect
			</button>
		{/if}
		<Corner base="crisp" links={accountLinks} {account} {after}>
			{#snippet customize(close)}
				<div class="cz">
					<p>Text size, colours and the rest of the look are set in MARGIE's Customize, and apply here too.</p>
					<a class="mg-link" href="/crisp/home" onclick={() => close()}>Open MARGIE</a>
				</div>
			{/snippet}
		</Corner>
	</header>

	{#if open}
		<button type="button" class="scrim" aria-label="Close the menu" transition:fade={{ duration: ui.ms(150) }} onclick={() => (open = false)}></button>
		<nav id="cr-legacy-pages" class="pages" aria-label="MARGIE" transition:fly={{ x: -24, duration: ui.ms(180), easing: cubicOut }}>
			<div class="pages-head">
				<span class="word">MARGIE</span>
				<button type="button" class="icon" aria-label="Close the menu" onclick={() => (open = false)}><X size={18} /></button>
			</div>
			{#each NAV as n (n.href)}
				<a href={n.href}><n.icon size={17} /><span>{n.label}</span></a>
			{/each}
			{#if tools.length}
				<span class="pages-group">Other tools</span>
				{#each tools as t (t.href)}
					<a href={t.href} aria-current={current(t.href) ? 'page' : undefined}><Wrench size={17} /><span>{t.label}</span></a>
				{/each}
			{/if}
		</nav>
	{/if}

	<main class="content">
		<div class="cr-page legacy-page">
			{@render children()}
			<InstallGate />
		</div>
	</main>
</div>

<style>
	.bar {
		position: relative;
		z-index: 5;
		flex-shrink: 0;
		display: flex;
		align-items: center;
		gap: 14px;
		height: 48px;
		padding: 0 16px;
		border-bottom: 1px solid var(--mg-border);
		background: var(--mg-surface);
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.word {
		font-size: calc(var(--cr-fs-body) * 1.2);
		font-weight: 700;
		letter-spacing: 0.06em;
	}
	.where {
		font-size: var(--cr-fs-meta);
		color: var(--mg-text-3);
	}
	.here {
		padding-left: 14px;
		border-left: 1px solid var(--mg-border);
		font-size: var(--cr-fs-meta);
		font-weight: 600;
		color: var(--mg-text-2);
	}
	.grow {
		flex-grow: 1;
	}
	.icon {
		display: grid;
		place-items: center;
		width: 36px;
		height: 36px;
		margin-left: -6px;
		border: none;
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-text-2);
		cursor: pointer;
	}
	.icon:hover {
		background: var(--mg-surface-2);
		color: var(--mg-text);
	}
	.cz {
		display: flex;
		flex-direction: column;
		gap: 8px;
		font-size: var(--cr-fs-meta);
		color: var(--mg-text-2);
	}
	.scrim {
		position: fixed;
		inset: 0;
		z-index: 40;
		border: none;
		background: var(--mg-scrim);
	}
	.pages {
		position: fixed;
		z-index: 41;
		top: var(--mg-titlebar, 0px);
		bottom: 0;
		left: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
		width: min(280px, 86vw);
		padding: 12px;
		overflow-y: auto;
		border-right: 1px solid var(--mg-border);
		background: var(--mg-surface);
		box-shadow: var(--cr-pop-shadow);
	}
	.pages-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 4px 4px 12px 10px;
		margin-bottom: 6px;
		border-bottom: 1px solid var(--mg-border);
	}
	.pages-group {
		margin: 14px 12px 4px;
		font-size: var(--cr-fs-micro);
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.pages a {
		display: flex;
		align-items: center;
		gap: 12px;
		height: 42px;
		padding: 0 12px;
		border-radius: var(--mg-r-sm);
		color: var(--mg-text-2);
	}
	.pages a:hover {
		background: var(--mg-surface-2);
		color: var(--mg-text);
	}
	.pages a[aria-current='page'] {
		background: color-mix(in srgb, var(--mg-accent) 12%, var(--mg-surface));
		color: var(--mg-accent-ink, var(--mg-accent));
		font-weight: 600;
	}
	.content {
		flex-grow: 1;
		min-height: 0;
		overflow: auto;
		background: var(--mg-bg);
	}
	@media (max-width: 820px) {
		.where,
		.here {
			display: none;
		}
	}
	.disconnect {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		height: 30px;
		padding: 0 10px;
		border: 1px solid var(--mg-border-strong);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--cr-fs-meta);
		cursor: pointer;
	}
	.disconnect:hover {
		border-color: var(--mg-danger);
		color: var(--mg-danger);
	}
</style>
