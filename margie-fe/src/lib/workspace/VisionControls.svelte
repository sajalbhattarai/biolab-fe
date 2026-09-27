<script lang="ts">
	import Switch from './Switch.svelte';
	import { preview, recolouring } from './preview.svelte';
	import { resolveColours } from './prefs';
	import { checkColours } from './themes';
	import { ui } from './ui.svelte';
	import { paletteFor, recolourMatrix, simulate, TYPICAL_TIERS, visionInfo, VISIONS, type Vision } from './vision';

	/**
	 * Colour-vision settings: target vision, cone strength, figure recolouring, state symbols and a
	 * page preview. `base` is the interface's theme preset, used for the checks.
	 */
	let { base = 'paper' }: { base?: string } = $props();

	const GROUPS = [
		{ id: 'typical', label: '' },
		{ id: 'anomalous', label: 'Partial: anomalous trichromacy' },
		{ id: 'dichromacy', label: 'Complete: dichromacy' },
		{ id: 'monochromacy', label: 'Little or no colour: monochromacy' }
	] as const;

	const chosen = $derived(visionInfo(ui.prefs.vision));
	const graded = $derived(chosen.graded || visionInfo(preview.vision).graded);
	const canRecolour = $derived(!!recolourMatrix(ui.prefs.vision, 1));

	function pick(v: Vision) {
		// Turns symbols on for any non-typical vision; they can be turned off again.
		ui.update(v === 'typical' ? { vision: v } : { vision: v, marks: true });
	}

	/** Each vision's colours as that vision sees them: states, then tiers. */
	function strip(v: Vision) {
		const pal = paletteFor(v, ui.dark);
		const typical = resolveColours({ ...ui.prefs, vision: 'typical', colours: { light: {}, dark: {} } }, ui.dark, base);
		const cols = pal ? [...pal.status, ...pal.tiers.slice(0, 5)] : [typical.ok, typical.warn, typical.danger, ...TYPICAL_TIERS];
		const s = visionInfo(v).graded ? ui.prefs.visionStrength : 1;
		return cols.map((c) => simulate(c, v, s));
	}

	const checks = $derived(checkColours(resolveColours(ui.prefs, ui.dark, base), ui.prefs.vision, ui.prefs.visionStrength));
</script>

