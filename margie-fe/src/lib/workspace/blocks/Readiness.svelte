<script lang="ts">
	import { ArrowRight, CircleCheck, TriangleAlert } from 'lucide-svelte';
	import { uiBase } from '../base.svelte';
	import { backend } from '../backend.svelte';
	import { ws } from '../data.svelte';

	/**
	 * One-line readiness strip: a quiet note when everything is installed, otherwise a tile per
	 * missing item with its fix. Details stay on the Install page.
	 */

	const row = (id: string) => ws.setup.find((r) => r.id === id);
	const known = $derived(!!ws.overview);
	/* Counts only what a run requires; licences and GTDB-Tk are optional. */
	const ready = $derived(known && ws.setup.filter((r) => r.required).every((r) => r.tone === 'ok'));

	/** Missing items in the order they block a run. */
	const missing = $derived.by(() => {
		const out: { text: string; fix?: { label: string; run: () => void }; href?: string; go?: string }[] = [];
		const runtime = row('runtime');
		const images = row('images');
		const databases = row('databases');
		const python = row('python');
		if (runtime && runtime.tone !== 'ok') out.push({ text: `Container app: ${runtime.value.toLowerCase()}`, href: uiBase.to('/setup') });
		if (images?.tone === 'warn') out.push({ text: `${images.value} tools built`, fix: { label: 'Build the rest', run: () => ws.build('containers') } });
		if (databases?.tone === 'warn')
			out.push({ text: `${databases.value} databases downloaded`, fix: { label: 'Download the rest', run: () => ws.build('databases') } });
		if (python && python.tone !== 'ok') out.push({ text: `Python: ${python.value}`, href: uiBase.to('/setup') });
		// Backend-reported rows (cluster) carry their own fix location.
		for (const r of ws.setup) {
			if (!r.required || r.tone === 'ok' || !r.href) continue;
			out.push({ text: `${r.label}: ${r.value.toLowerCase()}`, href: uiBase.to(r.href), go: r.href.startsWith('/settings') ? 'Open Settings' : 'Open Install' });
		}
		return out;
	});

	/** Small facts shown as pills. */
	const facts = $derived.by(() => {
		if (backend.cluster) return [row('cluster')?.value, row('account')?.value, row('output')?.detail].filter(Boolean) as string[];
		const images = row('images');
		const databases = row('databases');
		const runtime = row('runtime');
		return [images && `${images.value} tools`, databases && `${databases.value} databases`, runtime?.value].filter(Boolean) as string[];
	});
</script>

