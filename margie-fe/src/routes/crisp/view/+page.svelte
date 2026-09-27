<script lang="ts">
	import { page } from '$app/state';
	import { ArrowLeft, FolderOpen } from 'lucide-svelte';
	import FileViewer from '$lib/workspace/viewers/FileViewer.svelte';
	import '$lib/workspace/viewers/tools.css';

	/** Single-file page: Back and the parent folder above, the file in a card filling the window. */
	const path = $derived(page.url.searchParams.get('path') ?? '');
	const folder = $derived(path.slice(0, path.lastIndexOf('/')) || '/');
</script>

<svelte:head><title>{path ? `${path.split('/').pop()} | ` : ''}MARGIE</title></svelte:head>

<div class="cr-page fill" data-shade="page-view">
	<nav class="vp-top vw-bar" aria-label="Where this file is">
		<button type="button" class="vw-pill" onclick={() => history.back()}><ArrowLeft size={15} />Back</button>
		{#if path}
			<a class="vp-folder" href="/crisp/files?path={encodeURIComponent(folder)}" title="Open {folder} in Files">
				<FolderOpen size={15} /><span class="mg-mono">{`\u200e${folder}\u200e`}</span>
			</a>
		{/if}
	</nav>
	<section class="vp-card">
		{#if path}
			<FileViewer {path} />
		{:else}
			<p class="vw-msg">No file chosen. Open one from Files or Results.</p>
		{/if}
	</section>
</div>

<style>
	.fill {
		height: 100%;
		min-height: 0;
		padding-bottom: 24px;
		gap: 14px;
	}
	.vp-top {
		flex-wrap: nowrap;
	}
	.vp-folder {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
		height: var(--mg-ctl-sm, 36px);
		padding: 0 14px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 5%, transparent);
		color: var(--mg-text-2);
		font-size: var(--mg-fs-xs);
	}
	.vp-folder:hover {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.vp-folder span {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		direction: rtl;
		text-align: left;
	}
	.vp-folder :global(svg) {
		flex-shrink: 0;
	}
	.vp-card {
		display: flex;
		flex-direction: column;
		flex-grow: 1;
		min-height: 0;
		padding: var(--mg-pad);
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow);
	}
	.vp-card > :global(*) {
		flex-grow: 1;
		min-height: 0;
	}
	@media (max-width: 720px) {
		.fill {
			height: auto;
		}
		.vp-card {
			height: 88vh;
			flex: none;
			padding: 12px;
		}
	}
</style>
