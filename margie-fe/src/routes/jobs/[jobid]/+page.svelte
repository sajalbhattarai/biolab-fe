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
	}

	interface ContainerInfo {
		name: string;
		version: string;
		path: string;
		source: 'cached' | 'downloaded';
		docker_url: string;
	}

	interface FileEntry {
		name: string;
		type: 'file' | 'directory';
		size?: number;
	}

	interface JobStatus {
		job_id: string;
		status: 'pending' | 'running' | 'snakemake' | 'completed' | 'failed';
		phase: string;
		progress?: number;
		steps_done?: number;
		steps_total?: number;
		start_time?: string;
		end_time?: string;
		genome_path?: string;
		work_dir?: string;
		sub_jobs: SubJob[];
		slurm_jobs?: SlurmJob[];
		containers?: ContainerInfo[];
		logs?: string;
	}

	let jobId = $derived($page.params.jobid);
	let job = $state<JobStatus | null>(null);
	let error = $state('');
	let loading = $state(true);
	let pollInterval: ReturnType<typeof setInterval> | null = null;
	let showLogs = $state(true);  // Show logs by default
	let showContainers = $state(true);

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

			// Stop polling if job is done
			if (job && (job.status === 'completed' || job.status === 'failed')) {
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

	async function downloadFile(fileName: string) {
		const apiUrl = getApiUrl();
		const relativePath = currentSubdir ? `${currentSubdir}/${fileName}` : fileName;
		const url = `${apiUrl}/v1/ssh/download_file/${jobId}?path=${encodeURIComponent(relativePath)}`;
		try {
			const res = await fetch(url, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) { filesError = 'Download failed'; return; }
			const blob = await res.blob();
			const blobUrl = URL.createObjectURL(blob);
			const a = document.createElement('a');
			a.href = blobUrl;
			a.download = fileName;
			a.click();
			URL.revokeObjectURL(blobUrl);
		} catch (e) {
			filesError = e instanceof Error ? e.message : 'Download failed';
		}
	}

	function navigateToDir(dirName: string) {
		const newSubdir = currentSubdir ? `${currentSubdir}/${dirName}` : dirName;
		fetchJobFiles(newSubdir);
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
			default: return 'bg-gray-400';
		}
	}

	function getStatusText(status: string): string {
		switch (status) {
			case 'completed': return 'Completed';
			case 'running': return 'Running';
			case 'snakemake': return 'Running Snakemake';
			case 'failed': return 'Failed';
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

	$effect(() => {
		// Refetch when jobId changes (only in browser)
		if (typeof window !== 'undefined' && jobId) {
			loading = true;
			fetchJobStatus();
		}
	});

</script>

<div class="container mx-auto p-8 max-w-5xl space-y-6">
	<div class="flex items-center justify-between">
		<h1 class="text-3xl font-bold text-primary-500">Job Monitor</h1>
		<a href="/analyze" class="btn variant-ghost-surface px-4 py-2">New Analysis</a>
	</div>

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
				<div class="flex items-center gap-2">
					<span class="inline-block w-3 h-3 rounded-full {getStatusColor(job.status)}"></span>
					<span class="font-semibold">{getStatusText(job.status)}</span>
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
			<h2 class="text-xl font-semibold mb-4">Slurm Jobs</h2>
			{#if (job.slurm_jobs ?? []).length > 0}
				<div class="overflow-x-auto">
					<table class="w-full text-sm text-left">
						<thead class="text-xs uppercase text-surface-500 border-b border-surface-300 dark:border-surface-600">
							<tr>
								<th class="px-4 py-3">Job ID</th>
								<th class="px-4 py-3">Rule</th>
								<th class="px-4 py-3">Status</th>
								<th class="px-4 py-3">Time</th>
							</tr>
						</thead>
						<tbody>
							{#each job.slurm_jobs ?? [] as sj}
								<tr class="border-b border-surface-200 dark:border-surface-700">
									<td class="px-4 py-3 font-mono">{sj.job_id}</td>
									<td class="px-4 py-3 font-mono">{sj.rule ?? ''}</td>
									<td class="px-4 py-3 font-semibold {getSlurmStatusColor(sj.status)}">{sj.status}</td>
									<td class="px-4 py-3 font-mono">{sj.time}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{:else}
				<p class="text-surface-500">No jobs currently running on Slurm.</p>
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
				{#if (job.containers ?? []).length > 0}
					<div class="overflow-x-auto mt-4">
						<table class="w-full text-sm text-left">
							<thead class="text-xs uppercase text-surface-500 border-b border-surface-300 dark:border-surface-600">
								<tr>
									<th class="px-4 py-3">Name</th>
									<th class="px-4 py-3">Version</th>
									<th class="px-4 py-3">Source</th>
									<th class="px-4 py-3">Image</th>
								</tr>
							</thead>
							<tbody>
								{#each job.containers ?? [] as c}
									<tr class="border-b border-surface-200 dark:border-surface-700">
										<td class="px-4 py-3 font-mono">{c.name}</td>
										<td class="px-4 py-3 font-mono">{c.version}</td>
										<td class="px-4 py-3">
											<span class="text-xs font-semibold px-2 py-1 rounded {c.source === 'cached' ? 'bg-green-500/20 text-green-500' : 'bg-blue-500/20 text-blue-500'}">
												{c.source === 'cached' ? 'Cached' : 'Downloaded'}
											</span>
										</td>
										<td class="px-4 py-3 font-mono text-xs text-surface-400">{c.docker_url}</td>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
				{:else}
					<p class="text-surface-500 mt-4">No containers loaded yet.</p>
				{/if}
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
				<div class="flex items-center gap-3 mb-2">
					<h2 class="text-xl font-semibold">Output Files</h2>
					{#if job.status === 'completed'}
						<span class="text-xs font-semibold px-2 py-1 rounded bg-green-500/20 text-green-500">Files Complete</span>
					{:else if job.status === 'failed'}
						<span class="text-xs font-semibold px-2 py-1 rounded bg-red-500/20 text-red-500">Failed</span>
					{:else}
						<span class="text-xs font-semibold px-2 py-1 rounded bg-yellow-500/20 text-yellow-500 animate-pulse">Pending</span>
					{/if}
				</div>
				<p class="text-sm text-surface-500 mb-2 font-mono">{job.work_dir}</p>
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
					<div class="space-y-1">
						{#each outputFiles as entry}
							{#if entry.type === 'directory'}
								<button
									type="button"
									onclick={() => navigateToDir(entry.name)}
									class="flex items-center justify-between px-3 py-2 rounded bg-surface-200 dark:bg-surface-700 hover:bg-surface-300 dark:hover:bg-surface-600 w-full text-left"
								>
									<div class="flex items-center gap-2">
										<span class="text-yellow-500">&#128193;</span>
										<span class="font-mono text-sm">{entry.name}/</span>
									</div>
								</button>
							{:else}
								<div class="flex items-center justify-between px-3 py-2 rounded bg-surface-200 dark:bg-surface-700">
									<div class="flex items-center gap-2">
										<span class="text-surface-400">&#128196;</span>
										<span class="font-mono text-sm">{entry.name}</span>
									</div>
									<div class="flex items-center gap-3">
										<span class="text-xs text-surface-400">{formatFileSize(entry.size)}</span>
										<button
											type="button"
											onclick={() => downloadFile(entry.name)}
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
				<div class="mt-4 p-4 bg-surface-900 text-green-400 font-mono text-sm rounded-lg overflow-x-auto max-h-96 overflow-y-auto">
					{#if job.logs}
						{#each job.logs.split('\n').filter(line => line.trim()) as line, i}
							<div class="py-1 {i > 0 ? 'border-t border-surface-700' : ''}">
								<span class="text-surface-500 mr-2 select-none">{i + 1}</span>{line}
							</div>
						{/each}
					{:else}
						<p class="text-surface-500">No logs available yet.</p>
					{/if}
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
		{:else}
			<div class="bg-blue-100 border border-blue-400 text-blue-700 px-4 py-3 rounded flex items-center gap-2">
				<svg class="animate-spin h-4 w-4" viewBox="0 0 24 24">
					<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"></circle>
					<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
				</svg>
				<span>Job is running. This page will update automatically.</span>
			</div>
		{/if}
	{:else}
		<div class="card p-8 bg-surface-100 dark:bg-surface-800 text-center">
			<p class="text-surface-500">Job not found.</p>
		</div>
	{/if}
</div>
