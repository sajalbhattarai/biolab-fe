<script lang="ts">
	import { ui } from '../ui.svelte';
	import Resizer from '../motion/Resizer.svelte';
	import { untrack } from 'svelte';
	import { cubicOut } from 'svelte/easing';
	import { fly } from 'svelte/transition';
	import { api } from '$lib/api';
	import './tools.css';
	import { ChevronLeft, ChevronRight, Columns3, ListFilter, Search, SlidersHorizontal, X } from 'lucide-svelte';
	import {
		TIER_COLOURS,
		categoryColour,
		defaultWidth,
		forgetLayout,
		formatNumber,
		heat,
		ink,
		isEmpty,
		loadLayout,
		plainName,
		saveLayout,
		tint,
		type CellStyle,
		type ColourMode,
		type ColumnInfo,
		type GridLayout
	} from './grid';
	import { categoryCount, dataColour } from '../vision';

	/**
	 * Paged table viewer (TSV, CSV, GFF, Excel) with sorting, column reorder, resize, hide, pin,
	 * filter and search; the layout is remembered per column set. `preset` adds an outside filter
	 * (plain column name and required value), as the Results page's Show chips do.
	 */
	let { path, preset = [] }: { path: string; preset?: { column: string; value: string }[] } = $props();

	interface Row {
		i: number;
		cells: string[];
		styles?: number[];
	}
	interface Page {
		kind: string;
		sheets: { name: string; rows: number }[];
		sheet: number;
		columns: ColumnInfo[];
		headerStyle?: CellStyle;
		frozen?: number;
		palette: Record<string, CellStyle>;
		total: number;
		filtered: number;
		page: number;
		pages: number;
		size: number;
		rows: Row[];
	}

	const ROWNUM = 56;

	let data = $state<Page | null>(null);
	let loading = $state(false);
	let error = $state('');
	let sheet = $state(0);
	let page = $state(1);
	let size = $state(100);
	let search = $state('');
	let q = $state('');
	let sort = $state<{ col: number; dir: 'asc' | 'desc' } | null>(null);
	let filters = $state<Record<number, string>>({});
	let showFilters = $state(false);
	let menu = $state<'columns' | 'view' | null>(null);
	let detail = $state<number | null>(null);

	let layout = $state<GridLayout>({ order: [], hidden: [], widths: {}, pinned: 0, density: 'comfortable', wrap: false, colour: null });
	let layoutFor = '';

	// ---- loading ----

	async function fetchPage() {
		loading = true;
		const params = new URLSearchParams({ path, sheet: String(sheet), page: String(page), size: String(size), q });
		if (sort) params.set('sort', `${sort.col}:${sort.dir}`);
		for (const [c, f] of Object.entries(filters)) if (f.trim()) params.set(`f${c}`, f);
		for (const [c, f] of JSON.parse(presetKey) as [number, string][]) params.set(`f${c}`, f);
		try {
			const d = await api<Page>(`/files/table?${params}`);
			if (d.page !== page) page = d.page;
			setup(d);
			data = d;
			error = '';
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		} finally {
			loading = false;
		}
	}

	/** The preset as [column index, filter] pairs, serialised so an unchanged preset is not a change. */
	const presetKey = $derived.by(() => {
		const cols = data?.columns ?? [];
		const pairs = preset
			.map((p) => [cols.findIndex((c) => plainName(c.name) === p.column), `=${p.value}`] as [number, string])
			.filter(([i]) => i >= 0);
		return JSON.stringify(pairs);
	});
	// A new preset resets to the first page.
	$effect(() => {
		void JSON.stringify(preset);
		untrack(() => (page = 1));
	});

	$effect(() => {
		void [path, sheet, page, size, q, sort?.col, sort?.dir, JSON.stringify(filters), presetKey];
		fetchPage();
	});

	// Debounced search.
	$effect(() => {
		const s = search;
		const t = setTimeout(() => {
			if (s !== q) {
				q = s;
				page = 1;
			}
		}, 250);
		return () => clearTimeout(t);
	});

	let filterTimer: ReturnType<typeof setTimeout> | null = null;
	function setFilter(col: number, value: string) {
		if (filterTimer) clearTimeout(filterTimer);
		filterTimer = setTimeout(() => {
			filters = { ...filters, [col]: value };
			page = 1;
		}, 300);
	}

	// ---- layout ----

	const layoutName = $derived(data ? `${data.kind}:${data.sheet}` : '');

	/** Applies the saved layout for a table's first load, or defaults. */
	function setup(d: Page) {
		const signature = `${d.kind}:${d.sheet}:${d.columns.map((c) => c.name).join('\t')}`;
		if (signature === layoutFor) return;
		layoutFor = signature;
		const n = d.columns.length;
		const saved = loadLayout(`${d.kind}:${d.sheet}`, d.columns);
		const valid = (i: unknown): i is number => Number.isInteger(i) && (i as number) >= 0 && (i as number) < n;
		const order = (saved.order ?? []).filter(valid);
		for (let i = 0; i < n; i++) if (!order.includes(i)) order.push(i);
		// Hides empty and constant columns by default.
		const quiet = d.columns.map((c, i) => (c.kind === 'empty' || (c.kind === 'category' && c.values?.length === 1) ? i : -1)).filter((i) => i >= 0);
		layout = {
			order,
			hidden: (saved.hidden ?? quiet).filter(valid),
			widths: saved.widths ?? {},
			pinned: saved.pinned ?? d.frozen ?? 0,
			density: saved.density ?? 'comfortable',
			wrap: saved.wrap ?? false,
			colour: saved.colour ?? null
		};
		detail = null;
	}

	function persist() {
		if (data) saveLayout(layoutName, data.columns, $state.snapshot(layout) as GridLayout);
	}

	function resetLayout() {
		if (!data) return;
		forgetLayout(layoutName, data.columns);
		layoutFor = '';
		setup(data);
		sort = null;
		filters = {};
		search = '';
	}

	const columns = $derived(data?.columns ?? []);
	const visible = $derived(layout.order.filter((i) => !layout.hidden.includes(i) && i < columns.length));
	const width = (i: number) => layout.widths[i] ?? defaultWidth(columns[i]);
	/** Left offsets of the pinned columns, after the row numbers. */
	const pinnedLeft = $derived.by(() => {
		const left = new Map<number, number>();
		let x = ROWNUM;
		for (const c of visible.slice(0, layout.pinned)) {
			left.set(c, x);
			x += width(c);
		}
		return left;
	});
	const tableWidth = $derived(ROWNUM + visible.reduce((a, c) => a + width(c), 0));

	function toggleHidden(i: number) {
		layout.hidden = layout.hidden.includes(i) ? layout.hidden.filter((x) => x !== i) : [...layout.hidden, i];
		persist();
	}

	// ---- colour ----

	const findColumn = (...names: string[]) => columns.findIndex((c) => names.includes(plainName(c.name).toLowerCase()));
	const tierCol = $derived(findColumn('confidence_tier_hybrid', 'confidence_tier'));
	const reviewCol = $derived(findColumn('needs_review?', 'needs_review'));
	const modes = $derived<{ value: ColourMode; label: string }[]>([
		...(data?.kind === 'xlsx' ? [{ value: 'excel' as const, label: 'Excel' }] : []),
		...(tierCol >= 0 ? [{ value: 'tier' as const, label: 'Confidence' }] : []),
		{ value: 'values', label: 'Values' },
		{ value: 'off', label: 'Off' }
	]);
	const colour = $derived<ColourMode>(
		layout.colour && modes.some((m) => m.value === layout.colour) ? layout.colour : (modes[0]?.value ?? 'values')
	);

	/** Adapts a workbook colour to the reader's colour vision (vision.ts, dataColour). */
	const workbookColour = (hex: string) => dataColour(hex, ui.prefs.vision, ui.prefs.visionStrength);
	const cats = $derived(categoryCount(ui.prefs.vision));

	/** Row colour from its confidence tier, as in the Excel file and figures. */
	function rowTone(row: Row): { bg: string; fg?: string } | null {
		if (colour !== 'tier' || tierCol < 0) return null;
		const t = TIER_COLOURS[(row.cells[tierCol] ?? '').trim().toLowerCase()];
		return t ? { bg: tint(t, 20) } : { bg: 'var(--mg-surface-2)', fg: 'var(--mg-text-3)' };
	}
	const review = (row: Row) => colour === 'tier' && reviewCol >= 0 && /^y(es)?$/i.test((row.cells[reviewCol] ?? '').trim());

	function cellStyle(row: Row, c: number, idx: number): string {
		const col = columns[c];
		const parts: string[] = [];
		const left = pinnedLeft.get(c);
		if (left !== undefined) parts.push(`left:${left}px`);
		let bg = '';
		let fg = '';
		if (colour === 'excel' && row.styles) {
			const s = data?.palette[row.styles[c]];
			if (s?.bg) bg = workbookColour(s.bg);
			if (s?.fg) fg = workbookColour(s.fg);
			if (s?.bold) parts.push('font-weight:600');
			// Workbook borders, drawn lighter than Excel's "medium" line.
			if (s?.border) for (const e of s.border) parts.push(`border-${{ t: 'top', r: 'right', b: 'bottom', l: 'left' }[e]}:1px solid rgba(0,0,0,.45)`);
		} else if (colour === 'values' && col.kind === 'number') {
			const h = heat(row.cells[c] ?? '', col);
			if (h !== null) bg = `color-mix(in srgb, var(--mg-accent) ${Math.round(4 + h * 34)}%, var(--mg-surface))`;
		}
		if (!bg) {
			const tone = rowTone(row);
			if (tone) {
				bg = tone.bg;
				if (tone.fg) fg = tone.fg;
			} else bg = idx % 2 ? 'var(--mg-row-alt)' : 'var(--mg-surface)';
		}
		parts.push(`background:${bg}`);
		if (fg) parts.push(`color:${fg}`);
		return parts.join(';');
	}

	const headerStyle = (c: number) => {
		const left = pinnedLeft.get(c);
		const h = colour === 'excel' ? data?.headerStyle : undefined;
		return [left !== undefined ? `left:${left}px` : '', h?.bg ? `background:${workbookColour(h.bg)}` : '', h?.fg ? `color:${workbookColour(h.fg)}` : ''].filter(Boolean).join(';');
	};

	// ---- sorting, moving, resizing ----

	let resizing = false;
	let dragCol = $state<number | null>(null);
	let dropCol = $state<number | null>(null);

	function sortBy(c: number) {
		if (resizing) return;
		sort = sort?.col !== c ? { col: c, dir: 'asc' } : sort.dir === 'asc' ? { col: c, dir: 'desc' } : null;
		page = 1;
	}

	function move(from: number, to: number) {
		if (from === to) return;
		const order = layout.order.filter((i) => i !== from);
		const at = order.indexOf(to);
		const after = layout.order.indexOf(from) < layout.order.indexOf(to);
		order.splice(after ? at + 1 : at, 0, from);
		layout.order = order;
		persist();
	}

	function startResize(e: PointerEvent, c: number) {
		e.preventDefault();
		e.stopPropagation();
		resizing = true;
		const x0 = e.clientX;
		const w0 = width(c);
		const onMove = (ev: PointerEvent) => (layout.widths = { ...layout.widths, [c]: Math.max(48, Math.round(w0 + ev.clientX - x0)) });
		const onUp = () => {
			window.removeEventListener('pointermove', onMove);
			persist();
			setTimeout(() => (resizing = false));
		};
		window.addEventListener('pointermove', onMove);
		window.addEventListener('pointerup', onUp, { once: true });
	}

	/** Double-click on an edge fits the column to its title and this page's values. */
	function fit(c: number) {
		const lens = [plainName(columns[c].name).length + 3, ...(data?.rows ?? []).map((r) => shown(r.cells[c] ?? '', columns[c]).length)];
		layout.widths = { ...layout.widths, [c]: Math.round(Math.min(520, Math.max(56, Math.max(...lens) * 7.4 + 26))) };
		persist();
	}

	const shown = (v: string, col: ColumnInfo) => (isEmpty(v) ? '—' : col.kind === 'number' ? formatNumber(v) : v);

	// ---- keyboard ----

	function keydown(e: KeyboardEvent) {
		if (e.key === 'Escape') {
			if (menu) menu = null;
			else if (detail !== null) detail = null;
			return;
		}
		if (detail === null || !data || (e.target as HTMLElement)?.closest('input, select, textarea')) return;
		if (e.key === 'ArrowDown' || e.key === 'j') {
			e.preventDefault();
			detail = Math.min(data.rows.length - 1, detail + 1);
		} else if (e.key === 'ArrowUp' || e.key === 'k') {
			e.preventDefault();
			detail = Math.max(0, detail - 1);
		}
	}

	const detailRow = $derived(detail !== null ? data?.rows[detail] : undefined);
	let copied = $state(-1);
	async function copy(text: string, c: number) {
		try {
			await navigator.clipboard.writeText(text);
			copied = c;
			setTimeout(() => (copied = -1), 1500);
		} catch {
			// the value stays selectable by hand
		}
	}
