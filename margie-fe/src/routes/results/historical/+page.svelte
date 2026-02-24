<script lang="ts">
	import { Search, Filter, ChevronDown, ChevronRight } from 'lucide-svelte';

	type AnnotationTool = {
		name: string;
		version: string;
		db: string | null;
	};

	type Result = {
		id: string;
		name: string;
		date: string;
		time: string;
		status: string;
		contigs: number;
		length: string;
		quality: number;
		annotations: AnnotationTool[];
	};

	const results: Result[] = [
		{
			id: 'GEN-2024-001234',
			name: 'E. coli K-12 MG1655',
			date: '2024-12-29',
			time: '14:32',
			status: 'completed',
			contigs: 1247,
			length: '4.8 Mbp',
			quality: 94.2,
			annotations: [
				{ name: 'Prodigal', version: 'v4.0.1', db: null },
				{ name: 'COG',      version: 'v2.0.0', db: 'v1-jan2026' },
				{ name: 'Pfam',     version: 'v1.0.0', db: 'v1-feb2026' }
			]
		},
		{
			id: 'GEN-2024-001233',
			name: 'B. longum NCC2705',
			date: '2024-12-28',
			time: '09:15',
			status: 'completed',
			contigs: 892,
			length: '2.3 Mbp',
			quality: 91.7,
			annotations: [
				{ name: 'Prodigal', version: 'v4.0.1', db: null },
				{ name: 'COG',      version: 'v2.0.0', db: 'v1-jan2026' }
			]
		},
		{
			id: 'GEN-2024-001232',
			name: 'Ruminococcaceae UCG13',
			date: '2024-12-27',
			time: '16:48',
			status: 'completed',
			contigs: 2134,
			length: '3.6 Mbp',
			quality: 88.3,
			annotations: [
				{ name: 'Prodigal', version: 'v4.0.1', db: null },
				{ name: 'COG',      version: 'v2.0.0', db: 'v1-jan2026' },
				{ name: 'Pfam',     version: 'v1.0.0', db: 'v1-feb2026' }
			]
		},
		{
			id: 'GEN-2024-001231',
			name: 'Methanobrevibacter smithii',
			date: '2024-12-26',
			time: '11:22',
			status: 'failed',
			contigs: 0,
			length: 'N/A',
			quality: 0,
			annotations: []
		},
		{
			id: 'GEN-2024-001230',
			name: 'Lactobacillus acidophilus',
			date: '2024-12-25',
			time: '13:05',
			status: 'completed',
			contigs: 1567,
			length: '2.0 Mbp',
			quality: 96.1,
			annotations: [
				{ name: 'Prodigal', version: 'v4.0.1', db: null },
				{ name: 'Pfam',     version: 'v1.0.0', db: 'v1-feb2026' }
			]
		}
	];

	let searchQuery = '';
	let filterStatus = 'all';
	let expandedRows = new Set<string>();

	$: filteredResults = results.filter(result => {
		const matchesSearch = result.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
		                     result.id.toLowerCase().includes(searchQuery.toLowerCase());
		const matchesFilter = filterStatus === 'all' || result.status === filterStatus;
		return matchesSearch && matchesFilter;
	});

	function toggleRow(id: string) {
		if (expandedRows.has(id)) expandedRows.delete(id);
		else expandedRows.add(id);
		expandedRows = expandedRows;
	}

	function viewResult(id: string) {
		window.location.href = `/results/current?id=${id}`;
	}

	const toolColors: Record<string, string> = {
		Prodigal: 'variant-soft-primary',
		COG:      'variant-soft-tertiary',
		Pfam:     'variant-soft-secondary'
	};
</script>

<!-- Under Construction Banner -->
<div class="bg-warning-500/20 border-y-4 border-warning-500 py-4">
	<div class="container mx-auto px-4 flex items-center justify-center gap-3 flex-wrap">
		<span class="text-2xl">🚧</span>
		<p class="text-lg font-semibold text-warning-700 dark:text-warning-300">
			Under Construction — For demo purposes only. Data shown is not real.
		</p>
		<span class="text-2xl">🧪</span>
	</div>
</div>

