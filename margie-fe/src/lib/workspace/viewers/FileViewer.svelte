<script lang="ts" module>
	export type ViewKind = 'table' | 'image' | 'html' | 'pdf' | 'text';

	const TABLE = /\.(tsv|tab|csv|gff|gff3|gtf|xlsx)$/i;
	const IMAGE = /\.(png|jpe?g|gif|webp|svg)$/i;

	/** Display mode; .txt files can also be shown as tables. */
	export function viewKind(name: string): ViewKind {
		if (TABLE.test(name)) return 'table';
		if (IMAGE.test(name)) return 'image';
		if (/\.html?$/i.test(name)) return 'html';
		if (/\.pdf$/i.test(name)) return 'pdf';
		return 'text';
	}
</script>

<script lang="ts">
	import './tools.css';
	import type { Snippet } from 'svelte';
	import { Download, FileCode, FileImage, FileSpreadsheet, FileText, Table2 } from 'lucide-svelte';
	import { api, fileUrl, formatBytes } from '$lib/api';
	import { ago } from '../format';
	import DataGrid from './DataGrid.svelte';
	import HtmlViewer from './HtmlViewer.svelte';
	import ImageViewer from './ImageViewer.svelte';
	import TextViewer from './TextViewer.svelte';
	import { viewable } from './viewable.svelte';

	/** Viewer for any result file (table, image, web page, PDF, text) under a head with name, size, age and `actions`. */
	let { path, actions }: { path: string; actions?: Snippet } = $props();

	const name = $derived(path.split('/').pop() ?? path);
	const natural = $derived(viewKind(name));
	/** Tab-separated plain-text files can be shown either way. */
	const either = $derived(/\.(txt|tsv|tab|csv|gff|gff3|gtf)$/i.test(name));
	let as = $state<ViewKind | null>(null);
	const kind = $derived(as ?? natural);
	const pdf = viewable(() => (kind === 'pdf' ? fileUrl(path, true) : ''));
	const Icon = $derived({ table: FileSpreadsheet, image: FileImage, html: FileCode, pdf: FileImage, text: FileText }[kind]);

	let info = $state<{ size: number; mtime: string } | null>(null);
	$effect(() => {
		const p = path;
		as = null;
		info = null;
		const parent = p.slice(0, p.lastIndexOf('/')) || '/';
		api<{ entries: { name: string; size: number; mtime: string }[] }>(`/files?path=${encodeURIComponent(parent)}`)
			.then((d) => {
				if (p === path) info = d.entries.find((e) => e.name === name) ?? null;
			})
			.catch(() => {});
	});
</script>

<div class="file vw-scope">
	<header class="vw-bar">
		<span class="kind k-{kind}" aria-hidden="true"><Icon size={18} /></span>
		<div class="title">
			<h2 class="mg-mono" title={path}>{name}</h2>
			<span class="meta">
				{#if info}{formatBytes(info.size)}<i>|</i>changed {ago(info.mtime)}{:else}&nbsp;{/if}
			</span>
		</div>
		<span class="vw-grow"></span>
		{#if either}
			<div class="vw-group" role="group" aria-label="Show as">
				<button type="button" class="vw-btn" title="As a table" aria-pressed={kind === 'table'} onclick={() => (as = 'table')}><Table2 size={14} /><span class="vw-lbl">Table</span></button>
				<button type="button" class="vw-btn" title="As text" aria-pressed={kind === 'text'} onclick={() => (as = 'text')}><FileText size={14} /><span class="vw-lbl">Text</span></button>
			</div>
		{/if}
		{@render actions?.()}
		<a class="vw-pill" href={fileUrl(path)} download title="Download {name}"><Download size={15} /><span class="vw-lbl">Download</span></a>
	</header>

	<div class="view">
		{#key `${path}:${kind}`}
			{#if kind === 'table'}
				<DataGrid {path} />
			{:else if kind === 'image'}
				<ImageViewer src={fileUrl(path, true)} alt={name} />
			{:else if kind === 'html'}
				<HtmlViewer src={fileUrl(path, true)} title={name} />
			{:else if kind === 'pdf'}
				<iframe class="pdf vw-pane" src={pdf.url || 'about:blank'} title={name}></iframe>
			{:else}
				<TextViewer {path} {name} />
			{/if}
		{/key}
	</div>
</div>

<style>
	.file {
		display: flex;
		flex-direction: column;
		gap: 14px;
		height: 100%;
		min-height: 0;
	}
	header {
		flex-wrap: wrap;
		gap: 10px 12px;
	}
	.kind {
		display: grid;
		place-items: center;
		flex-shrink: 0;
		width: 40px;
		height: 40px;
		border-radius: 12px;
		background: color-mix(in srgb, var(--mg-accent) 13%, var(--mg-surface));
		color: var(--mg-accent-ink, var(--mg-accent));
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--mg-accent) 25%, transparent);
	}
	.title {
		display: flex;
		flex-direction: column;
		gap: 1px;
		min-width: 0;
		flex: 0 1 auto;
	}
	h2 {
		font-size: var(--mg-fs);
		font-weight: 650;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.meta {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.meta i {
		margin: 0 6px;
		font-style: normal;
	}
	.view {
		display: flex;
		flex-direction: column;
		flex-grow: 1;
		min-height: 0;
	}
	.view > :global(*) {
		flex-grow: 1;
		min-height: 0;
	}
	.pdf {
		width: 100%;
		height: 100%;
		min-height: 520px;
	}
</style>
