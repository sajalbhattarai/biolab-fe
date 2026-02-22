<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { authHeaders, clearToken } from '$lib/auth.js';

	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000'
		: '';

	let user = $state<{ username: string; cluster_username: string; cluster_host: string; home_dir: string } | null>(null);
	let config = $state<Record<string, any>>({});
	let loading = $state(false);
	let saving = $state(false);
	let error = $state('');
	let success = $state('');
	let connected = $state(false);
	let checking = $state(true);

	onMount(async () => {
		await loadUser();
	});

	async function loadUser() {
		try {
			const res = await fetch(`${API_URL}/v1/auth/me`, { headers: authHeaders() });
			if (res.status === 401) {
				clearToken();
				goto('/login');
				return;
			}
			if (!res.ok) throw new Error('Failed to load user profile');
			user = await res.json();
			await checkConnection();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load profile';
			checking = false;
		}
	}

	async function checkConnection() {
		checking = true;
		error = '';
		try {
			const res = await fetch(`${API_URL}/v1/ssh/status`, { headers: authHeaders() });
			if (res.status === 401) { clearToken(); goto('/login'); return; }
			if (!res.ok) throw new Error('Could not reach backend');
			const data = await res.json();
			connected = data.connected;
			if (connected) {
				await loadConfig();
			}
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to check SSH connection';
			connected = false;
		} finally {
			checking = false;
		}
	}

	async function loadConfig() {
		loading = true;
		error = '';
		try {
			const res = await fetch(`${API_URL}/v1/ssh/config`, { headers: authHeaders() });
			if (res.status === 401) { clearToken(); goto('/login'); return; }
			if (!res.ok) throw new Error('Failed to load config');
			config = await res.json();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load config';
		} finally {
			loading = false;
		}
	}

	async function saveConfig() {
		saving = true;
		error = '';
		success = '';
		try {
			const res = await fetch(`${API_URL}/v1/ssh/config`, {
				method: 'PUT',
				headers: authHeaders(),
				body: JSON.stringify(config),
			});
			if (res.status === 401) { clearToken(); goto('/login'); return; }
			if (!res.ok) throw new Error('Failed to save config');
			success = 'Configuration saved successfully.';
			setTimeout(() => success = '', 3000);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to save config';
		} finally {
			saving = false;
		}
	}

	function isObject(val: any): val is Record<string, any> {
		return val !== null && typeof val === 'object' && !Array.isArray(val);
	}

	function removeItem(arr: any[], index: number) {
		arr.splice(index, 1);
		config = { ...config };
	}

	function addItem(arr: any[]) {
		arr.push('');
		config = { ...config };
	}
</script>

