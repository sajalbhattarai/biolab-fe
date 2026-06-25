<script lang="ts">
	import Navibar from "$lib/Navibar.svelte";
</script>

<div class="w-full px-4 md:px-6 py-8 space-y-8">
	<!-- Page Header -->
	<section class="text-center py-8 space-y-4">
		<h1 class="text-4xl font-bold text-primary-500">Methods</h1>
		<p class="text-lg text-surface-600 dark:text-surface-300">A compact overview of the pipeline stages, tools, defaults, and references used by the platform.</p>
	</section>

	<!-- Overview Section -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<h2 class="text-2xl font-bold text-primary-500 mb-4">Overview</h2>
		<p class="text-surface-700 dark:text-surface-300">The Methods page explains the pipeline in plain language so users can understand what each stage does before they run it.</p>
	</section>

	<!-- Pipeline Steps -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<h2 class="text-2xl font-bold text-secondary-500 mb-6">Analysis Pipeline</h2>

		<div class="space-y-6">
			<!-- Step 1 -->
			<div class="border-l-4 border-primary-500 pl-4">
				<h3 class="text-xl font-semibold mb-2">Step 1: Lorem Preprocessing</h3>
			</div>

			<!-- Step 2 -->
			<div class="border-l-4 border-secondary-500 pl-4">
				<h3 class="text-xl font-semibold mb-2">Step 2: Ipsum Assembly</h3>
			</div>

			<!-- Step 3 -->
			<div class="border-l-4 border-tertiary-500 pl-4">
				<h3 class="text-xl font-semibold mb-2">Step 3: Dolor Annotation</h3>
			</div>

			<!-- Step 4 -->
			<div class="border-l-4 border-warning-500 pl-4">
				<h3 class="text-xl font-semibold mb-2">Step 4: Sit Amet Analysis</h3>
			</div>
		</div>
	</section>

	<!-- Tools & Technologies -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<h2 class="text-2xl font-bold text-tertiary-500 mb-6">Tools & Technologies</h2>

		<div class="grid grid-cols-1 md:grid-cols-2 gap-4">
			<div class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
				<h3 class="font-semibold text-lg mb-2">LoremTool v2.4</h3>
				<p class="text-sm text-surface-600 dark:text-surface-300">Pretium lectus quam id leo in vitae turpis massa sed.</p>
			</div>

			<div class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
				<h3 class="font-semibold text-lg mb-2">IpsumSoft Pro</h3>
				<p class="text-sm text-surface-600 dark:text-surface-300">Faucibus purus in massa tempor nec feugiat nisl pretium.</p>
			</div>

			<div class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
				<h3 class="font-semibold text-lg mb-2">DolorDB</h3>
				<p class="text-sm text-surface-600 dark:text-surface-300">Mauris augue neque gravida in fermentum et sollicitudin.</p>
			</div>

			<div class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
				<h3 class="font-semibold text-lg mb-2">SitAnalyzer</h3>
				<p class="text-sm text-surface-600 dark:text-surface-300">Ut porttitor leo a diam sollicitudin tempor id eu.</p>
			</div>
		</div>
	</section>

	<!-- Parameters -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<h2 class="text-2xl font-bold mb-6">Default Parameters</h2>

		<div class="overflow-x-auto">
			<table class="table table-hover w-full">
				<thead>
					<tr class="bg-surface-200 dark:bg-surface-700">
						<th class="p-3 text-left">Parameter</th>
						<th class="p-3 text-left">Default Value</th>
						<th class="p-3 text-left">Description</th>
					</tr>
				</thead>
				<tbody>
					<tr>
						<td class="p-3 font-mono text-sm">--lorem-threshold</td>
						<td class="p-3 font-mono text-sm">0.85</td>
						<td class="p-3 text-sm">Consectetur adipiscing elit duis</td>
					</tr>
					<tr>
						<td class="p-3 font-mono text-sm">--ipsum-depth</td>
						<td class="p-3 font-mono text-sm">50</td>
						<td class="p-3 text-sm">Dignissim diam quis enim lobortis</td>
					</tr>
					<tr>
						<td class="p-3 font-mono text-sm">--dolor-cutoff</td>
						<td class="p-3 font-mono text-sm">1e-5</td>
						<td class="p-3 text-sm">Egestas sed sed risus pretium quam</td>
					</tr>
					<tr>
						<td class="p-3 font-mono text-sm">--amet-window</td>
						<td class="p-3 font-mono text-sm">100</td>
						<td class="p-3 text-sm">Vulputate eu scelerisque felis</td>
					</tr>
				</tbody>
			</table>
		</div>
	</section>

	<!-- References -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<h2 class="text-2xl font-bold mb-6">References</h2>

		<ol class="list-decimal list-inside space-y-3 text-surface-700 dark:text-surface-300">
			<li class="pl-2">
				Lorem J, Ipsum D, Dolor S. (2024). <em>Consectetur adipiscing elit sed do eiusmod tempor.</em>
				Journal of Placeholder Science. 42(3):123-145.
			</li>
			<li class="pl-2">
				Sit A, Amet C, Consectetur A. (2023). <em>Adipiscing elit pellentesque habitant morbi.</em>
				Nature Placeholder Methods. 18:456-478.
			</li>
			<li class="pl-2">
				Dolor M, Tempor I. (2023). <em>Incididunt ut labore et dolore magna aliqua.</em>
				Bioinformatics Placeholder. 39(2):789-801.
			</li>
		</ol>
	</section>
</div>
