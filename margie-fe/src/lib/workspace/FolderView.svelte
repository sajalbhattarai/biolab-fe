<script lang="ts" module>
	export interface FolderRoot {
		label: string;
		path: string;
	}
</script>

<script lang="ts">
	import './viewers/tools.css';
	import { uiBase } from './base.svelte';
	import { untrack } from 'svelte';
	import { ArrowUp, ChevronLeft, ChevronRight, CornerDownLeft, Download, File, FileArchive, FileCode, FileImage, FileSpreadsheet, FileText, Folder, FolderOpen, RefreshCw } from 'lucide-svelte';
	import { ApiError, api, fileUrl, formatBytes } from '$lib/api';
	import { ws } from './data.svelte';
	import { ago } from './format';

	/**
	 * File browser drawn as a tree with back, forward, up and a path box; polls while a run writes.
	 * `memory` restores the last folder, `start` opens a given one, `onpick` sends file clicks to a
	 * preview, `here` binds the shown folder (null: the roots), and `fill` takes the parent's height.
	 */
	let {
		roots,
		empty = 'Nothing here yet.',
		memory = '',
		start = '',
		picked = null,
		onpick,
		here = $bindable(null),
		fill = false
	}: {
		roots: FolderRoot[];
		empty?: string;
		memory?: string;
		start?: string;
		picked?: string | null;
		onpick?: (path: string) => void;
		here?: string | null;
		fill?: boolean;
	} = $props();

	interface Entry {
		name: string;
		type: 'file' | 'directory';
		size: number;
		mtime: string;
	}

	/** Current folder; null is the list of roots. */
	let at = $state<{ root: FolderRoot; path: string } | null>(null);
	const current = $derived(at ?? (roots.length === 1 ? { root: roots[0], path: roots[0].path } : null));
	let entries = $state<Entry[]>([]);
	let missing = $state(false);
	let error = $state('');
	let now = $state(Date.now());
	let spinning = $state(false);

	$effect(() => {
		here = current?.path ?? null;
	});

	async function load() {
		const c = current;
		now = Date.now();
		if (!c) return;
		try {
			const d = await api<{ entries: Entry[] }>(`/files?path=${encodeURIComponent(c.path)}`);
			if (current?.path !== c.path) return;
			entries = d.entries;
			missing = false;
			error = '';
		} catch (e) {
			if (current?.path !== c.path) return;
			entries = [];
			missing = e instanceof ApiError && e.status === 404;
			error = missing ? '' : e instanceof Error ? e.message : String(e);
		}
	}

	function refresh() {
		spinning = true;
		load().finally(() => setTimeout(() => (spinning = false), 400));
	}

	/** Returns the closest root that contains a path. */
	function holder(p: string): FolderRoot | undefined {
		let best: FolderRoot | undefined;
		for (const r of roots) {
			const inside = p === r.path || p.startsWith(r.path === '/' ? '/' : r.path + '/');
			if (inside && (!best || r.path.length > best.path.length)) best = r;
		}
		return best;
	}

	// A folder named in the link takes precedence over the remembered one.
	let opened = $state('');
	$effect(() => {
		if (!start || start === opened) return;
		const root = holder(start);
		if (!root) return;
		opened = start;
		saved = null;
		at = { root, path: start };
	});

	// Restores the last folder for this tab once it is listed.
	const storeKey = $derived(`margie.folder.${memory}`);
	let saved: { root: string; path: string } | null = untrack(() => {
		try {
			return memory ? JSON.parse(sessionStorage.getItem(`margie.folder.${memory}`) ?? 'null') : null;
		} catch {
			return null;
		}
	});
	$effect(() => {
		if (!saved) return;
		const root = roots.find((r) => r.path === saved?.root);
		if (!root) return;
		at = { root, path: saved.path };
		saved = null;
	});
	$effect(() => {
		if (!memory || !at) return;
		try {
			sessionStorage.setItem(storeKey, JSON.stringify({ root: at.root.path, path: at.path }));
		} catch {
			// not remembered
		}
	});

	// Stays inside a lone root even as the run creates more.
	$effect(() => {
		if (at === null && roots.length === 1 && !saved && !start) at = { root: roots[0], path: roots[0].path };
	});

	$effect(() => {
		void current?.path;
		load();
	});

	// Polls often while a run is going, rarely otherwise.
	$effect(() => {
		const timer = setInterval(load, ws.active ? 3000 : 15000);
		return () => clearInterval(timer);
	});

	const crumbs = $derived.by(() => {
		const c = current;
		if (!c) return [];
		let acc = c.root.path;
		const rest = c.path
			.slice(c.root.path.length)
			.split('/')
			.filter(Boolean)
			.map((seg) => ({ label: seg, path: (acc = `${acc === '/' ? '' : acc}/${seg}`) }));
		return [{ label: c.root.label, path: c.root.path }, ...rest];
	});
	/** Indent depth of the folder's contents. */
	const top = $derived(roots.length > 1 ? 1 : 0);
	const inner = $derived(top + crumbs.length);

	/** Opens files in the current interface's viewer. */
	const viewer = $derived(uiBase.to('/view'));
	// ---- paths outside the roots ----
	// The server does not restrict reads to the roots, so any path can be typed or walked up to.

	/** Builds a root for a path outside every known one. */
	function rootFor(p: string): FolderRoot {
		return holder(p) ?? { label: p.split('/').filter(Boolean).at(-1) || '/', path: p };
	}

	let trail = $state<string[]>([]);
	let step = $state(-1);
	let typed = $state('');

	const canBack = $derived(step > 0);
	const canForward = $derived(step >= 0 && step < trail.length - 1);

	function goto(path: string, remember = true) {
		const p = path.trim();
		if (!p) return;
		at = { root: rootFor(p), path: p };
		typed = p;
		if (remember && trail[step] !== p) {
			// Drops the forward history.
			trail = [...trail.slice(0, step + 1), p];
			step = trail.length - 1;
		}
	}

	/** Opens a folder from outside as a history step. */
	export function go(path: string) {
		goto(path);
	}

	const open = (path: string) => goto(path);

	function back() {
		if (canBack) goto(trail[--step], false);
	}
	function forward() {
		if (canForward) goto(trail[++step], false);
	}

	/** Goes up one folder, even past a root. */
	function up() {
		const p = current?.path;
		if (!p || p === '/') return;
		goto(p.replace(/\/+$/, '').split('/').slice(0, -1).join('/') || '/');
	}

	// Keeps the path box in sync with the shown folder.
	$effect(() => {
		const p = current?.path;
		if (p) typed = p;
	});
	const child = (name: string) => `${current?.path === '/' ? '' : current?.path}/${name}`;
	/** Shortens a path to the part that tells folders apart (".../live/output/x" -> "output/x"). */
	function shortPath(p: string): string {
		const root = ws.resultRoots.outputRoot;
		if (!root || !p.startsWith(root)) return p;
		return root.split('/').filter(Boolean).at(-1) + p.slice(root.length);
	}
	/** True when modified in the last minute. */
	const fresh = (e: Entry) => now - new Date(e.mtime).getTime() < 60_000;

	function iconOf(name: string) {
		if (/\.(tsv|tab|csv|xlsx?|gff3?|gtf)$/i.test(name)) return FileSpreadsheet;
		if (/\.(png|jpe?g|gif|webp|svg|pdf)$/i.test(name)) return FileImage;
		if (/\.(html?|json|ya?ml|py|sh|smk|R|js|ts|toml)$/i.test(name)) return FileCode;
		if (/\.(gz|zip|tar|bz2|xz|tgz|sif)$/i.test(name)) return FileArchive;
		if (/\.(txt|log|md|out|err|stderr|stdout|fa|fna|faa|fasta|ffn|gbk?|gb)$/i.test(name)) return FileText;
		return File;
	}

	/** Sends a plain click to `onpick`; a modified click opens the file page. */
	function pick(e: MouseEvent, path: string) {
		if (!onpick || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
		e.preventDefault();
		onpick(path);
	}
</script>

<div class="fv" class:fill>
	<div class="vw-bar fv-bar">
		<div class="vw-group" role="group" aria-label="History">
			<button type="button" class="vw-btn icon" title="Back" aria-label="Back" disabled={!canBack} onclick={back}><ChevronLeft size={16} /></button>
			<button type="button" class="vw-btn icon" title="Forward" aria-label="Forward" disabled={!canForward} onclick={forward}><ChevronRight size={16} /></button>
			<button type="button" class="vw-btn icon" title="Up one folder" aria-label="Up one folder" disabled={!current || current.path === '/'} onclick={up}
				><ArrowUp size={15} /></button
			>
		</div>
		<form
			class="vw-field fv-where"
			onsubmit={(e) => {
				e.preventDefault();
				goto(typed);
			}}
		>
			<FolderOpen size={15} />
			<input
				bind:value={typed}
				spellcheck="false"
				autocapitalize="off"
				autocorrect="off"
				aria-label="Folder to open"
				placeholder="/path/to/a/folder"
				onkeydown={(e) => e.key === 'Escape' && current && (typed = current.path)}
			/>
			{#if typed.trim() && typed.trim() !== current?.path}
				<button type="submit" class="fv-go" title="Open this folder" aria-label="Open this folder"><CornerDownLeft size={14} /></button>
			{/if}
		</form>
		{#if ws.active}<span class="fv-live" title="Updating as the run writes"><i></i>Live</span>{/if}
		<button type="button" class="vw-pill icon" class:spin={spinning} title="Refresh" aria-label="Refresh" onclick={refresh}><RefreshCw size={15} /></button>
	</div>

	<div class="fv-scroll">
		<ul class="fv-tree" aria-label="Folder">
			{#if roots.length > 1}
				<li class="fv-row fv-crumb" style="--d: 0">
					{#if current}
						<button type="button" class="fv-name" onclick={() => (at = null)}><Folder size={16} /><span>All folders</span></button>
					{:else}
						<span class="fv-name here"><FolderOpen size={16} /><span>All folders</span></span>
					{/if}
				</li>
			{/if}
			{#each crumbs as c, i (c.path)}
				<li class="fv-row fv-crumb" style="--d: {top + i}">
					{#if i === crumbs.length - 1}
						<span class="fv-name here" title={c.path}><FolderOpen size={16} /><span>{c.label}</span></span>
					{:else}
						<button type="button" class="fv-name" title={c.path} onclick={() => open(c.path)}><Folder size={16} /><span>{c.label}</span></button>
					{/if}
				</li>
			{/each}

			{#if !current}
				{#each roots as r (r.path)}
					<li class="fv-row fv-place" style="--d: {inner}">
						<button type="button" class="fv-name dir" title={r.label} onclick={() => (at = { root: r, path: r.path })}><Folder size={16} /><span>{r.label}</span></button>
						<span class="fv-path" title={r.path}>{shortPath(r.path)}</span>
					</li>
				{:else}
					<li class="fv-row fv-note" style="--d: {inner}">{empty}</li>
				{/each}
			{:else if error}
				<li class="fv-row fv-note bad" style="--d: {inner}">{error}</li>
			{:else if missing}
				<li class="fv-row fv-note" style="--d: {inner}">Not created yet. It appears here when the run writes it.</li>
			{:else if !entries.length}
				<li class="fv-row fv-note" style="--d: {inner}">Empty so far.</li>
			{:else}
				<li class="fv-row fv-cols" style="--d: {inner}" aria-hidden="true"><span>Name</span><span>Size</span><span>Modified</span><span></span></li>
				{#each entries as e (e.name)}
					{@const p = child(e.name)}
					<li class="fv-row" class:picked={picked === p} style="--d: {inner}">
						{#if e.type === 'directory'}
							<button type="button" class="fv-name dir" title={e.name} onclick={() => open(p)}><Folder size={16} /><span>{e.name}</span></button>
							<span class="fv-size"></span>
						{:else}
							{@const Icon = iconOf(e.name)}
							<a class="fv-name" title={e.name} href="{viewer}?path={encodeURIComponent(p)}" aria-current={picked === p ? 'true' : undefined} onclick={(ev) => pick(ev, p)}
								><Icon size={16} /><span>{e.name}</span></a
							>
							<span class="fv-size">{formatBytes(e.size)}</span>
						{/if}
						<span class="fv-when" class:fresh={fresh(e)} title={new Date(e.mtime).toLocaleString()}>{ago(e.mtime)}</span>
						{#if e.type === 'file'}
							<a class="fv-dl" href={fileUrl(p)} download title="Download {e.name}" aria-label="Download {e.name}"><Download size={14} /></a>
						{:else}
							<span class="fv-dl"></span>
						{/if}
					</li>
				{/each}
			{/if}
		</ul>
	</div>
</div>

<style>
	.fv {
		container-type: inline-size;
		display: flex;
		flex-direction: column;
		gap: 12px;
		min-width: 0;
		font-size: var(--mg-fs-sm);
	}
	.fv.fill {
		height: 100%;
		min-height: 0;
	}
	.fv.fill .fv-scroll {
		flex: 1 1 auto;
		min-height: 0;
		overflow: auto;
		margin: 0 -6px;
		padding: 0 6px 6px;
	}

	/* ---- toolbar ---- */
	.fv-bar {
		flex-wrap: nowrap;
	}
	.fv-where {
		flex: 1 1 auto;
	}
	.fv-where input {
		font-size: var(--mg-fs-xs);
	}
	.fv-go {
		display: grid;
		place-items: center;
		flex-shrink: 0;
		width: 24px;
		height: 24px;
		margin-right: -8px;
		padding: 0;
		border: none;
		border-radius: var(--mg-r-sm);
		background: var(--mg-accent);
		color: var(--mg-on-accent);
		cursor: pointer;
	}
	.fv-live {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		flex-shrink: 0;
		height: 26px;
		padding: 0 10px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-ok) 14%, transparent);
		color: var(--mg-ok);
		font-size: var(--mg-fs-xs);
		font-weight: 600;
	}
	.fv-live i {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: currentColor;
	}
	.spin :global(svg) {
		animation: fv-turn 500ms ease;
	}

	/* ---- tree ---- */
	.fv-tree {
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.fv-row {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 76px 84px 30px;
		align-items: center;
		gap: 12px;
		min-height: 34px;
		padding: 0 6px 0 calc(6px + min(var(--d, 0), 8) * 18px);
		border-radius: var(--mg-r-sm);
		transition: background-color 120ms ease;
	}
	.fv-row:not(.fv-note):hover {
		background: color-mix(in srgb, var(--mg-text) 5%, transparent);
	}
	.fv-row.picked {
		background: color-mix(in srgb, var(--mg-accent) 14%, transparent);
		box-shadow: inset 3px 0 0 var(--mg-accent);
	}
	.fv-row.picked:hover {
		background: color-mix(in srgb, var(--mg-accent) 18%, transparent);
	}
	.fv-crumb,
	.fv-note {
		grid-template-columns: minmax(0, 1fr);
	}
	.fv-place {
		grid-template-columns: minmax(0, 1fr) minmax(0, 1.2fr);
	}
	/* Vertical guide line per level. */
	.fv-row:not(.fv-crumb) {
		background-image: linear-gradient(var(--mg-border), var(--mg-border));
		background-size: 1px 100%;
		background-position: calc(14px + (min(var(--d, 0), 8) - 1) * 18px) 0;
		background-repeat: no-repeat;
	}
	.fv-row[style*='--d: 0'] {
		background-image: none;
	}
	.fv-name {
		display: flex;
		align-items: center;
		gap: 9px;
		min-width: 0;
		padding: 5px 0;
		border: none;
		background: none;
		color: var(--mg-text);
		font: inherit;
		text-align: left;
		text-decoration: none;
		cursor: pointer;
	}
	.fv-name > span {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.fv-name :global(svg) {
		flex-shrink: 0;
		color: var(--mg-text-3);
	}
	.fv-name.dir :global(svg),
	.fv-crumb .fv-name :global(svg) {
		color: color-mix(in srgb, var(--mg-accent) 75%, var(--mg-text-3));
		fill: color-mix(in srgb, var(--mg-accent) 18%, transparent);
	}
	.fv-crumb .fv-name {
		color: var(--mg-text-2);
	}
	.fv-crumb button.fv-name:hover {
		color: var(--mg-text);
	}
	.fv-name.here {
		color: var(--mg-text);
		font-weight: 650;
		cursor: default;
	}
	.fv-name.here :global(svg) {
		color: var(--mg-accent);
	}
	a.fv-name:hover,
	.fv-name.dir:hover {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.fv-row.picked .fv-name {
		color: var(--mg-accent-ink, var(--mg-accent));
		font-weight: 600;
	}
	.fv-row.picked .fv-name :global(svg) {
		color: var(--mg-accent);
	}
	.fv-size,
	.fv-when,
	.fv-path {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-3);
	}
	.fv-size {
		text-align: right;
	}
	.fv-when.fresh {
		color: var(--mg-ok);
		font-weight: 600;
	}
	.fv-dl {
		display: grid;
		place-items: center;
		width: 28px;
		height: 28px;
		border-radius: var(--mg-r-sm);
		color: var(--mg-text-3);
		opacity: 0.55;
		transition:
			opacity 120ms ease,
			background-color 120ms ease;
	}
	.fv-row:is(:hover, :focus-within, .picked) a.fv-dl {
		opacity: 1;
	}
	a.fv-dl:hover {
		background: color-mix(in srgb, var(--mg-accent) 14%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	/* Column headers over a folder's contents. */
	.fv-row.fv-cols {
		min-height: 26px;
		background-image: none;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.fv-row.fv-cols:hover {
		background-color: transparent;
	}
	.fv-cols span:nth-child(2) {
		text-align: right;
	}
	.fv-cols span:first-child {
		padding-left: 25px;
	}
	.fv-note {
		min-height: 40px;
		color: var(--mg-text-3);
	}
	.fv-note.bad {
		color: var(--mg-danger);
	}

	@container (max-width: 560px) {
		.fv-row {
			grid-template-columns: minmax(0, 1fr) 70px 30px;
			gap: 8px;
			padding-left: calc(4px + min(var(--d, 0), 6) * 14px);
		}
		.fv-row:not(.fv-crumb) {
			background-position: calc(11px + (min(var(--d, 0), 6) - 1) * 14px) 0;
		}
		.fv-size,
		.fv-cols span:nth-child(2) {
			display: none;
		}
		.fv-place {
			grid-template-columns: minmax(0, 1fr);
		}
		.fv-path {
			display: none;
		}
	}

	@keyframes fv-turn {
		to {
			transform: rotate(360deg);
		}
	}
	:global([data-motion='off']) .fv * {
		animation: none !important;
		transition: none !important;
	}
</style>
