<script lang="ts">
	import { uiBase } from '../base.svelte';
	import { backend } from '../backend.svelte';
	import { ws } from '../data.svelte';
	import { ui } from '../ui.svelte';
	import ProgressBar from '../ProgressBar.svelte';
	import { ArrowRight, CircleAlert } from 'lucide-svelte';

	/**
	 * Start button with a sentence on what it will do; when blocked, it is replaced by the
	 * first blocker and its fix.
	 */

	const runtimeReady = $derived(ws.overview?.runtime.ready ?? true);
	const n = $derived(ws.genomes.length);
	const tools = $derived(ws.chosenTools.length);
	const plural = (count: number, one: string, many = one + 's') => `${count} ${count === 1 ? one : many}`;

	/** The first blocker and its fix. */
	const blocker = $derived.by((): { text: string; fix?: { label: string; run: () => void }; href?: string } | null => {
		if (!n) return { text: backend.cluster ? 'No genomes in the input folder on the cluster yet.' : 'No genomes to annotate yet.', href: uiBase.to('/genomes') };
		if (!ws.tools.length) return { text: 'Still reading which tools are available.' };
		if (ws.running.length) {
			const r = ws.running[0];
			return { text: `${r.label.replace(/ with .*$/, '')} is still going.`, href: uiBase.to(`/runs/${r.id}`) };
		}
		if (!runtimeReady) return { text: backend.cluster ? 'The cluster cannot be reached.' : 'The container app is not running.', href: uiBase.to('/setup') };
		// Backend-reported rows (cluster): the first not ready, and where to fix it.
		const unready = ws.setup.find((r) => r.required && r.tone !== 'ok' && r.href);
		if (unready) return { text: `${unready.label}: ${unready.value.toLowerCase()}.`, href: uiBase.to(unready.href as string) };
		const need = [...new Set([...ws.needs.images, ...ws.needs.databases])];
		if (need.length && backend.cluster) {
			// Cluster tools are installed by its administrators; this only points there.
			return {
				text: `${plural(need.length, 'tool')} not where the cluster config points: ${need.slice(0, 3).join(', ')}${need.length > 3 ? '…' : ''}`,
				href: uiBase.to('/setup#installed')
			};
		}
		if (need.length) {
			return {
				text: `${plural(need.length, 'tool')} still to install: ${need.slice(0, 3).join(', ')}${need.length > 3 ? '…' : ''}`,
				fix: { label: 'Install them', run: () => ws.build('all', need) }
			};
		}
		return null;
	});

	/** What the button will do. */
	const sentence = $derived(
		tools ? `Annotate ${plural(n, 'genome')} with ${plural(tools, 'tool')}` : `Call genes on ${plural(n, 'genome')}`
	);
	const outputDir = $derived(ws.resultRoots.outputRoot.split('/').filter(Boolean).at(-1) ?? 'output');
	const onCluster = $derived(backend.cluster ? ' on the cluster' : '');
	const under = $derived(
		tools
			? `the gene caller first, then the annotation tools | results to ${outputDir}/${onCluster}`
			: `no annotation tools chosen | gene calls to ${outputDir}/${onCluster}`
	);

	let starting = $state(false);
	/** True while the user's databases are still being copied. */
	const copying = $derived(ws.storesBusy && !ws.storesOp?.op?.startsWith('backup:'));

	async function start() {
		starting = true;
		const run = await ws.annotate();
		starting = false;
		if (run) ui.notify('Started', 'ok');
	}
</script>

<!-- First cluster run copies the databases to scratch; the run starts when done (ws.start, #watchStores). -->
{#if ws.storesOp && (ws.storesBusy || ws.storesOp.state === 'failed') && !ws.storesOp.op?.startsWith('backup:')}
	<div class="stores-setup">
		<ProgressBar
			percent={ws.storesOp.percent}
			state={ws.storesOp.state}
			label={ws.storesOp.state === 'queued'
				? 'Setting up your databases: waiting for a SLURM slot'
				: `Setting up your databases${ws.storesOp.label && !['Starting', 'Finished'].includes(ws.storesOp.label) ? `: ${ws.storesOp.label}` : ''}`}
			detail={ws.storesOp.state === 'failed'
				? ws.storesOp.message || 'The copy did not finish.'
				: 'A one-time copy of the base databases to your working folder. The run starts by itself when it finishes.'}
			log={[...(ws.storesOp.log ?? []), ...(ws.storesOp.slurm_out ?? [])]}
		/>
	</div>
{/if}
{#if blocker}
	<div class="blocked" role="status">
		<span class="b-icon" aria-hidden="true"><CircleAlert size={18} strokeWidth={2.3} /></span>
		<p>{blocker.text}</p>
		{#if blocker.fix}
			<button type="button" class="b-fix" onclick={blocker.fix.run}>{blocker.fix.label}</button>
		{:else if blocker.href}
			<a class="b-fix" href={blocker.href}>Take me there <ArrowRight size={14} /></a>
		{/if}
	</div>
{:else}
	<button type="button" class="go mg-btn primary" disabled={starting || copying} onclick={start}>
		{starting ? 'Starting…' : copying ? 'Starts when your databases are ready' : sentence}
	</button>
	<p class="under mg-note">{under}</p>
{/if}

<style>
	.go {
		/* Styled explicitly so other .mg-btn rules cannot change it. */
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 10px;
		width: 100%;
		height: calc(var(--mg-ctl) * 1.45);
		border-color: transparent;
		border-radius: var(--mg-r-sm);
		background: var(--mg-accent);
		color: var(--mg-on-accent);
		font-size: var(--mg-fs-lg);
		font-weight: 650;
		box-shadow: none;
	}
	.go::before {
		content: '';
		flex: none;
		width: 12px;
		height: 14px;
		background: currentColor;
		clip-path: polygon(0 0, 100% 50%, 0 100%);
	}
	.go:not(:disabled):hover {
		animation: none;
	}
	.go:disabled {
		box-shadow: none;
	}
	.stores-setup {
		margin-bottom: 12px;
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-surface);
	}
	.under {
		margin-top: 8px;
		text-align: center;
	}
	.blocked {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr);
		align-items: center;
		gap: 12px;
		padding: 14px 16px;
		border: 1px solid color-mix(in srgb, var(--mg-warn) 35%, var(--mg-border));
		border-radius: var(--mg-r);
		background: var(--mg-surface);
		color: var(--mg-text);
		font-size: var(--mg-fs-sm);
	}
	.b-icon {
		display: grid;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--mg-warn) 16%, transparent);
		color: var(--mg-warn);
	}
	.b-fix {
		grid-column: 1 / -1;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		height: calc(var(--mg-ctl) * 1.15);
		padding: 0 16px;
		border: 1px solid color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-accent-ink, var(--mg-accent));
		font: inherit;
		font-weight: 600;
		cursor: pointer;
		transition: background-color 140ms ease;
	}
	.b-fix:hover {
		background: color-mix(in srgb, var(--mg-accent) 9%, transparent);
	}
	:global([data-motion='off']) .go {
		animation: none !important;
	}
</style>
