<script lang="ts">
	import { Download, Share2, AlertCircle } from 'lucide-svelte';

	// Mock data for the graph
	const graphData = [
		{ label: 'Bacteria', value: 78, color: '#3b82f6' },
		{ label: 'Archaea', value: 15, color: '#10b981' },
		{ label: 'Eukarya', value: 5, color: '#f59e0b' },
		{ label: 'Virus', value: 2, color: '#ef4444' }
	];

	const maxValue = Math.max(...graphData.map(d => d.value));

	function downloadResults() {
		alert('Downloading results...');
	}

	function shareResults() {
		alert('Sharing results...');
	}
</script>

<div class="w-full px-4 md:px-6 py-8 space-y-8">
	<!-- Page Header -->
	<section class="flex justify-between items-start">
		<div>
			<h1 class="text-4xl font-bold text-primary-500 mb-2">Analysis Results</h1>
			<p class="text-sm text-surface-500 dark:text-surface-400 mb-2">This mock results page demonstrates the kinds of outputs the real workflow will surface after a run completes.</p>
			<p class="text-lg text-surface-600 dark:text-surface-300">Sample ID: <span class="font-mono font-semibold">GEN-2024-001234</span></p>
			<p class="text-sm text-surface-500">Completed: December 29, 2024 at 14:32 UTC</p>
		</div>
		<div class="flex gap-2">
			<button class="btn variant-outline-primary" onclick={shareResults}>
				<Share2 class="size-4 mr-2" />
				Share
			</button>
			<button class="btn variant-filled-primary" onclick={downloadResults}>
				<Download class="size-4 mr-2" />
				Download Report
			</button>
		</div>
	</section>

	<!-- Status Banner -->
	<div class="card p-4 bg-success-100 dark:bg-success-900/20 border border-success-500/30">
		<div class="flex items-center gap-3">
			<div class="text-2xl">✓</div>
			<div>
				<p class="font-semibold text-success-700 dark:text-success-300">Analysis Completed Successfully</p>
				<p class="text-sm text-success-600 dark:text-success-400">All pipeline stages completed without errors</p>
			</div>
		</div>
	</div>

	<!-- Summary Statistics -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<div class="flex items-center gap-2 mb-6">
			<h2 class="text-2xl font-bold text-primary-500">Summary Statistics</h2>
		</div>

		<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
			<div class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
				<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">Total Contigs</p>
				<p class="text-3xl font-bold text-primary-500">1,247</p>
			</div>
			<div class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
				<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">Total Length</p>
				<p class="text-3xl font-bold text-secondary-500">4.8 Mbp</p>
			</div>
			<div class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
				<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">N50 Value</p>
				<p class="text-3xl font-bold text-tertiary-500">12,456</p>
			</div>
			<div class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
				<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">GC Content</p>
				<p class="text-3xl font-bold text-warning-500">42.3%</p>
			</div>
		</div>
	</section>

	<!-- Quality Metrics -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<div class="flex items-center gap-2 mb-6">
			<h2 class="text-2xl font-bold text-secondary-500">Quality Metrics</h2>
		</div>

		<div class="space-y-4">
			<div>
				<div class="flex justify-between mb-2">
					<span class="text-sm font-semibold">Assembly Completeness</span>
					<span class="text-sm font-semibold">94.2%</span>
				</div>
				<div class="w-full bg-surface-300 dark:bg-surface-700 rounded-full h-3">
					<div class="bg-success-500 h-3 rounded-full" style="width: 94.2%"></div>
				</div>
			</div>

			<div>
				<div class="flex justify-between mb-2">
					<span class="text-sm font-semibold">Annotation Coverage</span>
					<span class="text-sm font-semibold">87.5%</span>
				</div>
				<div class="w-full bg-surface-300 dark:bg-surface-700 rounded-full h-3">
					<div class="bg-primary-500 h-3 rounded-full" style="width: 87.5%"></div>
				</div>
			</div>

			<div>
				<div class="flex justify-between mb-2">
					<span class="text-sm font-semibold">Read Quality Score</span>
					<span class="text-sm font-semibold">38.4 (Phred)</span>
				</div>
				<div class="w-full bg-surface-300 dark:bg-surface-700 rounded-full h-3">
					<div class="bg-tertiary-500 h-3 rounded-full" style="width: 96%"></div>
				</div>
			</div>

			<div class="mt-4 p-4 bg-warning-100 dark:bg-warning-900/20 rounded-lg border border-warning-500/30">
				<div class="flex items-start gap-2">
					<AlertCircle class="size-5 text-warning-600 dark:text-warning-400 mt-0.5" />
					<div>
						<p class="text-sm font-semibold text-warning-700 dark:text-warning-300">Quality Note</p>
						<p class="text-sm text-warning-600 dark:text-warning-400">Contamination level: 1.2% - within acceptable range</p>
					</div>
				</div>
			</div>
		</div>
	</section>

	<!-- Taxonomic Distribution Graph -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<div class="flex items-center gap-2 mb-6">
			<h2 class="text-2xl font-bold text-tertiary-500">Taxonomic Distribution</h2>
		</div>

		<div class="space-y-4">
			{#each graphData as item}
				<div>
					<div class="flex justify-between mb-2">
						<span class="text-sm font-semibold">{item.label}</span>
						<span class="text-sm font-semibold">{item.value}%</span>
					</div>
					<div class="w-full bg-surface-300 dark:bg-surface-700 rounded-full h-8 relative">
						<div
							class="h-8 rounded-full flex items-center justify-end pr-3 text-white text-sm font-semibold transition-all"
							style="width: {item.value}%; background-color: {item.color}"
						>
							{#if item.value > 10}
								{item.value}%
							{/if}
						</div>
					</div>
				</div>
			{/each}
		</div>

		<div class="mt-6 p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
			<p class="text-sm text-surface-600 dark:text-surface-300">
				<strong>Analysis Method:</strong> 16S rRNA gene sequencing with BLAST alignment against NCBI database
			</p>
		</div>
	</section>

	<!-- Gene Predictions -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<div class="flex items-center gap-2 mb-6">
			<h2 class="text-2xl font-bold text-primary-500">Gene Predictions</h2>
		</div>

		<div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
			<div class="p-4 bg-gradient-to-br from-primary-100 to-primary-200 dark:from-primary-900/30 dark:to-primary-800/30 rounded-lg border border-primary-300 dark:border-primary-700">
				<p class="text-sm text-primary-700 dark:text-primary-300 mb-1">Predicted Genes</p>
				<p class="text-3xl font-bold text-primary-600 dark:text-primary-400">4,523</p>
			</div>
			<div class="p-4 bg-gradient-to-br from-secondary-100 to-secondary-200 dark:from-secondary-900/30 dark:to-secondary-800/30 rounded-lg border border-secondary-300 dark:border-secondary-700">
				<p class="text-sm text-secondary-700 dark:text-secondary-300 mb-1">Coding Sequences</p>
				<p class="text-3xl font-bold text-secondary-600 dark:text-secondary-400">4,187</p>
			</div>
			<div class="p-4 bg-gradient-to-br from-tertiary-100 to-tertiary-200 dark:from-tertiary-900/30 dark:to-tertiary-800/30 rounded-lg border border-tertiary-300 dark:border-tertiary-700">
				<p class="text-sm text-tertiary-700 dark:text-tertiary-300 mb-1">RNA Genes</p>
				<p class="text-3xl font-bold text-tertiary-600 dark:text-tertiary-400">336</p>
			</div>
		</div>

		<div class="overflow-x-auto">
			<table class="table table-hover w-full text-sm">
				<thead>
					<tr class="bg-surface-200 dark:bg-surface-700">
						<th class="p-3 text-left">Gene ID</th>
						<th class="p-3 text-left">Product</th>
						<th class="p-3 text-left">Length (bp)</th>
						<th class="p-3 text-left">Confidence</th>
					</tr>
				</thead>
				<tbody>
					<tr>
						<td class="p-3 font-mono">GENE_001234</td>
						<td class="p-3">DNA polymerase III subunit alpha</td>
						<td class="p-3">1,248</td>
						<td class="p-3"><span class="badge variant-filled-success">High</span></td>
					</tr>
					<tr>
						<td class="p-3 font-mono">GENE_001235</td>
						<td class="p-3">50S ribosomal protein L7/L12</td>
						<td class="p-3">378</td>
						<td class="p-3"><span class="badge variant-filled-success">High</span></td>
					</tr>
					<tr>
						<td class="p-3 font-mono">GENE_001236</td>
						<td class="p-3">Hypothetical protein</td>
						<td class="p-3">542</td>
						<td class="p-3"><span class="badge variant-filled-warning">Medium</span></td>
					</tr>
					<tr>
						<td class="p-3 font-mono">GENE_001237</td>
						<td class="p-3">ATP synthase subunit beta</td>
						<td class="p-3">1,512</td>
						<td class="p-3"><span class="badge variant-filled-success">High</span></td>
					</tr>
				</tbody>
			</table>
		</div>
	</section>

	<!-- Phylogenetic Analysis -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<div class="flex items-center gap-2 mb-6">
			<h2 class="text-2xl font-bold text-secondary-500">Phylogenetic Analysis</h2>
		</div>

		<div class="mb-4">
			<p class="text-surface-700 dark:text-surface-300 mb-4">
				Maximum likelihood phylogenetic tree constructed from 16S rRNA sequences. Bootstrap values shown at nodes (1000 replicates).
			</p>
		</div>

		<!-- Image placeholder -->
		<div class="bg-surface-200 dark:bg-surface-700 rounded-lg p-4 flex items-center justify-center min-h-[400px]">
			<img
				src="/phylogenetic-tree.png"
				alt="Phylogenetic Tree"
				class="max-w-full h-auto rounded"
				onerror={(e) => {
					e.currentTarget.style.display = 'none';
					e.currentTarget.parentElement.innerHTML = '<div class="text-center"><p class="text-surface-500 mb-2">📊</p><p class="text-surface-600 dark:text-surface-400">Phylogenetic tree visualization</p><p class="text-sm text-surface-500">Image: /phylogenetic-tree.png</p></div>';
				}}
			/>
		</div>

		<div class="mt-4 grid grid-cols-1 md:grid-cols-2 gap-4">
			<div class="p-3 bg-surface-200 dark:bg-surface-700 rounded">
				<p class="text-sm font-semibold mb-1">Closest Relative</p>
				<p class="text-sm text-surface-600 dark:text-surface-300">Escherichia coli K-12 MG1655 (98.7% identity)</p>
			</div>
			<div class="p-3 bg-surface-200 dark:bg-surface-700 rounded">
				<p class="text-sm font-semibold mb-1">Tree Method</p>
				<p class="text-sm text-surface-600 dark:text-surface-300">Maximum Likelihood (RAxML, GTRGAMMA model)</p>
			</div>
		</div>
	</section>

	<!-- Download Options -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<div class="flex items-center gap-2 mb-6">
			<h2 class="text-2xl font-bold">Download Files</h2>
		</div>

		<div class="grid grid-cols-1 md:grid-cols-2 gap-4">
			<button class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg hover:bg-surface-300 dark:hover:bg-surface-600 transition-colors text-left">
				<p class="font-semibold mb-1">Assembly FASTA</p>
				<p class="text-sm text-surface-600 dark:text-surface-400">genome_assembly.fasta (2.3 MB)</p>
			</button>
			<button class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg hover:bg-surface-300 dark:hover:bg-surface-600 transition-colors text-left">
				<p class="font-semibold mb-1">Annotation GFF3</p>
				<p class="text-sm text-surface-600 dark:text-surface-400">genome_annotation.gff3 (1.8 MB)</p>
			</button>
			<button class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg hover:bg-surface-300 dark:hover:bg-surface-600 transition-colors text-left">
				<p class="font-semibold mb-1">Quality Report</p>
				<p class="text-sm text-surface-600 dark:text-surface-400">quality_report.pdf (456 KB)</p>
			</button>
			<button class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg hover:bg-surface-300 dark:hover:bg-surface-600 transition-colors text-left">
				<p class="font-semibold mb-1">Full Analysis Package</p>
				<p class="text-sm text-surface-600 dark:text-surface-400">complete_results.zip (8.7 MB)</p>
			</button>
		</div>
	</section>
</div>
