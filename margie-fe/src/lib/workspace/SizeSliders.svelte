<script lang="ts">
	import { TEXT_STEPS, textStep } from './prefs';
	import { ui } from './ui.svelte';

	/** Two sliders: text size, and control size (inputs, menus, buttons, table rows), with Small/Medium/Large marks. */
	const pct = (v: number) => `${Math.round(v * 100)}%`;
	const text = $derived(ui.prefs.textScale);
	const field = $derived(ui.prefs.fieldScale);
	const STEPS = [
		['s', 'S'],
		['m', 'M'],
		['l', 'L']
	] as const;
</script>

<div class="sizes">
	<div class="row">
		<span class="name">Text size</span>
		<input
			type="range"
			min="0.8"
			max="1.5"
			step="0.05"
			value={text}
			aria-label="Text size"
			aria-valuetext={pct(text)}
			oninput={(e) => ui.update({ textScale: Number(e.currentTarget.value) })}
		/>
		<span class="val">{pct(text)}</span>
	</div>
	<div class="steps" role="radiogroup" aria-label="Text size presets">
		{#each STEPS as [k, l] (k)}
			<button type="button" role="radio" aria-checked={textStep(text) === k} onclick={() => ui.update({ textScale: TEXT_STEPS[k], textSize: k })}>{l}</button>
		{/each}
	</div>
	<div class="row">
		<span class="name">Field size</span>
		<input
			type="range"
			min="0.8"
			max="1.6"
			step="0.05"
			value={field}
			aria-label="Field size"
			aria-valuetext={pct(field)}
			oninput={(e) => ui.update({ fieldScale: Number(e.currentTarget.value) })}
		/>
		<span class="val">{pct(field)}</span>
	</div>
	<span class="note">Field size sets how tall input boxes, menus, buttons and table rows are.</span>
	{#if text !== 1 || field !== 1}
		<button type="button" class="reset" onclick={() => ui.update({ textScale: 1, textSize: 'm', fieldScale: 1 })}>Back to 100%</button>
	{/if}
</div>

<style>
	.sizes {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.row {
		display: grid;
		grid-template-columns: 6.5em minmax(80px, 1fr) 3.4em;
		align-items: center;
		gap: 10px;
		font-size: var(--cr-fs-meta, var(--mg-fs-sm, 14px));
		color: var(--at-ink-2, var(--mg-text-2));
	}
	input {
		width: 100%;
		accent-color: var(--at-teal, var(--mg-accent));
		cursor: pointer;
	}
	.val {
		text-align: right;
		font-variant-numeric: tabular-nums;
		font-weight: 600;
		color: var(--at-ink, var(--mg-text));
	}
	.steps {
		display: flex;
		gap: 6px;
		margin: -2px 0 4px calc(6.5em + 10px);
	}
	.steps button,
	.reset {
		height: 24px;
		padding: 0 10px;
		border: 1px solid var(--mg-border, #d5d8dd);
		border-radius: var(--mg-r-sm);
		background: transparent;
		color: var(--mg-text-2, #454c57);
		font: inherit;
		font-size: var(--mg-fs-xs, 12px);
		cursor: pointer;
	}
	.steps button:hover,
	.reset:hover {
		border-color: color-mix(in srgb, var(--mg-accent, #0f766e) 45%, var(--mg-border, #d5d8dd));
		color: var(--mg-text, #15181d);
	}
	.steps button[aria-checked='true'] {
		border-color: var(--at-teal, var(--mg-accent));
		background: color-mix(in srgb, var(--mg-accent, #0f766e) 10%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
		font-weight: 600;
	}
	.reset {
		align-self: flex-start;
	}
	.note {
		font-size: var(--mg-fs-xs, 12px);
		color: var(--at-ink-3, var(--mg-text-3));
		line-height: 1.45;
	}
</style>
