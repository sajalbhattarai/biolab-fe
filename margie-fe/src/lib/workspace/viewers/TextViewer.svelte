<script lang="ts">
	import './tools.css';
	import { Search, TextWrap } from 'lucide-svelte';
	import { api } from '$lib/api';

	/** Text file viewer (log, FASTA, JSON, GenBank...) with line numbers; shows the first megabyte of large files. */
	let { path, name }: { path: string; name: string } = $props();

	let text = $state('');
	let binary = $state(false);
	let truncated = $state(false);
	let error = $state('');
	let loading = $state(true);
	let wrap = $state(false);
	let find = $state('');

	const json = $derived(/\.json$/i.test(name));
	const fasta = $derived(/\.(fa|fna|faa|fasta|ffn|frn|fas)$/i.test(name));

	$effect(() => {
		const p = path;
		loading = true;
		api<{ content: string; binary: boolean; truncated: boolean }>(`/files/text?path=${encodeURIComponent(p)}`)
			.then((d) => {
				if (p !== path) return;
				binary = d.binary;
				truncated = d.truncated;
				text = d.content;
				if (json && !d.truncated) {
					try {
						text = JSON.stringify(JSON.parse(d.content), null, 2);
					} catch {
						// shown unformatted
					}
				}
				error = '';
			})
			.catch((e) => (error = e instanceof Error ? e.message : String(e)))
			.finally(() => (loading = false));
	});

	const lines = $derived(text.replace(/\n$/, '').split('\n'));
	const needle = $derived(find.trim().toLowerCase());
	const hits = $derived(needle ? lines.reduce((n, l) => n + (l.toLowerCase().includes(needle) ? 1 : 0), 0) : 0);
</script>

<div class="text vw-scope">
	<div class="vw-bar">
		<label class="vw-field find">
			<Search size={15} />
			<input type="search" placeholder="Find in file" aria-label="Find in file" bind:value={find} />
			{#if needle}<span class="hits">{hits.toLocaleString('en-US')} line{hits === 1 ? '' : 's'}</span>{/if}
		</label>
		<span class="vw-grow"></span>
		<span class="vw-num">{lines.length.toLocaleString('en-US')} lines{truncated ? ', the first megabyte only' : ''}</span>
		<div class="vw-group">
			<button type="button" class="vw-btn" aria-pressed={wrap} title="Wrap long lines" onclick={() => (wrap = !wrap)}><TextWrap size={14} /><span class="vw-lbl">Wrap</span></button>
		</div>
	</div>
	{#if error}
		<p class="vw-pane vw-msg bad">{error}</p>
	{:else if loading}
		<p class="vw-pane vw-msg">Loading…</p>
	{:else if binary}
		<p class="vw-pane vw-msg">This file is not text, so it cannot be shown here. Download it to open it.</p>
	{:else}
		<div class="scroll vw-pane" class:wrap>
			<table>
				<tbody>
					{#each lines as line, i (i)}
						<tr class:hit={needle && line.toLowerCase().includes(needle)}>
							<td class="n">{i + 1}</td>
							<td class="l" class:head={fasta && line.startsWith('>')}>{line || ' '}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	{/if}
</div>

<style>
	.text {
		display: flex;
		flex-direction: column;
		gap: 12px;
		height: 100%;
		min-height: 0;
		font-size: var(--mg-fs-sm);
	}
	.find {
		flex: 0 1 320px;
	}
	.hits {
		flex-shrink: 0;
		padding: 1px 8px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-warn) 18%, transparent);
		color: var(--mg-text-2);
		font-size: var(--mg-fs-xs);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.vw-msg {
		flex-grow: 1;
	}
	.scroll {
		flex-grow: 1;
		min-height: 300px;
		overflow: auto;
		font-family: var(--mg-mono);
		font-size: var(--mg-fs-xs);
		line-height: 1.65;
	}
	table {
		border-collapse: collapse;
		min-width: 100%;
	}
	tr:first-child td {
		padding-top: 10px;
	}
	tr:last-child td {
		padding-bottom: 10px;
	}
	.n {
		position: sticky;
		left: 0;
		width: 1%;
		padding: 0 12px 0 16px;
		border-right: 1px solid var(--mg-border);
		background: color-mix(in srgb, var(--mg-text) 4%, var(--mg-surface));
		color: var(--mg-text-3);
		text-align: right;
		user-select: none;
		vertical-align: top;
		font-variant-numeric: tabular-nums;
	}
	.l {
		padding: 0 16px;
		white-space: pre;
		color: var(--mg-text);
	}
	.wrap .l {
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
	.l.head {
		color: var(--mg-accent-ink);
		font-weight: 600;
	}
	tr.hit .l {
		background: color-mix(in srgb, var(--mg-warn) 20%, var(--mg-surface));
	}
	tr.hit .n {
		color: var(--mg-text);
		box-shadow: inset 3px 0 0 var(--mg-warn);
	}
	@container vw (max-width: 620px) {
		.find {
			flex-basis: 100%;
		}
	}
</style>
