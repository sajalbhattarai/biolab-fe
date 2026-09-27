<script lang="ts">
	/**
	 * Layout for the Modern (crisp) interface: restores preferences, tracks system
	 * theme and motion, and starts workspace polling.
	 */
	import '@fontsource/ibm-plex-sans/400.css';
	import '@fontsource/ibm-plex-sans/500.css';
	import '@fontsource/ibm-plex-sans/600.css';
	import '@fontsource/ibm-plex-sans/700.css';
	import '@fontsource/ibm-plex-mono/400.css';
	import '@fontsource/ibm-plex-mono/500.css';
	import '$lib/workspace/workspace.css';
	import '$lib/workspace/motion/motion.css';
	import '$lib/crisp/crisp.css';
	import { onMount } from 'svelte';
	import CrispShell from '$lib/crisp/CrispShell.svelte';
	import { ws } from '$lib/workspace/data.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { catchDownloads } from '$lib/cluster/downloads';
	import { ui } from '$lib/workspace/ui.svelte';

	let { children } = $props();

	const dark = matchMedia('(prefers-color-scheme: dark)');
	const reduce = matchMedia('(prefers-reduced-motion: reduce)');
	ui.restore();
	ui.systemDark = dark.matches;
	ui.reducedMotion = reduce.matches;

	onMount(() => {
		const onDark = (e: MediaQueryListEvent) => (ui.systemDark = e.matches);
		const onReduce = (e: MediaQueryListEvent) => (ui.reducedMotion = e.matches);
		const save = () => ui.flush();
		dark.addEventListener('change', onDark);
		reduce.addEventListener('change', onReduce);
		addEventListener('pagehide', save);
		// In cluster mode, file links are intercepted and fetched with the sign-in.
		backend.refresh();
		const release = backend.cluster ? catchDownloads() : null;
		ws.loadAll();
		ws.startPolling();
		return () => {
			release?.();
			dark.removeEventListener('change', onDark);
			reduce.removeEventListener('change', onReduce);
			removeEventListener('pagehide', save);
			ws.stopPolling();
			ui.flush();
		};
	});
</script>

<svelte:head>
	<title>MARGIE</title>
	<meta name="color-scheme" content={ui.dark ? 'dark' : 'light'} />
</svelte:head>

<CrispShell>{@render children()}</CrispShell>
