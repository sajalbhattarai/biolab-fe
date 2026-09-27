<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { Bot, Check, Copy, Download, FileSpreadsheet, FolderOpen } from 'lucide-svelte';
	import GenomeChat from '$lib/crisp/GenomeChat.svelte';
	import { chatGet } from '$lib/workspace/chat-api';
	import { cubicOut } from 'svelte/easing';
	import { fly } from 'svelte/transition';
	import { api, fileUrl } from '$lib/api';
	import CountUp from '$lib/crisp/CountUp.svelte';
	import ResultsRing from '$lib/crisp/ResultsRing.svelte';
	import FolderView, { type FolderRoot } from '$lib/workspace/FolderView.svelte';
	import { uiBase } from '$lib/workspace/base.svelte';
	import { ws, type GenomeSummary } from '$lib/workspace/data.svelte';
	import { GLYPH_TIERS } from '$lib/workspace/final-summary';
	import { count, figureTitle } from '$lib/workspace/format';
	import Resizer from '$lib/workspace/motion/Resizer.svelte';
	import { thumb } from '$lib/workspace/motion/thumb';
	import { callerName, methodsFor, methodsText } from '$lib/workspace/report';
	import { ui } from '$lib/workspace/ui.svelte';
	import DataGrid from '$lib/workspace/viewers/DataGrid.svelte';
	import HtmlViewer from '$lib/workspace/viewers/HtmlViewer.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import ImageViewer from '$lib/workspace/viewers/ImageViewer.svelte';

	/**
	 * Modern's Results page: a head row (name, facts, tabs, downloads), a line of
	 * key numbers and the confidence bar with Details, and the selected tab filling
	 * the rest of the window.
	 */

	type Tab = 'map' | 'table' | 'figures' | 'methods' | 'files';
	const DETAILS = 'results:details';
	/*
	 * Answers the genome viewer's request (from a frame on this page) for the chat
	 * about its gene: the questions and answers naming its feature id, peg number,
	 * gene id or product.
	 */
	type ChatTurn = { role: 'user' | 'assistant'; text: string; at: string; model?: string; evidence?: { id: string; kind: string; path: string; detail: string }[] };
	function aiAbout(history: ChatTurn[], d: { fid?: string; gene?: string; product?: string }): string {
		// Feature id in full and short (peg.686), gene id, and product name.
		const keys = [d.fid, d.fid?.match(/[a-z]+\.\d+$/i)?.[0], d.gene, (d.product ?? '').length > 6 ? d.product : '']
			.filter((k): k is string => !!k)
			.map((k) => new RegExp(`${k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![0-9])`, 'i'));
		const pairs: [ChatTurn, ChatTurn | undefined][] = [];
		history.forEach((t, i) => t.role === 'user' && pairs.push([t, history[i + 1]?.role === 'assistant' ? history[i + 1] : undefined]));
		const about = pairs.filter(([q, a]) => keys.some((k) => k.test(`${q.text}\n${a?.text ?? ''}`)));
		if (!about.length) return pairs.length ? `The genome's AI conversation (${pairs.length} question${pairs.length === 1 ? '' : 's'}) does not mention this gene.` : '';
		return about
			.map(([q, a]) =>
				[
					`Question (${new Date(q.at).toLocaleString()}): ${q.text}`,
					'',
					`Answer${a?.model ? ` (${a.model})` : ''}:`,
					a?.text ?? '(no answer)',
					...(a?.evidence?.length ? ['', 'Evidence the AI read:', ...a.evidence.map((e) => `  [${e.id}] ${e.kind} ${e.path} (${e.detail})`)] : [])
				].join('\n')
			)
			.join('\n\n=====x====x====\n\n');
	}
	/** What the genome viewer says is open: its view, its colouring, and the gene, operon or contig selected. */
	type ViewerSel = { view?: string; mode?: string; sel?: { kind: string; id: string; label?: string; contig?: string; operon?: string } | null };
	let viewerSel = $state<ViewerSel | null>(null);
	$effect(() => {
		void selected;
		viewerSel = null;
	});
	/** Chat with the genome's "in view": the tab, the Show choice, and in the map what the viewer has open. */
	const chatContext = $derived.by(() => {
		if (!summary) return '';
		const parts = [`${TABS.find((t) => t.id === tab)?.label ?? tab} tab`];
		if (show !== 'all') parts.push(`showing ${SHOWS.find((x) => x.id === show)?.label.toLowerCase()} genes`);
		if (tab === 'map' && viewerSel) {
			const view = { circ: 'circular view', lin: 'linear view', ctg: 'contigs view' }[viewerSel.view ?? ''] ?? '';
			if (view) parts.push(`${view}${viewerSel.mode ? `, ${viewerSel.mode} colouring` : ''}`);
			const x = viewerSel.sel;
			if (x?.kind === 'gene') parts.push(`gene ${x.id}${x.label ? ` (${x.label})` : ''}${x.contig ? `, contig ${x.contig}` : ''}${x.operon ? `, ${x.operon}` : ', singleton'}`);
			else if (x?.kind === 'operon') parts.push(`operon ${x.id}${x.label ? ` (${x.label})` : ''}`);
			else if (x?.kind === 'contig') parts.push(`contig ${x.id}${x.label ? ` (${x.label})` : ''}`);
		}
		if (tab === 'figures' && summary.figures.length) {
			const f = summary.figures.includes(figure) ? figure : summary.figures[0];
			parts.push(`figure ${summary.figures.indexOf(f) + 1}: ${figureTitle(f)}`);
		}
		return parts.join(' | ');
	});

	$effect(() => {
		const on = async (e: MessageEvent) => {
			const d = e.data;
			if (!d || !e.source || (d.margie !== 'ai-for-gene' && d.margie !== 'selection')) return;
			if (![...document.querySelectorAll('iframe')].some((f) => f.contentWindow === e.source)) return;
			if (d.margie === 'selection') {
				viewerSel = { view: String(d.view ?? ''), mode: String(d.mode ?? ''), sel: d.sel ?? null };
				return;
			}
			let text = '';
			const genome = summary?.genome ?? String(d.genome ?? '');
			try {
				const r = await chatGet<{ history: ChatTurn[] }>(genome);
				text = aiAbout(r.history ?? [], d);
			} catch {
				// no chat here (a cluster, or none yet): the report goes without it
			}
			(e.source as Window).postMessage({ margie: 'ai-text', id: d.id, text }, '*');
		};
		addEventListener('message', on);
		return () => removeEventListener('message', on);
	});

	/*
	 * Full screen: only the map and (when open) the chat, with a slim bar for the
	 * name, the chat and the way out.
	 */
	let board = $state<HTMLElement | null>(null);
	let full = $state(false);
	async function toggleFull() {
		if (document.fullscreenElement) await document.exitFullscreen().catch(() => {});
		else await board?.requestFullscreen().catch(() => {});
	}

	/** The chat beside the report: open or not, remembered like the list. */
	const CHAT = 'results:chat-open';
	/** On the cluster: the genome's map made again with the viewer the backend has now (maps from earlier runs lack newer features). */
	let remaking = $state(false);
	let mapVersion = $state(0);
	async function remakeMap(viewer: string) {
		remaking = true;
		try {
			await api('/results/refresh-map', { method: 'POST', body: JSON.stringify({ folder: viewer.slice(0, viewer.lastIndexOf('/')).replace(/\/scoring$/, '') }) });
			mapVersion = Date.now();
			ui.notify('The map was made again with the current viewer.', 'ok');
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		} finally {
			remaking = false;
		}
	}
		const chatOpen = $derived(!ui.isFolded(CHAT, true));
	const TABS: { id: Tab; label: string }[] = [
		{ id: 'map', label: 'Map' },
		{ id: 'table', label: 'Table' },
		{ id: 'figures', label: 'Figures' },
		{ id: 'methods', label: 'Methods' },
		{ id: 'files', label: 'Files' }
	];
	const NAMED = GLYPH_TIERS.slice(0, 5);

	const running = $derived(ws.progress?.genomes.find((g) => g.state === 'running')?.name ?? '');
	const rows = $derived([
		...ws.finished.map((r) => ({ name: r.organism, state: r.organism === running ? 'running' : 'done' })),
		...(running && !ws.finished.some((r) => r.organism === running) ? [{ name: running, state: 'running' }] : []),
		...ws.results.filter((r) => !r.final?.table && r.organism !== running).map((r) => ({ name: r.organism, state: 'partial' }))
	]);
	/** ?folder shows the whole results folder; with nothing to pick it is the default. */
	const whole = $derived(page.url.searchParams.has('folder') || (!page.url.searchParams.get('g') && !rows.length));
	const selected = $derived(whole ? '' : (page.url.searchParams.get('g') ?? rows[0]?.name ?? ''));
	const selectedRow = $derived(rows.find((r) => r.name === selected));

	/** The results folder, and the per-genome folder when it lives elsewhere. */
	const wholeRoots = $derived.by((): FolderRoot[] => {
		const { outputRoot, genomesDir } = ws.resultRoots;
		if (!outputRoot) return [];
		const inside = genomesDir === outputRoot || genomesDir.startsWith(outputRoot + '/');
		return [{ label: 'Results', path: outputRoot }, ...(genomesDir && !inside ? [{ label: 'Per-genome results', path: genomesDir }] : [])];
	});

	/** A genome's own results folder and each tool's folder for it, as far as the run has got. */
	function genomeRoots(g: string): FolderRoot[] {
		const r = ws.results.find((x) => x.organism === g);
		return [...(r?.folder ? [{ label: 'Genome results', path: r.folder }] : []), ...(r?.tools ?? []).map((t) => ({ label: t.tool, path: t.path }))];
	}

	let summary = $state<GenomeSummary | null>(null);
	let loading = $state(false);
	/** The tab is in the address, so Back from a file returns to it. */
	const tab = $derived<Tab>(TABS.some((t) => t.id === page.url.searchParams.get('tab')) ? (page.url.searchParams.get('tab') as Tab) : 'map');
	/*
	 * Which genes to show, across the map and the table: all of them (the
	 * default), one confidence tier, the non-coding ones, those flagged for
	 * review, or those in or out of operons. Kept in the address with the tab.
	 */
	type Show = 'all' | 'highest' | 'high' | 'medium' | 'fair' | 'low' | 'noncoding' | 'flagged' | 'operonic' | 'nonoperonic';
	const SHOWS: { id: Show; label: string; tier?: number }[] = [
		{ id: 'all', label: 'All' },
		{ id: 'highest', label: 'Highest', tier: 0 },
		{ id: 'high', label: 'High', tier: 1 },
		{ id: 'medium', label: 'Medium', tier: 2 },
		{ id: 'fair', label: 'Fair', tier: 3 },
		{ id: 'low', label: 'Low', tier: 4 },
		{ id: 'noncoding', label: 'Non-coding', tier: 5 },
		{ id: 'flagged', label: 'Flagged' },
		{ id: 'operonic', label: 'In operons' },
		{ id: 'nonoperonic', label: 'Not in operons' }
	];
	const show = $derived<Show>((SHOWS.find((x) => x.id === page.url.searchParams.get('show'))?.id ?? 'all') as Show);
	const address = (t: Tab, s: Show) => `?g=${encodeURIComponent(selected)}&tab=${t}${s === 'all' ? '' : `&show=${s}`}`;
	const setTab = (t: Tab) => goto(address(t, show), { replaceState: true, noScroll: true, keepFocus: true });
	const setShow = (s: Show) => goto(address(tab, s), { replaceState: true, noScroll: true, keepFocus: true });
	/** The report table's filter for the choice: which column holds what. */
	const preset = $derived.by((): { column: string; value: string }[] => {
		if (show === 'all') return [];
		if (show === 'noncoding') return [{ column: 'CONFIDENCE_TIER', value: 'NOT_APPLICABLE_NON_CODING' }];
		if (show === 'flagged') return [{ column: 'NEEDS_REVIEW?', value: 'yes' }];
		if (show === 'operonic') return [{ column: 'IS_IN_OPERON?', value: 'yes' }];
		if (show === 'nonoperonic') return [{ column: 'IS_IN_OPERON?', value: 'no' }];
		return [{ column: 'CONFIDENCE_TIER', value: show }];
	});
	let copied = $state(false);
	let figure = $state('');
	const listShut = $derived(ui.isFolded('app:results-list'));
	const tabIn = (node: Element) => fly(node, { y: ui.motion === 'full' ? 8 : 4, duration: ui.ms(260), easing: cubicOut });

	$effect(() => {
		const g = selected;
		const finished = ws.finished.some((r) => r.organism === g);
		summary = null;
		if (!g || !finished) return;
		loading = true;
		ws.loadSummary(g).then((s) => {
			if (selected !== g) return;
			summary = s;
			loading = false;
		});
	});

	$effect(() => {
		for (const r of ws.finished.slice(0, 30)) ws.loadSummary(r.organism);
	});

	const caller = $derived(summary ? callerName(summary) : '');
	const circular = $derived(summary?.figures.find((f) => /_circular\.png$/i.test(f)));
	const methods = $derived(summary ? methodsFor(summary) : { text: '', refs: [] as string[] });
	/** Viewers that scroll and zoom themselves get a tall pane; notes and folders take what they need. */
	const fills = $derived(
		!!summary &&
			((tab === 'map' && !!(summary.final.viewer || circular)) || (tab === 'table' && !!summary.final.table) || (tab === 'figures' && summary.figures.length > 0))
	);

	/** Every tier the table names, highest first; any other label (none, not applicable…) in the no-tier colour. */
	const tierRows = $derived.by(() => {
		if (!summary) return [];
		const t = summary.tiers;
		const named = NAMED.map((name, i) => ({
			key: name,
			name,
			n: Object.entries(t).reduce((a, [k, n]) => a + (k.toLowerCase() === name ? n : 0), 0),
			tier: i
		}));
		const other = Object.entries(t)
			.filter(([k]) => !NAMED.includes(k.toLowerCase()))
			.map(([k, n]) => ({ key: k, name: /^none$/i.test(k) ? 'no tier' : k.replace(/_/g, ' ').toLowerCase(), n, tier: 5 }));
		return [...named, ...other].filter((r) => r.n > 0);
	});
	const tierTotal = $derived(tierRows.reduce((a, r) => a + r.n, 0) || 1);

	const pct = (n: number, of: number) => (of ? Math.round((n / of) * 100) : 0);
	/** How many genes a Show choice holds, where the summary says (null where it does not). */
	function showCount(s: Show): number | null {
		if (!summary) return null;
		const nonCoding = tierRows.filter((r) => /non.?coding/i.test(r.key)).reduce((a, r) => a + r.n, 0);
		if (s === 'all') return summary.genes;
		if (s === 'noncoding') return nonCoding;
		if (s === 'operonic') return summary.inOperons;
		if (s === 'nonoperonic') return Math.max(0, summary.genes - summary.inOperons - nonCoding);
		if (s === 'flagged') return null;
		return tierRows.find((r) => r.key === s)?.n ?? 0;
	}
	/** 4.6 Mb, 812 kb. */
	function size(bp: number): string {
		if (bp >= 1e6) return `${(bp / 1e6).toFixed(bp >= 1e7 ? 1 : 2)} Mb`;
		if (bp >= 1e3) return `${Math.round(bp / 1e3)} kb`;
		return `${bp} bp`;
	}

	async function copyMethods() {
		try {
			await navigator.clipboard.writeText(methodsText(methods));
			copied = true;
			setTimeout(() => (copied = false), 2000);
		} catch {
			ui.notify('Could not copy. Select the text instead.', 'error');
		}
	}

	/** A run that only calls genes writes no report, however far it gets. */
	const genesOnly = $derived(!!ws.active && ws.active.kind === 'annotate' && ws.active.args.includes('--genes-only'));

	function sub(name: string, state: string) {
		if (state === 'running') return genesOnly ? 'gene calls' : 'running';
		if (state === 'partial') return genesOnly ? 'gene calls only' : ws.active?.kind === 'annotate' ? 'in progress' : 'not finished';
		const s = ws.summaries[name];
		return s ? `${count(s.genes)} genes` : '';
	}
	const ringState = (state: string) => (state === 'running' ? 'running' : state === 'done' ? 'done' : 'pending');