{#if !known}
	<div class="rd rd-strip quiet" role="status">
		<span class="rd-icon wait" aria-hidden="true"><span class="rd-spin"></span></span>
		<p class="rd-title">{backend.cluster ? 'Reaching the cluster…' : 'Looking at what is installed…'}</p>
	</div>
{:else if ready || !missing.length}
	<div class="rd rd-strip ok">
		<span class="rd-icon" aria-hidden="true"><CircleCheck size={18} strokeWidth={2.4} /></span>
		<p class="rd-title">{backend.cluster ? 'Connected and ready' : 'Everything installed'}</p>
		<ul class="rd-facts">
			{#each facts as f (f)}<li>{f}</li>{/each}
		</ul>
		<a class="rd-go" href={uiBase.to('/setup')}>Install <ArrowRight size={14} /></a>
	</div>
{:else}
	<section class="rd rd-warn" aria-label="Missing before a run">
		<div class="rd-lead">
			<span class="rd-icon big" aria-hidden="true"><TriangleAlert size={22} strokeWidth={2.2} /></span>
			<div class="rd-lead-text">
				<p class="rd-title">{missing.length === 1 ? 'One thing is missing before a run' : `${missing.length} things are missing before a run`}</p>
				<p class="rd-sub">{facts.join(' | ')}</p>
				<a class="rd-go" href={uiBase.to('/setup')}>All of Install <ArrowRight size={14} /></a>
			</div>
		</div>
		<ul class="rd-items" style="--n: {Math.min(missing.length, 3)}">
			{#each missing as m, i (m.text)}
				<li style="--i: {i}">
					<span class="rd-num" aria-hidden="true">{i + 1}</span>
					<span class="rd-text">{m.text}</span>
					{#if m.fix && !ws.active}
						<button type="button" class="rd-fix" onclick={m.fix.run}>{m.fix.label}</button>
					{:else if m.href}
						<a class="rd-fix ghost" href={m.href}>{m.go ?? 'Open Install'}</a>
					{:else}
						<span class="rd-busy">a run is going</span>
					{/if}
				</li>
			{/each}
		</ul>
	</section>
{/if}

<style>
	.rd {
		--rd-tone: var(--mg-ok);
		position: relative;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface));
		box-shadow: var(--cr-card-shadow, none);
		color: var(--mg-text);
		overflow: hidden;
	}
	/* Status-coloured stripe on the left edge. */
	.rd::before {
		content: '';
		position: absolute;
		inset: 0 auto 0 0;
		width: 4px;
		background: var(--rd-tone);
	}
	.rd.quiet {
		--rd-tone: var(--mg-text-3);
	}
	.rd-warn {
		--rd-tone: var(--mg-warn);
		border-color: color-mix(in srgb, var(--mg-warn) 35%, var(--mg-border));
	}

	/* ---- one-line strip ---- */
	.rd-strip {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 14px;
		padding: 12px 20px 12px 22px;
		font-size: var(--mg-fs-sm);
	}
	.rd-title {
		font-weight: 650;
	}
	.rd-facts {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
		flex: 1;
		min-width: 0;
	}
	.rd-facts li {
		padding: 2px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
		color: var(--mg-text-2);
		font-size: var(--mg-fs-xs);
		font-variant-numeric: tabular-nums;
	}
	.rd-icon {
		flex: none;
		display: grid;
		place-items: center;
		width: 30px;
		height: 30px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--rd-tone) 16%, transparent);
		color: var(--rd-tone);
	}
	.rd-icon.big {
		width: 46px;
		height: 46px;
	}
	.rd-spin {
		width: 14px;
		height: 14px;
		border-radius: 50%;
		border: 2px solid color-mix(in srgb, var(--mg-text-3) 35%, transparent);
		border-top-color: var(--mg-text-2);
		animation: rd-turn 900ms linear infinite;
	}
	.rd-go {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		color: var(--mg-accent-ink, var(--mg-accent));
		font-size: var(--mg-fs-sm);
		font-weight: 600;
	}
	.rd-go:hover {
		text-decoration: underline;
		text-underline-offset: 3px;
	}

	/* ---- warning: problem on the left, one tile per fix on the right ---- */
	.rd-warn {
		display: grid;
		grid-template-columns: minmax(240px, 1fr) minmax(0, 2.4fr);
		align-items: stretch;
	}
	.rd-lead {
		display: flex;
		align-items: flex-start;
		gap: 14px;
		padding: 18px 20px 18px 24px;
		border-right: 1px solid var(--mg-border);
	}
	.rd-lead-text {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}
	.rd-lead .rd-title {
		font-size: var(--mg-fs-lg);
		line-height: 1.25;
	}
	.rd-sub {
		color: var(--mg-text-3);
		font-size: var(--mg-fs-xs);
		font-variant-numeric: tabular-nums;
	}
	.rd-lead .rd-go {
		margin-top: 6px;
	}
	.rd-items {
		display: grid;
		grid-template-columns: repeat(var(--n), minmax(0, 1fr));
		gap: 12px;
		padding: 16px 18px;
		align-content: center;
	}
	.rd-items li {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr);
		grid-template-rows: 1fr auto;
		gap: 10px 10px;
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm, 8px);
		background: var(--mg-surface);
		font-size: var(--mg-fs-sm);
	}
	.rd-num {
		display: grid;
		place-items: center;
		width: 22px;
		height: 22px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--mg-warn) 18%, transparent);
		color: var(--mg-warn);
		font-size: 11px;
		font-weight: 700;
	}
	.rd-text {
		align-self: center;
		font-weight: 550;
		overflow-wrap: anywhere;
	}
	.rd-fix,
	.rd-busy {
		grid-column: 1 / -1;
		justify-self: stretch;
	}
	.rd-fix {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		height: 32px;
		padding: 0 14px;
		border: 1px solid transparent;
		border-radius: var(--mg-r-sm);
		background: var(--mg-accent);
		color: var(--mg-on-accent, #fff);
		font: inherit;
		font-size: var(--mg-fs-sm);
		font-weight: 600;
		cursor: pointer;
		transition:
			transform 140ms ease,
			box-shadow 140ms ease;
	}
	.rd-fix:hover {
		box-shadow: none;
	}
	.rd-fix.ghost {
		border-color: color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		background: transparent;
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.rd-fix.ghost:hover {
		background: color-mix(in srgb, var(--mg-accent) 8%, transparent);
		box-shadow: none;
	}
	.rd-busy {
		text-align: center;
		color: var(--mg-text-3);
		font-size: var(--mg-fs-xs);
	}

	@keyframes rd-turn {
		to {
			transform: rotate(360deg);
		}
	}
	:global([data-motion='off']) .rd,
	:global([data-motion='off']) .rd * {
		animation: none !important;
		transition: none !important;
	}

	@media (max-width: 900px) {
		.rd-warn {
			grid-template-columns: minmax(0, 1fr);
		}
		.rd-lead {
			border-right: none;
			border-bottom: 1px solid var(--mg-border);
		}
	}
	@media (max-width: 620px) {
		.rd-items {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
