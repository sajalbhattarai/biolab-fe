<script lang="ts">
	import { tick, untrack } from 'svelte';
	import { Check, Dna, FolderInput, FolderOutput, ListOrdered, RotateCcw, Square, X } from 'lucide-svelte';
	import type { Run } from '$lib/api';
	import { genomeList, stemOf } from '$lib/crisp/genomes';
	import { COMPARE_TOOLS, RESULT_STAGES, logSteps } from '$lib/crisp/steps';
	import { uiBase } from '$lib/workspace/base.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { ws } from '$lib/workspace/data.svelte';
	import { ui } from '$lib/workspace/ui.svelte';
	import BuildBar from '$lib/workspace/blocks/BuildBar.svelte';
	import Fold from '$lib/workspace/motion/Fold.svelte';
	import FoldTitle from '$lib/workspace/motion/FoldTitle.svelte';
	import FoldToggle from '$lib/workspace/motion/FoldToggle.svelte';
	import GenomesPanel from '$lib/workspace/panels/GenomesPanel.svelte';
	import RunAction from '$lib/workspace/blocks/RunAction.svelte';
	import WorkflowSetup from '$lib/workspace/WorkflowSetup.svelte';

	/**
	 * Crisp's Analyze page in two cards: Run (inputs, outputs, tools and the start
	 * button, or a run-wide bar with Stop; Resume or Restart after a failed run), and
	 * a foldable progress grid of genomes by tool, grouped by phase, each cell a pie
	 * of that tool's progress. The grid scrolls and resizes for hundreds of genomes.
	 */
	let { tools }: { tools: string[] } = $props();

	const WORKFLOW = 'analyze:workflow';
	const GRID = 'analyze:grid';
	let showGenomes = $state(false);

	/* The genome table and the workflow open under the cards, so the page
	   brings whichever was just opened into view. */
	let genomesBox = $state<HTMLElement | null>(null);
	let workflowBox = $state<HTMLElement | null>(null);
	async function reveal(box: () => HTMLElement | null) {
		await tick();
		setTimeout(() => box()?.scrollIntoView({ behavior: ui.motion === 'off' ? 'auto' : 'smooth', block: 'nearest' }), ui.ms(220));
	}
	function toggleGenomes() {
		showGenomes = !showGenomes;
		if (showGenomes) reveal(() => genomesBox);
	}
	function toggleWorkflow() {
		ui.toggleFold(WORKFLOW, true);
		if (!ui.isFolded(WORKFLOW, true)) reveal(() => workflowBox);
	}

	const genomes = $derived(genomeList());
	const inFolder = $derived(genomes.filter((g) => g.file));
	const n = $derived(ws.genomes.length);

	const setting = (key: string) => ws.settings.find((s) => s.key === key)?.value ?? '';
	const inputDir = $derived(ws.genomeFolder || setting('USER_INPUT_DIR'));
	const outputDir = $derived(ws.resultRoots.outputRoot || setting('OUTPUT_ROOT'));
	const short = (p: string) => (p ? p.split('/').filter(Boolean).slice(-2).join('/') : 'not set');

	let typed = $state('');
	let saving = $state(false);
	$effect(() => {
		const current = inputDir;
		untrack(() => {
			if (!saving) typed = current;
		});
	});
	async function savePath() {
		const value = typed.trim();
		if (!value || value === inputDir) return;
		saving = true;
		const ok = await ws.saveSettings({ USER_INPUT_DIR: value });
		saving = false;
		ui.notify(ok ? 'Input path saved' : 'That path could not be used', ok ? 'ok' : 'error');
	}

	const caller = $derived(setting('GENE_CALLER') || 'prodigal');
	/* Which gene caller a genome gets is decided per genome (RASTtk with a
	   domain and genetic code, else Prodigal) unless one is fixed in Settings. */
	const callerName = $derived(backend.cluster || caller === 'auto' ? 'RASTtk or Prodigal' : caller === 'rasttk' ? 'RASTtk' : 'Prodigal');
	const toolCount = $derived(ws.chosenTools.length);

	// ---------------------------------------------------------------- the run
	/** The annotation going now, if any. */
	const run = $derived(ws.active?.kind === 'annotate' ? ws.active : null);
	const p = $derived(run ? ws.progress : null);
	const pct = $derived(p ? p.fraction * 100 : (run?.progress ?? 0));
	const runText = $derived.by(() => {
		if (!p) return run?.progressText ?? '';
		const done = p.genomes.filter((g) => g.state === 'done').length;
		return `${done} of ${p.genomes.length} genomes${p.current ? ` | ${p.current}` : ''}${p.detail ? ` | ${p.detail}` : ''}`;
	});
	/** The last annotation, when it ended badly and nothing has run since. */
	const lastBad = $derived.by((): Run | null => {
		if (ws.running.length) return null;
		const last = ws.runs.filter((r) => r.kind === 'annotate').sort((a, b) => b.started.localeCompare(a.started))[0];
		return last && (last.status === 'failed' || last.status === 'cancelled') ? last : null;
	});
	let acting = $state(false);
	async function stopRun() {
		if (!run || !confirm('Stop this run now? What has finished is kept, and Resume picks up from there.')) return;
		await ws.stop(run.id);
	}
	async function resume(r: Run) {
		acting = true;
		if (await ws.resume(r)) ui.notify('Resumed', 'ok');
		acting = false;
	}
	async function restart(r: Run) {
		if (!confirm('Start this run again from the beginning, with the same genomes and tools?')) return;
		acting = true;
		if (await ws.restart(r)) ui.notify('Restarted', 'ok');
		acting = false;
	}

	// ---------------------------------------------------------------- genomes and progress
	/*
	 * Every step a genome goes through, by phase. Steps this setup does not run are
	 * shown blank, so the whole pipeline stays in view.
	 */
	const FUNCTION = ['kegg', 'cog', 'pfam', 'pgap', 'tigrfam', 'dbcan', 'eggnog', 'merops', 'tcdb', 'uniprot', 'interpro', 'geneprop'];
	const LOCATION = ['tmbed', 'phobius', 'envelope', 'psortb', 'deepsig', 'signalp4', 'signalp6'];
	const GRAM_AFTER = new Set(['psortb', 'deepsig', 'signalp4']);
	const CALLERS = ['rasttk', 'prodigal'];
	const KNOWN = new Set([...FUNCTION, ...LOCATION, ...CALLERS, 'operon', 'gtdbtk', 'quast', 'llm', ...RESULT_STAGES, ...COMPARE_TOOLS]);

	/** The tools this setup offers, and those of the run in view (or the next one). */
	const planned = $derived(new Set(tools));
	const phases = $derived.by(() => {
		const offered = new Set([...ws.tools.map((t) => t.name), ...tools]);
		const pick = (list: readonly string[]) => list.filter((t) => offered.has(t) || t === 'envelope');
		const other = [...offered].filter((t) => !KNOWN.has(t));
		return [
			{ label: 'Prepare', cols: ['quast', 'gtdbtk'] },
			{ label: 'Genes', cols: ['genes'] },
			{ label: 'Function', cols: [...pick(FUNCTION), ...other] },
			{ label: 'Operons', cols: ['operon'] },
			{ label: 'Location', cols: pick(LOCATION) },
			{ label: 'Results', cols: [...RESULT_STAGES] },
			{ label: 'Compare', cols: [...COMPARE_TOOLS] },
			{ label: 'LLM', cols: ['llm'] },
			{ label: 'Report', cols: ['report'] }
		].filter((g) => g.cols.length);
	});
	const cols = $derived(phases.flatMap((g) => g.cols));

	/** The run whose steps are in view: the one going, else the last one that ended badly. */
	const shown = $derived(run ?? lastBad);
	$effect(() => {
		const r = lastBad;
		if (!run && r && ws.logOf !== r.id) untrack(() => ws.readLog(r.id));
	});
	/** Its log and clock, once they are the ones read. */
	const mine = $derived(!!shown && ws.logOf === shown.id);
	const logged = $derived(mine && shown ? logSteps(ws.log, shown.status) : null);

	/** The run's genomes while one goes; otherwise those in the input folder, by name. */
	const rows = $derived(
		run && p ? p.genomes.map((g) => g.name) : inFolder.map((g) => g.name).sort((a, b) => a.localeCompare(b))
	);
	const results = $derived(new Map(ws.results.map((r) => [r.organism, r])));
	const cells = $derived.by(() => {
		const m = new Map<string, 'done' | 'partial'>();
		for (const r of ws.results) for (const t of r.tools) m.set(`${t.tool}\t${r.organism}`, t.processed ? 'done' : 'partial');
		return m;
	});
	const meta = $derived(new Map(ws.genomes.map((g) => [stemOf(g.name), g])));
	/* A clock for the pies of tools under way: the server's time, ticking here between polls. */
	let tickAt = $state(Date.now());
	let skew = 0;
	$effect(() => {
		if (ws.clock) skew = ws.clock.now - Date.now();
	});
	$effect(() => {
		if (!run) return;
		const t = setInterval(() => (tickAt = Date.now()), 2000);
		return () => clearInterval(t);
	});
	/** The tool runs of the run in view, by tool and genome (the latest of each). */
	const started = $derived(mine ? new Map((ws.clock?.started ?? []).map((e) => [`${e.tool}\t${e.genome}`, e])) : new Map());
	/** The tool the run's own log says it is on, for a cluster, which has no clock. */
	const now = $derived(run && p?.current ? { genome: p.current, tool: p.detail } : null);

	type State = 'done' | 'run' | 'wait' | 'failed' | 'partial' | 'none' | 'na';
	type Cell = { state: State; pct: number | null; say: string };
	const mins = (s: number) => (s < 90 ? `${Math.round(s)} s` : `${Math.round(s / 60)} min`);
	const NA = (say: string): Cell => ({ state: 'na', pct: null, say });

	/** A tool run's state from the clock: done, failed, under way (with an estimate when there is one), or cut short. */
	function fromClock(tool: string, genome: string): Cell | null {
		const e = started.get(`${tool}\t${genome}`);
		if (!e) return null;
		if (e.ok) return { state: 'done', pct: 100, say: 'done, 100%' };
		if (e.failed) return { state: 'failed', pct: 0, say: 'failed (see the log)' };
		if (!run) return { state: 'partial', pct: 0, say: 'stopped before it finished' };
		const so = Math.max(0, (tickAt + skew - e.start) / 1000);
		const usual = ws.clock?.typical[tool];
		if (usual) {
			const pct = Math.min(95, (so / usual) * 100);
			return { state: 'run', pct, say: `${Math.round(pct)}% (${mins(so)} of about ${mins(usual)})` };
		}
		return { state: 'wait', pct: null, say: `running, ${mins(so)} so far (no earlier run of ${tool} here to estimate from)` };
	}
	const fromLog = (step: string, genome: string): Cell | null => {
		const s = logged?.state.get(`${step}\t${genome}`);
		if (!s) return null;
		if (s === 'done') return { state: 'done', pct: 100, say: 'done, 100%' };
		if (s === 'failed') return { state: 'failed', pct: 0, say: 'failed (see the log)' };
		if (s === 'partial') return { state: 'partial', pct: 0, say: 'stopped before it finished' };
		if (s === 'na') return NA('switched off in Settings');
		return { state: 'wait', pct: null, say: 'running now' };
	};

	/** A cell: its state, how far it is (0-100; null when that cannot be told), and a line for its tooltip. */
	function cell(col: string, genome: string): Cell {
		const r = results.get(genome);
		const has = (t: string) => cells.get(`${t}\t${genome}`);
		const done = (say = 'done, 100%'): Cell => ({ state: 'done', pct: 100, say });
		const none: Cell = { state: 'none', pct: 0, say: 'not started, 0%' };
		switch (col) {
			case 'quast':
			case 'llm':
				return has(col) === 'done' ? done() : NA(col === 'quast' ? 'not part of the pipeline on this computer' : 'not part of the pipeline yet');
			case 'gtdbtk': {
				if (has('gtdbtk') === 'done') return done();
				const c = fromClock('gtdbtk', genome);
				if (c) return c;
				if (setting('RUN_GTDBTK') !== '1') return NA('switched off in Settings');
				const g = meta.get(genome);
				return g?.domain && g?.genetic_code ? NA('not needed: its domain and genetic code are given') : none;
			}
			case 'genes': {
				for (const t of CALLERS) if (has(t) === 'done') return done(`done, 100% (${t === 'rasttk' ? 'RASTtk' : 'Prodigal'})`);
				for (const t of CALLERS) {
					const c = fromClock(t, genome);
					if (c) return { ...c, say: `${t === 'rasttk' ? 'RASTtk' : 'Prodigal'}: ${c.say}` };
				}
				if (now?.genome === genome && CALLERS.includes(now.tool)) return { state: 'wait', pct: null, say: 'running now' };
				return none;
			}
			case 'report':
				if (r?.final?.table) return done('done, 100%: the table, map and figures are in');
				return fromLog('figures', genome)?.state === 'wait' ? { state: 'wait', pct: null, say: 'being written' } : none;
		}
		if ((RESULT_STAGES as readonly string[]).includes(col) || (COMPARE_TOOLS as readonly string[]).includes(col)) {
			const l = fromLog(col, genome);
			// Not in the log but the report is there: done before (a cache hands it back without running it).
			if (l && !(l.state === 'na' && r?.final?.table)) return l;
			if (has(col) === 'done' || r?.final?.table) return done();
			return none;
		}
		// An annotation tool, the operon finder or the envelope stage.
		if (has(col) === 'done') return done();
		const c = fromClock(col, genome);
		if (c) return c;
		if (now?.genome === genome && now?.tool === col) return { state: 'wait', pct: null, say: 'running now' };
		const used = col === 'envelope' ? [...planned].some((t) => GRAM_AFTER.has(t)) : planned.has(col);
		if (!used) return NA(col === 'envelope' ? 'not needed: no tool reads the cell envelope in this run' : 'not chosen for this run');
		if (has(col) === 'partial') return { state: 'partial', pct: 0, say: 'started before, not finished' };
		return none;
	}
	/** Where a cell's results are: its folder for the Files page, or the run's log for one that failed. */
	function hrefOf(col: string, genome: string, c: Cell): string | undefined {
		if (c.state === 'na' || c.state === 'none') return undefined;
		if (c.state === 'failed') return shown ? uiBase.to(`/runs/${shown.id}`) : undefined;
		const r = results.get(genome);
		const out = ws.resultRoots.outputRoot;
		const toolPath = (t: string) => r?.tools.find((x) => x.tool === t)?.path;
		let dir: string | undefined;
		if (col === 'genes') dir = toolPath('rasttk') ?? toolPath('prodigal');
		else if (col === 'report') dir = r?.final?.dir;
		else if (col === 'figures') dir = r?.final?.diagrams ?? r?.folder;
		else if (['consolidation', 'labeling', 'scoring'].includes(col)) dir = r?.folder ? `${r.folder}/${col}` : undefined;
		else if ((RESULT_STAGES as readonly string[]).includes(col)) dir = r?.folder;
		else if ((COMPARE_TOOLS as readonly string[]).includes(col)) dir = out ? `${out}/${col}` : undefined;
		else dir = toolPath(col) ?? (out ? `${out}/${col}/${genome}` : undefined);
		return dir ? uiBase.to(`/files?path=${encodeURIComponent(dir)}`) : undefined;
	}

	/** Every cell once per change: a genome to a row, with how far each is. */
	const firsts = $derived(new Set(phases.map((g) => g.cols[0])));
	const avg = (cs: Cell[]) => {
		const on = cs.filter((c) => c.state !== 'na');
		return on.length ? on.reduce((a, c) => a + (c.pct ?? 0), 0) / on.length : null;
	};
	const matrix = $derived(
		rows.map((g) => {
			const cs = cols.map((t) => {
				const c = cell(t, g);
				return { t, ...c, href: hrefOf(t, g, c) };
			});
			return { g, cells: cs, pct: Math.round(avg(cs) ?? 0) };
		})
	);
	/** Each tool across every genome: its own progress, and how many are done. */
	const columns = $derived(
		cols.map((t, j) => {
			const cs = matrix.map((row) => row.cells[j]);
			const on = cs.filter((c) => c.state !== 'na');
			const pct = avg(cs);
			return {
				t,
				pct: pct === null ? null : Math.round(pct),
				done: on.filter((c) => c.state === 'done').length,
				failed: on.filter((c) => c.state === 'failed').length,
				of: on.length
			};
		})
	);
	const overall = $derived(Math.round(avg(matrix.flatMap((r) => r.cells)) ?? 0));
	const counts = $derived({
		done: columns.reduce((a, c) => a + c.done, 0),
		all: columns.reduce((a, c) => a + c.of, 0)
	});
