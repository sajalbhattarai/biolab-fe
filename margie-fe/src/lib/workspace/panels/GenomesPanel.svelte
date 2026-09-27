<script lang="ts">
	import { Check, X } from 'lucide-svelte';
	import { formatBytes } from '$lib/api';
	import NestedGenomes from '../NestedGenomes.svelte';
	import Panel from '../Panel.svelte';
	import { backend } from '../backend.svelte';
	import { ws } from '../data.svelte';
	import { ui } from '../ui.svelte';

	/**
	 * Genome table: a toolbar (selection and table tools), then one row per FASTA file with domain
	 * and genetic code as coloured selects and the gene caller it will get.
	 */

	let fileInput = $state<HTMLInputElement>();
	let tableInput = $state<HTMLInputElement>();
	let popover = $state<'paste' | 'fill' | null>(null);
	let pasted = $state('');
	let fillDomain = $state('Bacteria');
	let fillCode = $state('11');
	let dragging = $state(0);

	const toggle = (p: 'paste' | 'fill') => (popover = popover === p ? null : p);

	function applyPaste() {
		const n = ws.applyRows(pasted);
		ui.notify(n ? `Updated ${n} genome${n === 1 ? '' : 's'}` : 'No rows matched a genome file name', n ? 'ok' : 'error');
		if (n) {
			pasted = '';
			popover = null;
		}
	}

	async function importTable(files: FileList | null) {
		const f = files?.[0];
		if (!f) return;
		const n = ws.applyRows(await f.text());
		ui.notify(n ? `Updated ${n} genome${n === 1 ? '' : 's'} from ${f.name}` : `No rows in ${f.name} matched a genome file name`, n ? 'ok' : 'error');
		if (tableInput) tableInput.value = '';
	}

	function drop(e: DragEvent) {
		e.preventDefault();
		dragging = 0;
		if (e.dataTransfer?.files.length) ws.upload(e.dataTransfer.files);
	}

	/** `bare` omits the panel frame; `addRow: false` omits "Add FASTA files" where the page has a drop zone. */
	let { bare = false, actionsShown = true, addRow = true }: { bare?: boolean; actionsShown?: boolean; addRow?: boolean } = $props();

	/**
	 * Returns a genome's gene caller: Prodigal for all when chosen; otherwise RASTtk if domain and
	 * genetic code are known (or GTDB-Tk will find them), else Prodigal (margie_sb.smk's genome_calls).
	 */
	function caller(g: { domain: string; genetic_code: string }) {
		if (!backend.cluster && (ws.setting('GENE_CALLER') || 'prodigal') === 'prodigal') return 'Prodigal';
		if (g.domain && g.genetic_code) return 'RASTtk';
		return ws.runGtdbtk ? 'GTDB-Tk, then RASTtk' : 'Prodigal';
	}

	let pattern = $state('');

	/** "Only these" replaces the selection, "Add" extends it; both report the match count. */
	function applyPattern(add = false) {
		const text = pattern.trim();
		if (!text) return;
		const n = add ? ws.addGenomesByPattern(text) : ws.onlyGenomesByPattern(text);
		ui.notify(
			n ? `${n} genome${n === 1 ? '' : 's'} matched ${text}` : `Nothing matched ${text}`,
			n ? 'ok' : 'error'
		);
	}

	let switchingGtdbtk = $state(false);

	/** Genomes GTDB-Tk would classify: those missing either field. */
	const needGtdbtk = $derived(ws.genomes.filter((g) => !g.domain || !g.genetic_code).length);

	/**
	 * Toggles RUN_GTDBTK for the whole run; it affects only genomes missing domain or genetic code.
	 * saveSettings reloads the genomes, so ws.runGtdbtk and the caller column update themselves.
	 */
	async function toggleGtdbtk() {
		if (switchingGtdbtk) return;
		switchingGtdbtk = true;
		const on = !ws.runGtdbtk;
		const saved = await ws.saveSettings({ RUN_GTDBTK: on ? '1' : '0' });
		switchingGtdbtk = false;
		if (!saved) return;
		ui.notify(
			on
				? 'GTDB-Tk will classify the genomes with no domain or genetic code.'
				: 'GTDB-Tk is off. Genomes with no domain or genetic code use Prodigal.',
			'ok'
		);
	}
</script>

