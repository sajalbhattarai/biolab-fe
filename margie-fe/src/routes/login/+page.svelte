<script lang="ts">
	import { goto } from '$app/navigation';
	import { setToken } from '$lib/auth.js';

	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000'
		: '';

	let username = $state('');
	let password = $state('');
	let loading = $state(false);
	let error = $state('');

	async function handleLogin(e: Event) {
		e.preventDefault();
		loading = true;
		error = '';

		try {
			const res = await fetch(`${API_URL}/v1/auth/login`, {
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
			goto('/');
		} catch (e) {
			error = e instanceof Error ? e.message : 'Login failed. Please try again.';
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
</div>
