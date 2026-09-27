<script lang="ts">
	import { Check } from 'lucide-svelte';
	import { page } from '$app/state';
	import { ws } from '$lib/workspace/data.svelte';
	import { backend } from '$lib/workspace/backend.svelte';

	/**
	 * Guided mode's step bar: the four steps from setup to a report, each ticked
	 * when done, the current page marked, and one line on what to do there.
	 * Clean mode leaves it out.
	 */
	const path = $derived(page.url.pathname.replace(/\/$/, '') || '/crisp');

	const steps = $derived([
		{
			n: 1,
			href: '/crisp/setup',
			label: 'Install',
			done: ws.setupReady.total > 0 && ws.setupReady.ok === ws.setupReady.total
		},
		{ n: 2, href: '/crisp/genomes', label: 'Add genomes', done: ws.genomes.length > 0 },
		{ n: 3, href: '/crisp', label: 'Annotate', done: ws.results.length > 0, busy: !!ws.active },
		{ n: 4, href: '/crisp/results', label: 'Read the results', done: ws.finished.length > 0 }
	]);
	const here = (href: string) => (href === '/crisp' ? path === '/crisp' : path.startsWith(href));
	/** The first step not yet done. */
	const next = $derived(steps.find((s) => !s.done)?.n ?? 0);

	const HINTS: [string, string][] = [
		['/crisp/setup', 'Install what runs need: the container app, the tools and their reference data. Each item shows whether it is ready.'],
		['/crisp/genomes', "Drop FASTA files here, then check each genome's domain and genetic code (GTDB-Tk can work them out)."],
		['/crisp/results', 'Pick a genome on the left, then switch between the map, the table and the figures. Show filters both.'],
		['/crisp/files', 'Browse any folder, and click a file to preview it on the right.'],
		['/crisp/runs', 'Every job started from MARGIE, with its log. A failed run can be resumed or restarted from Analyze.'],
		['/crisp/settings', 'Folders, cores and memory, and the steps a run takes. Changes apply to the next run.'],
		['/crisp/view', 'One file on its own page. Back returns to where you were.'],
		['/crisp', 'Choose the tools, then press Annotate. Each genome’s progress fills in below as the run goes.']
	];
	const hint = $derived(HINTS.find(([h]) => here(h))?.[1] ?? '');
	const where = $derived(backend.cluster ? 'on the HPC' : 'on this computer');
</script>

{#if !path.startsWith('/crisp/home')}
	<nav class="guide" aria-label="Steps">
		<ol>
			{#each steps as s, i (s.n)}
				<li class:done={s.done} class:here={here(s.href)} class:next={s.n === next}>
					<a href={s.href} aria-current={here(s.href) ? 'step' : undefined}>
						<span class="n" aria-hidden="true">{#if s.done}<Check size={12} strokeWidth={3} />{:else}{s.n}{/if}</span>
						<span>{s.label}</span>
						{#if s.busy}<span class="busy">running</span>{/if}
					</a>
				</li>
				{#if i < steps.length - 1}<li class="sep" aria-hidden="true"></li>{/if}
			{/each}
		</ol>
		{#if hint}<p class="hint"><span class="sr">Hint {where}: </span>{hint}</p>{/if}
	</nav>
{/if}

<style>
	.guide {
		flex-shrink: 0;
		display: flex;
		align-items: center;
		gap: 10px 24px;
		flex-wrap: wrap;
		padding: 7px 16px;
		border-bottom: 1px solid var(--mg-border);
		background: color-mix(in srgb, var(--mg-accent-base, var(--mg-accent)) 4%, var(--mg-surface));
		font-size: var(--mg-fs-xs);
	}
	ol {
		display: flex;
		align-items: center;
		gap: 6px;
		list-style: none;
	}
	a {
		display: inline-flex;
		align-items: center;
		gap: 7px;
		padding: 3px 8px 3px 4px;
		border-radius: 99px;
		color: var(--mg-text-2);
		text-decoration: none;
		white-space: nowrap;
	}
	a:hover {
		color: var(--mg-text);
		background: color-mix(in srgb, var(--mg-text) 5%, transparent);
	}
	.n {
		display: grid;
		place-items: center;
		width: 20px;
		height: 20px;
		border: 1px solid var(--mg-border-strong);
		border-radius: 50%;
		background: var(--mg-surface);
		font-variant-numeric: tabular-nums;
	}
	.done .n {
		border-color: var(--mg-ok);
		background: var(--mg-ok);
		color: #fff;
	}
	.next .n {
		border-color: var(--mg-accent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.here a {
		background: color-mix(in srgb, var(--mg-accent) 12%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.sep {
		width: 18px;
		height: 1px;
		background: var(--mg-border-strong);
	}
	.busy {
		color: var(--cr-warm, var(--mg-warn));
	}
	.hint {
		flex: 1 1 320px;
		min-width: 0;
		color: var(--mg-text-2);
	}
	.sr {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
	}
	@media (max-width: 820px) {
		.sep {
			display: none;
		}
	}
</style>
