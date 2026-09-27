<script lang="ts">
	import { Database, Dna, ExternalLink, FileText, Folder, FolderCheck, HardDrive, House, Monitor, Package, Server, X } from 'lucide-svelte';
	import FolderView, { type FolderRoot } from '$lib/workspace/FolderView.svelte';
	import FileViewer from '$lib/workspace/viewers/FileViewer.svelte';
	import '$lib/workspace/viewers/tools.css';
	import { uiBase } from '$lib/workspace/base.svelte';
	import { backend } from '$lib/workspace/backend.svelte';

	/**
	 * Crisp's Files page: places as pills, the open folder as a tree (FolderView),
	 * and the selected file previewed beside it, with a draggable divider between.
	 */
	let {
		roots,
		start = '',
		memory = '',
		empty = 'Nothing here.'
	}: { roots: FolderRoot[]; start?: string; memory?: string; empty?: string } = $props();

	// ------------------------------------------------ the places, as pills
	function iconFor(r: FolderRoot) {
		const l = r.label.toLowerCase();
		if (r.path === '/') return backend.cluster ? Server : Monitor;
		if (l === 'home') return House;
		if (r.path.startsWith('/Volumes/') || r.path.startsWith('/mnt/') || r.path.startsWith('/media/')) return HardDrive;
		if (l.startsWith('result') || l.includes('output')) return FolderCheck;
		if (l.startsWith('genome')) return Dna;
		if (l.startsWith('database')) return Database;
		if (l.startsWith('margie')) return Package;
		return Folder;
	}

	let view = $state<ReturnType<typeof FolderView> | null>(null);
	/** The folder open in the tree; null is the list of places. */
	let here = $state<string | null>(null);

	/** The place a folder is in: the closest one, as MARGIE sits inside Home. */
	function placeOf(h: string | null): FolderRoot | null {
		if (!h) return null;
		let best: FolderRoot | null = null;
		for (const r of roots) {
			const inside = h === r.path || h.startsWith(r.path === '/' ? '/' : r.path + '/');
			if (inside && (!best || r.path.length > best.path.length)) best = r;
		}
		return best;
	}
	const place = $derived(placeOf(here));

	// ------------------------------------------------ the preview
	const PICKED = 'margie.crisp.files.picked';
	let picked = $state<string | null>(null);
	let pane = $state<HTMLElement | null>(null);
	$effect(() => {
		// Reopens the last file viewed, unless a link named a folder.
		if (start) return;
		try {
			picked = sessionStorage.getItem(PICKED);
		} catch {
			// not remembered
		}
	});
	$effect(() => {
		const p = picked;
		try {
			if (p) sessionStorage.setItem(PICKED, p);
			else sessionStorage.removeItem(PICKED);
		} catch {
			// not remembered
		}
	});

	function preview(p: string) {
		picked = p;
		if (pane && matchMedia('(max-width: 900px)').matches) requestAnimationFrame(() => pane?.scrollIntoView({ behavior: 'smooth', block: 'start' }));
	}
	const viewer = $derived(uiBase.to('/view'));
	const pickedName = $derived(picked?.split('/').pop() ?? '');

	// ------------------------------------------------ the divider
	const SPLIT = 'margie.crisp.files.split';
	let body = $state<HTMLElement | null>(null);
	let tree = $state<HTMLElement | null>(null);
	let left = $state<number | null>(
		(() => {
			try {
				const n = Number(localStorage.getItem(SPLIT));
				return n > 0 ? n : null;
			} catch {
				return null;
			}
		})()
	);
	const clampLeft = (n: number) => {
		const w = body?.clientWidth ?? 1200;
		return Math.round(Math.max(300, Math.min(w - 340, n)));
	};
	function setLeft(n: number) {
		left = clampLeft(n);
		try {
			localStorage.setItem(SPLIT, String(left));
		} catch {
			// not remembered
		}
	}
	function drag(e: PointerEvent) {
		if (!body) return;
		const handle = e.currentTarget as HTMLElement;
		handle.setPointerCapture(e.pointerId);
		const x0 = body.getBoundingClientRect().left;
		const move = (m: PointerEvent) => setLeft(m.clientX - x0);
		const up = () => {
			handle.removeEventListener('pointermove', move);
			handle.removeEventListener('pointerup', up);
		};
		handle.addEventListener('pointermove', move);
		handle.addEventListener('pointerup', up);
	}
	function nudge(e: KeyboardEvent) {
		const step = e.shiftKey ? 80 : 24;
		const now = left ?? tree?.getBoundingClientRect().width ?? 480;
		if (e.key === 'ArrowLeft') setLeft(now - step);
		else if (e.key === 'ArrowRight') setLeft(now + step);
		else return;
		e.preventDefault();
	}
