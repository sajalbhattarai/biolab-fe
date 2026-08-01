<script lang="ts">
	import { onMount } from 'svelte';
	import { fetchTerms, acceptTerms, type TermsPayload, type CatalogTool } from '$lib/license';

	let { onaccepted }: { onaccepted: () => void } = $props();

	let terms = $state<TermsPayload | null>(null);
	let checked = $state<Record<string, boolean>>({});
	let usageType = $state('');
	let licensed = $state<Record<string, boolean>>({});
	let loading = $state(true);
	let submitting = $state(false);
	let error = $state('');

	let allChecked = $derived(
		!!terms && terms.acknowledgments.length > 0 && terms.acknowledgments.every((a) => checked[a.id])
	);
	let blockedTools = $derived((terms?.gated_tools ?? []).filter((t) => t.tier === 'blocked'));
	let commercialTools = $derived(
		(terms?.gated_tools ?? []).filter((t) => t.tier === 'commercial_restricted')
	);
	let isCommercial = $derived(usageType === 'commercial');
	let canAccept = $derived(allChecked && !!usageType);
	// How many acknowledgments are still unticked, so the disabled-button hint can
	// say what is actually blocking rather than leaving the user to hunt for it.
	let missingAckCount = $derived(
		(terms?.acknowledgments ?? []).filter((a) => !checked[a.id]).length
	);
	let licensedIds = $derived(Object.keys(licensed).filter((id) => licensed[id]));
	// Tools that will be turned off for this run, given the current answers:
	// blocked tools without a license (always), plus commercial-restricted ones
	// without a license when the use is commercial.
	let willDisable = $derived(
		[
			...blockedTools.filter((t) => !licensed[t.id]),
			...(isCommercial ? commercialTools.filter((t) => !licensed[t.id]) : [])
		].map((t) => t.name)
	);
	// eggNOG-mapper is AGPL-3.0; as a network service the operator must offer its
	// corresponding source. Surface that in the footer, driven by the catalog.
	let sourceTool = $derived((terms?.tools ?? []).find((t) => t.id === 'eggnog'));
	// Every tool/database, in pipeline order, for the full license disclosure.
	let sortedTools = $derived(
		[...(terms?.tools ?? [])].sort((a, b) => a.phase - b.phase || a.name.localeCompare(b.name))
	);

	onMount(async () => {
		try {
			terms = await fetchTerms();
			const init: Record<string, boolean> = {};
			for (const a of terms.acknowledgments) init[a.id] = false;
			checked = init;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load licensing terms';
		} finally {
			loading = false;
		}
	});

	async function accept() {
		if (!terms || !canAccept || submitting) return;
		submitting = true;
		error = '';
		try {
			await acceptTerms({
				accepted_items: terms.acknowledgments.filter((a) => checked[a.id]).map((a) => a.id),
				terms_version: terms.terms_version,
				terms_sha256: terms.terms_sha256,
				usage_type: usageType,
				licensed_tools: licensedIds
			});
			onaccepted();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to record acceptance';
		} finally {
			submitting = false;
		}
	}
</script>

