<script lang="ts">
	import { acceptTerms, fetchLicenseStatus, fetchTerms, revokeLicense, type CatalogTool, type LicenseStatus, type TermsPayload } from '$lib/license';
	import { ws } from '$lib/workspace/data.svelte';
	import { ui } from '$lib/workspace/ui.svelte';
	import { forget } from './backend';

	/**
	 * Licence terms, accepted once per account before a cluster run: intended use,
	 * restricted tools held, and acknowledgments (the same record as the classic gate).
	 */

	let status = $state<LicenseStatus | null>(null);
	let terms = $state<TermsPayload | null>(null);
	let error = $state('');
	let usage = $state('');
	let held = $state<Record<string, boolean>>({});
	let ticked = $state<Record<string, boolean>>({});
	let busy = $state(false);
	let changing = $state(false);

	/** Loads the licence status and terms. */
	async function load() {
		error = '';
		try {
			[status, terms] = await Promise.all([fetchLicenseStatus(), fetchTerms()]);
			usage = status.usage_type ?? '';
			held = Object.fromEntries((status.licensed_tools ?? []).map((t) => [t, true]));
			ticked = {};
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		}
	}
	$effect(() => {
		load();
	});

	const blocked = $derived((terms?.gated_tools ?? []).filter((t) => t.tier === 'blocked'));
	const commercial = $derived((terms?.gated_tools ?? []).filter((t) => t.tier === 'commercial_restricted'));
	const gated = $derived([...blocked, ...(usage === 'commercial' ? commercial : [])]);
	const willDisable = $derived(gated.filter((t) => !held[t.id]).map((t) => t.name));
	const missing = $derived((terms?.acknowledgments ?? []).filter((a) => !ticked[a.id]).length);
	const canAccept = $derived(!!terms && !!usage && missing === 0 && !busy);
	const every = $derived([...(terms?.tools ?? [])].sort((a, b) => a.phase - b.phase || a.name.localeCompare(b.name)));
	const source = $derived((terms?.tools ?? []).find((t) => t.id === 'eggnog'));
	const showForm = $derived(!!status && (!status.accepted || changing));

	/** Submits acceptance with the ticked acknowledgments and held licences. */
	async function accept() {
		if (!terms || !canAccept) return;
		busy = true;
		try {
			await acceptTerms({
				accepted_items: terms.acknowledgments.filter((a) => ticked[a.id]).map((a) => a.id),
				terms_version: terms.terms_version,
				terms_sha256: terms.terms_sha256,
				usage_type: usage,
				licensed_tools: Object.keys(held).filter((k) => held[k])
			});
			ui.notify('Licence terms accepted', 'ok');
			changing = false;
			await after();
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		} finally {
			busy = false;
		}
	}

	/** Withdraws acceptance. */
	async function revoke() {
		busy = true;
		try {
			await revokeLicense();
			ui.notify('Acceptance withdrawn: runs wait until the terms are accepted again', 'ok');
			await after();
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		} finally {
			busy = false;
		}
	}

	/** Reloads everything that depends on the licence status. */
	async function after() {
		forget('licence');
		await Promise.allSettled([load(), ws.loadOverview(), ws.loadTools()]);
	}

	const usageLabel = (id: string | null) => terms?.usage_types.find((u) => u.id === id)?.label ?? id ?? '';
</script>

