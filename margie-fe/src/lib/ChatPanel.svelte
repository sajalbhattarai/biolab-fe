<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { authHeaders } from '$lib/auth.js';

	let { jobId, organism }: { jobId: string; organism: string } = $props();

	function getApiUrl() {
		if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
			return 'http://localhost:8000';
		}
		return '';
	}

	type Msg = { role: 'you' | 'margie'; text: string };

	let online = $state(false);
	let starting = $state(false);
	let statusNote = $state('');
	let error = $state('');
	let question = $state('');
	let busy = $state(false);
	let messages = $state<Msg[]>([]);
	let poll: ReturnType<typeof setInterval> | null = null;

	async function checkStatus(): Promise<boolean> {
		try {
			const res = await fetch(`${getApiUrl()}/v1/llm/status`, { headers: authHeaders() });
			if (!res.ok) return false;
			const s = await res.json();
			online = !!s.online;
			if (!online && s.detail) statusNote = s.detail;
			return online;
		} catch {
			return false;
		}
	}

	// While starting, poll until the model finishes loading. /health counts as
	// activity server-side, so this also keeps the session alive while the panel
	// is open — the idle timeout only advances once nobody is watching.
	function startPolling() {
		stopPolling();
		poll = setInterval(async () => {
			if (await checkStatus()) {
				starting = false;
				statusNote = '';
				stopPolling();
				keepAlive();
			}
		}, 5000);
	}
	function stopPolling() {
		if (poll) { clearInterval(poll); poll = null; }
	}
	function keepAlive() {
		stopPolling();
		poll = setInterval(checkStatus, 60000);
	}

	async function startChat() {
		starting = true;
		error = '';
		statusNote = 'Requesting a GPU and loading the model…';
		try {
			const res = await fetch(`${getApiUrl()}/v1/llm/start`, {
				method: 'POST',
				headers: { ...authHeaders(), 'Content-Type': 'application/json' }
			});
			const body = await res.json().catch(() => ({}));
			if (!res.ok) throw new Error(body.detail || `Could not start chat (${res.status})`);
			if (body.already_running) { online = true; starting = false; keepAlive(); return; }
			statusNote = body.detail || 'Starting…';
			startPolling();
		} catch (e) {
			starting = false;
			error = e instanceof Error ? e.message : 'Could not start chat';
		}
	}

	async function ask() {
		const q = question.trim();
		if (!q || busy) return;
		messages = [...messages, { role: 'you', text: q }];
		question = '';
		busy = true;
		error = '';
		try {
			const res = await fetch(`${getApiUrl()}/v1/llm/chat`, {
				method: 'POST',
				headers: { ...authHeaders(), 'Content-Type': 'application/json' },
				body: JSON.stringify({ job_id: jobId, organism, question: q })
			});
			const body = await res.json().catch(() => ({}));
			if (!res.ok) throw new Error(body.detail || `Chat failed (${res.status})`);
			messages = [...messages, { role: 'margie', text: body.answer || '(empty answer)' }];
		} catch (e) {
			error = e instanceof Error ? e.message : 'Chat failed';
			online = await checkStatus();
		} finally {
			busy = false;
		}
	}

	// End interactive mode when the page goes away, so the GPU is not held.
	// fetch(keepalive) rather than sendBeacon: beacon cannot carry the auth
	// header, and this endpoint is authenticated. This is only the fast path —
	// the server's own idle timeout is what covers a crash or a slept laptop.
	function releaseOnExit() {
		if (!online) return;
		try {
			fetch(`${getApiUrl()}/v1/llm/stop`, {
				method: 'POST',
				headers: authHeaders(),
				keepalive: true
			});
		} catch { /* nothing useful to do while unloading */ }
	}

	onMount(() => {
		checkStatus().then((up) => { if (up) keepAlive(); });
		// pagehide fires on tab close AND on bfcache navigation, where
		// beforeunload is unreliable in Safari.
		window.addEventListener('pagehide', releaseOnExit);
	});

	onDestroy(() => {
		stopPolling();
		if (typeof window !== 'undefined') window.removeEventListener('pagehide', releaseOnExit);
		releaseOnExit();
	});
</script>

<div class="flex h-full flex-col rounded border border-surface-500/30">
	<div class="flex items-center gap-2 border-b border-surface-500/30 px-3 py-2">
		<span class="font-semibold">Chat about the genome</span>
		<span class="text-xs opacity-60 break-all">{organism}</span>
		<span class="ml-auto flex items-center gap-1 text-xs">
			<span class="inline-block h-2 w-2 rounded-full {online ? 'bg-success-500' : 'bg-surface-400'}"
			></span>
			{online ? 'interactive' : starting ? 'starting' : 'offline'}
		</span>
	</div>

	{#if !online}
		<div class="flex flex-1 flex-col items-center justify-center gap-3 p-4 text-center">
			<p class="text-sm opacity-70">
				Ask questions about this genome's results. Answers come only from this run's
				own evidence — no outside knowledge.
			</p>
			<button
				type="button"
				class="btn variant-filled-primary btn-sm"
				onclick={startChat}
				disabled={starting}
			>{starting ? 'Starting…' : 'Start chat'}</button>
			{#if statusNote}<p class="text-xs opacity-60">{statusNote}</p>{/if}
			{#if starting}
				<p class="text-xs opacity-60">
					A GPU session is being allocated and the model loaded. Usually 1–3 minutes.
				</p>
			{/if}
			<p class="text-xs opacity-50">
				The session ends automatically when you leave this page, or after 30 minutes idle.
			</p>
		</div>
	{:else}
		<div class="flex-1 space-y-3 overflow-y-auto p-3">
			{#if messages.length === 0}
				<p class="text-sm opacity-60">
					Try: “How trustworthy is this annotation overall?” or “How many genes need review?”
				</p>
			{/if}
			{#each messages as m}
				<div class="text-sm">
					<div class="text-xs font-semibold opacity-60">{m.role === 'you' ? 'You' : 'MARGIE'}</div>
					<div class="whitespace-pre-wrap">{m.text}</div>
				</div>
			{/each}
			{#if busy}<p class="text-sm opacity-60">Thinking…</p>{/if}
		</div>
		<div class="flex gap-2 border-t border-surface-500/30 p-2">
			<input
				class="input flex-1 text-sm"
				placeholder="Ask about this genome…"
				bind:value={question}
				onkeydown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); ask(); } }}
				disabled={busy}
			/>
			<button type="button" class="btn variant-filled-primary btn-sm" onclick={ask} disabled={busy || !question.trim()}>Send</button>
		</div>
	{/if}

	{#if error}
		<div class="border-t border-surface-500/30 px-3 py-2 text-xs text-error-500">{error}</div>
	{/if}
</div>
