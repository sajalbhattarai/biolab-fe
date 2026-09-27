<script lang="ts">
	import { tick } from 'svelte';
	import { marked } from 'marked';
	import DOMPurify from 'dompurify';
	import { Bot, Check, ChevronDown, Copy, Download, ExternalLink, KeyRound, Settings2, ShieldAlert, Trash2, X } from 'lucide-svelte';
	import { chatAsk, chatAvailable, chatForget, chatGet, chatHpcKey, chatHpcReload, chatSettings, hpcKeysAvailable } from '$lib/workspace/chat-api';
	import { uiBase } from '$lib/workspace/base.svelte';
	import { ui } from '$lib/workspace/ui.svelte';
	import { ws } from '$lib/workspace/data.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import Resizer from '$lib/workspace/motion/Resizer.svelte';

	/**
	 * Chat with the genome: an AI model answers from one genome's results only
	 * (lib/server/genome-chat), within a reading budget, listing the evidence it read.
	 * Setup holds provider, model, key, budgets and the data notice (accepted before
	 * the first question). The conversation is kept per genome and can be saved.
	 */
	/** `context`: what is open in Results now (tab, filter, the viewer's selection), sent with a question unless left out. */
	let { genome, context = '', onclose }: { genome: string; context?: string; onclose: () => void } = $props();
	let useContext = $state(true);

	type Provider = 'anthropic' | 'openai' | 'gemini' | 'custom' | 'builtin';
	interface Evidence {
		id: string;
		kind: 'list' | 'read' | 'search';
		path: string;
		detail: string;
		full?: string;
	}
	interface Turn {
		role: 'user' | 'assistant';
		text: string;
		at: string;
		evidence?: Evidence[];
		provider?: Provider;
		model?: string;
		read?: number;
		context?: string;
	}
	interface Settings {
		provider: Provider;
		model: string;
		baseUrl: string;
		budget: number;
		answerTokens: number;
		consented: Provider[];
	}
	interface Info {
		settings: Settings;
		keys: Record<Provider, { saved: boolean; last4?: string; here?: boolean; hpc?: boolean }>;
		providers: Record<Provider, { label: string; base: string; models: string[]; policy: string; keys: string }>;
		builtin: { ready: boolean; model: string; note: string };
		history: Turn[];
	}

	let info = $state<Info | null>(null);
	let s = $state<Settings | null>(null);
	let turns = $state<Turn[]>([]);
	let loadError = $state('');
	let view = $state<'chat' | 'setup'>('chat');
	let question = $state('');
	let asking = $state(false);
	let askError = $state('');
	let keyInput = $state('');
	let saving = $state(false);
	let list = $state<HTMLElement | null>(null);
	let copied = $state(-1);

	const ORDER: Provider[] = ['anthropic', 'openai', 'gemini', 'custom', 'builtin'];
	const p = $derived(s?.provider ?? 'anthropic');
	const meta = $derived(info?.providers[p]);
	const hasKey = $derived(!!info?.keys[p]?.saved);
	const consented = $derived(!!s?.consented.includes(p));
	const ready = $derived(!!s && p !== 'builtin' && consented && (hasKey || p === 'custom') && !!s.model && (p !== 'custom' || !!s.baseUrl));

	async function load() {
		loadError = '';
		try {
			const d = await chatGet<Info>(genome);
			info = d;
			s = { ...d.settings };
			turns = d.history;
			if (!ready) view = 'setup';
			await scrollDown();
		} catch (e) {
			loadError = e instanceof Error ? e.message : String(e);
			// Settings do not depend on the genome, so they load anyway and stay editable.
			try {
				const d = await chatGet<Info>('');
				info = d;
				s = { ...d.settings };
				turns = [];
			} catch {
				// nothing to show but the error
			}
		}
	}
	$effect(() => {
		void genome;
		if (chatAvailable()) load();
	});

	async function scrollDown() {
		await tick();
		list?.scrollTo({ top: list.scrollHeight, behavior: ui.motion === 'off' ? 'auto' : 'smooth' });
	}

	/** Saves the choices (and a key, when one was typed). */
	async function saveSettings(extra: Record<string, unknown> = {}) {
		if (!s) return;
		saving = true;
		try {
			const d = await chatSettings<Omit<Info, 'history'>>({ ...s, ...extra });
			info = { ...d, history: turns };
			s = { ...d.settings };
			if ('key' in extra) keyInput = '';
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		} finally {
			saving = false;
		}
	}

	/** A key saved in (or, with null, removed from) the HPC home. */
	async function hpcKey(key: string | null) {
		saving = true;
		try {
			const d = await chatHpcKey<Omit<Info, 'history'>>(p, key);
			info = { ...d, history: turns };
			if (key) keyInput = '';
			ui.notify(key ? 'Saved in your HPC home.' : 'Removed from your HPC home.', 'ok');
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		} finally {
			saving = false;
		}
	}
	async function reloadHpc() {
		saving = true;
		try {
			const d = await chatHpcReload<Omit<Info, 'history'>>();
			info = { ...d, history: turns };
			ui.notify(d.keys[p]?.hpc ? 'Read the key from your HPC home.' : 'No key for this provider in your HPC home yet.', d.keys[p]?.hpc ? 'ok' : 'info');
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		} finally {
			saving = false;
		}
	}

	function pickProvider(to: Provider) {
		if (!s || !info) return;
		s.provider = to;
		const models = info.providers[to].models;
		if (!models.includes(s.model)) s.model = models[0] ?? '';
		saveSettings();
	}

	function setConsent(on: boolean) {
		if (!s) return;
		s.consented = on ? [...new Set([...s.consented, p])] : s.consented.filter((x) => x !== p);
		saveSettings();
	}

	async function send(text = question) {
		const q = text.trim();
		if (!q || asking) return;
		if (!ready) {
			view = 'setup';
			return;
		}
		askError = '';
		asking = true;
		question = '';
		const ctx = useContext ? context : '';
		turns = [...turns, { role: 'user', text: q, at: new Date().toISOString(), ...(ctx ? { context: ctx } : {}) }];
		await scrollDown();
		try {
			const d = await chatAsk<{ answer: Turn }>(genome, q, ctx);
			turns = [...turns, d.answer];
		} catch (e) {
			askError = e instanceof Error ? e.message : String(e);
			turns = turns.slice(0, -1);
			question = q;
		} finally {
			asking = false;
			await scrollDown();
		}
	}

	async function clearChat() {
		if (!turns.length || !confirm(`Forget this conversation about ${genome}?`)) return;
		await chatForget(genome);
		turns = [];
	}

	// ------------------------------------------------ showing answers

	/** Markdown to safe HTML, with evidence tags [E3] as small badges. */
	function render(md: string): string {
		const html = DOMPurify.sanitize(marked.parse(md, { async: false, gfm: true, breaks: false }) as string);
		return html.replace(/\[(E\d+)\]/g, '<span class="cite">$1</span>');
	}
	const kindWord = { list: 'listed', read: 'read', search: 'searched' } as const;
	/**
	 * Opens a file the model read on the Files page at its folder. The full path is kept
	 * because on the cluster the shown path leaves out the run's folder; answers
	 * without one are read against the results folder.
	 */
	function folderOf(e: Evidence): string | null {
		const at = (dir: string) => `${uiBase.path}/files?path=${encodeURIComponent(dir)}`;
		if (e.full) return at(e.kind === 'list' ? e.full.replace(/\/$/, '') : e.full.slice(0, e.full.lastIndexOf('/')));
		const out = ws.resultRoots.outputRoot;
		if (!out || backend.cluster || (e.kind === 'list' && !e.path.includes('/'))) return null;
		const dir = e.kind === 'list' ? e.path.replace(/\/$/, '') : e.path.split('/').slice(0, -1).join('/');
		return at(`${out}/${dir}`);
	}

	// ------------------------------------------------ saving the conversation

	function asMarkdown(): string {
		const lines = [`# Chat with ${genome}`, '', `Saved ${new Date().toLocaleString()} from MARGIE.`, ''];
		for (const t of turns) {
			if (t.role === 'user') lines.push(`## Question`, '', t.text, '');
			else {
				lines.push(`## Answer${t.model ? ` (${t.model})` : ''}`, '', t.text, '');
				if (t.evidence?.length) {
					lines.push('**Evidence read**', '');
					for (const e of t.evidence) lines.push(`- [${e.id}] ${kindWord[e.kind]} \`${e.full ?? e.path}\` (${e.detail})`);
					lines.push('');
				}
			}
		}
		return lines.join('\n');
	}
	function asText(): string {
		return asMarkdown()
			.replace(/^#+\s*/gm, '')
			.replace(/\*\*(.*?)\*\*/g, '$1')
			.replace(/`([^`]*)`/g, '$1');
	}
	function download(kind: 'md' | 'txt') {
		const blob = new Blob([kind === 'md' ? asMarkdown() : asText()], { type: kind === 'md' ? 'text/markdown' : 'text/plain' });
		const a = Object.assign(document.createElement('a'), {
			href: URL.createObjectURL(blob),
			download: `${genome}-chat-${new Date().toISOString().slice(0, 10)}.${kind}`
		});
		a.click();
		setTimeout(() => URL.revokeObjectURL(a.href), 1000);
	}
	async function copyAnswer(i: number) {
		await navigator.clipboard.writeText(turns[i].text);
		copied = i;
		setTimeout(() => (copied = -1), 1500);
	}

	const STARTERS = [
		'Summarise how well this genome is annotated.',
		'Which genes are flagged for review, and why?',
		'Which tools ran, and with what commands?',
		'What are the largest operons, and what do they do?'
	];
</script>

<aside class="gc" style="--w: {ui.size('results:chat', 420)}px" aria-label="Chat with the genome">
	<Resizer id="results:chat" fallback={420} min={320} max={760} edge="left" label="Resize the chat" />
	<header class="gc-head">
		<span class="gc-ic" aria-hidden="true"><Bot size={17} /></span>
		<div class="gc-title">
			<b>Chat with the genome</b>
			<span>{genome}{s && view === 'chat' ? ` | ${info?.providers[p].label ?? ''}${s.model ? `, ${s.model}` : ''}` : ''}</span>
		</div>
		<span class="gc-grow"></span>
		{#if turns.length && view === 'chat'}
			<button type="button" class="gc-icon" title="Save as Markdown" aria-label="Save the conversation as Markdown" onclick={() => download('md')}><Download size={16} /></button>
			<button type="button" class="gc-icon" title="Forget this conversation" aria-label="Forget this conversation" onclick={clearChat}><Trash2 size={16} /></button>
		{/if}
		<button type="button" class="gc-icon" class:on={view === 'setup'} title="Model, key and limits" aria-label="Model, key and limits" onclick={() => (view = view === 'setup' ? 'chat' : 'setup')}>
			<Settings2 size={16} />
		</button>
		<button type="button" class="gc-icon" aria-label="Close the chat" onclick={onclose}><X size={16} /></button>
	</header>

	{#if !chatAvailable()}
		<p class="gc-note">Chat needs the MARGIE app: it keeps your API key on your own computer and reads the cluster's results through the app's connection.</p>
	{:else if loadError && (!info || !s)}
		<p class="gc-note bad">{loadError} <button type="button" class="gc-link" onclick={load}>Try again</button></p>
	{:else if !info || !s}
		<p class="gc-note">Loading…</p>
	{:else if view === 'setup'}
		<!-- ------------------------------------------------ setup -->
		<div class="gc-body gc-setup">
			<section>
				<h3>Model</h3>
				<div class="gc-providers" role="radiogroup" aria-label="Provider">
					{#each ORDER as id (id)}
						<button type="button" role="radio" aria-checked={p === id} class="gc-prov" onclick={() => pickProvider(id)}>
							{info.providers[id].label}
							{#if info.keys[id]?.saved}<Check size={13} />{/if}
						</button>
					{/each}
				</div>

				{#if p === 'builtin'}
					<div class="gc-box">
						<p>{info.builtin.note}</p>
						{#if info.builtin.model}<p class="gc-small">Configured: <code>{info.builtin.model}</code></p>{/if}
						<a class="gc-btn" href={uiBase.to('/settings#LLM_BASE_MODEL')}>Open Settings → LLM <ExternalLink size={13} /></a>
					</div>
				{:else}
					{#if p === 'custom'}
						<label class="gc-field">
							<span>Base URL</span>
							<input class="mg-input" placeholder="https://openrouter.ai/api/v1 or http://localhost:11434/v1" bind:value={s.baseUrl} onchange={() => saveSettings()} spellcheck="false" />
						</label>
					{/if}
					<label class="gc-field">
						<span>Model</span>
						<input class="mg-input" list="gc-models" bind:value={s.model} onchange={() => saveSettings()} spellcheck="false" placeholder="model name" />
						<datalist id="gc-models">
							{#each meta?.models ?? [] as m (m)}<option value={m}></option>{/each}
						</datalist>
					</label>
					<div class="gc-field">
						<span>API key</span>
						{#if hasKey}
							<div class="gc-row">
								<span class="gc-saved"><KeyRound size={13} /> saved, ending …{info.keys[p].last4}</span>
							</div>
							<div class="gc-row gc-where">
								{#if info.keys[p].here}
									<span>on this computer</span>
									<button type="button" class="gc-link" onclick={() => saveSettings({ key: null, keyFor: p })}>Remove</button>
								{/if}
								{#if info.keys[p].hpc}
									<span>in your HPC home</span>
									<button type="button" class="gc-link" disabled={saving} onclick={() => hpcKey(null)}>Remove</button>
								{/if}
							</div>
						{/if}
						{#if !hasKey || (hpcKeysAvailable() && !(info.keys[p].here && info.keys[p].hpc))}
							<form class="gc-row" onsubmit={(e) => (e.preventDefault(), keyInput.trim() && saveSettings({ key: keyInput, keyFor: p }))}>
								<input class="mg-input" type="password" autocomplete="off" placeholder={p === 'custom' ? 'if the service needs one' : hasKey ? 'paste it again to keep a second copy' : 'paste your key'} bind:value={keyInput} />
								{#if hpcKeysAvailable()}
									<button type="submit" class="gc-btn" disabled={!keyInput.trim() || saving}>On this computer</button>
									<button type="button" class="gc-btn" disabled={!keyInput.trim() || saving} onclick={() => hpcKey(keyInput)}>In my HPC home</button>
								{:else}
									<button type="submit" class="gc-btn" disabled={!keyInput.trim() || saving}>Save</button>
								{/if}
							</form>
						{/if}
						{#if hpcKeysAvailable()}
							<span class="gc-small">
								In your HPC home it is kept in <code>~/.config/margie/ai-keys.json</code>, readable only by you, and used from any computer you connect
								from. You can also write it there yourself (in VS Code on the cluster, say), one line per provider such as
								<code>{p}=YOUR_KEY</code>, then
								<button type="button" class="gc-link" disabled={saving} onclick={reloadHpc}>read it again</button>. Check that your institution allows keeping
								keys there.
							</span>
						{/if}
						<span class="gc-small">
							On this computer it is kept in your MARGIE settings folder, readable by you alone. Wherever it is kept, it is sent only to {meta?.label}.
							{#if meta?.keys}<a href={meta.keys} target="_blank" rel="noreferrer">Get a key</a>{/if}
						</span>
					</div>
				{/if}
			</section>

			<section>
				<h3>Limits</h3>
				<div class="gc-two">
					<label class="gc-field">
						<span>Reading budget (tokens)</span>
						<input class="mg-input" type="number" min="1000" max="400000" step="1000" bind:value={s.budget} onchange={() => saveSettings()} />
					</label>
					<label class="gc-field">
						<span>Answer length (tokens)</span>
						<input class="mg-input" type="number" min="500" max="64000" step="500" bind:value={s.answerTokens} onchange={() => saveSettings()} />
					</label>
				</div>
				<span class="gc-small">
					The reading budget caps how much of the results the model may read for one question (about four characters a token). More reads
					more, and costs more.
				</span>
			</section>

			{#if p !== 'builtin'}
				<section class="gc-notice">
					<h3><ShieldAlert size={15} /> Before you use an external AI</h3>
					<p>
						<b>Make sure using external AI services is allowed by your institution or funding agency.</b> Some information may not be
						shared: unpublished sequences, patient or clinical material, data under a data-use agreement, or anything confidential.
					</p>
					<p><b>What is sent</b> to {meta?.label}, over the internet, with each question:</p>
					<ul>
						<li>your question and this conversation so far;</li>
						<li>the parts of {genome}'s results the model chooses to read: file names, table rows (gene ids, sequences, names, scores), tool logs and the commands in them;</li>
						<li>nothing else on this computer, and no other genome.</li>
					</ul>
					<p>
						<b>Free and paid plans differ.</b> Paid API use is usually not used to train models and is kept for a limited time (often 30 days,
						for abuse checks); free tiers and consumer apps may keep more, and some use what you send to improve their models. Check your
						provider's terms, and whether your institution has an agreement with them.
					</p>
					<p class="gc-links">
						{#if meta?.policy}<a href={meta.policy} target="_blank" rel="noreferrer">{meta.label}: data use and privacy <ExternalLink size={12} /></a>{/if}
						{#if p === 'custom'}The service you point to decides what it keeps; a model running on this computer keeps everything here.{/if}
					</p>
					<label class="gc-consent">
						<input type="checkbox" checked={consented} onchange={(e) => setConsent(e.currentTarget.checked)} />
						I have read this, and my institution allows it.
					</label>
				</section>
			{/if}

			<div class="gc-setup-foot">
				<button type="button" class="gc-btn primary" disabled={!ready} onclick={() => (view = 'chat')}>
					{ready ? 'Start chatting' : p === 'builtin' ? 'Not set up yet' : !consented ? 'Accept the notice first' : 'Add a key first'}
				</button>
			</div>
		</div>
	{:else}
		<!-- ------------------------------------------------ chat -->
		<div class="gc-body gc-list" bind:this={list}>
			{#if loadError}
				<p class="gc-note bad">Could not load this genome's conversation: {loadError} <button type="button" class="gc-link" onclick={load}>Try again</button></p>
			{/if}
			{#if !turns.length}
				<div class="gc-empty">
					<p>Ask about {genome}'s annotation. The model reads the results itself and shows what it read.</p>
					<div class="gc-starters">
						{#each STARTERS as q (q)}<button type="button" class="gc-starter" onclick={() => send(q)}>{q}</button>{/each}
					</div>
				</div>
			{/if}
			{#each turns as t, i (i)}
				{#if t.role === 'user'}
					{#if t.context}<div class="gc-qctx">asked with: {t.context}</div>{/if}
					<div class="gc-q">{t.text}</div>
				{:else}
					<article class="gc-a">
						<div class="gc-md">{@html render(t.text)}</div>
						{#if t.evidence?.length}
							<details class="gc-ev">
								<summary><ChevronDown size={13} /> Evidence read: {t.evidence.length}{t.read ? ` | about ${t.read.toLocaleString()} tokens` : ''}</summary>
								<ol>
									{#each t.evidence as e (e.id)}
										{@const href = folderOf(e)}
										<li>
											<span class="cite">{e.id}</span>
											<span class="ev-kind">{kindWord[e.kind]}</span>
											{#if href}<a href={href} class="ev-path" title="{e.full ?? e.path}: open its folder">{e.path}</a>{:else}<span class="ev-path">{e.path}</span>{/if}
											<span class="ev-detail">{e.detail}</span>
										</li>
									{/each}
								</ol>
							</details>
						{:else}
							<p class="gc-small warn">No results were read for this answer: treat it with care.</p>
						{/if}
						<div class="gc-a-foot">
							<span>{t.model ?? ''}</span>
							<span class="gc-grow"></span>
							<button type="button" class="gc-link" onclick={() => copyAnswer(i)}>{#if copied === i}<Check size={13} /> Copied{:else}<Copy size={13} /> Copy{/if}</button>
						</div>
					</article>
				{/if}
			{/each}
			{#if asking}
				<div class="gc-thinking"><span class="gc-spin"></span> Reading {genome}'s results…</div>
			{/if}
			{#if askError}<p class="gc-note bad">{askError}</p>{/if}
		</div>

		<form class="gc-ask" onsubmit={(e) => (e.preventDefault(), send())}>
			{#if context}
				<div class="gc-ctx" class:off={!useContext} title="Sent with your question, so the model knows what you mean by this gene or here">
					<span class="gc-ctx-l">In view</span>
					<span class="gc-ctx-t">{context}</span>
					<button type="button" class="gc-link" onclick={() => (useContext = !useContext)}>{useContext ? 'Leave out' : 'Include'}</button>
				</div>
			{/if}
			<textarea
				class="mg-input"
				rows="2"
				placeholder="Ask about this genome… (Enter to send, Shift+Enter for a new line)"
				bind:value={question}
				disabled={asking}
				onkeydown={(e) => {
					if (e.key === 'Enter' && !e.shiftKey) {
						e.preventDefault();
						send();
					}
				}}
			></textarea>
			<div class="gc-ask-foot">
				<span class="gc-small">Reads up to {s.budget.toLocaleString()} tokens of results | <button type="button" class="gc-link" onclick={() => (view = 'setup')}>change</button></span>
				<span class="gc-grow"></span>
				{#if turns.length}<button type="button" class="gc-link" onclick={() => download('txt')}>Save as text</button>{/if}
				<button type="submit" class="gc-btn primary" disabled={!question.trim() || asking}>Ask</button>
			</div>
		</form>
	{/if}
</aside>

<style>
	.gc {
		position: relative;
		flex: none;
		display: flex;
		flex-direction: column;
		width: var(--w);
		max-width: 60vw;
		min-height: 0;
		border-left: 1px solid var(--mg-border);
		background: var(--mg-surface);
		color: var(--mg-text);
		font-size: var(--mg-fs-sm);
	}
	.gc-head {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 10px 12px;
		border-bottom: 1px solid var(--mg-border);
	}
	.gc-ic {
		display: grid;
		place-items: center;
		width: 30px;
		height: 30px;
		border-radius: 9px;
		background: color-mix(in srgb, var(--mg-accent) 12%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.gc-title {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.gc-title b {
		font-weight: 500;
	}
	.gc-title span {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.gc-grow {
		flex: 1;
	}
	.gc-icon {
		display: grid;
		place-items: center;
		width: 30px;
		height: 30px;
		border: 1px solid transparent;
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text-2);
		cursor: pointer;
	}
	.gc-icon:hover,
	.gc-icon.on {
		border-color: var(--mg-border);
		background: var(--mg-surface-2);
		color: var(--mg-text);
	}
	.gc-body {
		flex: 1;
		min-height: 0;
		overflow: auto;
		padding: 12px 14px;
	}
	.gc-note {
		margin: 14px;
		color: var(--mg-text-2);
	}
	.bad {
		color: var(--mg-danger, #c0392b);
	}
	.warn {
		color: var(--mg-warn);
	}
	.gc-small {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
		line-height: 1.45;
	}
	.gc-small a,
	.gc-links a {
		color: var(--mg-accent-ink, var(--mg-accent));
	}

	/* ---- setup ---- */
	.gc-setup {
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	.gc-setup section {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.gc-setup h3 {
		display: flex;
		align-items: center;
		gap: 6px;
		margin: 0;
		font-size: var(--mg-fs-xs);
		font-weight: 500;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.gc-providers {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
	}
	.gc-prov {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		height: 28px;
		padding: 0 11px;
		border: 1px solid var(--mg-border);
		border-radius: 999px;
		background: var(--mg-surface);
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-xs);
		cursor: pointer;
	}
	.gc-prov[aria-checked='true'] {
		border-color: var(--mg-accent);
		background: color-mix(in srgb, var(--mg-accent) 12%, var(--mg-surface));
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.gc-field {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.gc-field > span:first-child {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-2);
	}
	.gc-two {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 10px;
	}
	.gc-row {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.gc-row .mg-input {
		flex: 1;
		min-width: 0;
	}
	.gc-where {
		gap: 6px 10px;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.gc-where span:not(:first-child)::before {
		content: '| ';
	}
	.gc-saved {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--mg-ok);
	}
	.gc-box,
	.gc-notice {
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
		line-height: 1.5;
	}
	.gc-box p,
	.gc-notice p {
		margin: 0 0 6px;
	}
	.gc-notice {
		border-color: color-mix(in srgb, var(--mg-warn) 45%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-warn) 6%, var(--mg-surface));
		color: var(--mg-text-2);
	}
	.gc-notice b {
		font-weight: 500;
		color: var(--mg-text);
	}
	.gc-notice ul {
		margin: 0 0 8px;
		padding-left: 18px;
		list-style: disc;
	}
	.gc-links a {
		display: inline-flex;
		align-items: center;
		gap: 4px;
	}
	.gc-consent {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-top: 4px;
		color: var(--mg-text);
		cursor: pointer;
	}
	.gc-consent input {
		accent-color: var(--mg-accent);
	}
	.gc-setup-foot {
		display: flex;
		justify-content: flex-end;
	}

	/* ---- buttons ---- */
	.gc-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		height: 30px;
		padding: 0 13px;
		border: 1px solid var(--mg-border-strong);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-text);
		font: inherit;
		font-size: var(--mg-fs-sm);
		text-decoration: none;
		cursor: pointer;
		align-self: flex-start;
	}
	.gc-btn.primary {
		border-color: transparent;
		background: var(--mg-accent);
		color: var(--mg-on-accent, #fff);
	}
	.gc-btn:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.gc-link {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 0;
		border: none;
		background: none;
		color: var(--mg-accent-ink, var(--mg-accent));
		font: inherit;
		font-size: var(--mg-fs-xs);
		cursor: pointer;
	}

	/* ---- the conversation ---- */
	.gc-list {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	.gc-empty p {
		margin: 0 0 10px;
		color: var(--mg-text-2);
	}
	.gc-starters {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.gc-starter {
		padding: 8px 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-text);
		font: inherit;
		text-align: left;
		cursor: pointer;
	}
	.gc-starter:hover {
		border-color: var(--mg-accent);
	}
	.gc-q {
		align-self: flex-end;
		max-width: 88%;
		padding: 8px 12px;
		border-radius: 12px 12px 4px 12px;
		background: color-mix(in srgb, var(--mg-accent) 13%, var(--mg-surface));
		white-space: pre-wrap;
	}
	.gc-a {
		padding: 10px 12px;
		border: 1px solid var(--mg-border);
		border-radius: 4px 12px 12px 12px;
		background: var(--mg-surface);
	}
	.gc-md {
		line-height: 1.55;
		overflow-wrap: anywhere;
	}
	.gc-md :global(h1),
	.gc-md :global(h2),
	.gc-md :global(h3),
	.gc-md :global(h4) {
		margin: 10px 0 4px;
		font-size: var(--mg-fs);
		font-weight: 500;
	}
	.gc-md :global(p) {
		margin: 0 0 8px;
	}
	.gc-md :global(ul),
	.gc-md :global(ol) {
		margin: 0 0 8px;
		padding-left: 20px;
	}
	.gc-md :global(ul) {
		list-style: disc;
	}
	.gc-md :global(ol) {
		list-style: decimal;
	}
	.gc-md :global(strong) {
		font-weight: 500;
	}
	.gc-md :global(code) {
		padding: 1px 4px;
		border-radius: 4px;
		background: var(--mg-surface-2);
		font-size: 0.92em;
	}
	.gc-md :global(pre) {
		overflow: auto;
		padding: 8px;
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
	}
	.gc-md :global(table) {
		display: block;
		overflow-x: auto;
		margin: 4px 0 10px;
		border-collapse: collapse;
		font-size: var(--mg-fs-xs);
	}
	.gc-md :global(th),
	.gc-md :global(td) {
		padding: 4px 8px;
		border: 1px solid var(--mg-border);
		text-align: left;
	}
	.gc-md :global(th) {
		background: var(--mg-surface-2);
		font-weight: 500;
	}
	.gc :global(.cite) {
		display: inline-block;
		padding: 0 5px;
		border-radius: 4px;
		background: color-mix(in srgb, var(--mg-accent) 14%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
		font-size: 0.78em;
		font-variant-numeric: tabular-nums;
		vertical-align: 1px;
	}
	.gc-ev {
		margin-top: 8px;
		border-top: 1px dashed var(--mg-border);
		padding-top: 6px;
		font-size: var(--mg-fs-xs);
	}
	.gc-ev summary {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		color: var(--mg-text-2);
		cursor: pointer;
		list-style: none;
	}
	.gc-ev summary::-webkit-details-marker {
		display: none;
	}
	.gc-ev[open] summary :global(svg) {
		transform: rotate(180deg);
	}
	.gc-ev ol {
		margin: 6px 0 0;
		padding: 0;
		list-style: none;
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.gc-ev li {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 6px;
	}
	.ev-kind {
		color: var(--mg-text-3);
	}
	.ev-path {
		overflow-wrap: anywhere;
		color: var(--mg-text);
	}
	a.ev-path {
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.ev-detail {
		color: var(--mg-text-3);
	}
	.gc-a-foot {
		display: flex;
		align-items: center;
		margin-top: 6px;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.gc-thinking {
		display: flex;
		align-items: center;
		gap: 8px;
		color: var(--mg-text-2);
	}
	.gc-spin {
		width: 14px;
		height: 14px;
		border-radius: 50%;
		border: 2px solid color-mix(in srgb, var(--mg-accent) 25%, transparent);
		border-top-color: var(--mg-accent);
		animation: gc-spin 900ms linear infinite;
	}
	@keyframes gc-spin {
		to {
			transform: rotate(360deg);
		}
	}
	/* What is open in Results, sent with the question. */
	.gc-ctx {
		display: flex;
		align-items: baseline;
		gap: 8px;
		padding: 5px 8px;
		border: 1px solid color-mix(in srgb, var(--mg-accent) 35%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-accent) 6%, var(--mg-surface));
		font-size: var(--mg-fs-xs);
	}
	.gc-ctx.off {
		opacity: 0.55;
		border-style: dashed;
	}
	.gc-ctx-l {
		flex: none;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	.gc-ctx-t {
		flex: 1;
		min-width: 0;
		overflow-wrap: anywhere;
		color: var(--mg-text-2);
	}
	.gc-qctx {
		align-self: flex-end;
		max-width: 88%;
		margin-bottom: -8px;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
		text-align: right;
	}
	.gc-ask {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding: 10px 12px;
		border-top: 1px solid var(--mg-border);
	}
	.gc-ask textarea {
		width: 100%;
		min-height: 52px;
		resize: vertical;
		font: inherit;
	}
	.gc-ask-foot {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	:global([data-motion='off']) .gc-spin {
		animation: none;
	}
	@media (max-width: 900px) {
		.gc {
			position: absolute;
			inset: 0 0 0 auto;
			z-index: 5;
			width: min(100%, var(--w));
			max-width: none;
			box-shadow: -8px 0 24px rgb(0 0 0 / 0.12);
		}
	}
</style>