<div class="container mx-auto p-8 max-w-4xl space-y-8">
	<section class="text-center py-8">
		<h1 class="text-4xl font-bold text-primary-500 mb-4">Profile Settings</h1>
		<p class="text-lg text-surface-600 dark:text-surface-300">
			{#if user}
				Configuration from <code class="font-mono text-sm bg-surface-200 dark:bg-surface-700 px-2 py-1 rounded">{user.cluster_username}@{user.cluster_host}</code>
			{:else}
				Loading profile...
			{/if}
		</p>
	</section>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">{error}</div>
	{/if}

	{#if success}
		<div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded">{success}</div>
	{/if}

	<!-- SSH Connection Status -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<h2 class="text-2xl font-bold mb-4 text-primary-500">SSH Connection</h2>
		{#if checking}
			<p class="text-surface-500">Checking connection...</p>
		{:else if connected}
			<div class="flex items-center gap-2">
				<span class="inline-block w-3 h-3 rounded-full bg-green-500"></span>
				<span class="text-green-700 dark:text-green-400 font-semibold">Connected to {user?.cluster_host}</span>
			</div>
		{:else}
			<div class="flex items-center gap-2">
				<span class="inline-block w-3 h-3 rounded-full bg-red-500"></span>
				<span class="text-red-700 dark:text-red-400 font-semibold">Could not connect to {user?.cluster_host}</span>
			</div>
			<p class="text-sm text-surface-500 mt-2">Check that your cluster is reachable and your SSH key is still valid.</p>
			<button type="button" onclick={checkConnection} class="btn variant-outline-primary mt-4 px-4 py-2 text-sm">
				Retry
			</button>
		{/if}
	</section>

	<!-- Config Section -->
	{#if loading}
		<section class="card p-6 bg-surface-100 dark:bg-surface-800 text-center">
			<p class="text-surface-500">Loading configuration...</p>
		</section>
	{:else if connected && Object.keys(config).length > 0}
		<section class="card p-6 bg-surface-100 dark:bg-surface-800">
			<h2 class="text-2xl font-bold mb-6 text-primary-500">CONFIG</h2>

			<div class="space-y-6">
				{#each Object.entries(config) as [section, value]}
					{#if isObject(value)}
						<div class="bg-surface-200 dark:bg-surface-700 rounded-lg p-4">
							<h3 class="text-xl font-semibold mb-4 text-secondary-500 border-b border-surface-300 dark:border-surface-600 pb-2">{section}</h3>
							<div class="space-y-3">
								{#each Object.entries(value) as [key, val]}
									{#if isObject(val)}
										<details class="group bg-surface-300 dark:bg-surface-600 rounded-lg">
											<summary class="cursor-pointer p-3 font-semibold flex justify-between items-center hover:bg-surface-400 dark:hover:bg-surface-500 rounded-lg transition-colors">
												<span>{key}</span>
												<span class="transform transition-transform group-open:rotate-180">▼</span>
											</summary>
											<div class="p-3 pt-0 space-y-2">
												{#each Object.entries(val) as [subKey, subVal]}
													<div class="grid grid-cols-1 md:grid-cols-2 gap-4 items-center">
														<label class="text-sm font-semibold font-mono">{subKey}</label>
														{#if Array.isArray(subVal)}
															<div class="flex flex-wrap gap-2 items-center">
																{#each subVal as item, i}
																	<span class="inline-flex items-center gap-1 bg-primary-200 dark:bg-primary-800 text-primary-800 dark:text-primary-200 px-2 py-1 rounded font-mono text-sm">
																		<input
																			type="text"
																			value={String(item)}
																			oninput={(e) => { config[section][key][subKey][i] = e.currentTarget.value; }}
																			class="bg-transparent border-none outline-none w-16 text-sm font-mono"
																		/>
																		<button type="button" onclick={() => removeItem(config[section][key][subKey], i)} class="text-primary-600 dark:text-primary-300 hover:text-red-500 font-bold">&times;</button>
																	</span>
																{/each}
																<button type="button" onclick={() => addItem(config[section][key][subKey])} class="text-primary-500 hover:text-primary-700 text-xl font-bold leading-none">+</button>
															</div>
														{:else}
															<input
																type="text"
																value={String(subVal ?? '')}
																oninput={(e) => { config[section][key][subKey] = e.currentTarget.value; }}
																class="input px-3 py-2 rounded bg-white dark:bg-surface-800 border border-surface-400 dark:border-surface-500 font-mono text-sm"
															/>
														{/if}
													</div>
												{/each}
											</div>
										</details>
									{:else if Array.isArray(val)}
										<div class="grid grid-cols-1 md:grid-cols-2 gap-4 items-center">
											<label class="text-sm font-semibold font-mono">{key}</label>
											<div class="flex flex-wrap gap-2 items-center">
												{#each val as item, i}
													<span class="inline-flex items-center gap-1 bg-primary-200 dark:bg-primary-800 text-primary-800 dark:text-primary-200 px-2 py-1 rounded font-mono text-sm">
														<input
															type="text"
															value={String(item)}
															oninput={(e) => { config[section][key][i] = e.currentTarget.value; }}
															class="bg-transparent border-none outline-none w-16 text-sm font-mono"
														/>
														<button type="button" onclick={() => removeItem(config[section][key], i)} class="text-primary-600 dark:text-primary-300 hover:text-red-500 font-bold">&times;</button>
													</span>
												{/each}
												<button type="button" onclick={() => addItem(config[section][key])} class="text-primary-500 hover:text-primary-700 text-xl font-bold leading-none">+</button>
											</div>
										</div>
									{:else}
										<div class="grid grid-cols-1 md:grid-cols-2 gap-4 items-center">
											<label class="text-sm font-semibold font-mono">{key}</label>
											<input
												type="text"
												value={String(val ?? '')}
												oninput={(e) => { config[section][key] = e.currentTarget.value; }}
												class="input px-3 py-2 rounded bg-white dark:bg-surface-800 border border-surface-400 dark:border-surface-500 font-mono text-sm"
											/>
										</div>
									{/if}
								{/each}
							</div>
						</div>
					{:else if Array.isArray(value)}
						<div class="grid grid-cols-1 md:grid-cols-2 gap-4 items-center">
							<label class="text-sm font-semibold font-mono">{section}</label>
							<div class="flex flex-wrap gap-2 items-center">
								{#each value as item, i}
									<span class="inline-flex items-center gap-1 bg-primary-200 dark:bg-primary-800 text-primary-800 dark:text-primary-200 px-2 py-1 rounded font-mono text-sm">
										<input
											type="text"
											value={String(item)}
											oninput={(e) => { config[section][i] = e.currentTarget.value; }}
											class="bg-transparent border-none outline-none w-16 text-sm font-mono"
										/>
										<button type="button" onclick={() => removeItem(config[section], i)} class="text-primary-600 dark:text-primary-300 hover:text-red-500 font-bold">&times;</button>
									</span>
								{/each}
								<button type="button" onclick={() => addItem(config[section])} class="text-primary-500 hover:text-primary-700 text-xl font-bold leading-none">+</button>
							</div>
						</div>
					{:else}
						<div class="grid grid-cols-1 md:grid-cols-2 gap-4 items-center">
							<label class="text-sm font-semibold font-mono">{section}</label>
							<input
								type="text"
								value={String(value ?? '')}
								oninput={(e) => { config[section] = e.currentTarget.value; }}
								class="input px-3 py-2 rounded bg-white dark:bg-surface-800 border border-surface-400 dark:border-surface-500 font-mono text-sm"
							/>
						</div>
					{/if}
				{/each}
			</div>

			<div class="flex justify-center mt-8">
				<button
					type="button"
					onclick={saveConfig}
					disabled={saving}
					class="btn variant-filled-primary btn-lg px-8 py-2"
				>
					{saving ? 'Saving...' : 'Save Configuration'}
				</button>
			</div>
		</section>
	{:else if connected}
		<section class="card p-6 bg-surface-100 dark:bg-surface-800 text-center">
			<p class="text-surface-500">No configuration found. Check that <code class="font-mono text-sm">~/.config/bioinformatics-tools/config.yaml</code> exists on {user?.cluster_host}.</p>
		</section>
	{/if}
</div>
