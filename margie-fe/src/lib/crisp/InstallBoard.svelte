<script lang="ts">
	import { tick } from 'svelte';
	import { Check } from 'lucide-svelte';
	import { uiBase } from '$lib/workspace/base.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { ws, type CheckRow, type SetupRow } from '$lib/workspace/data.svelte';
	import { ui } from '$lib/workspace/ui.svelte';
	import SetupPage from '$lib/workspace/pages/SetupPage.svelte';
	import BuildBar from '$lib/workspace/blocks/BuildBar.svelte';

	/**
	 * Crisp's Install page: a readiness band (ring, checklist, licences) above
	 * SetupPage, which holds every control. A checklist line opens its card below
	 * or the page that puts it right.
	 */

	const o = $derived(ws.overview);
	const cluster = $derived(!!backend.cluster);
	const building = $derived(ws.active?.kind === 'build' || ws.active?.kind === 'setup' ? ws.active : null);
	// ------------------------------------------------ the ring
	const ready = $derived(ws.setupReady);
	const R = 44;
	const C = 2 * Math.PI * R;
	const frac = $derived(ready.total ? ready.ok / ready.total : 0);
	const allReady = $derived(!!o && ready.total > 0 && ready.ok === ready.total);

	// ------------------------------------------------ licences
	const terms = $derived(ws.setup.find((r) => r.id === 'terms'));
	const licence = $derived.by(() => {
		if (cluster) return { ok: terms?.tone === 'ok', value: terms?.value ?? 'Not read yet', detail: terms?.detail ?? '' };
		const l = o?.licences;
		if (!l) return { ok: false, value: '…', detail: '' };
		return {
			ok: l.tools.length > 0 && l.accepted.length === l.tools.length,
			value: `${l.accepted.length} of ${l.tools.length} accepted`,
			detail: l.tools.length ? 'Tools with terms of their own stay off until you accept them.' : 'No tool needs extra terms.'
		};
	});

	// ------------------------------------------------ bringing a row of the detail into view
	let detail = $state<HTMLElement | null>(null);

	async function reveal(fold: string | null, find: (root: HTMLElement) => Element | null | undefined) {
		// Install's cards start folded, so one never opened counts as folded.
		const opening = !!fold && ui.isFolded(fold, true);
		if (opening && fold) ui.setFolded(fold, false);
		await tick();
		setTimeout(
			() => {
				const el = detail && find(detail);
				if (!(el instanceof HTMLElement)) return;
				const off = ui.motion === 'off';
				el.scrollIntoView({ behavior: off ? 'auto' : 'smooth', block: 'center' });
				if (off) return;
				const accent = getComputedStyle(el).getPropertyValue('--mg-accent').trim() || 'currentColor';
				el.animate([{ backgroundColor: `color-mix(in srgb, ${accent} 20%, transparent)` }, { backgroundColor: 'transparent' }], {
					duration: 1800,
					delay: ui.ms(300),
					easing: 'ease-out'
				});
			},
			opening ? ui.ms(440) : 0
		);
	}

	/** Where a line of the checklist is put right: a card below, or a page of its own. */
	const LOCAL: Record<string, { fold: string; shade: string } | string> = {
		runtime: { fold: 'setup:container-app', shade: 'container-app' },
		repo: { fold: 'setup:build-folder', shade: 'build-recipes' },
		images: { fold: 'setup:tools', shade: 'tools' },
		databases: { fold: 'setup:reference-data', shade: 'reference-data' },
		python: { fold: 'setup:python', shade: 'python' },
		licences: '/settings#licences',
		gtdbtk: '/settings#RUN_GTDBTK'
	};
	function target(r: SetupRow): { href: string } | { fold: string; find: (root: HTMLElement) => Element | null } | null {
		const href = r.href ?? (cluster ? undefined : typeof LOCAL[r.id] === 'string' ? (LOCAL[r.id] as string) : undefined);
		if (href && !href.startsWith('/setup')) return { href: uiBase.to(href) };
		if (href) {
			const id = href.split('#')[1];
			return id
				? { fold: `setup:${id}`, find: (root) => root.querySelector(`#${CSS.escape(id)}`) }
				: { fold: '', find: (root) => root };
		}
		const at = LOCAL[r.id];
		if (at && typeof at !== 'string') return { fold: at.fold, find: (root) => root.querySelector(`[data-shade="${at.shade}"]`) };
		return null;
	}
	function showLicences() {
		reveal('setup:terms', (root) => root.querySelector('#terms'));
	}
</script>

