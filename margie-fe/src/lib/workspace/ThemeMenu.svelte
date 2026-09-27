<script lang="ts">
	import { SunMoon } from 'lucide-svelte';
	import MenuButton from './MenuButton.svelte';
	import SizeSliders from './SizeSliders.svelte';
	import type { UiPrefs } from './prefs';
	import { presetChange, PRESETS } from './themes';
	import { ui } from './ui.svelte';

	/**
	 * Theme button in the corner: light or dark, plus colour presets, text size and face where the
	 * interface supports them. Everything else is in Customize (`onmore`).
	 */
	let {
		base = 'paper',
		colours = true,
		type = true,
		showLabel = true,
		note = '',
		onmore
	}: {
		/** The interface's preset, used while none is picked. */
		base?: string;
		/** Offers the presets (off for interfaces with their own colours). */
		colours?: boolean;
		/** Offers text size and face. */
		type?: boolean;
		showLabel?: boolean;
		note?: string;
		onmore?: () => void;
	} = $props();

	const LIGHTS: [UiPrefs['theme'], string][] = [
		['light', 'Light'],
		['dark', 'Dark'],
		['system', 'System']
	];
	const FACES: [UiPrefs['typeface'], string][] = [
		['helvetica', 'Helvetica'],
		['menlo', 'Menlo'],
		['plex', 'Plex'],
		['system', 'System']
	];
	const chosen = $derived(ui.prefs.palette || base);
</script>

{#snippet seg(label: string, options: [string, string][], value: string, pick: (v: string) => void)}
	<div class="tm-group">
		<span class="tm-label">{label}</span>
		<div class="tm-seg" role="radiogroup" aria-label={label} style="grid-template-columns: repeat({options.length === 4 ? 2 : options.length}, minmax(0, 1fr))">
			{#each options as [v, l] (v)}
				<button type="button" role="radio" aria-checked={value === v} onclick={() => pick(v)}>{l}</button>
			{/each}
		</div>
	</div>
{/snippet}

<MenuButton label="Theme" {showLabel} width={340}>
	{#snippet icon()}<SunMoon size={16} />{/snippet}
	{#snippet children(close)}
		{@render seg('Light or dark', LIGHTS, ui.prefs.theme, (v) => ui.update({ theme: v as UiPrefs['theme'] }))}
		{#if colours}
			<div class="tm-group">
				<span class="tm-label">Colours</span>
				<div class="tm-presets">
					{#each PRESETS as p (p.id)}
						{@const c = ui.dark ? p.dark : p.light}
						<button type="button" class="tm-preset" aria-pressed={chosen === p.id} onclick={() => ui.update(presetChange(ui.prefs.colours, p.id))}>
							<span class="tm-swatch" aria-hidden="true" style="--a: {c.bg}; --b: {c.surface2}; --c: {c.text}; border-color: {c.borderStrong}"></span>
							<span class="tm-name">{p.name}</span>
						</button>
					{/each}
				</div>
			</div>
		{/if}
		{#if type}
			<div class="tm-group"><SizeSliders /></div>
			{@render seg('Font', FACES, ui.prefs.typeface, (v) => ui.update({ typeface: v as UiPrefs['typeface'] }))}
		{/if}
		{#if note}<p class="tm-note">{note}</p>{/if}
		{#if onmore}
			<button
				type="button"
				class="tm-more"
				onclick={() => {
					close();
					onmore();
				}}>More in Customize</button
			>
		{/if}
	{/snippet}
</MenuButton>

<style>
	.tm-group {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.tm-group + .tm-group {
		padding-top: 14px;
		border-top: 1px solid var(--mg-border, #e2e4e8);
	}
	.tm-label {
		font-size: var(--cr-fs-micro, var(--mg-fs-xs, 12px));
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--mg-text-3, #646b76);
	}
	/* Same pill tray as the segmented choices. */
	.tm-seg {
		display: grid;
		gap: 2px;
		padding: 3px;
		border: 1px solid var(--mg-border, #e2e4e8);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text, #15181d) 4%, var(--mg-surface, #fff));
	}
	.tm-seg:has(> :nth-child(4)) {
		border-radius: calc(var(--mg-r, 8px) + 6px);
	}
	.tm-seg button {
		min-width: 0;
		height: 30px;
		padding: 0 6px;
		overflow: hidden;
		border: 0;
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-text-2, #454c57);
		font: inherit;
		font-size: var(--cr-fs-meta, var(--mg-fs-sm, 14px));
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
		cursor: pointer;
		transition: color var(--mo-1, 120ms) var(--mo-ease, ease);
	}
	.tm-seg button:hover {
		color: var(--mg-text, #15181d);
	}
	.tm-seg button[aria-checked='true'] {
		background: var(--mg-seg-sel, var(--mg-surface, #fff));
		box-shadow:
			var(--mg-shadow-sm, 0 1px 2px rgba(16, 24, 40, 0.06)),
			0 0 0 1px var(--mg-border, #e2e4e8);
		color: var(--mg-accent-ink, var(--mg-text, #15181d));
		font-weight: 600;
	}
	.tm-presets {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 6px;
	}
	.tm-preset {
		display: flex;
		align-items: center;
		gap: 9px;
		min-width: 0;
		height: 34px;
		padding: 0 12px 0 6px;
		border: 1px solid var(--mg-border, #e2e4e8);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface, #fff);
		color: var(--mg-text, #15181d);
		font: inherit;
		font-size: var(--cr-fs-meta, var(--mg-fs-sm, 14px));
		cursor: pointer;
		transition:
			border-color var(--mo-1, 120ms) var(--mo-ease, ease),
			background-color var(--mo-1, 120ms) var(--mo-ease, ease);
	}
	.tm-preset:hover {
		border-color: color-mix(in srgb, var(--mg-accent-base, var(--mg-accent, #0f766e)) 45%, var(--mg-border, #e2e4e8));
	}
	.tm-preset[aria-pressed='true'] {
		border-color: var(--mg-accent-base, var(--mg-accent, #0f766e));
		background: color-mix(in srgb, var(--mg-accent-base, var(--mg-accent, #0f766e)) 8%, var(--mg-surface, #fff));
		box-shadow: 0 0 0 1px var(--mg-accent-base, var(--mg-accent, #0f766e));
		font-weight: 600;
	}
	/* Preset swatch as rings: ink, panels, page. */
	.tm-swatch {
		flex-shrink: 0;
		width: 22px;
		height: 22px;
		border: 1px solid;
		border-radius: 50%;
		background: radial-gradient(circle, var(--c) 0 3px, var(--b) 3.5px 6px, var(--a) 6.5px);
	}
	.tm-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.tm-note {
		font-size: var(--cr-fs-meta, var(--mg-fs-sm, 14px));
		color: var(--mg-text-3, #646b76);
	}
	.tm-more {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		height: 34px;
		padding: 0 16px;
		border: 1px solid var(--mg-border, #e2e4e8);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text, #15181d) 3%, var(--mg-surface, #fff));
		color: var(--mg-accent-ink, var(--mg-accent, #0f766e));
		font: inherit;
		font-size: var(--cr-fs-meta, var(--mg-fs-sm, 14px));
		font-weight: 600;
		cursor: pointer;
	}
	.tm-more:hover {
		border-color: var(--mg-accent-base, var(--mg-accent, #0f766e));
	}
</style>
