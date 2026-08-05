<script lang="ts">
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';

	function getApiUrl() {
		if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
			return 'http://localhost:8000';
		}
		return '';
	}

	function handle401() { clearToken(); goto('/login'); }

	let jobId = $derived($page.params.jobid);
	let filePath = $derived($page.url.searchParams.get('path') ?? '');
	let fileName = $derived(filePath.split('/').pop() ?? filePath);
	let isImageFile = $derived(/\.(png|jpe?g|gif|webp|svg)$/i.test(fileName));
	let isTabularFile = $derived(/\.(tsv|csv)$/i.test(fileName));
	// Anything that is neither an image nor a clean delimited table is shown in
	// the themed text viewer: .txt/.log/.json/.yaml/.gff/.faa/.fna/.err/... and
	// unknown extensions alike. A binary sniff downgrades to a download prompt.
	let viewMode = $derived(isImageFile ? 'image' : isTabularFile ? 'table' : 'text');

	let imageUrl = $state('');
	let imageError = $state('');

	async function loadImage() {
		const path = filePath;
		if (!path) { error = 'No file specified'; loading = false; return; }
		loading = true;
		error = '';
		imageError = '';
		try {
			const apiUrl = getApiUrl();
			const params = new URLSearchParams({ path, format: 'raw' });
			const res = await fetch(`${apiUrl}/v1/ssh/download_file/${jobId}?${params}`, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) throw new Error('Failed to load image');
			// A plain <img src="/v1/ssh/..."> cannot send the auth header, so
			// fetch the bytes with auth and render them from an object URL.
			if (imageUrl) URL.revokeObjectURL(imageUrl);
			imageUrl = URL.createObjectURL(await res.blob());
		} catch (e) {
			imageError = e instanceof Error ? e.message : 'Failed to load image';
		} finally {
			loading = false;
		}
	}

	// --- Plain-text viewer -------------------------------------------------
	// Renders any non-image, non-table file in a dark, high-contrast code panel
	// with line numbers and light per-line colouring. Content is fetched as raw
	// bytes so a NUL-byte sniff can catch binaries before we try to decode them.
	const TEXT_LINE_CAP = 5000; // keep the DOM (and the tab) responsive
	let textLines = $state<string[]>([]);
	let textError = $state('');
	let looksBinary = $state(false);
	let textTruncated = $state(false);
	let wrapText = $state(false);

	async function loadText() {
		const path = filePath;
		if (!path) { error = 'No file specified'; loading = false; return; }
		loading = true;
		error = '';
		textError = '';
		looksBinary = false;
		textTruncated = false;
		try {
			const apiUrl = getApiUrl();
			const params = new URLSearchParams({ path, format: 'raw' });
			const res = await fetch(`${apiUrl}/v1/ssh/download_file/${jobId}?${params}`, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) throw new Error('Failed to load file');
			const bytes = new Uint8Array(await res.arrayBuffer());
			// A NUL byte in the first 8 KB is a reliable "this is binary" signal.
			if (bytes.subarray(0, 8192).includes(0)) { looksBinary = true; return; }
			const decoded = new TextDecoder('utf-8').decode(bytes).replace(/\r\n?/g, '\n');
			const lines = decoded.split('\n');
			if (lines.length > TEXT_LINE_CAP) {
				textTruncated = true;
				textLines = lines.slice(0, TEXT_LINE_CAP);
			} else {
				textLines = lines;
			}
		} catch (e) {
			textError = e instanceof Error ? e.message : 'Failed to load file';
		} finally {
			loading = false;
		}
	}

	// Cheap, safe per-line tinting -- no HTML is injected, only a class is chosen,
	// so Svelte still escapes every character of the line.
	function lineClass(line: string): string {
		const t = line.trimStart();
		if (!t) return '';
		if (t.startsWith('>')) return 'text-cyan-300 font-semibold';        // FASTA header
		if (/^(#|;|\/\/)/.test(t)) return 'text-emerald-300/80';            // comment
		if (/\b(error|fail(ed|ure)?|traceback|exception|fatal)\b/i.test(line)) return 'text-red-300';
		if (/\b(warn(ing)?|deprecat)\b/i.test(line)) return 'text-amber-300';
		if (/\b(info|notice|success|done|complete[d]?)\b/i.test(line)) return 'text-sky-300';
		return '';
	}

	const PAGE_SIZE_OPTIONS = [50, 100, 250, 500];
	const TRUNCATE_AT = 200;
	const BOOLEAN_PATTERN = /^(true|false|t|f|yes|no)$/i;
	const TRUTHY_PATTERN = /^(true|t|yes)$/i;
	const ID_PATTERN = /^[A-Za-z0-9_.-]+$/;

	const COLUMN_TINTS = [
		'bg-blue-500/10',
		'bg-green-500/10',
		'bg-amber-500/10',
		'bg-purple-500/10',
		'bg-pink-500/10',
		'bg-cyan-500/10',
	];

	function columnTint(index: number): string {
		return COLUMN_TINTS[index % COLUMN_TINTS.length];
	}

	// Figure-matching palette (reportfig_lib.CONF_TIER_COLOR) so the key "answer"
	// columns read the SAME colours as the operon-diagram figures and the Excel.
	const TIER_COLOR: Record<string, string> = {
		highest: '#1f77ff', high: '#00b84d', medium: '#ffcc00', fair: '#ff8c00', low: '#ee2233',
	};
	function hexLum(h: string): number {
		const s = h.replace('#', '');
		return (0.299 * parseInt(s.slice(0, 2), 16) + 0.587 * parseInt(s.slice(2, 4), 16) + 0.114 * parseInt(s.slice(4, 6), 16)) / 255;
	}
	function contrastFg(h: string): string {
		return hexLum(h) > 0.55 ? '#111111' : '#ffffff';
	}
	function normCol(name: string): string {
		return name.replace(/^(?:\[[A-Z]+\]-|Column-[A-Z]+:\s*)/i, '').trim().toLowerCase();
	}
	// Bright pill {bg,fg} for a value in a tier / review / context column, else null.
	function pillStyle(colName: string, value: string): { bg: string; fg: string } | null {
		const c = normCol(colName);
		const v = value.trim().toLowerCase();
		if (c === 'confidence_tier' || c === 'confidence_tier_hybrid') {
			const bg = TIER_COLOR[v];
			if (bg) return { bg, fg: contrastFg(bg) };
		}
		if (c === 'needs_review?' || c === 'needs_review') {
			if (v === 'yes') return { bg: '#ee2233', fg: '#ffffff' };
			if (v === 'no') return { bg: '#1e9e57', fg: '#ffffff' };
		}
		if (c === 'does_operon_context_improve_confidence?') {
			if (v.includes('increase')) return { bg: '#6b8e23', fg: '#ffffff' };
			if (v.includes('decrease')) return { bg: '#8b0000', fg: '#ffffff' };
		}
		return null;
	}

	let currentPage = $state(1);
	let pageSize = $state(100);
	let columns = $state<string[]>([]);
	let rows = $state<string[][]>([]);
	let totalRows = $state(0);
	let totalPages = $state(1);
	let loading = $state(true);
	let error = $state('');
	let downloadFormat = $state<'raw' | 'excel'>('raw');
	let downloading = $state(false);
	let downloadError = $state('');

	async function fetchPage() {
		const path = filePath;
		const requestedPage = currentPage;
		const requestedSize = pageSize;
		const id = jobId;

		if (!path) {
			error = 'No file specified';
			loading = false;
			return;
		}

		loading = true;
		error = '';
		try {
			const apiUrl = getApiUrl();
			const params = new URLSearchParams({
				path,
				page: String(requestedPage),
				page_size: String(requestedSize),
			});
			const res = await fetch(`${apiUrl}/v1/ssh/view_file/${id}?${params}`, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) throw new Error('Failed to load file');
			const data = await res.json();
			columns = data.columns;
			rows = data.rows;
			totalRows = data.total_rows;
			totalPages = data.total_pages;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load file';
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		if (viewMode === 'image') {
			loadImage();
		} else if (viewMode === 'table') {
			fetchPage();
		} else {
			loadText();
		}
	});

	function prevPage() {
		if (currentPage > 1) currentPage -= 1;
	}

	function nextPage() {
		if (currentPage < totalPages) currentPage += 1;
	}

	function isBoolean(value: string): boolean {
		return BOOLEAN_PATTERN.test(value.trim());
	}

	function isTruthy(value: string): boolean {
		return TRUTHY_PATTERN.test(value.trim());
	}

	function isIdLike(value: string): boolean {
		return ID_PATTERN.test(value) && !value.includes(' ');
	}

	function displayValue(value: string): string {
		return value.length > TRUNCATE_AT ? `${value.slice(0, TRUNCATE_AT)}…` : value;
	}

	async function downloadFile() {
		const path = filePath;
		if (!path) return;

		downloading = true;
		downloadError = '';
		try {
			const apiUrl = getApiUrl();
			const params = new URLSearchParams({ path, format: downloadFormat });
			const res = await fetch(`${apiUrl}/v1/ssh/download_file/${jobId}?${params}`, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) throw new Error('Download failed');
			const blob = await res.blob();
			const blobUrl = URL.createObjectURL(blob);
			const a = document.createElement('a');
			a.href = blobUrl;
			const baseName = fileName.replace(/\.(tsv|csv)$/i, '');
			a.download = downloadFormat === 'excel' ? `${baseName}.xlsx` : fileName;
			// format=raw keeps the original filename (tsv/csv)
			// anchor must be in the DOM and the URL must outlive the click (see the
			// jobs output-box saveBlob note) or the download silently no-ops.
			a.rel = 'noopener';
			document.body.appendChild(a);
			a.click();
			a.remove();
			setTimeout(() => URL.revokeObjectURL(blobUrl), 1500);
		} catch (e) {
			downloadError = e instanceof Error ? e.message : 'Download failed';
		} finally {
			downloading = false;
		}
	}
</script>

<div class="w-full px-4 md:px-6 py-8 max-w-none">
	<div class="mb-6 flex flex-wrap items-start justify-between gap-4">
		<div>
			<h1 class="text-2xl font-bold text-primary-500 font-mono break-all">{fileName}</h1>
			{#if viewMode === 'image'}
				<p class="text-sm text-surface-500 mt-1">image</p>
			{:else if viewMode === 'text'}
				<p class="text-sm text-surface-500 mt-1">text{textTruncated ? ' (truncated)' : ''}</p>
			{:else}
				<p class="text-sm text-surface-500 mt-1">{totalRows.toLocaleString()} rows</p>
			{/if}
		</div>
		<div class="flex items-center gap-2">
			{#if viewMode === 'text'}
				<button type="button" onclick={() => wrapText = !wrapText}
					class="btn variant-ghost-primary btn-sm" title="Toggle line wrapping">
					{wrapText ? 'No wrap' : 'Wrap'}
				</button>
			{/if}
			{#if viewMode === 'table'}
				<label for="download-format" class="text-sm text-surface-500">Format</label>
				<select
					id="download-format"
					bind:value={downloadFormat}
					class="input px-3 py-1 rounded-lg bg-surface-200 dark:bg-surface-700 border border-surface-300 dark:border-surface-600"
				>
					<option value="raw">TSV</option>
					<option value="excel">Excel (.xlsx)</option>
				</select>
			{/if}
			<button type="button" onclick={downloadFile} disabled={downloading}
				class="btn variant-filled-primary btn-sm">
				{downloading ? 'Downloading...' : 'Download'}
			</button>
		</div>
	</div>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">{error}</div>
	{/if}

	{#if downloadError}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">{downloadError}</div>
	{/if}

	{#if viewMode === 'table'}
	<div class="card p-4 bg-surface-100 dark:bg-surface-800 mb-4 flex flex-wrap items-center justify-between gap-3">
		<div class="flex items-center gap-2">
			<button type="button" onclick={prevPage} disabled={currentPage <= 1}
				class="btn variant-ghost-primary btn-sm">Previous</button>
			<span class="text-sm text-surface-600 dark:text-surface-300">Page {currentPage} of {totalPages}</span>
			<button type="button" onclick={nextPage} disabled={currentPage >= totalPages}
				class="btn variant-ghost-primary btn-sm">Next</button>
		</div>
		<div class="flex items-center gap-2">
			<label for="page-size" class="text-sm text-surface-500">Rows per page</label>
			<select
				id="page-size"
				bind:value={pageSize}
				onchange={() => currentPage = 1}
				class="input px-3 py-1 rounded-lg bg-surface-200 dark:bg-surface-700 border border-surface-300 dark:border-surface-600"
			>
				{#each PAGE_SIZE_OPTIONS as size}
					<option value={size}>{size}</option>
				{/each}
			</select>
		</div>
	</div>
	{/if}

	<section class="card bg-surface-100 dark:bg-surface-800 overflow-hidden">
		{#if loading}
			<div class="p-12 text-center text-surface-500">
				<p class="text-lg">Loading...</p>
			</div>
		{:else if viewMode === 'image'}
			{#if imageError}
				<div class="p-12 text-center text-red-500">
					<p class="text-lg">{imageError}</p>
				</div>
			{:else}
				<div class="p-4 flex justify-center bg-surface-50 dark:bg-surface-900 overflow-x-auto">
					<img src={imageUrl} alt={fileName} class="max-w-full h-auto" />
				</div>
			{/if}
		{:else if viewMode === 'text'}
			{#if textError}
				<div class="p-12 text-center text-red-500">
					<p class="text-lg">{textError}</p>
				</div>
			{:else if looksBinary}
				<div class="p-12 text-center text-surface-500 space-y-3">
					<p class="text-lg">This looks like a binary file and can&rsquo;t be shown as text.</p>
					<button type="button" onclick={downloadFile} disabled={downloading}
						class="btn variant-filled-primary btn-sm">Download instead</button>
				</div>
			{:else}
				{#if textTruncated}
					<div class="px-4 py-2 text-xs text-amber-600 dark:text-amber-400 bg-amber-500/10 border-b border-amber-500/20">
						Showing the first {TEXT_LINE_CAP.toLocaleString()} lines &mdash; download the file to see the rest.
					</div>
				{/if}
				<div class="bg-[#0d1117] text-[#e6edf3] font-mono text-[13px] leading-relaxed overflow-x-auto py-2">
					{#each textLines as line, i}
						<div class="flex hover:bg-white/5">
							<span class="select-none shrink-0 text-right px-3 text-[#6e7681] border-r border-[#21262d] bg-[#0d1117] sticky left-0" style="min-width:3.5rem">{i + 1}</span>
							<span class="pl-4 pr-4 {wrapText ? 'whitespace-pre-wrap break-words' : 'whitespace-pre'} {lineClass(line)}">{line === '' ? '\u00A0' : line}</span>
						</div>
					{/each}
				</div>
			{/if}
		{:else}
			<div class="overflow-x-auto">
				<table class="table table-hover w-full">
					<thead>
						<tr class="bg-surface-200 dark:bg-surface-700">
							{#each columns as column, i}
								<th class="p-3 text-left whitespace-nowrap {columnTint(i)}">{column}</th>
							{/each}
						</tr>
					</thead>
					<tbody>
						{#each rows as row}
							<tr class="hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors align-top">
								{#each row as cell, i}
									{@const pill = pillStyle(columns[i] ?? '', cell)}
									<td class="p-3 text-sm {columnTint(i)}" title={cell.length > TRUNCATE_AT ? cell : undefined}>
										{#if pill}
											<span class="inline-block rounded px-2 py-0.5 font-semibold whitespace-nowrap"
												style="background:{pill.bg};color:{pill.fg}">{cell}</span>
										{:else if isBoolean(cell)}
											<span class="badge {isTruthy(cell) ? 'variant-filled-success' : 'variant-filled-error'}">{cell}</span>
										{:else if isIdLike(cell)}
											<span class="font-mono">{displayValue(cell)}</span>
										{:else}
											{displayValue(cell)}
										{/if}
									</td>
								{/each}
							</tr>
						{/each}
					</tbody>
				</table>
			</div>

			{#if rows.length === 0}
				<div class="p-12 text-center text-surface-500">
					<p class="text-lg">No rows on this page</p>
				</div>
			{/if}
		{/if}
	</section>
</div>
