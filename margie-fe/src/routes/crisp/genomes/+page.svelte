<script lang="ts">
	import GenomesBoard from '$lib/crisp/GenomesBoard.svelte';
	import { ws } from '$lib/workspace/data.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { formatBytes } from '$lib/api';
	import { genomeList } from '$lib/crisp/genomes';

	const all = $derived(genomeList());
	/** Genomes in the input folder in a given state; results for removed files belong to Results. */
	const count = (state: string) => all.filter((g) => g.file && g.state === state).length;
	const bytes = $derived(ws.genomes.reduce((a, g) => a + g.size, 0));
	const unset = $derived(ws.genomes.filter((g) => !g.domain || !g.genetic_code).length);
</script>

<svelte:head><title>Genomes | MARGIE</title></svelte:head>

<div class="cr-page" data-shade="page-analyze">
	<div class="cr-head">
		<h1 class="cr-title">Genomes</h1>
		<p class="cr-lede">
			FASTA files in your input folder{backend.cluster ? ' on the cluster' : ''}, with each genome's domain and genetic code: RASTtk needs
			both, and a genome without them is called by Prodigal unless GTDB-Tk works them out. Start a run on
			<a class="mg-link" href="/crisp">Analyze</a>.
		</p>
		<span class="cr-meta">{ws.genomes.length ? `${ws.genomes.length} genome${ws.genomes.length === 1 ? '' : 's'}` : ''}</span>
	</div>

	{#if ws.genomes.length}
		<div class="cr-stats" aria-label="Genomes at a glance">
			<div class="cr-stat"><b>{ws.genomes.length}</b><span>genomes, {formatBytes(bytes)}</span></div>
			<div class="cr-stat"><b>{count('done')}</b><span>annotated</span></div>
			<div class="cr-stat"><b>{count('pending') + count('partial')}</b><span>to annotate{count('partial') ? `, ${count('partial')} incomplete` : ''}</span></div>
			<div class="cr-stat" style={unset ? '--stat: var(--mg-warn)' : undefined}><b>{unset}</b><span>missing domain or code</span></div>
		</div>
	{/if}

	<GenomesBoard />
</div>
