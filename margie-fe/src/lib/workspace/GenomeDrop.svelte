<script lang="ts">
	import { Upload } from 'lucide-svelte';
	import { fade } from 'svelte/transition';
	import { ws } from './data.svelte';
	import { ui } from './ui.svelte';

	/**
	 * Window-wide drop target for FASTA files, uploaded via ws.upload; drops already handled
	 * by a block (preventDefault) are ignored. `toasts` shows results where the shell has none.
	 */
	let { toasts = false }: { toasts?: boolean } = $props();

	const FASTA = /\.(fna|fa|fasta)$/i;
	/** Counts dragenter/dragleave, which fire for every element crossed. */
	let depth = $state(0);

	const carriesFiles = (e: DragEvent) => !!e.dataTransfer && Array.from(e.dataTransfer.types).includes('Files');

	function enter(e: DragEvent) {
		if (carriesFiles(e)) depth++;
	}
	function leave(e: DragEvent) {
		if (carriesFiles(e)) depth = Math.max(0, depth - 1);
	}
	function over(e: DragEvent) {
		if (!carriesFiles(e)) return;
		e.preventDefault();
		if (e.dataTransfer && !e.defaultPrevented) e.dataTransfer.dropEffect = 'copy';
	}
	function drop(e: DragEvent) {
		if (!carriesFiles(e)) return;
		depth = 0;
		if (e.defaultPrevented) return;
		e.preventDefault();
		const files = Array.from(e.dataTransfer?.files ?? []);
		const fasta = files.filter((f) => FASTA.test(f.name));
		const other = files.length - fasta.length;
		if (!fasta.length) {
			ui.notify('Only .fna, .fa and .fasta files can be added as genomes.', 'error');
			return;
		}
		if (other) ui.notify(`${other} file${other === 1 ? ' was' : 's were'} left out: not .fna, .fa or .fasta.`, 'info');
		ws.upload(fasta);
	}
</script>

<svelte:window ondragenter={enter} ondragleave={leave} ondragover={over} ondrop={drop} onblur={() => (depth = 0)} />

{#if depth > 0}
	<div class="gd" aria-hidden="true" transition:fade={{ duration: ui.ms(120) }}>
		<div class="gd-card">
			<span class="gd-icon"><Upload size={24} /></span>
			<b>Drop to add genomes</b>
			<span>FASTA files: .fna, .fa or .fasta</span>
		</div>
	</div>
{/if}

{#if toasts}
	<div class="gd-toasts" aria-live="polite">
		{#each ui.toasts as t (t.id)}
			<div class="gd-toast {t.tone}" transition:fade={{ duration: ui.ms(150) }}><span class="gd-dot" aria-hidden="true"></span><span>{t.text}</span></div>
		{/each}
	</div>
{/if}

<style>
	/* Full-window overlay: dashed inset frame, accent veil and a centred card. */
	.gd {
		position: fixed;
		inset: 0;
		z-index: 90;
		display: grid;
		place-items: center;
		background: color-mix(in srgb, var(--mg-accent-base, var(--mg-accent, #0f766e)) 10%, color-mix(in srgb, var(--mg-bg, #fff) 55%, transparent));
		backdrop-filter: blur(3px);
		pointer-events: none;
	}
	.gd::before {
		content: '';
		position: absolute;
		inset: 14px;
		border: 2px dashed color-mix(in srgb, var(--mg-accent-base, var(--mg-accent, #0f766e)) 70%, transparent);
		border-radius: calc(var(--mg-r, 8px) + 12px);
	}
	.gd-card {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		min-width: 300px;
		padding: 28px 40px 26px;
		border: 1px solid var(--mg-border, #e2e4e8);
		border-radius: calc(var(--mg-r, 8px) + 8px);
		background: var(--mg-surface, #fff);
		box-shadow: var(--cr-pop-shadow, var(--mg-shadow-lg, 0 8px 24px rgba(16, 24, 40, 0.14)));
		color: var(--mg-text, #15181d);
		font-family: var(--mg-font, inherit);
		font-size: var(--cr-fs-body, var(--mg-fs, 15px));
		text-align: center;
		animation: gd-rise var(--mo-2, 200ms) var(--mo-ease, cubic-bezier(0.2, 0.7, 0.2, 1)) both;
	}
	.gd-icon {
		display: grid;
		place-items: center;
		width: 56px;
		height: 56px;
		margin-bottom: 6px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--mg-accent-base, var(--mg-accent, #0f766e)) 14%, var(--mg-surface, #fff));
		box-shadow: 0 0 0 0 color-mix(in srgb, var(--mg-accent-base, var(--mg-accent, #0f766e)) 30%, transparent);
		color: var(--mg-accent-base, var(--mg-accent, #0f766e));
	}
	.gd-card b {
		font-size: var(--cr-fs-section, var(--mg-fs-lg, 17px));
		font-weight: 700;
	}
	.gd-card span:not(.gd-icon) {
		font-size: var(--cr-fs-meta, var(--mg-fs-sm, 14px));
		color: var(--mg-text-2, #454c57);
	}
	@keyframes gd-rise {
		from {
			opacity: 0;
			transform: translateY(8px) scale(0.98);
		}
	}
	:global([data-motion='off']) :is(.gd-card, .gd-icon) {
		animation: none;
	}
	@media (prefers-reduced-motion: reduce) {
		.gd-card,
		.gd-icon {
			animation: none;
		}
	}
	.gd-toasts {
		position: fixed;
		right: 16px;
		bottom: 16px;
		z-index: 91;
		display: flex;
		flex-direction: column;
		gap: 8px;
		max-width: min(440px, calc(100vw - 32px));
	}
	.gd-toast {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 10px 16px 10px 14px;
		border: 1px solid var(--mg-border, #e2e4e8);
		border-radius: calc(var(--mg-r, 8px) + 4px);
		background: var(--mg-surface, #fff);
		box-shadow: var(--mg-shadow-lg, 0 8px 24px rgba(16, 24, 40, 0.14));
		color: var(--mg-text, #15181d);
		font-family: var(--mg-font, inherit);
		font-size: var(--mg-fs-sm, 14px);
		overflow-wrap: anywhere;
	}
	.gd-dot {
		flex: none;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--mg-accent-base, var(--mg-accent, #0f766e));
	}
	.gd-toast.ok .gd-dot {
		background: var(--mg-ok, #15803d);
	}
	.gd-toast.error {
		border-color: color-mix(in srgb, var(--mg-danger, #b42318) 40%, var(--mg-border, #e2e4e8));
	}
	.gd-toast.error .gd-dot {
		background: var(--mg-danger, #b42318);
	}
</style>