<div class="container mx-auto p-8 space-y-8 max-w-6xl">
	<!-- Page Header -->
	<section>
		<h1 class="text-4xl font-bold text-primary-500 mb-2">Analysis History</h1>
		<p class="text-lg text-surface-600 dark:text-surface-300">View and manage your previous genome analyses</p>
	</section>

	<!-- Search and Filter Bar -->
	<section class="card p-4 bg-surface-100 dark:bg-surface-800">
		<div class="flex flex-col md:flex-row gap-4">
			<div class="flex-1 relative">
				<Search class="absolute left-3 top-1/2 transform -translate-y-1/2 size-5 text-surface-500" />
				<input
					type="text"
					placeholder="Search by sample name or ID..."
					bind:value={searchQuery}
					class="input w-full pl-10 pr-4 py-2 rounded-lg bg-surface-200 dark:bg-surface-700 border border-surface-300 dark:border-surface-600"
				/>
			</div>
			<div class="flex items-center gap-2">
				<Filter class="size-5 text-surface-500" />
				<select
					bind:value={filterStatus}
					class="input px-4 py-2 rounded-lg bg-surface-200 dark:bg-surface-700 border border-surface-300 dark:border-surface-600"
				>
					<option value="all">All Status</option>
					<option value="completed">Completed</option>
					<option value="failed">Failed</option>
					<option value="processing">Processing</option>
				</select>
			</div>
		</div>
	</section>

	<!-- Results Summary -->
	<div class="grid grid-cols-1 md:grid-cols-3 gap-4">
		<div class="card p-4 bg-surface-100 dark:bg-surface-800">
			<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">Total Analyses</p>
			<p class="text-3xl font-bold text-primary-500">{results.length}</p>
		</div>
		<div class="card p-4 bg-surface-100 dark:bg-surface-800">
			<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">Completed</p>
			<p class="text-3xl font-bold text-success-500">{results.filter(r => r.status === 'completed').length}</p>
		</div>
		<div class="card p-4 bg-surface-100 dark:bg-surface-800">
			<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">Failed</p>
			<p class="text-3xl font-bold text-error-500">{results.filter(r => r.status === 'failed').length}</p>
		</div>
	</div>

	<!-- Results List -->
	<section class="card bg-surface-100 dark:bg-surface-800 overflow-hidden">
		<div class="overflow-x-auto">
			<table class="table table-hover w-full">
				<thead>
					<tr class="bg-surface-200 dark:bg-surface-700">
						<th class="p-4 text-left">Sample ID</th>
						<th class="p-4 text-left">Sample Name</th>
						<th class="p-4 text-left">Date</th>
						<th class="p-4 text-left">Status</th>
						<th class="p-4 text-left">Contigs</th>
						<th class="p-4 text-left">Length</th>
						<th class="p-4 text-left">Quality</th>
						<th class="p-4 text-left">Annotation Sources</th>
						<th class="p-4 text-left">Actions</th>
					</tr>
				</thead>
				<tbody>
					{#each filteredResults as result}
						<tr class="hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors align-top">
							<td class="p-4 font-mono text-sm">{result.id}</td>
							<td class="p-4 font-semibold">{result.name}</td>
							<td class="p-4 text-sm">
								<div>{result.date}</div>
								<div class="text-xs text-surface-500">{result.time}</div>
							</td>
							<td class="p-4">
								{#if result.status === 'completed'}
									<span class="badge variant-filled-success">Completed</span>
								{:else if result.status === 'failed'}
									<span class="badge variant-filled-error">Failed</span>
								{:else if result.status === 'processing'}
									<span class="badge variant-filled-warning">Processing</span>
								{/if}
							</td>
							<td class="p-4 text-sm">{result.contigs.toLocaleString()}</td>
							<td class="p-4 text-sm">{result.length}</td>
							<td class="p-4">
								{#if result.status === 'completed'}
									<div class="flex items-center gap-2">
										<div class="w-16 bg-surface-300 dark:bg-surface-600 rounded-full h-2">
											<div class="bg-success-500 h-2 rounded-full" style="width: {result.quality}%"></div>
										</div>
										<span class="text-sm">{result.quality}%</span>
									</div>
								{:else}
									<span class="text-sm text-surface-500">N/A</span>
								{/if}
							</td>
							<!-- Annotation Sources -->
							<td class="p-4">
								{#if result.annotations.length === 0}
									<span class="text-sm text-surface-500">N/A</span>
								{:else}
									<button
										class="flex items-center gap-1 hover:opacity-80 transition-opacity"
										on:click={() => toggleRow(result.id)}
										aria-expanded={expandedRows.has(result.id)}
									>
										<div class="flex flex-wrap gap-1">
											{#each result.annotations as tool}
												<span class="badge text-xs {toolColors[tool.name] ?? 'variant-soft'}">
													{tool.name}
												</span>
											{/each}
										</div>
										{#if expandedRows.has(result.id)}
											<ChevronDown class="size-4 text-surface-500 shrink-0" />
										{:else}
											<ChevronRight class="size-4 text-surface-500 shrink-0" />
										{/if}
									</button>

									{#if expandedRows.has(result.id)}
										<div class="mt-2 space-y-1 text-xs border-l-2 border-surface-300 dark:border-surface-600 pl-2">
											{#each result.annotations as tool}
												<div class="text-surface-700 dark:text-surface-300">
													<span class="font-semibold">{tool.name}</span>
													<span class="text-surface-500"> {tool.version}</span>
													{#if tool.db}
														<span class="text-surface-400"> · db {tool.db}</span>
													{:else}
														<span class="text-surface-400"> · no db</span>
													{/if}
												</div>
											{/each}
										</div>
									{/if}
								{/if}
							</td>
							<td class="p-4">
								<div title="Disabled: will show comprehensive gene annotation dashboard">
									<button
										class="btn variant-ghost-primary btn-sm"
										disabled
									>
										View
									</button>
								</div>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>

		{#if filteredResults.length === 0}
			<div class="p-12 text-center text-surface-500">
				<p class="text-lg mb-2">No results found</p>
				<p class="text-sm">Try adjusting your search or filter criteria</p>
			</div>
		{/if}
	</section>

	<!-- Pagination (Mock) -->
	<div class="flex justify-center gap-2">
		<button class="btn variant-ghost-secondary" disabled>Previous</button>
		<button class="btn variant-filled-primary">1</button>
		<button class="btn variant-ghost-secondary">2</button>
		<button class="btn variant-ghost-secondary">3</button>
		<button class="btn variant-ghost-secondary">Next</button>
	</div>
</div>
