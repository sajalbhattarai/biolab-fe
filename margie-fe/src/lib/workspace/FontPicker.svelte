<script lang="ts">
	/**
	 * Typeface list where each row is drawn in its own face and arrowing applies it live.
	 * Faces come from fonts.ts; missing ones are marked.
	 */
	import { tick } from 'svelte';
	import { FACES, KIND_NAMES, installed, type Face, type FontKind } from './fonts';

	let {
		value,
		onchange,
		only,
		id
	}: {
		value: string;
		onchange: (id: string) => void;
		/** Restricts the list, for the monospace picker. */
		only?: FontKind;
		id?: string;
	} = $props();

	let filter = $state<FontKind | 'all'>('all');
	let search = $state('');
	let box = $state<HTMLDivElement>();

	const KINDS: (FontKind | 'all')[] = ['all', 'sans', 'serif', 'mono', 'display'];

	const shown = $derived.by(() => {
		const q = search.trim().toLowerCase();
		return FACES.filter((f) => {
			if (only && f.kind !== only) return false;
			if (!only && filter !== 'all' && f.kind !== filter) return false;
			return !q || f.name.toLowerCase().includes(q);
		});
	});

	/** Availability is known only in the browser once fonts are ready. */
	let ready = $state(false);
	$effect(() => {
		document.fonts?.ready?.then(() => (ready = true)).catch(() => (ready = true));
	});

	const here = $derived(shown.findIndex((f) => f.id === value));

	async function go(next: number) {
		if (!shown.length) return;
		const i = Math.max(0, Math.min(shown.length - 1, next));
		onchange(shown[i].id);
		await tick();
		// Keeps the selection in view while arrowing.
		box?.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: 'nearest' });
	}

	function onKey(e: KeyboardEvent) {
		const at = here === -1 ? 0 : here;
		if (e.key === 'ArrowDown') return (e.preventDefault(), go(at + 1));
		if (e.key === 'ArrowUp') return (e.preventDefault(), go(at - 1));
		if (e.key === 'PageDown') return (e.preventDefault(), go(at + 8));
		if (e.key === 'PageUp') return (e.preventDefault(), go(at - 8));
		if (e.key === 'Home') return (e.preventDefault(), go(0));
		if (e.key === 'End') return (e.preventDefault(), go(shown.length - 1));
		// Typing a letter jumps to the next face starting with it.
		if (e.key.length === 1 && /[a-z0-9]/i.test(e.key) && !e.metaKey && !e.ctrlKey) {
			const from = at + 1;
			const order = [...shown.slice(from), ...shown.slice(0, from)];
			const found = order.find((f) => f.name.toLowerCase().startsWith(e.key.toLowerCase()));
			if (found) {
				e.preventDefault();
				go(shown.indexOf(found));
			}
		}
	}

	const missing = (f: Face) => ready && !installed(f);
</script>

<div class="picker">
	{#if !only}
		<div class="kinds" role="tablist" aria-label="Kind of typeface">
			{#each KINDS as k (k)}
				<button type="button" role="tab" aria-selected={filter === k} class="kind" onclick={() => (filter = k)}>
					{k === 'all' ? 'All' : KIND_NAMES[k]}
				</button>
			{/each}
		</div>
	{/if}

	<input class="mg-input find" bind:value={search} placeholder="Find a typeface" spellcheck="false" aria-label="Find a typeface" />

	<!-- Focusable as a whole so arrow keys work without tabbing through every row. -->
	<div
		class="list"
		{id}
		bind:this={box}
		role="listbox"
		tabindex="0"
		aria-label="Typeface"
		aria-activedescendant={here >= 0 ? `face-${shown[here].id}` : undefined}
		onkeydown={onKey}
	>
		{#each shown as f (f.id)}
			<div
				id="face-{f.id}"
				role="option"
				aria-selected={f.id === value}
				class="row"
				class:missing={missing(f)}
				style="font-family: {f.stack}"
				onclick={() => onchange(f.id)}
				onkeydown={(e) => e.key === 'Enter' && onchange(f.id)}
				tabindex="-1"
			>
				<span class="name">{f.name}</span>
				<span class="note">
					{#if f.bundled}included{:else if missing(f)}not on this Mac{:else}{KIND_NAMES[f.kind]}{/if}
				</span>
			</div>
		{/each}
		{#if !shown.length}
			<p class="none mg-note">No typeface matches “{search}”.</p>
		{/if}
	</div>

	<p class="hint mg-note">{shown.length} typefaces. Click the list, then use ↑ ↓ to try them.</p>
</div>

<style>
	.picker {
		display: flex;
		flex-direction: column;
		gap: 8px;
		min-width: 0;
	}
	/* Kinds as a row of chips. */
	.kinds {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
	}
	.kind {
		height: 28px;
		padding: 0 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		cursor: pointer;
		transition:
			border-color var(--mo-1) var(--mo-ease),
			color var(--mo-1) var(--mo-ease);
	}
	.kind:hover {
		border-color: color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		color: var(--mg-text);
	}
	.kind[aria-selected='true'] {
		border-color: var(--mg-accent);
		background: color-mix(in srgb, var(--mg-accent) 10%, var(--mg-surface));
		color: var(--mg-accent-ink);
		font-weight: 600;
	}
	.find {
		width: 100%;
	}
	/* Scrolls inside the settings rather than growing the page. */
	.list {
		max-height: 220px;
		overflow-y: auto;
		padding: 4px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: color-mix(in srgb, var(--mg-text) 3%, var(--mg-surface));
	}
	.list:focus-visible {
		outline: 2px solid var(--mg-accent);
		outline-offset: 1px;
	}
	.row {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 12px;
		padding: 6px 12px;
		border-radius: calc(var(--mg-r) - 2px);
		cursor: pointer;
		font-size: var(--mg-fs);
	}
	.row:hover {
		background: var(--mg-surface);
	}
	.row[aria-selected='true'] {
		background: var(--mg-accent-soft);
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--mg-accent) 35%, transparent);
		color: var(--mg-accent-ink);
	}
	.name {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.note {
		flex-shrink: 0;
		/* The note is in the interface font. */
		font-family: var(--mg-font);
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.row.missing .name {
		opacity: 0.55;
	}
	.none {
		padding: 10px;
	}
	.hint {
		font-size: var(--mg-fs-xs);
	}
</style>