</script>

<svelte:document onfullscreenchange={() => (full = !!board && document.fullscreenElement === board)} />

<div class="rb" class:full bind:this={board}>
	<aside class="rb-side" class:shut={listShut} style="--w: {listShut ? 44 : ui.size('app:results-list', 220)}px">
		<div class="rb-side-head">
			<span class="rb-side-title">Genomes <b>{rows.length}</b></span>
			<button
				type="button"
				class="rb-fold"
				aria-expanded={!listShut}
				aria-label={listShut ? 'Show the genome list' : 'Hide the genome list'}
				title={listShut ? 'Show the list' : 'Hide the list'}
				onclick={() => ui.toggleFold('app:results-list')}
			>
				<svg viewBox="0 0 16 16" aria-hidden="true" class:flip={listShut}><path d="M10 4 6 8l4 4" /></svg>
			</button>
		</div>
		<nav class="rb-list" aria-label="Genomes with results" inert={listShut}>
			<a class="rb-row" href="?folder" aria-current={whole ? 'page' : undefined} data-sveltekit-replacestate data-sveltekit-noscroll>
				<span class="rb-row-icon" aria-hidden="true"><FolderOpen size={15} /></span>
				<span class="rb-row-text">
					<span class="rb-row-name">Results folder</span>
					<span class="rb-row-sub">{ws.active ? 'updating live' : 'everything on disk'}</span>
				</span>
			</a>
			{#each rows as r, i (r.name)}
				<a
					class="rb-row {r.state}"
					style="--i: {Math.min(i, 12)}"
					href="?g={encodeURIComponent(r.name)}&tab={tab}{show === 'all' ? '' : `&show=${show}`}"
					aria-current={r.name === selected ? 'page' : undefined}
					data-sveltekit-replacestate
					data-sveltekit-noscroll
				>
					<ResultsRing glyph={ws.summaries[r.name]?.glyph ?? null} size={30} state={ringState(r.state)} />
					<span class="rb-row-text">
						<span class="rb-row-name mg-mono" title={r.name}>{r.name}</span>
						<span class="rb-row-sub">{sub(r.name, r.state)}</span>
					</span>
				</a>
			{/each}
		</nav>
		{#if !listShut}<Resizer id="app:results-list" fallback={220} min={160} max={420} label="Resize the genome list" />{/if}
	</aside>

	<section class="rb-report" aria-labelledby="rb-title">
		{#if whole}
			<header class="rb-head">
				<div class="rb-title">
					<h2 id="rb-title">Results folder</h2>
					<p class="rb-note">Every tool's output and each genome's results, as they are on disk.</p>
				</div>
			</header>
			<div class="rb-pane rb-flow">
				<FolderView roots={wholeRoots} memory="all" empty="The results folder is not set. See Settings." />
			</div>
		{:else if summary}
			{#if full}
				<div class="rb-fullbar">
					<b class="mg-mono">{summary.genome}</b>
					<span class="rb-fullnote">{show === 'all' ? 'all genes' : `showing ${SHOWS.find((x) => x.id === show)?.label.toLowerCase()}`}</span>
					<span class="mg-grow"></span>
					<button type="button" class="rb-btn chat" aria-pressed={chatOpen} onclick={() => ui.toggleFold(CHAT, true)}><Bot size={15} />Chat with the genome</button>
					<button type="button" class="rb-btn exitfull" onclick={toggleFull}>Exit full screen | Esc</button>
				</div>
			{/if}
			<header class="rb-head">
				<div class="rb-title">
					<h2 id="rb-title" class="mg-mono" title={summary.genome}>{summary.genome}</h2>
					<ul class="rb-facts">
						{#if caller}<li><span>gene caller</span>{caller}</li>{/if}
						{#if summary.geneticCode}<li><span>genetic code</span>{summary.geneticCode}</li>{/if}
						{#if summary.domain && summary.domain !== 'Unknown'}<li><span>domain</span>{summary.domain}</li>{/if}
						{#if summary.envelope}<li><span>envelope</span>{summary.envelope}</li>{/if}
					</ul>
				</div>
				<div class="rb-tabs" role="tablist" aria-label="Report" use:thumb>
					{#each TABS as t (t.id)}
						<button type="button" role="tab" class="rb-tab" aria-selected={tab === t.id} onclick={() => setTab(t.id)}>
							{t.label}{#if t.id === 'figures' && summary.figures.length}<span class="rb-tab-n">{summary.figures.length}</span>{/if}
						</button>
					{/each}
				</div>
				<div class="rb-downloads">
					<button type="button" class="rb-btn chat" aria-pressed={chatOpen} onclick={() => ui.toggleFold(CHAT, true)}><Bot size={15} />Chat with the genome</button>
					{#if summary.final.excel}
						<a class="rb-btn primary" href={uiBase.to(`/view?path=${encodeURIComponent(summary.final.excel)}`)}><FileSpreadsheet size={15} />Open Excel</a>
					{/if}
					{#if summary.final.table}<a class="rb-btn" href={fileUrl(summary.final.table)} download><Download size={15} />TSV</a>{/if}
					{#if summary.final.excel}<a class="rb-btn" href={fileUrl(summary.final.excel)} download><Download size={15} />Excel</a>{/if}
				</div>
			</header>

			<!-- the numbers in one line; Details opens the ring, the tiers and the tools -->
			<div class="rb-strip">
				<span class="rb-strip-n"><b>{count(summary.genes)}</b> genes</span>
				<span class="rb-strip-n"><b>{count(summary.operons)}</b> operons</span>
				<span class="rb-strip-n"><b>{pct(summary.inOperons, summary.genes)}%</b> in operons</span>
				<span class="rb-strip-n"><b>{pct(summary.withSupport, summary.genes)}%</b> with support</span>
				{#if tierRows.length}
					<div class="rb-bar thin" role="img" aria-label={tierRows.map((r) => `${r.name} ${r.n}`).join(', ')}>
						{#each tierRows as r (r.key)}
							<span style="flex: {r.n}; background: var(--mg-tier-{r.tier})" title="{r.name}: {count(r.n)} ({pct(r.n, tierTotal)}%)"></span>
						{/each}
					</div>
				{:else}
					<span class="mg-grow"></span>
				{/if}
				<button type="button" class="rb-more" aria-expanded={!ui.isFolded(DETAILS, true)} onclick={() => ui.toggleFold(DETAILS, true)}>
					{ui.isFolded(DETAILS, true) ? 'Details' : 'Hide details'}
				</button>
			</div>

			<!-- which genes the map and the table show -->
			<div class="rb-show" role="group" aria-label="Show genes">
				<span class="rb-show-l">Show</span>
				{#each SHOWS as s (s.id)}
					{@const n = showCount(s.id)}
					{#if s.id === 'all' || n !== 0}
						<button type="button" class="rb-chip" aria-pressed={show === s.id} onclick={() => setShow(s.id)}>
							{#if s.tier !== undefined}<span class="rb-dot" style="background: var(--mg-tier-{s.tier})"></span>{/if}
							{s.label}{#if n !== null}<i>{count(n)}</i>{/if}
						</button>
					{/if}
				{/each}
			</div>

			{#if !ui.isFolded(DETAILS, true)}
			<div class="rb-hero">
				<figure class="rb-map">
					{#key summary.genome}
						<ResultsRing glyph={summary.glyph} size={212}>
							{#if summary.glyph}<b class="rb-ring-big">{size(summary.glyph.length)}</b>{/if}
							<span class="rb-ring-small"><CountUp value={summary.genes} /> genes</span>
							{#if summary.glyph && summary.glyph.contigs > 1}<span class="rb-ring-tiny">{summary.glyph.contigs} contigs</span>{/if}
						</ResultsRing>
					{/key}
					{#if summary.glyph}<figcaption>forward strand outside, reverse inside</figcaption>{/if}
				</figure>

				<div class="rb-numbers">
					<div class="rb-cards">
						<div class="rb-card" style="--c: var(--mg-accent)">
							<b><CountUp value={summary.operons} /></b>
							<span>operons</span>
						</div>
						<div class="rb-card" style="--c: var(--mg-tier-1)">
							<b><CountUp value={pct(summary.inOperons, summary.genes)} format={(n) => `${Math.round(n)}%`} /></b>
							<span>in operons <i>{count(summary.inOperons)} genes</i></span>
						</div>
						<div class="rb-card" style="--c: var(--mg-tier-0)">
							<b><CountUp value={pct(summary.withSupport, summary.genes)} format={(n) => `${Math.round(n)}%`} /></b>
							<span>with support <i>{count(summary.withSupport)} genes</i></span>
						</div>
					</div>

					{#if tierRows.length}
						<div class="rb-conf">
							<span class="rb-label">confidence</span>
							<div class="rb-bar" role="img" aria-label={tierRows.map((r) => `${r.name} ${r.n}`).join(', ')}>
								{#each tierRows as r, i (r.key)}
									<span style="flex: {r.n}; background: var(--mg-tier-{r.tier}); --i: {i}" title="{r.name}: {count(r.n)}"></span>
								{/each}
							</div>
							<ul class="rb-tiers" style="--cols: {tierRows.length <= 4 ? tierRows.length : Math.ceil(tierRows.length / 2)}">
								{#each tierRows as r, i (r.key)}
									<li style="--i: {i}" title={r.key}>
										<span class="rb-dot" style="background: var(--mg-tier-{r.tier})"></span>
										<span class="rb-tier-name">{r.name}</span>
										<span class="rb-tier-n">{count(r.n)}</span>
										<span class="rb-tier-pct">{pct(r.n, tierTotal)}%</span>
									</li>
								{/each}
							</ul>
						</div>
					{/if}

					{#if summary.tools.length}
						<ul class="rb-tools" aria-label="Tools">
							{#each summary.tools as t (t)}<li>{t}</li>{/each}
						</ul>
					{/if}
				</div>
			</div>

			{/if}

			<div class="rb-pane" class:rb-fill={fills} class:rb-flow={!fills}>
				{#key tab}
					<div class="rb-body" in:tabIn>
						{#if tab === 'map'}
							{#if summary.final.viewer}
								{#if backend.cluster}
									<p class="rb-remake">
										<span>This map was made on the cluster when the run finished. One from an earlier run lacks what has been added since (the gene report,
											operon map downloads, the contig and two-strand views).</span>
										<button type="button" class="rb-btn" disabled={remaking} onclick={() => remakeMap(summary!.final.viewer!)}>
											{remaking ? 'Making it again…' : 'Make this map again'}
										</button>
									</p>
								{/if}
								{#key mapVersion}
								<HtmlViewer src={fileUrl(summary.final.viewer, true) + (mapVersion ? `&v=${mapVersion}` : '')} download={fileUrl(summary.final.viewer)} onfull={toggleFull} {full} hash={show === 'all' ? '' : `show=${show}`} title="Genome viewer for {summary.genome}" />
								{/key}
							{:else if circular}
								<ImageViewer src={fileUrl(circular, true)} alt="Circular map of {summary.genome}" />
							{:else}
								<p class="rb-state">No genome map. Turn on Genome viewer in Settings to draw one next run.</p>
							{/if}
						{:else if tab === 'table' && summary.final.table}
							<DataGrid path={summary.final.table} {preset} />
						{:else if tab === 'figures'}
							{#if summary.figures.length}
								{@const shown = summary.figures.includes(figure) ? figure : summary.figures[0]}
								<div class="rb-gallery">
									<div class="rb-fig-side" style="--w: {ui.size('app:figs', 210)}px">
										<ul class="rb-fig-list" role="listbox" aria-label="Figures">
											{#each summary.figures as f, k (f)}
												<li>
													<button type="button" role="option" class="rb-fig-item" aria-selected={f === shown} onclick={() => (figure = f)}>
														<span class="rb-fig-n">{k + 1}</span>{figureTitle(f)}
													</button>
												</li>
											{/each}
										</ul>
										<Resizer id="app:figs" fallback={210} min={150} max={420} label="Resize the figure list" />
									</div>
									<div class="rb-fig">
										<p class="rb-fig-cap">Figure {summary.figures.indexOf(shown) + 1} of {summary.figures.length}: {figureTitle(shown)}</p>
										{#key shown}<ImageViewer src={fileUrl(shown, true)} alt="Figure {summary.figures.indexOf(shown) + 1}: {figureTitle(shown)}" />{/key}
									</div>
								</div>
							{:else}
								<p class="rb-state">No figures. Turn on Report figures in Settings to draw them next run.</p>
							{/if}
						{:else if tab === 'files'}
							{#key selected}<FolderView roots={genomeRoots(selected)} memory="genome:{selected}" />{/key}
						{:else if tab === 'methods'}
							<div class="rb-methods">
								<section class="rb-m-text">
									<h3>Methods</h3>
									<p>{methods.text}</p>
									<button type="button" class="rb-btn" class:done={copied} onclick={copyMethods}>
										{#if copied}<Check size={15} />Copied{:else}<Copy size={15} />Copy text and references{/if}
									</button>
								</section>
								<section class="rb-m-refs">
									<h3>References <b>{methods.refs.length}</b></h3>
									<ol>
										{#each methods.refs as r (r)}<li>{r}</li>{/each}
									</ol>
								</section>
							</div>
						{/if}
					</div>
				{/key}
			</div>
		{:else if loading}
			<div class="rb-state rb-wait">
				<ResultsRing size={120} state="running" />
				<span>Loading</span>
			</div>
		{:else if selectedRow}
			<header class="rb-head rb-head-row">
				<ResultsRing size={64} state={ringState(selectedRow.state)} />
				<div class="rb-title">
					<h2 id="rb-title" class="mg-mono" title={selected}>{selected}</h2>
					<p class="rb-note">
						{genesOnly
							? 'This run calls genes and stops there, so no report is written. Choose tools on Analyze and run again to annotate them.'
							: selectedRow.state === 'running'
								? `Running: ${ws.progress?.stage ?? ''}${ws.progress?.detail ? ` | ${ws.progress.detail}` : ''}. The report opens here when it finishes.`
								: 'Not finished. Its results so far are below; run it again to finish.'}
					</p>
				</div>
			</header>
			<div class="rb-pane rb-flow">
				{#key selected}<FolderView
						roots={genomeRoots(selected)}
						memory="genome:{selected}"
						empty="Nothing written yet. Folders appear here as the run writes them."
					/>{/key}
			</div>
		{:else}
			<div class="rb-state rb-wait">
				<ResultsRing size={120} state="pending" />
				<span>Results appear here once a run starts writing them.</span>
			</div>
		{/if}
	</section>
	{#if chatOpen && summary && !whole}
		<GenomeChat genome={summary.genome} context={chatContext} onclose={() => ui.toggleFold(CHAT, true)} />
	{/if}
</div>

<style>
	/* The whole of what is left of the window (the page is as tall as it). */
	.rb {
		position: relative;
		flex: 1;
		display: flex;
		min-height: 480px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		color: var(--mg-text);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow, var(--mg-shadow-lg));
		overflow: hidden;
	}

	/* ---- the genome list ---- */
	.rb-side {
		position: relative;
		flex-shrink: 0;
		width: var(--w);
		display: flex;
		flex-direction: column;
		border-right: 1px solid var(--mg-border);
		background: color-mix(in srgb, var(--mg-bg) 40%, transparent);
		transition: width var(--mo-3) var(--mo-ease);
	}
	.rb-side-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 6px;
		min-height: 48px;
		padding: 8px 8px 8px 16px;
		border-bottom: 1px solid var(--mg-border);
	}
	.rb-side-title {
		overflow: hidden;
		white-space: nowrap;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
		transition: opacity var(--mo-2) var(--mo-ease);
	}
	.rb-side-title b {
		margin-left: 4px;
		color: var(--mg-text-3);
		font-weight: 500;
	}
	.shut .rb-side-title {
		width: 0;
		opacity: 0;
	}
	.shut .rb-side-head {
		justify-content: center;
		padding: 8px 0;
	}
	.rb-fold {
		flex-shrink: 0;
		display: grid;
		place-items: center;
		width: 28px;
		height: 28px;
		padding: 0;
		border: 1px solid transparent;
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text-2);
		cursor: pointer;
	}
	.rb-fold:hover {
		border-color: var(--mg-border);
		color: var(--mg-text);
	}
	.rb-fold svg {
		width: 15px;
		height: 15px;
		fill: none;
		stroke: currentColor;
		stroke-width: 2;
		stroke-linecap: round;
		stroke-linejoin: round;
		transition: transform var(--mo-3) var(--mo-ease);
	}
	.rb-fold svg.flip {
		transform: rotate(180deg);
	}
	/* Height 0 and grow: the list scrolls in whatever height the report makes. */
	.rb-list {
		flex-grow: 1;
		height: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: 8px;
		overflow: auto;
		transition: opacity var(--mo-2) var(--mo-ease);
	}
	.shut .rb-list {
		opacity: 0;
		pointer-events: none;
	}
	.rb-row {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 7px 8px;
		border: 1px solid transparent;
		border-radius: var(--mg-r-sm);
		transition:
			background 140ms,
			border-color 140ms;
	}
	.rb-row:hover {
		background: var(--mg-surface-2);
	}
	.rb-row[aria-current='page'] {
		border-color: color-mix(in srgb, var(--mg-accent) 55%, transparent);
		background: color-mix(in srgb, var(--mg-accent) 12%, var(--mg-surface-2));
	}
	.rb-row-icon {
		display: grid;
		place-items: center;
		flex-shrink: 0;
		width: 30px;
		height: 30px;
		border-radius: 50%;
		background: var(--mg-surface-2);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.rb-row-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.rb-row-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-sm);
	}
	.rb-row[aria-current='page'] .rb-row-name {
		font-weight: 600;
	}
	.rb-row-sub {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.rb-row.running .rb-row-sub {
		color: var(--mg-accent-ink, var(--mg-accent));
	}

	/* ---- the report ---- */
	.rb-report {
		flex-grow: 1;
		min-width: 0;
		min-height: 0;
		display: flex;
		flex-direction: column;
	}
	.rb-head {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 10px 20px;
		padding: 10px var(--mg-pad);
		border-bottom: 1px solid var(--mg-border);
	}
	.rb-title {
		flex-grow: 1;
		display: flex;
		flex-direction: column;
		gap: 6px;
		min-width: 0;
	}
	.rb-title h2 {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-lg);
		font-weight: 650;
	}
	.rb-note {
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.rb-facts {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
	}
	.rb-facts li {
		display: inline-flex;
		align-items: baseline;
		gap: 6px;
		padding: 2px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		font-size: var(--mg-fs-xs);
		font-weight: 600;
	}
	.rb-facts span {
		color: var(--mg-text-3);
		font-weight: 400;
	}
	.rb-downloads {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}
	/* Full screen: only the report (and the chat) on the whole display. */
	.rb.full {
		border: none;
		border-radius: 0;
		background: var(--mg-bg, var(--mg-surface));
	}
	.rb.full > :global(.rb-side),
	.rb.full .rb-head,
	.rb.full .rb-strip,
	.rb.full .rb-show,
	.rb.full .rb-hero {
		display: none;
	}
	.rb.full .rb-pane {
		padding: 8px 10px 10px;
	}
	.rb-fullbar {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 8px 12px;
		border-bottom: 1px solid var(--mg-border);
		background: var(--mg-surface);
	}
	.rb-fullbar b {
		font-weight: 500;
	}
	.rb-fullnote {
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-3);
	}
	.rb-btn.exitfull {
		border-color: var(--mg-accent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	/* Figures by number: in the list, and over the one shown. */
	.rb-fig-n {
		display: inline-grid;
		place-items: center;
		min-width: 20px;
		height: 20px;
		margin-right: 8px;
		padding: 0 4px;
		border-radius: 4px;
		background: var(--mg-surface-2);
		color: var(--mg-text-2);
		font-size: var(--mg-fs-xs);
		font-variant-numeric: tabular-nums;
	}
	.rb-fig-cap {
		margin: 0 0 6px;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.rb-btn.chat[aria-pressed='true'] {
		border-color: var(--mg-accent);
		background: color-mix(in srgb, var(--mg-accent) 12%, var(--mg-surface));
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.rb-btn {
		display: inline-flex;
		align-items: center;
		gap: 7px;
		height: var(--mg-ctl-sm, 36px);
		padding: 0 15px;
		border: 1px solid var(--mg-border-strong);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-text);
		font: inherit;
		font-size: var(--mg-fs-sm);
		font-weight: 500;
		white-space: nowrap;
		cursor: pointer;
		transition:
			border-color 140ms,
			background 140ms;
	}
	.rb-btn:hover {
		border-color: var(--mg-accent);
		background: color-mix(in srgb, var(--mg-accent) 7%, var(--mg-surface));
	}
	.rb-btn.primary {
		border-color: var(--mg-accent);
		background: var(--mg-accent);
		color: var(--mg-on-accent);
	}
	.rb-btn.primary:hover {
		background: color-mix(in srgb, var(--mg-accent) 85%, var(--mg-text));
	}
	.rb-btn.done {
		border-color: var(--mg-ok);
		color: var(--mg-ok);
	}

	/* the sketch: ring, cards, confidence */
	/* The Show chips: one choice at a time, All by default. */
	.rb-show {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 6px;
		padding: 7px var(--mg-pad);
		border-bottom: 1px solid var(--mg-border);
	}
	.rb-show-l {
		margin-right: 4px;
		font-size: var(--mg-fs-xs);
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.rb-chip {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		height: 26px;
		padding: 0 10px;
		border: 1px solid var(--mg-border);
		border-radius: 999px;
		background: var(--mg-surface);
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-xs);
		cursor: pointer;
	}
	.rb-chip i {
		font-style: normal;
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-3);
	}
	.rb-chip:hover {
		border-color: var(--mg-border-strong);
		color: var(--mg-text);
	}
	.rb-chip[aria-pressed='true'] {
		border-color: var(--mg-accent);
		background: color-mix(in srgb, var(--mg-accent) 12%, var(--mg-surface));
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.rb-chip[aria-pressed='true'] i {
		color: inherit;
	}
	.rb-chip .rb-dot {
		width: 8px;
		height: 8px;
	}
	/* One line of numbers and the confidence bar. */
	.rb-strip {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 6px 18px;
		padding: 8px var(--mg-pad);
		border-bottom: 1px solid var(--mg-border);
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.rb-strip-n b {
		font-weight: 500;
		font-variant-numeric: tabular-nums;
		color: var(--mg-text);
	}
	.rb-bar.thin {
		flex: 1 1 200px;
		min-width: 120px;
		height: 8px;
	}
	.rb-more {
		flex: none;
		padding: 3px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-xs);
		cursor: pointer;
	}
	.rb-more:hover,
	.rb-more[aria-expanded='true'] {
		border-color: var(--mg-border-strong);
		color: var(--mg-text);
	}
	.rb-hero {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr);
		align-items: center;
		gap: 20px 36px;
		padding: 24px var(--mg-pad);
		border-bottom: 1px solid var(--mg-border);
	}
	.rb-map {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 10px;
	}
	.rb-map :global(.rb-ring) {
		filter: drop-shadow(0 6px 26px color-mix(in srgb, var(--mg-accent) 16%, transparent));
	}
	.rb-map figcaption {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.rb-ring-big {
		font-size: calc(var(--mg-fs-lg) * 1.35);
		font-weight: 700;
		letter-spacing: -0.02em;
		font-variant-numeric: tabular-nums;
	}
	.rb-ring-small {
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.rb-ring-tiny {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.rb-numbers {
		display: flex;
		flex-direction: column;
		gap: 18px;
		min-width: 0;
	}
	.rb-cards {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 10px;
	}
	.rb-card {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: 12px 14px 12px 16px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-surface-2);
		overflow: hidden;
	}
	.rb-card::before {
		content: '';
		position: absolute;
		inset: 0 auto 0 0;
		width: 3px;
		background: var(--c);
	}
	.rb-card b {
		font-size: calc(var(--mg-fs-lg) * 1.3);
		font-weight: 700;
		line-height: 1.15;
	}
	.rb-card span {
		display: flex;
		flex-wrap: wrap;
		gap: 0 6px;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.rb-card i {
		font-style: normal;
		color: var(--mg-text-3);
		font-variant-numeric: tabular-nums;
	}
	.rb-conf {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.rb-label {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.rb-bar {
		display: flex;
		gap: 2px;
		height: 14px;
		border-radius: 4px;
		overflow: hidden;
		background: var(--mg-border);
	}
	.rb-bar span {
		min-width: 3px;
		transform-origin: left;
	}
	.rb-tiers {
		display: grid;
		grid-template-columns: repeat(var(--cols, 3), minmax(0, 1fr));
		gap: 2px 20px;
	}
	.rb-tiers li {
		display: grid;
		grid-template-columns: 10px minmax(0, 1fr) auto 3.2em;
		align-items: center;
		gap: 10px;
		padding: 4px 0;
		border-bottom: 1px solid color-mix(in srgb, var(--mg-border) 60%, transparent);
		font-size: var(--mg-fs-sm);
	}
	.rb-dot {
		width: 10px;
		height: 10px;
		border-radius: 50%;
	}
	.rb-tier-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		text-transform: capitalize;
	}
	.rb-tier-n {
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.rb-tier-pct {
		text-align: right;
		color: var(--mg-text-3);
		font-variant-numeric: tabular-nums;
	}
	.rb-tools {
		display: flex;
		flex-wrap: wrap;
		gap: 5px;
	}
	.rb-tools li {
		padding: 1px 8px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-accent) 14%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
		font-family: var(--mg-mono);
		font-size: 11px;
	}

	/* the tabs: a pill that slides (motion/thumb.ts) */
	/* Across the whole report, each tab an equal share. */
	/* In the head's row, between the name and the downloads. */
	.rb-tabs {
		flex: 0 1 auto;
		display: grid;
		grid-auto-flow: column;
		grid-auto-columns: minmax(max-content, 1fr);
		gap: 2px;
		margin: 0 auto;
		padding: 4px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-bg) 45%, transparent);
		overflow-x: auto;
		scrollbar-width: none;
	}
	.rb-tabs > :global(.mo-thumb) {
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--mg-accent) 60%, transparent);
	}
	.rb-tab {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		flex-shrink: 0;
		height: 32px;
		padding: 0 14px;
		border: none;
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-sm);
		cursor: pointer;
		transition: color var(--mo-2) var(--mo-ease);
	}
	.rb-tab:hover {
		color: var(--mg-text);
	}
	.rb-tab[aria-selected='true'] {
		background: var(--mg-surface-2);
		color: var(--mg-text);
		font-weight: 600;
	}
	.rb-tab-n {
		padding: 0 6px;
		border-radius: var(--mg-r-sm);
		background: var(--mg-border);
		font-size: 11px;
		font-weight: 500;
	}

	/* ---- the pane under the tabs ---- */
	.rb-pane {
		padding: 14px var(--mg-pad) var(--mg-pad);
		min-width: 0;
	}
	/* Viewers that scroll and zoom themselves get a fixed height. */
	.rb-fill {
		flex: 1;
		min-height: 360px;
		display: flex;
		flex-direction: column;
	}
	.rb-fill > .rb-body {
		flex-grow: 1;
		min-height: 0;
		display: flex;
		flex-direction: column;
	}
	.rb-fill > .rb-body > :global(*) {
		flex-grow: 1;
		min-height: 0;
	}
	.rb-flow {
		flex-grow: 1;
		min-height: 0;
		overflow: auto;
	}
	.rb-gallery {
		display: flex;
		gap: var(--mg-gap);
		align-items: stretch;
		height: 100%;
	}
	.rb-fig-side {
		position: relative;
		flex-shrink: 0;
		width: var(--w);
		display: flex;
		flex-direction: column;
	}
	.rb-fig-list {
		flex-grow: 1;
		min-height: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding-right: 8px;
		overflow: auto;
	}
	.rb-fig-item {
		width: 100%;
		padding: 6px 10px;
		border: none;
		border-left: 2px solid transparent;
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-sm);
		text-align: left;
		cursor: pointer;
	}
	.rb-fig-item:hover {
		background: var(--mg-surface-2);
		color: var(--mg-text);
	}
	.rb-fig-item[aria-selected='true'] {
		border-left-color: var(--mg-accent);
		background: var(--mg-surface-2);
		color: var(--mg-text);
		font-weight: 500;
	}
	.rb-fig {
		flex-grow: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}
	/* The text to paste into a paper beside its references: two equal halves. */
	.rb-methods {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--mg-gap);
		line-height: 1.6;
	}
	.rb-methods section {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 12px;
		padding: 18px 20px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: color-mix(in srgb, var(--mg-text) 2.5%, var(--mg-surface));
	}
	.rb-methods h3 {
		font-size: var(--mg-fs-xs);
		font-weight: 650;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.rb-methods h3 b {
		margin-left: 4px;
		color: var(--mg-text-2);
	}
	.rb-m-text p {
		flex-grow: 1;
	}
	.rb-methods ol {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding-left: 20px;
		list-style: decimal;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.rb-state {
		flex-grow: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 14px;
		padding: 40px var(--mg-pad);
		text-align: center;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}

	:global([data-motion='off']) .rb * {
		animation: none !important;
	}

	@media (max-width: 900px) {
		.rb {
			flex-direction: column;
			min-height: 0;
		}
		.rb-side {
			width: 100%;
			border-right: none;
			border-bottom: 1px solid var(--mg-border);
		}
		.rb-side :global(.mo-resizer),
		.rb-fig-side :global(.mo-resizer) {
			display: none;
		}
		.rb-list {
			height: auto;
			max-height: 220px;
		}
		.shut .rb-list {
			display: none;
		}
		.shut .rb-side-title {
			width: auto;
			opacity: 1;
		}
		.shut .rb-side-head {
			justify-content: space-between;
			padding: 8px 8px 8px 16px;
		}
		.rb-head:not(.rb-head-row) {
			flex-wrap: wrap;
		}
		.rb-hero {
			grid-template-columns: minmax(0, 1fr);
			justify-items: stretch;
		}
		.rb-gallery {
			flex-direction: column;
		}
		.rb-methods {
			grid-template-columns: minmax(0, 1fr);
		}
		.rb-tiers {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.rb-fig-side {
			width: 100%;
			max-height: 160px;
		}
	}
	@media (max-width: 520px) {
		.rb-head,
		.rb-hero,
		.rb-pane {
			padding-left: 14px;
			padding-right: 14px;
		}
		.rb-tabs {
			margin-left: 14px;
			margin-right: 14px;
			max-width: calc(100% - 28px);
		}
		.rb-fill {
			height: clamp(380px, 70vh, 640px);
		}
		.rb-cards {
			gap: 6px;
		}
		.rb-card {
			padding: 10px 8px 10px 12px;
		}
		.rb-card b {
			font-size: var(--mg-fs-lg);
		}
		.rb-card span {
			font-size: var(--mg-fs-xs);
		}
		.rb-tab {
			padding: 0 10px;
		}
	}
	.rb-remake {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: 8px 16px;
		margin-bottom: 8px;
		padding: 6px 12px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-accent) 6%, transparent);
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-2);
	}
</style>
