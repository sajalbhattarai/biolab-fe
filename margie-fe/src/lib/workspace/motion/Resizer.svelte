<script lang="ts">
	import { ui } from '../ui.svelte';

	/**
	 * Drag handle on a side pane's edge (the pane needs position: relative and `ui.size(id, fallback)`).
	 * Supports dragging, arrow keys (Shift for bigger steps) and double-click to reset.
	 */
	let {
		id,
		fallback,
		min = 160,
		max = 560,
		edge = 'right',
		label
	}: { id: string; fallback: number; min?: number; max?: number; edge?: 'left' | 'right'; label: string } = $props();

	const width = $derived(ui.size(id, fallback));
	let dragging = $state(false);

	const clamp = (v: number) => Math.round(Math.max(min, Math.min(max, innerWidth * 0.75, v)));

	function down(e: PointerEvent) {
		if (e.button !== 0) return;
		e.preventDefault();
		const handle = e.currentTarget as HTMLElement;
		handle.setPointerCapture(e.pointerId);
		const x0 = e.clientX;
		const w0 = width;
		let next = w0;
		let frame = 0;
		dragging = true;
		document.documentElement.classList.add('mo-resizing');
		const move = (ev: PointerEvent) => {
			next = clamp(w0 + (edge === 'right' ? ev.clientX - x0 : x0 - ev.clientX));
			frame ||= requestAnimationFrame(() => {
				frame = 0;
				ui.setSize(id, next);
			});
		};
		const up = () => {
			cancelAnimationFrame(frame);
			ui.setSize(id, next);
			dragging = false;
			document.documentElement.classList.remove('mo-resizing');
			handle.removeEventListener('pointermove', move);
			handle.removeEventListener('pointerup', up);
			handle.removeEventListener('pointercancel', up);
		};
		handle.addEventListener('pointermove', move);
		handle.addEventListener('pointerup', up);
		handle.addEventListener('pointercancel', up);
	}

	function key(e: KeyboardEvent) {
		const step = (e.shiftKey ? 64 : 16) * (edge === 'right' ? 1 : -1);
		const to =
			e.key === 'ArrowRight' ? width + step : e.key === 'ArrowLeft' ? width - step : e.key === 'Home' ? min : e.key === 'End' ? max : null;
		if (to === null) return;
		e.preventDefault();
		ui.setSize(id, clamp(to));
	}
</script>

<!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
<div
	class="mo-resizer {edge}"
	class:dragging
	role="separator"
	tabindex="0"
	aria-orientation="vertical"
	aria-label={label}
	aria-valuenow={width}
	aria-valuemin={min}
	aria-valuemax={max}
	title="Drag to resize. Double-click to reset."
	onpointerdown={down}
	onkeydown={key}
	ondblclick={() => ui.setSize(id, null)}
></div>

<style>
	.mo-resizer {
		position: absolute;
		top: 0;
		bottom: 0;
		z-index: 6;
		width: 12px;
		cursor: col-resize;
		touch-action: none;
	}
	.right {
		right: -6px;
	}
	.left {
		left: -6px;
	}
	.mo-resizer::after {
		content: '';
		position: absolute;
		top: 8px;
		bottom: 8px;
		left: 5px;
		width: 2px;
		border-radius: 2px;
		background: var(--at-teal, var(--mg-accent));
		opacity: 0;
		transform: scaleY(0.6);
		transition:
			opacity var(--mo-1) ease,
			transform var(--mo-2) var(--mo-ease);
	}
	.mo-resizer:hover::after,
	.mo-resizer:focus-visible::after,
	.dragging::after {
		opacity: 1;
		transform: none;
	}
	.mo-resizer:focus-visible {
		outline: none;
	}
</style>
