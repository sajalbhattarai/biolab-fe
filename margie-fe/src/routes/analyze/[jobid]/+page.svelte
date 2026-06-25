<script lang="ts">
	import { page } from '$app/stores';

	// Use relative URL so it works in both dev and production
	const API_URL = typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000' // Dev: connect to local backend
		: ''; // Production: use relative URL (same domain)

	// Get job ID from the URL parameter
	const jobId = $derived($page.params.jobid);

	let jobState = $state('');
	let elapsedTime = $state('');
	let message = $state('');
	let loading = $state(true);
	let error = $state('');
	let isDone = $state(false);

	async function fetchJobStatus(signal: AbortSignal) {
		try {
			loading = true;
			error = '';

			const response = await fetch(`${API_URL}/v1/ssh/job_status/${jobId}/stream`, {
				signal
			});

			if (!response.ok) throw new Error('Failed to fetch job status');

			const reader = response.body?.getReader();
			const decoder = new TextDecoder();

			if (!reader) throw new Error('No response body');

			let buffer = '';

			// Read the stream
			while (true) {
				const { done, value } = await reader.read();
				if (done) break;

				const chunk = decoder.decode(value, { stream: true });
				console.log('Received chunk:', chunk);
				buffer += chunk;

				// Process complete SSE messages (they end with \n\n)
				const messages = buffer.split('\n\n');
				buffer = messages.pop() || ''; // Keep incomplete message in buffer

				console.log('Split messages:', messages);
				console.log('Remaining buffer:', buffer);

				for (const msg of messages) {
					// Skip empty messages
					if (!msg.trim()) continue;

					console.log('Processing message:', msg);
					if (msg.startsWith('data: ')) {
						const jsonStr = msg.substring(6); // Remove 'data: ' prefix
						console.log('JSON string:', jsonStr);
						try {
							const data = JSON.parse(jsonStr);
							console.log('Parsed data:', data);

							// Update state with the parsed data
							if (data.state) jobState = data.state;
							if (data.elapsed) elapsedTime = data.elapsed;
							if (data.message) message = data.message;
							if (data.error) error = data.error;
							if (data.done) isDone = true;

							// No longer loading after first message
							loading = false;
						} catch (e) {
							console.error('Failed to parse SSE data:', jsonStr, e);
						}
					}
				}
			}

			loading = false;
		} catch (e) {
			// Ignore abort errors (these happen when navigating away)
			if (e instanceof Error && e.name === 'AbortError') {
				console.log('Fetch aborted - user navigated away');
				return;
			}
			error = e instanceof Error ? e.message : 'Failed to fetch job status';
			console.error('Error fetching job status:', e);
			loading = false;
		}
	}

	// Fetch status when component mounts, cleanup on unmount
	$effect(() => {
		const abortController = new AbortController();
		fetchJobStatus(abortController.signal);

		// Cleanup function - runs when navigating away
		return () => {
			abortController.abort();
		};
	});
</script>

<div class="w-full px-4 md:px-6 py-8">
	<h1 class="text-4xl font-bold mb-4 text-center text-primary-500">Job Status</h1>

	<div class="card p-6 bg-surface-100 dark:bg-surface-800 mb-6">
		<h2 class="text-xl font-semibold mb-2">Job ID</h2>
		<p class="font-mono text-lg text-secondary-500">{jobId}</p>
	</div>

	{#if error}
		<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
			{error}
		</div>
	{/if}

	<div class="card p-6 bg-surface-100 dark:bg-surface-800">
		<h2 class="text-xl font-semibold mb-4">Job Status</h2>

		{#if loading}
			<div class="flex items-center gap-3 text-surface-600 dark:text-surface-400">
				<div class="animate-spin">⟳</div>
				<p>Loading job status...</p>
			</div>
		{:else}
			<div class="space-y-4">
				<div class="grid grid-cols-2 gap-4">
					<div class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
						<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">State</p>
						<p class="text-2xl font-bold text-primary-500">{jobState || 'Unknown'}</p>
					</div>
					<div class="p-4 bg-surface-200 dark:bg-surface-700 rounded-lg">
						<p class="text-sm text-surface-600 dark:text-surface-400 mb-1">Elapsed Time</p>
						<p class="text-2xl font-bold text-secondary-500">{elapsedTime || 'N/A'}</p>
					</div>
				</div>

				{#if message}
					<div class="p-4 bg-surface-900 text-green-400 rounded-lg font-mono text-sm">
						{message}
					</div>
				{/if}

				{#if isDone}
					<div class="p-4 bg-success-100 dark:bg-success-900/20 border border-success-500 rounded-lg">
						<p class="font-semibold text-success-700 dark:text-success-300">Job completed!</p>
					</div>
				{:else if !loading}
					<div class="p-4 bg-warning-100 dark:bg-warning-900/20 border border-warning-500 rounded-lg">
						<p class="font-semibold text-warning-700 dark:text-warning-300">Monitoring job... (updates every 3s)</p>
					</div>
				{/if}
			</div>
		{/if}
	</div>
</div>
