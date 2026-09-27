<script lang="ts">
	import './layout.css';
	import { onMount } from 'svelte';
	import { afterNavigate, goto } from '$app/navigation';
	import { page } from '$app/state';
	import favicon from '$lib/assets/favicon.svg';
	import LegacyShell from '$lib/crisp/LegacyShell.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { isLoggedIn } from '$lib/auth.js';
	import { useClusterBackend } from '$lib/config';
	import { ui } from '$lib/workspace/ui.svelte';

	let { children } = $props();

	/** The platform's older pages, in MARGIE's menu under its own. */
	const TOOLS = [
		{ href: '/analyze', label: 'Analyze (platform)' },
		{ href: '/filesearch', label: 'File search' },
		{ href: '/run_ssh', label: 'Run over SSH' },
		{ href: '/results/historical', label: 'Historical results' },
		{ href: '/methods', label: 'Methods' },
		{ href: '/contributors', label: 'Contributors' }
	];
	const signingIn = $derived(['/login', '/register'].some((p) => page.url.pathname.startsWith(p)));
	// Rechecked on every navigation (including the one after signing in).
	let loggedIn = $state(false);
	afterNavigate(() => {
		loggedIn = isLoggedIn();
		backend.refresh();
	});

	// /crisp (Modern) runs the pipeline locally with no account; /app and /atlas
	// redirect there. /start chooses where MARGIE runs and begins HPC sign-in.
	const PUBLIC_PATHS = ['/login', '/register', '/start', '/crisp', '/app', '/atlas'];
	/** Pages that bring their own chrome: this shell would be a second one. */
	const OWN_SHELL = ['/start', '/crisp'];
	const bare = $derived(OWN_SHELL.some((p) => page.url.pathname.startsWith(p)));
	/** True while / redirects to this browser's chosen interface. */
	let leaving = $state(false);

	onMount(() => {
		// Clears stored settings that pointed at a local backend (now /crisp).
		useClusterBackend();
		const path = window.location.pathname;
		if (!PUBLIC_PATHS.some(p => path.startsWith(p)) && !isLoggedIn()) {
			goto('/login');
			return;
		}
		// The front page redirects to the interface chosen in Customize (Modern by default).
		if (path === '/') {
			ui.restore();
			const home = ui.home();
			if (home !== '/') {
				leaving = true;
				goto(home, { replaceState: true });
			}
		}
	});
</script>

<svelte:head><link rel="icon" href={favicon} /></svelte:head>
{#if leaving && page.url.pathname === '/'}
	<!-- nothing: the chosen interface is opening -->
{:else if bare}
	{@render children()}
{:else}
	<LegacyShell tools={TOOLS} account={loggedIn} accountLinks={[{ href: '/profile', label: 'Profile' }]} drop={!signingIn}>
		{#snippet after()}
			{#if !loggedIn}<a href="/login" class="mg-btn small primary">Sign in</a>{/if}
		{/snippet}
		{@render children()}
	</LegacyShell>
{/if}