</script>

<svelte:window onkeydown={keydown} onclick={(e) => menu && !(e.target as HTMLElement).closest('.menu, .menu-btn') && (menu = null)} />

<div class="data-grid vw-scope" class:compact={layout.density === 'compact'}>
	{#if data && data.sheets.length > 1}
		<div class="sheets vw-group" role="tablist" aria-label="Sheets">
			{#each data.sheets as s, i (s.name)}
				<button
					type="button"
					role="tab"
					class="vw-btn sheet"
					aria-selected={sheet === i}
					onclick={() => {
						sheet = i;
						page = 1;
						sort = null;
						filters = {};
					}}>{s.name} <span class="n">{s.rows.toLocaleString('en-US')}</span></button
				>
			{/each}
		</div>
	{/if}

	<div class="vw-bar bar">
		<label class="vw-field search">
			<Search size={15} />
			<input type="search" placeholder="Search all columns" aria-label="Search all columns" bind:value={search} />
		</label>
		<div class="vw-group" role="group" aria-label="Table tools">
			<button type="button" class="vw-btn" title="Filter by column" aria-pressed={showFilters} onclick={() => (showFilters = !showFilters)}><ListFilter size={14} /><span class="vw-lbl">Filters</span></button>
			<span class="pop-anchor">
				<button type="button" class="vw-btn menu-btn" title="Columns" aria-pressed={menu === 'columns'} onclick={() => (menu = menu === 'columns' ? null : 'columns')}>
					<Columns3 size={14} /><span class="vw-lbl">Columns</span>
				</button>
			{#if menu === 'columns' && data}
				<div class="menu cols" role="dialog" aria-label="Columns">
					<div class="menu-head">
						<span class="mg-label">Drag to reorder, tick to show</span>
						<span class="mg-grow"></span>
						<button type="button" class="vw-pill sm" onclick={() => ((layout.hidden = []), persist())}>Show all</button>
					</div>
					<ul>
						{#each layout.order as c (c)}
							<li
								draggable="true"
								class:drop={dropCol === c && dragCol !== c}
								ondragstart={() => (dragCol = c)}
								ondragover={(e) => {
									e.preventDefault();
									dropCol = c;
								}}
								ondrop={(e) => {
									e.preventDefault();
									if (dragCol !== null) move(dragCol, c);
									dragCol = dropCol = null;
								}}
								ondragend={() => (dragCol = dropCol = null)}
							>
								<span class="handle" aria-hidden="true">⋮⋮</span>
								<label>
									<input type="checkbox" checked={!layout.hidden.includes(c)} onchange={() => toggleHidden(c)} />
									<span title={columns[c].name}>{plainName(columns[c].name)}</span>
								</label>
								<span class="kind">{columns[c].kind === 'empty' ? 'empty' : columns[c].kind}</span>
							</li>
						{/each}
					</ul>
					<div class="menu-foot">
						<label class="mg-label" for="pinned">Keep in view</label>
						<select id="pinned" class="mg-select" bind:value={layout.pinned} onchange={persist}>
							{#each [0, 1, 2, 3, 4, 5] as n (n)}<option value={n}>{n === 0 ? 'Row numbers only' : `First ${n} column${n === 1 ? '' : 's'}`}</option>{/each}
						</select>
						<span class="mg-grow"></span>
						<button type="button" class="vw-pill sm" onclick={resetLayout}>Reset layout</button>
					</div>
				</div>
			{/if}
			</span>
			<span class="pop-anchor">
				<button type="button" class="vw-btn menu-btn" title="View" aria-pressed={menu === 'view'} onclick={() => (menu = menu === 'view' ? null : 'view')}><SlidersHorizontal size={14} /><span class="vw-lbl">View</span></button>
			{#if menu === 'view'}
				<div class="menu view" role="dialog" aria-label="View">
					<span class="mg-label">Colour</span>
					<div class="vw-group fill" role="radiogroup" aria-label="Colour">
						{#each modes as m (m.value)}
							<button type="button" role="radio" class="vw-btn" class:on={colour === m.value} aria-checked={colour === m.value} onclick={() => ((layout.colour = m.value), persist())}>{m.label}</button>
						{/each}
					</div>
					<span class="mg-note explain">
						{colour === 'excel'
							? "The workbook's own colours."
							: colour === 'tier'
								? 'Each row in its confidence tier colour, as in the Excel file; ⚑ marks rows needing review.'
								: colour === 'values'
									? 'Categories as coloured labels; numbers shaded from low to high.'
									: 'Plain rows.'}
					</span>
					<span class="mg-label">Rows</span>
					<div class="vw-group fill" role="radiogroup" aria-label="Rows">
						{#each [['compact', 'Compact'], ['comfortable', 'Comfortable']] as [v, l] (v)}
							<button type="button" role="radio" class="vw-btn" class:on={layout.density === v} aria-checked={layout.density === v} onclick={() => ((layout.density = v as GridLayout['density']), persist())}>{l}</button>
						{/each}
					</div>
					<span class="mg-label">Long text</span>
					<div class="vw-group fill" role="radiogroup" aria-label="Long text">
						<button type="button" role="radio" class="vw-btn" class:on={!layout.wrap} aria-checked={!layout.wrap} onclick={() => ((layout.wrap = false), persist())}>Cut short</button>
						<button type="button" role="radio" class="vw-btn" class:on={layout.wrap} aria-checked={layout.wrap} onclick={() => ((layout.wrap = true), persist())}>Wrap</button>
					</div>
				</div>
			{/if}
			</span>
		</div>
		<span class="vw-grow"></span>
		<span class="count" class:loading>
			<i aria-hidden="true"></i>
			{#if data}
				{data.filtered === data.total ? `${data.total.toLocaleString('en-US')} rows` : `${data.filtered.toLocaleString('en-US')} of ${data.total.toLocaleString('en-US')} rows`}
			{/if}
		</span>
		<div class="vw-group" role="group" aria-label="Pages">
			<select aria-label="Rows per page" bind:value={size} onchange={() => (page = 1)}>
				{#each [50, 100, 250, 500] as n (n)}<option value={n}>{n} a page</option>{/each}
			</select>
			<button type="button" class="vw-btn icon" aria-label="Previous page" title="Previous page" disabled={!data || page <= 1} onclick={() => page--}><ChevronLeft size={16} /></button>
			<span class="vw-num">{data ? `${data.page.toLocaleString('en-US')} of ${data.pages.toLocaleString('en-US')}` : ''}</span>
			<button type="button" class="vw-btn icon" aria-label="Next page" title="Next page" disabled={!data || page >= data.pages} onclick={() => page++}><ChevronRight size={16} /></button>
		</div>
	</div>

	{#if error}
		<p class="vw-pane vw-msg bad">{error}</p>
	{:else if data}
		<div class="body vw-pane">
			<div class="scroller">
				<table style="width:{tableWidth}px">
					<colgroup>
						<col style="width:{ROWNUM}px" />
						{#each visible as c (c)}<col style="width:{width(c)}px" />{/each}
					</colgroup>
					<thead>
						<tr>
							<th class="rownum pin" style="left:0">#</th>
							{#each visible as c (c)}
								<th
									class:pin={pinnedLeft.has(c)}
									class:drop={dropCol === c && dragCol !== c}
									class:num={columns[c].kind === 'number'}
									style={headerStyle(c)}
									title={columns[c].name}
									draggable="true"
									aria-sort={sort?.col === c ? (sort.dir === 'asc' ? 'ascending' : 'descending') : 'none'}
									ondragstart={(e) => {
										if (resizing) return e.preventDefault();
										dragCol = c;
									}}
									ondragover={(e) => {
										e.preventDefault();
										dropCol = c;
									}}
									ondrop={(e) => {
										e.preventDefault();
										if (dragCol !== null) move(dragCol, c);
										dragCol = dropCol = null;
									}}
									ondragend={() => (dragCol = dropCol = null)}
								>
									<button type="button" class="sort" onclick={() => sortBy(c)}>
										<span class="field-label">{plainName(columns[c].name)}</span>
										{#if sort?.col === c}<span class="arrow">{sort.dir === 'asc' ? '↑' : '↓'}</span>{/if}
									</button>
									<span
										class="col-resize-handle"
										role="separator"
										aria-orientation="vertical"
										aria-label="Resize {plainName(columns[c].name)}"
										onpointerdown={(e) => startResize(e, c)}
										ondblclick={() => fit(c)}
									></span>
								</th>
							{/each}
						</tr>
						{#if showFilters}
							<tr class="filters">
								<th class="rownum pin" style="left:0"></th>
								{#each visible as c (c)}
									{@const col = columns[c]}
									<th class:pin={pinnedLeft.has(c)} style={pinnedLeft.has(c) ? `left:${pinnedLeft.get(c)}px` : ''}>
										{#if col.kind === 'category' && col.values}
											<select class="mg-select" aria-label="Filter {plainName(col.name)}" value={filters[c] ? filters[c].replace(/^=/, '') : ''} onchange={(e) => setFilter(c, e.currentTarget.value ? `=${e.currentTarget.value}` : '')}>
												<option value="">All</option>
												{#each col.values as v (v)}<option value={v}>{v}</option>{/each}
											</select>
										{:else}
											<input
												class="mg-input"
												aria-label="Filter {plainName(col.name)}"
												placeholder={col.kind === 'number' ? '>5 or 1..10' : 'contains'}
												value={filters[c] ?? ''}
												oninput={(e) => setFilter(c, e.currentTarget.value)}
											/>
										{/if}
									</th>
								{/each}
							</tr>
						{/if}
					</thead>
					<tbody>
						{#each data.rows as row, idx (row.i)}
							<tr class:review={review(row)} class:open={detail === idx} onclick={() => (detail = idx)}>
								<td class="rownum pin" style="left:0" title={review(row) ? 'Needs review' : undefined}>
									{#if review(row)}<span class="flag" aria-label="Needs review">⚑</span>{/if}{row.i + 1}
								</td>
								{#each visible as c (c)}
									{@const col = columns[c]}
									{@const v = row.cells[c] ?? ''}
									<td class="k-{col.kind}" class:pin={pinnedLeft.has(c)} class:wrap={layout.wrap} style={cellStyle(row, c, idx)} title={v.length > 40 ? v.slice(0, 400) : v}>
										{#if isEmpty(v)}<span class="nil">—</span>
										{:else if col.kind === 'category' && (colour === 'values' || colour === 'tier')}
											{@const cc = categoryColour(v, col, cats)}
											<span class="cell-chip" style="background:{tint(cc, 22)};color:{ink(cc)}">{v}</span>
										{:else}{shown(v, col)}{/if}
									</td>
								{/each}
							</tr>
						{:else}
							<tr><td class="none" colspan={visible.length + 1}>No rows match.</td></tr>
						{/each}
					</tbody>
				</table>
			</div>

			{#if detailRow}
				<aside
					class="detail"
					aria-label="Row {detailRow.i + 1}"
					style="width: min({ui.size('grid:detail', 400)}px, 70%)"
					transition:fly={{ x: 24, duration: ui.ms(260), easing: cubicOut }}
				>
					<Resizer id="grid:detail" fallback={400} min={260} max={760} edge="left" label="Resize the row details" />
					<header>
						<strong>Row {(detailRow.i + 1).toLocaleString('en-US')}</strong>
						<span class="vw-grow"></span>
						<div class="vw-group" role="group" aria-label="Row">
							<button type="button" class="vw-btn icon" aria-label="Previous row" title="Previous row (↑)" disabled={detail === 0} onclick={() => detail !== null && detail--}><ChevronLeft size={16} /></button>
							<button type="button" class="vw-btn icon" aria-label="Next row" title="Next row (↓)" disabled={detail === data.rows.length - 1} onclick={() => detail !== null && detail++}><ChevronRight size={16} /></button>
							<button type="button" class="vw-btn icon" aria-label="Close" title="Close (Esc)" onclick={() => (detail = null)}><X size={15} /></button>
						</div>
					</header>
					<dl>
						{#each layout.order as c (c)}
							{@const col = columns[c]}
							{@const v = detailRow.cells[c] ?? ''}
							<div class:dim={layout.hidden.includes(c)}>
								<dt title={col.name}>{plainName(col.name)}</dt>
								<dd class:seq={col.kind === 'sequence'}>
									{#if isEmpty(v)}<span class="nil">—</span>
									{:else if col.kind === 'category'}
										{@const cc = categoryColour(v, col, cats)}
										<span class="cell-chip" style="background:{tint(cc, 22)};color:{ink(cc)}">{v}</span>
									{:else}{col.kind === 'number' ? formatNumber(v) : v}{/if}
									{#if col.kind === 'sequence' && !isEmpty(v)}
										<button type="button" class="mg-link copy" onclick={() => copy(v, c)}>{copied === c ? 'Copied' : `Copy ${v.length.toLocaleString('en-US')} letters`}</button>
									{/if}
								</dd>
							</div>
						{/each}
					</dl>
				</aside>
			{/if}
		</div>
	{:else}
		<p class="vw-pane vw-msg body">Loading…</p>
	{/if}
</div>

<style>
	.data-grid {
		--row-h: 34px;
		--mg-row-alt: color-mix(in srgb, var(--mg-surface-2) 55%, var(--mg-surface));
		display: flex;
		flex-direction: column;
		gap: 12px;
		height: 100%;
		min-height: 0;
		font-size: var(--mg-fs-sm);
	}
	.data-grid.compact {
		--row-h: 26px;
	}
	.sheets {
		align-self: flex-start;
		max-width: 100%;
		overflow-x: auto;
		scrollbar-width: none;
	}
	.sheet .n {
		padding: 0 7px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 8%, transparent);
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-3);
	}
	.search {
		flex: 0 1 300px;
	}
	.count {
		display: inline-flex;
		align-items: center;
		gap: 7px;
		font-size: var(--mg-fs-xs);
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-2);
		white-space: nowrap;
	}
	.count i {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: var(--mg-ok);
	}
	.count.loading i {
		background: var(--mg-accent);
	}
	.pop-anchor {
		position: relative;
		height: 100%;
		display: inline-flex;
	}
	.menu {
		position: absolute;
		top: calc(100% + 10px);
		left: 0;
		z-index: 20;
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 14px;
		border: 1px solid var(--mg-border-strong);
		border-radius: var(--mg-r);
		background: var(--mg-surface);
		box-shadow: var(--mg-shadow-lg);
		font-size: var(--mg-fs-sm);
		animation: dg-pop 160ms cubic-bezier(0.2, 0.7, 0.2, 1) both;
	}
	.menu.cols {
		width: 380px;
		max-height: 70vh;
	}
	.menu.view {
		width: 330px;
	}
	.menu .vw-group.fill {
		display: flex;
		width: 100%;
	}
	.menu .vw-group.fill .vw-btn {
		flex: 1 1 0;
	}
	.explain {
		font-size: var(--mg-fs-xs);
	}
	.menu-head,
	.menu-foot {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.menu-foot .mg-select {
		border-radius: var(--mg-r-sm);
	}
	.menu ul {
		overflow: auto;
		margin: 0 -6px;
		padding: 4px 0;
		border-top: 1px solid var(--mg-border);
		border-bottom: 1px solid var(--mg-border);
	}
	.menu li {
		display: flex;
		align-items: center;
		gap: 8px;
		min-height: 32px;
		padding: 0 8px;
		border-top: 2px solid transparent;
		border-radius: var(--mg-r-sm);
		cursor: grab;
	}
	.menu li:hover {
		background: color-mix(in srgb, var(--mg-text) 5%, transparent);
	}
	.menu li.drop {
		border-top-color: var(--mg-accent);
	}
	.menu li label {
		flex-grow: 1;
		display: flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
		cursor: pointer;
	}
	.menu li label span {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.menu input[type='checkbox'] {
		accent-color: var(--mg-accent);
	}
	.handle {
		color: var(--mg-text-3);
		letter-spacing: -2px;
		font-size: 11px;
	}
	.kind {
		padding: 0 8px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 7%, transparent);
		color: var(--mg-text-3);
		font-size: var(--mg-fs-xs);
	}

	/* ---- table ---- */
	.body {
		position: relative;
		flex-grow: 1;
		min-height: 260px;
		display: flex;
	}
	.scroller {
		flex-grow: 1;
		min-width: 0;
		overflow: auto;
	}
	table {
		table-layout: fixed;
		border-collapse: separate;
		border-spacing: 0;
	}
	th,
	td {
		height: var(--row-h);
		padding: 0 10px;
		border-bottom: 1px solid var(--mg-border);
		border-right: 1px solid color-mix(in srgb, var(--mg-border) 60%, transparent);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		text-align: left;
		vertical-align: middle;
	}
	thead th {
		position: sticky;
		top: 0;
		z-index: 2;
		border-bottom-color: var(--mg-border-strong);
		background: var(--cr-head-bg, var(--mg-surface-2));
		color: var(--mg-text-2);
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		letter-spacing: 0.01em;
		user-select: none;
	}
	thead tr.filters th {
		top: var(--row-h);
		padding: 3px 6px;
	}
	thead tr.filters .mg-input,
	thead tr.filters .mg-select {
		width: 100%;
		height: calc(var(--row-h) - 8px);
	}
	th.drop {
		box-shadow: inset 2px 0 0 var(--mg-accent);
	}
	.pin {
		position: sticky;
		z-index: 1;
	}
	thead .pin {
		z-index: 3;
	}
	td.pin {
		box-shadow: 1px 0 0 var(--mg-border-strong);
	}
	.rownum {
		color: var(--mg-text-3);
		font-variant-numeric: tabular-nums;
		font-size: var(--mg-fs-xs);
		text-align: right;
		background: var(--cr-head-bg, var(--mg-surface-2));
	}
	td.rownum {
		background: var(--mg-surface);
	}
	.sort {
		display: flex;
		align-items: center;
		gap: 4px;
		width: 100%;
		height: 100%;
		padding: 0;
		border: none;
		background: none;
		color: inherit;
		font: inherit;
		cursor: pointer;
		text-align: left;
	}
	th.num .sort {
		justify-content: flex-end;
	}
	.field-label {
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.arrow {
		color: var(--mg-text);
	}
	th {
		position: sticky;
	}
	.col-resize-handle {
		position: absolute;
		top: 0;
		right: -3px;
		width: 7px;
		height: 100%;
		cursor: col-resize;
		z-index: 4;
	}
	.col-resize-handle:hover {
		background: var(--mg-accent);
		opacity: 0.4;
	}
	tbody tr {
		cursor: pointer;
	}
	tbody tr:hover td {
		filter: brightness(0.96);
	}
	:global([data-theme='dark']) tbody tr:hover td {
		filter: brightness(1.18);
	}
	tbody tr.open td {
		box-shadow: inset 0 2px 0 var(--mg-accent), inset 0 -2px 0 var(--mg-accent);
	}
	.flag {
		margin-right: 4px;
		color: var(--mg-danger);
	}
	td.k-number {
		text-align: right;
		font-variant-numeric: tabular-nums;
	}
	td.k-sequence {
		font-family: var(--mg-mono);
		font-size: var(--mg-fs-xs);
		letter-spacing: 0.02em;
	}
	td.wrap.k-text {
		white-space: normal;
		overflow-wrap: anywhere;
		line-height: 1.35;
		padding-top: 5px;
		padding-bottom: 5px;
	}
	.cell-chip {
		display: inline-block;
		max-width: 100%;
		padding: 1px 8px;
		border-radius: var(--mg-r-sm);
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		overflow: hidden;
		text-overflow: ellipsis;
		vertical-align: middle;
	}
	.nil {
		color: var(--mg-text-3);
	}
	.none {
		padding: 20px;
		color: var(--mg-text-3);
	}

	/* ---- row details ---- */
	.detail {
		position: relative;
		flex-shrink: 0;
		display: flex;
		flex-direction: column;
		border-left: 1px solid var(--mg-border);
		background: var(--mg-surface);
	}
	.detail header {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: 8px 10px 8px 16px;
		border-bottom: 1px solid var(--mg-border);
		background: var(--cr-head-bg, var(--mg-surface-2));
	}
	.detail dl {
		overflow: auto;
		padding: 4px 14px 14px;
	}
	.detail dl div {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: 8px 0;
		border-bottom: 1px solid var(--mg-border);
	}
	.detail dl div.dim dt::after {
		content: ' | hidden';
		color: var(--mg-text-3);
		font-weight: 400;
	}
	.detail dt {
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		color: var(--mg-text-2);
	}
	.detail dd {
		overflow-wrap: anywhere;
		line-height: 1.45;
	}
	.detail dd.seq {
		font-family: var(--mg-mono);
		font-size: var(--mg-fs-xs);
		max-height: 140px;
		overflow: auto;
	}
	.copy {
		display: block;
		margin-top: 4px;
		font-family: var(--mg-font);
		font-size: var(--mg-fs-xs);
	}
	@keyframes dg-pop {
		from {
			opacity: 0;
			transform: translateY(-4px);
		}
	}
	:global([data-motion='off']) .data-grid * {
		animation: none !important;
	}
	@container vw (max-width: 760px) {
		.search {
			flex-basis: 100%;
		}
		/* Menus open under the whole bar, as wide as the pane allows. */
		.bar {
			position: relative;
		}
		.pop-anchor {
			position: static;
		}
		.menu {
			max-width: 100%;
		}
	}
	@media (max-width: 760px) {
		.detail :global(.mo-resizer) {
			display: none;
		}
		.detail {
			position: absolute;
			inset: 0 0 0 auto;
			width: 90% !important;
			z-index: 5;
			box-shadow: var(--mg-shadow-lg);
		}
	}
</style>
