<script lang="ts">
	import { ArrowRight, ChartPie, Dna, FolderOpen, ListChecks, Maximize2, Package, Play, SlidersHorizontal, X } from 'lucide-svelte';
	import { clusterParts } from '$lib/workspace/cluster-parts';
	import { backend } from '$lib/workspace/backend.svelte';
	import { uiBase } from '../base.svelte';
	import { ui } from '../ui.svelte';
	import TabPicture from './home/TabPicture.svelte';

	/**
	 * Home page: centred title, motto and start link; what a run does and what comes out; one tile
	 * per tab that opens a sketch card (one at a time, closed by outside click or Escape); README links.
	 */
	const BACKEND = 'https://github.com/sajalbhattarai/margie-backend';
	const FRONTEND = 'https://github.com/sajalbhattarai/margie-frontend';
	const BSP = 'https://github.com/wintermutant/bioinformatics-tools';
	/** Citation target (CITATION.cff in margie-pipeline). */
	const CITE = 'https://github.com/sajalbhattarai/margie-pipeline';

	const TABS = [
		{
			id: 'analyze',
			label: 'Analyze',
			icon: Play,
			to: '',
			points: ['Choose which genomes, and which tools', 'Checks that everything a run needs is installed', 'The evidence grid fills in as each tool finishes']
		},
		{
			id: 'genomes',
			label: 'Genomes',
			icon: Dna,
			to: '/genomes',
			points: ['Drop in assembled genomes (.fa, .fasta, .fna)', 'Give each its domain and genetic code', 'Leave them blank and MARGIE works them out']
		},
		{
			id: 'results',
			label: 'Results',
			icon: ChartPie,
			to: '/results',
			points: ['A genome map, coloured by confidence', 'Every gene: its name, evidence and confidence tier', 'Download the table as Excel or TSV, with the figures']
		},
		{
			id: 'files',
			label: 'Files',
			icon: FolderOpen,
			to: '/files',
			points: ['Your folders on the cluster, or on this computer', 'Open tables, logs, pages and images in place', 'Download any file']
		},
		{
			id: 'jobs',
			label: 'Jobs',
			icon: ListChecks,
			to: '/runs',
			points: ['How far the current run is', 'Stop it, if you need to', 'Its full log, and why a run failed']
		},
		{
			id: 'install',
			label: 'Install',
			icon: Package,
			to: '/setup',
			points: ['Tool containers and their reference databases', 'Install or point to what is missing', 'Accept the tools’ licences']
		},
		{
			id: 'settings',
			label: 'Settings',
			icon: SlidersHorizontal,
			to: '/settings',
			points: ['Cores, memory and time for each step', 'Where genomes come from and results go', 'Optional steps, on or off']
		}
	] as const;

	/** Run steps in order: gene caller, then the tools. */
	const ORDER = [
		{ title: 'Find the genes', text: 'The gene caller marks every protein-coding gene in the genome.' },
		{ title: 'Read each protein', text: 'The annotation tools compare every protein with their reference databases.' },
		{ title: 'Weigh the evidence', text: 'Genes are grouped into operons, and each gets a name and a confidence tier.' }
	];

	let open = $state<string | null>(null);
	/** Whether the "What comes out" map is full screen. */
	let full = $state(false);
	const mapSrc = $derived(ui.dark ? '/home/genome-map-dark.webp' : '/home/genome-map.jpg');
	/** Moves the full-screen map to the interface root so it covers the whole window. */
	function toRoot(node: HTMLElement) {
		(node.closest('[data-mg-root]') ?? document.body).appendChild(node);
		return { destroy: () => node.remove() };
	}
	const shown = $derived(TABS.find((t) => t.id === open));
	const toggle = (id: string) => (open = open === id ? null : id);

	/** Closes the open card on a click outside the tiles and the card. */
	function outside(e: MouseEvent) {
		if (open && !(e.target as Element | null)?.closest?.('[data-home-keep]')) open = null;
	}
</script>

<svelte:window
	onclick={outside}
	onkeydown={(e) => {
		if (e.key !== 'Escape') return;
		if (full) full = false;
		else open = null;
	}}
/>

