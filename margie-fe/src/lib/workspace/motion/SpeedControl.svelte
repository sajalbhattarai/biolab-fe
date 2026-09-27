<script lang="ts">
	import { SPEEDS } from '../prefs';
	import { ui } from '../ui.svelte';

	/** Animation speed, from half to twice as fast, with a dot that moves at the chosen pace. */
	const index = $derived(Math.max(0, SPEEDS.indexOf(ui.prefs.speed)));
	const off = $derived(ui.motion === 'off');
</script>

<div class="speed" class:off>
	<span class="end">Slower</span>
	<input
		type="range"
		min="0"
		max={SPEEDS.length - 1}
		step="1"
		value={index}
		disabled={off}
		aria-label="Animation speed"
		aria-valuetext="{ui.prefs.speed} times"
		oninput={(e) => ui.update({ speed: SPEEDS[Number(e.currentTarget.value)] })}
	/>
	<span class="end">Faster</span>
	<span class="val">{ui.prefs.speed}×</span>
	<span class="demo" aria-hidden="true"><span></span></span>
</div>

<style>
	.speed {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: var(--mg-fs-xs);
		color: var(--at-ink-3, var(--mg-text-3));
	}
	input {
		flex: 1 1 90px;
		min-width: 70px;
		accent-color: var(--at-teal, var(--mg-accent));
		cursor: pointer;
	}
	input:disabled {
		cursor: not-allowed;
	}
	.val {
		min-width: 3.2em;
		font-variant-numeric: tabular-nums;
		font-weight: 600;
		color: var(--at-ink, var(--mg-text));
	}
	.off .val {
		color: inherit;
	}
	.demo {
		position: relative;
		flex-shrink: 0;
		width: 34px;
		height: 8px;
		border-radius: var(--mg-r-sm);
		background: var(--at-track, var(--mg-surface-2));
	}
	.demo span {
		position: absolute;
		top: 1px;
		left: 1px;
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: var(--at-teal, var(--mg-accent));
		animation: demo calc(900ms * var(--mo-k)) cubic-bezier(0.65, 0, 0.35, 1) infinite alternate;
	}
	.off .demo span {
		animation: none;
	}
	@keyframes demo {
		to {
			transform: translateX(26px);
		}
	}
</style>
