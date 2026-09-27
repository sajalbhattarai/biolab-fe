<script lang="ts">
	import type { Snippet } from 'svelte';
	import { cubicOut } from 'svelte/easing';
	import { fade, fly } from 'svelte/transition';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { ArrowDown, ArrowLeft, ArrowRight, ArrowUp, ChevronLeft, ChevronRight, History, ChartPie, Dna, Eye, FolderOpen, House, ListChecks, Menu, Package, Palette, Play, SlidersHorizontal, Unplug, X } from 'lucide-svelte';
	import RunRing from '$lib/crisp/RunRing.svelte';
	import AppearanceControls from '$lib/workspace/AppearanceControls.svelte';
	import GenomeDrop from '$lib/workspace/GenomeDrop.svelte';
	import InstallGate from '$lib/workspace/blocks/InstallGate.svelte';
	import Corner from '$lib/workspace/Corner.svelte';
	import Field from '$lib/workspace/Field.svelte';
	import Seg from '$lib/workspace/Seg.svelte';
	import { SHADE_NAMES, SHADE_ORDER } from '$lib/workspace/shades';
	import Switch from '$lib/workspace/Switch.svelte';
	import ThemeEditor from '$lib/workspace/ThemeEditor.svelte';
	import VisionControls from '$lib/workspace/VisionControls.svelte';
	import VisionFilters from '$lib/workspace/VisionFilters.svelte';
	import Resizer from '$lib/workspace/motion/Resizer.svelte';
	import { uiBase } from '$lib/workspace/base.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { clusterParts } from '$lib/workspace/cluster-parts';
	import { ws } from '$lib/workspace/data.svelte';
	import { pageMotion } from '$lib/workspace/motion/page';
	import { thumb } from '$lib/workspace/motion/thumb';
	import { preview, visionAttrs } from '$lib/workspace/preview.svelte';
	import { styleString } from '$lib/workspace/prefs';
	import { ui } from '$lib/workspace/ui.svelte';
	import { visionInfo } from '$lib/workspace/vision';
	import CrispMark from './CrispMark.svelte';
	import { crispVars } from './theme';
	import { PAGE_SHADE } from '$lib/workspace/shades';
	import GuideBar from './GuideBar.svelte';

	let { children }: { children: Snippet } = $props();

	uiBase.set('/crisp');

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
	const path = $derived(page.url.pathname.replace(/\/$/, '') || '/crisp');
	const current = (href: string) => (href === '/crisp' ? path === '/crisp' : path.startsWith(href));
	/** The page's own hue, for its eyebrow, the wash behind its head and its
	 *  pill in this bar. At "off" the strengths are 0, so it is the accent. */
	const pageShade = $derived(
		PAGE_SHADE[path] ?? PAGE_SHADE[Object.keys(PAGE_SHADE).find((k) => k !== '/crisp' && path.startsWith(k)) ?? ''] ?? 'cyan'
	);
	const vars = $derived(
		styleString(crispVars(ui.prefs, ui.dark)) +
			`; --cr-page: color-mix(in srgb, var(--sh-${pageShade}) var(--sh-title), var(--mg-accent-base)); ` +
			ui.motionStyle
	);

	/** One line about the run going on, if any. */
	const running = $derived.by(() => {
		const a = ws.active;
		if (!a) return '';
		const p = ws.progress;
		const more = ws.running.length > 1 ? ` | ${ws.running.length} jobs` : '';
		if (p) return `${p.stage} | ${p.genomes.filter((g) => g.state === 'done').length} of ${p.genomes.length} genomes`;
		// Downloads show the percentage, or the megabytes fetched when the total is unknown.
		const what = a.kind === 'build' ? 'Building' : a.kind === 'setup' ? 'Setting up' : 'Running';
		const pct = typeof a.progress === 'number' ? ` | ${a.progress}%` : '';
		return `${what}${pct}${a.progressText ? ` | ${a.progressText}` : ''}${more}`;
	});

	// ------------------------------------------------ the pages, in a side menu
	/* As on the classic pages, the header stays plain and the pages open from its menu button. */
	let pagesOpen = $state(false);
	$effect(() => {
		void path;
		pagesOpen = false;
	});

	// ------------------------------------------------ Customize
	let drawer = $state(false);
	$effect(() => {
		if (drawer) ui.checkDefault();
	});
	let settingDefault = $state(false);
	async function setDefault() {
		settingDefault = true;
		await ui.setDefault();
		settingDefault = false;
	}
	let tab = $state<'look' | 'colours' | 'vision'>('look');
	const TABS = [
		{ id: 'look', label: 'Look' },
		{ id: 'colours', label: 'Colours' },
		{ id: 'vision', label: 'Colour vision deficiency' }
	] as const;

	function open(to: typeof tab) {
		tab = to;
		drawer = true;
	}

	let content = $state<HTMLElement>();

	/*
	 * Back/forward history of places: a page, and on Results the genome, tab and Show
	 * choice (all in the address). Keeps the current place plus five behind; going
	 * somewhere new after stepping back drops what was ahead, as a browser does.
	 */
	interface Place {
		url: string;
		label: string;
	}
	const KEEP = 6;
	let places = $state<Place[]>([]);
	let at = $state(-1);
	let stepping = false;
	let recentOpen = $state(false);
	function labelOf(u: URL): string {
		const tab = NAV.find((n) => (n.href === '/crisp' ? u.pathname.replace(/\/$/, '') === '/crisp' : u.pathname.startsWith(n.href)));
		const parts = [tab?.label ?? (u.pathname.startsWith('/crisp/runs') ? 'Jobs' : u.pathname.startsWith('/crisp/view') ? 'Viewer' : 'MARGIE')];
		const q = u.searchParams;
		if (q.get('g')) parts.push(q.get('g')!);
		if (q.has('folder')) parts.push('results folder');
		if (q.get('tab')) parts.push(q.get('tab')!.replace(/^./, (c) => c.toUpperCase()));
		if (q.get('show')) parts.push(q.get('show')!.replace(/^./, (c) => c.toUpperCase()));
		if (q.get('path')) parts.push(q.get('path')!.split('/').filter(Boolean).at(-1) ?? '');
		const run = u.pathname.match(/^\/crisp\/runs\/([^/]+)/);
		if (run) parts.push(run[1]);
		return parts.filter(Boolean).join(' | ');
	}
	$effect(() => {
		const u = page.url;
		const url = u.pathname + u.search;
		const label = labelOf(u);
		if (stepping) {
			stepping = false;
			return;
		}
		if (places[at]?.url === url) return;
		const next = [...places.slice(0, at + 1), { url, label }].slice(-KEEP);
		places = next;
		at = next.length - 1;
	});
	function step(by: -1 | 1) {
		const to = at + by;
		if (to < 0 || to >= places.length) return;
		stepping = true;
		at = to;
		goto(places[to].url);
	}
	function jumpTo(i: number) {
		recentOpen = false;
		if (i === at) return;
		stepping = true;
		at = i;
		goto(places[i].url);
	}

	/*
	 * Scroll buttons for the box under the pointer (or the page): one per direction
	 * it scrolls, dimmed at its end. A click moves one screen, Shift-click to the end.
	 * Re-checked on pointer moves, scrolling and resizing, since boxes appear as data arrives.
	 */
	let target: HTMLElement | null = null;
	let sv = $state({ y: false, x: false, top: true, bottom: false, left: true, right: false });
	const scrollsY = (el: HTMLElement) => el.scrollHeight - el.clientHeight > 8 && /(auto|scroll)/.test(getComputedStyle(el).overflowY);
	const scrollsX = (el: HTMLElement) => el.scrollWidth - el.clientWidth > 8 && /(auto|scroll)/.test(getComputedStyle(el).overflowX);
	/** The nearest box around `el` that scrolls either way; the page when none does. */
	function scrollerOf(el: Element | null): HTMLElement | null {
		for (let n = el as HTMLElement | null; n && n !== document.body; n = n.parentElement) {
			if (n.closest?.('.jumps')) return target;
			if (scrollsY(n) || scrollsX(n)) return n;
		}
		return content ?? null;
	}
	function measure() {
		const t = target && target.isConnected ? target : (content ?? null);
		if (!t) return;
		const y = scrollsY(t),
			x = scrollsX(t);
		sv = {
			y,
			x,
			top: t.scrollTop <= 2,
			bottom: t.scrollTop >= t.scrollHeight - t.clientHeight - 2,
			left: t.scrollLeft <= 2,
			right: t.scrollLeft >= t.scrollWidth - t.clientWidth - 2
		};
	}
	function retarget(el: Element | null) {
		const t = scrollerOf(el);
		if (t === target) return;
		target?.removeEventListener('scroll', measure);
		target = t;
		target?.addEventListener('scroll', measure, { passive: true });
		measure();
	}
	let frame = 0;
	function onpointer(e: PointerEvent) {
		if (frame) return;
		frame = requestAnimationFrame(() => {
			frame = 0;
			retarget(document.elementFromPoint(e.clientX, e.clientY));
		});
	}
	$effect(() => {
		const c = content;
		if (!c) return;
		void page.url.pathname;
		retarget(c);
		const ro = new ResizeObserver(measure);
		ro.observe(c);
		for (const child of c.children) ro.observe(child);
		const mo = new MutationObserver(() => {
			for (const child of c.children) ro.observe(child);
			measure();
		});
		mo.observe(c, { childList: true, subtree: true });
		return () => {
			ro.disconnect();
			mo.disconnect();
		};
	});
	function nudge(dir: 'up' | 'down' | 'left' | 'right', toEnd: boolean) {
		const t = target && target.isConnected ? target : content;
		if (!t) return;
		const behavior = ui.motion === 'off' ? 'auto' : 'smooth';
		const vy = t.clientHeight * 0.85,
			vx = t.clientWidth * 0.85;
		if (dir === 'up') t.scrollTo({ top: toEnd ? 0 : t.scrollTop - vy, behavior });
		if (dir === 'down') t.scrollTo({ top: toEnd ? t.scrollHeight : t.scrollTop + vy, behavior });
		if (dir === 'left') t.scrollTo({ left: toEnd ? 0 : t.scrollLeft - vx, behavior });
		if (dir === 'right') t.scrollTo({ left: toEnd ? t.scrollWidth : t.scrollLeft + vx, behavior });
	}
	pageMotion(() => content);

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