</script>

<div class="analyze">
<!-- ------------------------------------------------ the run -->
<section class="card runcard" id="run">
	<div class="where">
		<label class="field">
			<span class="lbl"><FolderInput size={14} /> From</span>
			<input
				class="mg-input"
				value={typed}
				spellcheck="false"
				autocomplete="off"
				aria-label="Folder the genomes are read from"
				placeholder={backend.cluster ? '/path/to/genomes on the cluster' : '/path/to/genomes'}
				oninput={(e) => (typed = e.currentTarget.value)}
				onblur={savePath}
				onkeydown={(e) => e.key === 'Enter' && e.currentTarget.blur()}
			/>
		</label>
		<p class="field to">
			<span class="lbl"><FolderOutput size={14} /> To</span>
			<span class="path" title={outputDir}>{short(outputDir)}</span>
			<a class="mg-link quiet" href={uiBase.to('/settings#OUTPUT_ROOT')}>Change</a>
		</p>
	</div>

	<div class="what">
		<p class="lbl"><ListOrdered size={14} /> Tools</p>
		<p class="sum">
			{callerName}, then {toolCount ? `${toolCount} annotation tool${toolCount === 1 ? '' : 's'}` : 'nothing more (gene calls only)'}
		</p>
		<div class="acts">
			<button type="button" class="pill" aria-expanded={!ui.isFolded(WORKFLOW, true)} onclick={toggleWorkflow}>
				{ui.isFolded(WORKFLOW, true) ? 'Choose tools' : 'Done'}
			</button>
			<button type="button" class="pill" aria-expanded={showGenomes} onclick={toggleGenomes}>
				{showGenomes ? 'Hide genome table' : n ? 'Genome table' : 'Add genomes'}
			</button>
		</div>
	</div>

	<div class="go">
		{#if run}
			<BuildBar percent={pct} label={p?.stage ?? 'Annotating'} text={runText} />
			<div class="acts">
				<a class="mg-link quiet" href={uiBase.to(`/runs/${run.id}`)}>Log</a>
				<span class="mg-grow"></span>
				<button type="button" class="pill stop" onclick={stopRun}><Square size={12} strokeWidth={2.5} /> Stop</button>
			</div>
		{:else}
			{#if lastBad}
				<div class="bad" role="status">
					<p>
						<b>Last run {lastBad.status === 'cancelled' ? 'was stopped' : 'failed'}.</b>
						{#if lastBad.reason && lastBad.status === 'failed'}<span class="why" title={lastBad.reason}>{lastBad.reason}</span>{/if}
					</p>
					<div class="acts">
						<a class="mg-link quiet" href={uiBase.to(`/runs/${lastBad.id}`)}>Log</a>
						<span class="mg-grow"></span>
						{#if backend.cluster}
							<button type="button" class="pill" disabled={acting} onclick={() => restart(lastBad as Run)}>Restart</button>
						{/if}
						<button
							type="button"
							class="pill solid"
							disabled={acting}
							title="Run the same genomes and tools again; what finished is reused, not run again"
							onclick={() => resume(lastBad as Run)}
						>
							<RotateCcw size={13} strokeWidth={2.5} /> Resume
						</button>
					</div>
				</div>
			{/if}
			<RunAction />
		{/if}
	</div>
</section>

<Fold id={WORKFLOW} closed>
	<div class="gap"></div>
	<section class="extra" bind:this={workflowBox} aria-label="Tools for the next run">
		<header class="xhead">
			<span class="ic" aria-hidden="true"><ListOrdered size={15} /></span>
			<h2>Tools for the next run</h2>
			<span class="xnote">The gene caller runs first, then the annotation tools</span>
			<span class="mg-grow"></span>
			<button type="button" class="xclose" aria-label="Close the tools" onclick={toggleWorkflow}><X size={16} /></button>
		</header>
		<WorkflowSetup bare />
	</section>
</Fold>
<Fold id="analyze:genomes" open={showGenomes}>
	<div class="gap"></div>
	<section class="extra" bind:this={genomesBox} aria-label="Genome table">
		<header class="xhead">
			<span class="ic" aria-hidden="true"><Dna size={15} /></span>
			<h2>Genome table</h2>
			<span class="xnote">Domain, genetic code and which to run</span>
			<span class="mg-grow"></span>
			<a class="mg-link quiet" href={uiBase.to('/genomes')}>Open the Genomes page</a>
			<button type="button" class="xclose" aria-label="Hide the genome table" onclick={toggleGenomes}><X size={16} /></button>
		</header>
		<div class="xbody">
			<div class="table"><GenomesPanel bare /></div>
		</div>
	</section>
</Fold>

<!-- ------------------------------------------------ genomes and progress -->
<section class="card gridcard" class:folded={ui.isFolded(GRID, true)}>
	<header class="ghead">
		<FoldTitle id={GRID} closed>Genomes and progress</FoldTitle>
		<span class="count">{rows.length ? `${rows.length} genome${rows.length === 1 ? '' : 's'}` : ''}{counts.all ? ` | ${counts.done} of ${counts.all} steps done` : ''}</span>
		<span class="mg-grow"></span>
		<ul class="key" aria-label="Key">
			<li><span class="pie done" style="--p: 100"><Check size={9} strokeWidth={3.5} /></span>done</li>
			<li><span class="pie run" style="--p: 40"></span>running</li>
			<li><span class="pie failed"><X size={9} strokeWidth={3.5} /></span>failed</li>
			<li><span class="pie none"></span>not started</li>
			<li><span class="pie na"></span>not used</li>
		</ul>
		<FoldToggle id={GRID} closed />
	</header>
	<Fold id={GRID} closed>
		{#if rows.length && cols.length}
			<div class="scroller">
				<table class="pgrid" aria-label="Results in, by genome and tool">
					<thead>
						<tr class="phases">
							<th class="corner" rowspan="2" scope="col">Genome</th>
							{#each phases as g (g.label)}<th colspan={g.cols.length} scope="colgroup">{g.label}</th>{/each}
						</tr>
						<tr class="tools">
							{#each phases as g (g.label)}
								{#each g.cols as t, i (t)}<th scope="col" class:first={i === 0}><span>{t}</span></th>{/each}
							{/each}
						</tr>
						<!-- each tool across every genome -->
						<tr class="totals">
							<th scope="row" class="gname" title="All genomes: {overall}% of their steps done">
								<span class="gn">
									<span class="pie big" class:done={overall === 100} style="--p: {overall}" aria-hidden="true">
										{#if overall === 100}<Check size={9} strokeWidth={3.5} />{/if}
									</span>
									<span class="nm">All genomes</span>
									<span class="gpct">{overall}%</span>
								</span>
							</th>
							{#each columns as c (c.t)}
								{@const st = c.pct === null ? 'na' : c.pct === 100 ? 'done' : c.failed ? 'failed' : c.pct > 0 ? 'run' : 'none'}
								<th
									class:first={firsts.has(c.t)}
									title={c.pct === null
										? `${c.t}: not used`
										: `${c.t}: ${c.pct}% overall | ${c.done} of ${c.of} genome${c.of === 1 ? '' : 's'} done${c.failed ? ` | ${c.failed} failed` : ''}`}
								>
									<span class="pie {st === 'failed' ? 'run hurt' : st}" style="--p: {c.pct ?? 0}">
										{#if st === 'done'}<Check size={9} strokeWidth={3.5} />{/if}
									</span>
								</th>
							{/each}
						</tr>
					</thead>
					<tbody>
						{#each matrix as row (row.g)}
							<tr>
								<th scope="row" class="gname" title="{row.g}: {row.pct}% of its steps done">
									<span class="gn">
										<span class="pie big" class:done={row.pct === 100} style="--p: {row.pct}" aria-hidden="true">
											{#if row.pct === 100}<Check size={9} strokeWidth={3.5} />{/if}
										</span>
										<span class="nm">{row.g}</span>
										<span class="gpct">{row.pct}%</span>
									</span>
								</th>
								{#each row.cells as c (c.t)}
									{@const mark = c.state === 'done' ? 'tick' : c.state === 'failed' ? 'cross' : ''}
									<td class:first={firsts.has(c.t)} title="{row.g} | {c.t}: {c.say}{c.href ? (c.state === 'failed' ? ' | click for the log' : ' | click to open its folder') : ''}">
										{#if c.href}
											<a class="cellink" href={c.href} aria-label="{row.g} {c.t}: {c.say}">
												<span class="pie {c.state}" style="--p: {c.pct ?? 0}">
													{#if mark === 'tick'}<Check size={9} strokeWidth={3.5} />{:else if mark === 'cross'}<X size={9} strokeWidth={3.5} />{/if}
												</span>
											</a>
										{:else}
											<span class="pie {c.state}" style="--p: {c.pct ?? 0}"></span>
										{/if}
									</td>
								{/each}
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{:else}
			<p class="mg-note empty">
				{n ? 'Choose tools to see a column for each.' : 'No genomes yet.'}
				{#if !n}<a class="mg-link" href={uiBase.to('/genomes')}>Add FASTA files</a>{/if}
			</p>
		{/if}
	</Fold>
</section>
</div>

<style>
	.analyze {
		display: flex;
		flex-direction: column;
	}
	.card {
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		color: var(--mg-text);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow, none);
	}

	/* ---------------------------------------- the run: where | what | go */
	.runcard {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(0, 0.8fr) minmax(0, 1.2fr);
	}
	.runcard > div {
		display: flex;
		flex-direction: column;
		justify-content: center;
		gap: 10px;
		min-width: 0;
		padding: var(--mg-pad) calc(var(--mg-pad) * 1.2);
	}
	.runcard > div + div {
		border-left: 1px solid var(--mg-border);
	}
	.lbl {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		flex: none;
		margin: 0;
		font-size: var(--mg-fs-xs);
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.field {
		display: grid;
		grid-template-columns: 64px minmax(0, 1fr) auto;
		align-items: center;
		gap: 8px;
		margin: 0;
		font-size: var(--mg-fs-sm);
	}
	.field input {
		grid-column: 2 / -1;
		min-width: 0;
	}
	.path {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		color: var(--mg-text-2);
	}
	.sum {
		margin: 0;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.acts {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 8px;
	}
	.pill {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		height: 30px;
		padding: 0 14px;
		border: 1px solid color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-accent-ink, var(--mg-accent));
		font: inherit;
		font-size: var(--mg-fs-sm);
		font-weight: 500;
		cursor: pointer;
	}
	.pill:hover:not(:disabled),
	.pill[aria-expanded='true'] {
		background: color-mix(in srgb, var(--mg-accent) 10%, transparent);
	}
	.pill.solid {
		border-color: transparent;
		background: var(--mg-accent);
		color: var(--mg-on-accent, #fff);
	}
	.pill.solid:hover:not(:disabled) {
		background: var(--mg-accent);
		filter: brightness(0.95);
	}
	.pill.stop {
		border-color: color-mix(in srgb, var(--mg-danger, #c0392b) 55%, var(--mg-border));
		color: var(--mg-danger, #c0392b);
	}
	.pill.stop:hover {
		background: color-mix(in srgb, var(--mg-danger, #c0392b) 10%, transparent);
	}
	.pill:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.bad {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 10px 12px;
		border: 1px solid color-mix(in srgb, var(--mg-warn) 45%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-warn) 6%, transparent);
		font-size: var(--mg-fs-sm);
	}
	.bad p {
		display: flex;
		flex-direction: column;
		gap: 2px;
		margin: 0;
		min-width: 0;
	}
	.bad b {
		font-weight: 500;
	}
	.why {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-2);
	}
	/* RunAction's own button fills the column. */
	.go :global(.go) {
		width: 100%;
	}

	/* ---------------------------------------- genomes and progress */
	.gridcard {
		margin-top: var(--cr-gutter, 16px);
		overflow: hidden;
	}
	.ghead {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 6px 12px;
		min-height: 44px;
		padding: 6px var(--mg-pad);
		border-bottom: 1px solid var(--mg-border);
	}
	.gridcard.folded .ghead {
		border-bottom-color: transparent;
	}
	.ghead :global(.mo-fold-title) {
		margin: 0;
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.count {
		font-size: var(--mg-fs-sm);
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-2);
	}
	.key {
		display: flex;
		gap: 14px;
		margin: 0;
		padding: 0;
		list-style: none;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.key li {
		display: inline-flex;
		align-items: center;
		gap: 5px;
	}
	/* Scrolls both ways; pull its corner to make it taller. */
	.scroller {
		max-height: 60vh;
		min-height: 160px;
		overflow: auto;
		resize: vertical;
	}
	/* The full width of the card: few tools give wider columns, many give narrow ones. */
	.pgrid {
		width: 100%;
		border-collapse: separate;
		border-spacing: 0;
		font-size: var(--mg-fs-xs);
	}
	/* Three pinned rows of fixed height: phases (26), tool names (96), totals (30). */
	.pgrid thead th {
		box-sizing: border-box;
		position: sticky;
		z-index: 2;
		background: var(--cr-card, var(--mg-surface));
		font-weight: 500;
		color: var(--mg-text-3);
	}
	.phases th {
		top: 0;
		height: 26px;
		padding: 0 6px;
		border-bottom: 1px solid var(--mg-border);
		border-left: 1px solid var(--mg-border);
		text-align: left;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		white-space: nowrap;
	}
	.tools th {
		top: 26px;
		height: 96px;
		padding: 4px 0;
		border-bottom: 1px solid var(--mg-border);
		vertical-align: bottom;
	}
	.tools th span {
		display: inline-block;
		writing-mode: vertical-rl;
		transform: rotate(180deg);
		white-space: nowrap;
		color: var(--mg-text-2);
	}
	/* The row of totals stays in view under the tool names. */
	.totals th {
		top: 122px;
		height: 30px;
		border-bottom: 1px solid var(--mg-border);
		text-align: center;
	}
	.totals .gname {
		z-index: 3;
		color: var(--mg-text-2);
	}
	.pie.hurt {
		border-color: var(--mg-danger, #c0392b);
	}
	.cellink {
		display: inline-grid;
		place-items: center;
		border-radius: 50%;
	}
	.cellink:hover .pie {
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--mg-accent) 25%, transparent);
	}
	.cellink:focus-visible {
		outline: 2px solid var(--mg-accent);
		outline-offset: 1px;
	}
	.pgrid .corner {
		left: 0;
		z-index: 3;
		width: 240px;
		min-width: 240px;
		padding: 0 var(--mg-pad);
		border-bottom: 1px solid var(--mg-border);
		text-align: left;
		vertical-align: bottom;
		padding-bottom: 8px;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}
	.gname {
		position: sticky;
		left: 0;
		z-index: 1;
		width: 240px;
		max-width: 240px;
		height: 26px;
		padding: 0 var(--mg-pad);
		background: var(--cr-card, var(--mg-surface));
		font-weight: 400;
		text-align: left;
		color: var(--mg-text);
	}
	.gn {
		display: flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
	}
	.nm {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.pgrid td {
		min-width: 24px;
		height: 26px;
		padding: 0;
		text-align: center;
	}
	.pgrid .first {
		border-left: 1px solid var(--mg-border);
	}
	.pgrid tbody tr:hover th,
	.pgrid tbody tr:hover td {
		background: color-mix(in srgb, var(--mg-accent) 5%, var(--cr-card, var(--mg-surface)));
	}
	.empty {
		margin: 0;
		padding: var(--mg-pad);
	}

	/* ---------------------------------------- the pies, as Finder draws a copy */
	@property --p {
		syntax: '<number>';
		inherits: false;
		initial-value: 0;
	}
	.pie {
		--p: 0;
		display: inline-grid;
		place-items: center;
		flex: none;
		width: 15px;
		height: 15px;
		border-radius: 50%;
		border: 1.5px solid color-mix(in srgb, var(--mg-accent) 55%, var(--mg-border));
		background: conic-gradient(var(--mg-accent) calc(var(--p) * 1%), transparent 0);
		color: var(--mg-on-accent, #fff);
		vertical-align: middle;
		transition: --p 600ms ease;
	}
	.pie.big {
		width: 16px;
		height: 16px;
	}
	/* Done: full, with a tick. */
	.pie.done {
		border-color: var(--mg-accent);
		background: var(--mg-accent);
	}
	/* Failed: a cross on the danger colour. */
	.pie.failed {
		border-color: var(--mg-danger, #c0392b);
		background: var(--mg-danger, #c0392b);
	}
	/* Under way: filled as far as its own tool has got. */
	.pie.run {
		border-color: var(--mg-accent);
		transition: --p 2s linear;
	}
	/* Under way with nothing to estimate from: its ring breathes, and it fills no further than the truth. */
	.pie.wait {
		border-color: var(--mg-accent);
		animation: breathe 2.4s ease-in-out infinite;
	}
	@keyframes breathe {
		50% {
			border-color: color-mix(in srgb, var(--mg-accent) 25%, transparent);
		}
	}
	.pie.partial {
		border-style: dashed;
		border-color: var(--mg-warn);
	}
	.pie.none {
		border-style: dotted;
		border-color: var(--mg-border-strong);
	}
	/* Not used here (off, not chosen, not in this pipeline): a quiet grey disc, unlike any step that runs. */
	.pie.na {
		border-color: transparent;
		background: color-mix(in srgb, var(--mg-text-3) 14%, transparent);
	}
	.gpct {
		margin-left: auto;
		padding-left: 8px;
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-3);
	}

	/* ---------------------------------------- the cards that open below */
	/* Inside a fold, so a folded card leaves no space behind. */
	.gap {
		height: var(--cr-gutter, 16px);
	}
	.extra {
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow, none);
		color: var(--mg-text);
	}
	.xhead {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 12px;
		padding: 10px var(--mg-pad);
		border-bottom: 1px solid var(--mg-border);
	}
	.xhead h2 {
		margin: 0;
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.ic {
		flex: none;
		display: grid;
		place-items: center;
		width: 26px;
		height: 26px;
		border-radius: 8px;
		background: color-mix(in srgb, var(--mg-accent) 12%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.xnote {
		color: var(--mg-text-3);
		font-size: var(--mg-fs-sm);
	}
	.xclose {
		display: grid;
		place-items: center;
		width: 28px;
		height: 28px;
		border: 1px solid var(--mg-border);
		border-radius: 50%;
		background: var(--mg-surface);
		color: var(--mg-text-2);
		cursor: pointer;
	}
	.xclose:hover {
		color: var(--mg-text);
		border-color: var(--mg-border-strong);
	}
	.xbody {
		padding: var(--mg-pad);
	}
	.table {
		max-height: 44vh;
		overflow: auto;
		resize: vertical;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
	}

	:global([data-motion='off']) .pie {
		animation: none !important;
		transition: none !important;
	}

	@media (max-width: 1100px) {
		.runcard {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.runcard > .go {
			grid-column: 1 / -1;
			border-left: none;
			border-top: 1px solid var(--mg-border);
		}
	}
	@media (max-width: 700px) {
		.runcard {
			grid-template-columns: minmax(0, 1fr);
		}
		.runcard > div + div {
			border-left: none;
			border-top: 1px solid var(--mg-border);
		}
		.key,
		.xnote {
			display: none;
		}
	}
</style>