<div class="home">
	<section class="hero">
		<p class="house">
			A Snakemake pipeline in the <a href={BSP} target="_blank" rel="noreferrer">Bioinformatics Supercomputing Platform</a> (BSP)
		</p>
		<h1><img class="logo" src="/home/margie-logo.png" alt="MARGIE" width="232" height="232" /></h1>
		<p class="full">Mostly Automated Rapid Genome Inference Environment</p>
		<p class="motto">Annotate with confidence: a genome-centric, context-dependent approach</p>
		<div class="cta">
			<a class="pill primary" href={uiBase.path}><Play size={15} /> Start annotating</a>
			<a class="pill" href={uiBase.to('/genomes')}>Add genomes</a>
			<a class="pill" href={uiBase.to('/results')}>See results</a>
		</div>
	</section>

	<section class="run">
		<div class="card run-steps">
			<h2>What a run does</h2>
			<ol class="order">
				{#each ORDER as o, i (o.title)}
					<li>
						<span class="num">{i + 1}</span>
						<span class="step"><strong>{o.title}</strong><span>{o.text}</span></span>
					</li>
				{/each}
			</ol>
		</div>
		<figure class="card run-fig">
			<h2>What comes out</h2>
			<button type="button" class="map-btn" aria-label="Show the map full screen" title="Full screen" onclick={() => (full = true)}>
				<img src={mapSrc} alt="Circular genome map of Sedimenticola thiotaurini, coloured by operon" loading="eager" />
				<span class="zoom" aria-hidden="true"><Maximize2 size={15} /></span>
			</button>
			<figcaption>A map of each genome, coloured by operon, with a report on every gene.</figcaption>
		</figure>
	</section>

	<section class="guide" aria-labelledby="guide-title">
		<header class="sec-head">
			<h2 id="guide-title">What each tab does</h2>
		</header>
		<div class="tabs" role="group" aria-label="What each tab does" data-home-keep>
			{#each TABS as t (t.id)}
				<button type="button" class="tab" aria-expanded={open === t.id} aria-controls="home-card" onclick={() => toggle(t.id)}>
					<span class="tab-label">{t.label}</span>
				</button>
			{/each}
		</div>

		{#if shown}
			<div id="home-card" class="card stage" data-home-keep>
				{#key shown.id}
					<div class="card-in">
						<div class="picture"><TabPicture tab={shown.id} /></div>
						<div class="words">
							<h3><span class="tab-ic"><shown.icon size={19} strokeWidth={2} /></span> {shown.label}</h3>
							<ol class="points">
								{#each shown.points as p, i (p)}
									<li style="--i: {i}"><span class="num">{i + 1}</span>{p}</li>
								{/each}
							</ol>
							<a class="pill primary go" href={uiBase.to(shown.to)}>Open {shown.label} <ArrowRight size={15} /></a>
						</div>
						<button type="button" class="close" aria-label="Close" onclick={() => (open = null)}><X size={16} /></button>
					</div>
				{/key}
			</div>
		{/if}
	</section>

	{#if full}
		<div class="lightbox" role="dialog" aria-modal="true" aria-label="Genome map, full screen" use:toRoot>
			<button type="button" class="lb-back" aria-label="Close" onclick={() => (full = false)}></button>
			<img src={mapSrc} alt="Circular genome map of Sedimenticola thiotaurini, coloured by operon" />
			<button type="button" class="close lb-close" aria-label="Close" onclick={() => (full = false)}><X size={18} /></button>
		</div>
	{/if}

	{#if clusterParts.Compute}
		<section class="hpc-note" aria-labelledby="hpc-note-t">
			<h2 id="hpc-note-t">On an HPC: where MARGIE works</h2>
			<div class="hpc-cols">
				<p>
					<b>Login node</b> (the default). Browsing, the genome maps and chat run on the node you signed in to, and annotation runs go to SLURM.
					It starts at once, but the node is shared: large interactive maps and copies there leave less for other users.
				</p>
				<p>
					<b>Compute node.</b> Choose it with the <i>Login node / Compute node</i> button at the top, next to Customize, to run MARGIE's server as
					a SLURM job with the cores and memory you set. The job may wait in the queue; MARGIE shows why, and asks whether to use the login node
					meanwhile.
					{#if !backend.cluster}
						The button appears once you are connected to an HPC{#if clusterParts.switchHref}: <a class="mg-link" href={clusterParts.switchHref}>connect</a>{/if}.
					{/if}
				</p>
				<p>
					<b>Copies</b>, such as reference data the first time or a backup, go to SLURM when an account is set. What may run on login nodes
					depends on your institution: follow its policies.
				</p>
			</div>
		</section>
	{/if}

	<footer class="foot">
		<p>
			MARGIE is a Snakemake pipeline housed, among other tools, within the Bioinformatics Supercomputing Platform (BSP) developed by
			Dane Deemer. For BSP's other features, see the
			<a class="mg-link" href={BSP} target="_blank" rel="noreferrer">Bioinformatics Supercomputing Platform</a>.
		</p>
		<div class="cite">
			<span class="cite-t">How to cite</span>
			<p>
				Bhattarai S, Deemer D, Lindemann SR. <i>MARGIE: Mostly Automated Rapid Genome Inference Environment.</i> Purdue University. Software,
				MIT licence. <a class="mg-link" href={CITE} target="_blank" rel="noreferrer">github.com/sajalbhattarai/margie-pipeline</a>
			</p>
			<p class="cite-note">Please also cite each tool and database MARGIE runs; they are listed in the README.</p>
		</div>
		<p class="links">
			<a class="pill small" href={BACKEND} target="_blank" rel="noreferrer">Backend</a>
			<a class="pill small" href={FRONTEND} target="_blank" rel="noreferrer">Frontend</a>
		</p>
	</footer>
</div>

<style>
	.home {
		display: flex;
		flex-direction: column;
		gap: calc(var(--cr-gutter, 24px) * 1.25);
		width: 100%;
		max-width: var(--cr-width, none);
		margin: 0 auto;
		padding: var(--cr-gutter, 24px) var(--cr-gutter, 24px) calc(var(--cr-gutter, 24px) * 2.5);
		color: var(--mg-text);
	}
	h1 {
		margin: 0;
		font-size: calc(var(--mg-fs) * 2.2);
		font-weight: 700;
		line-height: 1.18;
		letter-spacing: -0.02em;
	}
	h2 {
		margin: 0;
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	p {
		margin: 0;
		line-height: 1.55;
	}

	/* ---- shared shapes ---- */
	.hero,
	.card,
	.tab {
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow, none);
	}
	.tab-ic {
		flex: none;
		display: grid;
		place-items: center;
		width: 38px;
		height: 38px;
		border-radius: 12px;
		background: color-mix(in srgb, var(--mg-accent) 13%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.num {
		flex: none;
		width: 22px;
		height: 22px;
		border-radius: 50%;
		display: grid;
		place-items: center;
		font-size: 11px;
		font-weight: 700;
		background: color-mix(in srgb, var(--mg-accent) 16%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.pill {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		height: calc(var(--mg-ctl, 36px) * 1.2);
		padding: 0 20px;
		border: 1px solid color-mix(in srgb, var(--mg-accent) 40%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-accent-ink, var(--mg-accent));
		font-weight: 600;
		transition:
			transform 160ms ease,
			box-shadow 160ms ease,
			background-color 160ms ease;
	}
	.pill:hover {
		background: color-mix(in srgb, var(--mg-accent) 8%, var(--mg-surface));
	}
	.pill.primary {
		border-color: transparent;
		background: var(--mg-accent);
		color: var(--mg-on-accent, #fff);
		box-shadow: none;
	}
	.pill.primary:hover {
		box-shadow: none;
	}
	.pill.small {
		height: 30px;
		padding: 0 14px;
		font-size: var(--mg-fs-sm);
	}

	/* ---- hero ---- */
	.hero {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 12px;
		padding: calc(var(--mg-gap) * 3.5) calc(var(--mg-gap) * 2.5);
		text-align: center;
	}
	.house {
		font-size: var(--mg-fs-xs);
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.house a {
		color: var(--mg-text-2);
		text-decoration: underline;
		text-decoration-color: var(--mg-border-strong);
		text-underline-offset: 3px;
	}
	.house a:hover {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.hero .logo {
		display: block;
		width: clamp(160px, 18vw, 232px);
		height: auto;
		animation: logo-in calc(700ms * var(--mo-speed, 1)) cubic-bezier(0.2, 0.7, 0.2, 1) both;
	}
	@keyframes logo-in {
		from {
			opacity: 0;
			transform: scale(0.94) rotate(-8deg);
		}
	}
	:global([data-motion='off']) .hero .logo {
		animation: none;
	}
	.hero h1 {
		font-size: calc(var(--mg-fs) * 3.6);
		line-height: 1;
		letter-spacing: 0.04em;
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.full {
		font-size: calc(var(--mg-fs) * 1.25);
		font-weight: 600;
	}
	.motto {
		max-width: 64ch;
		font-size: calc(var(--mg-fs) * 1.1);
		color: var(--mg-text-2);
	}
	.cta {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: 10px;
		margin-top: 14px;
	}

	/* ---- a run: two halves ---- */
	.run {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: calc(var(--cr-gutter, 24px) * 1.25);
	}
	.run-steps,
	.run-fig {
		display: flex;
		flex-direction: column;
		gap: 16px;
		margin: 0;
		padding: calc(var(--mg-gap) * 2);
	}
	.run h2 {
		text-align: center;
	}
	.order {
		flex: 1;
		display: flex;
		flex-direction: column;
		justify-content: center;
		gap: 10px;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.order li {
		display: flex;
		align-items: flex-start;
		gap: 12px;
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm, 8px);
		background: var(--mg-surface);
	}
	.order .num {
		width: 24px;
		height: 24px;
	}
	.step {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.step strong {
		font-weight: 650;
	}
	.step span {
		font-size: var(--mg-fs-xs);
		line-height: 1.45;
		color: var(--mg-text-2);
	}
	/* Map image multiplied into the card; dark theme uses its own transparent version. */
	.run-fig img {
		display: block;
		width: 100%;
		max-width: 540px;
		height: auto;
		margin: 0 auto;
		mix-blend-mode: multiply;
	}
	:global([data-theme='dark']) .run-fig img {
		mix-blend-mode: normal;
	}
	/* Full-screen map: a corner button, and the whole map clickable. */
	.map-btn {
		position: relative;
		display: block;
		width: 100%;
		max-width: 540px;
		margin: 0 auto;
		padding: 0;
		border: none;
		background: none;
		cursor: zoom-in;
	}
	.map-btn .zoom {
		position: absolute;
		top: 6px;
		right: 6px;
		display: grid;
		place-items: center;
		width: 30px;
		height: 30px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-text-2);
		opacity: 0.85;
		transition: opacity 140ms ease;
	}
	.map-btn:hover .zoom,
	.map-btn:focus-visible .zoom {
		opacity: 1;
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.map-btn:focus-visible {
		outline: 2px solid var(--mg-accent);
		outline-offset: 4px;
		border-radius: var(--mg-r-sm);
	}
	.lightbox {
		position: fixed;
		inset: 0;
		z-index: 50;
		display: grid;
		place-items: center;
		padding: calc(var(--mg-titlebar, 0px) + 24px) 24px 24px;
		animation: fade 180ms ease-out both;
	}
	.lb-back {
		position: absolute;
		inset: 0;
		border: none;
		background: var(--mg-bg);
		cursor: zoom-out;
	}
	/* Fits the whole map in the window. */
	.lightbox img {
		position: relative;
		width: auto;
		height: auto;
		max-width: calc(100vw - 64px);
		max-height: calc(100vh - var(--mg-titlebar, 0px) - 64px);
		object-fit: contain;
		border-radius: var(--mg-r-sm);
		box-shadow: 0 10px 40px rgb(0 0 0 / 0.18);
		background: var(--mg-surface);
	}
	.lb-close {
		top: calc(var(--mg-titlebar, 0px) + 16px);
		right: 16px;
		position: absolute;
	}
	figcaption {
		text-align: center;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-3);
	}

	/* ---- tab tiles ---- */
	.guide {
		display: flex;
		flex-direction: column;
		gap: 14px;
	}
	.sec-head {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		text-align: center;
	}
	.tabs {
		display: grid;
		grid-template-columns: repeat(7, minmax(0, 1fr));
		gap: 12px;
	}
	.tab {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		min-width: 0;
		height: 44px;
		padding: 0 10px;
		color: var(--mg-text);
		font: inherit;
		text-align: center;
		cursor: pointer;
		transition:
			border-color 160ms,
			background 160ms,
			transform 160ms,
			box-shadow 160ms;
	}
	.tab-label {
		font-weight: 500;
	}
	.tab:hover {
		border-color: var(--mg-border-strong);
	}
	.tab[aria-expanded='true'] {
		border-color: var(--mg-accent);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--mg-accent) 18%, transparent);
	}
	.tab:focus-visible,
	.close:focus-visible {
		outline: 2px solid var(--mg-accent);
		outline-offset: 2px;
	}

	/* ---- open card ---- */
	.card {
		position: relative;
	}
	/* Faint accent glow behind. */
	.stage {
		color: var(--mg-text);
		background: var(--cr-card, var(--mg-surface));
	}
	.card-in {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: calc(var(--mg-gap) * 2);
		align-items: center;
		padding: calc(var(--mg-gap) * 1.5) calc(var(--mg-gap) * 2);
		animation: fade 220ms ease-out both;
	}
	.picture {
		width: 100%;
		max-width: 420px;
		justify-self: center;
	}
	.words {
		display: flex;
		flex-direction: column;
		gap: 12px;
		max-width: 460px;
	}
	h3 {
		display: flex;
		align-items: center;
		gap: 10px;
		margin: 0;
		font-size: calc(var(--mg-fs) * 1.15);
		font-weight: 600;
	}
	.points {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.points li {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 7px 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm, 8px);
		background: var(--mg-surface);
		font-size: var(--mg-fs-sm);
		animation: rise 260ms ease-out both;
		animation-delay: calc(60ms + var(--i) * 50ms);
	}
	.go {
		align-self: flex-start;
	}
	.close {
		position: absolute;
		top: 12px;
		right: 12px;
		display: grid;
		place-items: center;
		width: 32px;
		height: 32px;
		border: 1px solid var(--mg-border);
		border-radius: 50%;
		background: var(--mg-surface);
		color: var(--mg-text-2);
		cursor: pointer;
	}
	.close:hover {
		border-color: var(--mg-border-strong);
		color: var(--mg-text);
	}

	/* ---- on an HPC ---- */
	.hpc-note {
		display: flex;
		flex-direction: column;
		gap: 10px;
		margin-bottom: calc(var(--mg-gap) * 2);
		padding: 14px 18px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface-2));
	}
	.hpc-note h2 {
		font-size: var(--mg-fs);
		font-weight: 500;
		text-transform: none;
		letter-spacing: 0;
		color: var(--cr-t2, var(--mg-text));
	}
	.hpc-cols {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 18px;
		color: var(--mg-text-2);
	}
	.hpc-cols b {
		font-weight: 500;
		color: var(--mg-text);
	}
	@media (max-width: 900px) {
		.hpc-cols {
			grid-template-columns: minmax(0, 1fr);
		}
	}

	/* ---- foot ---- */
	.foot {
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: 12px 24px;
		padding-top: var(--mg-gap);
		border-top: 1px solid var(--mg-border);
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.foot p {
		max-width: 80ch;
	}
	.links {
		display: flex;
		gap: 10px;
	}
	/* Citation, set apart for copying. */
	.cite {
		display: flex;
		flex-direction: column;
		gap: 6px;
		max-width: 80ch;
		margin-bottom: calc(var(--mg-gap) * 2);
		padding: 12px 18px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface-2));
		text-align: left;
		user-select: text;
	}
	.cite-t {
		font-size: var(--mg-fs-xs);
		color: var(--cr-t3, var(--mg-text-3));
	}
	.cite p {
		color: var(--mg-text);
	}
	.cite .cite-note {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}

	/* Opening animation, skipped when motion is off. */
	@keyframes fade {
		from {
			opacity: 0;
		}
	}
	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(4px);
		}
	}
	:global([data-motion='off']) .home * {
		animation: none !important;
	}

	@media (max-width: 980px) {
		.run,
		.card-in {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	/* Seven tiles in two rows: four, then three wider. */
	@media (max-width: 760px) {
		.tabs {
			grid-template-columns: repeat(12, minmax(0, 1fr));
			gap: 8px;
		}
		.tab {
			grid-column: span 3;
			padding: 12px 4px;
		}
		.tab:nth-child(n + 5) {
			grid-column: span 4;
		}
		.tab-label {
			font-size: var(--mg-fs-sm);
		}
		.hero {
			padding: calc(var(--mg-gap) * 2) calc(var(--mg-gap) * 1.5);
		}
	}
	@media (max-width: 520px) {
		.house {
		font-size: var(--mg-fs-xs);
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.house a {
		color: var(--mg-text-2);
		text-decoration: underline;
		text-decoration-color: var(--mg-border-strong);
		text-underline-offset: 3px;
	}
	.house a:hover {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.hero .logo {
		display: block;
		width: clamp(160px, 18vw, 232px);
		height: auto;
		animation: logo-in calc(700ms * var(--mo-speed, 1)) cubic-bezier(0.2, 0.7, 0.2, 1) both;
	}
	@keyframes logo-in {
		from {
			opacity: 0;
			transform: scale(0.94) rotate(-8deg);
		}
	}
	:global([data-motion='off']) .hero .logo {
		animation: none;
	}
	.hero h1 {
			font-size: calc(var(--mg-fs) * 2.6);
		}
		.full {
			font-size: var(--mg-fs);
		}
		.tab-ic {
			width: 32px;
			height: 32px;
		}
		.card-in {
			padding: calc(var(--mg-gap) * 1.25);
		}
		.cta {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.cta .primary {
			grid-column: 1 / -1;
		}
	}
</style>
