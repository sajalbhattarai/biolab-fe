<script lang="ts">
	import { uiBase } from '../base.svelte';
	import { ws } from '../data.svelte';

	/** Live status of the current run on the page that started it: progress, genome, stage, last message. */

	const run = $derived(ws.active);
	const p = $derived(ws.progress);
	const pct = $derived(p ? Math.round(p.fraction * 100) : (run?.progress ?? 0));
	const done = $derived(p ? p.genomes.filter((g) => g.state === 'done').length : 0);
	const what = $derived(
		run?.kind === 'build' ? 'Installing' : run?.kind === 'setup' ? 'Installing' : p ? p.stage : (run?.progressText ?? 'Working')
	);
</script>

{#if run}
	<div class="now">
		<div class="top">
			<span class="what">{what}</span>
			{#if p?.current}<span class="mg-mono who">{p.current}</span>{/if}
			<span class="mg-grow"></span>
			<span class="pct">{pct}%</span>
		</div>

		<div class="bar" role="progressbar" aria-valuenow={pct} aria-valuemin="0" aria-valuemax="100">
			<div style="width: {Math.max(2, pct)}%"></div>
		</div>

		<p class="sub mg-note">
			{#if p}
				{done} of {p.genomes.length} genomes{p.detail ? ` | ${p.detail}` : ''}
			{:else if run.progressText}
				{run.progressText}
			{:else}
				{run.label.replace(/ with .*$/, '')}
			{/if}
		</p>

		{#if ws.lastLine}<p class="log mg-mono">{ws.lastLine}</p>{/if}

		<div class="acts">
			<a class="pill" href={uiBase.to(`/runs/${run.id}`)}>Watch the log</a>
			<button type="button" class="pill stop" onclick={() => ws.stop(run.id)}>Stop</button>
			{#if ws.running.length > 1}<span class="mg-note">{ws.running.length} jobs going</span>{/if}
		</div>
	</div>
{/if}

<style>
	.now {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	.top {
		display: flex;
		align-items: baseline;
		gap: 10px;
		min-width: 0;
	}
	.what {
		font-size: var(--mg-fs-lg);
		font-weight: 650;
	}
	.who {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		color: var(--mg-text-2);
	}
	.pct {
		font-size: calc(var(--mg-fs-lg) * 1.2);
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.bar {
		height: 10px;
		overflow: hidden;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 9%, transparent);
	}
	.bar > div {
		height: 100%;
		border-radius: var(--mg-r-sm);
		background: var(--mg-accent);
		transition: width 600ms ease;
	}
	.sub {
		margin-top: -2px;
	}
	.log {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		padding: 8px 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
		color: var(--mg-text-2);
		font-size: var(--mg-fs-xs);
	}
	.acts {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 8px;
	}
	.acts > .mg-note {
		grid-column: 1 / -1;
		text-align: center;
	}
	.pill {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		height: 34px;
		padding: 0 14px;
		border: 1px solid color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-accent-ink, var(--mg-accent));
		font: inherit;
		font-size: var(--mg-fs-sm);
		font-weight: 600;
		cursor: pointer;
	}
	.pill:hover {
		background: color-mix(in srgb, var(--mg-accent) 9%, transparent);
	}
	.pill.stop {
		border-color: color-mix(in srgb, var(--mg-danger) 40%, var(--mg-border));
		color: var(--mg-danger);
	}
	.pill.stop:hover {
		background: color-mix(in srgb, var(--mg-danger) 9%, transparent);
	}
	:global([data-motion='off']) .bar > div {
		transition: none;
	}
</style>
