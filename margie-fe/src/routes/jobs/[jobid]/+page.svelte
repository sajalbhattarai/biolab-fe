<script lang="ts">
	import { page } from '$app/stores';
	import { onMount, onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';

	function getApiUrl() {
		if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
			return 'http://localhost:8000';
		}
		return '';
	}

	interface SubJob {
		id: string;
		name: string;
		status: 'pending' | 'running' | 'completed' | 'failed';
		start_time?: string;
		end_time?: string;
	}

	interface SlurmJob {
		job_id: string;
		rule: string;
		status: string;
		time: string;
		genome?: string;
		source?: string;
	}

	interface ContainerInfo {
		name: string;
		version: string;
		path: string;
		resolved_path?: string;
		source: 'local' | 'cached' | 'downloaded';
		registry_url?: string;
		docker_url?: string;
	}

	interface FileEntry {
		name: string;
		type: 'file' | 'directory';
		size?: number;
	}

	interface JobStatus {
		job_id: string;
		status: 'pending' | 'running' | 'snakemake' | 'completed' | 'failed' | 'cancelled';
		phase: string;
		progress?: number;
		steps_done?: number;
		steps_total?: number;
		start_time: string;
		end_time?: string;
		genome_path?: string;
		work_dir?: string;
		workflow?: string;
		selected_tools?: string;
		relaunched_from?: string;
		still_active?: boolean;
		status_note?: string;
		cluster_host: string;
		sub_jobs: SubJob[];
		slurm_jobs: SlurmJob[];
		containers: ContainerInfo[];
		logs?: string;
	}

	interface LogGroup {
		type: 'normal' | 'pip';
		lines: string[];
		done: boolean;
	}

	function isPipLine(line: string): boolean {
		return (
			/^Resolved \d+ package/.test(line) ||
			/^Prepared \d+ package/.test(line) ||
			/^Installed \d+ package/.test(line) ||
			/^ \+ [\w]/.test(line) ||
			/[━─]{10}/.test(line) ||
			/^Downloading /.test(line) ||
			/^Collecting /.test(line) ||
			/^Installing collected/.test(line) ||
			/^Successfully installed/.test(line) ||
			/^Using cached/.test(line) ||
			/^Requirement already satisfied/.test(line)
		);
	}

	function processLogs(logs: string): LogGroup[] {
		const lines = logs.split('\n').filter(l => l.trim());
		const groups: LogGroup[] = [];
		let current: LogGroup | null = null;
		for (const line of lines) {
			const type: 'pip' | 'normal' = isPipLine(line) ? 'pip' : 'normal';
			if (!current || current.type !== type) {
				current = { type, lines: [], done: false };
				groups.push(current);
			}
			current.lines.push(line);
			if (type === 'pip' && /^(Successfully installed|Installed \d+ package)/.test(line)) {
				current.done = true;
			}
		}
		return groups;
	}

	function containerSourceLabel(source: ContainerInfo['source']): string {
		if (source === 'local') return 'Local';
		if (source === 'cached') return 'Cached';
		return 'Downloaded';
	}

	function containerSourceClass(source: ContainerInfo['source']): string {
		if (source === 'local') return 'bg-amber-500/20 text-amber-500';
		if (source === 'cached') return 'bg-green-500/20 text-green-500';
		return 'bg-blue-500/20 text-blue-500';
	}

	function containerLocation(container: ContainerInfo): string {
		if (container.source === 'local') {
			return container.resolved_path ?? container.path;
		}

		return container.registry_url ?? container.docker_url ?? container.resolved_path ?? container.path;
	}

	let jobId = $derived($page.params.jobid);
	let job = $state<JobStatus | null>(null);
	let error = $state('');
	let loading = $state(true);
	let pollInterval: ReturnType<typeof setInterval> | null = null;
	let showLogs = $state(true);  // Show logs by default
	let logsCopied = $state(false);
	let showContainers = $state(false);
	let showSlurmJobs = $state(true);
	let showOutputFiles = $state(true);
	let showFileGuide = $state(false);
	let expandFileList = $state(false);  // taller file-list panel on demand
	let expandPipLogs = $state(false);
	let logGroups = $derived(job?.logs ? processLogs(job.logs) : []);

	let outputFiles = $state<FileEntry[]>([]);
	let currentSubdir = $state('');
	let filesLoading = $state(false);
	let filesError = $state('');
	let lastFileFetchTime = 0;

	onMount(() => {
		fetchJobStatus();
		pollInterval = setInterval(fetchJobStatus, 10000);  // Poll every 2 seconds for responsive logs
	});

	onDestroy(() => {
		if (pollInterval) clearInterval(pollInterval);
	});

	function handle401() { clearToken(); goto('/login'); }

	async function fetchJobStatus() {
		console.log('Fetching job status...')
		try {
			const apiUrl = getApiUrl();
			console.log('API URL:', apiUrl, 'Job ID:', jobId);
			const res = await fetch(`${apiUrl}/v1/ssh/job_status/${jobId}`, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) throw new Error('Failed to fetch job status');
			job = await res.json();
			error = '';
			console.log(`Fetched the ${apiUrl}/v1/ssh/job_status/${jobId}`)

			// Fetch files when work_dir is available, throttled to every 15s
			const now = Date.now();
			if (job?.work_dir && !filesLoading && (now - lastFileFetchTime >= 15000)) {
				lastFileFetchTime = now;
				fetchJobFiles(currentSubdir);
			}

			// Stop polling if job is done AND not still active on the cluster
			if (job && (job.status === 'completed' || job.status === 'failed' || job.status === 'cancelled') && !job.still_active) {
				// One final file fetch on completion
				if (job.work_dir) {
					fetchJobFiles(currentSubdir);
				}
				if (pollInterval) {
					clearInterval(pollInterval);
					pollInterval = null;
				}
			}
		} catch (e) {
			console.error('Error fetching api endpoint or something')
			error = e instanceof Error ? e.message : 'Failed to fetch job status';
		} finally {
			loading = false;
		}
	}

	// Expand-in-place tree. navigateToDir used to REPLACE the listing, so seeing
	// two organisms' outputs meant walking out and back in. Children are fetched
	// once per folder and cached; expanding again is instant.
	let expanded = $state<Set<string>>(new Set());
	let childCache = $state<Record<string, FileEntry[]>>({});
	let loadingDirs = $state<Set<string>>(new Set());

	function joinPath(base: string, name: string) {
		return base ? `${base}/${name}` : name;
	}

	async function loadDir(path: string): Promise<FileEntry[]> {
		if (childCache[path]) return childCache[path];
		loadingDirs = new Set([...loadingDirs, path]);
		try {
			const apiUrl = getApiUrl();
			const params = path ? `?subdir=${encodeURIComponent(path)}` : '';
			const res = await fetch(`${apiUrl}/v1/ssh/job_files/${jobId}${params}`, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return []; }
			if (!res.ok) throw new Error('Failed to list files');
			const data = await res.json();
			childCache = { ...childCache, [path]: data.entries };
			return data.entries;
		} catch (e) {
			filesError = e instanceof Error ? e.message : 'Failed to list files';
			return [];
		} finally {
			const n = new Set(loadingDirs); n.delete(path); loadingDirs = n;
		}
	}

	async function toggleDir(path: string) {
		if (expanded.has(path)) {
			const n = new Set(expanded); n.delete(path); expanded = n;
			return;
		}
		await loadDir(path);
		expanded = new Set([...expanded, path]);
	}

	/** Re-fetch every folder currently open, so Refresh updates the whole tree. */
	async function refreshTree() {
		childCache = {};
		await fetchJobFiles(currentSubdir);
		for (const path of [...expanded]) await loadDir(path);
	}

	// Flattened view of the open tree: the existing flat markup is reused, with
	// depth driving indentation. Cheaper and far less risky than a recursive
	// snippet rewrite of the whole block.
	type Row = { entry: FileEntry; path: string; depth: number };
	function flatten(entries: FileEntry[], base: string, depth: number): Row[] {
		const out: Row[] = [];
		for (const entry of entries) {
			const path = joinPath(base, entry.name);
			out.push({ entry, path, depth });
			if (entry.type === 'directory' && expanded.has(path)) {
				out.push(...flatten(childCache[path] ?? [], path, depth + 1));
			}
		}
		return out;
	}
	const fileRows = $derived(flatten(outputFiles, currentSubdir, 0));

	async function fetchJobFiles(subdir = '') {
		if (!job?.work_dir) return;
		filesLoading = true;
		filesError = '';
		try {
			const apiUrl = getApiUrl();
			const params = subdir ? `?subdir=${encodeURIComponent(subdir)}` : '';
			const res = await fetch(`${apiUrl}/v1/ssh/job_files/${jobId}${params}`, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) throw new Error('Failed to list files');
			const data = await res.json();
			outputFiles = data.entries;
			currentSubdir = subdir;
		} catch (e) {
			filesError = e instanceof Error ? e.message : 'Failed to list files';
			outputFiles = [];
		} finally {
			filesLoading = false;
		}
	}

	// Trigger a browser download from a Blob. The anchor MUST be in the document
	// and the object URL must outlive the click, or some browsers (Firefox always,
	// Chromium intermittently) silently no-op -- which was why the direct tsv/excel
	// buttons "did nothing" while the viewer's identical-but-in-DOM path worked.
	function saveBlob(blob: Blob, fileName: string) {
		const blobUrl = URL.createObjectURL(blob);
		const a = document.createElement('a');
		a.href = blobUrl;
		a.download = fileName;
		a.rel = 'noopener';
		document.body.appendChild(a);
		a.click();
		a.remove();
		setTimeout(() => URL.revokeObjectURL(blobUrl), 1500);
	}

	async function downloadFile(fileName: string) {
		const apiUrl = getApiUrl();
		// fileName is already a path relative to the job root (the tree may be
		// several levels deep), so it must NOT be prefixed again.
		const relativePath = fileName;
		const url = `${apiUrl}/v1/ssh/download_file/${jobId}?path=${encodeURIComponent(relativePath)}`;
		try {
			const res = await fetch(url, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) { filesError = 'Download failed'; return; }
			saveBlob(await res.blob(), fileName.split('/').pop() || fileName);
		} catch (e) {
			filesError = e instanceof Error ? e.message : 'Download failed';
		}
	}

	async function downloadFileAsExcel(fileName: string) {
		const apiUrl = getApiUrl();
		// fileName is already a path relative to the job root (the tree may be
		// several levels deep), so it must NOT be prefixed again.
		const relativePath = fileName;
		const xlsxName = fileName.replace(/\.(tsv|csv)$/i, '.xlsx');
		const url = `${apiUrl}/v1/ssh/download_file/${jobId}?path=${encodeURIComponent(relativePath)}&format=excel`;
		try {
			const res = await fetch(url, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) { filesError = 'Excel download failed'; return; }
			saveBlob(await res.blob(), xlsxName);
		} catch (e) {
			filesError = e instanceof Error ? e.message : 'Excel download failed';
		}
	}

	const LARGE_FILE_WARN_BYTES = 100 * 1024 * 1024; // 100MB, easy to tune
	let pendingLargeFile = $state<FileEntry | null>(null);

	function isTabular(name: string): boolean {
		const lower = name.toLowerCase();
		return lower.endsWith('.tsv') || lower.endsWith('.csv');
	}

	// The self-contained interactive genome/operon map written at the organism
	// top level by the pipeline's run_genome_viewer_one_genome rule. Matched by
	// name rather than extension: it is not a generic .html preview, it gets its
	// own sandboxed route. Older suffixed names are accepted too.
	function isGenomeViewer(name: string): boolean {
		return name === 'FINAL_GENOME_VIEWER.html' || /_genome_viewer\.html$/i.test(name);
	}

	function genomeMapHref(fileName: string): string {
		// fileName is already a path relative to the job root (the tree may be
		// several levels deep), so it must NOT be prefixed again.
		const relativePath = fileName;
		// currentSubdir is the organism folder when browsing per-organism output.
		const organism = currentSubdir ? currentSubdir.split('/').pop()! : '';
		return `/jobs/${jobId}/map?path=${encodeURIComponent(relativePath)}`
			+ (organism ? `&organism=${encodeURIComponent(organism)}` : '');
	}

	function launchViewerTab(fileName: string) {
		// fileName is already a path relative to the job root (the tree may be
		// several levels deep), so it must NOT be prefixed again.
		const relativePath = fileName;
		window.open(`/jobs/${jobId}/view?path=${encodeURIComponent(relativePath)}`, '_blank');
	}

	function openViewer(entry: FileEntry) {
		if (entry.size && entry.size > LARGE_FILE_WARN_BYTES) {
			pendingLargeFile = entry;
			return;
		}
		launchViewerTab(entry.name);
	}

	function confirmViewLargeFile() {
		if (pendingLargeFile) launchViewerTab(pendingLargeFile.name);
		pendingLargeFile = null;
	}


	function navigateUp() {
		const parts = currentSubdir.split('/').filter(Boolean);
		parts.pop();
		fetchJobFiles(parts.join('/'));
	}

	function formatFileSize(bytes?: number): string {
		if (bytes === undefined || bytes === null) return '';
		if (bytes < 1024) return `${bytes} B`;
		if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
		return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
	}

	function getStatusColor(status: string): string {
		switch (status) {
			case 'completed': return 'bg-green-500';
			case 'running': return 'bg-blue-500 animate-pulse';
			case 'snakemake': return 'bg-purple-500 animate-pulse';
			case 'failed': return 'bg-red-500';
			case 'cancelled': return 'bg-orange-500';
			default: return 'bg-gray-400';
		}
	}

	function getStatusText(status: string): string {
		switch (status) {
			case 'completed': return 'Completed';
			case 'running': return 'Running';
			case 'snakemake': return 'Running Snakemake';
			case 'failed': return 'Failed';
			case 'cancelled': return 'Cancelled';
			default: return 'Pending';
		}
	}

	function getSlurmStatusColor(status: string): string {
		switch (status) {
			case 'COMPLETED': return 'text-green-500';
			case 'COMPLETING': return 'text-cyan-500';
			case 'RUNNING': return 'text-blue-500';
			case 'PENDING': return 'text-yellow-500';
			case 'SUBMITTED': return 'text-yellow-500';
			case 'FAILED': return 'text-red-500';
			case 'CANCELLED': return 'text-gray-500';
			case 'CACHED': return 'text-purple-500';
			default: return 'text-surface-500';
		}
	}

	function formatTime(time?: string): string {
		if (!time) return '-';
		return new Date(time).toLocaleString();
	}

	async function copyLogs() {
		if (!job?.logs) return;
		try {
			await navigator.clipboard.writeText(job.logs);
			logsCopied = true;
			setTimeout(() => logsCopied = false, 1500);
		} catch (e) {
			console.error('Failed to copy logs:', e);
		}
	}

	async function cancelJob() {
		if (!confirm('Are you sure you want to cancel this job? All running SLURM jobs and SSH processes will be terminated.')) {
			return;
		}
		try {
			const apiUrl = getApiUrl();
			const res = await fetch(`${apiUrl}/v1/ssh/cancel_job/${jobId}`, {
				method: 'POST',
				headers: authHeaders()
			});
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) {
				const body = await res.json().catch(() => null);
				throw new Error(body?.detail || `Failed to cancel job (${res.status})`);
			}
			const data = await res.json();
			console.log('Job cancelled:', data);
			// Immediately refresh status
			await fetchJobStatus();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to cancel job';
		}
	}

	let resumeInFlight = $state(false);
	let restartInFlight = $state(false);
	let relaunchedJobId = $state<string | null>(null);
	let relaunchedAction = $state<'resumed' | 'restarted' | null>(null);

	async function resumeFailedJob() {
		resumeInFlight = true;
		relaunchedJobId = null;
		try {
			const apiUrl = getApiUrl();
			const res = await fetch(`${apiUrl}/v1/ssh/resume_job/${jobId}`, {
				method: 'POST',
				headers: authHeaders()
			});
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) throw new Error((await res.json()).detail ?? 'Failed to resume job');
			const data = await res.json();
			relaunchedJobId = data.job_id;
			relaunchedAction = 'resumed';
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to resume job';
		} finally {
			resumeInFlight = false;
		}
	}

	async function restartJob() {
		if (!confirm('Restart this analysis from scratch with the same genome, workflow, and tool selection?')) {
			return;
		}
		restartInFlight = true;
		relaunchedJobId = null;
		try {
			const apiUrl = getApiUrl();
			const res = await fetch(`${apiUrl}/v1/ssh/restart_job/${jobId}`, {
				method: 'POST',
				headers: authHeaders()
			});
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) throw new Error((await res.json()).detail ?? 'Failed to restart job');
			const data = await res.json();
			relaunchedJobId = data.job_id;
			relaunchedAction = 'restarted';
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to restart job';
		} finally {
			restartInFlight = false;
		}
	}

	$effect(() => {
		// Refetch when jobId changes (only in browser)
		if (typeof window !== 'undefined' && jobId) {
			loading = true;
			fetchJobStatus();
		}
	});

