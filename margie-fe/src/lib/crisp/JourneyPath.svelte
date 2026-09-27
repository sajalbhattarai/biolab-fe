<script lang="ts">
	import { Check } from 'lucide-svelte';
	import { ws } from '$lib/workspace/data.svelte';

	/** Guided mode's path (set up, add genomes, run, explore), filled as far as the real state has got.
	 *  Four equal tiles across the width; `links` points the steps elsewhere (Modern's pages by default). */
	let {
		links = { setup: '/crisp/setup', genomes: '/crisp/genomes', run: '/crisp#run', explore: '/crisp/results' }
	}: { links?: { setup: string; genomes: string; run: string; explore: string } } = $props();

	const steps = $derived([
		{ label: 'Set up', note: 'Tools and databases', href: links.setup, done: !!ws.overview && ws.setupReady.ok === ws.setupReady.total },
		{ label: 'Add genomes', note: 'FASTA files', href: links.genomes, done: ws.genomes.length > 0 },
		{ label: 'Run', note: 'Gene caller, then tools', href: links.run, done: ws.runs.some((r) => r.kind === 'annotate' && r.status === 'completed') || !!ws.active },
		{ label: 'Explore', note: 'Reports per genome', href: links.explore, done: ws.finished.length > 0 }
	]);
	const current = $derived(Math.max(0, steps.findIndex((s) => !s.done)));
	const allDone = $derived(steps.every((s) => s.done));
	const doneCount = $derived(steps.filter((s) => s.done).length);
</script>

<nav class="jp" aria-label="Steps">
	<ol style="--k: {steps.length}">
		{#each steps as s, i (s.label)}
			{@const now = i === current && !s.done}
			<li class:done={s.done} class:now style="--i: {i}">
				<a href={s.href} aria-current={now ? 'step' : undefined}>
					<span class="jp-dot" aria-hidden="true">{#if s.done}<Check size={15} strokeWidth={3} />{:else}{i + 1}{/if}</span>
					<span class="jp-words">
						<span class="jp-label">{s.label}</span>
						<span class="jp-note">{s.done ? 'Done' : now ? 'Next' : s.note}</span>
					</span>
				</a>
			</li>
		{/each}
	</ol>
	<span class="jp-meta" aria-live="polite">{allDone ? 'All done' : `${doneCount} of ${steps.length}`}</span>
</nav>

<style>
	.jp {
		display: flex;
		align-items: center;
		gap: 18px;
		padding: 10px 18px 10px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow, none);
		color: var(--mg-text);
	}
	ol {
		flex: 1;
		display: grid;
		grid-template-columns: repeat(var(--k), minmax(0, 1fr));
		gap: 8px;
		min-width: 0;
	}
	li {
		position: relative;
		min-width: 0;
	}
	a {
		display: flex;
		align-items: center;
		gap: 12px;
		height: 100%;
		padding: 10px 14px;
		border: 1px solid var(--mg-border);
		border-radius: calc(var(--mg-r) - 2px);
		background: var(--mg-surface);
		transition:
			background-color 160ms ease,
			border-color 160ms ease;
	}
	a:hover {
		border-color: var(--mg-border-strong);
	}
	.done a {
		background: color-mix(in srgb, var(--mg-accent) 5%, var(--mg-surface));
	}
	.now a {
		border-color: color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-accent) 9%, var(--mg-surface));
	}
	.jp-dot {
		flex: none;
		display: grid;
		place-items: center;
		width: 30px;
		height: 30px;
		border-radius: 50%;
		border: 2px solid var(--mg-border-strong);
		background: var(--mg-surface);
		color: var(--mg-text-3);
		font-size: var(--mg-fs-xs);
		font-weight: 700;
	}
	.done .jp-dot {
		border-color: var(--mg-accent);
		background: var(--mg-accent);
		color: var(--mg-on-accent, #fff);
	}
	.now .jp-dot {
		border-color: var(--mg-accent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.jp-words {
		display: flex;
		flex-direction: column;
		min-width: 0;
		line-height: 1.25;
	}
	.jp-label {
		font-size: var(--mg-fs-sm);
		font-weight: 650;
		color: var(--mg-text);
	}
	li:not(.done):not(.now) .jp-label {
		color: var(--mg-text-2);
	}
	.jp-note {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.now .jp-note {
		color: var(--mg-accent-ink, var(--mg-accent));
		font-weight: 600;
	}
	.jp-meta {
		flex: none;
		padding: 4px 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
		color: var(--mg-text-2);
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	:global([data-motion='off']) .jp * {
		animation: none !important;
		transition: none !important;
	}

	@media (max-width: 860px) {
		.jp {
			padding: 8px;
		}
		ol {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.jp-meta {
			display: none;
		}
	}
	@media (max-width: 460px) {
		a {
			gap: 8px;
			padding: 8px;
		}
		.jp-dot {
			width: 26px;
			height: 26px;
		}
	}
</style>
