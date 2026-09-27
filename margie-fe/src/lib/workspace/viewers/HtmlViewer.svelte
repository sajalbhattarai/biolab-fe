<script lang="ts">
	import './tools.css';
	import { Download, ExternalLink, Maximize, Minimize, MousePointerClick } from 'lucide-svelte';
	import { viewable } from './viewable.svelte';

	/**
	 * Frames an HTML result (the genome viewer) to fill its space or the display. `hash` is appended
	 * to the address (e.g. #show=highest) so changes reach the page without a reload.
	 */
	/** `onfull`: the parent page goes full screen instead (Results, with its chat); `full` reports it. */
	let {
		src,
		title,
		hash = '',
		download = '',
		onfull,
		full: outerFull = false
	}: { src: string; title: string; hash?: string; download?: string; onfull?: () => void; full?: boolean } = $props();
	const tail = $derived(hash ? `#${hash}` : '');
	/** Framed: the fitted page (see the download route); standalone: the original. */
	const framed = $derived(`${src}${src.includes('?') ? '&' : '?'}embed=1`);
	const shown = viewable(() => framed);
	/** Signed-in fetched copies open as themselves; plain URLs open without the frame's adjustments. */
	const own = $derived((shown.url.startsWith('blob:') ? shown.url : src) + tail);

	let frame = $state<HTMLIFrameElement>();
	/** Keeps the bar in full screen so exiting is one click. */
	let box = $state<HTMLDivElement>();
	let full = $state(false);

	async function fullscreen() {
		if (onfull) return onfull();
		if (full) {
			await document.exitFullscreen().catch(() => {});
			return;
		}
		try {
			await box?.requestFullscreen();
		} catch {
			window.open(own, '_blank', 'noopener');
		}
	}
</script>

<svelte:document onfullscreenchange={() => (full = document.fullscreenElement === box)} />

<div class="html vw-scope" class:full bind:this={box}>
	<div class="vw-bar">
		<div class="vw-group" role="group" aria-label="Page">
			<!-- The parent's full screen has its own exit. -->
			{#if !outerFull}
				<button type="button" class="vw-btn" class:exit={full} onclick={fullscreen}>
					{#if full}<Minimize size={14} />Exit full screen | Esc{:else}<Maximize size={14} />Full screen{/if}
				</button>
			{/if}
			<a class="vw-btn" href={own} target="_blank" rel="noopener"><ExternalLink size={14} />New tab</a>
			{#if download}<a class="vw-btn" href={download} download><Download size={14} />Download (interactive HTML)</a>{/if}
		</div>
		<span class="vw-grow"></span>
		<span class="vw-num hint"><MousePointerClick size={14} />{full || outerFull ? 'Press Esc to leave full screen' : 'Hover or click the map for details'}</span>
	</div>
	{#if shown.error}
		<p class="vw-pane vw-msg">{shown.error}</p>
	{:else}
		<!-- Sandboxed like the local server's CSP: the page's scripts and downloads, not this app's sign-in or storage. -->
		<iframe
			class="vw-pane"
			bind:this={frame}
			src={shown.url ? shown.url + tail : 'about:blank'}
			{title}
			allow="fullscreen"
			sandbox="allow-scripts allow-downloads allow-popups allow-popups-to-escape-sandbox allow-modals"
		></iframe>
	{/if}
</div>

<style>
	.html {
		display: flex;
		flex-direction: column;
		gap: 12px;
		height: 100%;
		min-height: 0;
		font-size: var(--mg-fs-sm);
	}
	.hint {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--mg-text-3);
	}
	.vw-msg {
		flex-grow: 1;
	}
	iframe {
		flex-grow: 1;
		width: 100%;
		min-height: 480px;
		background: #fff;
	}
	/* Full screen: bar on top, page filling the rest. */
	.html.full {
		gap: 0;
		padding: 0;
		background: var(--mg-surface, #fff);
	}
	.html.full .vw-bar {
		padding: 8px 12px;
		border-bottom: 1px solid var(--mg-border);
	}
	.html.full iframe {
		min-height: 0;
		border: none;
		border-radius: 0;
	}
	.exit {
		border-color: var(--mg-accent) !important;
		color: var(--mg-accent-ink, var(--mg-accent)) !important;
	}
</style>
