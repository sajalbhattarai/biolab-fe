<script lang="ts">
	import { STAGE_NAMES, type AnnotateProgress } from '$lib/workspace/progress';

	/**
	 * Draws a run as rings: the outer one counts finished genomes, the main one
	 * shows the current genome's stages (done teal, running amber). Build and
	 * setup runs, which have no stages, get a slowly turning arc.
	 */
	let {
		progress = null,
		label = '',
		size = 220,
		compact = false
	}: { progress?: AnnotateProgress | null; label?: string; size?: number; compact?: boolean } = $props();

	const N = STAGE_NAMES.length;
	const GAP = 3;
	const at = $derived.by(() => {
		if (!progress) return -1;
		if (progress.stage === 'Comparing genomes' || progress.stage === 'Finishing') return N;
		if (progress.stage === 'Starting') return 0;
		return STAGE_NAMES.indexOf(progress.stage);
	});
	const done = $derived(progress ? progress.genomes.filter((g) => g.state === 'done').length : 0);

	const point = (r: number, deg: number) => {
		const a = (deg * Math.PI) / 180;
		return [50 + r * Math.sin(a), 50 - r * Math.cos(a)];
	};
	const arc = (r: number, a0: number, a1: number) => {
		const [x0, y0] = point(r, a0);
		const [x1, y1] = point(r, a1);
		return `M${x0.toFixed(2)} ${y0.toFixed(2)}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
	};
	const seg = (i: number) => arc(37, (i / N) * 360 + GAP / 2, ((i + 1) / N) * 360 - GAP / 2);
	const outerDone = $derived(progress ? Math.max(0.001, Math.min(0.999, progress.fraction)) * 360 : 0);
</script>

<div class="run-ring" class:compact style="--size: {size}px">
	<svg viewBox="0 0 100 100" width={size} height={size} aria-hidden="true">
		<circle cx="50" cy="50" r="46.5" class="track thin" />
		{#if progress}
			<path d={arc(46.5, 0, outerDone)} class="outer" />
			{#each STAGE_NAMES as name, i (name)}
				<path d={seg(i)} class="stage" class:done={i < at} class:now={i === at} />
			{/each}
		{:else}
			<circle cx="50" cy="50" r="37" class="track" />
			<g class="spin"><path d={arc(37, 0, 80)} class="stage now" /></g>
		{/if}
	</svg>
	{#if !compact}
		<div class="centre">
			{#if progress}
				<span class="stage-name">{at >= N ? progress.stage : (STAGE_NAMES[at] ?? progress.stage)}</span>
				{#if progress.detail && at < N}<span class="detail">{progress.detail}</span>{/if}
				{#if progress.current && at < N}<span class="genome" title={progress.current}>{progress.current}</span>{/if}
				<span class="count">{done} of {progress.genomes.length} genome{progress.genomes.length === 1 ? '' : 's'}</span>
			{:else}
				<span class="stage-name">{label || 'Working'}</span>
			{/if}
		</div>
	{/if}
</div>

<style>
	.run-ring {
		position: relative;
		width: var(--size);
		height: var(--size);
		flex-shrink: 0;
	}
	svg {
		display: block;
	}
	.track {
		fill: none;
		stroke: var(--at-track);
		stroke-width: 7;
	}
	.track.thin {
		stroke-width: 1.4;
	}
	.outer {
		fill: none;
		stroke: var(--at-teal);
		stroke-width: 1.4;
		stroke-linecap: round;
		transition: d var(--mo-3) var(--mo-ease);
	}
	.stage {
		fill: none;
		stroke: var(--at-track);
		stroke-width: 7;
		transition: stroke var(--mo-3) var(--mo-ease);
	}
	.stage.done {
		stroke: var(--at-teal);
	}
	.stage.now {
		stroke: var(--at-amber);
	}
	:global([data-motion='full']) .stage.now,
	.spin {
		transform-origin: 50px 50px;
	}
	:global([data-motion='full']) .spin,
	:global([data-motion='subtle']) .spin {
		animation: turn calc(2.8s * var(--mo-loop)) linear infinite;
	}
	.centre {
		position: absolute;
		inset: 22%;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 2px;
		text-align: center;
		min-width: 0;
	}
	.stage-name {
		font-family: var(--at-display);
		font-size: calc(var(--size) * 0.085);
		font-weight: 700;
		letter-spacing: -0.01em;
		line-height: 1.1;
	}
	.detail {
		color: var(--at-amber-ink);
		font-size: 12px;
		font-weight: 600;
	}
	.genome {
		max-width: 100%;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-family: var(--mg-mono);
		font-size: 11px;
		color: var(--at-ink-2);
	}
	.count {
		margin-top: 2px;
		font-size: 11px;
		color: var(--at-ink-3);
	}
	@keyframes turn {
		to {
			transform: rotate(360deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.stage.now,
		.spin {
			animation: none !important;
		}
	}
</style>
