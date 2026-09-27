<script lang="ts">
	import { preview } from './preview.svelte';
	import { ui } from './ui.svelte';
	import { feValues, recolourMatrix, simMatrix } from './vision';

	/**
	 * SVG colour matrices referenced by workspace.css: one recolours figures for the chosen vision,
	 * the other previews the page as another vision sees it. Both work in linear RGB.
	 */
	const fix = $derived(ui.prefs.recolour ? recolourMatrix(ui.prefs.vision, ui.prefs.visionStrength) : null);
	const sim = $derived(preview.vision !== 'typical' ? simMatrix(preview.vision, ui.prefs.visionStrength) : null);
</script>

<svg class="vision-filters" aria-hidden="true" focusable="false" width="0" height="0">
	{#if fix}
		<filter id="mg-recolour" color-interpolation-filters="linearRGB">
			<feColorMatrix type="matrix" values={feValues(fix)} />
		</filter>
	{/if}
	{#if sim}
		<filter id="mg-preview" color-interpolation-filters="linearRGB">
			<feColorMatrix type="matrix" values={feValues(sim)} />
		</filter>
	{/if}
</svg>

<style>
	.vision-filters {
		position: absolute;
		width: 0;
		height: 0;
		overflow: hidden;
		pointer-events: none;
	}
</style>