<div class="vision">
	<p class="lead">Pick a colour vision deficiency, and the colours for states, sections, confidence tiers and tables are adjusted so they stay distinguishable.</p>

	<section class="cr-group">
		<h3 class="cr-group-title">Whose eyes</h3>
		<div class="types" role="radiogroup" aria-label="Colour vision deficiency">
			{#each GROUPS as g (g.id)}
				{#if g.label}<p class="group">{g.label}</p>{/if}
				{#each VISIONS.filter((v) => v.group === g.id) as v (v.id)}
					<button type="button" role="radio" class="type" aria-checked={ui.prefs.vision === v.id} onclick={() => pick(v.id)}>
						<span class="mg-radio" aria-hidden="true"></span>
						<span class="text">
							<span class="name"><b>{v.plain}</b>{#if v.id !== 'typical'}<span class="clinical">{v.name}</span>{/if}</span>
							<span class="note">{v.note}{v.common ? ` | ${v.common}` : ''}</span>
						</span>
						<span class="strip" aria-hidden="true" title="Its colours, as seen with {v.plain.toLowerCase()}">
							{#each strip(v.id) as c, i (i)}<span class:gap={i === 3} style="background: {c}"></span>{/each}
						</span>
					</button>
				{/each}
			{/each}
		</div>

		{#if graded}
			<label class="strength">
				<span class="row">
					<span class="mg-label">How weak</span>
					<span class="mg-grow"></span>
					<span class="val">{Math.round(ui.prefs.visionStrength * 100)}%</span>
				</span>
				<input
					type="range"
					min="0.1"
					max="1"
					step="0.05"
					value={ui.prefs.visionStrength}
					oninput={(e) => ui.update({ visionStrength: Number(e.currentTarget.value) })}
				/>
				<span class="mg-note">Used for recolouring figures and for the preview.</span>
			</label>
		{/if}
	</section>

	<section class="cr-group switches">
		<h3 class="cr-group-title">Help</h3>
		<div class="sw">
			<span class="text">
				<span class="mg-label">Recolour figures and images</span>
				<span class="mg-note">
					{#if canRecolour}
						Shifts colours in figures, maps and images so they can be told apart.
					{:else if ui.prefs.vision === 'typical'}
						Only for red or green deficiency.
					{:else}
						Not available for {chosen.plain.toLowerCase()}; figures are shown as drawn.
					{/if}
				</span>
			</span>
			<Switch label="Recolour figures and images" checked={recolouring()} disabled={!canRecolour} onchange={(recolour) => ui.update({ recolour })} />
		</div>
		<div class="sw">
			<span class="text">
				<span class="mg-label">Symbols beside states</span>
				<span class="mg-note">Adds ✓, !, ✕ and ▸ next to done, attention, failed and running.</span>
			</span>
			<Switch label="Symbols beside states" checked={ui.prefs.marks} onchange={(marks) => ui.update({ marks })} />
		</div>
	</section>

	<section class="cr-group preview">
		<h3 class="cr-group-title">Preview</h3>
		<label class="mg-label" for="vision-preview">See the page as</label>
		<select id="vision-preview" class="mg-select" value={preview.vision} onchange={(e) => (preview.vision = e.currentTarget.value as Vision)}>
			<option value="typical">Off</option>
			{#each VISIONS.slice(1) as v (v.id)}<option value={v.id}>{v.plain} ({v.name.toLowerCase()})</option>{/each}
		</select>
		<span class="mg-note">Shows the whole page as someone with that deficiency sees it. It stays on until you turn it off.</span>
	</section>

	{#if ui.prefs.vision !== 'typical' || checks.length}
		<div class="verdict" class:bad={checks.length}>
			{#if checks.length}
				<p><b>{checks.length === 1 ? 'One thing' : `${checks.length} things`} to look at</b></p>
				<ul>
					{#each checks.slice(0, 5) as c (c.text)}<li>{c.text}</li>{/each}
				</ul>
				<p class="mg-note">Colours you changed by hand take priority. Reset them under Colours.</p>
			{:else}
				<p>States and tiers are distinguishable with {chosen.plain.toLowerCase()}, and all text meets 4.5:1 contrast.</p>
			{/if}
		</div>
	{/if}
</div>

<style>
	.vision {
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	/* Parts are Customize cards (crisp.css .cr-group). */
	section {
		gap: 12px;
	}
	.lead {
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
		line-height: 1.55;
	}
	.types {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.group {
		margin: 12px 0 4px 4px;
		font-size: var(--mg-fs-sm);
		font-weight: 600;
		color: var(--mg-text-2);
	}
	.type {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr) auto;
		align-items: center;
		gap: 4px 12px;
		width: 100%;
		padding: 9px 12px;
		border: 1px solid transparent;
		border-radius: var(--mg-r);
		background: none;
		color: inherit;
		font: inherit;
		text-align: left;
		cursor: pointer;
	}
	.type:hover {
		background: var(--mg-surface-2);
	}
	.type[aria-checked='true'] {
		border-color: color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-accent) 7%, var(--mg-surface));
	}
	.text {
		display: flex;
		flex-direction: column;
		gap: 1px;
		min-width: 0;
	}
	.name {
		display: flex;
		align-items: baseline;
		flex-wrap: wrap;
		gap: 2px 8px;
		font-size: var(--mg-fs-sm);
	}
	.name b {
		font-weight: 650;
	}
	.clinical {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.note {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
		line-height: 1.45;
	}
	.strip {
		display: flex;
		gap: 2px;
	}
	.strip span {
		width: 9px;
		height: 18px;
		border-radius: 2px;
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--mg-text) 10%, transparent);
	}
	.strip .gap {
		margin-left: 5px;
	}
	.strength {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.strength .row {
		display: flex;
		align-items: baseline;
	}
	.val {
		font-size: var(--mg-fs-sm);
		font-weight: 650;
		font-variant-numeric: tabular-nums;
	}
	input[type='range'] {
		width: 100%;
		accent-color: var(--mg-accent);
	}
	.switches {
		gap: 14px;
	}
	.sw {
		display: flex;
		align-items: flex-start;
		gap: 14px;
	}
	.sw .text {
		flex: 1;
		gap: 3px;
	}
	.preview {
		gap: 8px;
	}
	.verdict {
		padding: 12px 14px;
		border: 1px solid color-mix(in srgb, var(--mg-ok) 40%, var(--mg-border));
		border-radius: var(--mg-r);
		background: color-mix(in srgb, var(--mg-ok) 6%, var(--mg-surface));
		font-size: var(--mg-fs-sm);
		line-height: 1.5;
	}
	.verdict.bad {
		border-color: color-mix(in srgb, var(--mg-warn) 55%, var(--mg-border));
		background: var(--mg-warn-soft);
	}
	.verdict ul {
		margin: 6px 0;
		padding-left: 18px;
		list-style: disc;
	}
</style>