</script>

<div class="fb-board">
	<nav class="fb-places" aria-label="Places">
		<h2>Places</h2>
		{#each roots as r (r.path)}
			{@const Icon = iconFor(r)}
			<button type="button" class="fb-pill" class:on={place?.path === r.path} aria-current={place?.path === r.path ? 'location' : undefined} title={r.path} onclick={() => view?.go(r.path)}>
				<Icon size={15} />
				<span>{r.label}</span>
			</button>
		{/each}
	</nav>

	<div class="fb-body" bind:this={body} style={left ? `--fb-left: ${left}px` : undefined}>
		<div class="fb-tree" bind:this={tree}>
			<FolderView bind:this={view} bind:here {roots} {start} {memory} {empty} {picked} onpick={preview} fill />
		</div>

		<!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
		<div
			class="fb-split"
			role="separator"
			aria-orientation="vertical"
			aria-label="Resize the tree and the preview"
			aria-valuenow={left ?? undefined}
			title="Drag to resize. Double-click to reset."
			tabindex="0"
			onpointerdown={drag}
			onkeydown={nudge}
			ondblclick={() => {
				left = null;
				try {
					localStorage.removeItem(SPLIT);
				} catch {
					// not remembered
				}
			}}
		><span></span></div>

		<section class="fb-preview" bind:this={pane} aria-label="Preview">
			{#if picked}
				{#key picked}
					<div class="fb-file">
						<FileViewer path={picked}>
							{#snippet actions()}
								<div class="vw-group" role="group" aria-label="Preview">
									<a class="vw-btn" href="{viewer}?path={encodeURIComponent(picked ?? '')}" title="Open {pickedName} on its own page"><ExternalLink size={14} /><span class="vw-lbl">Full view</span></a>
									<button type="button" class="vw-btn icon" title="Close the preview" aria-label="Close the preview" onclick={() => (picked = null)}><X size={15} /></button>
								</div>
							{/snippet}
						</FileViewer>
					</div>
				{/key}
			{:else}
				<div class="fb-empty">
					<FileText size={26} strokeWidth={1.4} />
					<strong>No file open</strong>
					<span>Pick a file on the left to preview it here: tables, text, logs, web pages and images.</span>
				</div>
			{/if}
		</section>
	</div>
</div>

<style>
	/* Places down the left, as a file manager has them; the folder and the
	   preview side by side to their right. */
	.fb-board {
		display: grid;
		grid-template-columns: 200px minmax(0, 1fr);
		flex-grow: 1;
		min-height: 0;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		color: var(--mg-text);
		background: var(--mg-surface);
		box-shadow: none;
		overflow: hidden;
	}

	/* ---- places ---- */
	.fb-places {
		display: flex;
		flex-direction: column;
		gap: 1px;
		min-width: 0;
		min-height: 0;
		padding: 10px 8px;
		border-right: 1px solid var(--mg-border);
		background: var(--cr-card, var(--mg-surface-2));
		overflow-y: auto;
		scrollbar-width: thin;
	}
	.fb-places h2 {
		margin: 2px 10px 6px;
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		color: var(--mg-text-3);
	}
	.fb-pill {
		display: flex;
		align-items: center;
		gap: 9px;
		min-width: 0;
		height: 32px;
		padding: 0 10px;
		border: none;
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-sm);
		text-align: left;
		cursor: pointer;
		transition:
			background-color 140ms ease,
			color 140ms ease;
	}
	.fb-pill span {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.fb-pill:hover {
		background: color-mix(in srgb, var(--mg-text) 6%, transparent);
		color: var(--mg-text);
	}
	.fb-pill.on {
		background: color-mix(in srgb, var(--mg-accent) 13%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.fb-pill :global(svg) {
		flex-shrink: 0;
		color: var(--mg-text-3);
	}
	.fb-pill.on :global(svg) {
		color: currentColor;
	}

	/* ---- tree | preview ---- */
	.fb-body {
		position: relative;
		display: grid;
		grid-template-columns: minmax(300px, var(--fb-left, 44%)) 0 minmax(0, 1fr);
		flex-grow: 1;
		min-height: 0;
	}
	.fb-tree {
		min-width: 0;
		min-height: 0;
		padding: 14px var(--mg-pad);
		border-right: 1px solid var(--mg-border);
	}
	.fb-split {
		position: relative;
		z-index: 2;
		width: 12px;
		margin-left: -6px;
		cursor: col-resize;
		touch-action: none;
	}
	.fb-split span {
		position: absolute;
		top: 50%;
		left: 50%;
		width: 6px;
		height: 44px;
		border: 1px solid var(--mg-border-strong);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		transform: translate(-50%, -50%);
		transition:
			background-color 160ms ease,
			border-color 160ms ease;
	}
	.fb-split:hover span,
	.fb-split:focus-visible span {
		border-color: var(--mg-accent);
		background: var(--mg-accent);
	}
	.fb-split:focus-visible {
		outline: none;
	}
	.fb-preview {
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
		background: var(--mg-surface);
	}
	.fb-file {
		display: flex;
		flex-direction: column;
		flex-grow: 1;
		min-height: 0;
		padding: 14px var(--mg-pad) var(--mg-pad);
		overflow: auto;
		animation: fb-in 260ms cubic-bezier(0.2, 0.7, 0.2, 1) both;
	}
	.fb-file > :global(*) {
		flex-grow: 1;
		min-height: 0;
	}
	.fb-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 6px;
		flex-grow: 1;
		padding: calc(var(--mg-gap) * 2) var(--mg-pad);
		text-align: center;
		color: var(--mg-text-3);
		font-size: var(--mg-fs-sm);
	}
	.fb-empty :global(svg) {
		margin-bottom: 4px;
		opacity: 0.7;
	}
	.fb-empty strong {
		color: var(--mg-text-2);
		font-size: var(--mg-fs);
		font-weight: 500;
	}
	.fb-empty > span {
		max-width: 36ch;
	}

	@keyframes fb-in {
		from {
			opacity: 0;
			transform: translateY(4px);
		}
	}
	:global([data-motion='off']) .fb-board,
	:global([data-motion='off']) .fb-board :global(*) {
		animation: none !important;
		transition: none !important;
	}

	@media (max-width: 900px) {
		.fb-board {
			display: flex;
			flex-direction: column;
			flex: none;
		}
		.fb-places {
			flex-direction: row;
			border-right: none;
			border-bottom: 1px solid var(--mg-border);
			overflow-x: auto;
		}
		.fb-places h2 {
			display: none;
		}
		.fb-pill {
			flex-shrink: 0;
		}
		.fb-body {
			display: flex;
			flex-direction: column;
		}
		.fb-tree {
			flex: none;
			border-right: none;
			border-bottom: 1px solid var(--mg-border);
		}
		.fb-split {
			display: none;
		}
		.fb-preview {
			flex: none;
			height: 85vh;
		}
		.fb-preview:has(.fb-empty) {
			height: auto;
		}
	}
	@media (max-width: 520px) {
		.fb-places,
		.fb-tree,
		.fb-file {
			padding-left: 12px;
			padding-right: 12px;
		}
	}
</style>
