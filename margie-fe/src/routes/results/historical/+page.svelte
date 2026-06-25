<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { Search, Filter } from 'lucide-svelte';
	import { authHeaders, clearToken } from '$lib/auth.js';

	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000'
		: '';

	function handle401() { clearToken(); goto('/login'); }

	type JobStatus = 'pending' | 'running' | 'snakemake' | 'completed' | 'failed' | 'cancelled';

	interface HistoryJob {
		job_id: string;
		status: JobStatus;
		phase?: string;
		genome_path?: string;
		workflow: string;
		work_dir?: string;
		start_time: string;
	}

	interface WorkflowOption {
		id: string;
		label: string;
	}

	let jobs = $state<HistoryJob[]>([]);
	let availableWorkflows = $state<WorkflowOption[]>([]);
	let loading = $state(true);
	let error = $state('');

	const PAGE_SIZE = 20;
	let currentPage = $state(1);
	let totalPages = $state(1);
	let totalJobs = $state(0);

	let searchQuery = $state('');
	let filterStatus = $state('all');
	let filterWorkflow = $state('all');

	let filteredJobs = $derived(jobs.filter(job => {
		const haystack = `${job.genome_path ?? ''} ${job.job_id}`.toLowerCase();
		const matchesSearch = haystack.includes(searchQuery.toLowerCase());
		const matchesStatus = filterStatus === 'all' || job.status === filterStatus;
		return matchesSearch && matchesStatus;
	}));

	function workflowLabel(id?: string): string {
		if (!id) return 'Unknown';
		return availableWorkflows.find(w => w.id === id)?.label ?? id;
	}

	async function loadWorkflows() {
		try {
			const res = await fetch(`${API_URL}/v1/ssh/workflows`, { headers: authHeaders() });
			if (res.ok) {
				availableWorkflows = (await res.json()).map((wf: any) => ({ id: wf.id, label: wf.label }));
			}
		} catch {}
	}

	async function loadJobs() {
		loading = true;
		error = '';
		try {
			const params = new URLSearchParams({ page: String(currentPage), page_size: String(PAGE_SIZE) });
			if (filterWorkflow !== 'all') params.set('workflow', filterWorkflow);
			const res = await fetch(`${API_URL}/v1/ssh/jobs?${params}`, { headers: authHeaders() });
			if (res.status === 401) { handle401(); return; }
			if (!res.ok) throw new Error('Failed to load job history');
			const data = await res.json();
			jobs = data.jobs ?? [];
			totalPages = data.total_pages ?? 1;
			totalJobs = data.total_jobs ?? jobs.length;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load job history';
			jobs = [];
		} finally {
			loading = false;
		}
	}

	function onWorkflowFilterChange() {
		currentPage = 1;
		loadJobs();
	}

	function prevPage() {
		if (currentPage > 1) {
			currentPage -= 1;
			loadJobs();
		}
	}

	function nextPage() {
		if (currentPage < totalPages) {
			currentPage += 1;
			loadJobs();
		}
	}

	onMount(async () => {
		await loadWorkflows();
		await loadJobs();
	});

	function viewJob(jobId: string) {
		goto(`/jobs/${jobId}`);
	}

	function formatTime(time?: string): string {
		if (!time) return '-';
		return new Date(time).toLocaleString();
	}

	function statusBadgeClass(status: JobStatus): string {
		switch (status) {
			case 'completed': return 'variant-filled-success';
			case 'failed': return 'variant-filled-error';
			case 'cancelled': return 'variant-filled-warning';
			default: return 'variant-filled-primary';
		}
	}

	function statusLabel(status: JobStatus): string {
		switch (status) {
			case 'completed': return 'Completed';
			case 'failed': return 'Failed';
			case 'cancelled': return 'Cancelled';
			case 'snakemake': return 'Running Snakemake';
			case 'running': return 'Running';
			default: return 'Pending';
		}
	}
</script>

