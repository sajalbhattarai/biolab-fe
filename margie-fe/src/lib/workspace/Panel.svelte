<script lang="ts">
	import type { Snippet } from 'svelte';
	import { ChevronLeft, ChevronRight, EyeOff, MoveHorizontal } from 'lucide-svelte';
	import { PANEL_TITLES, type PanelId } from './prefs';
	import Fold from './motion/Fold.svelte';
	import FoldTitle from './motion/FoldTitle.svelte';
	import FoldToggle from './motion/FoldToggle.svelte';
	import { ui } from './ui.svelte';

	/** One workspace panel: a title, its actions, and in guided mode its step number and a hint. */
	let { id, meta = '', actions, children }: { id: PanelId; meta?: string; actions?: Snippet; children: Snippet } = $props();

	const STEPS: Partial<Record<PanelId, { n: number; hint: string }>> = {
		status: { n: 1, hint: 'Build the tools and download the reference data, once.' },
		genomes: { n: 2, hint: 'Add FASTA files. Domain and genetic code are optional.' },
		run: { n: 3, hint: 'Choose how much to run, then start.' },
		results: { n: 4, hint: 'Open a finished genome to explore it.' }
	};

	const pref = $derived(ui.prefs.panels.find((p) => p.id === id));
	const folded = $derived(ui.isFolded(`panel:${id}`));
	const step = $derived(ui.guided ? STEPS[id] : undefined);
</script>

<section id="panel-{id}" data-shade={id} aria-labelledby="panel-{id}-title" class="panel mg-card" class:editing={ui.editLayout} class:folded>
	<header class="mg-card-head">
		<FoldTitle id="panel:{id}" headingId="panel-{id}-title">
			{#if step}<span class="num">{step.n}</span>{/if}{PANEL_TITLES[id]}
		</FoldTitle>
		{#if meta}<span class="mg-note">{meta}</span>{/if}
		<span class="mg-grow"></span>
		{#if ui.editLayout}
			<span class="tools">
				<button type="button" class="mg-icon-btn" aria-label="Move {PANEL_TITLES[id]} earlier" title="Move earlier" onclick={() => ui.movePanel(id, -1)}>
					<ChevronLeft size={15} />
				</button>
				<button type="button" class="mg-icon-btn" aria-label="Move {PANEL_TITLES[id]} later" title="Move later" onclick={() => ui.movePanel(id, 1)}>
					<ChevronRight size={15} />
				</button>
				<button
					type="button"
					class="mg-icon-btn"
					aria-label={pref && pref.span > 1 ? `Make ${PANEL_TITLES[id]} narrower` : `Make ${PANEL_TITLES[id]} wider`}
					title={pref && pref.span > 1 ? 'Narrower' : 'Wider'}
					onclick={() => ui.toggleSpan(id)}
				>
					<MoveHorizontal size={15} />
				</button>
				<button type="button" class="mg-icon-btn" aria-label="Hide {PANEL_TITLES[id]}" title="Hide" onclick={() => ui.togglePanel(id)}>
					<EyeOff size={15} />
				</button>
			</span>
		{:else}
			<span class="tools">
				{#if actions}{@render actions()}{/if}
				<FoldToggle id="panel:{id}" />
			</span>
		{/if}
	</header>
	<Fold id="panel:{id}" class="panel-fold">
		{#if step}<p class="hint">{step.hint}</p>{/if}
		<div class="body" inert={ui.editLayout}>
			{@render children()}
		</div>
	</Fold>
</section>

<style>
	.panel {
		display: flex;
		flex-direction: column;
		min-width: 0;
		height: 100%;
	}
	/* A collapsed panel shows only its header. */
	.panel.folded {
		height: auto;
	}
	.panel :global(.panel-fold) {
		flex-grow: 1;
		min-height: 0;
	}
	.panel :global(.panel-fold > .mo-fold-inner) {
		display: flex;
		flex-direction: column;
	}
	.panel.editing {
		border-style: dashed;
		border-color: var(--mg-border-strong);
	}
	.panel.editing .body {
		opacity: 0.5;
	}
	.mg-card-head {
		flex-wrap: wrap;
		row-gap: 6px;
	}
	.num {
		margin-right: 8px;
		font-size: var(--mg-fs-sm);
		font-weight: 500;
		color: var(--mg-text-3);
		font-variant-numeric: tabular-nums;
	}
	.tools {
		display: flex;
		align-items: center;
		gap: 14px;
	}
	.editing .tools {
		gap: 0;
	}
	.hint {
		padding: 4px var(--mg-pad) 0;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-3);
	}
	.body {
		display: flex;
		flex-direction: column;
		flex-grow: 1;
		min-height: 0;
	}
</style>
