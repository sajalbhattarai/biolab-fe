<script lang="ts">
	import { Laptop } from 'lucide-svelte';
	import { clearToken, setToken } from '$lib/auth.js';
	import { getApiUrl } from '$lib/config';
	import { ui } from '$lib/workspace/ui.svelte';

	let username = $state('');
	let password = $state('');
	let loading = $state(false);
	let error = $state('');

	/**
	 * Opens the local interface, which needs no account; signing in is for the cluster.
	 * A full page load, so the interface restarts for the new place.
	 */
	function runLocally() {
		clearToken();
		window.location.assign('/crisp/home');
	}

	async function handleLogin(e: Event) {
		e.preventDefault();
		loading = true;
		error = '';

		const apiUrl = getApiUrl();
		try {
			const res = await fetch(`${apiUrl}/v1/auth/login`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ username, password }),
			});

			if (res.status === 401) {
				error = 'Invalid username or password.';
				return;
			}
			if (!res.ok) throw new Error('Login failed. Please try again.');

			const data = await res.json();
			setToken(data.access_token);
			// The interface this browser opens with: Crisp, unless another was picked.
			ui.restore();
			window.location.assign(ui.home());
		} catch (e) {
			if (e instanceof TypeError) {
				error =
					`Can't reach the backend at ${apiUrl || window.location.origin}. ` +
					'Connect to your HPC on the start page first (link below), or run MARGIE on this computer.';
			} else {
				error = e instanceof Error ? e.message : 'Login failed. Please try again.';
			}
		} finally {
			loading = false;
		}
	}
</script>

<div class="container mx-auto p-8 max-w-md">
	<section class="text-center py-8">
		<h1 class="text-4xl font-bold text-primary-500 mb-2">Sign In</h1>
		<p class="text-surface-600 dark:text-surface-300">Bioinformatics Supercomputing Platform</p>
	</section>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">{error}</div>
	{/if}

	<div class="card p-8 bg-surface-100 dark:bg-surface-800">
		<form onsubmit={handleLogin} class="space-y-5">
			<div>
				<label for="username" class="block text-sm font-semibold mb-1">Username</label>
				<input
					id="username"
					type="text"
					bind:value={username}
					required
					autocomplete="username"
					disabled={loading}
					class="input w-full px-4 py-2 rounded-lg bg-surface-200 dark:bg-surface-700 border border-surface-300 dark:border-surface-600"
				/>
			</div>
			<div>
				<label for="password" class="block text-sm font-semibold mb-1">Password</label>
				<input
					id="password"
					type="password"
					bind:value={password}
					required
					autocomplete="current-password"
					disabled={loading}
					class="input w-full px-4 py-2 rounded-lg bg-surface-200 dark:bg-surface-700 border border-surface-300 dark:border-surface-600"
				/>
			</div>
			<button
				type="submit"
				disabled={loading}
				class="btn variant-filled-primary w-full py-3"
			>
				{loading ? 'Signing in...' : 'Sign In'}
			</button>
		</form>
	</div>

	<p class="text-center text-sm text-surface-500 mt-6">
		No account? <a href="/register" class="text-primary-500 hover:underline">Register</a>
	</p>

	<div class="mt-8">
		<div class="flex items-center gap-3 text-xs uppercase tracking-wide text-surface-500">
			<span class="flex-1 border-t border-surface-300 dark:border-surface-600"></span>
			or
			<span class="flex-1 border-t border-surface-300 dark:border-surface-600"></span>
		</div>

		<button
			type="button"
			class="mt-4 w-full py-3 rounded-lg border border-primary-500 text-primary-500 font-semibold hover:bg-primary-500/10 flex items-center justify-center gap-2"
			onclick={runLocally}
		>
			<Laptop size={18} />
			Run MARGIE on this computer
		</button>
		<p class="mt-2 text-center text-xs text-surface-500">
			Uses this computer's own cores, memory and disk. No account, no cluster.
		</p>
	</div>

	<p class="text-center text-sm text-surface-500 mt-8">
		Not connected to your HPC yet, or setting MARGIE up for the first time?
		<a href="/start" class="text-primary-500 hover:underline">Choose where MARGIE runs</a>
	</p>
</div>