{#snippet toolTerms(t: CatalogTool, pick: boolean)}
	<li class="tool">
		<div class="tool-head">
			{#if pick}
				<label class="pick">
					<input type="checkbox" checked={!!held[t.id]} onchange={(e) => (held[t.id] = e.currentTarget.checked)} />
					<span class="name">{t.name}</span>
				</label>
				<span class="mg-note">I hold my own licence</span>
			{:else}
				<span class="name">{t.name}</span>
			{/if}
			<span class="mg-grow"></span>
			<span class="mg-note">{t.license}</span>
		</div>
		<p class="mg-note">{t.user_action}</p>
		{#if t.license_url || t.obtain_url}
			<p class="mg-note links">
				{#if t.license_url}<a class="mg-link" href={t.license_url} target="_blank" rel="noopener noreferrer">Licence terms</a>{/if}
				{#if t.obtain_url}<a class="mg-link" href={t.obtain_url} target="_blank" rel="noopener noreferrer">{t.license_url ? 'Obtain from' : 'Provider page'}</a>{/if}
			</p>
		{/if}
	</li>
{/snippet}

<div class="lic">
	{#if error}
		<p class="mg-danger">{error}</p>
		<button type="button" class="mg-btn small" onclick={load}>Try again</button>
	{:else if !status || !terms}
		<p class="mg-note">Reading the terms…</p>
	{:else if !showForm}
		<div class="done">
			<p>
				<strong>Accepted</strong> for {usageLabel(status.usage_type)}, terms of {status.current_terms_version}.
				{status.licensed_tools.length ? `Your own licences: ${status.licensed_tools.join(', ')}.` : ''}
			</p>
			{#if status.disabled_tools.length}
				<p class="mg-note">Off for your runs: {status.disabled_tools.join(', ')}.</p>
			{:else}
				<p class="mg-note">Every tool is available to you.</p>
			{/if}
			<p class="acts">
				<button type="button" class="mg-link" onclick={() => (changing = true)}>Change my answers</button>
				<button type="button" class="mg-link quiet" disabled={busy} onclick={revoke}>Withdraw acceptance</button>
			</p>
		</div>
	{:else}
		<section class="part">
			<h3>How will you use MARGIE?</h3>
			<p class="mg-note">This decides which licence-restricted tools you can run.</p>
			<div class="choices">
				{#each terms.usage_types as u (u.id)}
					<label class="choice">
						<input type="radio" name="usage" value={u.id} checked={usage === u.id} onchange={() => (usage = u.id)} />
						<span>{u.label}</span>
					</label>
				{:else}
					<p class="mg-danger">The API sent no usage types, so the terms cannot be accepted. Please report this.</p>
				{/each}
			</div>
		</section>

		{#if blocked.length}
			<section class="part">
				<h3>Tools you must license yourself</h3>
				<p class="mg-note">Academic use only, and not redistributable by MARGIE: obtain your own copy or permission from the provider.</p>
				<ul class="tools">{#each blocked as t (t.id)}{@render toolTerms(t, true)}{/each}</ul>
			</section>
		{/if}
		{#if commercial.length}
			<section class="part">
				<h3>Restricted for commercial use</h3>
				<p class="mg-note">Free for academic and non-profit use; commercial use needs the provider's permission first.</p>
				<ul class="tools">{#each commercial as t (t.id)}{@render toolTerms(t, usage === 'commercial')}{/each}</ul>
			</section>
		{/if}

		<section class="part">
			<details>
				<summary>Licences of all {every.length} tools and databases</summary>
				<ul class="tools every">{#each every as t (t.id)}{@render toolTerms(t, false)}{/each}</ul>
			</details>
		</section>

		<section class="part">
			<h3>Terms</h3>
			<pre class="terms">{terms.terms_markdown}</pre>
			<div class="choices">
				{#each terms.acknowledgments as a (a.id)}
					<label class="choice">
						<input type="checkbox" checked={!!ticked[a.id]} onchange={(e) => (ticked[a.id] = e.currentTarget.checked)} />
						<span>{a.label}</span>
					</label>
				{/each}
			</div>
		</section>

		{#if usage}
			<p class="outcome" class:off={willDisable.length}>
				{willDisable.length ? `Off for your runs: ${willDisable.join(', ')}. Tick "I hold my own licence" above to use one.` : 'Every tool will be available to you.'}
			</p>
		{/if}

		<div class="acts">
			<button type="button" class="mg-btn primary" disabled={!canAccept} onclick={accept}>{busy ? 'Recording…' : 'Accept the terms'}</button>
			{#if changing}<button type="button" class="mg-link quiet" onclick={() => (changing = false)}>Keep my answers</button>{/if}
			<span class="mg-note">
				{#if !usage && missing}Choose how you will use MARGIE, and tick the {missing} acknowledgment{missing === 1 ? '' : 's'}.
				{:else if !usage}Choose how you will use MARGIE.
				{:else if missing}Tick the {missing} remaining acknowledgment{missing === 1 ? '' : 's'}.
				{:else}Terms of {terms.terms_version}. Your acceptance, account, time (UTC) and address are recorded.{/if}
			</span>
		</div>

		<p class="mg-note source">
			MARGIE is a network service built on open-source tools. As eggNOG-mapper's AGPL-3.0 licence requires, its corresponding source is
			available{source?.provenance?.downloaded_from?.length ? `: ${source.provenance.downloaded_from.join(', ')}` : ''}. Source and exact
			versions of every GPL and AGPL component are kept under <span class="mg-mono">build-here/</span> in the MARGIE repository.
		</p>
	{/if}
</div>

<style>
	.lic {
		display: flex;
		flex-direction: column;
		gap: 18px;
		padding: var(--mg-pad);
		font-size: var(--mg-fs-sm);
	}
	h3 {
		margin: 0 0 2px;
		font-size: var(--mg-fs);
		font-weight: 650;
	}
	.part {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.choices {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin-top: 4px;
	}
	.choice {
		display: flex;
		align-items: flex-start;
		gap: 8px;
		max-width: 80ch;
	}
	.choice input {
		margin-top: 3px;
	}
	.tools {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
		gap: 10px;
		margin-top: 4px;
	}
	.tools.every {
		max-height: 24rem;
		overflow: auto;
		margin-top: 10px;
	}
	.tool {
		display: flex;
		flex-direction: column;
		gap: 4px;
		padding: 10px 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-surface);
	}
	.tool-head {
		display: flex;
		align-items: baseline;
		flex-wrap: wrap;
		gap: 4px 10px;
	}
	.pick {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.name {
		font-weight: 600;
	}
	.links {
		display: flex;
		gap: 14px;
	}
	.tool p {
		margin: 0;
	}
	summary {
		cursor: pointer;
		font-weight: 600;
	}
	.terms {
		max-height: 18rem;
		overflow: auto;
		margin: 4px 0 0;
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-bg);
		font-family: var(--mg-mono);
		font-size: var(--mg-fs-xs);
		white-space: pre-wrap;
	}
	.outcome {
		padding: 10px 12px;
		border: 1px solid var(--mg-ok);
		border-radius: var(--mg-r);
		background: color-mix(in srgb, var(--mg-ok) 8%, transparent);
	}
	.outcome.off {
		border-color: var(--mg-warn);
		background: var(--mg-warn-soft);
	}
	.acts {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 10px 16px;
	}
	.done {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.done p {
		margin: 0;
	}
	.source {
		padding-top: 12px;
		border-top: 1px solid var(--mg-border);
	}
</style>
