<script lang="ts">
	import '../viewers/tools.css';
	import { uiBase } from '../base.svelte';
	import { onDestroy, tick } from 'svelte';
	import { ArrowLeft, Check, Copy, FolderOpen, Square, TextWrap, X } from 'lucide-svelte';
	import { api, type Run } from '$lib/api';
	import { ws } from '$lib/workspace/data.svelte';
	import { ui } from '$lib/workspace/ui.svelte';
	import { ago, duration } from '$lib/workspace/format';

	const STATUS: Record<Run['status'], string> = { running: 'Running', completed: 'Finished', failed: 'Failed', cancelled: 'Stopped' };
	const TYPE: Record<string, string> = { annotate: 'Annotate', setup: 'Set up', build: 'Install' };
	/** Lines drawn in the terminal; Copy log copies all of them. */
	const SHOWN = 20000;

	/**
	 * One run's live log: a head card (status, progress, actions), a dark terminal, and a facts
	 * column (ID, times, tools, genomes, output folder, SLURM jobs and containers found in the log).
	 */
	let { id }: { id: string } = $props();
	let run = $state<Run | null>(null);
	let step = $state('');
	let log = $state('');
	let error = $state('');
	let box = $state<HTMLPreElement>();
	let offset = 0;
	let timer: ReturnType<typeof setTimeout> | null = null;
	let loaded = '';
	let wrap = $state(true);

	let copied = $state(false);

	/** Copies the whole log, not only the visible part. */
	async function copyLog() {
		if (!log) return;
		try {
			await navigator.clipboard.writeText(log);
			copied = true;
			setTimeout(() => (copied = false), 1600);
		} catch {
			ui.notify('Could not reach the clipboard', 'error');
		}
	}

	async function read(runId: string) {
		try {
			for (let i = 0; i < 20; i++) {
				const d = await api<{ run: Run; step?: string; log: { text: string; offset: number; size: number } }>(`/runs/${runId}?offset=${offset}`);
				if (runId !== id) return;
				run = d.run;
				step = d.step ?? '';
				if (d.log.text) {
					const atEnd = !box || box.scrollHeight - box.scrollTop - box.clientHeight < 40;
					log = (log + d.log.text).slice(-2_000_000);
					if (atEnd) tick().then(() => box && (box.scrollTop = box.scrollHeight));
				}
				offset = d.log.offset;
				if (d.log.offset >= d.log.size) break;
			}
			error = '';
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		}
		if (run?.status === 'running' && runId === id) timer = setTimeout(() => read(runId), 2000);
	}

	$effect(() => {
		if (id === loaded) return;
		loaded = id;
		if (timer) clearTimeout(timer);
		run = null;
		log = '';
		offset = 0;
		read(id);
	});

	onDestroy(() => timer && clearTimeout(timer));

	const all = $derived(log.replace(/\n$/, '').split('\n'));
	const lines = $derived(all.length > SHOWN ? all.slice(-SHOWN) : all);
	const pct = $derived(!run ? 0 : run.status === 'completed' ? 100 : Math.max(0, Math.min(100, run.progress ?? 0)));
	const tone = (l: string) => (/error|failed|traceback|exception/i.test(l) ? 'err' : /warn/i.test(l) ? 'warn' : /\b(done|finished|completed)\b/i.test(l) ? 'ok' : '');

	/** SLURM job numbers and container images named in the log. */
	function found(re: RegExp): string[] {
		const seen = new Set<string>();
		for (const m of log.matchAll(re)) if (seen.size < 12) seen.add(m[1]);
		return [...seen];
	}
	const slurm = $derived(found(/(?:Submitted batch job|SLURM_JOB_ID[=:]?\s*|external jobid\s*'?|slurm[_ -]?job(?:[_ -]?id)?[=:\s]+)(\d{3,})/gi));
	const containers = $derived(found(/([\w.+-]+\.sif)\b/g));

	const when = (iso?: string) => (iso ? new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' }) : '');
	const folderHref = (dir: string) => `${uiBase.path}/files?path=${encodeURIComponent(dir)}`;
</script>

<div class="rl">
	<header class="rl-head {run?.status ?? 'loading'}">
		<a class="vw-pill icon" href={uiBase.to('/runs')} aria-label="Back to Jobs" title="Back to Jobs"><ArrowLeft size={16} /></a>
		<span class="rl-mark" aria-hidden="true">
			{#if !run || run.status === 'running'}<span class="rl-spin"></span>
			{:else if run.status === 'completed'}<Check size={20} strokeWidth={3} />
			{:else if run.status === 'failed'}<X size={20} strokeWidth={3} />
			{:else}<Square size={13} strokeWidth={3} fill="currentColor" />{/if}
		</span>
		<div class="rl-title">
			<h1 title={run?.label}>{run?.label ?? 'Reading the job…'}</h1>
			{#if run}
				<p class="rl-meta">
					<span class="rl-tag">{STATUS[run.status]}</span>
					<span>{TYPE[run.kind] ?? run.kind}</span>
					<span>started {ago(run.started)}</span>
					<span>{run.finished ? `took ${duration(run)}` : `running for ${duration(run)}`}</span>
					{#if run.exitCode != null && run.exitCode !== 0}<span class="rl-bad">exit {run.exitCode}</span>{/if}
				</p>
			{/if}
		</div>
		{#if run}
			<div class="rl-acts">
				{#if run.outputDir}
					<a class="vw-pill" href={folderHref(run.outputDir)} title={run.outputDir}><FolderOpen size={15} />Output</a>
				{/if}
				<button type="button" class="vw-pill" disabled={!log} onclick={copyLog} title="Copy the whole log">
					{#if copied}<Check size={15} />Copied{:else}<Copy size={15} />Copy log{/if}
				</button>
				{#if run.status === 'running'}
					<button type="button" class="vw-pill danger" onclick={() => run && ws.stop(run.id)}><Square size={12} fill="currentColor" />Stop</button>
				{/if}
			</div>
			<div class="rl-progress">
				<div class="rl-bar" role="progressbar" aria-valuenow={pct} aria-valuemin="0" aria-valuemax="100" aria-label="Progress">
					<span style="width: {Math.max(run.status === 'running' ? 3 : 0, pct)}%"></span>
				</div>
				<span class="rl-pct">{pct}%</span>
				<span class="rl-step">{run.progressText || step || (run.status === 'running' ? 'Working' : STATUS[run.status])}</span>
			</div>
			{#if run.reason}<p class="rl-why" title={run.reason}>{run.reason}</p>{/if}
		{/if}
	</header>

	{#if error}<p class="rl-error">{error}</p>{/if}

	<div class="rl-body">
		<section class="rl-term" aria-label="Log">
			<div class="rl-term-bar">
				<span class="rl-dots" aria-hidden="true"><i></i><i></i><i></i></span>
				<span class="rl-term-title">Log</span>
				<span class="rl-term-n">{log ? `${all.length.toLocaleString('en-US')} lines${all.length > SHOWN ? `, the last ${SHOWN.toLocaleString('en-US')} shown` : ''}` : ''}</span>
				<span class="vw-grow"></span>
				{#if run?.status === 'running'}<span class="rl-live"><i></i>Live</span>{/if}
				<button type="button" class="rl-term-btn" aria-pressed={wrap} title="Wrap long lines" onclick={() => (wrap = !wrap)}><TextWrap size={14} />Wrap</button>
			</div>
			{#if run?.command}<p class="rl-cmd mg-mono" title={run.command}>$ {run.command}</p>{/if}
			<pre class="rl-out mg-mono" class:wrap bind:this={box}>{#if log}{#each lines as l, k (k)}<span class={tone(l)}>{l}</span>
{/each}{:else}<span class="dim">{run ? 'No output yet.' : 'Loading…'}</span>{/if}{#if run?.status === 'running'}<span class="rl-cursor" aria-hidden="true"></span>{/if}</pre>
		</section>

		<aside class="rl-info" aria-label="About this job">
			<h2>This job</h2>
			<dl>
				<div><dt>Job ID</dt><dd class="mg-mono">{id}</dd></div>
				{#if run}
					<div><dt>Started</dt><dd>{when(run.started)}</dd></div>
					<div><dt>{run.finished ? 'Finished' : 'Running for'}</dt><dd>{run.finished ? when(run.finished) : duration(run)}</dd></div>
					{#if run.exitCode != null}<div><dt>Exit code</dt><dd class:rl-bad={run.exitCode !== 0}>{run.exitCode}</dd></div>{/if}
					{#if step}<div><dt>Step</dt><dd>{step}</dd></div>{/if}
					{#if run.files?.length}
						<div class="wide">
							<dt>Genomes <b>{run.files.length}</b></dt>
							<dd class="rl-chips">{#each run.files.slice(0, 24) as f (f)}<span class="mg-mono">{f}</span>{/each}{#if run.files.length > 24}<span>+{run.files.length - 24}</span>{/if}</dd>
						</div>
					{/if}
					{#if run.tools?.length}
						<div class="wide">
							<dt>Tools <b>{run.tools.length}</b></dt>
							<dd class="rl-chips">{#each run.tools as t (t)}<span class="mg-mono">{t}</span>{/each}</dd>
						</div>
					{/if}
					{#if slurm.length}
						<div class="wide">
							<dt>SLURM jobs <b>{slurm.length}</b></dt>
							<dd class="rl-chips">{#each slurm as j (j)}<span class="mg-mono">{j}</span>{/each}</dd>
						</div>
					{/if}
					{#if containers.length}
						<div class="wide">
							<dt>Containers <b>{containers.length}</b></dt>
							<dd class="rl-chips">{#each containers as c (c)}<span class="mg-mono">{c}</span>{/each}</dd>
						</div>
					{/if}
					{#if run.outputDir}
						<div class="wide">
							<dt>Output folder</dt>
							<dd><a class="rl-path mg-mono" href={folderHref(run.outputDir)} title="Open in Files">{run.outputDir}</a></dd>
						</div>
					{/if}
				{/if}
			</dl>
		</aside>
	</div>
</div>

<style>
	.rl {
		display: flex;
		flex-direction: column;
		gap: var(--cr-gutter, 18px);
		min-height: 0;
	}

	/* ---- head card ---- */
	.rl-head {
		--st: var(--mg-accent);
		display: grid;
		grid-template-columns: auto auto minmax(0, 1fr) auto;
		grid-template-areas:
			'back mark title acts'
			'prog prog prog prog';
		align-items: center;
		gap: 14px 16px;
		padding: 18px 20px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow);
	}
	.rl-head.completed {
		--st: var(--mg-ok);
	}
	.rl-head.failed {
		--st: var(--mg-danger);
	}
	.rl-head.cancelled {
		--st: var(--mg-text-3);
	}
	.rl-head > .vw-pill {
		grid-area: back;
	}
	.rl-mark {
		grid-area: mark;
		display: grid;
		place-items: center;
		width: 46px;
		height: 46px;
		border-radius: 50%;
		background: var(--st);
		color: var(--mg-on-accent);
		box-shadow: none;
	}
	.running .rl-mark,
	.loading .rl-mark {
		background: color-mix(in srgb, var(--mg-accent) 16%, var(--mg-surface));
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--mg-accent) 35%, transparent);
	}
	.cancelled .rl-mark {
		color: var(--mg-surface);
	}
	.rl-spin {
		width: 22px;
		height: 22px;
		border-radius: 50%;
		border: 3px solid color-mix(in srgb, var(--mg-accent) 28%, transparent);
		border-top-color: var(--mg-accent);
		animation: rl-turn 900ms linear infinite;
	}
	.rl-title {
		grid-area: title;
		display: flex;
		flex-direction: column;
		gap: 5px;
		min-width: 0;
	}
	.rl-title h1 {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: calc(var(--mg-fs) * 1.3);
		font-weight: 700;
		letter-spacing: -0.01em;
	}
	.rl-meta {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 4px 0;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.rl-meta > span:not(.rl-tag) + span::before {
		content: '|';
		margin: 0 8px;
		color: var(--mg-text-3);
	}
	.rl-tag {
		margin-right: 10px;
		padding: 1px 10px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--st) 15%, transparent);
		color: var(--st);
		font-size: var(--mg-fs-xs);
		font-weight: 700;
	}
	.running .rl-tag {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.rl-bad {
		color: var(--mg-danger);
		font-weight: 600;
	}
	.rl-acts {
		grid-area: acts;
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: 8px;
	}
	.rl-progress {
		grid-area: prog;
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		grid-template-areas: 'bar pct' 'step step';
		align-items: center;
		gap: 6px 14px;
	}
	.rl-bar {
		grid-area: bar;
		height: 8px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 9%, transparent);
		overflow: hidden;
	}
	.rl-bar span {
		display: block;
		height: 100%;
		border-radius: var(--mg-r-sm);
		background: var(--st);
		transition: width 600ms ease;
	}
	.running .rl-bar span {
		background: var(--mg-accent);
	}
	.rl-pct {
		grid-area: pct;
		min-width: 3.2em;
		text-align: right;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		color: var(--st);
	}
	.running .rl-pct {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.rl-step {
		grid-area: step;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.rl-why {
		grid-column: 1 / -1;
		padding: 8px 12px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-danger) 9%, transparent);
		color: var(--mg-danger);
		font-size: var(--mg-fs-sm);
		overflow-wrap: anywhere;
	}
	.rl-error {
		color: var(--mg-danger);
		font-size: var(--mg-fs-sm);
	}

	/* ---- terminal and facts ---- */
	.rl-body {
		flex: 1 1 auto;
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(260px, 340px);
		gap: var(--cr-gutter, 18px);
		min-height: 420px;
	}

	/* Terminal stays dark in both themes. */
	.rl-term {
		--tm-ink: #e4e8ec;
		--tm-dim: #9aa3ab;
		--tm-rule: rgba(255, 255, 255, 0.09);
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
		border: 1px solid color-mix(in srgb, var(--mg-border) 60%, #000);
		border-radius: var(--mg-r);
		background: #14171b;
		color: var(--tm-ink);
		box-shadow: var(--cr-card-shadow);
		overflow: hidden;
	}
	.rl-term-bar {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 10px 14px 10px var(--mg-pad);
		border-bottom: 1px solid var(--tm-rule);
		font-size: var(--mg-fs-sm);
	}
	.rl-dots {
		display: flex;
		gap: 6px;
	}
	.rl-dots i {
		width: 11px;
		height: 11px;
		border-radius: 50%;
		background: var(--mg-danger);
	}
	.rl-dots i:nth-child(2) {
		background: var(--mg-warn);
	}
	.rl-dots i:last-child {
		background: var(--mg-ok);
	}
	.rl-term-title {
		font-weight: 650;
	}
	.rl-term-n {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--tm-dim);
	}
	.rl-live {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		font-size: var(--mg-fs-xs);
		font-weight: 650;
		color: color-mix(in srgb, var(--mg-ok) 70%, #fff);
	}
	.rl-live i {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: currentColor;
	}
	.rl-term-btn {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		height: 28px;
		padding: 0 12px;
		border: 1px solid var(--tm-rule);
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--tm-dim);
		font: inherit;
		font-size: var(--mg-fs-xs);
		cursor: pointer;
	}
	.rl-term-btn:hover {
		color: var(--tm-ink);
	}
	.rl-term-btn[aria-pressed='true'] {
		border-color: rgba(255, 255, 255, 0.22);
		background: rgba(255, 255, 255, 0.08);
		color: var(--tm-ink);
	}
	.rl-cmd {
		margin: 0;
		padding: 10px var(--mg-pad) 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: color-mix(in srgb, var(--mg-accent) 60%, #fff);
	}
	.rl-out {
		flex: 1 1 0;
		min-height: 0;
		margin: 0;
		padding: 10px var(--mg-pad) 18px;
		overflow: auto;
		font-size: var(--mg-fs-xs);
		line-height: 1.6;
		white-space: pre;
		color: color-mix(in srgb, var(--tm-ink) 88%, transparent);
	}
	.rl-out.wrap {
		white-space: pre-wrap;
		word-break: break-word;
	}
	.rl-out .ok {
		color: color-mix(in srgb, var(--mg-ok) 70%, #fff);
	}
	.rl-out .warn {
		color: color-mix(in srgb, var(--mg-warn) 75%, #fff);
	}
	.rl-out .err {
		color: color-mix(in srgb, var(--mg-danger) 75%, #fff);
	}
	.rl-out .dim {
		color: var(--tm-dim);
	}
	.rl-cursor {
		display: inline-block;
		width: 8px;
		height: 14px;
		vertical-align: text-bottom;
		background: var(--mg-ok);
	}

	.rl-info {
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow);
		overflow: auto;
	}
	.rl-info h2 {
		padding: 14px var(--mg-pad);
		border-bottom: 1px solid var(--mg-border);
		font-size: var(--cr-fs-section, var(--mg-fs));
		font-weight: 650;
	}
	.rl-info dl {
		display: flex;
		flex-direction: column;
		padding: 4px var(--mg-pad) 12px;
	}
	.rl-info dl > div {
		display: grid;
		grid-template-columns: 7.5em minmax(0, 1fr);
		align-items: baseline;
		gap: 12px;
		padding: 9px 0;
		border-bottom: 1px solid var(--cr-rule, var(--mg-border));
		font-size: var(--mg-fs-sm);
	}
	.rl-info dl > div:last-child {
		border-bottom: none;
	}
	.rl-info dl > div.wide {
		grid-template-columns: minmax(0, 1fr);
		gap: 6px;
	}
	.rl-info dt {
		color: var(--mg-text-3);
		font-size: var(--mg-fs-xs);
	}
	.rl-info dt b {
		margin-left: 4px;
		font-weight: 600;
		color: var(--mg-text-2);
	}
	.rl-info dd {
		overflow-wrap: anywhere;
	}
	.rl-info dd.mg-mono {
		font-size: var(--mg-fs-xs);
	}
	.rl-chips {
		display: flex;
		flex-wrap: wrap;
		gap: 5px;
	}
	.rl-chips span {
		padding: 1px 9px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-accent) 12%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
		font-size: var(--mg-fs-xs);
	}
	.rl-path {
		font-size: var(--mg-fs-xs);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.rl-path:hover {
		text-decoration: underline;
		text-underline-offset: 3px;
	}

	@keyframes rl-turn {
		to {
			transform: rotate(360deg);
		}
	}
	:global([data-motion='off']) .rl,
	:global([data-motion='off']) .rl * {
		animation: none !important;
		transition: none !important;
	}

	@media (max-width: 980px) {
		.rl-body {
			grid-template-columns: minmax(0, 1fr);
		}
		.rl-term {
			height: 70vh;
		}
	}
	@media (max-width: 720px) {
		.rl-head {
			grid-template-columns: auto auto minmax(0, 1fr);
			grid-template-areas:
				'back mark title'
				'acts acts acts'
				'prog prog prog';
			gap: 12px;
			padding: 16px;
		}
		.rl-mark {
			width: 38px;
			height: 38px;
		}
		.rl-title h1 {
			white-space: normal;
			font-size: var(--mg-fs-lg);
		}
		.rl-acts {
			justify-content: flex-start;
		}
	}
</style>