<div class="card p-6 bg-surface-100 dark:bg-surface-800 mb-8 border-2 border-primary-500">
	<h2 class="text-2xl font-semibold mb-1">Licensing terms</h2>
	<p class="text-sm text-surface-500 dark:text-surface-400 mb-4">
		Please accept the licensing terms before use.
	</p>

	{#if loading}
		<p class="text-surface-500 dark:text-surface-400">Loading licensing terms…</p>
	{:else if !terms}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
			{error || 'Could not load the licensing terms. Please reload the page.'}
		</div>
	{:else}
		{#if error}
			<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
				{error}
			</div>
		{/if}

		<!-- How will you use MARGIE? -->
		<h3 class="text-lg font-semibold mt-2 mb-1">How will you use MARGIE?</h3>
		<p class="text-sm text-surface-500 dark:text-surface-400 mb-2">
			This decides which license-restricted tools are available to you.
		</p>
		<div class="space-y-2 mb-5">
			{#each terms.usage_types as u (u.id)}
				<label class="flex items-start gap-2 cursor-pointer text-sm">
					<input
						type="radio"
						class="mt-1"
						name="usage_type"
						value={u.id}
						bind:group={usageType}
					/>
					<span>{u.label}</span>
				</label>
			{/each}
		</div>

		<!-- Tools you must license yourself -->
		{#if blockedTools.length > 0}
			<h3 class="text-lg font-semibold mt-2 mb-1">Tools you must license yourself</h3>
			<p class="text-sm text-surface-500 dark:text-surface-400 mb-2">
				These are academic-use-only and cannot be redistributed by MARGIE. You must obtain your own
				copy or permission directly from the provider before using them.
			</p>
			<div class="space-y-3 mb-5">
				{#each blockedTools as t (t.id)}
					{@render toolCard(t)}
				{/each}
			</div>
		{/if}

		<!-- Commercial-restricted tools -->
		{#if commercialTools.length > 0}
			<h3 class="text-lg font-semibold mt-2 mb-1">Restricted for commercial use</h3>
			<p class="text-sm text-surface-500 dark:text-surface-400 mb-2">
				Free for academic / non-profit use. For commercial use you must first obtain permission or a
				license.
			</p>
			<div class="space-y-3 mb-5">
				{#each commercialTools as t (t.id)}
					{@render toolCard(t)}
				{/each}
			</div>
		{/if}

		<!-- Full per-tool / database license details -->
		<h3 class="text-lg font-semibold mt-2 mb-1">License details for every tool &amp; database</h3>
		<p class="text-sm text-surface-500 dark:text-surface-400 mb-2">
			MARGIE runs these third-party tools and databases, each under its own license. By accepting,
			you agree to use each responsibly, within its license, and to credit its authors.
		</p>
		<details class="mb-5">
			<summary class="cursor-pointer text-sm font-medium">Show all {sortedTools.length} licenses</summary>
			<div class="mt-3 space-y-3 max-h-96 overflow-y-auto pr-2">
				{#each sortedTools as t (t.id)}
					{@render licenseRow(t)}
				{/each}
			</div>
		</details>

		<!-- Full terms text -->
		<h3 class="text-lg font-semibold mt-2 mb-1">Terms &amp; acknowledgment</h3>
		<div
			class="max-h-72 overflow-y-auto rounded border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 p-4 text-sm whitespace-pre-wrap font-mono mb-4"
		>{terms.terms_markdown}</div>

		<!-- Acknowledgment checkboxes -->
		<div class="space-y-2 mb-5">
			{#each terms.acknowledgments as a (a.id)}
				<label class="flex items-start gap-2 cursor-pointer text-sm">
					<input type="checkbox" class="mt-1" bind:checked={checked[a.id]} />
					<span>{a.label}</span>
				</label>
			{/each}
		</div>

		<!-- What will be disabled, based on the answers above -->
		{#if usageType}
			{#if willDisable.length > 0}
				<div
					class="text-sm rounded border border-amber-400 bg-amber-50 dark:bg-amber-950/40 text-amber-800 dark:text-amber-300 px-4 py-3 mb-4"
				>
					These tools will be turned off for your runs (you can enable one by ticking
					“I have obtained my own license” above): <b>{willDisable.join(', ')}</b>.
				</div>
			{:else}
				<div
					class="text-sm rounded border border-green-400 bg-green-50 dark:bg-green-950/40 text-green-800 dark:text-green-300 px-4 py-3 mb-4"
				>
					All tools are available for your selected usage.
				</div>
			{/if}
		{/if}

		<div class="flex items-center gap-3">
			<button
				class="btn variant-filled-primary px-6 py-2 rounded bg-primary-500 text-white disabled:opacity-50 disabled:cursor-not-allowed"
				disabled={!canAccept || submitting}
				onclick={accept}
			>
				{submitting ? 'Recording…' : 'Accept and continue'}
			</button>
			<!--
				Must key off canAccept, not usageType alone. canAccept is
				(allChecked && usageType), so picking a usage type but leaving an
				acknowledgment unticked left the button disabled while this hint
				showed the reassuring "Terms version..." line -- the button looked
				broken rather than blocked. Name what is actually missing.
			-->
			<span class="text-xs text-surface-400">
				{#if !canAccept}
					{#if !usageType && missingAckCount > 0}
						Select how you'll use MARGIE, and check the
						{missingAckCount} remaining acknowledgment{missingAckCount === 1 ? '' : 's'}.
					{:else if !usageType}
						Select how you'll use MARGIE to continue.
					{:else}
						Check the {missingAckCount} remaining
						acknowledgment{missingAckCount === 1 ? '' : 's'} to continue.
					{/if}
				{:else}
					Terms version {terms.terms_version}. Your acceptance, username, time (UTC) and IP are recorded.
				{/if}
			</span>
		</div>

		<!-- Source & offer of source (AGPL / open-source compliance) -->
		<div
			class="mt-5 pt-4 border-t border-surface-300 dark:border-surface-600 text-xs text-surface-500 dark:text-surface-400"
		>
			<p class="font-semibold mb-1">Source &amp; offer of source</p>
			<p>
				MARGIE is a network service built on open-source tools. In accordance with the AGPL-3.0
				license of eggNOG-mapper, the corresponding source is available:
			</p>
			<ul class="list-disc ml-5 mt-1">
				{#each sourceTool?.provenance?.downloaded_from ?? [] as src}
					<li>{src}</li>
				{/each}
				{#if sourceTool?.provenance?.build_recipe?.length}
					<li>Build recipe: {sourceTool.provenance.build_recipe.join(', ')}</li>
				{/if}
			</ul>
			<p class="mt-1">
				Corresponding source and exact versions for all GPL/AGPL components are maintained under
				<code>build-here/</code> in the MARGIE repository; each tool's own source and version are
				listed with its terms above.
			</p>
		</div>
	{/if}
</div>

{#snippet licenseRow(t: CatalogTool)}
	<div class="rounded border border-surface-300 dark:border-surface-600 p-3">
		<div class="font-semibold">{t.name}</div>
		<dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 mt-1 text-xs">
			<dt class="text-surface-500 dark:text-surface-400">License type</dt><dd>{t.license}</dd>
			<dt class="text-surface-500 dark:text-surface-400">Academic use</dt><dd>{t.academic_use}</dd>
			<dt class="text-surface-500 dark:text-surface-400">Research use</dt><dd>{t.research_use}</dd>
			<dt class="text-surface-500 dark:text-surface-400">Commercial use</dt><dd>{t.commercial_use}</dd>
			<dt class="text-surface-500 dark:text-surface-400">Permission</dt><dd>{t.user_action}</dd>
			<!--
				Only call it a licence link when it actually is one. license_url is
				the verified licence page; obtain_url is usually just the provider's
				homepage, and labelling that "License link" sent people to a front
				page and implied they had read the terms.
			-->
			{#if t.license_url}
				<dt class="text-surface-500 dark:text-surface-400">License terms</dt>
				<dd><a href={t.license_url} target="_blank" rel="noopener noreferrer" class="text-primary-500 underline break-all">{t.license_url}</a></dd>
			{/if}
			{#if t.obtain_url}
				<dt class="text-surface-500 dark:text-surface-400">
					{t.license_url ? 'Obtain from' : 'Provider page'}
				</dt>
				<dd><a href={t.obtain_url} target="_blank" rel="noopener noreferrer" class="text-primary-500 underline break-all">{t.obtain_url}</a></dd>
			{/if}
			{#if !t.license_url && t.license_quote}
				<dt class="text-surface-500 dark:text-surface-400">License text</dt>
				<dd class="opacity-80">quoted below — no direct licence URL on record</dd>
			{/if}
		</dl>
		{#if t.license_quote}
			<div class="mt-2">
				<span class="text-[10px] uppercase tracking-wide text-surface-400">License notice ({t.license_quote_kind === 'verbatim' ? 'verbatim' : 'summary'})</span>
				<pre class="mt-1 whitespace-pre-wrap font-mono text-xs bg-surface-50 dark:bg-surface-900 border border-surface-200 dark:border-surface-700 rounded p-2">{t.license_quote}</pre>
			</div>
		{/if}
	</div>
{/snippet}

{#snippet toolCard(t: CatalogTool)}
	<div class="rounded border border-surface-300 dark:border-surface-600 p-3">
		<div class="flex flex-wrap items-baseline justify-between gap-2">
			<span class="font-semibold">{t.name}</span>
			<span class="text-xs text-surface-500 dark:text-surface-400">{t.license}</span>
		</div>
		<p class="text-sm mt-1"><span class="font-medium">Action:</span> {t.user_action}</p>
		{#if t.allowed?.length}
			<p class="text-xs text-green-700 dark:text-green-400 mt-1">
				Allowed: {t.allowed.join('; ')}
			</p>
		{/if}
		{#if t.not_allowed?.length}
			<p class="text-xs text-red-700 dark:text-red-400 mt-0.5">
				Not allowed: {t.not_allowed.join('; ')}
			</p>
		{/if}
		{#if t.provenance?.downloaded_from?.length}
			<p class="text-xs text-surface-500 dark:text-surface-400 mt-1">
				Source: {t.provenance.downloaded_from.join(' · ')}
			</p>
		{/if}
		{#if t.obtain_url}
			<a
				href={t.obtain_url}
				target="_blank"
				rel="noopener noreferrer"
				class="text-xs text-primary-500 underline mt-1 inline-block"
			>
				Obtain / license this tool →
			</a>
		{/if}
		<label class="flex items-start gap-2 cursor-pointer text-sm mt-2 pt-2 border-t border-surface-200 dark:border-surface-700">
			<input type="checkbox" class="mt-1" bind:checked={licensed[t.id]} />
			<span>I have obtained my own license / permission for {t.name}.</span>
		</label>
	</div>
{/snippet}
