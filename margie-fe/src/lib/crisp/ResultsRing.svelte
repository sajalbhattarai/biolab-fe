<script lang="ts" module>
	let uid = 0;
</script>

<script lang="ts">
	import type { GenomeGlyph } from '$lib/workspace/final-summary';

	/**
	 * Draws a genome as a ring of arcs (forward strand outside, reverse inside),
	 * each coloured by its genes' majority confidence tier (--mg-tier-N). Without
	 * a map it is a dashed ring, turning while the genome runs.
	 */
	let {
		glyph = null,
		size = 96,
		state = 'done',
		children
	}: {
		glyph?: GenomeGlyph | null;
		size?: number;
		state?: 'done' | 'running' | 'pending';
		children?: import('svelte').Snippet;
	} = $props();

	const id = `rb-ring-${++uid}`;
	const GAP = 0.4;

	const point = (r: number, deg: number) => {
		const a = (deg * Math.PI) / 180;
		return [50 + r * Math.sin(a), 50 - r * Math.cos(a)];
	};
	const arc = (r: number, a0: number, a1: number) => {
		const [x0, y0] = point(r, a0);
		const [x1, y1] = point(r, a1);
		return `M${x0.toFixed(2)} ${y0.toFixed(2)}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
	};

	/** Merges neighbouring bins of one tier into one arc. */
	function runs(bins: number[]) {
		const n = bins.length;
		const out: { tier: number; a0: number; a1: number }[] = [];
		for (let i = 0; i < n; ) {
			let j = i;
			while (j + 1 < n && bins[j + 1] === bins[i]) j++;
			if (bins[i] >= 0) out.push({ tier: bins[i], a0: (i / n) * 360 + GAP / 2, a1: ((j + 1) / n) * 360 - GAP / 2 });
			i = j + 1;
		}
		return out;
	}
	const outer = $derived(glyph ? runs(glyph.plus) : []);
	const inner = $derived(glyph ? runs(glyph.minus) : []);
</script>

<div class="rb-ring {state}" style="--size: {size}px">
	<svg viewBox="0 0 100 100" role="img" aria-label={glyph ? 'Genome map: genes by confidence tier, forward strand outside' : state === 'running' ? 'Being annotated' : 'No map yet'}>
		{#if glyph}
			<defs>
				<mask id={id}>
					<circle class="sweep" cx="50" cy="50" r="25" fill="none" stroke="#fff" stroke-width="50" pathLength="1" transform="rotate(-90 50 50)" />
				</mask>
			</defs>
			<circle cx="50" cy="50" r="47.5" class="backbone" />
			<g mask="url(#{id})">
				{#each outer as s (s.a0)}<path d={arc(41.5, s.a0, s.a1)} style="stroke: var(--mg-tier-{s.tier})" stroke-width="7" />{/each}
				{#each inner as s (s.a0)}<path d={arc(32.5, s.a0, s.a1)} style="stroke: var(--mg-tier-{s.tier})" stroke-width="7" />{/each}
			</g>
			<circle cx="50" cy="50" r="27.5" class="backbone faint" />
		{:else}
			<g class="dashes">
				<circle cx="50" cy="50" r="41.5" stroke-dasharray="3 3.6" />
				<circle cx="50" cy="50" r="32.5" stroke-dasharray="2.4 3" />
			</g>
		{/if}
	</svg>
	{#if children}<div class="rb-ring-mid">{@render children()}</div>{/if}
</div>

<style>
	.rb-ring {
		position: relative;
		flex-shrink: 0;
		width: var(--size);
		height: var(--size);
	}
	svg {
		display: block;
		width: 100%;
		height: 100%;
		overflow: visible;
	}
	path {
		fill: none;
	}
	.backbone {
		fill: none;
		stroke: var(--mg-border-strong);
		stroke-width: 0.8;
	}
	.backbone.faint {
		stroke: var(--mg-border);
	}
	.dashes circle {
		fill: none;
		stroke: var(--mg-text-3);
		stroke-width: 7;
		opacity: 0.28;
	}
	.running .dashes circle {
		stroke: var(--mg-accent);
		opacity: 0.6;
	}
	.dashes {
		transform-origin: 50px 50px;
	}
	.sweep {
		stroke-dasharray: 1 1;
	}
	.rb-ring-mid {
		position: absolute;
		inset: 22%;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		text-align: center;
		line-height: 1.15;
	}
	:global([data-motion='off']) .sweep,
	:global([data-motion='off']) .dashes {
		animation: none !important;
	}
	@media (prefers-reduced-motion: reduce) {
		.sweep,
		.dashes {
			animation: none !important;
		}
	}
</style>
