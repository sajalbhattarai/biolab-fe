<script lang="ts">
	import { Check } from 'lucide-svelte';
	import type { Snippet } from 'svelte';
	import { uiBase } from '../base.svelte';
	import { backend } from '../backend.svelte';
	import { clusterParts } from '../cluster-parts';
	import BuildBar from '$lib/workspace/blocks/BuildBar.svelte';
	import Fold from '$lib/workspace/motion/Fold.svelte';
	import FoldTitle from '$lib/workspace/motion/FoldTitle.svelte';
	import FoldToggle from '$lib/workspace/motion/FoldToggle.svelte';
	import { ws, type CheckRow } from '$lib/workspace/data.svelte';
	import type { Run } from '$lib/api';
	import { ui } from '$lib/workspace/ui.svelte';

	/**
	 * Install details in two rows: container app, build folder and Python; then tools and reference data.
	 * Cards start folded (InstallBoard opens one by data-shade); tool and data cards hold per-item tiles,
	 * selection, and a progress bar while a build of that kind runs. Clusters show their own page.
	 */

	type Kind = 'containers' | 'databases';

	const STATUS: Record<CheckRow['status'], string> = {
		ok: 'Ready',
		missing: 'Missing',
		warn: 'Check',
		optional: 'Optional',
		unknown: 'Unknown'
	};

	const o = $derived(ws.overview);
	const offered = $derived({
		containers: new Set(o?.repo.containers.map((i) => i.name) ?? []),
		databases: new Set(o?.repo.databases.map((i) => i.name) ?? [])
	});
	const repoName = $derived((ws.overview?.repo.path ?? '').split('/').filter(Boolean).pop() || 'the build repository');
	const missing = (rows: CheckRow[]) => rows.filter((r) => r.status === 'missing').length;
	/** Ready rows only; an unknown state (no container app running) counts as not built. */
	const ready = (rows: CheckRow[]) => rows.filter((r) => r.status === 'ok').length;

	/** Tools whose download the user supplies. */
	const NEEDS_DOWNLOAD: Record<string, { setting: string; where: string }> = {
		phobius: { setting: 'PHOBIUS_TARBALL', where: 'phobius.sbc.su.se' }
	};

	const gatedTools = $derived(new Set(o?.licences.tools ?? []));
	const acceptedTools = $derived(new Set(o?.licences.accepted ?? []));

	interface Fix {
		label: string;
		title: string;
		run?: () => void;
		href?: string;
	}

	/** Why a row cannot be built or downloaded here, or null. */
	function blocker(r: CheckRow, what: Kind): Fix | null {
		if (gatedTools.has(r.name) && !acceptedTools.has(r.name)) {
			return {
				label: 'Licence needed',
				title: `${r.name} carries its own licence terms and stays off until you accept them: Settings → Licences (README §8 explains the terms).`,
				href: uiBase.to('/settings#licences')
			};
		}
		if (!offered[what].has(r.name)) return { label: 'No recipe', title: `${repoName} has no recipe for ${r.name}.` };
		const own = NEEDS_DOWNLOAD[r.name];
		if (own && !ws.setting(own.setting).trim()) {
			return {
				label: 'Your download',
				title: `${r.name} may not be redistributed, so you download it from ${own.where} yourself and point Settings at your copy.`,
				href: uiBase.to(`/settings#${own.setting}`)
			};
		}
		return null;
	}

	/** The row's next action: build, download, accept licence, or supply. */
	function fixFor(r: CheckRow, what: Kind): Fix | null {
		if (r.status !== 'missing' && r.status !== 'warn') return null;
		const b = blocker(r, what);
		if (b) return b.label === 'No recipe' && !o?.repo.ok ? null : b;
		return {
			label: what === 'containers' ? 'Build' : 'Download',
			title: what === 'containers' ? `Build the ${r.name} image now.` : `Download ${r.name}'s reference data now.`,
			run: () => build(what, [r.name])
		};
	}

	/** Shortens a row's detail for a tile: strips the common path head and splits out a bracketed size. */
	function brief(detail: string): { text: string; size: string } {
		const m = /^(.*?)\s*\(([\d.]+\s*[KMGTP]i?B?)\)$/.exec(detail.trim());
		let text = m ? m[1] : detail;
		if (text.startsWith('/')) text = '…/' + text.split('/').filter(Boolean).slice(-2).join('/');
		return { text, size: m ? m[2] : '' };
	}

	// ---- runs of each kind and their progress ----
	/** The running build or download of this kind (build.sh's first argument names the kind). */
	const runFor = (what: Kind): Run | undefined =>
		ws.running.find((r) => r.kind === 'build' && (r.args[0] === `--${what}` || r.args[0] === '--all'));
	const runs = $derived({ containers: runFor('containers'), databases: runFor('databases') });

	/** Done and in-progress items of the watched run, from its log. */
	function stepsOf(run: Run | undefined): { done: Set<string>; now: string } {
		const log = run && ws.active?.id === run.id ? ws.log : '';
		const done = new Set([...log.matchAll(/^\[ *(?:ok|OK) *\] *([a-z0-9_-]+)/gm)].map((m) => m[1]));
		const now = [...log.matchAll(/^==> (?:Fetching|Building): (\S+)/gm)].at(-1)?.[1] ?? '';
		return { done, now: done.has(now) ? '' : now };
	}
	const steps = $derived({ containers: stepsOf(runs.containers), databases: stepsOf(runs.databases) });

	/** A row's state in its kind's run: absent, waiting, going or done. */
	function inRun(r: CheckRow, what: Kind): '' | 'queued' | 'going' | 'done' {
		const run = runs[what];
		if (!run?.tools?.includes(r.name)) return '';
		const s = steps[what];
		if (s.done.has(r.name)) return 'done';
		if (s.now === r.name) return 'going';
		return 'queued';
	}
	/** Progress in the run's own words, e.g. "1 of 3 done | pfam 62%". */
	function tally(what: Kind): string {
		const run = runs[what];
		if (!run) return '';
		const now = steps[what].now;
		const going = now ? ` | ${now}${run.progressText ? ` ${run.progressText}` : ''}` : '';
		if (!run.tools?.length) return `${run.progress ?? 0}%${going}`;
		return `${run.tools.filter((t) => steps[what].done.has(t)).length} of ${run.tools.length} done${going}`;
	}
	/** Percentage of the current item when the run reports one, else null. */
	const itemPct = (what: Kind): number | null => {
		const m = /^(\d{1,3})%$/.exec(runs[what]?.progressText ?? '');
		return m ? Math.min(100, Number(m[1])) : null;
	};
	/** Blocks a new run of a kind while one is going or the server has no capacity. */
	const blocked = (what: Kind) => !!runs[what] || !ws.canStart;

	// ---- multi-select ----
	let picked = $state<Record<Kind, string[]>>({ containers: [], databases: [] });
	/** Pickable rows: not ready and not blocked. Ready rows show a fixed tick. */
	const pickable = (rows: CheckRow[], what: Kind) =>
		rows.filter((r) => r.status !== 'ok' && r.status !== 'optional' && !blocker(r, what)).map((r) => r.name);
	function toggle(what: Kind, name: string) {
		picked[what] = picked[what].includes(name) ? picked[what].filter((n) => n !== name) : [...picked[what], name];
	}
	function pickAll(what: Kind, rows: CheckRow[], on: boolean) {
		picked[what] = on ? pickable(rows, what) : [];
	}
	function pickMissing(what: Kind, rows: CheckRow[]) {
		const can = new Set(pickable(rows, what));
		picked[what] = rows.filter((r) => r.status === 'missing' && can.has(r.name)).map((r) => r.name);
	}
	async function installPicked(what: Kind) {
		const names = picked[what];
		if (!names.length) return;
		if (await build(what, names)) picked[what] = [];
	}

	// ---- build folder ----
	let buildDir = $state('');
	let savingBuild = $state(false);
	/* Follows the saved folder until the user edits it. */
	let buildTouched = false;
	$effect(() => {
		const current = o?.repo.path ?? '';
		if (!buildTouched) buildDir = current;
	});
	async function useBuildFolder() {
		savingBuild = true;
		buildTouched = false;
		if (await ws.saveSettings({ SETUP_REPO: buildDir.trim() }))
			ui.notify(ws.overview?.repo.ok ? 'Build folder saved' : 'Saved, but that folder does not look like margie-build', ws.overview?.repo.ok ? 'ok' : 'error');
		savingBuild = false;
	}

	async function build(what: Kind, tools?: string[]) {
		const run = await ws.build(what, tools);
		if (run) ui.notify(`${what === 'containers' ? 'Building' : 'Downloading'}${tools?.length ? ` ${tools.join(', ')}` : ''}`, 'ok');
		return run;
	}

	async function chooseRuntime(id: string) {
		if (await ws.saveSettings({ RUNTIME: id })) ui.notify('Container app saved', 'ok');
	}

	/** Saved key for a card's open state. */
	const foldId = (title: string) => 'setup:' + title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
