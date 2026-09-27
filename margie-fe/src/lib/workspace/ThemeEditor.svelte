<script lang="ts">
	import { RotateCcw } from 'lucide-svelte';
	import { accentColor, resolveColours, sanitizePrefs } from './prefs';
	import { checkColours, presetChange, PRESETS, TOKENS } from './themes';
	import { ui } from './ui.svelte';
	import { contrast, HEX, visionInfo } from './vision';

	/**
	 * Theme editor: a neutrals preset, then every interface colour with its contrast and checks.
	 * Edits apply live to the current light or dark mode; `base` is the interface's preset.
	 */
	let { base = 'paper' }: { base?: string } = $props();

	const mode = $derived(ui.dark ? 'dark' : 'light');
	const chosen = $derived(ui.prefs.palette || base);
	const colours = $derived(resolveColours(ui.prefs, ui.dark, base));
	/** The theme without manual changes: the target of "reset". */
	const plain = $derived(resolveColours({ ...ui.prefs, colours: { light: {}, dark: {} } }, ui.dark, base));
	const edited = $derived(ui.prefs.colours[mode]);
	const editedCount = $derived(Object.keys(ui.prefs.colours.light).length + Object.keys(ui.prefs.colours.dark).length);
	const checks = $derived(checkColours(colours, ui.prefs.vision, ui.prefs.visionStrength));
	const flagged = $derived(new Set(checks.flatMap((c) => c.keys)));

	const GROUPS = [
		{ id: 'Surfaces', note: '' },
		{ id: 'Text', note: 'Each level should keep 4.5:1 contrast on cards.' },
		{ id: 'Meaning', note: 'Done, attention and failed.' },
		{ id: 'Sections', note: 'One colour per kind of block.' },
		{ id: 'Confidence', note: 'Confidence tiers in tables and charts.' }
	] as const;

	function set(key: string, value: string) {
		const hex = ('#' + value.trim().replace(/^#/, '')).toUpperCase();
		if (!HEX.test(hex)) return;
		const side = { ...ui.prefs.colours[mode] };
		if (hex === plain[key]) delete side[key];
		else side[key] = hex;
		ui.update({ colours: { ...ui.prefs.colours, [mode]: side } });
	}
	function reset(key: string) {
		const side = { ...ui.prefs.colours[mode] };
		delete side[key];
		ui.update({ colours: { ...ui.prefs.colours, [mode]: side } });
	}
	const pickPreset = (id: string) => ui.update(presetChange(ui.prefs.colours, id));

	// ---- sharing a theme ----
	let pasting = $state(false);
	let pasted = $state('');
	async function copy() {
		const theme = { margieTheme: 1, palette: chosen, accent: ui.prefs.accent, colours: ui.prefs.colours };
		try {
			await navigator.clipboard.writeText(JSON.stringify(theme, null, 2));
			ui.notify('Theme copied: paste it into another MARGIE', 'ok');
		} catch {
			ui.notify('Could not reach the clipboard', 'error');
		}
	}
	function applyPasted() {
		let raw: Record<string, unknown>;
		try {
			raw = JSON.parse(pasted);
		} catch {
			return ui.notify('That is not a theme: it should be the text Copy theme gives', 'error');
		}
		// Keeps only valid values, as saving does.
		const clean = sanitizePrefs({ ...ui.prefs, palette: raw.palette, accent: raw.accent, colours: raw.colours }, ui.prefs);
		ui.update({ palette: clean.palette, accent: clean.accent, colours: clean.colours });
		pasting = false;
		pasted = '';
		ui.notify('Theme applied', 'ok');
	}
</script>

<div class="editor">
	<section class="cr-group">
		<h3 class="cr-group-title">Preset</h3>
		<div class="presets" role="radiogroup" aria-label="Theme preset">
			{#each PRESETS as p (p.id)}
				{@const n = p[mode]}
				<button
					type="button"
					role="radio"
					class="preset"
					aria-checked={chosen === p.id}
					onclick={() => pickPreset(p.id)}
					style="--p-bg: {n.bg}; --p-sf: {n.surface}; --p-sf2: {n.surface2}; --p-bd: {n.border}; --p-t: {n.text}; --p-t3: {n.text3}; --p-ac: {accentColor(ui.prefs, ui.dark)}"
				>
					<span class="mini" aria-hidden="true">
						<span class="card">
							<span class="band"></span>
							<span class="l1"></span>
							<span class="l2"></span>
							<span class="dot"></span>
						</span>
					</span>
					<span class="pname">{p.name}{p.id === base ? ' | default' : ''}</span>
					<span class="pnote">{p.note}</span>
				</button>
			{/each}
		</div>
	</section>

	<p class="mg-note which"><span class="which-dot" aria-hidden="true"></span>Editing {mode}-mode colours. Switch to {ui.dark ? 'light' : 'dark'} mode to edit those.</p>

	<section class="cr-group">
		<h3 class="cr-group-title">Accent</h3>
		<div class="row accent">
			<label class="well" style="--c: {accentColor(ui.prefs, ui.dark)}">
				<input type="color" value={accentColor(ui.prefs, ui.dark)} oninput={(e) => ui.update({ accent: e.currentTarget.value.toUpperCase() })} aria-label="Accent" />
			</label>
			<span class="what"><span class="label">Accent</span><span class="hint">buttons, links, focus</span></span>
			<input
				class="mg-input mono hex"
				value={accentColor(ui.prefs, ui.dark)}
				spellcheck="false"
				aria-label="Accent as hex"
				onchange={(e) => HEX.test(e.currentTarget.value.trim()) && ui.update({ accent: e.currentTarget.value.trim().toUpperCase() })}
			/>
			<span class="ratio">{contrast(accentColor(ui.prefs, ui.dark), colours.surface).toFixed(1)}</span>
			<span class="reset-slot"></span>
		</div>
	</section>

	{#each GROUPS as g (g.id)}
		<section class="cr-group">
			<h3 class="cr-group-title">{g.id}</h3>
			{#if g.note}<p class="mg-note">{g.note}</p>{/if}
			<ul class="rows">
				{#each TOKENS.filter((t) => t.group === g.id) as t (t.key)}
					{@const value = colours[t.key]}
					{@const need = t.group === 'Sections' ? 3 : 4.5}
					{@const r = t.text ? contrast(value, colours.surface) : 0}
					<li class="row" class:flag={flagged.has(t.key)}>
						<label class="well" style="--c: {value}">
							<input type="color" {value} oninput={(e) => set(t.key, e.currentTarget.value)} aria-label={t.label} />
						</label>
						<span class="what">
							<span class="label" style={t.text ? `color: ${value}` : undefined}>{t.label}</span>
							{#if t.hint}<span class="hint">{t.hint}</span>{/if}
						</span>
						<input
							class="mg-input mono hex"
							{value}
							spellcheck="false"
							aria-label="{t.label} as hex"
							onchange={(e) => set(t.key, e.currentTarget.value)}
							onkeydown={(e) => e.key === 'Enter' && set(t.key, e.currentTarget.value)}
						/>
						{#if t.text}
							<span class="ratio" class:low={r < need} title="Contrast on the cards; {need}:1 is enough">{r.toFixed(1)}</span>
						{:else}
							<span class="ratio"></span>
						{/if}
						<span class="reset-slot">
							{#if edited[t.key]}
								<button type="button" class="mg-icon-btn" title="Back to {plain[t.key]}" aria-label="Reset {t.label}" onclick={() => reset(t.key)}>
									<RotateCcw size={13} />
								</button>
							{/if}
						</span>
					</li>
				{/each}
			</ul>
		</section>
	{/each}

	<section class="cr-group checks" class:ok={!checks.length}>
		<h3 class="cr-group-title">Checks</h3>
		{#if checks.length}
			<ul>
				{#each checks as c (c.text)}<li class={c.level}>{c.text}</li>{/each}
			</ul>
		{:else}
			<p>
				All text meets 4.5:1 contrast, and states and tiers are distinguishable{ui.prefs.vision === 'typical'
					? ''
					: ` with ${visionInfo(ui.prefs.vision).plain.toLowerCase()}`}.
			</p>
		{/if}
	</section>

	<section class="cr-group share">
		<h3 class="cr-group-title">Share</h3>
		<div class="acts">
			<button type="button" class="mg-btn small" onclick={copy}>Copy theme</button>
			<button type="button" class="mg-btn small" aria-expanded={pasting} onclick={() => (pasting = !pasting)}>Paste a theme</button>
			<span class="mg-grow"></span>
			<button type="button" class="mg-link quiet" disabled={!editedCount} onclick={() => ui.update({ colours: { light: {}, dark: {} } })}>
				Reset {editedCount || ''} colour{editedCount === 1 ? '' : 's'}
			</button>
		</div>
		{#if pasting}
			<textarea class="mg-input mono" rows="5" placeholder={'{ "margieTheme": 1, ... }'} bind:value={pasted}></textarea>
			<div class="acts">
				<span class="mg-note">Paste text from Copy theme.</span>
				<span class="mg-grow"></span>
				<button type="button" class="mg-btn small primary" disabled={!pasted.trim()} onclick={applyPasted}>Apply</button>
			</div>
		{/if}
	</section>
</div>

<style>
	.editor {
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	/* Each part is a slightly tighter Customize card (crisp.css .cr-group). */
	section {
		gap: 10px;
	}
	.presets {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(112px, 1fr));
		gap: 8px;
	}
	.preset {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: 6px 6px 8px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-surface);
		color: inherit;
		font: inherit;
		text-align: left;
		cursor: pointer;
		transition:
			border-color var(--mo-1) var(--mo-ease),
			transform var(--mo-1) var(--mo-ease),
			box-shadow var(--mo-1) var(--mo-ease);
	}
	.preset:hover {
		border-color: color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		box-shadow: var(--mg-shadow-sm);
	}
	.preset[aria-checked='true'] {
		border-color: var(--mg-accent);
		background: color-mix(in srgb, var(--mg-accent) 6%, var(--mg-surface));
		box-shadow: 0 0 0 1px var(--mg-accent);
	}
	:global([data-motion='off']) .preset {
		transition: none;
		transform: none;
	}
	.mini {
		display: block;
		height: 54px;
		margin-bottom: 4px;
		padding: 8px;
		border-radius: calc(var(--mg-r) - 3px);
		background: var(--p-bg);
		box-shadow: inset 0 0 0 1px var(--p-bd);
	}
	.card {
		position: relative;
		display: block;
		height: 100%;
		border: 1px solid var(--p-bd);
		border-radius: 4px;
		background: var(--p-sf);
		overflow: hidden;
	}
	.band {
		position: absolute;
		inset: 0 0 auto;
		height: 9px;
		background: var(--p-sf2);
		border-bottom: 1px solid var(--p-bd);
	}
	.l1,
	.l2 {
		position: absolute;
		left: 6px;
		height: 3px;
		border-radius: 2px;
	}
	.l1 {
		top: 15px;
		width: 55%;
		background: var(--p-t);
	}
	.l2 {
		top: 23px;
		width: 38%;
		background: var(--p-t3);
	}
	.dot {
		position: absolute;
		right: 6px;
		bottom: 5px;
		width: 18px;
		height: 7px;
		border-radius: var(--mg-r-sm);
		background: var(--p-ac);
	}
	.pname {
		font-size: var(--mg-fs-sm);
		font-weight: 600;
	}
	.pnote {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
		line-height: 1.35;
	}
	.which {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 8px 16px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
	}
	.which-dot {
		flex: none;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--mg-accent);
	}
	.rows {
		display: flex;
		flex-direction: column;
	}
	.row {
		display: grid;
		grid-template-columns: 28px minmax(0, 1fr) 84px 34px 26px;
		align-items: center;
		gap: 10px;
		min-height: 38px;
		padding: 3px 4px;
		border-radius: var(--mg-r-sm);
	}
	.row + .row {
		border-top: 1px solid var(--mg-border);
	}
	.row.flag {
		background: var(--mg-warn-soft);
	}
	.well {
		position: relative;
		width: 28px;
		height: 28px;
		border-radius: 50%;
		background: var(--c);
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--mg-text) 16%, transparent);
		cursor: pointer;
	}
	.well input {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		opacity: 0;
		cursor: pointer;
	}
	.what {
		display: flex;
		flex-direction: column;
		min-width: 0;
		line-height: 1.3;
	}
	.label {
		font-size: var(--mg-fs-sm);
		font-weight: 600;
	}
	.hint {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.hex {
		width: 100%;
		height: 30px;
		padding: 0 8px;
		font-size: var(--mg-fs-xs);
		text-transform: uppercase;
	}
	.ratio {
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-3);
		text-align: right;
	}
	.ratio.low {
		color: var(--mg-danger);
	}
	.checks ul {
		display: flex;
		flex-direction: column;
		gap: 4px;
		font-size: var(--mg-fs-sm);
	}
	.checks li {
		padding: 8px 12px;
		border-radius: var(--mg-r);
		background: var(--mg-warn-soft);
		color: var(--mg-text);
	}
	.checks li.bad {
		background: var(--mg-danger-soft);
	}
	.checks p {
		padding: 10px 12px;
		border-radius: var(--mg-r);
		background: color-mix(in srgb, var(--mg-ok) 8%, var(--mg-surface));
		font-size: var(--mg-fs-sm);
	}

	.acts {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 10px;
	}
	textarea {
		width: 100%;
		font-size: var(--mg-fs-xs);
	}
</style>