{#snippet mark(status: CheckRow['status'] | 'ok' | 'warn' | 'none')}
	<span class="ib-badge {status}" aria-hidden="true">
		{#if status === 'ok'}<Check size={10} strokeWidth={4} />{:else if status === 'missing' || status === 'warn'}!{:else if status === 'unknown'}?{/if}
	</span>
{/snippet}

<section class="ib-board" aria-label="Ready to run">
	{#if building}
		<div class="ib-now" role="status">
			<span class="ib-spinner" aria-hidden="true"></span>
			<span class="ib-now-text">
				<strong>{building.label}</strong>
				<span class="mg-note">{ws.lastLine || 'Starting'}</span>
			</span>
			<span class="ib-now-bar"><BuildBar percent={building.progress ?? 0} /></span>
			<a class="mg-link" href={uiBase.to(`/runs/${building.id}`)}>Log</a>
			<button type="button" class="mg-link quiet ib-stop" onclick={() => building && ws.stop(building.id)}>Stop</button>
		</div>
	{/if}

	<!-- ------------------------------------------------ ready, the checklist, the licences -->
	<div class="ib-side">
		<div class="ib-gauge">
			<svg viewBox="0 0 110 110" class="ib-ring" class:all={allReady} role="img" aria-label="{ready.ok} of {ready.total} ready">
				<circle class="bg" cx="55" cy="55" r={R} />
				<circle class="fg" cx="55" cy="55" r={R} stroke-dasharray="{C * frac} {C}" transform="rotate(-90 55 55)" />
				<text x="55" y="61" text-anchor="middle">{o ? `${ready.ok}/${ready.total}` : '…'}</text>
			</svg>
			<div class="ib-gauge-text">
				<b>{allReady ? 'Ready to run' : o ? `${ready.total - ready.ok} to set up` : cluster ? 'Reaching the cluster' : 'Reading'}</b>
				<span class="mg-note">{cluster ? `on ${backend.host || 'the cluster'}` : 'on this computer'}</span>
				{#if !cluster}
					<button type="button" class="mg-link quiet" disabled={ws.checking} onclick={() => ws.loadCheck()}>{ws.checking ? 'Checking' : 'Check again'}</button>
				{/if}
			</div>
		</div>

		<ul class="ib-checks">
			{#each ws.setup as r (r.id)}
				{@const go = target(r)}
				<li class="ib-t-{r.tone}">
					{#if go && 'href' in go}
						<a class="ib-check" href={go.href} title={r.detail}>
							{@render mark(r.tone === 'ok' ? 'ok' : r.tone === 'neutral' ? 'none' : 'warn')}
							<span class="lbl">{r.label}</span><span class="val">{r.value}</span>
						</a>
					{:else}
						<button type="button" class="ib-check" title={r.detail} disabled={!go} onclick={() => go && reveal(go.fold, go.find)}>
							{@render mark(r.tone === 'ok' ? 'ok' : r.tone === 'neutral' ? 'none' : 'warn')}
							<span class="lbl">{r.label}</span><span class="val">{r.value}</span>
						</button>
					{/if}
				</li>
			{:else}
				<li class="mg-note">{cluster ? 'Reaching the cluster…' : 'Reading…'}</li>
			{/each}
		</ul>

		{#snippet licenceCard()}
			<span class="ib-doc" aria-hidden="true">
				<svg viewBox="0 0 34 40"><path class="page" d="M2 2h20l10 10v26H2z" /><path class="fold" d="M22 2v10h10" /><path class="rule" d="M8 18h18M8 24h14M8 30h16" /></svg>
				{@render mark(licence.ok ? 'ok' : cluster ? 'warn' : 'none')}
			</span>
			<span class="ib-lic-text">
				<b>{cluster ? 'Licence terms' : 'Licences'}</b>
				<span class="val">{licence.value}</span>
				{#if licence.detail}<span class="mg-note">{licence.detail}</span>{/if}
			</span>
		{/snippet}
		{#if cluster}
			<button type="button" class="ib-licence" onclick={showLicences}>{@render licenceCard()}</button>
		{:else}
			<a class="ib-licence" href={uiBase.to('/settings#licences')}>{@render licenceCard()}</a>
		{/if}
	</div>
</section>

<div class="ib-detail" bind:this={detail}>
	<SetupPage />
</div>

<style>
	.ib-board {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		color: var(--mg-text);
		background: var(--mg-surface);
		box-shadow: none;
		overflow: hidden;
	}
	.ib-now {
		grid-column: 1 / -1;
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 10px calc(var(--mg-pad) * 1.2);
		border-bottom: 1px solid var(--mg-border);
		background: color-mix(in srgb, var(--mg-accent) 10%, transparent);
		font-size: var(--mg-fs-sm);
	}
	.ib-now-text {
		display: flex;
		flex-direction: column;
		flex: 1;
		min-width: 0;
	}
	.ib-now-text > * {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.ib-now-bar {
		flex: 0 1 260px;
		min-width: 140px;
	}
	.ib-spinner {
		flex: none;
		width: 16px;
		height: 16px;
		border-radius: 50%;
		border: 2.5px solid color-mix(in srgb, var(--mg-accent) 30%, transparent);
		border-top-color: var(--mg-accent);
		animation: ib-spin 900ms linear infinite;
	}

	/* ---- the marks ---- */
	.ib-badge {
		position: absolute;
		right: -3px;
		bottom: 0;
		display: grid;
		place-items: center;
		width: 16px;
		height: 16px;
		border-radius: 50%;
		border: 2px solid var(--mg-surface);
		background: var(--mg-text-3);
		color: #fff;
		font-size: 10px;
		font-weight: 800;
		line-height: 1;
	}
	.ib-badge.ok {
		background: var(--mg-ok);
	}
	.ib-badge.missing,
	.ib-badge.warn {
		background: var(--mg-warn);
	}
	.ib-badge.optional,
	.ib-badge.none {
		display: none;
	}

	/* ---- one band: ring | checklist | licences ---- */
	.ib-side {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr) minmax(220px, 280px);
		align-items: center;
		gap: 16px 28px;
		min-width: 0;
		padding: calc(var(--mg-pad) * 1.1) calc(var(--mg-pad) * 1.4);
	}
	.ib-gauge {
		display: flex;
		align-items: center;
		gap: 16px;
	}
	.ib-ring {
		flex: none;
		width: 84px;
		height: 84px;
	}
	.ib-ring .bg,
	.ib-ring .fg {
		fill: none;
		stroke-width: 10;
	}
	.ib-ring .bg {
		stroke: var(--mg-border);
	}
	.ib-ring .fg {
		stroke: var(--mg-warn);
		stroke-linecap: round;
		transition: stroke-dasharray var(--mo-3, 420ms) cubic-bezier(0.2, 0.7, 0.2, 1);
	}
	.ib-ring.all .fg {
		stroke: var(--mg-ok);
	}
	.ib-ring text {
		fill: var(--mg-text);
		font-family: var(--mg-font);
		font-size: 20px;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.ib-gauge-text {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 2px;
		min-width: 0;
	}
	.ib-gauge-text b {
		font-size: var(--mg-fs-lg);
		font-weight: 650;
	}
	.ib-checks {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 2px 20px;
		align-self: center;
	}
	.ib-check {
		display: flex;
		align-items: center;
		gap: 10px;
		width: 100%;
		min-height: 34px;
		padding: 4px 6px;
		border: none;
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text);
		font: inherit;
		font-size: var(--mg-fs-sm);
		text-align: left;
		text-decoration: none;
		cursor: pointer;
	}
	.ib-check:disabled {
		cursor: default;
	}
	.ib-check:hover:not(:disabled) {
		background: var(--mg-surface-2);
	}
	/* In the list the mark sits in line, before the name. */
	.ib-check .ib-badge {
		position: static;
		flex: none;
		border: none;
	}
	.ib-check .ib-badge.none {
		display: block;
		width: 16px;
		height: 16px;
		background: none;
		border: 2px solid var(--mg-border-strong);
	}
	.ib-check .lbl {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.ib-check .val {
		max-width: 50%;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		color: var(--mg-text-2);
		font-variant-numeric: tabular-nums;
	}
	.ib-t-warn .ib-check .val,
	.ib-t-danger .ib-check .val {
		color: var(--mg-warn);
	}
	.ib-licence {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-surface);
		color: var(--mg-text);
		font: inherit;
		text-align: left;
		text-decoration: none;
		cursor: pointer;
		transition:
			border-color var(--mo-1, 140ms) ease,
			transform var(--mo-2, 260ms) cubic-bezier(0.2, 0.7, 0.2, 1);
	}
	.ib-licence:hover {
		border-color: color-mix(in srgb, var(--mg-accent) 55%, var(--mg-border));
	}
	.ib-doc {
		position: relative;
		flex: none;
		width: 34px;
		height: 40px;
	}
	.ib-doc svg {
		display: block;
		width: 100%;
		height: 100%;
	}
	.ib-doc .page {
		fill: var(--mg-surface-2);
		stroke: var(--mg-text-3);
		stroke-width: 1.4;
		stroke-linejoin: round;
	}
	.ib-doc .fold,
	.ib-doc .rule {
		fill: none;
		stroke: var(--mg-text-3);
		stroke-width: 1.4;
	}
	.ib-doc .rule {
		stroke: var(--mg-border-strong);
		stroke-width: 2;
		stroke-linecap: round;
	}
	.ib-doc .ib-badge {
		right: -6px;
		bottom: -4px;
	}
	.ib-lic-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
		font-size: var(--mg-fs-sm);
	}
	.ib-lic-text .val {
		color: var(--mg-text-2);
	}

	/* ---- the detail below ---- */
	.ib-detail {
		display: flex;
		flex-direction: column;
	}
	.ib-stop {
		padding: 0;
		border: none;
		background: none;
		font: inherit;
		cursor: pointer;
	}

	@keyframes ib-spin {
		to {
			transform: rotate(360deg);
		}
	}
	:global([data-motion='off']) .ib-board *,
	:global([data-motion='off']) .ib-board *::after {
		animation: none !important;
		transition: none !important;
	}

	@media (max-width: 1100px) {
		.ib-side {
			grid-template-columns: auto minmax(0, 1fr);
		}
		.ib-licence {
			grid-column: 1 / -1;
		}
	}
	@media (max-width: 700px) {
		.ib-side {
			grid-template-columns: minmax(0, 1fr);
		}
		.ib-checks {
			grid-template-columns: minmax(0, 1fr);
		}
		.ib-ring {
			width: 72px;
			height: 72px;
		}
	}
</style>
