<script lang="ts">
	/**
	 * Build or download progress: label, the run's own status text or percentage, and a bar
	 * with a sheen while running (static when motion is off).
	 */
	let { percent, label = '', text = '', small = false }: { percent: number; label?: string; text?: string; small?: boolean } = $props();
	const p = $derived(Math.max(2, Math.min(100, Math.round(percent || 0))));
</script>

<div class="bb" class:small role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={p} aria-label={label || 'Progress'}>
	{#if label || !small}
		<div class="bb-top">
			{#if label}<span class="bb-label">{label}</span>{/if}
			<span class="bb-num">{text || `${p}%`}</span>
		</div>
	{/if}
	<div class="bb-track"><div class="bb-fill" style="width: {p}%"></div></div>
</div>

<style>
	.bb {
		display: flex;
		flex-direction: column;
		gap: 5px;
		min-width: 0;
	}
	.bb-top {
		display: flex;
		align-items: baseline;
		gap: 10px;
		font-size: var(--mg-fs-xs);
	}
	.bb-label {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-weight: 600;
		color: var(--mg-text);
	}
	.bb-num {
		margin-left: auto;
		flex: none;
		font-variant-numeric: tabular-nums;
		color: var(--mg-text-2);
	}
	.bb-track {
		position: relative;
		height: 8px;
		border-radius: 999px;
		background: color-mix(in srgb, var(--mg-accent) 12%, var(--mg-surface-2));
		overflow: hidden;
	}
	.small .bb-track {
		height: 4px;
	}
	.bb-fill {
		position: relative;
		height: 100%;
		border-radius: inherit;
		background: linear-gradient(90deg, color-mix(in srgb, var(--mg-accent) 75%, var(--mg-ok)), var(--mg-accent));
		transition: width 600ms cubic-bezier(0.2, 0.7, 0.2, 1);
		overflow: hidden;
	}
	.bb-fill::after {
		content: '';
		position: absolute;
		inset: 0;
		background: linear-gradient(90deg, transparent, rgb(255 255 255 / 0.35), transparent);
		transform: translateX(-100%);
		animation: sheen 1.8s ease-in-out infinite;
	}
	@keyframes sheen {
		to {
			transform: translateX(100%);
		}
	}
	:global([data-motion='off']) .bb-fill,
	:global([data-motion='off']) .bb-fill::after {
		animation: none;
		transition: none;
	}
</style>
