<script lang="ts">
	import { genomeList } from '$lib/crisp/genomes';
	import Readiness from '$lib/workspace/blocks/Readiness.svelte';
	import AnalyzeBoard from '$lib/crisp/AnalyzeBoard.svelte';
	import { ws } from '$lib/workspace/data.svelte';

	/**
	 * Analyze page: genome selection, run setup and the start button, with a status line under the
	 * title and Atlas's evidence grid while a run goes.
	 */
	const n = $derived(ws.genomes.length);
	const genomes = $derived(genomeList());
	const waiting = $derived(genomes.filter((g) => g.file && g.state !== 'done'));
	const done = $derived(genomes.filter((g) => g.state === 'done'));
	const plural = (count: number, one: string, many = one + 's') => `${count} ${count === 1 ? one : many}`;
	/* True unless a required item is known to be missing (rows still being checked do not count). */
	const setupOk = $derived(!ws.setup.some((r) => r.required && (r.tone === 'warn' || r.tone === 'danger')));

	/** Status line and the next action, if any. */
	const status = $derived.by((): { text: string; action?: { label: string; href: string } } => {
		const p = ws.progress;
		if (!ws.loaded) return { text: 'Loading…' };
		if (ws.active && p)
			return {
				text: `Annotating${p.current ? ` ${p.current}` : ''}: ${p.stage.toLowerCase()}, ${p.genomes.filter((g) => g.state === 'done').length} of ${p.genomes.length} genomes done.`,
				action: { label: 'View log', href: `/crisp/runs/${ws.active.id}` }
			};
		if (ws.active) return { text: `${ws.active.label.replace(/ with .*$/, '')}.`, action: { label: 'View log', href: `/crisp/runs/${ws.active.id}` } };
		if (!n) return { text: 'No genomes yet. Add FASTA files to start.', action: { label: 'Add genomes', href: '/crisp/genomes' } };
		if (waiting.length && !setupOk)
			return {
				text: `${plural(waiting.length, 'genome')} waiting. Install is not complete (${ws.setupReady.ok} of ${ws.setupReady.total}).`,
				action: { label: 'Go to Install', href: '/crisp/setup' }
			};
		if (waiting.length) return { text: `${plural(waiting.length, 'genome')} ready to annotate.` };
		return { text: `All ${plural(done.length, 'genome')} annotated.`, action: { label: 'Open Results', href: '/crisp/results' } };
	});

	/** Evidence-grid columns: the running run's tools (all when it names none), else the chosen ones. */
	const runTools = $derived.by(() => {
		const args = ws.active?.args ?? [];
		const named = args.flatMap((a, i) => (args[i - 1] === '--tool' ? [a] : []));
		const list = named.length
			? named
			: ws.active?.tools?.length
				? ws.active.tools
				: !ws.active && ws.chosenTools.length
					? ws.chosenTools
					: ws.tools.map((t) => t.name);
		return ['operon', ...list.filter((t) => t !== 'operon')];
	});
</script>

<svelte:head><title>Analyze | MARGIE</title></svelte:head>

<div class="cr-page" data-shade="page-analyze">
	<header class="cr-head">
		<h1 class="cr-title">Analyze</h1>
		<p class="cr-lede">{status.text}</p>
		<span class="cr-meta">{n ? `${plural(n, 'genome')}${done.length ? `, ${done.length} annotated` : ''}` : ''}</span>
		{#if status.action}
			<div class="cr-head-acts">
				<a class="mg-btn" href={status.action.href}>{status.action.label}</a>
			</div>
		{/if}
	</header>

	<Readiness />

	<AnalyzeBoard tools={runTools} />
</div>