<div class="w-full px-4 md:px-6 py-8 space-y-8">
	<!-- Page Header -->
	<section>
		<h1 class="text-4xl font-bold text-primary-500 mb-2">Analysis History</h1>
		<p class="text-lg text-surface-600 dark:text-surface-300">
			Browse and resume previous runs — find older jobs by genome path, job ID, workflow, or status, then jump back into the job view.
		</p>
	</section>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">{error}</div>
	{/if}

	<!-- Search and Filter Bar -->
	<section class="card p-4 bg-surface-100 dark:bg-surface-800">
		<div class="flex flex-col md:flex-row gap-4">
			<div class="flex-1 relative">
				<Search class="absolute left-3 top-1/2 transform -translate-y-1/2 size-5 text-surface-500" />
				<input
					type="text"
					placeholder="Search by genome path or job ID..."
					bind:value={searchQuery}
					class="input w-full pl-10 pr-4 py-2 rounded-lg bg-surface-200 dark:bg-surface-700 border border-surface-300 dark:border-surface-600"
				/>
			</div>
			<div class="flex items-center gap-2">
				<Filter class="size-5 text-surface-500" />
				<select
					bind:value={filterWorkflow}
					onchange={onWorkflowFilterChange}
					class="input px-4 py-2 rounded-lg bg-surface-200 dark:bg-surface-700 border border-surface-300 dark:border-surface-600"
				>
					<option value="all">All Workflows</option>
					{#each availableWorkflows as wf}
						<option value={wf.id}>{wf.label}</option>
					{/each}
				</select>
				<select
					bind:value={filterStatus}
					class="input px-4 py-2 rounded-lg bg-surface-200 dark:bg-surface-700 border border-surface-300 dark:border-surface-600"
				>
					<option value="all">All Status</option>
					<option value="completed">Completed</option>
					<option value="failed">Failed</option>
					<option value="running">Running</option>
					<option value="pending">Pending</option>
					<option value="cancelled">Cancelled</option>
				</select>
			</div>
		</div>
	</section>


	<!-- Results Summary -->
	<div class="grid grid-cols-1 md:grid-cols-3 gap-4">
		<div class="card p-4 bg-surface-100 dark:bg-surface-800">
			<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">Total Analyses</p>
			<p class="text-3xl font-bold text-primary-500">{totalJobs}</p>
		</div>
		<div class="card p-4 bg-surface-100 dark:bg-surface-800">
			<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">Completed</p>
			<p class="text-3xl font-bold text-success-500">{jobs.filter(j => j.status === 'completed').length}</p>
		</div>
		<div class="card p-4 bg-surface-100 dark:bg-surface-800">
			<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">Failed</p>
			<p class="text-3xl font-bold text-error-500">{jobs.filter(j => j.status === 'failed').length}</p>
		</div>
	</div>

	<!-- Job List -->
	<section class="card bg-surface-100 dark:bg-surface-800 overflow-hidden">
		{#if loading}
			<div class="p-12 text-center text-surface-500">
				<p class="text-lg">Loading job history...</p>
			</div>
		{:else}
			<div class="overflow-x-auto">
				<table class="table table-hover w-full">
					<thead>
						<tr class="bg-surface-200 dark:bg-surface-700">
							<th class="p-4 text-left">Job ID</th>
							<th class="p-4 text-left">Workflow</th>
							<th class="p-4 text-left">Genome Path</th>
							<th class="p-4 text-left">Started</th>
							<th class="p-4 text-left">Status</th>
							<th class="p-4 text-left">Actions</th>
						</tr>
					</thead>
					<tbody>
						{#each filteredJobs as job}
							<tr class="hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors align-top">
								<td class="p-4 font-mono text-xs">{job.job_id}</td>
								<td class="p-4 text-sm font-semibold">{workflowLabel(job.workflow)}</td>
								<td class="p-4 text-sm font-mono">{job.genome_path ?? 'N/A'}</td>
								<td class="p-4 text-sm">{formatTime(job.start_time)}</td>
								<td class="p-4">
									<span class="badge {statusBadgeClass(job.status)}">{statusLabel(job.status)}</span>
								</td>
								<td class="p-4">
									<button
										type="button"
										class="btn variant-ghost-primary btn-sm"
										onclick={() => viewJob(job.job_id)}
									>View</button>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>

			{#if filteredJobs.length === 0 && jobs.length === 0}
				<div class="p-12 text-center text-surface-500">
					<p class="text-lg mb-2">No past jobs yet</p>
					<p class="text-sm">Run an analysis from the Analyze page and it'll show up here.</p>
				</div>
			{:else if filteredJobs.length === 0}
				<div class="p-12 text-center text-surface-500">
					<p class="text-lg mb-2">No results found</p>
					<p class="text-sm">Try adjusting your search or filter criteria</p>
				</div>
			{/if}

			<div class="flex items-center justify-between gap-3 px-4 py-3 border-t border-surface-300 dark:border-surface-600">
				<button type="button" onclick={prevPage} disabled={currentPage <= 1}
					class="btn variant-ghost-primary btn-sm">Previous</button>
				<span class="text-sm text-surface-600 dark:text-surface-300">Page {currentPage} of {totalPages} ({totalJobs} total)</span>
				<button type="button" onclick={nextPage} disabled={currentPage >= totalPages}
					class="btn variant-ghost-primary btn-sm">Next</button>
			</div>
		{/if}
	</section>
</div>