<svelte:window
	onpointermove={onpointer}
	onkeydown={(e) => {
		// Cmd/Ctrl + [ and ] step back and forward, as in a browser.
		if ((e.metaKey || e.ctrlKey) && (e.key === '[' || e.key === ']')) {
			const tag = (e.target as HTMLElement | null)?.tagName;
			if (tag === 'INPUT' || tag === 'TEXTAREA') return;
			e.preventDefault();
			step(e.key === '[' ? -1 : 1);
			return;
		}
		if (e.key !== 'Escape') return;
		drawer = false;
		pagesOpen = false;
		recentOpen = false;
	}}
/>

<div class="crisp" data-mg-root data-theme={ui.dark ? 'dark' : 'light'} data-motion={ui.motion} data-shades={ui.prefs.shades} style={vars} {...visionAttrs()}>
	<VisionFilters />
	<GenomeDrop />
	<InstallGate />
	<header class="bar">
		<button type="button" class="icon menu" aria-label="Pages" aria-expanded={pagesOpen} aria-controls="cr-pages" onclick={() => (pagesOpen = !pagesOpen)}>
			<Menu size={20} />
		</button>
		<a class="brand" href="/crisp/home" aria-label="MARGIE, home">
			<CrispMark size={20} />
			<span class="word">MARGIE</span>
			<span class="where">{backend.cluster ? `on the HPC${backend.host ? `, ${backend.host.split('.')[0]}` : ''}` : 'on this computer'}</span>
		</a>
		<span class="here">{NAV.find((n) => current(n.href))?.label ?? ''}</span>
		<!-- back, forward, and the last places -->
		<div class="hist" role="group" aria-label="Back and forward">
			<button type="button" class="icon" aria-label="Back" title={at > 0 ? `Back to ${places[at - 1].label}` : 'Back'} disabled={at <= 0} onclick={() => step(-1)}>
				<ChevronLeft size={18} />
			</button>
			<button type="button" class="icon" aria-label="Forward" title={at < places.length - 1 ? `Forward to ${places[at + 1].label}` : 'Forward'} disabled={at >= places.length - 1} onclick={() => step(1)}>
				<ChevronRight size={18} />
			</button>
			<button type="button" class="icon" aria-label="Recent places" aria-expanded={recentOpen} title="Recent places" disabled={places.length < 2} onclick={() => (recentOpen = !recentOpen)}>
				<History size={16} />
			</button>
			{#if recentOpen}
				<button type="button" class="hist-scrim" aria-label="Close recent places" onclick={() => (recentOpen = false)}></button>
				<ul class="hist-menu" role="menu" aria-label="Recent places">
					{#each [...places.keys()].reverse() as i (i)}
						<li>
							<button type="button" role="menuitem" class:now={i === at} onclick={() => jumpTo(i)}>
								<span>{places[i].label}</span>
								{#if i === at}<em>here</em>{/if}
							</button>
						</li>
					{/each}
				</ul>
			{/if}
		</div>
		<span class="grow"></span>
		{#if running && ws.active}
			<a class="running" href="/crisp/runs/{ws.active.id}" transition:fade={{ duration: ui.ms(150) }} title="Watch the log">
				<RunRing progress={ws.progress} size={20} compact />
				<span>{running}</span>
			</a>
		{/if}
		{#if ui.prefs.vision !== 'typical'}
			<button type="button" class="icon" title="Colours adjusted for {visionInfo(ui.prefs.vision).plain.toLowerCase()}" aria-label="Colour vision deficiency" onclick={() => open('vision')}>
				<Eye size={17} />
			</button>
		{/if}
		<!-- Theme, Customize and account (signing out returns to the cluster-or-computer choice), top right in every interface. -->
		{#if backend.cluster && clusterParts.disconnect}
			<button type="button" class="disconnect" title="End the connection to the HPC; runs already on the cluster keep going" onclick={disconnectHpc}>
				<Unplug size={15} />Disconnect
			</button>
		{/if}
		{#if backend.cluster && clusterParts.Compute}<clusterParts.Compute />{/if}
		<Corner base="crisp" onmore={() => open('colours')} oncustomize={() => (drawer ? (drawer = false) : open(tab))} customizeOpen={drawer} />
	</header>

	<!-- The pages, as tabs across the top; on a narrow window the menu button above has them instead. -->
	<nav class="toptabs" aria-label="MARGIE">
		{#each NAV as n (n.href)}
			<a href={n.href} aria-current={current(n.href) ? 'page' : undefined} style="--tab: color-mix(in srgb, var(--sh-{PAGE_SHADE[n.href] ?? 'cyan'}) var(--sh-title), var(--mg-accent-base))"
				><n.icon size={15} /><span>{n.label}</span></a
			>
		{/each}
	</nav>

	{#if pagesOpen}
		<button type="button" class="scrim" aria-label="Close the menu" transition:fade={{ duration: ui.ms(150) }} onclick={() => (pagesOpen = false)}></button>
		<nav id="cr-pages" class="pages" aria-label="MARGIE" transition:fly={{ x: -24, duration: ui.ms(180), easing: cubicOut }}>
			<div class="pages-head">
				<span class="word">MARGIE</span>
				<button type="button" class="icon" aria-label="Close the menu" onclick={() => (pagesOpen = false)}><X size={18} /></button>
			</div>
			{#each NAV as n (n.href)}
				<a href={n.href} aria-current={current(n.href) ? 'page' : undefined}><n.icon size={17} /><span>{n.label}</span></a>
			{/each}
		</nav>
	{/if}

	{#if ui.guided}<GuideBar />{/if}

	<main class="content" bind:this={content}>
		{@render children()}
	</main>

	{#if sv.y || sv.x}
		<div class="jumps" role="group" aria-label="Scroll" transition:fade={{ duration: ui.ms(150) }}>
			{#if sv.x}
				<button type="button" class="jump" disabled={sv.left} aria-label="Scroll left" title="Left (Shift: to the start)" onclick={(e) => nudge('left', e.shiftKey)}><ArrowLeft size={16} /></button>
			{/if}
			{#if sv.y}
				<button type="button" class="jump" disabled={sv.top} aria-label="Scroll up" title="Up (Shift: to the top)" onclick={(e) => nudge('up', e.shiftKey)}><ArrowUp size={16} /></button>
				<button type="button" class="jump" disabled={sv.bottom} aria-label="Scroll down" title="Down (Shift: to the bottom)" onclick={(e) => nudge('down', e.shiftKey)}><ArrowDown size={16} /></button>
			{/if}
			{#if sv.x}
				<button type="button" class="jump" disabled={sv.right} aria-label="Scroll right" title="Right (Shift: to the end)" onclick={(e) => nudge('right', e.shiftKey)}><ArrowRight size={16} /></button>
			{/if}
		</div>
	{/if}

	{#if drawer}
		<button type="button" class="scrim" aria-label="Close Customize" transition:fade={{ duration: ui.ms(180) }} onclick={() => (drawer = false)}></button>
		<div
			class="drawer"
			role="dialog"
			aria-label="Customize"
			tabindex="-1"
			style="width: min({ui.size('crisp:drawer', 440)}px, 100%)"
			transition:fly={{ x: 28, duration: ui.ms(260), easing: cubicOut }}
		>
			<Resizer id="crisp:drawer" fallback={440} min={340} max={720} edge="left" label="Resize Customize" />
			<header>
				<span class="drawer-icon" aria-hidden="true"><Palette size={16} /></span>
				<h2>Customize</h2>
				<span class="grow"></span>
				<button type="button" class="icon" aria-label="Close" onclick={() => (drawer = false)}><X size={17} /></button>
			</header>
			<div class="tabs" role="tablist" aria-label="Customize" use:thumb>
				{#each TABS as t (t.id)}
					<button type="button" role="tab" aria-selected={tab === t.id} onclick={() => (tab = t.id)}>{t.label}</button>
				{/each}
			</div>
			<div class="drawer-body" class:cards={tab === 'look'} role="tabpanel">
				{#if tab === 'look'}
					<section class="cr-group">
						<h3 class="cr-group-title">Interface</h3>
						{#if clusterParts.switchHref}
							<Field title="Where MARGIE runs">
								<div class="line-switch where-line">
									<span class="where">{backend.cluster ? `On the HPC${backend.host ? `, ${backend.host}` : ''}` : 'On this computer'}</span>
									<a class="mg-btn small" href={clusterParts.switchHref}>Change</a>
								</div>
							</Field>
						{/if}
	
						<Field title="Hints">
							<Seg
								label="Hints"
								value={ui.prefs.mode}
								onpick={(mode) => ui.update({ mode, welcomed: true })}
								options={[
									{ value: 'clean', label: 'Clean' },
									{ value: 'guided', label: 'Guided' }
								]}
							/>
							<span class="note">Guided shows the four steps, from installing to reading the results, and a hint for the page you are on.</span>
						</Field>
					</section>
					<AppearanceControls />
					<section class="cr-group">
						<h3 class="cr-group-title">Page</h3>
						<Field title="Backdrop">
							<Seg
								label="Backdrop"
								value={ui.prefs.backdrop}
								onpick={(backdrop) => ui.update({ backdrop })}
								options={[
									{ value: 'glow', label: 'Glow' },
									{ value: 'plain', label: 'Plain' }
								]}
							/>
							<span class="note">Glow adds a faint colour behind each page's title.</span>
						</Field>
						<Field title="Colour">
							<Seg
								label="Colour"
								value={ui.prefs.tint}
								onpick={(tint) => ui.update({ tint })}
								options={[
									{ value: 'plain', label: 'Plain' },
									{ value: 'soft', label: 'Soft' },
									{ value: 'strong', label: 'Strong' }
								]}
							/>
							<span class="note">How strongly tags and block headers are tinted.</span>
						</Field>
						<Field title="Shades">
							<Seg
								label="Shades"
								value={ui.prefs.shades}
								onpick={(shades) => ui.update({ shades })}
								options={SHADE_ORDER.map((s) => ({ value: s, label: SHADE_NAMES[s] }))}
							/>
							<span class="note"
								>A colour for each kind of block, shown beside its name. From Trace, barely there, to Bold. Vivid and Bold also tint the header and its
								controls.</span
							>
						</Field>
						<Field title="Contrast">
							<Seg
								label="Contrast"
								value={ui.prefs.contrast}
								onpick={(contrast) => ui.update({ contrast })}
								options={[
									{ value: 'normal', label: 'Normal' },
									{ value: 'more', label: 'More' },
									{ value: 'high', label: 'High' }
								]}
							/>
							<span class="note"
								>Pushes the text and the lines further from the page behind them. It works on top of whatever colours you have chosen, including your
								own.</span
							>
						</Field>
						<Field title="Page width">
							<Seg
								label="Page width"
								value={ui.prefs.pageWidth}
								onpick={(pageWidth) => ui.update({ pageWidth })}
								options={[
									{ value: 'narrow', label: 'Narrow' },
									{ value: 'wide', label: 'Wide' },
									{ value: 'full', label: 'Full' }
								]}
							/>
						</Field>
						<Field title="Tables">
							<div class="line-switch">
								<span class="note">Shade every other row of long tables.</span>
								<Switch label="Shade every other row" checked={ui.prefs.stripes} onchange={(stripes) => ui.update({ stripes })} />
							</div>
						</Field>
					</section>
				{:else if tab === 'colours'}
					<ThemeEditor base="crisp" />
				{:else}
					<VisionControls base="crisp" />
				{/if}
			</div>
			<footer>
				<button type="button" class="mg-btn primary set-default" disabled={settingDefault} onclick={setDefault}>Set as default in themes and customization</button>
				<div class="foot-line">
					<span class="saved-dot" aria-hidden="true"></span>
					<span class="note">{ui.hasDefault ? 'MARGIE opens with your default look, here and on the HPC.' : 'Changes apply now. Set as default to open with them every time.'}</span>
					{#if ui.hasDefault}<button type="button" class="mg-link" onclick={() => ui.resetToDefault()}>Back to default</button>{/if}
				</div>
			</footer>
		</div>
	{/if}

	{#if preview.vision !== 'typical'}
		<div class="previewing" role="status" transition:fly={{ y: 8, duration: ui.ms(180) }}>
			<Eye size={15} />
			<span>Showing the page as seen with <b>{visionInfo(preview.vision).plain.toLowerCase()}</b></span>
			<button type="button" class="mg-link" onclick={() => (preview.vision = 'typical')}>Turn off</button>
		</div>
	{/if}

	<div class="toasts" aria-live="polite">
		{#each ui.toasts as t (t.id)}
			<div class="toast {t.tone}" transition:fly={{ y: 8, duration: ui.ms(150) }}><span class="toast-dot" aria-hidden="true"></span><span>{t.text}</span></div>
		{/each}
	</div>
</div>

<style>
	.bar {
		position: relative;
		z-index: 5;
		flex-shrink: 0;
		display: flex;
		align-items: stretch;
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
		/* Proportional, so the name follows the reader's text-size setting. */
		font-size: calc(var(--cr-fs-body) * 1.2);
		font-weight: 700;
		letter-spacing: 0.06em;
	}
	.where {
		font-size: var(--cr-fs-meta);
		color: var(--mg-text-3);
	}
	/* The current page, beside the name; the menu holds the rest. */
	.here {
		align-self: center;
		padding-left: 14px;
		border-left: 1px solid var(--mg-border);
		font-size: var(--cr-fs-meta);
		font-weight: 600;
		color: var(--mg-text-2);
	}
	.here:empty {
		display: none;
	}
	.menu {
		margin-left: -6px;
	}
	/* Back, forward and the recent places, beside the name. */
	.hist {
		position: relative;
		align-self: center;
		display: flex;
		align-items: center;
		gap: 2px;
	}
	.hist .icon:disabled {
		opacity: 0.35;
		cursor: default;
	}
	.hist-scrim {
		position: fixed;
		inset: 0;
		z-index: 40;
		border: none;
		background: transparent;
	}
	.hist-menu {
		position: absolute;
		top: calc(100% + 6px);
		left: 0;
		z-index: 41;
		min-width: 260px;
		max-width: 420px;
		margin: 0;
		padding: 6px;
		list-style: none;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		box-shadow: var(--cr-pop-shadow, 0 10px 30px rgb(0 0 0 / 0.14));
	}
	.hist-menu button {
		display: flex;
		align-items: center;
		gap: 8px;
		width: 100%;
		padding: 7px 10px;
		border: none;
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text);
		font: inherit;
		font-size: var(--mg-fs-sm);
		text-align: left;
		cursor: pointer;
	}
	.hist-menu button span {
		flex: 1;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.hist-menu button:hover {
		background: var(--mg-surface-2);
	}
	.hist-menu button.now {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.hist-menu em {
		font-style: normal;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	/* The scroll buttons: small and round, together at the bottom right. */
	.jumps {
		position: fixed;
		right: 18px;
		bottom: 18px;
		z-index: 30;
		display: flex;
		gap: 6px;
		padding: 4px;
		border: 1px solid var(--mg-border);
		border-radius: 999px;
		background: color-mix(in srgb, var(--mg-surface) 92%, transparent);
		box-shadow: 0 4px 14px rgb(0 0 0 / 0.12);
	}
	.jump:disabled {
		opacity: 0.35;
		cursor: default;
	}
	.jump {
		display: grid;
		place-items: center;
		width: 34px;
		height: 34px;
		border: 1px solid var(--mg-border);
		border-radius: 50%;
		background: var(--mg-surface);
		color: var(--mg-text-2);
		cursor: pointer;
	}
	.jump:hover:not(:disabled) {
		border-color: var(--mg-accent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.jump:focus-visible {
		outline: 2px solid var(--mg-accent);
		outline-offset: 2px;
	}
	/* The pages as tabs across the top, the current one underlined in the accent. */
	.toptabs {
		position: relative;
		z-index: 4;
		flex-shrink: 0;
		display: flex;
		justify-content: center;
		gap: 4px;
		height: 42px;
		padding: 0 16px;
		border-bottom: 1px solid var(--mg-border);
		background: var(--mg-surface);
		overflow-x: auto;
		scrollbar-width: none;
	}
	.toptabs a {
		position: relative;
		display: inline-flex;
		align-items: center;
		gap: 7px;
		padding: 0 14px;
		color: var(--mg-text-2);
		font-size: var(--mg-fs-sm);
		white-space: nowrap;
		text-decoration: none;
		transition: color 140ms ease;
	}
	.toptabs a:hover {
		color: var(--mg-text);
	}
	.toptabs a::after {
		content: '';
		position: absolute;
		left: 10px;
		right: 10px;
		bottom: -1px;
		height: 2px;
		border-radius: 2px 2px 0 0;
		background: transparent;
		transition: background-color 140ms ease;
	}
	/* The page you are on wears its own hue, the one its title has. */
	.toptabs a[aria-current='page'] {
		color: var(--tab, var(--mg-accent-ink, var(--mg-accent)));
		font-weight: 500;
	}
	.toptabs a[aria-current='page']::after {
		background: var(--tab, var(--mg-accent));
	}
	.toptabs a:focus-visible {
		outline: 2px solid var(--mg-accent);
		outline-offset: -4px;
		border-radius: var(--mg-r-sm);
	}
	/* Wide: the tabs show the current page, so the menu button and page name are hidden. */
	@media (min-width: 821px) {
		.bar > .menu,
		.bar > .here {
			display: none;
		}
	}
	@media (max-width: 820px) {
		.toptabs {
			display: none;
		}
	}
	/* The side menu of pages, as on the classic pages. */
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
	.grow {
		flex-grow: 1;
	}
	.bar > :is(.running, .icon, .menu) {
		align-self: center;
	}
	/* The job going on, as a pill of its own in the warm colour: its ring,
	   and a line of where it has got to. */
	.running {
		display: flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
		height: 36px;
		padding: 0 14px 0 6px;
		border: 1px solid color-mix(in srgb, var(--cr-warm) 35%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--cr-warm) 8%, var(--mg-surface));
		box-shadow: 0 0 0 0 color-mix(in srgb, var(--cr-warm) 30%, transparent);
		color: var(--mg-text-2);
		font-size: var(--cr-fs-meta);
		font-weight: 500;
		white-space: nowrap;
		transition:
			border-color var(--mo-1) var(--mo-ease),
			color var(--mo-1) var(--mo-ease);
	}
	.crisp[data-motion='off'] .running {
		animation: none;
	}
	.running span {
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.running:hover {
		border-color: var(--cr-warm);
		color: var(--mg-text);
	}
	.icon {
		display: grid;
		place-items: center;
		width: 36px;
		height: 36px;
		flex-shrink: 0;
		border: 1px solid transparent;
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-text-2);
		cursor: pointer;
		transition:
			background-color var(--mo-1) var(--mo-ease),
			color var(--mo-1) var(--mo-ease);
	}
	.icon:hover {
		background: color-mix(in srgb, var(--mg-text) 6%, transparent);
		color: var(--mg-text);
	}
	/* Colour vision is on: its eye sits in the bar as an accent pill. */
	.bar > .icon {
		border-color: color-mix(in srgb, var(--mg-accent-base) 35%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-accent-base) 8%, var(--mg-surface));
		color: var(--mg-accent-ink, var(--mg-accent-base));
	}
	.content {
		view-transition-name: mo-main;
		flex-grow: 1;
		min-height: 0;
		overflow: auto;
		/* Backdrop "Glow": a faint wash of the page's colour behind its head (a Customize choice). */
		background:
			radial-gradient(900px 360px at 8% -120px, color-mix(in srgb, var(--cr-page, var(--mg-accent)) var(--cr-glow), transparent), transparent 72%),
			var(--mg-bg);
		background-attachment: local;
	}
	/* Shades off: no colour square before a block's name. */
	.crisp[data-shades='off'] :global([data-shade] > :is(.mg-card-head, .cr-block-head) h2::before) {
		display: none;
	}

	/* ------------------------------------------------ Customize */
	.scrim {
		position: absolute;
		inset: var(--mg-titlebar, 0px) 0 0 0;
		z-index: 30;
		border: none;
		background: var(--mg-scrim);
		cursor: default;
	}
	/* Sits below the desktop app's title strip (--mg-titlebar), where a click
	   would drag the window instead. */
	.drawer {
		position: absolute;
		top: var(--mg-titlebar, 0px);
		right: 0;
		bottom: 0;
		z-index: 31;
		display: flex;
		flex-direction: column;
		border-left: 1px solid var(--mg-border);
		background: var(--mg-bg);
		box-shadow: var(--cr-pop-shadow);
	}
	.drawer header {
		display: flex;
		align-items: center;
		gap: 10px;
		height: 60px;
		flex-shrink: 0;
		padding: 0 12px 0 18px;
		border-bottom: 1px solid var(--mg-border);
		background: var(--mg-surface);
		color: var(--mg-text-2);
	}
	.drawer-icon {
		display: grid;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--mg-accent-base) 12%, var(--mg-surface));
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--mg-accent-base) 25%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent-base));
	}
	.drawer h2 {
		font-size: var(--cr-fs-section);
		font-weight: 700;
		letter-spacing: -0.01em;
		color: var(--mg-text);
	}
	/* The three parts of Customize as a pill tray, like the page tabs. */
	.tabs {
		position: relative;
		flex-shrink: 0;
		display: flex;
		gap: 2px;
		margin: 14px 18px 0;
		padding: 4px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 4%, var(--mg-surface));
	}
	.tabs button {
		position: relative;
		z-index: 1;
		flex: 1 1 auto;
		min-width: 0;
		height: 32px;
		padding: 0 12px;
		overflow: hidden;
		border: none;
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--cr-fs-meta);
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
		cursor: pointer;
		transition: color var(--mo-1) var(--mo-ease);
	}
	.tabs button:hover {
		color: var(--mg-text);
	}
	.tabs button[aria-selected='true'] {
		background: var(--mg-seg-sel);
		box-shadow:
			var(--mg-shadow-sm),
			0 0 0 1px var(--mg-border);
		color: var(--mg-accent-ink, var(--mg-accent-base));
		font-weight: 600;
	}
	.tabs > :global(.mo-thumb) {
		border-radius: var(--mg-r-sm);
		background: var(--mg-seg-sel);
		box-shadow:
			var(--mg-shadow-sm),
			0 0 0 1px var(--mg-border);
	}
	.tabs:global(.mo-has-thumb) button[aria-selected='true'] {
		box-shadow: none;
	}
	.drawer-body {
		flex-grow: 1;
		min-height: 0;
		overflow: auto;
		display: flex;
		flex-direction: column;
		gap: 16px;
		padding: 16px 18px 20px;
	}
	/* Look: its groups as cards, two abreast once the drawer is widened. */
	.drawer-body.cards {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(300px, 100%), 1fr));
		align-content: start;
	}
	.drawer footer {
		flex-shrink: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		gap: 10px;
		padding: 12px 18px;
		border-top: 1px solid var(--mg-border);
		background: var(--mg-surface);
	}
	.set-default {
		width: 100%;
		justify-content: center;
	}
	.foot-line {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.foot-line .mg-link {
		margin-left: auto;
		flex-shrink: 0;
		font-size: var(--mg-fs-xs);
	}
	.saved-dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: var(--mg-ok);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--mg-ok) 18%, transparent);
	}
	.note {
		font-size: var(--cr-fs-micro);
		color: var(--mg-text-3);
		line-height: 1.45;
	}
	.where {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--cr-fs-meta);
		font-weight: 500;
	}
	.line-switch {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 14px;
	}
	.where-line {
		padding: 6px 6px 6px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 3%, var(--mg-surface));
	}

	/* ------------------------------------------------ notices */
	.previewing {
		position: absolute;
		left: 50%;
		bottom: 20px;
		z-index: 40;
		translate: -50% 0;
		display: flex;
		align-items: center;
		gap: 10px;
		height: 42px;
		padding: 0 8px 0 16px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		box-shadow: var(--cr-pop-shadow);
		font-size: var(--cr-fs-meta);
		white-space: nowrap;
	}
	.previewing :global(svg) {
		color: var(--mg-accent-ink, var(--mg-accent-base));
	}
	.previewing .mg-link {
		height: 30px;
		padding: 0 14px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 6%, transparent);
		color: var(--mg-text);
		font-weight: 600;
	}
	.toasts {
		position: fixed;
		right: 18px;
		bottom: 18px;
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 8px;
		z-index: 50;
		pointer-events: none;
	}
	/* A notice: a rounded card with a dot of its tone. */
	.toast {
		display: flex;
		align-items: center;
		gap: 10px;
		max-width: min(440px, calc(100vw - 36px));
		padding: 10px 16px 10px 14px;
		border: 1px solid var(--mg-border);
		border-radius: calc(var(--mg-r) + 4px);
		background: var(--mg-surface);
		box-shadow: var(--cr-pop-shadow);
		font-size: var(--cr-fs-meta);
		line-height: 1.4;
		overflow-wrap: anywhere;
		pointer-events: auto;
	}
	.toast-dot {
		flex: none;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--mg-accent-base);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--mg-accent-base) 18%, transparent);
	}
	.toast.ok .toast-dot {
		background: var(--mg-ok);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--mg-ok) 18%, transparent);
	}
	.toast.error {
		border-color: color-mix(in srgb, var(--mg-danger) 40%, var(--mg-border));
	}
	.toast.error .toast-dot {
		background: var(--mg-danger);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--mg-danger) 18%, transparent);
	}
	@media (max-width: 980px) {
		.running span {
			display: none;
		}
		.running {
			padding: 0 6px;
		}
	}
	@media (max-width: 820px) {
		.where,
		.here {
			display: none;
		}
	}
	/* The bar stretches its items; these two are buttons of their own height. */
	.bar > :global(.ct),
	.disconnect {
		align-self: center;
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
