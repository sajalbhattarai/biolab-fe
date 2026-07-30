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

	const PAGE_SIZE_OPTIONS = [50, 100, 250, 500];
	const TRUNCATE_AT = 200;
	const BOOLEAN_PATTERN = /^(true|false|t|f|yes|no)$/i;
	const TRUTHY_PATTERN = /^(true|t|yes)$/i;
	const ID_PATTERN = /^[A-Za-z0-9_.-]+$/;

	const COLUMN_TINTS = [
		'bg-blue-500/5',
		'bg-green-500/5',
		'bg-amber-500/5',
		'bg-purple-500/5',
		'bg-pink-500/5',
		'bg-cyan-500/5',
	];

	function columnTint(index: number): string {
		return COLUMN_TINTS[index % COLUMN_TINTS.length];
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
		if (isImageFile) {
			loadImage();
		} else {
			fetchPage();
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
			{#if isImageFile}
				<p class="text-sm text-surface-500 mt-1">image</p>
			{:else}
				<p class="text-sm text-surface-500 mt-1">{totalRows.toLocaleString()} rows</p>
			{/if}
		</div>
		<div class="flex items-center gap-2">
			{#if !isImageFile}
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

	{#if !isImageFile}
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
		{:else if isImageFile}
			{#if imageError}
				<div class="p-12 text-center text-red-500">
					<p class="text-lg">{imageError}</p>
				</div>
			{:else}
				<div class="p-4 flex justify-center bg-surface-50 dark:bg-surface-900 overflow-x-auto">
					<img src={imageUrl} alt={fileName} class="max-w-full h-auto" />
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
									<td class="p-3 text-sm {columnTint(i)}" title={cell.length > TRUNCATE_AT ? cell : undefined}>
										{#if isBoolean(cell)}
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
