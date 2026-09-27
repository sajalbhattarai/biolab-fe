<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { authHeaders } from '$lib/auth.js';
	import { getApiUrl } from '$lib/config';

	let { jobId, organism }: { jobId: string; organism: string } = $props();

	type Msg = { role: 'you' | 'margie'; text: string; at: string };

	// Keeps the transcript in localStorage per job and organism, so it survives reloads
	// and does not mix between genomes.
	const historyKey = $derived(`margie:chat:${jobId}:${organism}`);

	function loadHistory() {
		try {
			const raw = localStorage.getItem(historyKey);
			if (raw) messages = JSON.parse(raw);
		} catch { /* corrupt or unavailable storage: start empty */ }
	}
	function saveHistory() {
		try {
			localStorage.setItem(historyKey, JSON.stringify(messages));
		} catch { /* quota or private mode: the chat still works in-session */ }
	}
	function clearHistory() {
		messages = [];
		subjectGene = '';
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
	// Gene the last answer was about, sent back so follow-ups stay on the same gene.
	let subjectGene = $state('');

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

	// Polls /health until the model loads; the polls also count as activity for the idle timeout.
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
				// Send the recent turns so "it" / "that gene" resolve. Only the last
				// few, and the server caps it again — an unbounded transcript would
				// undo the prompt trimming and slow every answer back down.
				body: JSON.stringify({
					job_id: jobId,
					organism,
					question: q,
					stream: true,
					// Keeps a follow-up on the same gene. The server falls back to
					// searching the transcript without it, which resolved to an
					// arbitrary gene and answered confidently about the wrong one.
					subject_gene_id: subjectGene || null,
					history: messages.slice(-7, -1).map((m) => ({ role: m.role, text: m.text }))
				})
			});
			if (!res.ok) {
				// Failures before the stream opens are still JSON.
				const body = await res.json().catch(() => ({}));
				throw new Error(body.detail || `Chat failed (${res.status})`);
			}

			// Gene this answer is about, for the next turn.
			try {
				const cs = res.headers.get('X-Context-Summary');
				if (cs) {
					const parsed = JSON.parse(cs);
					if (parsed?.subject_gene_id) subjectGene = parsed.subject_gene_id;
				}
			} catch { /* optional header: the answer still stands */ }

			// Appends an empty turn and grows it as tokens stream in.
			messages = [...messages,
				{ role: 'margie', text: '', at: new Date().toISOString() }];
			const idx = messages.length - 1;

			const reader = res.body?.getReader();
			if (!reader) throw new Error('Streaming is not supported by this browser');
			const dec = new TextDecoder();
			let acc = '';
			for (;;) {
				const { value, done } = await reader.read();
				if (done) break;
				acc += dec.decode(value, { stream: true });
				// Reassigns the array so Svelte sees the change.
				const next = [...messages];
				next[idx] = { ...next[idx], text: acc };
				messages = next;
			}
			acc += dec.decode();
			const settled = [...messages];
			settled[idx] = { ...settled[idx], text: acc || '(empty answer)' };
			messages = settled;
			saveHistory();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Chat failed';
			online = await checkStatus();
		} finally {
			busy = false;
		}
	}

	// Renders the small markdown subset the answers use. Escapes first, then
	// re-introduces the allowed tags, so model output cannot inject markup.
	function mdToHtml(src: string): string {
		let h = esc(src);
		// **bold** on its own line is a section heading.
		h = h.replace(/^\s*\*\*(.+?)\*\*\s*$/gm, '<div class="ansh">$1</div>');
		h = h.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
		h = h.replace(/`([^`]+)`/g, '<code>$1</code>');
		// Leading - or * becomes a bullet div (not <ul>), so markup stays balanced.
		h = h.replace(/^\s*[-*]\s+(.*)$/gm, '<div class="ansli">$1</div>');
		return h;
	}

	/** Escapes text for HTML; used by mdToHtml and the PDF export. */
	function esc(s: string): string {
		return s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c] as string);
	}

	// Exports to PDF with the browser's print dialog: opens a self-contained
	// formatted document and calls print().
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
  body { font: 11pt/1.5 'Times New Roman', Times, Georgia, serif; color: #000; background: #fff; }
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

		// Opens a blob URL; document.write into a popup is unreliable in Safari and popup blockers.
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

	// Ends interactive mode on page exit to free the GPU. Uses fetch(keepalive) because
	// sendBeacon cannot send the auth header; the server's idle timeout is the fallback.
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
		// pagehide also fires on bfcache navigation, where beforeunload is unreliable in Safari.
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
		<!-- Saved transcript from an earlier session; readable and exportable without a GPU. -->
		<div class="flex-1 space-y-3 overflow-y-auto p-3">
			<p class="text-xs opacity-60">
				Saved transcript. Start chat to ask more.
			</p>
			{#each messages as m}
				<div class="text-sm">
					<div class="text-xs font-semibold opacity-60">{m.role === 'you' ? 'You' : 'MARGIE'}</div>
					{#if m.role === 'margie'}
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<div class="ansbody">{@html mdToHtml(m.text)}</div>
					{:else}
						<div class="whitespace-pre-wrap">{m.text}</div>
					{/if}
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
				The session ends automatically when you leave this page, or after about 5 minutes idle.
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
					{#if m.role === 'margie'}
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<div class="ansbody">{@html mdToHtml(m.text)}</div>
				{:else}
					<div class="whitespace-pre-wrap">{m.text}</div>
				{/if}
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

<style>
	/* Typography for answers rendered as headed sections. */
	.ansbody { white-space: pre-wrap; line-height: 1.45; }
	.ansbody :global(.ansh) {
		font-weight: 700;
		margin: 0.6em 0 0.15em;
		white-space: normal;
	}
	.ansbody :global(.ansh:first-child) { margin-top: 0; }
	.ansbody :global(.ansli) {
		padding-left: 1em;
		text-indent: -0.6em;
		white-space: normal;
	}
	.ansbody :global(.ansli)::before { content: "\2022  "; opacity: 0.6; }
	.ansbody :global(code) {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.92em;
		padding: 0 0.2em;
		background: rgba(127, 127, 127, 0.14);
		border-radius: 3px;
	}
</style>
