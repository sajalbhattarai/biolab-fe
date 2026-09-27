<script lang="ts">
	import SpeedControl from './motion/SpeedControl.svelte';
	import Field from './Field.svelte';
	import FontPicker from './FontPicker.svelte';
	import Seg from './Seg.svelte';
	import SizeSliders from './SizeSliders.svelte';
	import { ACCENTS, accentColor } from './prefs';
	import { ui } from './ui.svelte';

	/** Shared appearance settings for the Customize drawer: colour and shape, type, motion. */
	const HEX = /^#?[0-9a-fA-F]{6}$/;
	const custom = $derived(ui.prefs.accent.startsWith('#'));
	let hex = $state('');
	$effect(() => {
		hex = accentColor(ui.prefs, ui.dark);
	});

	function setHex(v: string) {
		const t = v.trim();
		if (HEX.test(t)) ui.update({ accent: ('#' + t.replace('#', '')).toUpperCase() });
	}
</script>

<section class="cr-group">
	<h3 class="cr-group-title">Colour and shape</h3>
	<Field title="Theme">
		<Seg
			label="Theme"
			value={ui.prefs.theme}
			onpick={(theme) => ui.update({ theme })}
			options={[
				{ value: 'light', label: 'Light' },
				{ value: 'dark', label: 'Dark' },
				{ value: 'system', label: 'System' }
			]}
		/>
	</Field>

	<Field title="Accent">
		<div class="swatches" role="radiogroup" aria-label="Accent colour">
			{#each ACCENTS as a (a.id)}
				<button
					type="button"
					role="radio"
					class="swatch mg-t"
					aria-checked={ui.prefs.accent === a.id}
					aria-label={a.name}
					title={a.name}
					style="--c: {ui.dark ? a.dark : a.light}"
					onclick={() => ui.update({ accent: a.id })}
				></button>
			{/each}
			<label class="swatch picker mg-t" class:selected={custom} title="Custom colour" style="--c: {custom ? ui.prefs.accent : 'transparent'}">
				<span class="mg-sr">Custom colour</span>
				<input type="color" value={accentColor(ui.prefs, ui.dark)} oninput={(e) => setHex(e.currentTarget.value)} />
			</label>
			<input
				class="mg-input mono hex"
				aria-label="Accent colour as hex"
				spellcheck="false"
				bind:value={hex}
				onchange={() => setHex(hex)}
				onkeydown={(e) => e.key === 'Enter' && setHex(hex)}
			/>
		</div>
	</Field>

	<Field title="Corners">
		<Seg
			label="Corners"
			value={ui.prefs.radius}
			onpick={(radius) => ui.update({ radius })}
			options={[
				{ value: 0, label: 'Sharp' },
				{ value: 6, label: 'Soft' },
				{ value: 10, label: 'Round' }
			]}
		/>
	</Field>

	<Field title="Density">
		<Seg
			label="Density"
			value={ui.prefs.density}
			onpick={(density) => ui.update({ density })}
			options={[
				{ value: 'compact', label: 'Compact' },
				{ value: 'comfortable', label: 'Comfortable' }
			]}
		/>
	</Field>

</section>

<section class="cr-group">
	<h3 class="cr-group-title">Type</h3>
	<Field title="Size">
		<SizeSliders />
	</Field>

	<Field title="Font">
		<FontPicker value={ui.prefs.typeface} onchange={(typeface) => ui.update({ typeface })} />
	</Field>

	<Field title="Monospace">
		<!-- Separate from the interface font: used for logs, paths and sequences. -->
		<FontPicker only="mono" value={ui.prefs.monoface} onchange={(monoface) => ui.update({ monoface })} />
	</Field>

</section>

<section class="cr-group">
	<h3 class="cr-group-title">Motion</h3>
	<Field title="Motion">
		<Seg
			label="Motion"
			value={ui.prefs.motion}
			onpick={(motion) => ui.update({ motion })}
			options={[
				{ value: 'full', label: 'Full' },
				{ value: 'subtle', label: 'Subtle' },
				{ value: 'off', label: 'Off' }
			]}
		/>
		{#if ui.reducedMotion}
			<span class="note">Your computer asks for reduced motion, so animations stay off.</span>
		{/if}
	</Field>

	<Field title="Speed">
		<SpeedControl />
	</Field>
</section>

<style>
	.swatches {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 10px;
	}
	.swatch {
		position: relative;
		width: 26px;
		height: 26px;
		padding: 0;
		border: none;
		border-radius: var(--mg-r-sm);
		background: var(--c);
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--mg-text) 12%, transparent);
		cursor: pointer;
		transition: transform var(--mo-1) var(--mo-ease);
	}
	.swatch:hover {
		transform: scale(1.1);
	}
	.swatch[aria-checked='true'],
	.swatch.selected {
		box-shadow: 0 0 0 2px var(--mg-surface), 0 0 0 4px var(--c);
	}
	.picker {
		display: inline-block;
		border: 1.5px dashed var(--mg-border-strong);
		background: transparent;
	}
	.picker.selected {
		border: none;
		background: var(--c);
	}
	.picker input {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		opacity: 0;
		cursor: pointer;
	}
	.hex {
		width: 104px;
		height: 34px;
		margin-left: auto;
		text-transform: uppercase;
	}
	.note {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
</style>
