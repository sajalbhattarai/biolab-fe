<script lang="ts">
	import QueueWait from '$lib/workspace/blocks/QueueWait.svelte';
	import { formatBytes } from '$lib/api';
	import { uiBase } from '$lib/workspace/base.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { ws, type StoreOp } from '$lib/workspace/data.svelte';
	import Fold from '$lib/workspace/motion/Fold.svelte';
	import FoldTitle from '$lib/workspace/motion/FoldTitle.svelte';
	import FoldToggle from '$lib/workspace/motion/FoldToggle.svelte';
	import ProgressBar from '$lib/workspace/ProgressBar.svelte';
	import { ui } from '$lib/workspace/ui.svelte';
	import { forget, WORKFLOW } from './backend';
	import { call, get } from './http';
	import Licence from './Licence.svelte';

	/**
	 * Cluster Install page: connection, SLURM account, licence terms, containers
	 * and databases (setting up missing ones by copy, pull or margie-build), and a
	 * self-test SLURM job.
	 */

	const known = $derived(!!ws.overview);
	const ready = $derived(ws.setup.filter((r) => r.required).every((r) => r.tone === 'ok'));

	// ---- self-test ----
	interface Probe {
		status: string;
		phase?: string;
		logs?: string;
	}
	let probe = $state<{ id: string; job: Probe | null; started: number } | null>(null);
	let testing = $state(false);
	const terminal = (s?: string) => ['completed', 'failed', 'cancelled', 'error', 'success'].includes((s ?? '').toLowerCase());

	/** Submits the quick example job and follows it. */
	async function selfTest() {
		testing = true;
		try {
			const r = await call<{ job_id: string }>('POST', '/v1/workflows/run_quick_example');
			probe = { id: r.job_id, job: null, started: Date.now() };
			follow(r.job_id);
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
			testing = false;
		}
	}

	/** Polls the job every 2 s until it finishes or another probe replaces it. */
	async function follow(id: string) {
		while (probe?.id === id) {
			try {
				const job = await get<Probe>(`/v1/ssh/job_status/${encodeURIComponent(id)}`);
				if (probe?.id !== id) return;
				probe.job = job;
				if (terminal(job.status)) break;
			} catch {
				// Retried on the next poll.
			}
			await new Promise((r) => setTimeout(r, 2000));
		}
		testing = false;
	}

	// ---- installed assets ----
	const STATUS: Record<string, { text: string; cls: string }> = {
		ok: { text: 'there', cls: 'ok' },
		missing: { text: 'not found', cls: 'bad' },
		optional: { text: 'not found', cls: '' },
		unknown: { text: 'cannot tell', cls: '' },
		warn: { text: 'check', cls: 'bad' }
	};
	const shelves = $derived([
		{ id: 'containers', title: 'Containers', rows: ws.images },
		{ id: 'databases', title: 'Databases', rows: ws.databases }
	]);
	const counted = (rows: typeof ws.images) => {
		const of = rows.filter((r) => r.status !== 'optional');
		return `${of.filter((r) => r.status === 'ok').length} of ${of.length} there`;
	};

	// ---- setting up missing assets ----
	interface PlanItem {
		id: string;
		label: string;
		kind: 'image' | 'database';
		tool: string;
		action: 'copy' | 'pull' | 'build';
		dst: string;
		bytes: number | null;
		gated: boolean;
	}
	interface Plan {
		items: PlanItem[];
		skipped: { id: string; label: string; kind: string; reason: string }[];
		config: Record<string, string>;
		copy_bytes: number;
		free: number | null;
		fits: boolean;
		statement: string;
		/** Destination folders for containers and databases. */
		sif_dir: string;
		db_dir: string;
	}
	let builds = $state(true);
	let optional = $state(false);
	let plan = $state<Plan | null>(null);
	let planning = $state(false);
	let accepted = $state(false);
	let op = $state<StoreOp | null>(null);
	const opBusy = $derived(op?.state === 'queued' || op?.state === 'running');
	const lacking = $derived([...ws.images, ...ws.databases].some((r) => r.status !== 'ok'));
	const gatedTools = $derived([...new Set((plan?.items ?? []).filter((i) => i.gated).map((i) => i.label))]);
	const ACTION: Record<PlanItem['action'], string> = { copy: 'copied from the lab folder', pull: 'pulled', build: 'built with margie-build' };
	const what = (kind: string) => (kind === 'image' ? 'container' : 'database');
	const count = (a: PlanItem['action']) => (plan?.items ?? []).filter((i) => i.action === a).length;

	// margie-build builds what cannot be copied: found on the cluster or cloned here.
	interface Recipes {
		path: string | null;
		source: 'settings' | 'lab' | 'yours' | null;
		clone_to: string;
		url: string;
	}
	let recipes = $state<Recipes | null>(null);
	let recipesUrl = $state('');
	let cloning = $state(false);
	const WHERE: Record<string, string> = { settings: 'set in Settings', lab: "the lab's copy on depot", yours: 'your own clone' };
	$effect(() => {
		get<Recipes>('/v1/ssh/assets/build-recipes')
			.then((r) => {
				recipes = r;
				recipesUrl = r.url;
			})
			.catch(() => (recipes = null));
	});
	/** Clones margie-build on the cluster from the given URL. */
	async function cloneRecipes() {
		cloning = true;
		try {
			recipes = await call<Recipes>('POST', '/v1/ssh/assets/build-recipes', { url: recipesUrl });
			forget('config');
			ui.notify(`margie-build is in ${recipes.path}.`, 'ok');
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		} finally {
			cloning = false;
		}
	}

	// Destination folders proposed by the plan; only changed ones are sent.
	let sifTo = $state('');
	let dbTo = $state('');
	let proposed = { sif: '', db: '' };
	const chosen = () => ({
		sif_to: sifTo.trim() && sifTo.trim() !== proposed.sif ? sifTo.trim() : '',
		db_to: dbTo.trim() && dbTo.trim() !== proposed.db ? dbTo.trim() : ''
	});

	/** Fetches the setup plan, optionally keeping the chosen destination folders. */
	async function preview(keep = false) {
		planning = true;
		accepted = false;
		try {
			const to = keep ? chosen() : { sif_to: '', db_to: '' };
			plan = await get<Plan>(
				`/v1/ssh/assets/plan?builds=${builds}&optional=${optional}&accept=*&sif_to=${encodeURIComponent(to.sif_to)}&db_to=${encodeURIComponent(to.db_to)}`
			);
			if (!keep) proposed = { sif: plan.sif_dir, db: plan.db_dir };
			sifTo = plan.sif_dir;
			dbTo = plan.db_dir;
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		} finally {
			planning = false;
		}
	}

	/** Starts the setup job with the accepted gated tools and chosen folders. */
	async function setUp() {
		const accept = accepted ? [...new Set((plan?.items ?? []).filter((i) => i.gated).map((i) => i.tool))] : [];
		const to = chosen();
		plan = null;
		try {
			op = (await call<{ op: StoreOp | null }>('POST', '/v1/ssh/assets/setup', { builds, optional, accept, ...to })).op;
			watch();
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		}
	}

	// Polls the shared stores copy job every 2 s and refreshes when it ends.
	let watching = false;
	async function watch() {
		if (watching) return;
		watching = true;
		while (watching) {
			try {
				op = (await get<{ op: StoreOp | null }>('/v1/ssh/stores/progress')).op;
			} catch {
				// A missed poll is not a failed copy.
			}
			if (!opBusy) break;
			await new Promise((r) => setTimeout(r, 2000));
		}
		if (!watching) return;
		watching = false;
		if (op?.op !== 'assets') return;
		forget('config');
		await Promise.allSettled([ws.loadCheck(), ws.loadSettings(), ws.loadOverview()]);
		if (op.state === 'done') ui.notify('The containers and databases are set up.', 'ok');
	}
	$effect(() => {
		// Picks up a setup started earlier or elsewhere.
		get<{ op: StoreOp | null }>('/v1/ssh/stores/progress')
			.then((d) => {
				if (d.op?.op !== 'assets') return;
				op = d.op;
				if (opBusy) watch();
			})
			.catch(() => {});
		return () => (watching = false);
	});

	const probeLines = $derived((probe?.job?.logs ?? '').trimEnd().split('\n').slice(-8).join('\n'));
	const probeOk = $derived(['completed', 'success'].includes((probe?.job?.status ?? '').toLowerCase()));
	const seconds = $derived(probe ? Math.round((Date.now() - probe.started) / 1000) : 0);

	// ---- workflow tools by phase ----
	interface WorkflowTool {
		key?: string;
		phase?: number;
		name: string;
		purpose: string;
	}
	let phases = $state<[number, WorkflowTool[]][]>([]);
	$effect(() => {
		get<{ id: string; tools: WorkflowTool[] }[]>('/v1/ssh/workflows')
			.then((all) => {
				const tools = all.find((w) => w.id === WORKFLOW)?.tools ?? [];
				const by = new Map<number, WorkflowTool[]>();
				for (const t of tools) if (t.phase !== undefined) by.set(t.phase, [...(by.get(t.phase) ?? []), t]);
				phases = [...by.entries()].sort((a, b) => a[0] - b[0]);
			})
			.catch(() => (phases = []));
	});
	const purpose = (t: WorkflowTool) => t.purpose.replace(/^Phase \d+:\s*/, '');
