<script lang="ts">
	import { Check, ExternalLink, FolderOpen, ScrollText, Square, Trash2, X } from 'lucide-svelte';
	import '$lib/workspace/viewers/tools.css';
	import { api, type Run } from '$lib/api';
	import { uiBase } from '$lib/workspace/base.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { ws } from '$lib/workspace/data.svelte';
	import { ago, duration } from '$lib/workspace/format';

	/**
	 * Modern's Jobs page: every job as a card (status, what it did, progress,
	 * output folder) beside the log of the selected one, the current run by default.
	 */

	const TYPE: Record<string, string> = { annotate: 'Annotate', setup: 'Set up', build: 'Install' };
	const STATUS: Record<string, string> = { running: 'running', completed: 'finished', failed: 'failed', cancelled: 'stopped' };

	/** "Annotate 6 genomes", "Install pfam, kegg +3". */
	function title(r: Run): string {
		const label = r.label.replace(/ with .*$/, '');
		if (r.kind === 'annotate' && r.files?.length) return `Annotate ${r.files.length === 1 ? r.files[0] : `${r.files.length} genomes`}`;
		return label;
	}
	function toolsLine(r: Run): string {
		if (r.tools?.length) return r.tools.length > 3 ? `${r.tools.slice(0, 3).join(', ')} +${r.tools.length - 3}` : r.tools.join(', ');
		if (r.kind === 'annotate') return r.args.includes('--genes-only') ? 'gene caller only' : 'all tools';
		return '';
	}
	const pctOf = (r: Run) => (r.status === 'completed' ? 100 : Math.max(0, Math.min(100, r.progress ?? 0)));
	const folderHref = (dir: string) => `${uiBase.path}/files?path=${encodeURIComponent(dir)}`;

	// ------------------------------------------------ the log beside the list
	let picked = $state<string | null>(null);
	const shown = $derived(ws.runs.find((r) => r.id === picked) ?? ws.active ?? ws.runs[0] ?? null);
	/** The watched run's log is already in ws.log; any other is read once. */
	const live = $derived(!!shown && shown.id === ws.active?.id);
	let fetched = $state<{ id: string; text: string } | null>(null);
	$effect(() => {
		const r = shown;
		if (!r || live || fetched?.id === r.id) return;
		const id = r.id;
		fetched = { id, text: 'Reading the log…' };
		api<{ log: { text: string } }>(`/runs/${id}?tail=12000`)
			.then((d) => {
				if (fetched?.id === id) fetched = { id, text: d.log.text || 'Nothing in the log.' };
			})
			.catch(() => {
				if (fetched?.id === id) fetched = { id, text: 'The log could not be read.' };
			});
	});
	const logText = $derived(live ? ws.log.slice(-12000) : fetched && shown && fetched.id === shown.id ? fetched.text : '');
	const lines = $derived(logText.trimEnd().split('\n').slice(-60));
	let term = $state<HTMLElement | null>(null);
	$effect(() => {
		void lines;
		if (term) term.scrollTop = term.scrollHeight;
	});

	// ------------------------------------------------ clearing the history
	let asking = $state(false);
	let clearing = $state(false);
	let backup = $state('');
	const stillGoing = $derived(ws.runs.filter((r) => r.status === 'running').length);
	async function clear() {
		clearing = true;
		const r = await ws.clearRuns();
		clearing = false;
		asking = false;
		if (r) backup = r.backup;
	}
</script>

