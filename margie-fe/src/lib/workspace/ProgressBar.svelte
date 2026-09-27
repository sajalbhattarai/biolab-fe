<script lang="ts">
	/** Progress bar for a long copy: percentage, current step in words, and a folded log. */
	let {
		percent = 0,
		state = 'running',
		label = '',
		detail = '',
		log = []
	}: {
		percent?: number;
		state?: 'queued' | 'running' | 'done' | 'failed';
		label?: string;
		detail?: string;
		log?: string[];
	} = $props();

	const pct = $derived(Math.max(0, Math.min(100, Math.round(percent))));
	const waiting = $derived(state === 'queued');
</script>

<div class="pb" class:failed={state === 'failed'} class:done={state === 'done'}>
	<div class="pb-head">
		<span class="pb-label">{label}</span>
		<span class="pb-pct" aria-hidden="true">{waiting ? 'waiting' : `${pct}%`}</span>
	</div>
	<div
		class="pb-track"
		class:waiting
		role="progressbar"
		aria-label={label}
		aria-valuemin="0"
		aria-valuemax="100"
		aria-valuenow={waiting ? undefined : pct}
		aria-valuetext={waiting ? 'waiting to start' : `${pct}%`}
	>
		<span class="pb-fill" style="width: {waiting ? 100 : pct}%"></span>
	</div>
	{#if detail}<p class="pb-detail">{detail}</p>{/if}
	{#if log.length}
		<details class="pb-log">
			<summary>Details</summary>
			<pre class="mg-mono">{log.join('\n')}</pre>
		</details>
	{/if}
</div>

<style>
	.pb {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.pb-head {
		display: flex;
		align-items: baseline;
		gap: 12px;
		font-size: var(--mg-fs-sm);
	}
	.pb-label {
		flex: 1 1 auto;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-weight: 600;
	}
	.pb-pct {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
		color: var(--mg-text-2);
	}
	.pb-track {
		position: relative;
		height: 10px;
		overflow: hidden;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 10%, transparent);
	}
	.pb-fill {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: var(--mg-accent);
		transition: width var(--mo-3, 300ms) var(--mo-ease, ease);
	}
	/* Queued: a moving stripe instead of a fill. */
	.pb-track.waiting .pb-fill {
		background: repeating-linear-gradient(
			-45deg,
			color-mix(in srgb, var(--mg-accent) 35%, transparent) 0 10px,
			color-mix(in srgb, var(--mg-accent) 15%, transparent) 10px 20px
		);
		background-size: 28px 28px;
		animation: pb-wait calc(900ms * var(--mo-loop, 1)) linear infinite;
	}
	@keyframes pb-wait {
		to {
			background-position: 28px 0;
		}
	}
	.done .pb-fill {
		background: var(--mg-ok);
	}
	.failed .pb-fill {
		background: var(--mg-danger);
	}
	.pb-detail {
		margin: 0;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-2);
	}
	.failed .pb-detail {
		color: var(--mg-danger);
	}
	.pb-log summary {
		cursor: pointer;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.pb-log pre {
		max-height: 220px;
		overflow: auto;
		margin: 6px 0 0;
		padding: 8px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
		font-size: var(--mg-fs-xs);
		line-height: 1.45;
		white-space: pre-wrap;
	}
</style>
