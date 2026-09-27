<script lang="ts">
	import { Check, Cpu, KeyRound, Lock, Server } from 'lucide-svelte';
	import Fold from './motion/Fold.svelte';
	import FoldTitle from './motion/FoldTitle.svelte';
	import FoldToggle from './motion/FoldToggle.svelte';
	import Switch from './Switch.svelte';
	import { uiBase } from './base.svelte';
	import { backend } from './backend.svelte';
	import { ws, type Depth } from './data.svelte';
	import { ui } from './ui.svelte';

	/**
	 * Run setup card: gene caller, machine resources and annotation tools as toggle cards.
	 * Minimal shows the short form, Advanced the full one; collapsed until opened.
	 */

	const FOLD = 'analyze:workflow';

	/** `bare` omits the card when a panel already draws one. */
	let { bare = false }: { bare?: boolean } = $props();
	let detail = $state<'minimal' | 'advanced'>('minimal');

	const num = (key: string, fallback: number) => {
		const v = Number(ws.setting(key));
		return Number.isFinite(v) && v > 0 ? v : fallback;
	};
	const cores = $derived(num('LOCAL_MAX_CORES', 4));
	const memory = $derived(num('LOCAL_MAX_MEMORY_GB', 8));
	const atOnce = $derived(num('LOCAL_PARALLEL_TOOLS', 1));
	const perTool = $derived({ cores: Math.max(1, Math.floor(cores / atOnce)), memory: Math.max(1, Math.floor(memory / atOnce)) });
	/** Parallel-tool pills: one up to the core count (max eight), plus the saved value. */
	const atOnceChoices = $derived([...new Set([...Array.from({ length: Math.min(cores, 8) }, (_, i) => i + 1), atOnce])].sort((a, b) => a - b));
	const caller = $derived(ws.setting('GENE_CALLER') || 'prodigal');
	const gtdbtk = $derived(ws.setting('RUN_GTDBTK') === '1');

	/** RASTtk needs a known domain and genetic code. */
	const ready = $derived(ws.genomes.filter((g) => g.domain && g.domain !== 'Unknown' && g.genetic_code).length);

	// GTDB-Tk needs its own image and reference tree, which check.sh skips while it is off.
	const gtdbtkImage = $derived(ws.images.find((r) => r.name === 'gtdbtk'));
	const gtdbtkData = $derived(ws.databases.find((r) => r.name === 'gtdbtk'));
	const gtdbtkNeeds = $derived([
		...(gtdbtkImage && gtdbtkImage.status !== 'ok'
			? [{ what: 'containers' as const, need: 'its image', label: 'Build it', title: 'Build the gtdbtk image' }]
			: []),
		...(gtdbtkData && gtdbtkData.status !== 'ok'
			? [{ what: 'databases' as const, need: 'its reference tree (about 150 GB)', label: 'Download it', title: "Download GTDB-Tk's reference tree" }]
			: [])
	]);

	const save = async (key: string, value: string) => {
		if (value === ws.setting(key)) return;
		if (await ws.saveSettings({ [key]: value })) ui.notify('Saved', 'ok');
	};

	/** SLURM account and partition for cluster jobs. */
	const account = $derived(ws.setting('compute.cluster_default.account'));
	const partition = $derived(ws.setting('compute.cluster_default.partition'));
	const maxJobs = $derived(num('compute.cluster_default.max_jobs', 5));

	const licensed = $derived(new Set(ws.tools.filter((t) => t.licensed).map((t) => t.name)));
	const locked = $derived(ws.tools.filter((t) => t.gated && !t.licensed));
	/** The tools a run uses. */
	const inRun = $derived(ws.chosenTools.filter((t) => licensed.has(t)));
	/** Cluster: RASTtk where domain and code are known (or found by GTDB-Tk), Prodigal otherwise. */
	const clusterCaller = $derived(
		gtdbtk ? 'GTDB-Tk, then RASTtk' : ready === ws.genomes.length ? 'RASTtk' : ready ? 'RASTtk and Prodigal' : 'Prodigal'
	);
	const callerName = $derived(
		backend.cluster ? clusterCaller : caller === 'rasttk' ? 'RASTtk' : caller === 'prodigal' ? 'Prodigal' : 'RASTtk or Prodigal'
	);
	const summary = $derived(
		`${callerName}, then ${inRun.length ? `${inRun.length} tool${inRun.length === 1 ? '' : 's'}` : 'nothing more'} | ${
			backend.cluster ? `${maxJobs} jobs` : atOnce
		} at once`
	);

	/** Gene-caller choices: per genome when offered, then either one. */
	const callers = $derived([
		...(detail === 'advanced' || caller === 'auto' ? [{ value: 'auto', label: 'Per genome' }] : []),
		{ value: 'rasttk', label: 'RASTtk' },
		{ value: 'prodigal', label: 'Prodigal' }
	]);
	const DEPTHS: { value: Depth; label: string }[] = [
		{ value: 'quick', label: 'Quick' },
		{ value: 'standard', label: 'Standard' },
		{ value: 'licensed', label: 'Everything' },
		{ value: 'custom', label: 'Custom' }
	];

	// ---- tools, grouped ----
	const GROUPS = [
		{ label: 'Function and pathways', tools: ['kegg', 'cog', 'eggnog', 'uniprot', 'geneprop', 'operon'] },
		{ label: 'Families and domains', tools: ['pfam', 'tigrfam', 'pgap', 'interpro', 'dbcan', 'merops'] },
		{ label: 'Membrane and location', tools: ['tcdb', 'deepsig', 'signalp4', 'psortb', 'phobius', 'tmbed'] }
	];
	const BLURB: Record<string, string> = {
		kegg: 'KEGG pathways',
		cog: 'COG categories',
		eggnog: 'Orthologous groups',
		uniprot: 'Swiss-Prot matches',
		geneprop: 'Genome Properties',
		operon: 'Operons by gene order',
		pfam: 'Protein families',
		tigrfam: 'TIGRFAM families',
		pgap: 'NCBI PGAP models',
		interpro: 'Member databases',
		dbcan: 'CAZymes',
		merops: 'Peptidases',
		tcdb: 'Transporters',
		deepsig: 'Signal peptides',
		signalp4: 'Signal peptides, v4',
		psortb: 'Cell location',
		phobius: 'Membrane topology',
		tmbed: 'Membrane helices'
	};
	const groups = $derived.by(() => {
		const known = new Set(GROUPS.flatMap((g) => g.tools));
		const byName = new Map(ws.tools.map((t) => [t.name, t]));
		const out = GROUPS.map((g) => ({ label: g.label, tools: g.tools.flatMap((n) => byName.get(n) ?? []) }));
		const other = ws.tools.filter((t) => !known.has(t.name));
		if (other.length) out.push({ label: 'Other', tools: other });
		return out.filter((g) => g.tools.length);
	});
	/** A manual tool toggle switches the run to Custom. */
	function toggleTool(name: string) {
		const now = ws.chosenTools;
		ws.custom = now.includes(name) ? now.filter((x) => x !== name) : [...now, name];
		ws.depth = 'custom';
	}
