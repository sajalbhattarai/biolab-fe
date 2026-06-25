<script lang="ts">
	import { goto } from '$app/navigation';
</script>

<!-- Beta Banner -->
<div class="beta-strip rounded-2xl py-3 px-2 app-fade-in">
	<div class="container mx-auto px-4 flex items-center justify-center gap-3 flex-wrap">
		<span class="text-xl">🧬</span>
		<p class="text-base font-semibold">Early beta release.</p>
		<a
			href="https://bioinformatics-tools.readthedocs.io/en/latest/"
			target="_blank"
			rel="noopener noreferrer"
			class="inline-flex items-center gap-1 text-sm font-medium underline underline-offset-2 transition-colors hover:opacity-80"
		>
			📖 Read the docs
		</a>
		<span class="text-xl">🚀</span>
	</div>
</div>

<div class="w-full px-4 md:px-6 py-6 md:py-8 space-y-10">
	<section class="text-center app-fade-in">
		<h1 class="text-4xl font-bold text-primary-500">Bioinformatics Supercomputing Platform</h1>
		<p class="mt-2 text-surface-600 dark:text-surface-300">Launch analyses, monitor jobs, and manage configuration from one place.</p>
	</section>

	<!-- Quick Navigation Section -->
	<section>
		<div class="w-full space-y-4">
			<!-- Primary: Analyze -->
			<button class="card p-8 md:p-10 bg-surface-100 dark:bg-surface-800 w-full transition-all duration-200 text-center hover:translate-y-[-2px] app-fade-in app-stagger-1" onclick={() => goto('analyze')}>
				<div class="flex items-center justify-center gap-3">
					<span class="text-4xl">🧬</span>
					<h2 class="text-2xl font-bold">Analyze</h2>
				</div>
				<p class="text-surface-600 dark:text-surface-300 mt-2">Submit a genome for annotation</p>
			</button>

			<!-- Secondary tools -->
			<div class="grid grid-cols-2 gap-3">
				<!-- TODO: Re-enable when SLURM credentials/resources can be specified
				<button class="card p-4 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors text-center" onclick={() => goto('run_script')}>
					<div class="text-2xl mb-1">⚙️</div>
					<p class="text-sm font-medium">Run SLURM</p>
				</button>
				-->
				<button class="card p-4 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors text-center app-fade-in app-stagger-2" onclick={() => goto('run_ssh')}>
					<div class="text-2xl mb-1">🖥️</div>
					<p class="text-sm font-medium">Run SSH</p>
				</button>
				<button class="card p-4 bg-surface-100 dark:bg-surface-800 hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors text-center app-fade-in app-stagger-3" onclick={() => goto('filesearch')}>
					<div class="text-2xl mb-1">🔍</div>
					<p class="text-sm font-medium">File Search</p>
				</button>
			</div>

			<!-- Analysis History -->
			<button class="card p-6 bg-surface-100 dark:bg-surface-800 w-full hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors text-center app-fade-in app-stagger-2" onclick={() => goto('results/historical')}>
				<div class="flex items-center justify-center gap-3">
					<span class="text-3xl">📜</span>
					<h3 class="text-xl font-semibold">Analysis History</h3>
				</div>
				<p class="text-surface-600 mt-1">Review previous genome submissions and analyses</p>
			</button>
		</div>
	</section>

	<!-- Programs & Tools Section -->
	<section>
		<div class="flex items-center justify-center gap-3 mb-4">
			<h2 class="text-3xl md:text-4xl font-bold text-center tracking-tight">Analysis Programs & Tools</h2>
		</div>
		<p class="text-center text-surface-700 mb-8">Tools used by the platform for genome analysis.</p>

		<div class="grid grid-cols-1 md:grid-cols-3 gap-4 w-full">
			<a href="https://github.com/hyattpd/Prodigal" target="_blank" rel="noopener noreferrer" class="card p-5 bg-surface-100 dark:bg-surface-800 hover:translate-y-[-2px] transition-all duration-200 app-fade-in app-stagger-1">
				<div class="flex items-start justify-between mb-2">
					<h3 class="text-lg font-semibold text-teal-700">Prodigal</h3>
					<span class="text-xs text-surface-500">v2.6.3</span>
				</div>
				<p class="text-sm text-surface-700">Prokaryotic gene recognition and translation initiation site identification</p>
			</a>

			<a href="https://pfam.xfam.org/" target="_blank" rel="noopener noreferrer" class="card p-5 bg-surface-100 dark:bg-surface-800 hover:translate-y-[-2px] transition-all duration-200 app-fade-in app-stagger-2">
				<div class="flex items-start justify-between mb-2">
					<h3 class="text-lg font-semibold text-amber-700">Pfam</h3>
					<span class="text-xs text-surface-500">v37.0</span>
				</div>
				<p class="text-sm text-surface-700">Protein family database for domain annotation and functional classification</p>
			</a>

			<a href="https://www.ncbi.nlm.nih.gov/research/cog/" target="_blank" rel="noopener noreferrer" class="card p-5 bg-surface-100 dark:bg-surface-800 hover:translate-y-[-2px] transition-all duration-200 app-fade-in app-stagger-3">
				<div class="flex items-start justify-between mb-2">
					<h3 class="text-lg font-semibold text-cyan-700">COG</h3>
					<span class="text-xs text-surface-500">2020</span>
				</div>
				<p class="text-sm text-surface-700">Clusters of Orthologous Groups for evolutionary gene classification</p>
			</a>
		</div>
	</section>

	<!-- Footer -->
	<footer class="text-center py-8 border-t border-surface-300/60">
		<p class="text-surface-600">© 2026 Dane Deemer</p>
	</footer>
</div>