</script>

{#snippet head(id: string, title: string, meta: string)}
	<header class="mg-card-head">
		<FoldTitle id="setup:{id}">{title}</FoldTitle>
		<span class="mg-note">{meta}</span>
		<span class="mg-grow"></span>
		<FoldToggle id="setup:{id}" />
	</header>
{/snippet}

<!-- Two columns; tools and reference data span the full width. -->
<div class="cs-grid mg-in">
	<section class="mg-card" data-shade="at-a-glance">
		{@render head('at-a-glance', 'At a glance', known ? (ready ? `ready on ${backend.host}` : `${ws.setupReady.ok} of ${ws.setupReady.total} ready`) : 'reaching the cluster')}
		<Fold id="setup:at-a-glance">
			<ul class="list">
				{#each ws.setup as r (r.id)}
					<li>
						<span class="name">{r.label}</span>
						<span class="status" class:mg-warn={r.tone === 'warn'} class:mg-danger={r.tone === 'danger'}>{r.value}</span>
						<span class="detail mg-note" title={r.detail}>{r.detail}</span>
						{#if r.href && r.tone !== 'ok' && r.tone !== 'neutral' && !r.href.startsWith('/setup')}
							<a class="mg-link" href={uiBase.to(r.href)}>Set it</a>
						{:else}
							<span></span>
						{/if}
					</li>
				{:else}
					<li class="mg-note">Reaching the cluster…</li>
				{/each}
			</ul>
		</Fold>
	</section>

	<section class="mg-card" id="terms" data-shade="licences">
		{@render head('terms', 'Licence terms', ws.overview?.licences ? '' : '')}
		<Fold id="setup:terms"><Licence /></Fold>
	</section>

	<section class="mg-card cs-wide" id="installed" data-shade="tools">
		{@render head('installed', 'Tools and reference data', ws.check ? shelves.map((s) => `${s.title.toLowerCase()} ${counted(s.rows)}`).join(' | ') : 'looking')}
		<Fold id="setup:installed">
			<p class="mg-note lede">
				Where the workflow will look for each tool's container and database, from your cluster config: the containers and databases folders
				under <a class="mg-link" href={uiBase.to('/settings#folders')}>Settings → Folders</a>, which start at the lab's shared folders. A
				folder your account cannot read shows as "cannot tell". GTDB-Tk and the LLM layer are only needed when chosen. A run that needs one
				that is not there does not start.
				<button type="button" class="mg-link quiet" disabled={ws.checking} onclick={() => ws.loadCheck()}>{ws.checking ? 'Looking' : 'Look again'}</button>
			</p>
			{#if op && (opBusy || op.state === 'failed')}
				<div class="assets-op">
					<ProgressBar
						percent={op.percent}
						state={op.state}
						label={op.state === 'queued' ? 'Waiting for a SLURM slot' : `Setting up${op.label && op.label !== 'Starting' ? `: ${op.label}` : ''}`}
						detail={op.state === 'failed' ? op.message || 'The setup did not finish.' : op.job ? `SLURM job ${op.job}` : ''}
						log={[...(op.log ?? []), ...(op.slurm_out ?? [])]}
					/>
					<QueueWait {op} onchange={(o) => (op = o)} />
				</div>
			{/if}
			{#if recipes}
				<div class="assets-recipes">
					{#if recipes.path}
						<span>Build recipes: <span class="mg-mono">{recipes.path}</span> <span class="mg-note">({WHERE[recipes.source ?? ''] ?? ''})</span></span>
					{:else}
						<span>Build recipes (margie-build) are not on the cluster. Clone them into <span class="mg-mono">{recipes.clone_to}</span> to build what cannot be copied:</span>
						<input class="mg-input mg-mono" aria-label="margie-build repository" bind:value={recipesUrl} />
						<button type="button" class="mg-btn small" disabled={cloning || !recipesUrl.trim()} onclick={cloneRecipes}>
							{cloning ? 'Cloning…' : 'Clone'}
						</button>
					{/if}
				</div>
			{/if}
			{#if ws.check && lacking && !opBusy}
				<div class="assets-ask">
					{#if !plan}
						<p>
							Not all of them are where your config points. MARGIE can set up the missing ones on the cluster: copied from the lab's folder
							when it has them, pulled from a container registry if one is set, or built with margie-build. Nothing already there is replaced.
						</p>
						<div class="assets-opts">
							<label><input type="checkbox" bind:checked={builds} /> Build what cannot be copied (downloads; hours)</label>
							<label><input type="checkbox" bind:checked={optional} /> Include GTDB-Tk and the LLM layer</label>
							<button type="button" class="mg-btn small primary" disabled={planning} onclick={() => preview()}>
								{planning ? 'Working it out…' : 'Set up what is missing'}
							</button>
						</div>
					{:else}
						{#if plan.items.length}
							<p>
								<b>{plan.items.length}</b> to set up:
								{[
									count('copy') && `${count('copy')} copied (${formatBytes(plan.copy_bytes)})`,
									count('pull') && `${count('pull')} pulled`,
									count('build') && `${count('build')} built`
								]
									.filter(Boolean)
									.join(', ')}.
								{plan.free !== null ? `Scratch has ${formatBytes(plan.free)} free.` : ''}
							</p>
							<ul class="assets-items">
								{#each plan.items as i (i.id)}
									<li>
										<span>{i.label} {what(i.kind)}</span>
										<span class="mg-note">{ACTION[i.action]}{i.gated ? ' (licence)' : ''}</span>
										<span class="mg-note mg-mono path" title={i.dst}><span dir="ltr">{i.dst}</span></span>
									</li>
								{/each}
							</ul>
						{:else}
							<p>Nothing here can be set up from this account.</p>
						{/if}
						<div class="assets-where">
							<label>
								<span>Containers go in</span>
								<input class="mg-input mg-mono" bind:value={sifTo} />
							</label>
							<label>
								<span>Databases go in</span>
								<input class="mg-input mg-mono" bind:value={dbTo} />
							</label>
							<button
								type="button"
								class="mg-btn small"
								disabled={planning || (sifTo.trim() === plan.sif_dir && dbTo.trim() === plan.db_dir)}
								onclick={() => preview(true)}
							>
								{planning ? 'Working it out…' : 'Use these folders'}
							</button>
							<span class="mg-note">Any folder your account can write to, except the lab's on depot. The databases each go in a folder of their own there.</span>
						</div>
						{#if Object.keys(plan.config).length}
							<p class="mg-note">
								Your config will point at the new copies: {Object.entries(plan.config)
									.map(([k, v]) => `${k} → ${v}`)
									.join('; ')}.
							</p>
						{/if}
						{#if plan.skipped.length}
							<details class="mg-note">
								<summary>{plan.skipped.length} left out</summary>
								<ul>
									{#each plan.skipped as sk (sk.id)}<li>{sk.label} {what(sk.kind)}: {sk.reason}</li>{/each}
								</ul>
							</details>
						{/if}
						{#if gatedTools.length}
							<label class="assets-licence">
								<input type="checkbox" bind:checked={accepted} />
								<span>
									To build {gatedTools.join(', ')}: “{plan.statement}” This is a legally binding agreement; your use of these tools and their
									databases is your own responsibility. Unticked, they are left out.
								</span>
							</label>
						{/if}
						{#if !plan.fits}
							<p class="no-room">
								The copies need {formatBytes(plan.copy_bytes)} and scratch has {plan.free === null ? 'unknown' : formatBytes(plan.free)} free (5 GB is
								kept spare): they would not fit.
							</p>
						{/if}
						<div class="assets-opts">
							{#if plan.items.length && plan.fits}
								<button type="button" class="mg-btn small primary" onclick={setUp}>Yes, set them up</button>
							{/if}
							<button type="button" class="mg-btn small" onclick={() => (plan = null)}>No</button>
						</div>
					{/if}
				</div>
			{/if}
			<div class="shelves">
				{#each shelves as shelf (shelf.id)}
					<div class="shelf">
						<h3>{shelf.title} <span class="mg-note">{counted(shelf.rows)}</span></h3>
						<ul class="found">
							{#each shelf.rows as r (r.name)}
								<li>
									<span class="mg-mono tool" title={r.name}>{r.name}</span>
									<span class="state {STATUS[r.status]?.cls ?? ''}">{STATUS[r.status]?.text ?? r.status}</span>
									<!-- Truncated from the left so the file name stays visible. -->
									<span class="mg-note path" title={r.detail}><span dir="ltr">{r.detail}</span></span>
								</li>
							{:else}
								<li class="mg-note">{ws.check ? 'None listed by the workflow.' : 'Looking…'}</li>
							{/each}
						</ul>
					</div>
				{/each}
			</div>
		</Fold>
	</section>

	<section class="mg-card" data-shade="container-app">
		{@render head('self-test', 'Check the cluster', 'SSH, the job runner and SLURM, end to end')}
		<Fold id="setup:self-test">
			<div class="test">
				<p class="mg-note">
					Starts MARGIE's quick self-test on {backend.host || 'the cluster'}: a tiny workflow that touches a few files and records them, so it
					finishes in seconds. If it does, a real run has a working path from here to SLURM and back.
				</p>
				<div class="acts">
					<button type="button" class="mg-btn small" disabled={testing} onclick={selfTest}>{testing ? 'Running…' : 'Run the self-test'}</button>
					{#if probe?.job}
						<span class="verdict" class:ok={probeOk} class:bad={terminal(probe.job.status) && !probeOk}>
							{probeOk ? `Passed in ${seconds} s` : terminal(probe.job.status) ? `Did not pass: ${probe.job.status}` : (probe.job.phase ?? probe.job.status)}
						</span>
					{/if}
				</div>
				{#if probeLines}<pre class="log">{probeLines}</pre>{/if}
			</div>
		</Fold>
	</section>

	<section class="mg-card" data-shade="tools">
		{@render head('phases', 'What a run can use', phases.length ? `${phases.reduce((a, [, t]) => a + t.length, 0)} steps in ${phases.length} phases` : '')}
		<Fold id="setup:phases">
			<p class="mg-note lede">
				The tools' containers and databases are in the folders set under
				<a class="mg-link" href={uiBase.to('/settings#folders')}>Settings → Folders</a>. A run goes through these phases in order; Analyze
				chooses which of the tools take part.
			</p>
			<ol class="phases">
				{#each phases as [n, tools] (n)}
					<li>
						<span class="n">{n}</span>
						<span class="names">
							{#each tools as t, i (t.key ?? t.name)}<span title={purpose(t)}>{t.name}</span>{i < tools.length - 1 ? ', ' : ''}{/each}
						</span>
						<span class="mg-note why">{tools.length === 1 ? purpose(tools[0]) : ''}</span>
					</li>
				{/each}
			</ol>
		</Fold>
	</section>
</div>

<style>
	.cs-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--cr-gutter, 20px);
		align-items: start;
	}
	.cs-grid > .mg-card {
		min-width: 0;
	}
	.cs-wide {
		grid-column: 1 / -1;
	}
	@media (max-width: 900px) {
		.cs-grid {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	.list {
		display: flex;
		flex-direction: column;
		padding: 8px var(--mg-pad) var(--mg-pad);
	}
	.list li {
		display: grid;
		grid-template-columns: 9rem minmax(0, 12rem) minmax(0, 1fr) auto;
		align-items: baseline;
		gap: 12px;
		min-height: 34px;
		padding: 6px 0;
		font-size: var(--mg-fs-sm);
	}
	.list li + li {
		border-top: 1px solid var(--mg-border);
	}
	.name {
		font-weight: 600;
	}
	.status,
	.detail {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.test {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: var(--mg-pad);
	}
	.test p {
		margin: 0;
		max-width: 80ch;
	}
	.acts {
		display: flex;
		align-items: center;
		gap: 14px;
	}
	.verdict {
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.verdict.ok {
		color: var(--mg-ok);
		font-weight: 600;
	}
	.verdict.bad {
		color: var(--mg-danger);
		font-weight: 600;
	}
	.log {
		margin: 0;
		padding: 10px 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-bg);
		font-family: var(--mg-mono);
		font-size: var(--mg-fs-xs);
		white-space: pre-wrap;
		overflow: auto;
		max-height: 14rem;
	}
	.assets-op,
	.assets-ask,
	.assets-recipes {
		margin: 8px var(--mg-pad) 0;
	}
	.assets-recipes {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 12px;
		font-size: var(--mg-fs-sm);
	}
	.assets-recipes input {
		flex: 1 1 28ch;
		min-width: 0;
	}
	.assets-ask {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 10px 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
		font-size: var(--mg-fs-sm);
	}
	.assets-ask p {
		margin: 0;
		max-width: 90ch;
	}
	.assets-opts {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 16px;
	}
	.assets-items {
		display: grid;
		grid-template-columns: minmax(0, max-content) max-content minmax(0, 1fr);
		column-gap: 14px;
		max-height: 16rem;
		overflow: auto;
	}
	.assets-items li {
		grid-column: 1 / -1;
		display: grid;
		grid-template-columns: subgrid;
		align-items: baseline;
		padding: 3px 0;
		border-top: 1px solid var(--mg-border);
	}
	.assets-where {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) auto;
		gap: 6px 12px;
		align-items: end;
	}
	.assets-where label {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.assets-where .mg-note {
		grid-column: 1 / -1;
	}
	@media (max-width: 700px) {
		.assets-where {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	.assets-licence {
		display: flex;
		gap: 8px;
		align-items: baseline;
	}
	.no-room {
		color: var(--mg-warn);
	}
	.shelves {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(26rem, 1fr));
		gap: var(--mg-gap);
		padding: 8px var(--mg-pad) var(--mg-pad);
	}
	.shelf h3 {
		margin: 0 0 6px;
		font-size: var(--mg-fs);
		font-weight: 650;
	}
	/* Rows share the list's columns (subgrid), so the name column fits the longest name. */
	.found {
		display: grid;
		grid-template-columns: minmax(0, max-content) max-content minmax(0, 1fr);
		column-gap: 14px;
	}
	.found li {
		grid-column: 1 / -1;
		display: grid;
		grid-template-columns: subgrid;
		align-items: baseline;
		padding: 5px 0;
		border-top: 1px solid var(--mg-border);
		font-size: var(--mg-fs-sm);
	}
	.state {
		color: var(--mg-text-3);
	}
	/* Coloured dot before the state word. */
	.state::before {
		content: '';
		display: inline-block;
		width: 7px;
		height: 7px;
		margin-right: 8px;
		border-radius: 50%;
		vertical-align: 1px;
		background: var(--mg-border-strong);
	}
	.state.ok::before {
		background: var(--mg-ok);
	}
	.state.bad::before {
		background: var(--mg-warn);
	}
	.state.ok {
		color: var(--mg-ok);
	}
	.state.bad {
		color: var(--mg-warn);
	}
	.tool {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.path {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		direction: rtl;
		text-align: left;
	}
	.path > span {
		unicode-bidi: isolate;
	}
	.lede {
		margin: 0;
		padding: 12px var(--mg-pad) 4px;
		max-width: 90ch;
	}
	.phases {
		display: flex;
		flex-direction: column;
		padding: 4px var(--mg-pad) var(--mg-pad);
	}
	.phases li {
		display: grid;
		grid-template-columns: 2rem minmax(0, 1.4fr) minmax(0, 1fr);
		gap: 12px;
		align-items: baseline;
		padding: 7px 0;
		font-size: var(--mg-fs-sm);
	}
	.phases li + li {
		border-top: 1px solid var(--mg-border);
	}
	.n {
		color: var(--mg-text-3);
		font-variant-numeric: tabular-nums;
	}
	@media (max-width: 700px) {
		.list li,
		.phases li {
			grid-template-columns: minmax(0, 1fr);
			gap: 2px;
		}
	}
</style>
