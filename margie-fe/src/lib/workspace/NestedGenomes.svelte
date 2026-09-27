<script lang="ts">
	import { FolderTree } from 'lucide-svelte';
	import { formatBytes } from '$lib/api';
	import { ws } from './data.svelte';
	import { ui } from './ui.svelte';

	/**
	 * Finds genomes in subfolders of the genomes folder (runs read only the top level), offers to
	 * copy or move them up, and after a move to remove the emptied folders. Hidden when there are none.
	 */

	const nested = $derived(ws.nested);
	const folders = $derived([...new Set(nested.map((n) => n.folder))].sort());
	const clashes = $derived(nested.filter((n) => n.clashes));
	const bytes = $derived(nested.reduce((a, n) => a + n.size, 0));

	/** null: asking what to do; 'moved': asking whether to remove the folders. */
	let step = $state<'ask' | 'moved'>('ask');
	let emptied = $state<string[]>([]);
	let open = $state(false);

	async function gather(mode: 'copy' | 'move') {
		const r = await ws.gatherGenomes(mode);
		if (!r) return;
		const what = mode === 'copy' ? 'Copied' : 'Moved';
		ui.notify(
			`${what} ${r.moved.length} genome${r.moved.length === 1 ? '' : 's'}${r.skipped.length ? `, left ${r.skipped.length} where they were` : ''}`,
			r.moved.length ? 'ok' : 'error'
		);
		if (mode === 'move' && r.moved.length) {
			emptied = [...new Set(r.moved.map((rel) => rel.split('/')[0]))];
			step = 'moved';
		}
	}

	async function clearFolders(yes: boolean) {
		if (yes) {
			const r = await ws.gatherGenomes('move', true);
			if (r) ui.notify(r.removed.length ? `Removed ${r.removed.length} empty folder${r.removed.length === 1 ? '' : 's'}` : 'Nothing left to remove', 'ok');
		}
		step = 'ask';
		emptied = [];
	}
</script>

{#if nested.length}
	<div class="nest">
		<div class="line">
			<span class="ico" aria-hidden="true"><FolderTree size={16} /></span>
			<strong>{nested.length} genome{nested.length === 1 ? '' : 's'}</strong>
			<span class="mg-note">
				in {folders.length} folder{folders.length === 1 ? '' : 's'} inside your genomes folder ({formatBytes(bytes)}). A run reads only the
				folder itself, so these are not in it yet.
			</span>
			<span class="mg-grow"></span>
			<button type="button" class="pill" aria-expanded={open} onclick={() => (open = !open)}>{open ? 'Hide' : 'Show'} them</button>
		</div>

		{#if open}
			<ul class="found">
				{#each nested as n (n.rel)}
					<li>
						<span class="mg-mono where">{n.folder}/</span>
						<span class="mg-mono name">{n.name}</span>
						<span class="mg-note size">{formatBytes(n.size)}</span>
						<span class="mg-note state" class:mg-warn={n.clashes}>{n.clashes ? 'a file of this name is already there' : 'ready to move'}</span>
					</li>
				{/each}
			</ul>
		{/if}

		{#if step === 'ask'}
			<div class="line acts">
				<span class="mg-note">Put them in the genomes folder?</span>
				<button type="button" class="mg-btn small primary" disabled={ws.savingGenomes} onclick={() => gather('move')}>Move them</button>
				<button type="button" class="mg-btn small" disabled={ws.savingGenomes} onclick={() => gather('copy')}>Copy them</button>
				<span class="mg-note">
					Moving leaves the folders empty; copying leaves your originals alone.
					{#if clashes.length}<span class="mg-warn">{clashes.length} would clash with a file already there and stay put.</span>{/if}
				</span>
			</div>
		{:else}
			<div class="line acts">
				<span class="mg-note">Moved. Delete the {emptied.length === 1 ? 'folder' : 'folders'} left behind ({emptied.join(', ')})?</span>
				<button type="button" class="mg-btn small" disabled={ws.savingGenomes} onclick={() => clearFolders(true)}>Delete them</button>
				<button type="button" class="pill" onclick={() => clearFolders(false)}>Keep them</button>
				<span class="mg-note">Only folders with nothing left in them are removed.</span>
			</div>
		{/if}
	</div>
{/if}

<style>
	/* Warning card listing the folders and the actions. */
	.nest {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 12px 14px;
		border: 1px solid color-mix(in srgb, var(--mg-warn) 55%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-warn) 7%, var(--mg-surface));
		box-shadow: inset 3px 0 0 var(--mg-warn);
		font-size: var(--mg-fs-sm);
	}
	.line {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 12px;
	}
	.line.acts {
		padding-top: 10px;
		border-top: 1px solid color-mix(in srgb, var(--mg-warn) 25%, var(--mg-border));
	}
	.ico {
		display: grid;
		place-items: center;
		flex: none;
		width: 28px;
		height: 28px;
		border-radius: 8px;
		background: color-mix(in srgb, var(--mg-warn) 18%, transparent);
		color: var(--mg-warn);
	}
	.pill {
		height: 28px;
		padding: 0 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		cursor: pointer;
	}
	.pill:hover {
		border-color: var(--mg-border-strong);
		color: var(--mg-text);
	}
	.found {
		display: flex;
		flex-direction: column;
		max-height: 220px;
		overflow: auto;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
	}
	.found li {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(0, 1.2fr) 80px minmax(0, 1fr);
		gap: 12px;
		align-items: baseline;
		padding: 6px 12px;
		font-size: var(--mg-fs-xs);
	}
	.found li + li {
		border-top: 1px solid var(--mg-border);
	}
	.where,
	.name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.where {
		color: var(--mg-text-3);
	}
	.size {
		text-align: right;
		font-variant-numeric: tabular-nums;
	}
	:global([data-motion='off']) .nest {
		animation: none;
	}
	@media (max-width: 700px) {
		.found li {
			grid-template-columns: minmax(0, 1fr) auto;
		}
		.state {
			grid-column: 1 / -1;
		}
	}
</style>