{#if ws.runs.length}
	<div class="board">
		<div class="list">
			<div class="toolbar">
				<span class="mg-note">Pick a job to read its log.</span>
				<span class="mg-grow"></span>
				{#if backend.cluster}
					<span class="mg-note">Kept by the cluster, in your job history.</span>
				{:else if asking}
					<span class="mg-note ask">
						Clear {ws.runs.length - stillGoing} finished job{ws.runs.length - stillGoing === 1 ? '' : 's'}? A copy is kept in
						<span class="mg-mono">run-history/</span>.
					</span>
					<button type="button" class="vw-pill sm primary" disabled={clearing} onclick={clear}>{clearing ? 'Clearing' : 'Clear and back up'}</button>
					<button type="button" class="vw-pill sm" onclick={() => (asking = false)}>Keep them</button>
				{:else}
					<button type="button" class="vw-pill sm" onclick={() => (asking = true)}><Trash2 size={13} />Clean history</button>
				{/if}
			</div>
			{#if backup}<p class="mg-note saved">Backed up to <span class="mg-mono">{backup}</span></p>{/if}

			<ul class="cards">
				{#each ws.runs as r, i (r.id)}
					{@const pct = pctOf(r)}
					{@const tl = toolsLine(r)}
					<li style="--i: {Math.min(i, 12)}">
						<div class="card {r.status}" class:picked={shown?.id === r.id}>
							<button type="button" class="pick" aria-pressed={shown?.id === r.id} onclick={() => (picked = r.id)} title={r.command ?? r.label}>
								<span class="mark" aria-hidden="true">
									{#if r.status === 'running'}<span class="spinner"></span>
									{:else if r.status === 'completed'}<Check size={16} strokeWidth={3} />
									{:else if r.status === 'failed'}<X size={16} strokeWidth={3} />
									{:else}<Square size={11} strokeWidth={3} fill="currentColor" />{/if}
								</span>
								<span class="what">
									<span class="name">{title(r)}</span>
									<span class="meta">
										{TYPE[r.kind] ?? r.kind} | {STATUS[r.status] ?? r.status} {ago(r.started)}{r.finished ? ` | took ${duration(r)}` : ''}{tl ? ` | ${tl}` : ''}
									</span>
								</span>
								<span class="pct">{pct}%</span>
							</button>
							<div class="bar" role="progressbar" aria-valuenow={pct} aria-valuemin="0" aria-valuemax="100">
								<span style="width: {Math.max(r.status === 'running' ? 3 : 0, pct)}%"></span>
							</div>
							{#if r.reason}<p class="why" title={r.reason}>{r.reason}</p>{/if}
							<div class="acts">
								<a class="vw-pill sm" href={uiBase.to(`/runs/${r.id}`)}><ScrollText size={13} />Full log</a>
								{#if r.outputDir}
									<a class="vw-pill sm outdir" href={folderHref(r.outputDir)} title={r.outputDir}>
										<FolderOpen size={13} /><span>{r.outputDir.split('/').filter(Boolean).slice(-2).join('/')}</span>
									</a>
								{/if}
								<span class="mg-grow"></span>
								<span class="id mg-mono" title="Job ID">{r.id}</span>
								{#if r.status === 'running'}<button type="button" class="vw-pill sm danger" onclick={() => ws.stop(r.id)}><Square size={10} fill="currentColor" />Stop</button>{/if}
							</div>
						</div>
					</li>
				{/each}
			</ul>
		</div>

		<aside class="term" aria-label="Log of {shown ? title(shown) : 'the job'}">
			<div class="term-bar">
				<span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>
				<span class="term-title">{shown ? title(shown) : ''}</span>
				{#if shown}<a class="term-open" href={uiBase.to(`/runs/${shown.id}`)}><ExternalLink size={13} />Open</a>{/if}
			</div>
			{#if shown?.command}<p class="cmd mg-mono" title={shown.command}>$ {shown.command}</p>{/if}
			<pre class="out mg-mono" bind:this={term}>{#each lines as l, k (k)}<span class="ln" class:err={/error|failed|traceback/i.test(l)} class:ok={/\b(done|finished|completed)\b/i.test(l)}>{l}</span>
{/each}{#if live}<span class="cursor" aria-hidden="true"></span>{/if}</pre>
		</aside>
	</div>
{:else}
	<p class="empty">
		<strong>No jobs yet.</strong>
		<span>Add a genome and press Run on <a class="mg-link" href={uiBase.path}>Analyze</a>; every job shows up here with its log.</span>
	</p>
{/if}

<style>
	/* Two equal halves, as tall as each other: the cards scroll in theirs and
	   the terminal fills its own, so neither leaves the other a gap. */
	.board {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		grid-template-rows: minmax(0, 1fr);
		max-height: max(520px, calc(100vh - 150px));
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		color: var(--mg-text);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow, var(--mg-shadow-lg));
		overflow: hidden;
	}
	.list {
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
		border-right: 1px solid var(--mg-border);
	}
	.toolbar {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 12px;
		min-height: 54px;
		padding: 10px var(--mg-pad);
		border-bottom: 1px solid var(--mg-border);
	}
	.ask {
		color: var(--mg-text);
	}
	.saved {
		padding: 8px var(--mg-pad);
		color: var(--mg-ok);
	}
	.cards {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: var(--mg-pad);
		overflow: auto;
	}
	.card {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-surface-2);
		transition:
			border-color 160ms,
			box-shadow 160ms;
	}
	.card.picked {
		border-color: var(--mg-accent);
		box-shadow: 0 0 0 1px var(--mg-accent), 0 8px 24px color-mix(in srgb, var(--mg-accent) 18%, transparent);
	}
	.pick {
		display: grid;
		grid-template-columns: 30px minmax(0, 1fr) auto;
		align-items: center;
		gap: 12px;
		width: 100%;
		padding: 0;
		border: none;
		background: none;
		color: inherit;
		font: inherit;
		text-align: left;
		cursor: pointer;
	}
	.pick:focus-visible {
		outline: 2px solid var(--mg-accent);
		outline-offset: 4px;
		border-radius: var(--mg-r-sm);
	}
	.mark {
		width: 30px;
		height: 30px;
		display: grid;
		place-items: center;
		border-radius: 50%;
		background: var(--mg-border-strong);
		color: var(--mg-text);
	}
	.completed .mark {
		background: var(--mg-ok);
		color: #fff;
	}
	.failed .mark {
		background: var(--mg-danger);
		color: #fff;
	}
	.running .mark {
		background: color-mix(in srgb, var(--mg-accent) 22%, transparent);
	}
	.spinner {
		width: 16px;
		height: 16px;
		border-radius: 50%;
		border: 2.5px solid color-mix(in srgb, var(--mg-accent) 30%, transparent);
		border-top-color: var(--mg-accent);
		animation: spin 900ms linear infinite;
	}
	.what {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-weight: 650;
	}
	.meta {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.pct {
		font-size: var(--mg-fs-sm);
		font-weight: 650;
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-2);
	}
	.running .pct {
		color: var(--mg-accent);
	}
	.bar {
		height: 5px;
		border-radius: 3px;
		background: var(--mg-border);
		overflow: hidden;
	}
	.bar span {
		display: block;
		height: 100%;
		border-radius: 3px;
		background: var(--mg-text-3);
		transition: width 600ms ease;
	}
	.completed .bar span {
		background: var(--mg-ok);
	}
	.failed .bar span {
		background: var(--mg-danger);
	}
	.running .bar span {
		background: var(--mg-accent);
	}
	.why {
		margin: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-danger);
	}
	.acts {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: var(--mg-fs-xs);
	}
	.outdir {
		flex-shrink: 1;
		min-width: 0;
	}
	.outdir span {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.id {
		color: var(--mg-text-3);
		font-size: 11px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		max-width: 14ch;
	}

	/* ---- the terminal ---- */
	/* A terminal is dark in either theme, with its own light ink. */
	.term {
		--tm-ink: #e4e8ec;
		--tm-dim: #9aa3ab;
		--tm-rule: rgba(255, 255, 255, 0.09);
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
		background: #14171b;
		color: var(--tm-ink);
	}
	.term-open {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		height: 28px;
		padding: 0 12px;
		border: 1px solid var(--tm-rule);
		border-radius: var(--mg-r-sm);
		color: var(--tm-dim);
		font-size: var(--mg-fs-xs);
	}
	.term-open:hover {
		border-color: rgba(255, 255, 255, 0.22);
		color: var(--tm-ink);
	}
	.term-bar {
		display: flex;
		align-items: center;
		gap: 12px;
		min-height: 54px;
		padding: 10px var(--mg-pad);
		border-bottom: 1px solid var(--tm-rule);
		font-size: var(--mg-fs-sm);
	}
	.dots {
		display: flex;
		gap: 6px;
	}
	.dots i {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		background: var(--tm-dim);
	}
	.dots i:first-child {
		background: var(--mg-danger);
	}
	.dots i:nth-child(2) {
		background: var(--mg-warn);
	}
	.dots i:last-child {
		background: var(--mg-ok);
	}
	.term-title {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-weight: 600;
	}
	.cmd {
		margin: 0;
		padding: 8px var(--mg-pad) 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: 11px;
		color: color-mix(in srgb, var(--mg-accent) 60%, #fff);
	}
	.out {
		flex: 1 1 auto;
		min-height: 260px;
		margin: 0;
		padding: 10px var(--mg-pad) 16px;
		overflow: auto;
		font-size: 11.5px;
		line-height: 1.55;
		white-space: pre-wrap;
		word-break: break-word;
		color: color-mix(in srgb, var(--tm-ink) 85%, transparent);
	}
	.ln.ok {
		color: color-mix(in srgb, var(--mg-ok) 70%, #fff);
	}
	.ln.err {
		color: color-mix(in srgb, var(--mg-danger) 75%, #fff);
	}
	.cursor {
		display: inline-block;
		width: 8px;
		height: 14px;
		vertical-align: text-bottom;
		background: var(--mg-ok);
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		padding: calc(var(--mg-gap) * 2) var(--mg-pad);
		text-align: center;
		color: var(--mg-text-3);
	}
	.empty strong {
		color: var(--mg-text-2);
		font-size: var(--mg-fs);
	}

	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}
	:global([data-motion='off']) .board * {
		animation: none !important;
	}

	@media (max-width: 1000px) {
		.board {
			grid-template-columns: minmax(0, 1fr);
			grid-template-rows: auto auto;
			max-height: none;
		}
		.list {
			border-right: none;
			border-bottom: 1px solid var(--mg-border);
		}
		.cards {
			max-height: 70vh;
		}
	}
	@media (max-width: 520px) {
		.id {
			display: none;
		}
		.out {
			max-height: 60vh;
		}
	}
</style>
