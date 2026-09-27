<script lang="ts">
	import './tools.css';
	import { Maximize2, Scan, ZoomIn, ZoomOut } from 'lucide-svelte';
	import { viewable } from './viewable.svelte';

	/** Image viewer: fitted, then zoomed toward the pointer (buttons, keys, Ctrl/⌘ + wheel, pinch) and dragged. */
	let { src, alt }: { src: string; alt: string } = $props();
	const shown = viewable(() => src);

	let box = $state<HTMLDivElement>();
	let natural = $state({ w: 0, h: 0 });
	let scale = $state(1);
	let x = $state(0);
	let y = $state(0);
	let fitted = $state(true);
	let loaded = $state(false);
	let failed = $state(false);
	let backdrop = $state<'white' | 'checker' | 'dark'>('white');
	let dragging = $state(false);

	const MIN = 0.02;
	const MAX = 16;

	/** Fits the whole image, centred. */
	function fit() {
		if (!box || !natural.w) return;
		const r = box.getBoundingClientRect();
		scale = Math.min(1, (r.width - 32) / natural.w, (r.height - 32) / natural.h);
		x = (r.width - natural.w * scale) / 2;
		y = (r.height - natural.h * scale) / 2;
		fitted = true;
	}

	/** Zooms by `factor`, keeping point (px, py) fixed. */
	function zoom(factor: number, px?: number, py?: number) {
		if (!box) return;
		const r = box.getBoundingClientRect();
		const cx = px ?? r.width / 2;
		const cy = py ?? r.height / 2;
		const next = Math.min(MAX, Math.max(MIN, scale * factor));
		x = cx - ((cx - x) * next) / scale;
		y = cy - ((cy - y) * next) / scale;
		scale = next;
		fitted = false;
	}

	function actual() {
		if (!box) return;
		const r = box.getBoundingClientRect();
		zoom(1 / scale, r.width / 2, r.height / 2);
	}

	function onload(e: Event) {
		const img = e.currentTarget as HTMLImageElement;
		natural = { w: img.naturalWidth, h: img.naturalHeight };
		loaded = true;
		fit();
	}

	function wheel(e: WheelEvent) {
		if (!box) return;
		e.preventDefault();
		const r = box.getBoundingClientRect();
		if (e.ctrlKey || e.metaKey) {
			zoom(Math.exp(-e.deltaY * 0.0022), e.clientX - r.left, e.clientY - r.top);
		} else {
			x -= e.deltaX;
			y -= e.deltaY;
			fitted = false;
		}
	}

	function down(e: PointerEvent) {
		if (e.button !== 0) return;
		dragging = true;
		const x0 = e.clientX - x;
		const y0 = e.clientY - y;
		(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
		const move = (ev: PointerEvent) => {
			x = ev.clientX - x0;
			y = ev.clientY - y0;
			fitted = false;
		};
		const up = () => {
			dragging = false;
			window.removeEventListener('pointermove', move);
		};
		window.addEventListener('pointermove', move);
		window.addEventListener('pointerup', up, { once: true });
	}

	function key(e: KeyboardEvent) {
		if ((e.target as HTMLElement)?.closest('input, select, textarea')) return;
		if (e.key === '+' || e.key === '=') zoom(1.25);
		else if (e.key === '-') zoom(0.8);
		else if (e.key === '0') fit();
		else if (e.key === '1') actual();
	}

	// Keeps a fitted image fitted on resize.
	$effect(() => {
		if (!box) return;
		const ro = new ResizeObserver(() => fitted && fit());
		ro.observe(box);
		return () => ro.disconnect();
	});
</script>

<svelte:window onkeydown={key} />

<div class="viewer vw-scope">
	<div class="vw-bar">
		<div class="vw-group" role="group" aria-label="Size">
			<button type="button" class="vw-btn" title="Fit to the window (0)" aria-pressed={fitted} onclick={fit}><Scan size={14} /><span class="vw-lbl">Fit</span></button>
			<button type="button" class="vw-btn" title="Actual size (1)" onclick={actual}><Maximize2 size={14} /><span class="vw-lbl">Actual size</span></button>
		</div>
		<div class="vw-group" role="group" aria-label="Zoom">
			<button type="button" class="vw-btn icon" aria-label="Zoom out" title="Zoom out (−)" onclick={() => zoom(0.8)}><ZoomOut size={15} /></button>
			<span class="vw-num pct">{Math.round(scale * 100)}%</span>
			<button type="button" class="vw-btn icon" aria-label="Zoom in" title="Zoom in (+)" onclick={() => zoom(1.25)}><ZoomIn size={15} /></button>
		</div>
		<span class="vw-grow"></span>
		{#if loaded}<span class="vw-num">{natural.w.toLocaleString('en-US')} × {natural.h.toLocaleString('en-US')} px</span>{/if}
		<div class="vw-group" role="radiogroup" aria-label="Background">
			{#each [['white', 'White'], ['checker', 'Checks'], ['dark', 'Dark']] as [v, l] (v)}
				<button type="button" role="radio" class="vw-btn" class:on={backdrop === v} aria-checked={backdrop === v} onclick={() => (backdrop = v as typeof backdrop)}>
					<span class="swatch {v}" aria-hidden="true"></span>{l}
				</button>
			{/each}
		</div>
	</div>
	<div
		class="stage vw-pane {backdrop}"
		class:dragging
		bind:this={box}
		role="img"
		aria-label={alt}
		onwheel={wheel}
		onpointerdown={down}
		ondblclick={() => (fitted ? actual() : fit())}
	>
		{#if failed || shown.error}
			<p class="msg">{shown.error || 'This image could not be shown.'}</p>
		{:else if shown.url}
			<img
				src={shown.url}
				{alt}
				draggable="false"
				decoding="async"
				style="transform: translate({x}px, {y}px) scale({scale}); opacity: {loaded ? 1 : 0}"
				{onload}
				onerror={() => (failed = true)}
			/>
			{#if !loaded}<p class="msg">Loading</p>{/if}
		{:else}
			<p class="msg">Loading</p>
		{/if}
	</div>
	<p class="hint">Drag to move | Ctrl or ⌘ + scroll to zoom | double-click to switch between fit and actual size</p>
</div>

<style>
	.viewer {
		display: flex;
		flex-direction: column;
		gap: 12px;
		height: 100%;
		min-height: 0;
		font-size: var(--mg-fs-sm);
	}
	.pct {
		min-width: 48px;
		text-align: center;
	}
	.swatch {
		width: 12px;
		height: 12px;
		border-radius: 50%;
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--mg-text) 30%, transparent);
	}
	.swatch.white {
		background: #fff;
	}
	.swatch.dark {
		background: #1a1a18;
	}
	.swatch.checker {
		background: conic-gradient(#d9d6cf 25%, #fff 0 50%, #d9d6cf 0 75%, #fff 0) 0 0 / 6px 6px;
	}
	.stage {
		position: relative;
		flex-grow: 1;
		min-height: 320px;
		cursor: grab;
		touch-action: none;
	}
	.stage.dragging {
		cursor: grabbing;
	}
	.stage.white {
		background: #fff;
	}
	.stage.dark {
		background: #1a1a18;
	}
	.stage.checker {
		background-color: #fff;
		background-image: linear-gradient(45deg, #e6e3dd 25%, transparent 25%), linear-gradient(-45deg, #e6e3dd 25%, transparent 25%),
			linear-gradient(45deg, transparent 75%, #e6e3dd 75%), linear-gradient(-45deg, transparent 75%, #e6e3dd 75%);
		background-size: 16px 16px;
		background-position:
			0 0,
			0 8px,
			8px -8px,
			-8px 0;
	}
	img {
		position: absolute;
		top: 0;
		left: 0;
		max-width: none;
		transform-origin: 0 0;
		user-select: none;
		image-rendering: auto;
	}
	.msg {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		color: #777;
	}
	.hint {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
		text-align: center;
	}
</style>