{#snippet actions()}
	<!-- On the cluster, domain and code are saved to the account's config, where the run reads them. -->
	{#if ws.genomes.length}
		{#if ws.savingGenomes}<span class="gp-saving">Saving</span>{/if}
		<button
			type="button"
			class="gp-pill"
			aria-pressed={ws.runGtdbtk}
			disabled={switchingGtdbtk}
			title={needGtdbtk
				? `Classify the ${needGtdbtk} genome${needGtdbtk === 1 ? '' : 's'} with no domain or genetic code. ${backend.cluster ? 'Runs on the highmem partition, about 400 GB of memory.' : 'Needs a high-memory machine.'}`
				: 'Every genome already has a domain and genetic code, so GTDB-Tk has nothing to classify.'}
			onclick={toggleGtdbtk}
		>
			{#if ws.runGtdbtk}<Check size={14} />{/if}Use GTDB-Tk
		</button>
		<button type="button" class="gp-pill" aria-pressed={popover === 'paste'} onclick={() => toggle('paste')}>Paste</button>
		<button type="button" class="gp-pill" aria-pressed={popover === 'fill'} onclick={() => toggle('fill')}>Fill empty</button>
		<button type="button" class="gp-pill" onclick={() => tableInput?.click()}>Import table</button>
	{/if}
{/snippet}

<!-- Shared body: inside the board's Panel, or bare inside the Analyze step. -->
{#snippet picker()}
		<!-- Selects which genomes a run annotates; all are selected by default. -->
		<div class="pick">
			<label class="pick-all">
				<input
					type="checkbox"
					checked={ws.everyGenomeChosen}
					indeterminate={!ws.everyGenomeChosen && ws.selectedGenomes.length > 0}
					onchange={(e) => (e.currentTarget.checked ? ws.chooseAllGenomes() : ws.chooseNoGenomes())}
				/>
				<span>
					{#if ws.everyGenomeChosen}
						All {ws.genomes.length} genomes
					{:else}
						{ws.selectedGenomes.length} of {ws.genomes.length} chosen
					{/if}
				</span>
			</label>

			<form
				class="pick-pattern"
				onsubmit={(e) => {
					e.preventDefault();
					applyPattern();
				}}
			>
				<input
					bind:value={pattern}
					placeholder="a-c, 1-9, GCA*"
					spellcheck="false"
					aria-label="Choose genomes by name"
					title={'Comma-separated. "a" starts with a, "a-c" starts with a to c, "1-9" starts with a digit, "GCA*" matches the whole name.'}
				/>
				<button type="submit" class="gp-seg" disabled={!pattern.trim()}>Only these</button>
				<button type="button" class="gp-seg" disabled={!pattern.trim()} onclick={() => applyPattern(true)}>Add</button>
			</form>

			<button type="button" class="gp-pill" onclick={() => ws.invertGenomes()}>Invert</button>
		</div>
{/snippet}

{#snippet body()}
	<div
		class="drop"
		class:over={dragging > 0}
		role="region"
		aria-label="Genome files"
		ondragenter={(e) => {
			e.preventDefault();
			dragging++;
		}}
		ondragleave={() => (dragging = Math.max(0, dragging - 1))}
		ondragover={(e) => e.preventDefault()}
		ondrop={drop}
	>
		{#if ws.genomes.length}
			<div class="gp-bar">
				{@render picker()}
				{#if bare && actionsShown}<div class="gp-acts">{@render actions()}</div>{/if}
			</div>
		{/if}
		{#if popover === 'paste'}
			<div class="pop">
				<label class="mg-label" for="paste-rows">Paste rows of file name, domain and genetic code</label>
				<textarea id="paste-rows" class="mg-input mono" rows="4" placeholder={'Ecoli_K12.fna\tBacteria\t11'} bind:value={pasted}></textarea>
				<div class="row-end">
					<button type="button" class="mg-link quiet" onclick={() => (popover = null)}>Cancel</button>
					<button type="button" class="mg-btn small primary" disabled={!pasted.trim()} onclick={applyPaste}>Apply</button>
				</div>
			</div>
		{:else if popover === 'fill'}
			<div class="pop">
				<span class="mg-label">Fill every empty cell with</span>
				<div class="row-end">
					<select class="mg-select" aria-label="Domain" bind:value={fillDomain}>
						<option value="Bacteria">Bacteria</option>
						<option value="Archaea">Archaea</option>
					</select>
					<select class="mg-select" aria-label="Genetic code" bind:value={fillCode}>
						{#each ws.geneticCodes as c (c)}<option value={c}>{c}</option>{/each}
					</select>
					<span class="mg-grow"></span>
					<button type="button" class="mg-link quiet" onclick={() => (popover = null)}>Cancel</button>
					<button
						type="button"
						class="mg-btn small primary"
						onclick={() => {
							ws.fillEmpty(fillDomain, fillCode);
							popover = null;
						}}>Fill</button
					>
				</div>
			</div>
		{/if}

		<NestedGenomes />

		{#if ws.genomes.length}
			<div class="gtable" role="table" aria-label="Genomes">
				<div class="tr th" class:remote={backend.cluster} role="row">
					<span role="columnheader"><span class="vh">Chosen</span></span><span role="columnheader">File</span><span role="columnheader" class="size"
						>Size</span
					><span role="columnheader">Domain</span><span role="columnheader">Genetic code</span><span role="columnheader" class="via"
						>Gene caller</span
					>{#if !backend.cluster}<span></span>{/if}
				</div>
				{#each ws.genomes as g (g.name)}
					<div class="tr" class:remote={backend.cluster} class:unchosen={!ws.isGenomeChosen(g.name)} role="row">
						<span role="cell">
							<input
								type="checkbox"
								aria-label="Annotate {g.name}"
								checked={ws.isGenomeChosen(g.name)}
								onchange={(e) => ws.setGenomeChosen(g.name, e.currentTarget.checked)}
							/>
						</span>
						<span role="cell" class="file" title={g.name}>{g.name.replace(/\.[^.]+$/, '')}<span class="ext">{g.name.match(/\.[^.]+$/)?.[0] ?? ''}</span></span>
						<span role="cell" class="size">{formatBytes(g.size)}</span>
						<span role="cell">
							<select
								class="gp-badge"
								class:bac={g.domain === 'Bacteria'}
								class:arc={g.domain === 'Archaea'}
								class:unk={!g.domain}
								aria-label="Domain of {g.name}"
								value={g.domain} onchange={(e) => ws.edit(g.name, 'domain', e.currentTarget.value)}>
								<option value="">Unknown</option>
								<option value="Bacteria">Bacteria</option>
								<option value="Archaea">Archaea</option>
							</select>
						</span>
						<span role="cell">
							<select
								class="gp-badge"
								class:unk={!g.genetic_code}
								aria-label="Genetic code of {g.name}"
								value={g.genetic_code}
								onchange={(e) => ws.edit(g.name, 'genetic_code', e.currentTarget.value)}
							>
								<option value="">Unknown</option>
								{#each ws.geneticCodes as code (code)}<option value={code}>{code}</option>{/each}
							</select>
						</span>
						<span role="cell" class="via" title={caller(g)}>{caller(g)}</span>
						<!-- Cluster files are removed in their folder there, not from here. -->
						{#if !backend.cluster}
							<button type="button" class="gp-x" aria-label="Remove {g.name}" title="Remove" onclick={() => ws.remove(g.name)}>
								<X size={14} />
							</button>
						{/if}
					</div>
				{/each}
			</div>
		{/if}
		{#if backend.cluster}
			<p class="remote-note mg-note" class:first={!ws.genomes.length}>
				{ws.genomeFolder
					? `Kept in ${ws.genomeFolder} on the cluster. Files added here are copied there, and one already there is never replaced; to remove one, delete it there.`
					: 'Type the folder on the cluster that holds your FASTA files (step 1 on Analyze), and they show here.'}
			</p>
		{/if}

		{#if addRow && (!backend.cluster || ws.genomeFolder)}
			<div class="add" class:first={!ws.genomes.length}>
				<button type="button" class="mg-btn small" onclick={() => fileInput?.click()}>{backend.cluster ? 'Add FASTA files to the cluster' : 'Add FASTA files'}</button>
				<span class="mg-note">{dragging ? 'Drop to add' : 'or drop them here'}</span>
			</div>
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
			ws.upload(files);
		}}
	/>
	<input bind:this={tableInput} type="file" accept=".tsv,.csv,.txt" hidden onchange={(e) => importTable(e.currentTarget.files)} />
{/snippet}

{#if bare}
	{@render body()}
{:else}
	<Panel id="genomes" meta={ws.genomes.length ? String(ws.genomes.length) : ''} {actions}>
		{@render body()}
	</Panel>
{/if}

<style>
	.drop {
		display: flex;
		flex-direction: column;
		flex-grow: 1;
		border-radius: var(--mg-r);
		outline: 1.5px dashed transparent;
		outline-offset: -4px;
		transition: background-color var(--mo-1, 140ms) ease;
	}
	.drop.over {
		background: color-mix(in srgb, var(--mg-accent) 6%, transparent);
		outline-color: var(--mg-accent);
	}

	/* ---- toolbar: selection on the left, table tools on the right ---- */
	.gp-bar {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: 10px 16px;
		padding: 12px 14px;
		border-bottom: 1px solid var(--mg-border);
	}
	.gp-acts {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 6px;
	}
	.gp-saving {
		font-size: var(--mg-fs-xs);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.gp-pill {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		height: 28px;
		padding: 0 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-xs);
		font-weight: 400;
		white-space: nowrap;
		cursor: pointer;
		transition:
			border-color var(--mo-1, 140ms) ease,
			background-color var(--mo-1, 140ms) ease,
			color var(--mo-1, 140ms) ease;
	}
	.gp-pill:hover:not(:disabled) {
		border-color: var(--mg-border-strong);
		color: var(--mg-text);
	}
	.gp-pill[aria-pressed='true'] {
		border-color: color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-accent) 7%, var(--mg-surface));
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.gp-pill:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}
	.pick {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 8px 12px;
	}
	.pick-all {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		height: 28px;
		padding: 0 12px 0 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		font-size: var(--mg-fs-sm);
		font-weight: 400;
		font-variant-numeric: tabular-nums;
		cursor: pointer;
	}
	/* Pattern input and its two actions as one joined pill. */
	.pick-pattern {
		display: inline-flex;
		align-items: stretch;
		height: 28px;
		border: 1px solid var(--mg-border-strong);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		overflow: hidden;
	}
	.pick-pattern:focus-within {
		border-color: var(--mg-accent);
	}
	.pick-pattern input {
		width: 19ch;
		min-width: 0;
		padding: 0 12px;
		border: none;
		background: none;
		color: var(--mg-text);
		font: inherit;
		font-size: var(--mg-fs-xs);
		outline: none;
	}
	.gp-seg {
		padding: 0 11px;
		border: none;
		border-left: 1px solid var(--mg-border);
		background: none;
		color: var(--mg-accent-ink, var(--mg-accent));
		font: inherit;
		font-size: var(--mg-fs-xs);
		font-weight: 400;
		white-space: nowrap;
		cursor: pointer;
	}
	.gp-seg:hover:not(:disabled) {
		background: color-mix(in srgb, var(--mg-accent) 10%, transparent);
	}
	.gp-seg:disabled {
		color: var(--mg-text-3);
		cursor: default;
	}

	/* ---- paste / fill ---- */
	.pop {
		display: flex;
		flex-direction: column;
		gap: 8px;
		margin: 12px 14px;
		padding: 12px 14px;
		border: 1px solid color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-accent) 5%, var(--mg-surface));
		animation: gp-pop 220ms cubic-bezier(0.2, 0.7, 0.2, 1) both;
	}
	.row-end {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: flex-end;
		gap: 10px 12px;
	}
	.drop > :global(.nest) {
		margin: 12px 14px 0;
	}

	/* ---- table ---- */
	.gtable {
		display: flex;
		flex-direction: column;
		container-type: inline-size;
	}
	.tr {
		display: grid;
		grid-template-columns: 20px minmax(0, 2.4fr) minmax(0, 0.7fr) minmax(0, 1fr) minmax(0, 1fr) minmax(0, 1.2fr) 28px;
		gap: 14px;
		align-items: center;
		min-height: calc(var(--mg-row, 36px) + 6px);
		padding: 0 14px;
		border-top: 1px solid var(--mg-border);
		font-size: var(--mg-fs-sm);
		transition: background-color var(--mo-1, 140ms) ease;
	}
	/* No remove column on the cluster. */
	.tr.remote {
		grid-template-columns: 20px minmax(0, 2.4fr) minmax(0, 0.7fr) minmax(0, 1fr) minmax(0, 1fr) minmax(0, 1.2fr);
	}
	.tr {
		border-top-color: var(--cr-rule, var(--mg-border));
	}
	.tr:not(.th):hover {
		background: color-mix(in srgb, var(--mg-accent) 4%, transparent);
	}
	.th {
		position: sticky;
		top: 0;
		z-index: 1;
		min-height: 34px;
		border-top: none;
		border-bottom: 1px solid var(--mg-border);
		background: var(--mg-surface);
		color: var(--cr-t3, var(--mg-text-3));
		font-size: var(--mg-fs-xs);
		font-weight: 400;
	}
	.th .size,
	.th .via {
		color: inherit;
	}
	.th + .tr {
		border-top: none;
	}
	.tr input[type='checkbox'] {
		margin: 0;
		accent-color: var(--mg-accent);
	}
	.file {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.file .ext {
		color: var(--mg-text-3);
	}
	.size {
		padding-right: 12px;
		text-align: right;
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-2);
	}
	.via {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		color: var(--mg-text-2);
	}
	/* Deselected rows stay listed and editable. */
	.tr.unchosen .file,
	.tr.unchosen .size,
	.tr.unchosen .via {
		opacity: 0.45;
	}
	/* Domain and genetic code as outlined fields with a domain colour dot; unknown uses the warning colour. */
	.gp-badge {
		--dot: transparent;
		appearance: none;
		-webkit-appearance: none;
		max-width: 100%;
		height: 26px;
		padding: 0 24px 0 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background-color: var(--mg-surface);
		background-image:
			radial-gradient(circle, var(--dot) 3.5px, transparent 4px),
			linear-gradient(45deg, transparent 50%, var(--mg-text-3) 50%),
			linear-gradient(135deg, var(--mg-text-3) 50%, transparent 50%);
		background-position:
			9px 50%,
			calc(100% - 13px) 55%,
			calc(100% - 9px) 55%;
		background-size:
			8px 8px,
			4px 4px,
			4px 4px;
		background-repeat: no-repeat;
		color: var(--mg-text);
		font: inherit;
		font-size: var(--mg-fs-xs);
		cursor: pointer;
		transition: border-color var(--mo-1, 140ms) ease;
	}
	.gp-badge:hover {
		border-color: var(--mg-border-strong);
	}
	.gp-badge:focus-visible {
		outline: 2px solid var(--mg-accent);
		outline-offset: 1px;
	}
	.gp-badge.bac,
	.gp-badge.arc,
	.gp-badge.unk {
		padding-left: 22px;
	}
	.gp-badge.bac {
		--dot: var(--mg-accent);
	}
	.gp-badge.arc {
		--dot: var(--mg-tier-0);
	}
	.gp-badge.unk {
		--dot: var(--mg-warn);
		border-color: color-mix(in srgb, var(--mg-warn) 45%, var(--mg-border));
		color: var(--mg-warn);
	}
	.gp-badge option {
		background: var(--mg-surface);
		color: var(--mg-text);
	}
	.gp-x {
		display: grid;
		place-items: center;
		width: 26px;
		height: 26px;
		border: 1px solid transparent;
		border-radius: 50%;
		background: none;
		color: var(--mg-text-3);
		cursor: pointer;
	}
	.gp-x:hover {
		border-color: color-mix(in srgb, var(--mg-danger) 45%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-danger) 10%, transparent);
		color: var(--mg-danger);
	}
	/* Narrow: file name and the two selects only. */
	@container (max-width: 560px) {
		.tr {
			grid-template-columns: 20px minmax(0, 1.4fr) minmax(0, 1.1fr) minmax(0, 0.8fr) 26px;
			gap: 8px;
			padding: 0 10px;
		}
		.tr.remote {
			grid-template-columns: 20px minmax(0, 1.4fr) minmax(0, 1.1fr) minmax(0, 0.8fr);
		}
		.tr .size,
		.tr .via {
			display: none;
		}
		.gp-badge {
			padding-left: 9px;
			padding-right: 20px;
		}
	}
	/* Visually hidden, kept for screen readers. */
	.vh {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}
	.add {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 12px 14px 14px;
		border-top: 1px solid var(--mg-border);
	}
	.remote-note {
		margin: 0;
		padding: 10px 14px 12px;
		border-top: 1px solid var(--mg-border);
	}
	.remote-note.first,
	.add.first {
		border-top: none;
	}

	@keyframes gp-pop {
		from {
			opacity: 0;
			transform: translateY(-4px);
		}
	}
	:global([data-motion='off']) .drop,
	:global([data-motion='off']) .drop * {
		animation: none !important;
		transition: none !important;
	}
</style>