</script>

<!-- Row of pills with one chosen. -->
{#snippet pills(label: string, value: string, options: { value: string; label: string }[], onpick: (v: string) => void)}
	<div class="wf-seg" role="radiogroup" aria-label={label} style="--k: {options.length}">
		{#each options as o (o.value)}
			<button type="button" role="radio" aria-checked={value === o.value} onclick={() => onpick(o.value)}>{o.label}</button>
		{/each}
	</div>
{/snippet}

<!-- Shared body: a card of its own on a Crisp page, framed by the panel on the workspace board. -->
{#snippet body()}
	<div class="wf">
		<div class="wf-bar">
			<ol class="wf-flow" aria-label="What a run does, in order">
				<li><span class="wf-n">1</span>Gene caller <b>{callerName}</b></li>
				<li><span class="wf-n">2</span>Annotation tools <b>{inRun.length || 'none'}</b></li>
				<li><span class="wf-n"><Cpu size={12} /></span>At once <b>{backend.cluster ? maxJobs : atOnce}</b></li>
			</ol>
			{@render pills('How much setup', detail, [
				{ value: 'minimal', label: 'Minimal' },
				{ value: 'advanced', label: 'Advanced' }
			], (v) => (detail = v as 'minimal' | 'advanced'))}
		</div>

		<div class="wf-pair">
			<!-- ---- gene caller ---- -->
			<article class="wf-card">
				<header class="wf-head">
					<span class="wf-badge">1</span>
					<div class="wf-title">
						<h3>Gene caller</h3>
						<span>runs first, on every genome</span>
					</div>
				</header>
				{#if backend.cluster}
					<p class="wf-value">{clusterCaller}</p>
					<p class="mg-note">
						RASTtk calls the genes, through BV-BRC, of every genome whose domain and genetic code are known: it needs both. Any other genome
						is called by Prodigal on the cluster, from the assembly alone.
						{#if !gtdbtk && ready < ws.genomes.length}
							<strong>{ready} of {ws.genomes.length}</strong> of your genomes have both; fill the rest in on
							<a class="mg-link" href={uiBase.to('/genomes')}>Genomes</a>, or let GTDB-Tk work them out.
						{/if}
					</p>
				{:else}
					{@render pills('Gene caller', caller, callers, (v) => save('GENE_CALLER', v))}
					{#if caller === 'prodigal'}
						<p class="mg-note">
							Prodigal calls genes from the assembly alone, on any machine. It is the default, and the right choice on a laptop.
						</p>
					{:else if caller === 'rasttk'}
						<p class="mg-note">
							RASTtk calls genes with Prodigal and Glimmer, adds its own steps, and also reports RNAs and repeats. It needs each genome's
							domain and genetic code, so genomes without them fall back to Prodigal.
							{#if ready < ws.genomes.length}
								<strong>{ready} of {ws.genomes.length}</strong> of your genomes have both; fill the rest in on the genome table, or let GTDB-Tk
								work them out.
							{/if}
						</p>
					{:else}
						<p class="mg-note">Decided per genome: RASTtk for genomes whose domain and genetic code are known, Prodigal for the rest.</p>
					{/if}
				{/if}
				<!-- Shown locally with Prodigal too, so it is never enabled out of sight. -->
				{#if backend.cluster || caller !== 'prodigal' || gtdbtk}
					<div class="wf-switch">
						<div>
							<span class="wf-sw-label">Work out the domain with GTDB-Tk</span>
							<p class="mg-note">
								{#if backend.cluster}
									GTDB-Tk places each genome in the bacterial and archaeal taxonomy, which gives RASTtk the domain and genetic code of every
									genome. It runs on the highmem partition, about 400 GB of memory, and adds hours to a run. Off, the Genomes table supplies
									both.
								{:else}
									GTDB-Tk places each genome in the standard bacterial and archaeal taxonomy, which gives the domain and genetic code RASTtk
									needs. It loads a large reference tree: about 400 GB of memory on this machine, so it belongs on a cluster or a very large
									workstation. Off, the genome table supplies both, and neither its image nor its reference tree counts as part of your setup.
								{/if}
							</p>
						</div>
						<Switch label="Classify with GTDB-Tk" checked={gtdbtk} onchange={(on) => save('RUN_GTDBTK', on ? '1' : '0')} />
					</div>
					{#if gtdbtk && backend.cluster && gtdbtkNeeds.length}
						<p class="mg-note warn">
							Switched on, it still needs {gtdbtkNeeds.map((n) => n.need).join(' and ')} on the cluster.
							<a class="mg-link" href={uiBase.to('/setup#installed')}>Install</a>
						</p>
					{:else if gtdbtk && !backend.cluster && ws.check}
						{#if gtdbtkNeeds.length}
							<p class="mg-note warn">
								<span>Switched on, it still needs {gtdbtkNeeds.map((n) => n.need).join(' and ')} before a run can use it.</span>
								{#each gtdbtkNeeds as n (n.what)}
									<button type="button" class="mg-link" title={n.title} disabled={!ws.canStart} onclick={() => ws.build(n.what, ['gtdbtk'])}>
										{n.label}
									</button>
								{/each}
							</p>
						{:else}
							<p class="mg-note">Its image and reference tree are both ready.</p>
						{/if}
					{/if}
				{/if}
			</article>

			<!-- ---- machine ---- -->
			<article class="wf-card">
				<header class="wf-head">
					<span class="wf-badge icon">{#if backend.cluster}<Server size={15} />{:else}<Cpu size={15} />{/if}</span>
					<div class="wf-title">
						<h3>{backend.cluster ? 'The cluster' : 'This computer'}</h3>
						<span>{backend.cluster ? 'where the jobs go' : 'what a run may use'}</span>
					</div>
				</header>
				{#if backend.cluster}
					<dl class="wf-tiles three">
						<div><dt>SLURM account</dt><dd class:unset={!account}>{account || 'not set'}</dd></div>
						<div><dt>Partition</dt><dd>{partition || 'default'}</dd></div>
						<div><dt>Jobs at once</dt><dd>{maxJobs}</dd></div>
					</dl>
					{#if detail === 'advanced'}
						<div class="wf-inputs three">
							<label>
								<span>SLURM account</span>
								<input class="mg-input" value={account} spellcheck="false" onchange={(e) => save('compute.cluster_default.account', e.currentTarget.value)} />
							</label>
							<label>
								<span>Partition</span>
								<input class="mg-input" value={partition} spellcheck="false" onchange={(e) => save('compute.cluster_default.partition', e.currentTarget.value)} />
							</label>
							<label>
								<span>Jobs at once</span>
								<input class="mg-input" type="number" min="1" value={maxJobs} onchange={(e) => save('compute.cluster_default.max_jobs', e.currentTarget.value)} />
							</label>
						</div>
						<p class="mg-note">
							Each tool is a SLURM job of its own, charged to the account. Per-tool threads, memory and time are in
							<a class="mg-link" href={uiBase.to('/settings#per-tool')}>Settings</a>.
						</p>
					{:else}
						<p class="mg-note">
							{account ? `Jobs are charged to ${account} and queued on ${partition || 'the default partition'}.` : 'Every job is charged to a SLURM account; none is set yet.'}
							<a class="mg-link" href={uiBase.to('/settings#compute.cluster_default.account')}>Change</a>
						</p>
					{/if}
				{:else}
					<div class="wf-sub">
						<span class="wf-sw-label">Tools at once</span>
						{@render pills(
							'Tools at once',
							String(atOnce),
							atOnceChoices.map((v) => ({ value: String(v), label: String(v) })),
							(v) => save('LOCAL_PARALLEL_TOOLS', v)
						)}
					</div>
					<dl class="wf-tiles">
						<div><dt>Cores each</dt><dd>{perTool.cores} <small>of {cores}</small></dd></div>
						<div><dt>Memory each</dt><dd>{perTool.memory} GB <small>of {memory}</small></dd></div>
					</dl>
					{#if detail === 'advanced'}
						<div class="wf-inputs three">
							<label>
								<span>Cores in all</span>
								<input class="mg-input" type="number" min="1" value={cores} onchange={(e) => save('LOCAL_MAX_CORES', e.currentTarget.value)} />
							</label>
							<label>
								<span>Memory in all (GB)</span>
								<input class="mg-input" type="number" min="1" value={memory} onchange={(e) => save('LOCAL_MAX_MEMORY_GB', e.currentTarget.value)} />
							</label>
							<label>
								<span>Tools at once</span>
								<input class="mg-input" type="number" min="1" max={cores} value={atOnce} onchange={(e) => save('LOCAL_PARALLEL_TOOLS', e.currentTarget.value)} />
							</label>
						</div>
					{/if}
					<p class="mg-note">
						The two budgets are shared out between the tools running at once, so four at a time each get a quarter. The rest of the machine
						stays yours.
						{#if detail !== 'advanced'}<a class="mg-link" href={uiBase.to('/settings#LOCAL_MAX_CORES')}>Change the budgets</a>{/if}
					</p>
				{/if}
			</article>
		</div>

		<!-- ---- tools ---- -->
		<article class="wf-card wide">
			<header class="wf-head">
				<span class="wf-badge">2</span>
				<div class="wf-title">
					<h3>Annotation tools <span class="wf-count">{inRun.length} of {ws.tools.length}</span></h3>
					<span>run after the gene caller</span>
				</div>
				<span class="mg-grow"></span>
				{@render pills('How much to run', ws.depth, DEPTHS, (v) => (ws.depth = v as Depth))}
			</header>

			<div class="wf-groups" style="--g: {groups.length}">
				{#each groups as g (g.label)}
					<section class="wf-group" aria-label={g.label}>
						<h4>{g.label}</h4>
						<ul>
							{#each g.tools as t, i (t.name)}
								{@const on = inRun.includes(t.name)}
								<li style="--i: {i}">
									<button
										type="button"
										class="wf-tool"
										class:on
										class:locked={!t.licensed}
										aria-pressed={on}
										disabled={!t.licensed}
										title={t.licensed ? (t.gated ? 'Licence accepted' : '') : 'Its licence has not been accepted'}
										onclick={() => toggleTool(t.name)}
									>
										<span class="wf-box" aria-hidden="true">{#if on}<Check size={12} strokeWidth={3.2} />{/if}</span>
										<span class="wf-tname">
											<span class="mg-mono">{t.name}</span>
											{#if BLURB[t.name]}<small>{BLURB[t.name]}</small>{/if}
										</span>
										{#if !t.licensed}
											<span class="wf-lic need"><Lock size={11} /> licence</span>
										{:else if t.gated}
											<span class="wf-lic" aria-label="Licence accepted"><KeyRound size={11} /></span>
										{/if}
									</button>
								</li>
							{/each}
						</ul>
					</section>
				{/each}
			</div>

			<footer class="wf-foot">
				{#if inRun.length}
					<p class="mg-note">
						{#if backend.cluster}
							Gene calling (RASTtk or Prodigal) and the operon layer always run, and so do the steps that follow every genome —
							consolidation, labeling, fingerprinting and scoring. The envelope stage joins when a tool after it reads what it infers.
						{:else}
							Gene calling, envelope inference and the operon layer always run, and so do the steps that follow every genome — consolidation,
							labeling, fingerprinting and scoring. Those are this project's own scripts, so nothing has to be accepted for them.
						{/if}
					</p>
				{:else}
					<p class="mg-note">
						No tools are chosen, so a run calls genes and stops there. Nothing downstream has anything to read without annotation results:
						no envelope, no operon layer, no consolidation, labeling, fingerprinting or scoring.
					</p>
				{/if}
				<p class="wf-legend mg-note">
					<span class="wf-lic"><KeyRound size={11} /></span> licence accepted
					{#if locked.length}<span class="wf-lic need"><Lock size={11} /> licence</span> needs its terms accepted{/if}
				</p>
				{#if locked.length}
					<p class="mg-note locked">
						Behind a licence: {#each locked as t, i (t.name)}<span class="mg-mono">{t.name}</span>{i < locked.length - 1 ? ', ' : ''}{/each}.
						{#if backend.cluster}
							Record the licences you hold with the terms, in
							<a class="mg-link" href={uiBase.to('/setup#terms')}>Install → Licence terms</a>, to use them.
						{:else}
							InterPro runs only its freely distributable member databases. Accept the terms in
							<a class="mg-link" href={uiBase.to('/settings#licences')}>Settings → Licences</a> to use them.
						{/if}
					</p>
				{/if}
			</footer>
		</article>
	</div>
{/snippet}

{#if bare}
	<Fold id={FOLD} closed>{@render body()}</Fold>
{:else}
	<section class="mg-card" id="workflow-setup" data-shade="workflow">
		<header class="mg-card-head">
			<FoldTitle id={FOLD} closed>Workflow setup</FoldTitle>
			<span class="mg-note">{summary}</span>
			<span class="mg-grow"></span>
			<FoldToggle id={FOLD} closed open="Change" shut="Done" />
		</header>

		<Fold id={FOLD} closed>{@render body()}</Fold>
	</section>
{/if}

<style>
	/* Cards of one shape: two side by side, tools in a full-width grid beneath. */
	.wf {
		display: flex;
		flex-direction: column;
		gap: var(--mg-gap);
		padding: calc(var(--mg-pad) * 1.2);
		color: var(--mg-text);
	}
	.wf-bar {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: 10px 16px;
	}
	.wf-flow {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px;
	}
	.wf-flow li {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		height: 32px;
		padding: 0 14px 0 5px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-text-2);
		font-size: var(--mg-fs-sm);
	}
	.wf-flow b {
		color: var(--mg-text);
		font-weight: 650;
	}
	.wf-n {
		display: grid;
		place-items: center;
		width: 22px;
		height: 22px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--mg-accent) 14%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
		font-size: 11px;
		font-weight: 700;
	}

	/* ---- pills ---- */
	.wf-seg {
		display: inline-grid;
		grid-template-columns: repeat(var(--k), minmax(0, auto));
		gap: 2px;
		max-width: 100%;
		padding: 3px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
	}
	.wf-seg button {
		min-width: 36px;
		height: 30px;
		padding: 0 14px;
		border: 0;
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-sm);
		font-weight: 600;
		white-space: nowrap;
		cursor: pointer;
		transition:
			background-color 160ms ease,
			color 160ms ease,
			box-shadow 160ms ease;
	}
	.wf-seg button:hover {
		color: var(--mg-text);
	}
	.wf-seg button[aria-checked='true'] {
		background: var(--mg-accent);
		color: var(--mg-on-accent, #fff);
		box-shadow: none;
	}

	/* ---- cards ---- */
	.wf-pair {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--mg-gap);
		align-items: stretch;
	}
	.wf-card {
		display: flex;
		flex-direction: column;
		gap: 12px;
		min-width: 0;
		padding: calc(var(--mg-pad) * 1.1);
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-surface);
	}
	.wf-card :global(p.mg-note) {
		margin: 0;
		max-width: 75ch;
	}
	.wf-head {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 10px 12px;
	}
	.wf-badge {
		flex: none;
		display: grid;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: 50%;
		background: var(--mg-accent);
		color: var(--mg-on-accent, #fff);
		font-size: var(--mg-fs-sm);
		font-weight: 700;
	}
	.wf-badge.icon {
		background: color-mix(in srgb, var(--mg-accent) 14%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.wf-title {
		display: flex;
		flex-direction: column;
		line-height: 1.25;
	}
	.wf-title h3 {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: var(--mg-fs-lg);
		font-weight: 650;
	}
	.wf-title > span {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.wf-count {
		padding: 1px 9px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
		color: var(--mg-text-2);
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.wf-value {
		font-size: var(--mg-fs-lg);
		font-weight: 650;
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.wf-switch {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		align-items: start;
		gap: 14px;
		margin-top: auto;
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm, 8px);
		background: var(--mg-surface-2);
	}
	.wf-switch .mg-note {
		margin-top: 4px;
		font-size: var(--mg-fs-xs);
	}
	.wf-sw-label {
		font-weight: 600;
		font-size: var(--mg-fs-sm);
	}
	.wf-sub {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: 8px 14px;
	}
	.wf-tiles {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 10px;
		margin: 0;
	}
	.wf-tiles.three {
		grid-template-columns: repeat(3, minmax(0, 1fr));
	}
	.wf-tiles > div {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		padding: 10px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm, 8px);
		background: var(--mg-surface-2);
	}
	.wf-tiles dt {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.wf-tiles dd {
		margin: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-lg);
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.wf-tiles dd.unset {
		color: var(--mg-warn);
	}
	.wf-tiles small {
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		color: var(--mg-text-3);
	}
	.wf-inputs {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 10px;
	}
	.wf-inputs label {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.wf-inputs input {
		width: 100%;
		border-radius: var(--mg-r-sm);
		padding-inline: 12px;
	}
	.warn {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 4px 12px;
		color: var(--mg-warn);
	}

	/* ---- tools ---- */
	.wf-groups {
		display: grid;
		grid-template-columns: repeat(var(--g), minmax(0, 1fr));
		gap: var(--mg-gap);
	}
	.wf-group {
		display: flex;
		flex-direction: column;
		gap: 8px;
		min-width: 0;
	}
	.wf-group h4 {
		padding-bottom: 6px;
		border-bottom: 1px solid var(--mg-border);
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.wf-group ul {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(190px, 1fr));
		gap: 6px;
	}
	.wf-tool {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr) auto;
		align-items: center;
		gap: 10px;
		width: 100%;
		min-height: 48px;
		padding: 7px 12px 7px 10px;
		border: 1px solid var(--mg-border);
		border-radius: 12px;
		background: var(--mg-surface);
		color: var(--mg-text-2);
		font: inherit;
		text-align: left;
		cursor: pointer;
		transition:
			border-color 140ms ease,
			background-color 140ms ease,
			transform 140ms ease;
	}
	.wf-tool:hover:not(:disabled) {
		border-color: var(--mg-border-strong);
	}
	.wf-tool.on {
		border-color: color-mix(in srgb, var(--mg-accent) 55%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-accent) 9%, var(--mg-surface));
		color: var(--mg-text);
	}
	.wf-tool.locked {
		border-style: dashed;
		opacity: 0.65;
		cursor: not-allowed;
	}
	.wf-box {
		display: grid;
		place-items: center;
		width: 18px;
		height: 18px;
		border: 2px solid var(--mg-border-strong);
		border-radius: 6px;
		color: var(--mg-on-accent, #fff);
		transition:
			background-color 140ms ease,
			border-color 140ms ease;
	}
	.on .wf-box {
		border-color: var(--mg-accent);
		background: var(--mg-accent);
	}
	.wf-tname {
		display: flex;
		flex-direction: column;
		min-width: 0;
		line-height: 1.25;
	}
	.wf-tname .mg-mono {
		font-size: var(--mg-fs-sm);
		font-weight: 600;
	}
	.wf-tname small {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.wf-lic {
		display: inline-flex;
		align-items: center;
		gap: 3px;
		padding: 2px 6px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-accent) 12%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
		font-size: 10px;
		font-weight: 700;
		vertical-align: middle;
	}
	.wf-lic.need {
		background: color-mix(in srgb, var(--mg-warn) 16%, transparent);
		color: var(--mg-warn);
	}
	.wf-foot {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding-top: 12px;
		border-top: 1px dashed var(--mg-border);
	}
	.wf-legend {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 6px;
		font-size: var(--mg-fs-xs);
	}
	.wf-legend .wf-lic.need {
		margin-left: 10px;
	}

	:global([data-motion='off']) .wf * {
		animation: none !important;
		transition: none !important;
	}

	@media (max-width: 1100px) {
		.wf-groups {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	@media (max-width: 860px) {
		.wf-pair {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	@media (max-width: 520px) {
		.wf {
			padding: var(--mg-pad);
		}
		.wf-inputs,
		.wf-tiles.three {
			grid-template-columns: minmax(0, 1fr);
		}
		.wf-head .wf-seg {
			width: 100%;
			grid-template-columns: repeat(var(--k), minmax(0, 1fr));
		}
		.wf-seg button {
			padding: 0 8px;
		}
	}
</style>
