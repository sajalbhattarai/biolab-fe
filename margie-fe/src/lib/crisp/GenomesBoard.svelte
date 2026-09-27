<script lang="ts">
	import { Lock } from 'lucide-svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { ws } from '$lib/workspace/data.svelte';
	import GenomesPanel from '$lib/workspace/panels/GenomesPanel.svelte';

	/**
	 * Crisp's Genomes page: a FASTA drop zone and tallies by domain and gene caller
	 * on the left; the genome table (GenomesPanel) on the right, whose own
	 * "Add FASTA files" the zone replaces.
	 */

	let fileInput = $state<HTMLInputElement>();
	let dragging = $state(0);
	let adding = $state(false);

	/** On the cluster, files go into its genomes folder, so there must be one. */
	const canAdd = $derived(!backend.cluster || !!ws.genomeFolder);

	const bacteria = $derived(ws.genomes.filter((g) => g.domain === 'Bacteria').length);
	const archaea = $derived(ws.genomes.filter((g) => g.domain === 'Archaea').length);
	const unknown = $derived(ws.genomes.filter((g) => !g.domain || !g.genetic_code).length);

	/** The gene caller each genome gets, as GenomesPanel's table says it. */
	const prodigalAll = $derived(!backend.cluster && (ws.setting('GENE_CALLER') || 'prodigal') === 'prodigal');
	const callers = $derived.by(() => {
		const full = ws.genomes.filter((g) => g.domain && g.genetic_code).length;
		const rest = ws.genomes.length - full;
		if (prodigalAll) return [{ label: 'Prodigal', n: ws.genomes.length, cls: 'unk' }];
		return [
			{ label: 'RASTtk', n: full, cls: 'bac' },
			{ label: ws.runGtdbtk ? 'GTDB-Tk, then RASTtk' : 'Prodigal', n: rest, cls: ws.runGtdbtk ? 'arc' : 'unk' }
		];
	});
	const chosen = $derived(ws.selectedGenomes.length);
	const share = (n: number) => (ws.genomes.length ? (n / ws.genomes.length) * 100 : 0);

	async function add(files: FileList | File[]) {
		if (!files.length || adding) return;
		adding = true;
		await ws.upload(files);
		adding = false;
	}

	function drop(e: DragEvent) {
		// Handled here, so the page-wide drop (GenomeDrop) ignores it.
		e.preventDefault();
		dragging = 0;
		if (canAdd && e.dataTransfer?.files.length) add([...e.dataTransfer.files]);
	}
</script>