</script>

<div class="w-full px-4 md:px-6 py-8 space-y-6">
	<div class="flex items-center justify-between">
		<h1 class="text-3xl font-bold text-primary-500">Job Monitor</h1>
		<div class="flex items-center gap-3">
			{#if job}
				<button
					type="button"
					onclick={restartJob}
					disabled={restartInFlight}
					class="btn variant-filled-secondary px-4 py-2"
				>{restartInFlight ? 'Restarting...' : 'Restart This Analysis'}</button>
			{/if}
			<a href="/analyze" class="btn variant-ghost-surface px-4 py-2">New Analysis</a>
		</div>
	</div>

	{#if relaunchedJobId}
		<div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded flex items-center justify-between gap-3">
			<span>
				A new job has been started that {relaunchedAction === 'resumed' ? 'resumes' : 'restarts'} this one.
				The new job ID is <span class="font-mono">{relaunchedJobId}</span> — visit the
				<a href="/results/historical" class="underline font-semibold">jobs page</a> to monitor it.
			</span>
			<a href={`/jobs/${relaunchedJobId}`} class="btn variant-filled-primary btn-sm shrink-0">View New Job</a>
		</div>
	{/if}

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">{error}</div>
	{/if}

	{#if loading && !job}
		<div class="card p-8 bg-surface-100 dark:bg-surface-800 text-center">
			<p class="text-surface-500">Loading job status...</p>
		</div>
	{:else if job}
		<!-- Main Job Status -->
		<section class="card p-6 bg-surface-100 dark:bg-surface-800">
			<div class="flex items-start justify-between mb-4">
				<div>
					<h2 class="text-xl font-semibold mb-1">Job ID</h2>
					<code class="font-mono text-sm bg-surface-200 dark:bg-surface-700 px-2 py-1 rounded">{job.job_id}</code>
				</div>
				<div class="flex items-center gap-3">
					<div class="flex items-center gap-2">
						<span class="inline-block w-3 h-3 rounded-full {getStatusColor(job.status)}"></span>
						<span class="font-semibold">{getStatusText(job.status)}</span>
					</div>
					{#if job.status === 'running' || job.status === 'pending' || job.status === 'snakemake' || job.still_active}
						<button
							type="button"
							onclick={() => cancelJob()}
							class="btn variant-filled-error px-3 py-1.5 text-sm font-semibold rounded flex items-center gap-1.5 hover:brightness-110 transition-all"
							title="Cancel all running jobs"
						>
							<span>🛑</span>
							<span>Emergency Stop</span>
						</button>
					{/if}
				</div>
			</div>

			{#if job.genome_path}
				<div class="mb-4">
					<span class="text-sm text-surface-500">Genome:</span>
					<span class="font-mono text-sm ml-2">{job.genome_path}</span>
				</div>
			{/if}



			<div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
				<div>
					<span class="text-surface-500 block">Phase</span>
					<span class="font-semibold">{job.phase || 'Initializing'}</span>
					{#if job.resumed_from_history}
						<span class="text-xs text-yellow-500">last known</span>
					{/if}
				</div>
				<div>
					<span class="text-surface-500 block">Started</span>
					<span>{formatTime(job.start_time)}</span>
				</div>
				<div>
					<span class="text-surface-500 block">Ended</span>
					<span>{formatTime(job.end_time)}</span>
				</div>
				{#if job.progress !== undefined}
					<div>
						<span class="text-surface-500 block">Progress</span>
						<span>{job.progress}%</span>
					</div>
				{/if}
			</div>

			{#if job.progress !== undefined}
				<div class="mt-4">
					<div class="w-full bg-surface-300 dark:bg-surface-600 rounded-full h-2">
						<div
							class="h-2 rounded-full transition-all duration-500 {job.status === 'failed' ? 'bg-red-500' : 'bg-primary-500'}"
							style="width: {job.progress}%"
						></div>
					</div>
				</div>
			{/if}
		</section>

		<!-- Snakemake Sub-Jobs -->
		{#if job.sub_jobs && job.sub_jobs.length > 0}
			<section class="card p-6 bg-surface-100 dark:bg-surface-800">
				<h2 class="text-xl font-semibold mb-4">Snakemake Jobs</h2>
				<div class="space-y-2">
					{#each job.sub_jobs as subJob}
						<div class="flex items-center justify-between p-3 bg-surface-200 dark:bg-surface-700 rounded-lg">
							<div class="flex items-center gap-3">
								<span class="inline-block w-2.5 h-2.5 rounded-full {getStatusColor(subJob.status)}"></span>
								<span class="font-mono text-sm">{subJob.name}</span>
							</div>
							<div class="flex items-center gap-4 text-sm text-surface-500">
								<span>ID: {subJob.id}</span>
								{#if subJob.start_time}
									<span>Started: {formatTime(subJob.start_time)}</span>
								{/if}
								{#if subJob.end_time}
									<span>Ended: {formatTime(subJob.end_time)}</span>
								{/if}
							</div>
						</div>
					{/each}
				</div>
			</section>
		{:else if job.status === 'snakemake'}
			<section class="card p-6 bg-surface-100 dark:bg-surface-800">
				<h2 class="text-xl font-semibold mb-4">Snakemake Jobs</h2>
				<p class="text-surface-500">Waiting for snakemake jobs to spawn...</p>
			</section>
		{/if}

		<!-- Slurm Jobs -->
		<section class="card p-6 bg-surface-100 dark:bg-surface-800">
			<div class="flex items-center justify-between">
				<button
					type="button"
					onclick={() => showSlurmJobs = !showSlurmJobs}
					class="flex items-center gap-3 text-left flex-1"
				>
					<h2 class="text-xl font-semibold">Slurm Jobs</h2>
					<span class="transform transition-transform {showSlurmJobs ? 'rotate-180' : ''}">&#9660;</span>
				</button>
				<button
					type="button"
					onclick={() => fetchJobStatus()}
					class="text-xs text-primary-500 hover:text-primary-400 px-2 py-1 rounded border border-primary-500/30 hover:border-primary-400 transition-colors"
					title="Refresh SLURM jobs"
				>↻ Refresh</button>
			</div>
			{#if showSlurmJobs}
				<div>
				{#if (job.slurm_jobs ?? []).length > 0}
					<div
						class="overflow-auto resize-y h-60 min-h-[120px] max-h-[80vh] rounded border border-surface-300 dark:border-surface-600 mt-4"
					>
						<table class="min-w-full text-sm text-left">
							<thead class="text-xs uppercase text-surface-500 border-b border-surface-300 dark:border-surface-600 sticky top-0 bg-surface-100 dark:bg-surface-800">
								<tr>
									<th class="px-4 py-3 whitespace-nowrap">Job ID</th>
									<th class="px-4 py-3 whitespace-nowrap">Rule</th>
									<th class="px-4 py-3 whitespace-nowrap">Organism</th>
									<th class="px-4 py-3 whitespace-nowrap">Status</th>
									<th class="px-4 py-3 whitespace-nowrap">Source</th>
									<th class="px-4 py-3 whitespace-nowrap">Time</th>
								</tr>
							</thead>
							<tbody>
								{#each job.slurm_jobs ?? [] as sj}
									<tr class="border-b border-surface-200 dark:border-surface-700">
										<td class="px-4 py-3 font-mono whitespace-nowrap">{sj.job_id}</td>
										<td class="px-4 py-3 font-mono whitespace-nowrap">{sj.rule ?? ''}</td>
										<td class="px-4 py-3 font-mono truncate max-w-[16rem]" title={sj.genome ?? ''}>{sj.genome ?? ''}</td>
										<td class="px-4 py-3 font-semibold whitespace-nowrap {getSlurmStatusColor(sj.status)}">{sj.status}</td>
										<td class="px-4 py-3 whitespace-nowrap {sj.source === 'from cache' ? 'text-purple-500 font-semibold' : 'text-surface-500'}">{sj.source ?? 'fresh run'}</td>
										<td class="px-4 py-3 font-mono whitespace-nowrap">{sj.time}</td>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
					<p class="text-xs text-surface-400 mt-1">Drag the bottom-right corner to resize.</p>
				{:else}
					<p class="text-surface-500 mt-4">No jobs currently running on Slurm.</p>
				{/if}
				</div>
			{/if}
		</section>

		<!-- Containers -->
		<section class="card p-6 bg-surface-100 dark:bg-surface-800">
			<button
				type="button"
				onclick={() => showContainers = !showContainers}
				class="flex items-center justify-between w-full text-left"
			>
				<h2 class="text-xl font-semibold">Containers</h2>
				<span class="transform transition-transform {showContainers ? 'rotate-180' : ''}">&#9660;</span>
			</button>
			{#if showContainers}
				<div>
				{#if (job.containers ?? []).length > 0}
					<div class="overflow-x-auto mt-4">
						<table class="w-full text-sm text-left">
							<thead class="text-xs uppercase text-surface-500 border-b border-surface-300 dark:border-surface-600">
								<tr>
									<th class="px-4 py-3">Name</th>
									<th class="px-4 py-3">Version</th>
									<th class="px-4 py-3">Source</th>
									<th class="px-4 py-3">Location / Image</th>
								</tr>
							</thead>
							<tbody>
								{#each job.containers ?? [] as c}
									<tr class="border-b border-surface-200 dark:border-surface-700">
										<td class="px-4 py-3 font-mono">{c.name}</td>
										<td class="px-4 py-3 font-mono">{c.version}</td>
										<td class="px-4 py-3">
											<span class="text-xs font-semibold px-2 py-1 rounded {containerSourceClass(c.source)}">
												{containerSourceLabel(c.source)}
											</span>
										</td>
										<td class="px-4 py-3 font-mono text-xs text-surface-400">{containerLocation(c)}</td>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
				{:else}
					<p class="text-surface-500 mt-4">No containers loaded yet.</p>
				{/if}
				</div>
			{/if}
		</section>

		<!-- Snakemake Progress -->
		{#if job.steps_total}
			<section class="card p-6 bg-surface-100 dark:bg-surface-800">
				<div class="flex items-center justify-between mb-3">
					<h2 class="text-xl font-semibold">Workflow Progress</h2>
					<span class="text-sm font-mono text-surface-500">{job.steps_done} / {job.steps_total} steps</span>
				</div>
				<div class="w-full bg-surface-300 dark:bg-surface-600 rounded-full h-3">
					<div
						class="h-3 rounded-full transition-all duration-500 {job.progress === 100 ? 'bg-green-500' : 'bg-primary-500'}"
						style="width: {job.progress}%"
					></div>
				</div>
				<p class="text-sm text-surface-500 mt-2">{job.progress}% complete</p>
			</section>
		{/if}

		<!-- Output Files -->
		{#if job.work_dir}
			<section class="card p-6 bg-surface-100 dark:bg-surface-800">
				<div class="flex items-center justify-between">
					<button
						type="button"
						onclick={() => showOutputFiles = !showOutputFiles}
						class="flex items-center gap-3 text-left flex-1"
					>
						<div class="flex items-center gap-3">
							<h2 class="text-xl font-semibold">Output Files</h2>
							{#if job.status === 'completed'}
								<span class="text-xs font-semibold px-2 py-1 rounded bg-green-500/20 text-green-500">Files Complete</span>
							{:else if job.status === 'failed'}
								<span class="text-xs font-semibold px-2 py-1 rounded bg-red-500/20 text-red-500">Failed</span>
							{:else}
								<span class="text-xs font-semibold px-2 py-1 rounded bg-yellow-500/20 text-yellow-500 animate-pulse">Pending</span>
							{/if}
						</div>
						<span class="transform transition-transform {showOutputFiles ? 'rotate-180' : ''}">&#9660;</span>
					</button>
					<button
						type="button"
						onclick={refreshTree}
						disabled={filesLoading}
						class="text-xs text-primary-500 hover:text-primary-400 px-2 py-1 rounded border border-primary-500/30 hover:border-primary-400 transition-colors disabled:opacity-50"
						title="Refresh file listing"
					>↻ Refresh</button>
				</div>
				{#if showOutputFiles}
				<div>
				<p class="text-sm text-surface-500 mb-2 mt-2 font-mono">{job.work_dir}</p>

				<!-- File Guide -->
				<div class="mb-3 border border-primary-500/20 rounded-lg overflow-hidden">
					<button
						type="button"
						onclick={() => showFileGuide = !showFileGuide}
						class="flex items-center justify-between w-full px-4 py-2.5 bg-primary-500/5 hover:bg-primary-500/10 text-left transition-colors"
					>
						<span class="text-sm font-semibold text-primary-400">Which files should I download?</span>
						<span class="text-xs text-surface-400 transform transition-transform {showFileGuide ? 'rotate-180' : ''}">&#9660;</span>
					</button>
					{#if showFileGuide}
						<div class="px-4 py-3 space-y-4 text-sm bg-surface-50 dark:bg-surface-900 border-t border-primary-500/20">

							<p class="text-surface-500 dark:text-surface-400">
								When a genome finishes, its folder is tidied into just <span class="font-semibold">three things</span>.
								Here is what each one is:
							</p>

							<div>
								<p class="text-xs font-semibold uppercase text-surface-400 mb-1 tracking-wide">1 &middot; Final annotation</p>
								<p class="font-mono text-xs font-semibold text-green-400 break-all">&lt;organism&gt;/FINAL_ANNOTATION_WITH_CONFIDENCE.tsv&nbsp;(+&nbsp;.xlsx)</p>
								<p class="text-surface-500 text-xs mt-1">
									The publication-ready, per-gene results table: the concordant annotation label, C1&ndash;C4 confidence
									components, final confidence (adjacency and hybrid), operon context and members, and review flags.
									Open the <span class="font-mono">.tsv</span> in the viewer here, or grab the ready-made
									<span class="font-mono">.xlsx</span> sitting right beside it &mdash; already colour-coded by confidence
									tier to match the diagrams.
								</p>
							</div>

							<div class="border-t border-surface-300 dark:border-surface-700 pt-3">
								<p class="text-xs font-semibold uppercase text-surface-400 mb-1 tracking-wide">2 &middot; Diagrams</p>
								<p class="font-mono text-xs font-semibold text-blue-400 break-all">&lt;organism&gt;/diagrams/</p>
								<p class="text-surface-500 text-xs mt-1">
									The genome's figures &mdash; confidence-tier / confidence-stage / component figures plus the operon-context
									figures. If you enabled <span class="font-semibold">Full-genome operon map</span> in your Profile settings,
									the complete per-operon atlas (every operon drawn with its per-gene confidence table) is in
									<span class="font-mono">diagrams/complete-organism-operon-diagrams/</span>.
								</p>
							</div>

							<div class="border-t border-surface-300 dark:border-surface-700 pt-3">
								<p class="text-xs font-semibold uppercase text-surface-400 mb-1 tracking-wide">3 &middot; Per-tool phased output</p>
								<p class="font-mono text-xs font-semibold text-amber-400 break-all">&lt;organism&gt;/per-tool-phased-output/</p>
								<p class="text-surface-500 text-xs mt-1">
									Everything else, kept for provenance: each annotation tool's phase folder (PGAP, eggNOG, InterPro,
									RASTtk, and the rest) and the intermediate scoring tables under <span class="font-mono">scoring/</span>.
									You rarely need these &mdash; the Final annotation above is the distilled result.
								</p>
							</div>

						</div>
					{/if}
				</div>

				{#if currentSubdir}
					<p class="text-sm text-surface-400 mb-2 font-mono">/ {currentSubdir}</p>
				{/if}

				{#if filesError}
					<p class="text-red-500 text-sm mb-2">{filesError}</p>
				{/if}

				{#if currentSubdir}
					<button
						type="button"
						onclick={() => navigateUp()}
						class="flex items-center gap-2 px-3 py-2 mb-1 rounded bg-surface-200 dark:bg-surface-700 hover:bg-surface-300 dark:hover:bg-surface-600 w-full text-left"
					>
						<span class="text-surface-400">..</span>
						<span class="font-mono text-sm text-surface-400">Back</span>
					</button>
				{/if}

				{#if filesLoading && outputFiles.length === 0}
					<p class="text-surface-500">Loading files...</p>
				{:else if outputFiles.length > 0}
					<div class="flex justify-end mb-1">
						<button
							type="button"
							onclick={() => expandFileList = !expandFileList}
							class="text-xs text-primary-500 hover:text-primary-400 px-2 py-1 rounded border border-primary-500/30 hover:border-primary-400 transition-colors"
							title="Make the file list taller or shorter"
						>{expandFileList ? 'Shrink list \u25B2' : 'Expand list \u25BC'}</button>
					</div>
					<div class="space-y-1 overflow-y-auto resize-y {expandFileList ? 'h-[70vh]' : 'h-60'} min-h-[120px] max-h-[85vh] rounded border border-surface-300 dark:border-surface-600 p-2 pr-3">
						{#each fileRows as { entry, path, depth } (path)}
							{#if entry.type === 'directory'}
								<button
									type="button"
									onclick={() => toggleDir(path)}
									aria-expanded={expanded.has(path)}
									style="margin-left:{depth * 14}px"
									class="flex items-center justify-between px-3 py-2 rounded bg-surface-200 dark:bg-surface-700 hover:bg-surface-300 dark:hover:bg-surface-600 w-full text-left"
								>
									<div class="flex items-center gap-2">
										<span class="inline-block w-3 text-surface-400">
											{loadingDirs.has(path) ? '⋯' : expanded.has(path) ? '▾' : '▸'}
										</span>
										<span class="text-yellow-500">&#128193;</span>
										<span class="font-mono text-sm">{entry.name}/</span>
									</div>
								</button>
							{:else}
								<div
									style="margin-left:{depth * 14}px"
									class="flex items-center justify-between px-3 py-2 rounded bg-surface-200 dark:bg-surface-700"
								>
									<div class="flex items-center gap-2">
										<span class="inline-block w-3"></span>
										<span class="text-surface-400">&#128196;</span>
										<span class="font-mono text-sm">{entry.name}</span>
									</div>
									<div class="flex items-center gap-3">
										<span class="text-xs text-surface-400">{formatFileSize(entry.size)}</span>
										{#if isGenomeViewer(entry.name)}
											<a
												href={genomeMapHref(path)}
												class="text-xs font-semibold text-tertiary-500 hover:text-tertiary-400"
												title="Open the interactive genome / operon map"
											>Open map</a>
										{/if}
										{#if !isGenomeViewer(entry.name)}
											<button
												type="button"
												onclick={() => openViewer({ ...entry, name: path })}
												class="text-xs text-primary-500 hover:text-primary-400"
											>View</button>
										{/if}
										{#if isTabular(entry.name)}
											<button
												type="button"
												onclick={() => downloadFileAsExcel(path)}
												class="text-xs text-green-500 hover:text-green-400 font-semibold"
												title="Download as Excel with tier coloring"
											>Excel</button>
										{/if}
										<button
											type="button"
											onclick={() => downloadFile(path)}
											class="text-xs text-primary-500 hover:text-primary-400"
										>Download</button>
									</div>
								</div>
							{/if}
						{/each}
					</div>
				{:else}
					<p class="text-surface-500">No files found.</p>
				{/if}
				</div>
				{/if}
			</section>
		{/if}

		<!-- Logs Section -->
		<section class="card p-6 bg-surface-100 dark:bg-surface-800">
			<button
				type="button"
				onclick={() => showLogs = !showLogs}
				class="flex items-center justify-between w-full text-left"
			>
				<h2 class="text-xl font-semibold">Logs</h2>
				<span class="transform transition-transform {showLogs ? 'rotate-180' : ''}">&#9660;</span>
			</button>
			{#if showLogs}
				<div class="relative mt-4">
					<button
						type="button"
						onclick={copyLogs}
						disabled={!job.logs}
						class="absolute top-2 right-2 z-10 text-xs font-semibold px-3 py-1.5 rounded bg-surface-700 hover:bg-surface-600 text-surface-200 disabled:opacity-50 transition-colors shadow"
						title="Copy logs to clipboard"
					>
						{logsCopied ? 'Copied!' : 'Copy'}
					</button>
					<div class="p-4 bg-surface-900 text-green-400 font-mono text-sm rounded-lg overflow-x-auto max-h-96 overflow-y-auto">
					{#if job.logs}
						{#each logGroups as group}
							{#if group.type === 'pip'}
								<div class="py-1 border-t border-surface-700 first:border-t-0">
									<span class="text-surface-500 mr-2 select-none">—</span>
									<span class="text-yellow-400">
										{group.done
											? `Completed bioinformatics-tools pip package on ${job.cluster_host ?? 'remote server'}`
											: `Downloading bioinformatics-tools pip package on ${job.cluster_host ?? 'remote server'}`}
									</span>
									<button type="button"
										class="ml-2 text-xs text-surface-400 hover:text-surface-200 underline"
										onclick={() => expandPipLogs = !expandPipLogs}
									>{expandPipLogs ? 'hide details' : 'show details'}</button>
									{#if expandPipLogs}
										{#each group.lines as line}
											<div class="pl-6 py-0.5 text-surface-400">{line}</div>
										{/each}
									{/if}
								</div>
							{:else}
								{#each group.lines as line, li}
									<div class="py-1 border-t border-surface-700 first:border-t-0">
										<span class="text-surface-500 mr-2 select-none">{li + 1}</span>{line}
									</div>
								{/each}
							{/if}
						{/each}
					{:else}
						<p class="text-surface-500">No logs available yet.</p>
					{/if}
				</div>
			</div>
			{/if}
		</section>

		<!-- Status Messages -->
		{#if job.status === 'completed'}
			<div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded">
				Analysis completed successfully. Results are ready.
			</div>
		{:else if job.status === 'failed'}
			<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
				Analysis failed. Check the logs for details.
			</div>
		{:else if job.status === 'cancelled'}
			<div class="bg-orange-100 border border-orange-400 text-orange-700 px-4 py-3 rounded">
				Job was cancelled by user. All SLURM jobs have been terminated.
			</div>
		{:else if job.still_active}
			<div class="bg-yellow-100 border border-yellow-400 text-yellow-800 px-4 py-3 rounded flex items-center gap-2">
				<svg class="animate-spin h-4 w-4 shrink-0" viewBox="0 0 24 24">
					<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"></circle>
					<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
				</svg>
				<span>Job is still running on the cluster. Live updates will resume shortly.</span>
			</div>
		{:else}
			<div class="bg-blue-100 border border-blue-400 text-blue-700 px-4 py-3 rounded flex items-center gap-2">
				<svg class="animate-spin h-4 w-4" viewBox="0 0 24 24">
					<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"></circle>
					<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
				</svg>
				<span>Job is running. This page will update automatically.</span>
			</div>
		{/if}

		{#if job.status === 'failed' || job.status === 'cancelled' || job.still_active === false}
			<div class="flex justify-end">
				<button
					type="button"
					onclick={resumeFailedJob}
					disabled={resumeInFlight}
					class="btn variant-filled-primary px-4 py-2 text-sm font-semibold"
				>{resumeInFlight ? 'Resuming...' : 'Resume from where it failed'}</button>
			</div>
		{/if}
	{:else}
		<div class="card p-8 bg-surface-100 dark:bg-surface-800 text-center">
			<p class="text-surface-500">Job not found.</p>
		</div>
	{/if}

	{#if pendingLargeFile}
		<!-- svelte-ignore a11y_click_events_have_key_events -->
		<div class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onclick={() => pendingLargeFile = null} role="button" tabindex="-1">
			<!-- svelte-ignore a11y_click_events_have_key_events -->
			<div class="bg-surface-100 dark:bg-surface-800 rounded-lg shadow-2xl max-w-md w-full overflow-y-auto app-pop-in" onclick={(e) => e.stopPropagation()} role="dialog" tabindex="-1">
				<div class="px-6 py-4 border-b border-surface-300 dark:border-surface-600">
					<h2 class="text-xl font-bold text-primary-500">Large file</h2>
				</div>
				<div class="px-6 py-5 space-y-3 text-surface-700 dark:text-surface-300">
					<p><span class="font-mono text-sm">{pendingLargeFile.name}</span> is {formatFileSize(pendingLargeFile.size)}.</p>
					<p class="text-sm">Loading the row count for a file this size may take a few seconds. Continue?</p>
				</div>
				<div class="px-6 py-4 border-t border-surface-300 dark:border-surface-600 flex justify-end gap-3">
					<button type="button" onclick={() => pendingLargeFile = null} class="btn variant-ghost-primary btn-sm">Cancel</button>
					<button type="button" onclick={confirmViewLargeFile} class="btn variant-filled-primary btn-sm">View Anyway</button>
				</div>
			</div>
		</div>
	{/if}
</div>
