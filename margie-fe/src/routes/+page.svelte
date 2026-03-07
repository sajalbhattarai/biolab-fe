<script lang="ts">
	import { goto } from '$app/navigation';
</script>

<!-- Beta Banner -->
<div class="bg-primary-500/10 border-y-2 border-primary-400 py-3">
	<div class="container mx-auto px-4 flex items-center justify-center gap-3 flex-wrap">
		<span class="text-xl">🧬</span>
		<p class="text-base font-semibold text-primary-700 dark:text-primary-300">
			You're using an early beta — features may change and some are still in progress.
		</p>
		<a
			href="https://bioinformatics-tools.readthedocs.io/en/latest/"
			target="_blank"
			rel="noopener noreferrer"
			class="inline-flex items-center gap-1 text-sm font-medium text-primary-600 dark:text-primary-400 underline underline-offset-2 hover:text-primary-800 dark:hover:text-primary-200 transition-colors"
		>
			📖 Read the docs
		</a>
		<span class="text-xl">🚀</span>
	</div>
</div>

<div class="container mx-auto p-8 space-y-8">
	<!-- Quick Navigation Section -->
	<section>
		<div class="max-w-4xl mx-auto space-y-4">
			<!-- Primary: Analyze -->
			<button class="card w-full p-8 bg-primary-500 hover:bg-primary-600 transition-colors text-center" on:click={() => goto('analyze')}>
				<div class="flex items-center justify-center gap-3">
					<span class="text-4xl">🧬</span>
					<h2 class="text-2xl font-bold text-white">Analyze</h2>
				</div>
				<p class="text-primary-100 mt-2">Submit a genome for annotation</p>
			</button>

			<!-- Secondary tools -->
			<div class="grid grid-cols-2 gap-3">
				<!-- TODO: Re-enable when SLURM credentials/resources can be specified
				<button class="card p-4 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors text-center" on:click={() => goto('run_script')}>
					<div class="text-2xl mb-1">⚙️</div>
					<p class="text-sm font-medium">Run SLURM</p>
				</button>
				-->
				<button class="card p-4 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors text-center" on:click={() => goto('run_ssh')}>
					<div class="text-2xl mb-1">🖥️</div>
					<p class="text-sm font-medium">Run SSH</p>
				</button>
				<button class="card p-4 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors text-center" on:click={() => goto('filesearch')}>
					<div class="text-2xl mb-1">🔍</div>
					<p class="text-sm font-medium">File Search</p>
				</button>
			</div>

			<!-- Analysis History -->
			<button class="card w-full p-6 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors text-center" on:click={() => goto('results/historical')}>
				<div class="flex items-center justify-center gap-3">
					<span class="text-3xl">📜</span>
					<h3 class="text-xl font-semibold text-secondary-500">Analysis History</h3>
				</div>
				<p class="text-surface-600 dark:text-surface-300 mt-1">Review previous genome submissions and analyses</p>
			</button>
		</div>
	</section>

	<!-- Programs & Tools Section -->
	<section>
		<h2 class="text-3xl font-bold text-center mb-8">Analysis Programs & Tools</h2>
		<p class="text-center text-surface-600 dark:text-surface-300 mb-8">Industry-leading bioinformatics tools for comprehensive genome analysis</p>

		<div class="grid grid-cols-1 md:grid-cols-3 gap-4 max-w-4xl mx-auto">
			<a href="https://github.com/hyattpd/Prodigal" target="_blank" rel="noopener noreferrer" class="card p-5 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors">
				<div class="flex items-start justify-between mb-2">
					<h3 class="text-lg font-semibold text-primary-500">Prodigal</h3>
					<span class="text-xs text-surface-500">v2.6.3</span>
				</div>
				<p class="text-sm text-surface-600 dark:text-surface-300">Prokaryotic gene recognition and translation initiation site identification</p>
			</a>

			<a href="https://pfam.xfam.org/" target="_blank" rel="noopener noreferrer" class="card p-5 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors">
				<div class="flex items-start justify-between mb-2">
					<h3 class="text-lg font-semibold text-secondary-500">Pfam</h3>
					<span class="text-xs text-surface-500">v37.0</span>
				</div>
				<p class="text-sm text-surface-600 dark:text-surface-300">Protein family database for domain annotation and functional classification</p>
			</a>

			<a href="https://www.ncbi.nlm.nih.gov/research/cog/" target="_blank" rel="noopener noreferrer" class="card p-5 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors">
				<div class="flex items-start justify-between mb-2">
					<h3 class="text-lg font-semibold text-tertiary-500">COG</h3>
					<span class="text-xs text-surface-500">2020</span>
				</div>
				<p class="text-sm text-surface-600 dark:text-surface-300">Clusters of Orthologous Groups for evolutionary gene classification</p>
			</a>
		</div>
	</section>

	<!-- Footer -->
	<footer class="text-center py-8 border-t border-surface-300 dark:border-surface-700">
		<p class="text-surface-600 dark:text-surface-300">© 2026 Dane Deemer</p>
	</footer>
</div>
