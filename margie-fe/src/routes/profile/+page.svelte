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
	let savingCredentials = $state(false);
	let creatingConfig = $state(false);
	let testingPath = $state(false);
	let pathTestResult = $state<{writable: boolean; error?: string} | null>(null);
	let error = $state('');
	let success = $state('');
	let credentialsError = $state('');
	let credentialsSuccess = $state('');
	let connected = $state(false);
	let checking = $state(true);

	// Cluster credentials form
	let editClusterHost = $state('');
	let editClusterUsername = $state('');
	let editPrivateKey = $state('');
	let showPrivateKey = $state(false);

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

			// Populate credentials form with current values
			editClusterHost = user.cluster_host;
			editClusterUsername = user.cluster_username;

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

	async function testPathWritable(path: string) {
		testingPath = true;
		pathTestResult = null;

		try {
			const res = await fetch(`${API_URL}/v1/ssh/test-path-writable`, {
				method: 'POST',
				headers: authHeaders(),
				body: JSON.stringify({ path }),
			});

			if (res.status === 401) { clearToken(); goto('/login'); return; }
			if (res.ok) {
				pathTestResult = await res.json();
			} else {
				pathTestResult = { writable: false, error: 'Failed to test path' };
			}
		} catch (e) {
			pathTestResult = { writable: false, error: e instanceof Error ? e.message : 'Failed to test path' };
		} finally {
			testingPath = false;
		}
	}

	async function saveConfig() {
		saving = true;
		error = '';
		success = '';

		// If main_database exists, test it before saving
		if (config.main_database) {
			await testPathWritable(config.main_database);
			if (pathTestResult && !pathTestResult.writable) {
				error = `Cannot save: main_database path is not writable. ${pathTestResult.error || ''}`;
				saving = false;
				return;
			}
		}

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

	async function createDefaultConfig() {
		creatingConfig = true;
		error = '';
		success = '';

		try {
			const res = await fetch(`${API_URL}/v1/ssh/config/create-default`, {
				method: 'POST',
				headers: authHeaders(),
			});

			if (res.status === 401) {
				clearToken();
				goto('/login');
				return;
			}

			if (!res.ok) {
				const errData = await res.json().catch(() => ({}));
				throw new Error(errData.detail || 'Failed to create default config');
			}

			success = 'Default configuration created successfully!';

			// Reload config to display it
			await loadConfig();

			setTimeout(() => success = '', 3000);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to create default config';
		} finally {
			creatingConfig = false;
		}
	}

	async function updateCredentials() {
		savingCredentials = true;
		credentialsError = '';
		credentialsSuccess = '';

		// Build the payload - only send fields that have values
		const payload: Record<string, string> = {};

		// Only send changed or non-empty values
		if (editClusterHost && editClusterHost !== user?.cluster_host) {
			payload.cluster_host = editClusterHost;
		}
		if (editClusterUsername && editClusterUsername !== user?.cluster_username) {
			payload.cluster_username = editClusterUsername;
		}
		if (editPrivateKey.trim()) {
			payload.private_key = editPrivateKey;
		}

		if (Object.keys(payload).length === 0) {
			credentialsError = 'No changes to save. Update at least one field.';
			savingCredentials = false;
			return;
		}

		try {
			const res = await fetch(`${API_URL}/v1/auth/update-credentials`, {
				method: 'PUT',
				headers: authHeaders(),
				body: JSON.stringify(payload),
			});

			if (res.status === 401) {
				clearToken();
				goto('/login');
				return;
			}

			if (!res.ok) {
				const errData = await res.json().catch(() => ({}));
				throw new Error(errData.detail || 'Failed to update credentials');
			}

			credentialsSuccess = 'Cluster credentials updated successfully! The connection will be retested.';

			// Clear the private key input after successful update
			editPrivateKey = '';

			// Reload user and recheck connection
			await loadUser();

			setTimeout(() => credentialsSuccess = '', 5000);
		} catch (e) {
			credentialsError = e instanceof Error ? e.message : 'Failed to update credentials';
		} finally {
			savingCredentials = false;
		}
	}
</script>

<div class="container mx-auto p-8 max-w-4xl space-y-8">
	<section class="text-center py-8">
		<h1 class="text-4xl font-bold text-primary-500 mb-4">Profile Settings</h1>
		<p class="text-lg text-surface-600 dark:text-surface-300">
			{#if user}
				Configuration for <code class="font-mono text-sm bg-surface-200 dark:bg-surface-700 px-2 py-1 rounded">{user.cluster_username}@{user.cluster_host}</code>
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
			<h2 class="text-2xl font-bold mb-2 text-primary-500">CONFIG</h2>

			<!-- Important Note -->
			<div class="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4 mb-6">
				<div class="flex items-start gap-3">
					<span class="text-blue-600 dark:text-blue-400 text-xl font-bold">ℹ️</span>
					<div>
						<p class="text-sm text-blue-900 dark:text-blue-100 font-semibold mb-1">Database Configuration</p>
						<p class="text-sm text-blue-800 dark:text-blue-200">
							Make sure to set a <code class="font-mono bg-blue-100 dark:bg-blue-800 px-1 py-0.5 rounded">main_database</code> config key with the path to your database.
							If not set, the database defaults to <code class="font-mono bg-blue-100 dark:bg-blue-800 px-1 py-0.5 rounded">~/.local/share/bioinformatics-tools/my-db.db</code>
						</p>
					</div>
				</div>
			</div>

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
						<!-- Special handling for main_database -->
						{#if section === 'main_database'}
							<div class="bg-amber-50 dark:bg-amber-900/20 border-2 border-amber-300 dark:border-amber-700 rounded-lg p-5">
								<div class="flex items-start gap-3 mb-3">
									<span class="text-amber-600 dark:text-amber-400 text-xl font-bold">⚠️</span>
									<div class="flex-1">
										<h3 class="text-lg font-semibold font-mono text-amber-900 dark:text-amber-100 mb-1">{section}</h3>
										<p class="text-sm text-amber-800 dark:text-amber-200">
											This path must be writable by your user. The database file will be created here if it doesn't exist.
										</p>
									</div>
								</div>

								<div class="space-y-3">
									<input
										type="text"
										value={String(value ?? '')}
										oninput={(e) => { config[section] = e.currentTarget.value; pathTestResult = null; }}
										class="input w-full px-4 py-2 rounded bg-white dark:bg-amber-900/40 border-2 border-amber-300 dark:border-amber-600 font-mono text-sm"
										placeholder="~/.local/share/bioinformatics-tools/my-db.db"
									/>

									<div class="flex items-center gap-3">
										<button
											type="button"
											onclick={() => testPathWritable(config[section])}
											disabled={testingPath || !config[section]}
											class="btn variant-filled-secondary px-4 py-2 text-sm"
										>
											{testingPath ? 'Testing...' : 'Test Writability'}
										</button>

										{#if pathTestResult}
											{#if pathTestResult.writable}
												<div class="flex items-center gap-2 text-green-700 dark:text-green-400">
													<span class="inline-block w-2 h-2 rounded-full bg-green-500"></span>
													<span class="text-sm font-semibold">Path is writable ✓</span>
												</div>
											{:else}
												<div class="flex items-center gap-2 text-red-700 dark:text-red-400">
													<span class="inline-block w-2 h-2 rounded-full bg-red-500"></span>
													<span class="text-sm font-semibold">Path is not writable ✗</span>
												</div>
											{/if}
										{/if}
									</div>

									{#if pathTestResult && !pathTestResult.writable && pathTestResult.error}
										<div class="text-xs text-red-700 dark:text-red-400 bg-red-100 dark:bg-red-900/30 rounded p-2 font-mono">
											{pathTestResult.error}
										</div>
									{/if}
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
		<section class="card p-6 bg-surface-100 dark:bg-surface-800 text-center space-y-4">
			<p class="text-surface-600 dark:text-surface-300 text-lg">No configuration found</p>
			<p class="text-surface-500 text-sm">
				The file <code class="font-mono text-sm bg-surface-200 dark:bg-surface-700 px-2 py-1 rounded">~/.config/bioinformatics-tools/config.yaml</code> does not exist on {user?.cluster_host}.
			</p>
			<div class="pt-4">
				<button
					type="button"
					onclick={createDefaultConfig}
					disabled={creatingConfig}
					class="btn variant-filled-primary px-8 py-3"
				>
					{creatingConfig ? 'Creating...' : 'Create Default Configuration'}
				</button>
			</div>
			<div class="pt-2 px-8">
				<details class="text-left">
					<summary class="cursor-pointer text-sm text-primary-500 hover:text-primary-700 font-semibold">What will be created?</summary>
					<div class="mt-3 text-xs text-surface-600 dark:text-surface-400 bg-surface-200 dark:bg-surface-700 rounded p-3 font-mono">
						<pre>main_database: ~/.local/share/bioinformatics-tools/my-db.db
compute:
  cluster-default:
    accounts: []
    max_cpus: 0
    queues: none</pre>
					</div>
				</details>
			</div>
		</section>
	{/if}

	<!-- Cluster Credentials Section -->
	<section class="card p-6 bg-surface-100 dark:bg-surface-800">
		<h2 class="text-2xl font-bold mb-2 text-primary-500">Cluster Credentials</h2>
		<p class="text-sm text-surface-500 mb-6">
			Update your HPC cluster connection details. Changes will be validated before saving.
		</p>

		{#if credentialsError}
			<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">{credentialsError}</div>
		{/if}

		{#if credentialsSuccess}
			<div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-4">{credentialsSuccess}</div>
		{/if}

		<div class="space-y-4">
			<!-- Cluster Host -->
			<div>
				<label for="cluster-host" class="block text-sm font-semibold mb-2">Cluster Host</label>
				<input
					id="cluster-host"
					type="text"
					bind:value={editClusterHost}
					placeholder="e.g., negishi.rcac.purdue.edu"
					disabled={savingCredentials}
					class="input w-full px-4 py-2 rounded-lg bg-white dark:bg-surface-700 border border-surface-300 dark:border-surface-600 font-mono text-sm"
				/>
			</div>

			<!-- Cluster Username -->
			<div>
				<label for="cluster-username" class="block text-sm font-semibold mb-2">Cluster Username</label>
				<input
					id="cluster-username"
					type="text"
					bind:value={editClusterUsername}
					placeholder="e.g., your-hpc-username"
					disabled={savingCredentials}
					class="input w-full px-4 py-2 rounded-lg bg-white dark:bg-surface-700 border border-surface-300 dark:border-surface-600 font-mono text-sm"
				/>
			</div>

			<!-- Private Key -->
			<div>
				<div class="flex items-center justify-between mb-2">
					<label for="private-key" class="block text-sm font-semibold">SSH Private Key</label>
					<button
						type="button"
						onclick={() => showPrivateKey = !showPrivateKey}
						class="text-xs text-primary-500 hover:text-primary-700 font-semibold"
					>
						{showPrivateKey ? 'Hide' : 'Show'}
					</button>
				</div>
				<textarea
					id="private-key"
					bind:value={editPrivateKey}
					placeholder="Leave blank to keep current key, or paste new key here..."
					disabled={savingCredentials}
					rows="8"
					class="input w-full px-4 py-2 rounded-lg bg-white dark:bg-surface-700 border border-surface-300 dark:border-surface-600 font-mono text-xs resize-y"
					style={showPrivateKey ? '' : '-webkit-text-security: disc; text-security: disc;'}
				></textarea>
				<p class="text-xs text-surface-400 mt-1">
					Leave blank to keep your current private key. Only paste a new key if you need to update it.
				</p>
			</div>

			<!-- Save Button -->
			<div class="flex justify-center pt-4">
				<button
					type="button"
					onclick={updateCredentials}
					disabled={savingCredentials}
					class="btn variant-filled-secondary btn-lg px-8 py-2"
				>
					{savingCredentials ? 'Updating...' : 'Update Credentials'}
				</button>
			</div>
		</div>
	</section>
</div>