<section class="gb-board" aria-label="Genomes">
	<!-- ------------------------------------------------ adding -->
	<div class="gb-side">
		<h2 class="gb-colhead">Add</h2>
		<button
			type="button"
			class="gb-drop"
			class:over={dragging > 0 && canAdd}
			class:locked={!canAdd}
			disabled={!canAdd}
			aria-label={canAdd ? (backend.cluster ? 'Add FASTA files to the cluster' : 'Add FASTA files') : 'Adding files needs the genomes folder on the cluster'}
			onclick={() => fileInput?.click()}
			ondragenter={(e) => {
				e.preventDefault();
				dragging++;
			}}
			ondragleave={() => (dragging = Math.max(0, dragging - 1))}
			ondragover={(e) => e.preventDefault()}
			ondrop={drop}
		>
			<span class="gb-art" aria-hidden="true">
				{#if canAdd}
					<span class="gb-doc gb-fall"><i>.fna</i></span>
				{/if}
				<span class="gb-doc gb-rest"><i>.fa</i></span>
				<span class="gb-tray"></span>
			</span>
			<span class="gb-words">
				{#if !canAdd}
					<b class="gb-drop-title"><Lock size={14} /> Folder first</b>
					<span class="gb-drop-note">Type the folder on the cluster that holds your FASTA files (step 1 on Analyze).</span>
				{:else if adding}
					<b class="gb-drop-title">Adding…</b>
					<span class="gb-drop-note">{backend.cluster ? 'Copying to the cluster' : 'Copying to your input folder'}</span>
				{:else if dragging}
					<b class="gb-drop-title">Drop to add</b>
					<span class="gb-drop-note">.fna, .fa or .fasta</span>
				{:else}
					<b class="gb-drop-title">Drop FASTA here</b>
					<span class="gb-drop-note">or click to choose{backend.cluster ? '; copied to the cluster' : ''}</span>
				{/if}
			</span>
		</button>

		{#if ws.genomes.length}
			{#snippet bar(label: string, n: number, cls: string)}
				<li class={cls}>
					<span class="gb-label"><i class="gb-dot" aria-hidden="true"></i>{label}</span><b>{n}</b>
					<span class="gb-bar" aria-hidden="true"><i style="width: {share(n)}%"></i></span>
				</li>
			{/snippet}
			<h2 class="gb-colhead">Domains</h2>
			<ul class="gb-tally">
				{@render bar('Bacteria', bacteria, 'bac')}
				{@render bar('Archaea', archaea, 'arc')}
				{@render bar(ws.runGtdbtk ? 'GTDB-Tk will tell' : 'Unknown', unknown, 'unk')}
			</ul>
			<h2 class="gb-colhead">Gene callers</h2>
			<ul class="gb-tally">
				{#each callers as c (c.label)}{@render bar(c.label, c.n, c.cls)}{/each}
			</ul>
			<h2 class="gb-colhead">Next run</h2>
			<ul class="gb-tally">
				{@render bar(chosen === ws.genomes.length ? 'All chosen' : 'Chosen', chosen, 'bac')}
			</ul>
			{#if unknown}
				<p class="gb-hint">
					{unknown} genome{unknown === 1 ? ' has' : 's have'} no domain or genetic code.
					{ws.runGtdbtk
						? 'GTDB-Tk works them out before RASTtk.'
						: 'Set them in the table, or switch on Use GTDB-Tk; otherwise Prodigal calls their genes.'}
				</p>
			{/if}
		{/if}
	</div>

	<!-- ------------------------------------------------ the table -->
	<div class="gb-main">
		<h2 class="gb-colhead">Genomes <span class="gb-count">{ws.genomes.length || ''}</span></h2>
		<div class="gb-table" class:empty={!ws.genomes.length}><GenomesPanel bare addRow={false} /></div>
		{#if !ws.genomes.length && canAdd}
			<p class="gb-empty">No genomes yet. Each FASTA file you add gets a row here, with its domain and genetic code.</p>
		{/if}
	</div>

	<input
		bind:this={fileInput}
		type="file"
		multiple
		accept={backend.cluster ? '.fna,.fa,.fasta' : '.fna,.fa,.fasta,.fsa,.fas'}
		hidden
		onchange={(e) => {
			const files = [...(e.currentTarget.files ?? [])];
			e.currentTarget.value = '';
			add(files);
		}}
	/>
</section>

<style>
	.gb-board {
		display: grid;
		grid-template-columns: minmax(250px, 1fr) minmax(0, 3.2fr);
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		color: var(--mg-text);
		background: var(--mg-surface);
		box-shadow: none;
		accent-color: var(--mg-accent);
	}
	.gb-side,
	.gb-main {
		display: flex;
		flex-direction: column;
		gap: 12px;
		min-width: 0;
		padding: calc(var(--mg-pad) * 1.2);
	}
	/* The zone stays in reach beside a long table. */
	.gb-side {
		position: sticky;
		top: 0;
		align-self: start;
	}
	.gb-main {
		border-left: 1px solid var(--mg-border);
	}
	.gb-colhead {
		display: flex;
		align-items: baseline;
		gap: 8px;
		margin: 4px 0 0;
		font-size: var(--mg-fs-sm);
		font-weight: 500;
		color: var(--cr-t2, var(--mg-text));
	}
	.gb-count {
		font-weight: 400;
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-3);
	}

	/* ---- the drop zone ---- */
	.gb-drop {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		width: 100%;
		padding: 16px 14px 18px;
		border: 1.5px dashed var(--mg-border-strong);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface-2));
		color: var(--mg-text);
		font: inherit;
		text-align: center;
		cursor: pointer;
		transition:
			background-color 160ms,
			border-color 160ms,
			transform 160ms;
	}
	.gb-drop:hover:not(:disabled),
	.gb-drop.over {
		border-color: color-mix(in srgb, var(--mg-accent) 60%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-accent) 5%, var(--mg-surface));
	}
	.gb-drop.over {
		transform: scale(1.02);
	}
	.gb-drop:focus-visible {
		outline: 2px solid var(--mg-accent);
		outline-offset: 3px;
	}
	.gb-drop.locked {
		border-color: color-mix(in srgb, var(--mg-warn) 60%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-warn) 6%, transparent);
		cursor: not-allowed;
	}
	.gb-words {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		min-width: 0;
	}
	.gb-drop-title {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		font-weight: 500;
		color: var(--mg-text);
	}
	.locked .gb-drop-title {
		color: var(--mg-warn);
	}
	.gb-drop-note {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.gb-art {
		position: relative;
		width: 96px;
		height: 80px;
		margin-bottom: 4px;
		scale: 0.85;
	}
	/* A sheet with a folded corner. */
	.gb-doc {
		position: absolute;
		width: 38px;
		height: 50px;
		border: 1.5px solid var(--mg-border-strong);
		border-radius: 3px;
		background: linear-gradient(225deg, var(--mg-surface) 0 9px, var(--mg-border-strong) 9px 10.5px, var(--mg-surface-2) 10.5px);
		clip-path: polygon(0 0, calc(100% - 10px) 0, 100% 10px, 100% 100%, 0 100%);
	}
	.gb-doc i {
		position: absolute;
		inset: auto 0 8px;
		font-size: 10px;
		font-style: normal;
		color: var(--mg-text-3);
	}
	.gb-rest {
		left: 18px;
		bottom: 14px;
		transform: rotate(-8deg);
	}
	.gb-fall {
		left: 50px;
		top: -8px;
		border-color: color-mix(in srgb, var(--mg-accent) 55%, var(--mg-border-strong));
	}
	.gb-fall i {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.over .gb-fall {
		animation-duration: 1.1s;
	}
	.gb-tray {
		position: absolute;
		left: 4px;
		right: 4px;
		bottom: 0;
		height: 22px;
		border: 1.5px solid var(--mg-border-strong);
		border-top: none;
		border-radius: 0 0 10px 10px;
	}
	.locked .gb-tray {
		border-color: color-mix(in srgb, var(--mg-warn) 60%, var(--mg-border));
	}

	/* ---- the tallies: a dot, the words and the count, over a thin bar ---- */
	.gb-tally {
		display: flex;
		flex-direction: column;
		gap: 10px;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.gb-tally li {
		--c: var(--mg-accent);
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		align-items: center;
		gap: 5px 10px;
		font-size: var(--mg-fs-sm);
	}
	.gb-tally li.arc {
		--c: var(--mg-tier-0);
	}
	.gb-tally li.unk {
		--c: var(--mg-warn);
	}
	.gb-label {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
		color: var(--mg-text-2);
		white-space: nowrap;
	}
	.gb-dot {
		flex-shrink: 0;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--c);
	}
	.gb-tally b {
		font-variant-numeric: tabular-nums;
		font-weight: 500;
		color: var(--mg-text);
	}
	.gb-bar {
		grid-column: 1 / -1;
		height: 3px;
		border-radius: 2px;
		background: color-mix(in srgb, var(--mg-text) 7%, transparent);
		overflow: hidden;
	}
	.gb-bar i {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: color-mix(in srgb, var(--c) 75%, transparent);
		transition: width var(--mo-3, 420ms) cubic-bezier(0.2, 0.7, 0.2, 1);
	}
	.gb-hint {
		margin: 0;
		padding: 8px 10px;
		border-left: 2px solid var(--mg-warn);
		border-radius: 0 var(--mg-r-sm) var(--mg-r-sm) 0;
		background: color-mix(in srgb, var(--mg-warn) 8%, transparent);
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-2);
	}
	.gb-empty {
		margin: 0;
		padding: 18px 0 6px;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-3);
	}

	/* ---- the table, in a frame of its own ---- */
	.gb-table {
		min-width: 0;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-surface);
		overflow: hidden;
	}

	.gb-table.empty {
		border: none;
		background: none;
	}

	:global([data-motion='off']) .gb-board,
	:global([data-motion='off']) .gb-board * {
		animation: none !important;
		transition: none !important;
	}

	@media (max-width: 860px) {
		.gb-board {
			grid-template-columns: minmax(0, 1fr);
		}
		.gb-side {
			position: static;
		}
		.gb-main {
			border-left: none;
			border-top: 1px solid var(--mg-border);
		}
		/* The zone lies down beside its words, and the tally runs across. */
		.gb-drop {
			flex-direction: row;
			justify-content: center;
			gap: 16px;
			padding: 12px 14px;
		}
		.gb-art {
			width: 84px;
			height: 76px;
			margin: 0;
			transform-origin: center;
		}
		.gb-art .gb-doc {
			scale: 0.75;
		}
		.gb-art .gb-rest {
			left: 6px;
			bottom: 2px;
		}
		.gb-art .gb-fall {
			left: 38px;
			top: -6px;
		}
		.gb-words {
			align-items: flex-start;
			text-align: left;
		}
		.gb-tally {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: 8px 14px;
		}
	}
</style>
