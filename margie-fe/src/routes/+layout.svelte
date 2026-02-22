<script lang="ts">
	import './layout.css';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import favicon from '$lib/assets/favicon.svg';
	import Navibar from '$lib/Navibar.svelte';
	import { isLoggedIn } from '$lib/auth.js';

	let { children } = $props();

	const PUBLIC_PATHS = ['/login', '/register'];

	onMount(() => {
		const path = window.location.pathname;
		if (!PUBLIC_PATHS.some(p => path.startsWith(p)) && !isLoggedIn()) {
			goto('/login');
		}
	});
</script>

<svelte:head><link rel="icon" href={favicon} /></svelte:head>
<Navibar />
{@render children()}