</script>

{#snippet badge(tone: 'ok' | 'warn' | 'none' | 'unknown')}
	<span class="sp-badge {tone}" aria-hidden="true">
		{#if tone === 'ok'}<Check size={10} strokeWidth={4} />{:else if tone === 'warn'}!{:else if tone === 'unknown'}?{/if}
	</span>
{/snippet}

{#snippet card(title: string, shade: string, count: string, body: Snippet, actions?: Snippet, under?: Snippet)}
	{@const id = foldId(title)}
	<section class="sp-card" class:folded={ui.isFolded(id, true)} data-shade={shade}>
		<header class="sp-head">
			<FoldTitle {id} closed>{title}</FoldTitle>
			{#if count}<span class="sp-count">{count}</span>{/if}
			<span class="mg-grow"></span>
			{#if actions}{@render actions()}{/if}
			<FoldToggle {id} closed />
		</header>
		{#if under}<div class="sp-under">{@render under()}</div>{/if}
		<Fold {id} closed>
			<div class="sp-body">{@render body()}</div>
		</Fold>
	</section>
{/snippet}

<!-- A kind's shelf: progress bar, selection bar and one tile per item. -->
{#snippet tiles(rows: CheckRow[], what: Kind)}
	{#if !ws.check}
		<p class="mg-note">Checking…</p>
	{:else if !rows.length}
		<p class="mg-note">None listed.</p>
	{:else}
		{@const can = pickable(rows, what)}
		{@const all = can.length > 0 && can.every((n) => picked[what].includes(n))}
		<div class="sp-pickbar">
			<label class="sp-check">
				<input
					type="checkbox"
					checked={all}
					indeterminate={!all && picked[what].length > 0}
					disabled={!can.length}
					onchange={(e) => pickAll(what, rows, e.currentTarget.checked)}
				/>
				Select all
			</label>
			{#if missing(rows)}<button type="button" class="mg-link quiet sp-small" onclick={() => pickMissing(what, rows)}>Missing only</button>{/if}
			{#if picked[what].length}<button type="button" class="mg-link quiet sp-small" onclick={() => (picked[what] = [])}>Clear</button>{/if}
			<span class="mg-grow"></span>
			<button
				type="button"
				class="sp-pill"
				disabled={!picked[what].length || blocked(what) || !o?.repo.ok}
				title={runs[what] ? 'One is already running' : !ws.canStart ? 'Wait for the run going now' : ''}
				onclick={() => installPicked(what)}
			>
				{what === 'containers' ? 'Build' : 'Download'} selected{picked[what].length ? ` (${picked[what].length})` : ''}
			</button>
		</div>
		<ul class="sp-tiles">
			{#each rows as r (r.name + r.section)}
				{@const fix = fixFor(r, what)}
				{@const b = brief(r.detail)}
				{@const run = inRun(r, what)}
				{@const may = can.includes(r.name)}
				<li class="sp-tile s-{r.status}" class:picked={picked[what].includes(r.name)} class:run={!!run} title={r.detail}>
					{#if may}
						<input
							type="checkbox"
							class="sp-pick"
							aria-label="Pick {r.name}"
							checked={picked[what].includes(r.name)}
							onchange={() => toggle(what, r.name)}
						/>
					{:else if r.status === 'ok' && !blocker(r, what)}
						<input type="checkbox" class="sp-pick" aria-label="{r.name} is ready" checked disabled />
					{:else}
						{@render badge(r.status === 'ok' ? 'ok' : r.status === 'missing' || r.status === 'warn' ? 'warn' : r.status === 'unknown' ? 'unknown' : 'none')}
					{/if}
					<span class="sp-tile-text">
						<span class="name">{r.name}</span>
						{#if run === 'going'}
							<span class="sp-state go">{runs[what]?.progressText || (what === 'containers' ? 'Building…' : 'Downloading…')}</span>
						{:else if run === 'queued'}
							<span class="sp-state">Queued</span>
						{:else if run === 'done'}
							<span class="sp-state ok">Done</span>
						{:else}
							<span class="sp-state">{STATUS[r.status]}{b.size ? ` | ${b.size}` : ''}</span>
						{/if}
					</span>
					{#if run === 'going'}
						{@const pct = itemPct(what)}
						<span class="sp-spin" aria-hidden="true"></span>
						<span class="sp-mini" class:unsure={pct === null} style="width: {pct ?? 100}%" aria-hidden="true"></span>
					{:else if !run && fix?.run}
						<button type="button" class="sp-pill sm" disabled={blocked(what)} aria-label="{fix.label} {r.name}" title={fix.title} onclick={fix.run}>{fix.label}</button>
					{:else if !run && fix?.href}
						<a class="sp-pill sm ghost" href={fix.href} aria-label="{r.name}: {fix.label}" title={fix.title}>{fix.label}</a>
					{:else if !run && fix}
						<span class="sp-flag" title={fix.title}>{fix.label}</span>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
{/snippet}

{#if backend.cluster && clusterParts.Setup}
	<!-- Cluster tools are installed by its administrators; its own page lists the user's part. -->
	<clusterParts.Setup />
{:else if o}
	<div class="sp-rows">
		<!-- ---- row one: container app | build folder over Python ---- -->
		<div class="sp-row two first">
			{#snippet runtimes()}
				<ul class="sp-apps">
					{#each o.runtimes as r (r.id)}
						{@const using = r.installed && o.runtime.active === r.id}
						<li class="sp-app" class:using class:off={!r.installed}>
							<span class="sp-app-top">
								{@render badge(r.running ? 'ok' : r.installed ? 'warn' : 'none')}
								<b>{r.label}</b>
								<span class="mg-grow"></span>
								{#if using}<span class="sp-flag on">In use</span>{/if}
							</span>
							<span class="sp-state">{r.running ? 'Running' : r.installed ? 'Not running' : 'Not installed'}</span>
							{#if r.installed ? !r.running && r.hint : r.install}
								{@const say = r.installed ? r.hint : r.install}
								{#if /^https?:\/\//.test(say)}
									<a class="mg-link sp-hint" href={say} target="_blank" rel="noreferrer" title={say}>Get it</a>
								{:else}
									<span class="sp-hint mg-note" title={say}>{say}</span>
								{/if}
							{/if}
							{#if r.installed && (!r.running || !using)}
								<span class="sp-app-acts">
									{#if !r.running}<button type="button" class="sp-pill sm" onclick={() => ws.startRuntime(r.id)}>Start</button>{/if}
									{#if !using}<button type="button" class="sp-pill sm ghost" onclick={() => chooseRuntime(r.id)}>Use</button>{/if}
								</span>
							{/if}
						</li>
					{/each}
				</ul>
			{/snippet}
			{@render card('Container app', 'container-app', o.runtime.label ? `${o.runtime.label}${o.runtime.ready ? ', running' : ''}` : 'none', runtimes)}

			<div class="sp-stack">
			{#snippet folder()}
				<form class="sp-folder" onsubmit={(e) => (e.preventDefault(), useBuildFolder())}>
					<label class="mg-label" for="build-folder">Setup or build folder (margie-build)</label>
					<span class="sp-folder-row">
						<input id="build-folder" class="mg-input mono" bind:value={buildDir} oninput={() => (buildTouched = true)} placeholder="/path/to/margie-build" spellcheck="false" />
						<button type="submit" class="mg-btn" disabled={!buildDir.trim() || buildDir.trim() === o.repo.path || savingBuild}>
							{savingBuild ? 'Checking…' : 'Use'}
						</button>
					</span>
					{#if o.repo.ok}
						<span class="sp-found">
							<span><b>{o.repo.containers.length}</b> container recipes</span>
							<span><b>{o.repo.databases.length}</b> database recipes</span>
						</span>
					{:else}
						<span class="sp-warn">{o.repo.reason}</span>
					{/if}
				</form>
			{/snippet}
			{@render card('Build folder', 'build-recipes', o.repo.ok ? `${o.repo.containers.length} tools, ${o.repo.databases.length} databases` : 'not found', folder)}

			{#snippet python()}
				<div class="sp-py">
					<span class="sp-py-mark">
						{@render badge(o.python.ready ? 'ok' : o.python.base ? 'none' : 'warn')}
						<b>{o.python.ready ? o.python.version : o.python.base ? o.python.base.version : '—'}</b>
					</span>
					<span class="sp-py-text">
						{#if o.python.ready}
							<span class="mg-mono sp-path" title={o.python.path}>{o.python.path}</span>
							<span class="mg-note">Combines, scores and draws the results.</span>
						{:else if o.python.base}
							<span class="mg-mono sp-path" title={o.python.base.path}>{o.python.base.path}</span>
							<span class="mg-note">
								The first run makes its own environment from this Python and installs numpy, pandas, scipy, matplotlib and openpyxl (needs the
								internet once).
							</span>
						{:else}
							<span class="sp-warn">Install Python 3.11 or newer, or set MARGIE_PYTHON to one.</span>
						{/if}
					</span>
				</div>
			{/snippet}
			{@render card('Python', 'python', o.python.ready ? 'ready' : o.python.base ? 'first run sets it up' : 'missing', python)}
			</div>
		</div>

		<!-- ---- row two: tools, reference data ---- -->
		<div class="sp-row two">
			{#snippet buildAll()}
				{#if missing(ws.images) && !runs.containers}
					<button type="button" class="sp-pill" disabled={blocked('containers') || !o?.repo.ok} onclick={() => build('containers')}>Build all missing</button>
				{/if}
			{/snippet}
			{#snippet toolsBar()}
				{#if runs.containers}<BuildBar percent={runs.containers.progress ?? 0} label="Building" text={tally('containers')} />{/if}
			{/snippet}
			{#snippet toolTiles()}{@render tiles(ws.images, 'containers')}{/snippet}
			{@render card('Tools', 'tools', ws.check ? `${ready(ws.images)} of ${ws.images.length} built` : 'checking', toolTiles, buildAll, runs.containers ? toolsBar : undefined)}

			{#snippet downloadAll()}
				{#if missing(ws.databases) && !runs.databases}
					<button type="button" class="sp-pill" disabled={blocked('databases') || !o?.repo.ok} onclick={() => build('databases')}>Download all missing</button>
				{/if}
			{/snippet}
			{#snippet dataBar()}
				{#if runs.databases}<BuildBar percent={runs.databases.progress ?? 0} label="Downloading" text={tally('databases')} />{/if}
			{/snippet}
			{#snippet dataTiles()}{@render tiles(ws.databases, 'databases')}{/snippet}
			{@render card(
				'Reference data',
				'reference-data',
				ws.check ? `${ready(ws.databases)} of ${ws.databases.length} downloaded, about 170 GB in all` : 'checking',
				dataTiles,
				downloadAll,
				runs.databases ? dataBar : undefined
			)}
		</div>
	</div>
{/if}

<style>
	.sp-rows {
		display: flex;
		flex-direction: column;
		gap: var(--cr-gutter, 20px);
	}
	/* Even columns; open cards in a row share a height, folded ones show only the head. */
	.sp-row {
		display: grid;
		gap: var(--cr-gutter, 20px);
		align-items: start;
	}
	.sp-row.two {
		grid-template-columns: repeat(2, minmax(0, 1fr));
	}
	/* Row one: container app beside build folder and Python stacked; folded heads fill their share. */
	.sp-row.first {
		align-items: stretch;
	}
	.sp-stack {
		display: flex;
		flex-direction: column;
		gap: var(--cr-gutter, 20px);
		min-width: 0;
	}
	.sp-stack > :global(.sp-card:last-child) {
		flex: 1;
	}
	.sp-row.first .sp-card.folded .sp-head {
		flex: 1;
	}
	/* Open cards fill the height; container apps share it evenly. */
	.sp-row.first .sp-card > :global(.mo-fold.open) {
		flex: 1;
	}
	.sp-row.first .sp-body,
	.sp-row.first .sp-apps {
		height: 100%;
	}
	.sp-card {
		display: flex;
		flex-direction: column;
		min-width: 0;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow);
		overflow: hidden;
	}
	.sp-head {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 6px 10px;
		min-height: 44px;
		padding: 6px var(--mg-pad);
		border-bottom: 1px solid var(--mg-border);
	}
	.sp-card.folded .sp-head {
		border-bottom-color: transparent;
	}
	.sp-head :global(.mo-fold-title) {
		display: flex;
		align-items: center;
		gap: 9px;
		margin: 0;
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.sp-head :global(.mo-fold-title)::before {
		content: '';
		flex: none;
		width: 8px;
		height: 8px;
		border-radius: 2px;
		background: var(--sh, var(--mg-accent));
	}
	.sp-count {
		font-size: var(--mg-fs-sm);
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-2);
	}
	/* Run bar under the head, shown open or folded. */
	.sp-under {
		padding: 8px var(--mg-pad) 10px;
		border-bottom: 1px solid var(--mg-border);
		background: color-mix(in srgb, var(--mg-accent) 5%, transparent);
	}
	.sp-body {
		padding: var(--mg-pad);
	}

	/* ---- pills, badges ---- */
	.sp-pill {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex: none;
		height: 26px;
		padding: 0 12px;
		border: 1px solid transparent;
		border-radius: var(--mg-r-sm);
		background: var(--mg-accent);
		color: var(--mg-on-accent, #fff);
		font: inherit;
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		white-space: nowrap;
		text-decoration: none;
		cursor: pointer;
	}
	.sp-pill.sm {
		height: 22px;
		padding: 0 9px;
	}
	.sp-pill.ghost {
		border-color: color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-accent) 8%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.sp-pill:disabled {
		opacity: 0.45;
		cursor: not-allowed;
	}
	.sp-flag {
		flex: none;
		padding: 1px 8px;
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
		color: var(--mg-text-3);
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		white-space: nowrap;
	}
	.sp-flag.on {
		background: color-mix(in srgb, var(--mg-ok) 14%, transparent);
		color: var(--mg-ok);
	}
	.sp-badge {
		display: grid;
		place-items: center;
		flex: none;
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: var(--mg-text-3);
		color: #fff;
		font-size: 10px;
		font-weight: 800;
		line-height: 1;
	}
	.sp-badge.ok {
		background: var(--mg-ok);
	}
	.sp-badge.warn {
		background: var(--mg-warn);
	}
	.sp-badge.none {
		background: none;
		border: 2px solid var(--mg-border-strong);
	}
	.sp-warn {
		color: var(--mg-warn);
		font-size: var(--mg-fs-sm);
	}

	/* ---- selection ---- */
	.sp-pickbar {
		display: flex;
		align-items: center;
		gap: 12px;
		margin-bottom: 10px;
		font-size: var(--mg-fs-sm);
	}
	.sp-check {
		display: inline-flex;
		align-items: center;
		gap: 7px;
		cursor: pointer;
	}
	.sp-small {
		font-size: var(--mg-fs-xs);
	}
	.sp-pick:disabled {
		opacity: 0.55;
		cursor: default;
	}
	.sp-check input,
	.sp-pick {
		flex: none;
		width: 15px;
		height: 15px;
		margin: 0;
		accent-color: var(--mg-accent);
		cursor: pointer;
	}

	/* ---- status tiles (tools, reference data) ---- */
	.sp-tiles {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
		gap: 6px;
	}
	.sp-tile {
		display: flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
		min-height: 44px;
		padding: 5px 8px 5px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
	}
	.sp-tile.s-missing,
	.sp-tile.s-warn {
		border-color: color-mix(in srgb, var(--mg-warn) 45%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-warn) 5%, var(--mg-surface));
	}
	.sp-tile.s-unknown,
	.sp-tile.s-optional {
		border-style: dashed;
	}
	.sp-tile.picked {
		border-color: var(--mg-accent);
		background: color-mix(in srgb, var(--mg-accent) 7%, var(--mg-surface));
	}
	.sp-tile.run {
		border-color: color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
	}
	.sp-tile {
		position: relative;
		overflow: hidden;
	}
	/* Current item's progress as a thin bar along the tile's foot. */
	.sp-mini {
		position: absolute;
		left: 0;
		bottom: 0;
		height: 3px;
		background: var(--mg-accent);
		transition: width 600ms cubic-bezier(0.2, 0.7, 0.2, 1);
	}
	.sp-mini.unsure {
		background: linear-gradient(90deg, transparent, var(--mg-accent), transparent);
		background-size: 50% 100%;
		background-repeat: no-repeat;
		animation: sp-slide 1.4s ease-in-out infinite;
	}
	@keyframes sp-slide {
		from {
			background-position: -50% 0;
		}
		to {
			background-position: 150% 0;
		}
	}
	.sp-tile-text {
		display: flex;
		flex-direction: column;
		flex: 1;
		min-width: 0;
	}
	.sp-tile .name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-sm);
		font-weight: 500;
		color: var(--mg-text);
	}
	.sp-state {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-2);
	}
	.s-ok .sp-state,
	.sp-state.ok {
		color: var(--mg-ok);
	}
	.s-missing .sp-state,
	.s-warn .sp-state {
		color: var(--mg-warn);
	}
	.sp-state.go {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.sp-spin {
		flex: none;
		width: 14px;
		height: 14px;
		border-radius: 50%;
		border: 2px solid color-mix(in srgb, var(--mg-accent) 25%, transparent);
		border-top-color: var(--mg-accent);
		animation: sp-spin 900ms linear infinite;
	}
	@keyframes sp-spin {
		to {
			transform: rotate(360deg);
		}
	}

	/* ---- container apps: two by two ---- */
	.sp-apps {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		grid-auto-rows: 1fr;
		gap: 6px;
	}
	.sp-app {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		padding: 8px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		font-size: var(--mg-fs-sm);
	}
	.sp-app.using {
		border-color: color-mix(in srgb, var(--mg-accent) 55%, var(--mg-border));
		box-shadow: inset 3px 0 0 var(--mg-accent);
	}
	.sp-app.off {
		border-style: dashed;
		background: transparent;
	}
	.sp-app.off b {
		color: var(--mg-text-2);
	}
	.sp-app-top {
		display: flex;
		align-items: center;
		gap: 7px;
		min-width: 0;
	}
	.sp-app-top b {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-weight: 500;
	}
	.sp-hint {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
	}
	.sp-app-acts {
		display: flex;
		gap: 6px;
		margin-top: auto;
		padding-top: 4px;
	}

	/* ---- build folder ---- */
	.sp-folder {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.sp-folder-row {
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.sp-folder-row .mg-input {
		flex: 1;
		min-width: 0;
	}
	.sp-found {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 6px;
	}
	.sp-found > span {
		display: flex;
		flex-direction: column;
		padding: 8px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.sp-found b {
		font-size: var(--mg-fs-lg);
		font-weight: 600;
		line-height: 1.2;
		font-variant-numeric: tabular-nums;
		color: var(--mg-text);
	}

	/* ---- python ---- */
	.sp-py {
		display: flex;
		align-items: center;
		gap: 12px;
	}
	.sp-py-mark {
		display: flex;
		align-items: center;
		gap: 8px;
		flex: none;
		padding: 8px 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
	}
	.sp-py-mark b {
		font-size: var(--mg-fs-lg);
		font-weight: 500;
		font-variant-numeric: tabular-nums;
	}
	.sp-py-text {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		font-size: var(--mg-fs-sm);
	}
	.sp-path {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
	}

	:global([data-motion='off']) .sp-rows *,
	:global([data-motion='off']) .sp-card {
		animation: none !important;
		transition: none !important;
	}

	@media (max-width: 800px) {
		.sp-row.two {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	@media (max-width: 520px) {
		.sp-apps {
			grid-template-columns: minmax(0, 1fr);
			grid-auto-rows: auto;
		}
		.sp-tiles {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.sp-py {
			flex-direction: column;
			align-items: flex-start;
		}
	}
</style>
