<script lang="ts">
	import { tick, untrack } from 'svelte';
	import { beforeNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import { Bot, Cpu, Folder, FolderOpen, Folders, HardDrive, Layers, ListChecks, Lock, MemoryStick, RotateCcw, ScrollText, Server, SlidersHorizontal, Wrench } from 'lucide-svelte';
	import { api, formatBytes } from '$lib/api';
	import { LICENCE_LEGAL_NOTICE, LICENCE_STATEMENT, statementMatches } from '$lib/licence';
	import Switch from '$lib/workspace/Switch.svelte';
	import { ws, type Setting } from '$lib/workspace/data.svelte';
	import Fold from '$lib/workspace/motion/Fold.svelte';
	import { ui } from '$lib/workspace/ui.svelte';
	import { CONFIRMED, GUARDED, isConfirmed, isGuarded, unlocks } from '$lib/workspace/guarded';
	import DatabasesPanel from '$lib/workspace/DatabasesPanel.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { uiBase } from '$lib/workspace/base.svelte';
	import { foldDomId } from '$lib/workspace/motion/fold';
	import { rangeOf } from './settingRange';

	/**
	 * Modern's Settings page: cards of sliders, switches and folder fields, with the
	 * same guards, licence form and #KEY anchors other pages link to. One section is
	 * open at a time (the chips at the top or its Show/Hide); edits stay marked
	 * unsaved until that section's Save.
	 */

	/** `closed`: folded until opened, for a group too long to read by default. */
	/** `wide`: a long run of numbers, given the board's full width below the other cards. */
	const GROUPS: { id: string; title: string; icon: typeof Cpu; match: (s: Setting) => boolean; closed?: boolean; wide?: boolean }[] = [
		{ id: 'steps', title: 'Steps', icon: ListChecks, match: (s) => s.group === 'Tools' && s.type === 'flag' },
		// A cluster's: the SLURM account and limits, and its job history.
		{ id: 'cluster', title: 'Cluster', icon: Server, match: (s) => s.group === 'Cluster' },
		{ id: 'runtime', title: 'Running', icon: Cpu, match: (s) => s.group === 'Runtime' },
		{ id: 'folders', title: 'Folders', icon: FolderOpen, match: (s) => s.group === 'Folders' || s.group === 'Setup' },
		{ id: 'tools', title: 'Tool options', icon: Wrench, match: (s) => s.group === 'Tools' && s.type !== 'flag' },
		// A cluster's: resources shared by every tool, per phase, and per tool.
		{ id: 'phases', title: 'Phases', icon: Layers, match: (s) => s.group === 'Phases', wide: true },
		{ id: 'per-tool', title: 'Per tool', icon: SlidersHorizontal, match: (s) => s.group === 'Per tool', closed: true, wide: true },
		// Derived from the folders above; rarely changed.
		{ id: 'other-folders', title: 'Other folders', icon: Folders, match: (s) => s.group === 'Other folders' },
		// The built-in model for Chat with the genome.
		{ id: 'llm', title: 'Built-in model', icon: Bot, match: (s) => s.group === 'LLM' }
	];
	/*
	 * Only what applies where MARGIE runs now. On this computer, the SLURM
	 * account, partition and job sizes (phases, per tool) are the cluster's and
	 * are left out; on a cluster, this computer's own limits (LOCAL_...) are.
	 */
	const CLUSTER_ONLY = new Set(['Cluster', 'Phases', 'Per tool']);
	const applies = (s: Setting) =>
		backend.cluster ? !s.key.startsWith('LOCAL_') : !CLUSTER_ONLY.has(s.group) && !s.key.startsWith('SLURM_') && s.key !== 'PARALLEL_TOOLS';
	const groups = $derived(GROUPS.map((g) => ({ ...g, items: ws.settings.filter((s) => g.match(s) && applies(s)) })).filter((g) => g.items.length));

	/** This computer: what it has, and what MARGIE may use of it. */
	const machine = $derived(backend.cluster ? null : (ws.overview as { machine?: { chip?: string; cores?: number; memory?: number; diskFree?: number; os?: string } } | null)?.machine ?? null);
	/** The folders to jump to (on a cluster: home, scratch and depot among them). */
	let places = $state<{ label: string; path: string }[]>([]);
	$effect(() => {
		void backend.cluster;
		api<{ places: { label: string; path: string }[] }>('/files?places=1')
			.then((d) => (places = d.places.filter((p) => p.path && p.path !== '/')))
			.catch(() => (places = []));
	});
	const changed = $derived(groups.reduce((a, g) => a + g.items.filter((s) => s.overridden).length, 0));

	/**
	 * A group's settings as rows, with runs that share a "Phase: field" label
	 * gathered under the phase (Annotation: nodes, CPUs, memory, time). A
	 * description already shown in the group is not repeated under the next.
	 */
	type Chunk = { head: string | null; cells: boolean; items: { s: Setting; label: string; desc: boolean }[] };
	function chunks(id: string, items: Setting[]): Chunk[] {
		const out: Chunk[] = [];
		const seen = new Set<string>();
		for (const s of items) {
			const at = s.label.indexOf(': ');
			const head = at > 0 ? s.label.slice(0, at) : null;
			const label = head ? s.label.slice(at + 2).replace(/^\w/, (c) => c.toUpperCase()) : s.label;
			const cells = head !== null || id === 'per-tool';
			const last = out.at(-1);
			const item = { s, label, desc: !cells || !seen.has(s.description) };
			if (cells) seen.add(s.description);
			if (last && last.cells && cells && last.head === head) last.items.push(item);
			else out.push({ head, cells, items: [item] });
		}
		return out;
	}

	/**
	 * A wide group as a table: one row per phase (or tool), one column per
	 * field they share (Nodes, CPUs, Memory, Time limit), a gap where a row
	 * lacks one. Settings without a phase are left for the plain rows.
	 */
	type Row = { head: string; note: string; at: Map<string, Chunk['items'][number]> };
	function table(id: string, items: Setting[]) {
		const all = chunks(id, items);
		const rows: Row[] = [];
		const cols: string[] = [];
		for (const c of all) {
			if (!c.cells || !c.head) continue;
			rows.push({ head: c.head, note: c.items[0].s.description, at: new Map(c.items.map((it) => [it.label, it])) });
		}
		// The columns in the order of the fullest row, then any the others add.
		for (const r of [...rows].sort((a, b) => b.at.size - a.at.size)) for (const k of r.at.keys()) if (!cols.includes(k)) cols.push(k);
		return { rows, cols, rest: all.filter((c) => !c.cells || !c.head) };
	}

	/**
	 * The narrow cards dealt into equal columns, as many as the width holds:
	 * each goes, in order, to the column that is shortest so far (by a rough
	 * height from its settings), so the columns end close to level.
	 */
	let boardWidth = $state(0);
	/* One section is open at a time, so the sections stand in one column,
	   each the full width; the open one lays its settings out across it. */
	const ncols = 1;
	const weight = (items: Setting[]) => 1.4 + items.reduce((a, s) => a + (s.type === 'flag' ? 1 : s.type === 'path' ? 1.5 : 1.8), 0);
	type Slot = { g: (typeof groups)[number] | null; k: number };
	const columns = $derived.by(() => {
		const cols: Slot[][] = Array.from({ length: ncols }, () => []);
		const h = cols.map(() => 0);
		const put = (slot: Slot, w: number) => {
			const i = h.indexOf(Math.min(...h));
			cols[i].push(slot);
			h[i] += w;
		};
		groups.filter((g) => !g.wide).forEach((g, k) => put({ g, k }, weight(g.items)));
		if (licenceTools.length) put({ g: null, k: groups.length }, 6 + licenceTools.length * 0.4);
		return cols;
	});

	const budget = $derived(Number(ws.setting('LOCAL_MAX_CORES')) || null);

	// Unlocks last for this visit only, so none stays open on a shared machine.
	let unlocked = $state(false);
	let asking = $state<string | null>(null);
	/** Click-to-unlock settings opened this visit, and the one whose note is showing. */
	let opened = $state<Record<string, boolean>>({});
	let confirming = $state<string | null>(null);
	let phrase = $state('');
	let wrong = $state(false);
	const locked = (s: Setting) => (isConfirmed(s.key) && !opened[s.key]) || (isGuarded(s.key) && !unlocked);

	async function tryUnlock() {
		if (await unlocks(phrase)) {
			unlocked = true;
			asking = null;
			phrase = '';
			wrong = false;
			ui.notify('Unlocked for this visit', 'ok');
		} else {
			wrong = true;
			ui.notify('That is not the phrase', 'error');
		}
	}

	// ------------------------------------------------ one section open at a time
	let openId = $state<string | null>(null);
	const isOpen = (id: string) => openId === id;
	const toggle = (id: string) => (openId = openId === id ? null : id);

	// ------------------------------------------------ edits, saved per section
	/* The values being edited. When the saved settings change, untouched values
	   follow them; edited ones stay as typed until saved or discarded. */
	let draft = $state<Record<string, string>>({});
	let savedAs: Record<string, string> = {};
	$effect(() => {
		const next = Object.fromEntries(ws.settings.map((s) => [s.key, s.value]));
		untrack(() => {
			const d = { ...draft };
			for (const [k, v] of Object.entries(next)) if (!(k in d) || d[k] === savedAs[k]) d[k] = v;
			draft = d;
			savedAs = next;
		});
	});
	const edited = (s: Setting) => String(draft[s.key] ?? s.value) !== s.value;
	const unsaved = (items: Setting[]) => items.filter(edited);
	const anyUnsaved = $derived(ws.settings.some(edited));

	let saving = $state<string | null>(null);
	async function saveGroup(g: { id: string; title: string; items: Setting[] }) {
		const todo = unsaved(g.items);
		if (!todo.length) return;
		saving = g.id;
		const ok = await ws.saveSettings(Object.fromEntries(todo.map((s) => [s.key, String(draft[s.key] ?? '')])));
		saving = null;
		if (ok) ui.notify(`${g.title}: ${todo.length === 1 ? '1 change' : `${todo.length} changes`} saved`, 'ok');
	}
	function discardGroup(g: { items: Setting[] }) {
		for (const s of g.items) draft[s.key] = s.value;
	}

	// Leaving the page with edits not saved asks first.
	beforeNavigate(({ cancel, type }) => {
		if (type !== 'leave' && anyUnsaved && !confirm('Some settings are changed but not saved. Leave without saving them?')) cancel();
	});

	const CHOICE: Record<string, string> = { '1': 'on', '0': 'off' };
	const folderHref = (p: string) => `${uiBase.path}/files?path=${encodeURIComponent(p)}`;

	// ------------------------------------------------ licences
	const licenceTools = $derived(ws.settings.filter((s) => s.key.startsWith('LICENCE_AGREED_')));
	const toolName = (s: Setting) => s.key.slice('LICENCE_AGREED_'.length).toLowerCase();
	const savedUse = $derived(ws.setting('LICENCE_INTENDED_USE'));
	const savedStatement = $derived(statementMatches(ws.setting('LICENCE_STATEMENT')));
	const savedOn = (s: Setting) => s.value === '1' && savedStatement && savedUse.trim() !== '';

	let use = $state('');
	let flags = $state<Record<string, boolean>>({});
	let typed = $state('');
	let savingLic = $state(false);
	$effect(() => {
		use = savedUse;
		flags = Object.fromEntries(licenceTools.map((s) => [s.key, savedOn(s)]));
		typed = '';
	});

	const licChanged = $derived(use.trim() !== savedUse.trim() || licenceTools.some((s) => flags[s.key] !== savedOn(s)));
	const anyOn = $derived(Object.values(flags).some(Boolean));
	/** Accepting a tool, or changing the intended use of accepted ones, needs the statement typed. */
	const needsStatement = $derived(anyOn && (licenceTools.some((s) => flags[s.key] && !savedOn(s)) || use.trim() !== savedUse.trim()));
	const typedOk = $derived(statementMatches(typed));
	const canSave = $derived(licChanged && !savingLic && (!anyOn || use.trim() !== '') && (!needsStatement || typedOk));

	async function saveLicences() {
		savingLic = true;
		const accepted = Object.fromEntries(licenceTools.map((s) => [toolName(s), !!flags[s.key]]));
		const added = await ws.saveLicences(use.trim(), accepted, typed);
		savingLic = false;
		if (added) ui.notify(added.length ? `Accepted: ${added.join(', ')}` : 'Licences saved', 'ok');
	}

	// ------------------------------------------------ going to one setting
	/** Opens the group holding `id` (a setting, a group or "licences"), scrolls to it and lights it up. */
	function reveal(id: string) {
		// A page's own name for a cluster setting (OUTPUT_ROOT) is listed under its real key.
		const alias = ws.settings.find((s) => s.key === id && !s.group);
		const real = alias ? (ws.settings.find((s) => s.group && s.label === alias.label && s.value === alias.value)?.key ?? id) : id;
		const group = real === 'licences' ? 'licences' : (GROUPS.find((g) => g.id === real || ws.settings.some((s) => s.key === real && g.match(s)))?.id ?? '');
		const wasShut = !!group && !isOpen(group);
		if (group) openId = group;
		const ready = wasShut ? new Promise((r) => setTimeout(r, ui.ms(420) + 40)) : tick();
		ready.then(() => {
			const el = document.getElementById(real);
			if (!el) return;
			// A section is brought to the top; one setting to the middle of the window.
			el.scrollIntoView({ block: real === group ? 'start' : 'center', behavior: ui.motion === 'off' ? 'auto' : 'smooth' });
			el.classList.add('flash');
			setTimeout(() => el.classList.remove('flash'), 2500);
		});
	}

	// A link like /crisp/settings#RUN_GTDBTK scrolls to that setting once the settings have loaded.
	let handled = '';
	$effect(() => {
		const id = page.url.hash.slice(1);
		if (!id || id === handled || !ws.settings.length) return;
		handled = id;
		reveal(decodeURIComponent(id));
	});
</script>

{#snippet control(s: Setting)}
	{@const r = rangeOf(s, budget)}
	{#if isConfirmed(s.key) && !opened[s.key]}
		{#if confirming === s.key}
			<div class="sb-confirm">
				<span class="mg-note">{CONFIRMED[s.key].why}</span>
				<span class="sb-btns">
					<button
						type="button"
						class="mg-link quiet"
						onclick={() => {
							opened = { ...opened, [s.key]: true };
							confirming = null;
						}}>Unlock</button
					>
					<button type="button" class="mg-link quiet" onclick={() => (confirming = null)}>Cancel</button>
				</span>
			</div>
		{:else}
			<span class="sb-locked">
				<Lock size={13} aria-hidden="true" />
				<span class="mg-mono" title={s.value || s.default}>{s.value || s.default || 'Not set'}</span>
			</span>
			<button type="button" class="mg-link quiet" title={CONFIRMED[s.key].title} onclick={() => (confirming = s.key)}>Unlock</button>
		{/if}
	{:else if isGuarded(s.key) && !unlocked}
		<!-- Shown, never hidden: only changing it by accident needs guarding. -->
		{#if asking === s.key}
			<form
				class="sb-unlock"
				onsubmit={(e) => {
					e.preventDefault();
					tryUnlock();
				}}
			>
				<input
					class="mg-input"
					type="password"
					bind:value={phrase}
					placeholder="Phrase"
					aria-label={GUARDED[s.key].title}
					aria-invalid={wrong || undefined}
					spellcheck="false"
				/>
				<button type="submit" class="mg-link quiet" disabled={!phrase.trim()}>OK</button>
				<button
					type="button"
					class="mg-link quiet"
					onclick={() => {
						asking = null;
						phrase = '';
						wrong = false;
					}}>Cancel</button
				>
			</form>
		{:else}
			<span class="sb-locked">
				<Lock size={13} aria-hidden="true" />
				<span class="mg-mono" title={s.value}>{s.value || 'Not set'}</span>
			</span>
			<button type="button" class="mg-link quiet" title={GUARDED[s.key].why} onclick={() => (asking = s.key)}>Unlock</button>
		{/if}
	{:else if s.type === 'flag'}
		<Switch label={s.label} checked={draft[s.key] === '1'} onchange={(on) => (draft[s.key] = on ? '1' : '0')} />
	{:else if s.type === 'choice' && (s.choices?.length ?? 0) <= 5}
		<div class="sb-seg" role="radiogroup" aria-label={s.label}>
			{#each s.choices ?? [] as c (c)}
				<button
					type="button"
					role="radio"
					aria-checked={draft[s.key] === c}
					onclick={() => (draft[s.key] = c)}>{CHOICE[c] ?? c}</button
				>
			{/each}
		</div>
	{:else if s.type === 'choice'}
		<select class="mg-select" aria-label={s.label} bind:value={draft[s.key]}>
			{#each s.choices ?? [] as c (c)}<option value={c}>{c}</option>{/each}
		</select>
	{:else if r}
		{@const n = Math.min(r.max, Math.max(r.min, r.read(String(draft[s.key] ?? '')) ?? r.read(s.default) ?? r.min))}
		<div class="sb-slide">
			<input
				type="range"
				class="sb-range"
				min={r.min}
				max={r.max}
				step={r.step}
				value={n}
				style="--p: {((n - r.min) / Math.max(1, r.max - r.min)) * 100}%"
				aria-label={s.label}
				oninput={(e) => (draft[s.key] = r.write(Number(e.currentTarget.value)))}
			/>
			<span class="sb-num">
				<input
					class="mg-input"
					type={s.type === 'int' ? 'number' : 'text'}
					min={s.type === 'int' ? 1 : undefined}
					aria-label="{s.label}, exact"
					placeholder={s.default}
					spellcheck="false"
					bind:value={draft[s.key]}
					onkeydown={(e) => e.key === 'Enter' && e.currentTarget.blur()}
				/>
				{#if s.type === 'int' && r.unit}<span class="sb-unit">{r.unit}</span>{/if}
			</span>
		</div>
	{:else if s.type === 'path'}
		{@const p = String(draft[s.key] || s.default || '')}
		<div class="sb-path">
			{#if p.startsWith('/')}
				<a class="sb-folder" href={folderHref(p)} title="Open {p} in Files"><Folder size={15} /></a>
			{:else}
				<span class="sb-folder" aria-hidden="true"><Folder size={15} /></span>
			{/if}
			<input
				class="mg-input mg-mono"
				aria-label={s.label}
				placeholder={s.default}
				spellcheck="false"
				bind:value={draft[s.key]}
				onkeydown={(e) => e.key === 'Enter' && e.currentTarget.blur()}
			/>
		</div>
	{:else}
		<input
			class="mg-input sb-text-in"
			class:sb-short={s.type === 'int'}
			type={s.type === 'int' ? 'number' : 'text'}
			min={s.type === 'int' ? 1 : undefined}
			aria-label={s.label}
			placeholder={s.default}
			spellcheck="false"
			bind:value={draft[s.key]}
			onkeydown={(e) => e.key === 'Enter' && e.currentTarget.blur()}
		/>
	{/if}
{/snippet}

{#snippet reset(s: Setting)}
	{#if String(draft[s.key] ?? s.value) !== s.default && s.type !== 'flag' && !locked(s)}
		<button type="button" class="sb-reset" title="Back to the default{s.default ? `: ${s.default}` : ''} (saved with the section)" onclick={() => (draft[s.key] = s.default)}>
			<RotateCcw size={12} aria-hidden="true" />Reset
		</button>
	{/if}
{/snippet}

{#snippet dot(s: Setting)}
	{#if edited(s)}<span class="sb-dot sb-unsaved" title="Changed, not saved yet"></span>
	{:else if s.overridden}<span class="sb-dot" title="Changed from the default"></span>{/if}
{/snippet}

{#snippet card(g: (typeof groups)[number], k: number)}
	{@const pending = unsaved(g.items).length}
	<section class="sb-card" id={g.id} data-shade={g.id} class:sb-shut={!isOpen(g.id)} style="--i: {k}">
		<header class="sb-head">
			<span class="sb-ico" aria-hidden="true"><g.icon size={16} /></span>
			<button type="button" class="sb-title" aria-expanded={isOpen(g.id)} aria-controls={foldDomId(`settings:${g.id}`)} onclick={() => toggle(g.id)}>{g.title}</button>
			<span class="sb-count">{g.items.length} setting{g.items.length === 1 ? '' : 's'}</span>
			{#if pending}<span class="sb-pending">{pending} unsaved</span>{/if}
			<span class="mg-grow"></span>
			<button type="button" class="mg-link quiet" aria-expanded={isOpen(g.id)} onclick={() => toggle(g.id)}>{isOpen(g.id) ? 'Hide' : 'Show'}</button>
		</header>
		<Fold id="settings:{g.id}" open={isOpen(g.id)}>
			{@const t = g.wide ? table(g.id, g.items) : null}
			{#if t && t.rows.length}
				{#if t.cols.length > 1}
					<div class="sb-table" role="table" aria-label={g.title} style="--cols: {t.cols.length}">
						<div class="sb-tr sb-thead" role="row">
							<span class="sb-th" role="columnheader">{g.id === 'per-tool' ? 'Tool' : 'Phase'}</span>
							{#each t.cols as col (col)}<span class="sb-th" role="columnheader">{col}</span>{/each}
						</div>
						{#each t.rows as row (row.head)}
							<div class="sb-tr" role="row">
								<div class="sb-rh" role="rowheader">
									<b>{row.head}</b>
									{#if row.note}<span class="sb-desc">{row.note}</span>{/if}
								</div>
								{#each t.cols as col (col)}
									{@const it = row.at.get(col)}
									{#if it}
										<div class="sb-td" role="cell" id={it.s.key} title={it.s.description}>
											<span class="sb-td-lbl"><span class="sb-td-name">{col}</span>{@render dot(it.s)}</span>
											<div class="sb-field">{@render control(it.s)}</div>
											{@render reset(it.s)}
										</div>
									{:else}
										<div class="sb-td sb-none" role="cell" aria-label="{col}: not used by {row.head}"><span aria-hidden="true">—</span></div>
									{/if}
								{/each}
							</div>
						{/each}
					</div>
				{:else}
					<ul class="sb-tiles">
						{#each t.rows as row (row.head)}
							{#each [...row.at.values()] as { s, label } (s.key)}
								<li class="sb-cell" id={s.key}>
									<div class="sb-cell-top">
										<span class="sb-tile-name">{row.head}</span>
										<span class="sb-lbl">{label}</span>{@render dot(s)}
										<span class="mg-grow"></span>
										{@render reset(s)}
									</div>
									<div class="sb-field">{@render control(s)}</div>
									{#if s.description}<span class="sb-desc">{s.description}</span>{/if}
								</li>
							{/each}
						{/each}
					</ul>
				{/if}
			{/if}
			<ul class="sb-list" class:sb-empty={t && !t.rest.length}>
				{#each t ? t.rest : chunks(g.id, g.items) as c, j (c.items[0].s.key + j)}
					{#if c.cells}
						<li class="sb-sub">
							{#if c.head}<h3 class="sb-subhead">{c.head}</h3>{/if}
							<ul class="sb-cells">
								{#each c.items as { s, label, desc } (s.key)}
									<li class="sb-cell" id={s.key} title={desc ? undefined : s.description}>
										<div class="sb-cell-top">
											<span class="sb-lbl">{label}</span>{@render dot(s)}
											<span class="mg-grow"></span>
											{@render reset(s)}
										</div>
										<div class="sb-field">{@render control(s)}</div>
										{#if desc && s.description}<span class="sb-desc">{s.description}</span>{/if}
									</li>
								{/each}
							</ul>
						</li>
					{:else}
						{#each c.items as { s } (s.key)}
							<li class="sb-row" class:sb-flag={s.type === 'flag' && !locked(s)} id={s.key}>
								<div class="sb-txt">
									<span class="sb-lbl">{s.label}{@render dot(s)}</span>
									{#if s.description}<span class="sb-desc">{s.description}</span>{/if}
								</div>
								{#if s.type === 'flag' && !locked(s)}
									{@render control(s)}
								{:else}
									<div class="sb-ctl">
										<div class="sb-field">{@render control(s)}</div>
										{@render reset(s)}
									</div>
								{/if}
							</li>
						{/each}
					{/if}
				{/each}
			</ul>
			<footer class="sb-save">
				<span class="sb-desc">{pending ? `${pending === 1 ? '1 change' : `${pending} changes`} not saved yet` : 'Changes here are kept once you save them.'}</span>
				<span class="mg-grow"></span>
				<button type="button" class="mg-btn small" disabled={!pending || saving === g.id} onclick={() => discardGroup(g)}>Discard</button>
				<button type="button" class="mg-btn small primary" disabled={!pending || saving === g.id} onclick={() => saveGroup(g)}>
					{saving === g.id ? 'Saving…' : 'Save'}
				</button>
			</footer>
		</Fold>
	</section>
{/snippet}

<div class="sb">
	<nav class="sb-nav" aria-label="Settings groups">
		{#each groups as g (g.id)}
			<button type="button" class="sb-chip" aria-pressed={isOpen(g.id)} onclick={() => reveal(g.id)}>
				<g.icon size={13} aria-hidden="true" />{g.title}<span class="sb-n">{g.items.length}</span>
				{#if unsaved(g.items).length}<span class="sb-dot sb-unsaved" title="Unsaved changes"></span>{/if}
			</button>
		{/each}
		{#if licenceTools.length}
			<button type="button" class="sb-chip" aria-pressed={isOpen('licences')} onclick={() => reveal('licences')}>
				<ScrollText size={13} aria-hidden="true" />Licences<span class="sb-n">{licenceTools.filter(savedOn).length}/{licenceTools.length}</span>
			</button>
		{/if}
		<span class="mg-grow"></span>
		<span class="sb-changed" title={changed ? `${changed} changed from the default` : 'Every setting is at its default'}>
			{#if changed}<span class="sb-dot" aria-hidden="true"></span>{changed} changed{:else}All defaults{/if}
		</span>
	</nav>

	<!-- where MARGIE runs: this computer's resources, and the folders to jump to -->
	<div class="sb-here">
		{#if machine}
			<div class="sb-machine" aria-label="This computer">
				<span class="sb-here-t">This computer</span>
				{#if machine.chip}<span class="sb-fact"><Cpu size={14} />{machine.chip}</span>{/if}
				{#if machine.cores}<span class="sb-fact"><b>{machine.cores}</b> cores{budget ? ` | MARGIE may use ${budget}` : ''}</span>{/if}
				{#if machine.memory}<span class="sb-fact"><MemoryStick size={14} /><b>{formatBytes(machine.memory)}</b> memory{ws.setting('LOCAL_MAX_MEMORY_GB') ? ` | MARGIE may use ${ws.setting('LOCAL_MAX_MEMORY_GB')} GB` : ''}</span>{/if}
				{#if machine.diskFree}<span class="sb-fact"><HardDrive size={14} /><b>{formatBytes(machine.diskFree)}</b> free on the databases disk</span>{/if}
			</div>
		{:else if backend.cluster}
			<div class="sb-machine"><span class="sb-here-t">On the HPC{backend.host ? `, ${backend.host}` : ''}</span><span class="sb-fact">Resources are set per job below (SLURM).</span></div>
		{/if}
		{#if places.length}
			<div class="sb-places" aria-label="Folders">
				<span class="sb-here-t">{backend.cluster ? 'Your folders on the cluster' : 'Folders'}</span>
				{#each places as p (p.path)}
					<a class="sb-place" href={folderHref(p.path)} title="Open {p.path} in Files"><Folder size={13} />{p.label}</a>
				{/each}
				<span class="sb-desc">Change where these point under Folders.</span>
			</div>
		{/if}
	</div>

	{#if backend.cluster}<div class="sb-db"><DatabasesPanel /></div>{/if}

	{#snippet licences()}
			<section class="sb-card" id="licences" data-shade="licences" class:sb-shut={!isOpen('licences')} style="--i: {groups.length}">
				<header class="sb-head">
					<span class="sb-ico" aria-hidden="true"><ScrollText size={16} /></span>
					<button type="button" class="sb-title" aria-expanded={isOpen('licences')} aria-controls={foldDomId('settings:licences')} onclick={() => toggle('licences')}>Licences</button>
					<span class="sb-count">{licenceTools.filter(savedOn).length} of {licenceTools.length} accepted</span>
					{#if licChanged}<span class="sb-pending">unsaved</span>{/if}
					<span class="mg-grow"></span>
					<button type="button" class="mg-link quiet" aria-expanded={isOpen('licences')} onclick={() => toggle('licences')}>{isOpen('licences') ? 'Hide' : 'Show'}</button>
				</header>
				<Fold id="settings:licences" open={isOpen('licences')}>
					<div class="sb-lic">
						<p class="sb-desc">
							These tools carry academic or non-commercial terms, and stay off until you accept them. Read each tool's terms in
							<a class="mg-link" href="https://github.com/sajalbhattarai/margie-pipeline#8-licence-compliance" target="_blank" rel="noreferrer">README §8</a>
							first.
						</p>

						<label class="sb-use">
							<span class="sb-lbl">Intended use</span>
							<input class="mg-input" bind:value={use} placeholder="e.g. academic research at your institution" />
						</label>

						<ul class="sb-tools">
							{#each licenceTools as s (s.key)}
								<li class:on={!!flags[s.key]}>
									<span class="mg-mono">{toolName(s)}</span>
									<span class="mg-grow"></span>
									<Switch label="Accept the {toolName(s)} licence" checked={!!flags[s.key]} onchange={(on) => (flags[s.key] = on)} />
								</li>
							{/each}
						</ul>

						{#if needsStatement}
							<div class="sb-agree">
								<p class="sb-legal">{LICENCE_LEGAL_NOTICE}</p>
								<label for="licence-statement" class="sb-lbl">Type this statement to accept</label>
								<p class="sb-statement">{LICENCE_STATEMENT}</p>
								<textarea
									id="licence-statement"
									class="mg-input"
									rows="2"
									spellcheck="false"
									autocomplete="off"
									bind:value={typed}
									onpaste={(e) => e.preventDefault()}
								></textarea>
								<span class="sb-desc" class:sb-match={typedOk}
									>{typed ? (typedOk ? 'Matches' : 'Keep typing: it must match the statement above.') : 'Pasting is turned off.'}</span
								>
							</div>
						{/if}

						<div class="sb-end">
							{#if anyOn && !use.trim()}<span class="sb-desc">Describe your intended use first.</span>{/if}
							<button type="button" class="mg-btn small primary" disabled={!canSave} onclick={saveLicences}>
								{needsStatement ? 'Accept and save' : 'Save'}
							</button>
						</div>
					</div>
				</Fold>
			</section>
	{/snippet}

	<div class="sb-cols" bind:clientWidth={boardWidth} style="--n: {ncols}">
		{#each columns as col, ci (ci)}
			<div class="sb-col">
				{#each col as slot (slot.g?.id ?? 'licences')}
					{#if slot.g}{@render card(slot.g, slot.k)}{:else}{@render licences()}{/if}
				{/each}
			</div>
		{/each}
	</div>

	{#each groups.filter((g) => g.wide) as g, k (g.id)}{@render card(g, k + groups.length)}{/each}
</div>

<style>
	.sb {
		display: flex;
		flex-direction: column;
		gap: var(--mg-pad);
		padding: calc(var(--mg-pad) * 1.1);
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		color: var(--mg-text);
		background: var(--mg-surface);
		box-shadow: none;
	}

	/* ---- the chips along the top ---- */
	/* The chips share the width evenly, the tally of changes as the last one. */
	/* Where MARGIE runs: one line of this computer's resources, one of folders to jump to. */
	.sb-here {
		display: flex;
		flex-direction: column;
		gap: 8px;
		margin-bottom: 12px;
		padding: 10px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface));
		font-size: var(--mg-fs-sm);
	}
	.sb-here:empty {
		display: none;
	}
	.sb-machine,
	.sb-places {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 6px 16px;
	}
	.sb-here-t {
		font-size: var(--mg-fs-xs);
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.sb-fact {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--mg-text-2);
	}
	.sb-fact b {
		font-weight: 500;
		color: var(--mg-text);
	}
	.sb-place {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		padding: 3px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		color: var(--mg-accent-ink, var(--mg-accent));
		text-decoration: none;
	}
	.sb-place:hover {
		border-color: var(--mg-accent);
	}
	.sb-nav {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(118px, 1fr));
		align-items: center;
		gap: 8px;
	}
	.sb-nav > .mg-grow {
		display: none;
	}
	.sb-chip {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 7px;
		min-width: 0;
		white-space: nowrap;
		height: 30px;
		padding: 0 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-sm);
		cursor: pointer;
		transition:
			border-color 160ms,
			color 160ms,
			transform 160ms;
	}
	.sb-chip[aria-pressed='true'] {
		border-color: var(--mg-accent);
		background: color-mix(in srgb, var(--mg-accent) 10%, var(--mg-surface));
		color: var(--mg-accent-ink, var(--mg-accent));
		font-weight: 600;
	}
	.sb-chip:hover {
		border-color: color-mix(in srgb, var(--mg-accent) 60%, var(--mg-border));
		color: var(--mg-text);
	}
	.sb-chip :global(svg) {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.sb-n {
		font-size: var(--mg-fs-xs);
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-3);
	}
	.sb-changed {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 7px;
		height: 30px;
		padding: 0 12px;
		border: 1px dashed var(--mg-border-strong);
		border-radius: var(--mg-r-sm);
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-2);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.sb-dot {
		display: inline-block;
		flex: none;
		width: 7px;
		height: 7px;
		margin-left: 7px;
		border-radius: 50%;
		background: var(--mg-accent);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--mg-accent) 22%, transparent);
		vertical-align: middle;
	}
	.sb-dot.sb-unsaved {
		background: var(--mg-warn);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--mg-warn) 22%, transparent);
	}
	.sb-pending {
		padding: 1px 8px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-warn) 16%, transparent);
		color: var(--mg-warn);
		font-size: var(--mg-fs-xs);
		font-weight: 600;
	}
	/* Each section's own Save, at its foot. */
	.sb-save {
		display: flex;
		align-items: center;
		gap: 10px;
		margin-top: 6px;
		padding: 10px var(--mg-pad) 12px;
		border-top: 1px solid var(--mg-border);
	}
	/* The open section uses the width: its settings in two columns. */
	@media (min-width: 1000px) {
		.sb-card:not(.sb-shut) .sb-list:not(.sb-empty) {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			column-gap: calc(var(--mg-pad) * 2);
		}
	}
	.sb-changed .sb-dot {
		margin-left: 0;
	}

	/* ---- the cards, in as many columns as fit ---- */
	/* Equal columns; the last card of each stretches so their feet line up. */
	.sb-cols {
		display: grid;
		grid-template-columns: repeat(var(--n, 1), minmax(0, 1fr));
		gap: var(--mg-pad);
		align-items: stretch;
	}
	.sb-col {
		display: flex;
		flex-direction: column;
		gap: var(--mg-pad);
		min-width: 0;
	}
	.sb-col > .sb-card:last-child:not(.sb-shut) {
		flex: 1;
	}
	.sb-card {
		display: flex;
		flex-direction: column;
		min-width: 0;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: color-mix(in srgb, var(--mg-surface-2) 70%, transparent);
		transition:
			border-color 200ms,
			box-shadow 600ms;
	}
	.sb-card:global(.flash) {
		border-color: var(--mg-accent);
		box-shadow: 0 0 0 1px var(--mg-accent), 0 8px 26px color-mix(in srgb, var(--mg-accent) 20%, transparent);
	}
	.sb-head {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 12px var(--mg-pad);
	}
	.sb-ico {
		display: grid;
		place-items: center;
		width: 30px;
		height: 30px;
		flex: none;
		border-radius: 9px;
		background: color-mix(in srgb, var(--mg-accent) 16%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.sb-head .sb-title {
		padding: 0;
		border: none;
		background: none;
		color: var(--mg-text);
		font: inherit;
		cursor: pointer;
		margin: 0;
		font-size: var(--mg-fs-lg);
		font-weight: 650;
		line-height: 1.2;
	}
	.sb-count {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.sb-list {
		display: flex;
		flex-direction: column;
		padding: 0 0 6px;
	}
	.sb-list > li {
		border-top: 1px solid var(--mg-border);
	}

	/* ---- one setting to a row ---- */
	.sb-row {
		display: flex;
		flex-direction: column;
		gap: 9px;
		padding: 12px var(--mg-pad);
		transition: background-color 1200ms ease;
	}
	.sb-row.sb-flag {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		align-items: center;
		gap: 16px;
	}
	.sb-row:global(.flash),
	.sb-cell:global(.flash) {
		background: color-mix(in srgb, var(--mg-accent) 14%, transparent);
		transition: none;
	}
	.sb-txt {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.sb-lbl {
		font-size: var(--mg-fs);
		font-weight: 600;
	}
	.sb-desc {
		max-width: 64ch;
		font-size: var(--mg-fs-xs);
		line-height: 1.45;
		color: var(--mg-text-3);
	}
	.sb-ctl {
		display: flex;
		align-items: center;
		gap: 12px;
		min-width: 0;
	}
	.sb-field {
		display: flex;
		align-items: center;
		gap: 10px;
		flex: 1 1 auto;
		min-width: 0;
	}
	.sb-reset {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		flex: none;
		padding: 2px 8px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-xs);
		cursor: pointer;
		transition:
			border-color 160ms,
			color 160ms;
	}
	.sb-reset:hover {
		border-color: var(--mg-accent);
		color: var(--mg-text);
	}
	.sb-reset:hover :global(svg) {
		transform: rotate(-120deg);
	}
	.sb-reset :global(svg) {
		transition: transform 300ms ease;
	}

	/* ---- a phase's settings, side by side ---- */
	.sb-sub {
		padding: 12px var(--mg-pad) 14px;
	}
	.sb-subhead {
		margin: 0 0 8px;
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.sb-cells {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
		gap: 10px;
	}
	.sb-cell {
		display: flex;
		flex-direction: column;
		gap: 6px;
		min-width: 0;
		padding: 10px 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-surface) 60%, transparent);
		transition: background-color 1200ms ease;
	}
	.sb-cell-top {
		display: flex;
		align-items: center;
		gap: 6px;
		min-height: 22px;
	}
	.sb-cell .sb-lbl {
		font-size: var(--mg-fs-sm);
	}
	.sb-cell .sb-dot {
		margin-left: 0;
	}

	/* ---- controls ---- */
	.sb-slide {
		display: flex;
		align-items: center;
		gap: 12px;
		width: 100%;
		min-width: 0;
	}
	.sb-cell .sb-slide {
		flex-wrap: wrap;
		gap: 6px 10px;
	}
	.sb-cell .sb-range {
		flex-basis: 100%;
	}
	.sb-range {
		flex: 1 1 auto;
		min-width: 80px;
		height: 22px;
		margin: 0;
		background: none;
		cursor: pointer;
		appearance: none;
		-webkit-appearance: none;
	}
	.sb-range::-webkit-slider-runnable-track {
		height: 6px;
		border-radius: 3px;
		background: linear-gradient(to right, var(--mg-accent) var(--p), var(--mg-border-strong) var(--p));
	}
	.sb-range::-moz-range-track {
		height: 6px;
		border-radius: 3px;
		background: linear-gradient(to right, var(--mg-accent) var(--p), var(--mg-border-strong) var(--p));
	}
	.sb-range::-webkit-slider-thumb {
		-webkit-appearance: none;
		width: 18px;
		height: 18px;
		margin-top: -6px;
		border: 3px solid var(--mg-accent);
		border-radius: 50%;
		background: #fff;
		box-shadow: none;
		transition: transform 160ms;
	}
	.sb-range::-moz-range-thumb {
		width: 12px;
		height: 12px;
		border: 3px solid var(--mg-accent);
		border-radius: 50%;
		background: #fff;
	}
	.sb-range:hover::-webkit-slider-thumb {
		transform: scale(1.12);
	}
	.sb-range:active::-webkit-slider-thumb {
		transform: scale(1.22);
	}
	.sb-range:focus-visible {
		outline: 2px solid var(--mg-accent);
		outline-offset: 3px;
		border-radius: 4px;
	}
	.sb-num {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		flex: none;
	}
	.sb-num input {
		width: 92px;
		font-variant-numeric: tabular-nums;
	}
	.sb-cell .sb-num input {
		width: 84px;
	}
	.sb-unit {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.sb-short {
		width: 92px;
	}
	.sb-text-in:not(.sb-short) {
		width: 100%;
	}
	.sb-cell .sb-text-in {
		width: 100%;
	}
	.sb-path {
		position: relative;
		display: flex;
		align-items: center;
		width: 100%;
		min-width: 0;
	}
	.sb-folder {
		position: absolute;
		left: 1px;
		top: 1px;
		bottom: 1px;
		z-index: 1;
		display: grid;
		place-items: center;
		width: 34px;
		border-radius: var(--mg-r-sm) 0 0 var(--mg-r-sm);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	a.sb-folder:hover {
		background: color-mix(in srgb, var(--mg-accent) 14%, transparent);
	}
	.sb-path input {
		width: 100%;
		min-width: 0;
		padding-left: 38px;
		font-size: var(--mg-fs-xs);
	}
	.sb-seg {
		display: inline-flex;
		flex-wrap: wrap;
		gap: 3px;
		padding: 3px;
		border: 1px solid var(--mg-border);
		border-radius: 16px;
		background: var(--mg-surface);
	}
	.sb-seg button {
		height: 26px;
		padding: 0 12px;
		border: none;
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-sm);
		cursor: pointer;
		transition:
			background-color 180ms,
			color 180ms;
	}
	.sb-seg button:hover {
		color: var(--mg-text);
	}
	.sb-seg button[aria-checked='true'] {
		background: var(--mg-accent);
		color: var(--mg-on-accent, #fff);
		font-weight: 600;
	}
	.sb-field :global(.mg-select) {
		width: min(100%, 24em);
	}
	.sb-locked {
		display: inline-flex;
		align-items: center;
		gap: 7px;
		flex: 1 1 auto;
		min-width: 0;
		height: var(--mg-ctl-sm, 32px);
		padding: 0 10px;
		border: 1px dashed var(--mg-border-strong);
		border-radius: var(--mg-r-sm);
		color: var(--mg-text-2);
		font-size: var(--mg-fs-xs);
	}
	.sb-locked :global(svg) {
		flex: none;
		color: var(--mg-warn);
	}
	.sb-locked .mg-mono {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.sb-unlock {
		display: flex;
		align-items: center;
		gap: 8px;
		width: 100%;
		min-width: 0;
	}
	.sb-unlock .mg-input {
		flex: 1 1 auto;
		min-width: 0;
	}
	.sb-confirm {
		display: flex;
		flex-direction: column;
		gap: 6px;
		min-width: 0;
	}
	.sb-btns {
		display: flex;
		gap: 14px;
	}

	/* ---- a wide group as a table: phases down, fields across ---- */
	.sb-empty {
		display: none;
	}
	.sb-table {
		display: grid;
		grid-template-columns: minmax(12em, 1.15fr) repeat(var(--cols), minmax(0, 1fr));
		border-top: 1px solid var(--mg-border);
	}
	.sb-tr {
		display: contents;
	}
	.sb-th {
		padding: 9px 16px;
		border-bottom: 1px solid var(--mg-border-strong);
		background: color-mix(in srgb, var(--mg-surface) 70%, transparent);
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.sb-rh,
	.sb-td {
		min-width: 0;
		padding: 12px 16px;
		border-bottom: 1px solid var(--mg-border);
		transition: background-color 1200ms ease;
	}
	.sb-tr:last-child > * {
		border-bottom: 0;
	}
	.sb-td,
	.sb-th + .sb-th {
		border-left: 1px solid var(--mg-border);
	}
	.sb-tr:nth-child(odd) > :is(.sb-rh, .sb-td) {
		background: color-mix(in srgb, var(--mg-surface) 45%, transparent);
	}
	.sb-rh {
		display: flex;
		flex-direction: column;
		gap: 3px;
	}
	.sb-rh b {
		font-size: var(--mg-fs-sm);
		font-weight: 650;
	}
	.sb-td {
		position: relative;
		display: flex;
		flex-direction: column;
		justify-content: center;
		gap: 6px;
	}
	.sb-td:global(.flash) {
		background: color-mix(in srgb, var(--mg-accent) 14%, transparent) !important;
		transition: none;
	}
	.sb-td-lbl {
		position: absolute;
		top: 8px;
		right: 10px;
		display: flex;
		align-items: center;
	}
	.sb-td-name {
		display: none;
	}
	.sb-td .sb-slide {
		flex-wrap: wrap;
		gap: 6px 10px;
	}
	.sb-td .sb-range {
		flex-basis: 100%;
	}
	.sb-td .sb-num input {
		width: 96px;
	}
	.sb-td .sb-reset {
		align-self: flex-start;
	}
	.sb-none {
		align-items: center;
		color: var(--mg-text-3);
	}

	/* ---- a wide group of one field each: even tiles ---- */
	.sb-tiles {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
		gap: 10px;
		padding: 14px var(--mg-pad) var(--mg-pad);
		border-top: 1px solid var(--mg-border);
	}
	.sb-tile-name {
		font-size: var(--mg-fs-xs);
		font-weight: 650;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.sb-tiles .sb-lbl {
		font-weight: 500;
		color: var(--mg-text-2);
	}
	.sb-tiles .sb-slide {
		flex-wrap: nowrap;
	}
	.sb-tiles .sb-range {
		flex-basis: auto;
	}

	/* ---- licences ---- */
	.sb-lic {
		display: flex;
		flex-direction: column;
		gap: 16px;
		padding: 14px var(--mg-pad) var(--mg-pad);
		border-top: 1px solid var(--mg-border);
	}
	.sb-use {
		display: flex;
		flex-direction: column;
		gap: 6px;
		max-width: 520px;
	}
	.sb-tools {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
		gap: 8px;
	}
	.sb-tools li {
		display: flex;
		align-items: center;
		gap: 8px;
		min-height: 36px;
		padding: 0 10px 0 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		font-size: var(--mg-fs-sm);
		transition: border-color 200ms;
	}
	.sb-tools li.on {
		border-color: color-mix(in srgb, var(--mg-ok) 55%, var(--mg-border));
	}
	.sb-agree {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 14px 16px;
		border: 1px solid var(--mg-border-strong);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
	}
	.sb-legal {
		font-size: var(--mg-fs-sm);
		font-weight: 600;
	}
	.sb-statement {
		font-size: var(--mg-fs-sm);
		font-style: italic;
		color: var(--mg-text-2);
	}
	.sb-agree textarea {
		width: 100%;
	}
	.sb-match {
		color: var(--mg-ok);
	}
	.sb-end {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		gap: 16px;
	}

	/* Full width, a phase's name sits to the left of its settings. */
	@media (min-width: 1000px) {
		.sb > .sb-card .sb-sub {
			display: grid;
			grid-template-columns: 11em minmax(0, 1fr);
			gap: 16px;
		}
		.sb > .sb-card .sb-subhead {
			margin: 10px 0 0;
		}
	}

	:global([data-motion='off']) .sb * {
		animation: none !important;
		transition: none !important;
	}

	@media (max-width: 760px) {
		.sb-table {
			display: flex;
			flex-direction: column;
		}
		.sb-thead {
			display: none;
		}
		.sb-tr {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			border-bottom: 1px solid var(--mg-border);
		}
		.sb-tr > :is(.sb-rh, .sb-td) {
			border-bottom: 0;
		}
		.sb-rh {
			grid-column: 1 / -1;
			padding-bottom: 4px;
		}
		.sb-td {
			border-left: 0;
			justify-content: flex-start;
		}
		.sb-td-lbl {
			position: static;
			gap: 6px;
		}
		.sb-td-name {
			display: inline;
			font-size: var(--mg-fs-xs);
			font-weight: 600;
			color: var(--mg-text-2);
		}
		.sb-none {
			display: none;
		}
	}
	@media (max-width: 600px) {
		.sb {
			padding: 10px;
		}
		.sb-nav {
			display: flex;
			flex-wrap: wrap;
		}
		.sb-chip {
			flex: 1 1 auto;
		}
		.sb-changed {
			flex: 1 1 100%;
		}
		.sb-head,
		.sb-row,
		.sb-sub {
			padding-left: 12px;
			padding-right: 12px;
		}
		.sb-slide {
			flex-wrap: wrap;
			gap: 6px 10px;
		}
		.sb-range {
			flex-basis: 100%;
		}
	}
</style>
