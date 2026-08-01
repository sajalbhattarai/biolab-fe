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

	type Msg = { role: 'you' | 'margie'; text: string; at: string };

	// History is kept per job+organism so switching genomes does not mix
	// transcripts, and so a reload or a trip back to the job page does not lose
	// the conversation. localStorage, not the server: these are the user's own
	// notes about their own run, and a chat that vanishes on refresh is useless
	// for the "read it, then write it up" workflow this exists to support.
	const historyKey = $derived(`margie:chat:${jobId}:${organism}`);

	function loadHistory() {
		try {
			const raw = localStorage.getItem(historyKey);
			if (raw) messages = JSON.parse(raw);
		} catch { /* corrupt or unavailable storage is not worth failing over */ }
	}
	function saveHistory() {
		try {
			localStorage.setItem(historyKey, JSON.stringify(messages));
		} catch { /* quota or private mode — the chat still works in-session */ }
	}
	function clearHistory() {
		messages = [];
		try { localStorage.removeItem(historyKey); } catch { /* ignore */ }
	}

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
		messages = [...messages, { role: 'you', text: q, at: new Date().toISOString() }];
		saveHistory();
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
			messages = [...messages,
				{ role: 'margie', text: body.answer || '(empty answer)', at: new Date().toISOString() }];
			saveHistory();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Chat failed';
			online = await checkStatus();
		} finally {
			busy = false;
		}
	}

	// PDF export via the browser's own print-to-PDF, deliberately: adding jsPDF
	// or similar would mean a new dependency and a hand-rolled layout engine,
	// and the browser already produces better typography, real text selection,
	// and correct page breaks. Opens a self-contained formatted document and
	// calls print(); the user picks "Save as PDF".
	function esc(s: string): string {
		return s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c] as string);
	}

	function downloadPdf() {
		if (messages.length === 0) return;
		const when = new Date().toLocaleString();
		const rows = messages
			.map((m) => {
				const who = m.role === 'you' ? 'Question' : 'MARGIE';
				const ts = m.at ? new Date(m.at).toLocaleString() : '';
				return `<div class="turn ${m.role}">
					<div class="who">${esc(who)}<span class="ts">${esc(ts)}</span></div>
					<div class="body">${esc(m.text)}</div>
				</div>`;
			})
			.join('\n');

		const doc = `<!doctype html><html><head><meta charset="utf-8">
<title>MARGIE chat — ${esc(organism)}</title>
<style>
  @page { margin: 20mm; }
  body { font: 11pt/1.5 Calibri, Arial, sans-serif; color: #000; background: #fff; }
  h1 { font-size: 15pt; margin: 0 0 2mm; }
  .meta { font-size: 9pt; color: #444; margin-bottom: 6mm;
          border-bottom: 1px solid #999; padding-bottom: 3mm; }
  .meta div { margin: 0.5mm 0; }
  .turn { margin: 0 0 5mm; page-break-inside: avoid; }
  .who { font-weight: 700; font-size: 9.5pt; margin-bottom: 1mm; }
  .ts { font-weight: 400; color: #666; margin-left: 3mm; font-size: 8.5pt; }
  .body { white-space: pre-wrap; }
  .turn.you .body { border-left: 2px solid #0b2842; padding-left: 3mm; }
  .note { margin-top: 8mm; padding-top: 3mm; border-top: 1px solid #999;
          font-size: 8.5pt; color: #444; }
</style></head><body>
<h1>MARGIE — genome chat transcript</h1>
<div class="meta">
  <div><strong>Genome:</strong> ${esc(organism)}</div>
  <div><strong>Job:</strong> ${esc(jobId)}</div>
  <div><strong>Exported:</strong> ${esc(when)}</div>
  <div><strong>Exchanges:</strong> ${messages.filter((m) => m.role === 'you').length}</div>
</div>
${rows}
<div class="note">
  Answers were generated from this run's own pipeline records
  (FINAL_ANNOTATION_WITH_CONFIDENCE.tsv and the consolidated evidence matrix) only.
  The model was instructed to use no outside knowledge and to state when the evidence
  does not answer a question. Verify any claim against the cited field before relying
  on it in published work.
</div>
</body></html>`;

		// A blob URL in a new window, not document.write into an opened handle:
		// popup blockers and Safari both treat the latter inconsistently.
		const url = URL.createObjectURL(new Blob([doc], { type: 'text/html' }));
		const w = window.open(url, '_blank');
		if (!w) {
			error = 'Could not open the export window — allow pop-ups for this site.';
			URL.revokeObjectURL(url);
			return;
		}
		w.addEventListener('load', () => {
			w.focus();
			w.print();
			setTimeout(() => URL.revokeObjectURL(url), 60000);
		});
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
		loadHistory();
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
		<span class="ml-auto flex items-center gap-2 text-xs">
			{#if messages.length > 0}
				<button
					type="button"
					class="underline hover:opacity-70"
					title="Export this transcript as a formatted PDF"
					onclick={downloadPdf}>⤓ PDF</button>
				<button
					type="button"
					class="underline hover:opacity-70"
					title="Delete this saved transcript"
					onclick={clearHistory}>clear</button>
			{/if}
			<span class="inline-block h-2 w-2 rounded-full {online ? 'bg-success-500' : 'bg-surface-400'}"
			></span>
			{online ? 'interactive' : starting ? 'starting' : 'offline'}
		</span>
	</div>

	{#if !online && messages.length > 0}
		<!-- Saved transcript from an earlier session. Readable and exportable
		     without holding a GPU — restarting is only needed to ask more. -->
		<div class="flex-1 space-y-3 overflow-y-auto p-3">
			<p class="text-xs opacity-60">
				Saved transcript. Start chat to ask more.
			</p>
			{#each messages as m}
				<div class="text-sm">
					<div class="text-xs font-semibold opacity-60">{m.role === 'you' ? 'You' : 'MARGIE'}</div>
					<div class="whitespace-pre-wrap">{m.text}</div>
				</div>
			{/each}
		</div>
		<div class="border-t border-surface-500/30 p-2 text-center">
			<button
				type="button"
				class="btn variant-filled-primary btn-sm"
				onclick={startChat}
				disabled={starting}
			>{starting ? 'Starting…' : 'Start chat'}</button>
			{#if statusNote}<p class="mt-1 text-xs opacity-60">{statusNote}</p>{/if}
		</div>
	{:else if !online}
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
