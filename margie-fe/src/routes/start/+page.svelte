<script lang="ts">
	import '@fontsource/ibm-plex-sans/400.css';
	import '@fontsource/ibm-plex-sans/500.css';
	import '@fontsource/ibm-plex-sans/600.css';
	import '@fontsource/ibm-plex-sans/700.css';
	import '@fontsource/ibm-plex-mono/400.css';
	import '$lib/workspace/workspace.css';
	import '$lib/crisp/crisp.css';
	import { onMount, tick } from 'svelte';
	import { fade, fly, slide } from 'svelte/transition';
	import { page } from '$app/state';
	import { ArrowRight, Check, ChevronRight, CircleAlert, Copy, Eye, EyeOff, KeyRound, LoaderCircle, Monitor, Server, Terminal, UserRound } from 'lucide-svelte';
	import CrispMark from '$lib/crisp/CrispMark.svelte';
	import Corner from '$lib/workspace/Corner.svelte';
	import SizeSliders from '$lib/workspace/SizeSliders.svelte';
	import { crispVars } from '$lib/crisp/theme';
	import { clearToken, isLoggedIn, setToken } from '$lib/auth.js';
	import { getApiUrl } from '$lib/config';
	import { styleString } from '$lib/workspace/prefs';
	import { ui } from '$lib/workspace/ui.svelte';
	import type { HpcStatus } from '$lib/connect/hpc';
	import type { KeyStatus } from '$lib/connect/keys';
	import type { LocalStatus } from '$lib/connect/local';
	import type { ConnectSettings } from '$lib/connect/settings';
	import type { SourceStatus } from '$lib/connect/source';
	import type { WslStatus } from '$lib/connect/wsl';

	/**
	 * Start page: chooses where MARGIE runs (this computer or an HPC) and prepares it
	 * through /api/connect. Locally it finds or fetches the pipeline; on an HPC it
	 * connects over ssh (answering prompts here), sets up a key, then signs in.
	 */

	type Snap = { settings: ConnectSettings; local: LocalStatus; hpc: HpcStatus; key: KeyStatus; source: SourceStatus; wsl: WslStatus | null };
	let snap = $state<Snap | null>(null);
	let choice = $state<'' | 'local' | 'hpc'>('');
	let busy = $state('');
	let problem = $state('');
	const launch = page.url.searchParams.has('launch');

	async function load(fetchSource = false) {
		try {
			const r = await fetch(fetchSource ? '/api/connect?fetch=1' : '/api/connect');
			if (r.ok) snap = await r.json();
		} catch {
			// Server unreachable: the next poll retries.
		}
	}

	async function act(action: string, extra: Record<string, unknown> = {}, label = action) {
		busy = label;
		problem = '';
		try {
			const r = await fetch('/api/connect', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ action, ...extra })
			});
			const data = await r.json().catch(() => ({}));
			if (!r.ok) throw new Error(data.message || `That did not work (${r.status}).`);
			snap = data;
			return data;
		} catch (e) {
			problem = e instanceof Error ? e.message : String(e);
			return null;
		} finally {
			busy = '';
		}
	}

	// ---- this computer ----
	let pipelineDir = $state('');
	/** Opens the local interface with a full page load so its data starts fresh. */
	async function openLocal() {
		if (!(await act('choose', { target: 'local' }, 'open'))) return;
		clearToken();
		window.location.assign('/crisp/home');
	}

	// ---- HPC ----
	let hpcUser = $state('');
	let hpcAddr = $state('');
	let backendDir = $state('');
	let dirTouched = $state(false);
	let answer = $state('');
	let reveal = $state(false);
	let restartOpen = $state(false);
	/** Advanced section: backend folder, code, and clean restart. */
	let advancedOpen = $state(false);
	let answerBox = $state<HTMLInputElement>();

	const hpc = $derived(snap?.hpc);
	const prompt = $derived(hpc?.prompts[0]);
	const host = $derived(`${hpcUser.trim()}@${hpcAddr.trim()}`);
	const connecting = $derived(hpc?.phase === 'connecting');
	const connected = $derived(hpc?.phase === 'ready');

	/* Suggests the usual backend folder until one is typed. */
	$effect(() => {
		if (!dirTouched && hpcUser.trim()) backendDir = `/home/${hpcUser.trim()}/bioinformatics-tools`;
	});

	async function connect(mode: 1 | 2 = 1) {
		restartOpen = false;
		if (connecting || connected) await act('hpc-stop', {}, 'stop');
		await act('hpc-start', { host, backendDir: backendDir.trim(), mode }, 'connect');
	}

	async function send(cancel = false) {
		if (!prompt) return;
		await act('hpc-answer', { id: prompt.id, text: answer, cancel }, 'answer');
		answer = '';
		reveal = false;
	}

	// ---- backend source ----
	let commitMessage = $state('');
	let checking = $state(false);
	const source = $derived(snap?.source);
	const unpushed = $derived(!!source?.local && (source.onGitHub === false || source.ahead > 0 || source.changes.length > 0));

	async function checkGitHub() {
		checking = true;
		await load(true);
		checking = false;
	}

	/* Focuses the answer box whenever ssh asks something new. */
	$effect(() => {
		if (prompt?.id) tick().then(() => answerBox?.focus());
	});

	/** The connection steps; progress maps the reported step ids onto them. */
	const STEPS = [
		{ id: 'connect', label: 'Sign in to the HPC', of: ['clean', 'connect', 'node', 'signed-in'] },
		{ id: 'prepare', label: 'Get MARGIE ready there', of: ['prepare'], note: 'the first time, it is downloaded and installed' },
		{ id: 'code', label: 'Check it is the latest', of: ['code'] },
		{ id: 'start', label: "Start MARGIE's server", of: ['start'] },
		{ id: 'tunnel', label: 'Open a secure tunnel to it', of: ['tunnel'] }
	];
	const progress = $derived.by(() => {
		const reached = hpc?.steps ?? [];
		const at = (s: (typeof STEPS)[number]) => reached.findLastIndex((r) => s.of.includes(r.id));
		const last = Math.max(-1, ...STEPS.map((s, i) => (at(s) >= 0 ? i : -1)));
		return STEPS.map((s, i) => {
			const detail = reached.filter((r) => s.of.includes(r.id)).at(-1)?.text ?? '';
			let state: 'done' | 'now' | 'todo' | 'failed' = 'todo';
			if (connected || i < last) state = 'done';
			else if (i === last) state = hpc?.phase === 'failed' ? 'failed' : connecting ? 'now' : 'done';
			// A running backend is reused, so the start step counts as done.
			if (s.id === 'start' && at(s) < 0 && (connected || last > i)) state = 'done';
			return { ...s, state, detail: state === 'todo' ? '' : detail };
		});
	});

	// ---- passwordless login ----
	let manual = $state(false);
	let keyPath = $state('~/.ssh/margie_ed25519');
	let keyNote = $state('');
	const keyReady = $derived(!!snap?.settings.sshKey && !!snap?.key.exists);
	/** Keys used before, newest first. */
	const recentKeys = $derived((snap?.settings.recentKeys ?? '').split('|').filter(Boolean));

	async function setUpKey() {
		keyNote = '';
		const r = await act('key-setup', {}, 'key');
		if (r?.result)
			keyNote = r.result.works
				? 'Key installed. Your password is no longer needed.'
				: 'Key installed, but the cluster still asks for two-factor. MARGIE will ask when needed.';
	}

	// ---- MARGIE account ----
	let accountMode = $state<'signin' | 'create'>('signin');
	let username = $state('');
	let password = $state('');
	let pastedKey = $state('');
	let alreadyIn = $state(false);

	async function signIn() {
		busy = 'signin';
		problem = '';
		try {
			const res = await fetch(`${getApiUrl()}/v1/auth/login`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ username, password })
			});
			if (res.status === 401) throw new Error('That username and password did not match an account on this HPC.');
			if (!res.ok) throw new Error(`Signing in did not work (${res.status}).`);
			setToken((await res.json()).access_token);
			ui.restore();
			window.location.assign(ui.home());
		} catch (e) {
			problem =
				e instanceof TypeError ? `Can't reach MARGIE's server at ${getApiUrl()}. Is the connection still open?` : e instanceof Error ? e.message : String(e);
		} finally {
			busy = '';
		}
	}

	async function createAccount() {
		if (await act('register', { username, password, privateKey: keyReady ? '' : pastedKey }, 'create')) await signIn();
	}

	function copy(text: string) {
		navigator.clipboard?.writeText(text).then(
			() => ui.notify('Copied', 'ok'),
			() => {}
		);
	}

	// ---- load and polling ----
	let started = false;
	onMount(() => {
		ui.restore();
		const dark = matchMedia('(prefers-color-scheme: dark)');
		ui.systemDark = dark.matches;
		const onDark = (e: MediaQueryListEvent) => (ui.systemDark = e.matches);
		dark.addEventListener('change', onDark);
		alreadyIn = isLoggedIn();
		let timer: ReturnType<typeof setTimeout>;
		const poll = async () => {
			await load();
			const active = snap?.hpc.phase === 'connecting' || snap?.local.clone.running;
			timer = setTimeout(poll, active ? 900 : 4000);
		};
		load(true).then(() => {
			if (!snap) return;
			const s = snap.settings;
			// Unsupported locally (Windows) or already connecting: selects the HPC.
			choice = snap.hpc.phase !== 'idle' || snap.local.unsupported ? 'hpc' : s.target;
			const [u, a] = s.hpcHost.includes('@') ? s.hpcHost.split('@') : ['', ''];
			hpcUser = u;
			hpcAddr = a;
			if (s.backendDir) {
				backendDir = s.backendDir;
				dirTouched = true;
			}
			if (s.sshKey) keyPath = s.sshKey;
			pipelineDir = s.pipelineRoot;
			// From the launcher: opens the local interface if that was the choice; the HPC never auto-connects.
			if (launch && !started) {
				started = true;
				if (s.target === 'local' && snap.local.pipeline) openLocal();
			}
			// From "Save and reconnect": reconnects with the new settings.
			if (page.url.searchParams.has('reconnect') && !started && s.hpcHost && s.backendDir) {
				started = true;
				choice = 'hpc';
				connect(1);
			}
			poll();
		});
		return () => {
			clearTimeout(timer);
			dark.removeEventListener('change', onDark);
		};
	});

	const vars = $derived(styleString(crispVars(ui.prefs, ui.dark)) + '; --cr-page: var(--mg-accent); ' + ui.motionStyle);
	const manualCommands = $derived(
		[
			`# 1. A key for MARGIE (no passphrase: the backend uses it unattended)`,
			`ssh-keygen -t ed25519 -N '' -f ~/.ssh/margie_ed25519 -C margie`,
			`# 2. Its public half onto the HPC (asks for your password once)`,
			`ssh-copy-id -i ~/.ssh/margie_ed25519.pub ${hpcUser || 'you'}@${hpcAddr || 'cluster.address'}`,
			`# 3. Check it: this should print ok without asking for anything`,
			`ssh -i ~/.ssh/margie_ed25519 -o BatchMode=yes ${hpcUser || 'you'}@${hpcAddr || 'cluster.address'} echo ok`
		].join('\n')
	);
</script>

<svelte:head><title>Set up | MARGIE</title></svelte:head>

<div class="crisp start" data-mg-root data-theme={ui.dark ? 'dark' : 'light'} data-motion={ui.motion} style={vars}>
	<header class="bar">
		<span class="brand"><CrispMark size={22} /><span class="word">MARGIE</span></span>
		<span class="grow"></span>
		{#if connected}<span class="conn"><span class="led" aria-hidden="true"></span><span class="conn-text">Connected to {hpc?.node.split('.')[0]}</span></span>{/if}
		<!-- The interfaces' corner controls, without the account menu. -->
		<Corner base="crisp" account={false}>
			{#snippet customize()}
				<SizeSliders />
			{/snippet}
		</Corner>
	</header>

	<main class="content">
		<div class="page">
			<header class="st-head">
				<h1 class="cr-title">Set up MARGIE</h1>
				<p class="cr-lede">Choose where analyses run. You can change this later.</p>
				<span class="cr-meta">
					{#if !snap}Looking…{:else if connected}Connected to {hpc?.node.split('.')[0]}{:else if snap.settings.target === 'hpc'}Last used: HPC{:else}Last used: this computer{/if}
				</span>
			</header>

			<!-- The two targets as equal cards. -->
			<div class="choices" role="radiogroup" aria-label="Where MARGIE runs">
				<button type="button" role="radio" class="choice" aria-checked={choice === 'local'} onclick={() => (choice = 'local')}>
					<span class="c-top">
						<span class="c-icon" aria-hidden="true"><Monitor size={22} /></span>
						<span class="radio" aria-hidden="true"></span>
					</span>
					<b class="c-name">This computer</b>
					<span class="c-note">Uses this computer's CPU, memory and disk. No account needed.</span>
					<span class="c-state" class:ok={!!snap?.local.pipeline} class:warn={!!snap && !snap.local.pipeline}>
						<span class="dot" aria-hidden="true"></span>
						{#if !snap}…{:else if snap.local.unsupported}{snap.wsl?.ready ? 'WSL 2 ready' : 'Needs WSL 2'}{:else if snap.local.pipeline}Pipeline found{:else}Pipeline missing{/if}
					</span>
				</button>
				<button type="button" role="radio" class="choice" aria-checked={choice === 'hpc'} onclick={() => (choice = 'hpc')}>
					<span class="c-top">
						<span class="c-icon" aria-hidden="true"><Server size={22} /></span>
						<span class="radio" aria-hidden="true"></span>
					</span>
					<b class="c-name">HPC cluster</b>
					<span class="c-note">Runs jobs on your cluster through SSH.</span>
					<span class="c-state" class:ok={connected} class:now={connecting}>
						<span class="dot" aria-hidden="true"></span>
						{#if connected}Connected{:else if snap?.settings.hpcHost}{snap.settings.hpcHost}{:else}Not set up{/if}
					</span>
				</button>
			</div>

			{#if problem}
				<p class="error" role="alert" transition:fade={{ duration: ui.ms(150) }}><CircleAlert size={16} /> <span>{problem}</span></p>
			{/if}

			<!-- ---- this computer ---- -->
			{#if choice === 'local' && snap}
				<section class="card" in:fade={{ duration: ui.ms(150) }}>
					<header class="card-head"><h2><span class="num"><Monitor size={14} /></span>This computer</h2></header>
					{#if snap.local.unsupported}
						<div class="card-body">
							<p>{snap.local.unsupported}</p>
							{#if snap.wsl}
								<ol class="wsl-steps">
									{#each snap.wsl.steps as st, i (st.id)}
										<li class:ok={st.ok}>
											<span class="num">{#if st.ok}<Check size={13} />{:else}{i + 1}{/if}</span>
											<div>
												<b>{st.label}</b> <span class="hint">{st.detail}</span>
												{#if !st.ok}
													<p class="hint">{st.how.where}:</p>
													<div class="cmd">
														<pre>{st.how.commands.join('\n')}</pre>
														<button type="button" class="mg-icon-btn" aria-label="Copy" onclick={() => copy(st.how.commands.join('\n'))}><Copy size={15} /></button>
													</div>
												{/if}
											</div>
										</li>
									{/each}
								</ol>
								<div class="acts">
									<button type="button" class="mg-btn" disabled={!!busy} onclick={() => load()}>Check again</button>
								</div>
							{/if}
							<div class="acts">
								<button type="button" class="mg-btn primary" onclick={() => (choice = 'hpc')}>Use the HPC cluster</button>
							</div>
						</div>
					{:else if snap.local.pipeline}
						<div class="card-body">
							<div class="fields">
								<div class="field span">
									<span class="label">Pipeline folder</span>
									<span class="value">{snap.local.pipeline}</span>
									<span class="hint">Tools and reference data are installed from the Install page.</span>
								</div>
							</div>
							<div class="acts end">
								<button type="button" class="mg-btn primary big" disabled={!!busy} onclick={openLocal}>Open MARGIE <ArrowRight size={16} /></button>
							</div>
						</div>
					{:else}
						<div class="card-body">
							<p class="status warn"><CircleAlert size={15} /> The pipeline was not found. Looked in {snap.local.looked.join(', ')}.</p>
						</div>
						<!-- The two ways to get the pipeline, side by side. -->
						<div class="halves">
							<div class="card-body sub">
								<h3>Download it</h3>
								<p class="hint">Clones margie-pipeline into <code>{snap.local.looked.find((l) => l.endsWith('margie-pipeline'))}</code>.</p>
								<div class="acts">
									<button type="button" class="mg-btn primary" disabled={snap.local.clone.running || !!busy} onclick={() => act('local-clone', {}, 'clone')}>
										{#if snap.local.clone.running}<LoaderCircle size={15} class="spin" /> Downloading…{:else}Download{/if}
									</button>
								</div>
								{#if snap.local.clone.log.length}
									<div class="logwrap">
										<button type="button" class="mg-link quiet copy-log" onclick={() => copy(snap?.local.clone.log.join('\n') ?? '')}>Copy</button>
										<pre class="log">{snap.local.clone.log.join('\n')}</pre>
									</div>
								{/if}
								{#if snap.local.clone.ok === false}
									<p class="hint warn">Download failed. Check your GitHub access, or use an existing copy.</p>
								{/if}
							</div>
							<form class="card-body sub" onsubmit={(e) => (e.preventDefault(), act('local-use', { dir: pipelineDir }, 'use'))}>
								<h3>Use an existing copy</h3>
								<div class="fields">
									<label class="field span">
										<span class="label">Pipeline folder</span>
										<span class="inline">
											<input class="mg-input mono" bind:value={pipelineDir} placeholder="/path/to/margie-pipeline" spellcheck="false" />
											<button type="submit" class="mg-btn" disabled={!pipelineDir.trim() || !!busy}>Use folder</button>
										</span>
										<span class="hint">The folder that holds <code>annotate.sh</code> and <code>pipeline.conf.sh</code>.</span>
									</label>
								</div>
							</form>
						</div>
					{/if}
				</section>
			{/if}

			<!-- ---- HPC ---- -->
			{#if choice === 'hpc' && snap}
				<!-- Overview of the three steps. -->
				<ol class="steps" aria-label="Steps">
					<li class:done={connected} class:now={!connected}>
						<span class="num">{#if connected}<Check size={14} />{:else}1{/if}</span>
						<span class="s-text"><b>Connection</b><span>{connected ? 'Connected' : connecting ? 'Connecting…' : 'Sign in to the HPC'}</span></span>
					</li>
					<li class:done={keyReady} class:now={connected && !keyReady}>
						<span class="num">{#if keyReady}<Check size={14} />{:else}2{/if}</span>
						<span class="s-text"><b>SSH key</b><span>{keyReady ? 'In use' : 'Optional'}</span></span>
					</li>
					<li class:done={connected && alreadyIn} class:now={connected && !alreadyIn}>
						<span class="num">{#if connected && alreadyIn}<Check size={14} />{:else}3{/if}</span>
						<span class="s-text"><b>MARGIE account</b><span>{connected && alreadyIn ? 'Signed in' : 'Sign in or create one'}</span></span>
					</li>
				</ol>

				<!-- 1. connection -->
				<section class="card" class:done={connected} in:fade={{ duration: ui.ms(150) }}>
					<header class="card-head">
						<h2><span class="num">{#if connected}<Check size={14} />{:else}1{/if}</span>Connection</h2>
						{#if connecting || connected}
							<button type="button" class="mg-btn small" disabled={!!busy} onclick={() => act('hpc-stop', {}, 'stop')}>
								{connecting ? 'Stop' : 'Disconnect'}
							</button>
						{/if}
					</header>

					<div class="card-body">
						{#if hpc?.phase === 'idle' || hpc?.phase === 'failed'}
							<form class="form" onsubmit={(e) => (e.preventDefault(), connect(1))}>
								<div class="fields">
									<label class="field">
										<span class="label">Username</span>
										<input class="mg-input" bind:value={hpcUser} placeholder="jdoe" autocomplete="username" spellcheck="false" required />
									</label>
									<label class="field">
										<span class="label">Host</span>
										<input class="mg-input" bind:value={hpcAddr} placeholder="cluster.university.edu" spellcheck="false" required />
									</label>
								</div>
								<div class="acts">
									<button type="submit" class="mg-btn primary connect" class:going={busy === 'connect' || busy === 'stop'} aria-busy={busy === 'connect' || busy === 'stop'} disabled={!hpcUser.trim() || !hpcAddr.trim() || !backendDir.trim() || !!busy}>
										{#if busy === 'connect' || busy === 'stop'}<LoaderCircle size={15} class="spin" /> Connecting…{:else}Connect{/if}
									</button>
									<span class="hint">Your password and any two-factor prompt are asked for here.</span>
								</div>
							</form>
						{/if}

						{#if hpc && hpc.phase !== 'idle'}
							<ul class="progress-list" aria-live="polite" in:slide={{ duration: ui.ms(220) }}>
								{#each progress as s (s.id)}
									<li class={s.state}>
										<span class="tick" aria-hidden="true">
											{#if s.state === 'done'}<Check size={14} />{:else if s.state === 'now'}<LoaderCircle size={14} class="spin" />{:else if s.state === 'failed'}<CircleAlert size={14} />{/if}
										</span>
										<span class="p-text">{s.label}{#if s.detail && (s.state !== 'done' || s.id === 'code')}<span class="detail" class:stale={/^(Older|Not updated|Could not)/.test(s.detail)}>{s.detail}</span>{/if}</span>
									</li>
								{/each}
							</ul>
						{/if}

						{#if prompt}
							<form class="box" onsubmit={(e) => (e.preventDefault(), send())} transition:fade={{ duration: ui.ms(150) }}>
								<p class="box-label">Prompt from the HPC</p>
								<pre class="asked">{prompt.text.trim()}</pre>
								<div class="inline">
									<input
										bind:this={answerBox}
										class="mg-input"
										type={reveal ? 'text' : 'password'}
										bind:value={answer}
										autocomplete="off"
										aria-label="Your answer"
									/>
									<button type="button" class="mg-icon-btn" aria-label={reveal ? 'Hide' : 'Show'} onclick={() => (reveal = !reveal)}>
										{#if reveal}<EyeOff size={16} />{:else}<Eye size={16} />{/if}
									</button>
									<button type="submit" class="mg-btn primary" disabled={busy === 'answer'}>Send</button>
								</div>
								<p class="hint">Sent to ssh only, not stored. For Duo, enter an option number or a passcode.</p>
							</form>
						{/if}

						{#each hpc?.questions ?? [] as q (q.id)}
							<div class="box" transition:fade={{ duration: ui.ms(150) }}>
								<p class="box-label">Confirm</p>
								<p class="question">{q.text}</p>
								<div class="acts">
									{#each q.choices as c, i (c.value)}
										<button
											type="button"
											class="mg-btn {i === 0 ? 'primary' : ''}"
											disabled={busy === 'reply'}
											onclick={() => act('hpc-reply', { id: q.id, value: c.value }, 'reply')}>{c.label}</button
										>
									{/each}
								</div>
							</div>
						{/each}

						{#if hpc?.phase === 'failed'}
							<p class="error"><CircleAlert size={16} /> <span>{hpc.error}</span></p>
						{/if}
						{#if connected}
							<p class="status ok">
								<Check size={15} /> Connected to {hpc?.node}{hpc?.by === 'terminal' ? ' (started from the terminal)' : ''}.
							</p>
						{/if}
						{#if hpc && hpc.log.length && hpc.phase !== 'idle'}
							<details class="files" open={hpc.phase === 'failed'}>
								<summary>Log</summary>
								<div class="logwrap">
									<button type="button" class="mg-link quiet copy-log" onclick={() => copy(hpc.log.join('\n'))}>Copy</button>
									<pre class="log">{hpc.log.join('\n')}</pre>
								</div>
							</details>
						{:else if hpc?.by === 'terminal' && connecting}
							<p class="hint">Connecting from the terminal; prompts appear there.</p>
						{/if}
					</div>

					{#if hpc?.phase === 'idle' || hpc?.phase === 'failed'}
						<button type="button" class="adv-toggle" aria-expanded={advancedOpen} onclick={() => (advancedOpen = !advancedOpen)}>
							<ChevronRight size={16} class="chev" />
							<span>Advanced settings</span>
							<span class="adv-sum" class:warn={unpushed}>
								{#if unpushed}Backend changes not on GitHub{:else}{backendDir}{/if}
							</span>
						</button>
						{#if advancedOpen}
							<div class="card-body advanced" transition:fade={{ duration: ui.ms(120) }}>
								<div class="fields">
									<label class="field">
										<span class="label">Backend folder on the HPC</span>
										<input
											class="mg-input mono"
											bind:value={backendDir}
											oninput={() => (dirTouched = true)}
											placeholder="/home/jdoe/bioinformatics-tools"
											spellcheck="false"
										/>
										<span class="hint">Cloned from GitHub if it is not there yet.</span>
									</label>

									<div class="field">
										<span class="label">Clean restart</span>
										<span class="hint">Cancels all your SLURM jobs, stops your MARGIE sessions on every login node, and updates the backend before starting it.</span>
										{#if restartOpen}
											<div class="acts">
												<button type="button" class="mg-btn danger" disabled={!hpcUser.trim() || !hpcAddr.trim() || !!busy} onclick={() => connect(2)}>
													Cancel jobs and restart
												</button>
												<button type="button" class="mg-link quiet" onclick={() => (restartOpen = false)}>Keep them</button>
											</div>
										{:else}
											<div class="acts">
												<button type="button" class="mg-btn" disabled={!hpcUser.trim() || !hpcAddr.trim() || !!busy} onclick={() => (restartOpen = true)}>
													Clean restart…
												</button>
											</div>
										{/if}
									</div>

									{#if source}
										<div class="field span">
											<span class="label">Backend code</span>
											<div class="backend-code">
												<div class="code-top">
													<span class="code-id">
														{source.name} | <code>{source.branch}</code>{#if source.target}{' | '}<code>{source.target}</code>{/if}
													</span>
													<button type="button" class="mg-btn small" disabled={checking} onclick={checkGitHub}>{checking ? 'Checking…' : 'Refresh'}</button>
												</div>
												{#if source.local}
													{#if source.onGitHub === false}
														<p class="status warn"><CircleAlert size={15} /> Branch <code>{source.branch}</code> is not on GitHub.</p>
													{:else if source.ahead > 0}
														<p class="status warn"><CircleAlert size={15} /> {source.ahead} local commit{source.ahead === 1 ? '' : 's'} not pushed.</p>
													{:else if source.onGitHub && !source.changes.length}
														<p class="status ok"><Check size={15} /> Up to date on GitHub.</p>
													{/if}
													{#if source.changes.length}
														<div class="status warn">
															<CircleAlert size={15} />
															{source.changes.length} uncommitted change{source.changes.length === 1 ? '' : 's'}.
															<details class="files">
																<summary>Show files</summary>
																<pre class="log">{source.changes.join('\n')}</pre>
															</details>
														</div>
														<div class="inline">
															<input class="mg-input" bind:value={commitMessage} placeholder="Commit message" aria-label="Commit message" />
															<button
																type="button"
																class="mg-btn"
																disabled={!commitMessage.trim() || !!busy}
																onclick={() => act('source-commit', { message: commitMessage }, 'commit').then((r) => r && (commitMessage = ''))}
															>
																{busy === 'commit' ? 'Committing…' : 'Commit and push'}
															</button>
														</div>
													{:else if source.onGitHub === false || source.ahead > 0}
														<div class="acts">
															<button type="button" class="mg-btn" disabled={!!busy} onclick={() => act('source-push', {}, 'push')}>
																{busy === 'push' ? 'Pushing…' : 'Push'}
															</button>
														</div>
													{/if}
													{#if source.behind > 0}
														<p class="hint">GitHub has {source.behind} newer commit{source.behind === 1 ? '' : 's'}; the HPC uses GitHub's version.</p>
													{/if}
													{#if source.note}<p class="hint">GitHub: {source.note}</p>{/if}
												{:else}
													<p class="hint">The HPC gets this branch from GitHub.</p>
												{/if}
											</div>
										</div>
									{/if}
								</div>
							</div>
						{/if}
					{/if}
				</section>

				<!-- 2 and 3, side by side. -->
				<div class="pair">
					<!-- 2. SSH key -->
					<section class="card" class:done={keyReady}>
						<header class="card-head">
							<h2><span class="num">{#if keyReady}<Check size={14} />{:else}2{/if}</span>SSH key</h2>
							<span class="opt">optional</span>
						</header>
						<div class="card-body">
							{#if keyReady}
								<div class="fields">
									<div class="field span">
										<span class="label">Key in use</span>
										<span class="value">{snap.key.path}</span>
										{#if keyNote}<span class="hint">{keyNote}</span>{/if}
									</div>
								</div>
								<div class="acts">
									<button type="button" class="mg-btn" disabled={!!busy} onclick={() => act('key-clear', {}, 'key-clear')}>
										{#if busy === 'key-clear'}<LoaderCircle size={15} class="spin" />{/if} Stop using this key
									</button>
									<span class="hint">The next connection asks for your password again. The key file stays on this computer.</span>
								</div>
							{:else}
								<p class="keywarn">
									Use a key only on a computer that is your own. On a shared or public computer, logging in automatically with a key is at your own
									risk. Always follow your institution's security policies.
								</p>
								<!-- Previously used keys, selectable before connecting. -->
								<form class="fields" onsubmit={(e) => (e.preventDefault(), act('key-use', { path: keyPath }, 'use-key'))}>
									<label class="field span">
										<span class="label">Key file</span>
										<span class="inline">
											<input class="mg-input" bind:value={keyPath} list="recent-keys" spellcheck="false" placeholder="~/.ssh/margie_ed25519" />
											{#if keyPath}<button type="button" class="mg-btn" onclick={() => (keyPath = '')}>Clear</button>{/if}
											<button type="submit" class="mg-btn" disabled={!!busy || !keyPath.trim()}>
												{#if busy === 'use-key'}<LoaderCircle size={15} class="spin" />{/if} Use this key
											</button>
										</span>
										<datalist id="recent-keys">
											{#each recentKeys as k (k)}<option value={k}></option>{/each}
										</datalist>
									</label>
								</form>
								{#if recentKeys.length}
									<div class="recent">
										<span class="label">Used before</span>
										{#each recentKeys as k (k)}
											<button type="button" class="chip-key" class:on={keyPath === k} title="Use {k}" onclick={() => (keyPath = k)}>{k.replace(/^.*\/\.ssh\//, '~/.ssh/')}</button>
										{/each}
										<button type="button" class="mg-link quiet" onclick={() => act('key-forget-recent', {}, 'forget')}>Forget these</button>
									</div>
								{/if}
								{#if connected}
									<p>
										Or let MARGIE make one: a key of its own, <code>~/.ssh/margie_ed25519</code>, added to your <code>authorized_keys</code> on the HPC.
									</p>
									<div class="acts">
										<button type="button" class="mg-btn primary" disabled={!!busy} onclick={setUpKey}>
											{#if busy === 'key'}<LoaderCircle size={15} class="spin" /> Setting up…{:else}Set up key{/if}
										</button>
										<button type="button" class="mg-btn" aria-expanded={manual} onclick={() => (manual = !manual)}>
											{manual ? 'Hide commands' : 'Set up by hand'}
										</button>
									</div>
									{#if manual}
										<div class="manual" transition:fade={{ duration: ui.ms(150) }}>
											<div class="cmd">
												<pre>{manualCommands}</pre>
												<button type="button" class="mg-icon-btn" aria-label="Copy" onclick={() => copy(manualCommands)}><Copy size={15} /></button>
											</div>
										</div>
									{/if}
								{:else}
									<p class="hint">A new key can be set up once you are connected.</p>
								{/if}
							{/if}
						</div>
					</section>

					<!-- 3. account -->
					<section class="card" class:off={!connected}>
						<header class="card-head">
							<h2><span class="num">3</span>MARGIE account</h2>
						</header>
						<div class="card-body">
							{#if !connected}
								<p class="waiting"><UserRound size={18} /><span>Available after connecting.</span></p>
							{:else if alreadyIn}
								<div class="acts">
									<a class="mg-btn primary" href={ui.home()}>Open MARGIE <ArrowRight size={16} /></a>
									<button type="button" class="mg-link quiet" onclick={() => (clearToken(), (alreadyIn = false))}>Use another account</button>
								</div>
							{:else}
								<div class="tabs" role="tablist" aria-label="Account">
									<button type="button" role="tab" aria-selected={accountMode === 'signin'} onclick={() => (accountMode = 'signin')}>Sign in</button>
									<button type="button" role="tab" aria-selected={accountMode === 'create'} onclick={() => (accountMode = 'create')}>Create account</button>
								</div>
								<form class="form" onsubmit={(e) => (e.preventDefault(), accountMode === 'signin' ? signIn() : createAccount())}>
									<div class="fields">
										<label class="field">
											<span class="label">Username</span>
											<input class="mg-input" bind:value={username} autocomplete="username" required />
										</label>
										<label class="field">
											<span class="label">Password</span>
											<input
												class="mg-input"
												type="password"
												bind:value={password}
												autocomplete={accountMode === 'signin' ? 'current-password' : 'new-password'}
												required
											/>
										</label>
										{#if accountMode === 'create'}
											<p class="hint span">
												Separate from your cluster login. Jobs run as <b>{hpcUser}</b>
												{#if keyReady}using the SSH key above.{:else}using an SSH key: set one up above, or paste a private key.{/if}
											</p>
											{#if !keyReady}
												<label class="field span">
													<span class="label">Private key</span>
													<textarea class="mg-input mono" rows="4" bind:value={pastedKey} placeholder="-----BEGIN OPENSSH PRIVATE KEY-----"></textarea>
												</label>
											{/if}
										{/if}
									</div>
									<div class="acts">
										<button type="submit" class="mg-btn primary" disabled={!username || !password || !!busy}>
											{#if busy === 'signin' || busy === 'create'}<LoaderCircle size={15} class="spin" />{/if}
											{accountMode === 'signin' ? 'Sign in' : 'Create account'}
										</button>
									</div>
								</form>
							{/if}
						</div>
					</section>
				</div>
			{/if}

			<p class="foot">
				<Terminal size={14} />
				<span>From a terminal: <code>margie --local</code>, <code>margie --hpc</code>, or <code>./setup.sh --hpc</code>.</span>
			</p>
		</div>
	</main>

	<div class="toasts" aria-live="polite">
		{#each ui.toasts as t (t.id)}
			<div class="toast {t.tone}" transition:fly={{ y: 8, duration: ui.ms(150) }}><span class="toast-dot" aria-hidden="true"></span><span>{t.text}</span></div>
		{/each}
	</div>
</div>

<style>
	/* ---- top bar (matches the interface's) ---- */
	.bar {
		flex-shrink: 0;
		display: flex;
		align-items: center;
		gap: 16px;
		height: 60px;
		padding: 0 16px 0 20px;
		border-bottom: 1px solid var(--mg-border);
		background: var(--cr-bar-bg);
		backdrop-filter: saturate(1.4) blur(12px);
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 9px;
	}
	.word {
		font-size: calc(var(--cr-fs-body) * 1.3);
		font-weight: 700;
		letter-spacing: 0.06em;
	}
	.grow {
		flex-grow: 1;
	}
	.conn {
		display: flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
		height: 36px;
		padding: 0 14px;
		border: 1px solid color-mix(in srgb, var(--mg-ok) 35%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-ok) 8%, var(--mg-surface));
		font-size: var(--cr-fs-meta);
		font-weight: 500;
		color: var(--mg-text-2);
		white-space: nowrap;
	}
	.conn-text {
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.led {
		flex: none;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--mg-ok);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--mg-ok) 20%, transparent);
	}
	.content {
		flex-grow: 1;
		min-height: 0;
		overflow: auto;
		background: var(--mg-bg);
		background-attachment: local;
	}
	/* Full width with the interface's gutter. */
	.page {
		width: 100%;
		max-width: var(--cr-width);
		margin: 0 auto;
		padding: var(--cr-gutter) var(--cr-gutter) calc(var(--cr-gutter) * 3);
		display: flex;
		flex-direction: column;
		gap: var(--cr-gutter);
	}
	.st-head {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		grid-template-areas:
			'title meta'
			'lede lede';
		align-items: center;
		gap: 6px 32px;
		padding: 4px 0 2px;
	}
	code {
		font-family: var(--mg-mono);
		font-size: 0.9em;
		overflow-wrap: anywhere;
	}

	/* ---- target cards ---- */
	.choices {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--cr-gutter);
	}
	.choice {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 6px;
		min-width: 0;
		padding: 22px 24px 20px;
		border: 1px solid var(--mg-border);
		border-radius: calc(var(--mg-r) + 4px);
		background: var(--cr-card);
		box-shadow: var(--cr-card-shadow);
		color: inherit;
		font: inherit;
		text-align: left;
		cursor: pointer;
		transition:
			border-color var(--mo-1) var(--mo-ease),
			box-shadow var(--mo-2) var(--mo-ease),
			transform var(--mo-2) var(--mo-ease);
	}
	.choice:hover {
		border-color: color-mix(in srgb, var(--mg-accent-base) 40%, var(--mg-border));
	}
	.choice[aria-checked='true'] {
		border-color: var(--mg-accent-base);
		background: var(--cr-card);
		box-shadow:
			0 0 0 1px var(--mg-accent-base),
			var(--cr-card-shadow);
	}
	.c-top {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		align-self: stretch;
		margin-bottom: 8px;
	}
	.c-icon {
		display: grid;
		place-items: center;
		width: 48px;
		height: 48px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--mg-accent-base) 12%, var(--mg-surface));
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--mg-accent-base) 25%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent-base));
	}
	.radio {
		width: 22px;
		height: 22px;
		border: 1.5px solid var(--mg-border-strong);
		border-radius: 50%;
		background: var(--mg-surface);
		transition: border-width var(--mo-1) var(--mo-ease);
	}
	.choice[aria-checked='true'] .radio {
		border: 7px solid var(--mg-accent-base);
	}
	.c-name {
		font-size: calc(var(--cr-fs-section) * 1.12);
		font-weight: 700;
		letter-spacing: -0.01em;
	}
	.c-note {
		font-size: var(--cr-fs-meta);
		color: var(--mg-text-2);
	}
	.c-state {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		max-width: 100%;
		margin-top: 8px;
		padding: 4px 12px;
		overflow: hidden;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		font-size: var(--cr-fs-micro);
		font-weight: 600;
		color: var(--mg-text-2);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.c-state .dot {
		flex: none;
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: var(--mg-border-strong);
	}
	.c-state.ok .dot {
		background: var(--mg-ok);
	}
	.c-state.warn .dot {
		background: var(--mg-warn);
	}
	.c-state.now .dot {
		background: var(--mg-accent-base);
	}
	.start[data-motion='off'] :is(.choice, .c-state .dot, .card) {
		animation: none;
		transition: none;
		transform: none;
	}

	/* ---- HPC step overview ---- */
	.steps {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 10px;
		padding: 6px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 4%, var(--mg-surface));
		counter-reset: step;
	}
	.steps li {
		display: flex;
		align-items: center;
		gap: 12px;
		min-width: 0;
		padding: 8px 14px 8px 8px;
		border-radius: var(--mg-r-sm);
		color: var(--mg-text-3);
	}
	.steps li.now {
		background: var(--mg-seg-sel);
		box-shadow:
			var(--mg-shadow-sm),
			0 0 0 1px var(--mg-border);
		color: var(--mg-text);
	}
	.steps li.done {
		color: var(--mg-text);
	}
	.s-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
		line-height: 1.3;
	}
	.s-text b {
		font-size: var(--cr-fs-meta);
		font-weight: 650;
	}
	.s-text span {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--cr-fs-micro);
		color: var(--mg-text-3);
	}
	.steps .now .num {
		border-color: var(--mg-accent-base);
		color: var(--mg-accent-ink, var(--mg-accent-base));
	}

	/* ---- cards (board shape) ---- */
	.card {
		display: flex;
		flex-direction: column;
		min-width: 0;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card);
		box-shadow: var(--cr-card-shadow);
		overflow: hidden;
	}
	.pair {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--cr-gutter);
	}
	.card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		min-height: calc(var(--cr-fs-body) * 3.4);
		padding: 10px 18px;
		border-bottom: 1px solid var(--mg-border);
	}
	.card-head h2 {
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: var(--cr-fs-section);
		font-weight: 650;
	}
	.card-body {
		display: flex;
		flex-direction: column;
		gap: 14px;
		padding: 18px;
	}
	.card-body + .card-body,
	.card-body.sub {
		border-top: 1px solid var(--mg-border);
	}
	/* The two ways of getting the pipeline, side by side. */
	.halves {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
	}
	.halves > .card-body + .card-body {
		border-left: 1px solid var(--mg-border);
	}
	.card.off .card-head h2,
	.card.off .card-body {
		color: var(--mg-text-3);
	}
	.waiting {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		padding: 24px 12px;
		border: 1px dashed var(--mg-border-strong);
		border-radius: var(--mg-r);
		font-size: var(--cr-fs-meta);
		color: var(--mg-text-3);
		text-align: center;
	}
	h3 {
		font-size: var(--cr-fs-body);
		font-weight: 650;
	}
	.num {
		display: inline-grid;
		place-items: center;
		flex: none;
		width: 28px;
		height: 28px;
		border: 1.5px solid var(--mg-border-strong);
		border-radius: 50%;
		background: var(--mg-surface);
		font-size: var(--cr-fs-micro);
		font-weight: 700;
		color: var(--mg-text-2);
	}
	.done .num,
	.steps .done .num {
		border-color: var(--mg-ok);
		background: var(--mg-ok);
		color: var(--mg-surface);
	}
	.opt {
		padding: 2px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		font-size: var(--cr-fs-micro);
		color: var(--mg-text-3);
	}

	/* ---- fields (two equal columns) ---- */
	.form {
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	.fields {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 16px 18px;
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 6px;
		min-width: 0;
	}
	.span {
		grid-column: 1 / -1;
	}
	.label {
		font-size: var(--cr-fs-meta);
		font-weight: 600;
		color: var(--mg-text-2);
	}
	.field > .mg-input,
	.field textarea {
		width: 100%;
	}
	/* A found path, shaped like a field to keep the column even. */
	.value {
		display: flex;
		align-items: center;
		min-height: var(--mg-ctl-sm);
		padding: 6px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: color-mix(in srgb, var(--mg-text) 3%, var(--mg-surface));
		font-family: var(--mg-mono);
		font-size: var(--cr-fs-meta);
		overflow-wrap: anywhere;
	}
	.inline {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.inline .mg-input {
		flex: 1;
		min-width: 0;
	}
	.acts {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 14px;
	}
	.acts.end {
		justify-content: flex-end;
	}
	.mg-btn.big {
		height: calc(var(--mg-ctl-sm) + 6px);
		padding: 0 22px;
		font-size: var(--cr-fs-body);
	}
	.hint {
		font-size: var(--cr-fs-meta);
		color: var(--mg-text-3);
	}
	.hint.warn {
		color: var(--mg-warn);
	}
	.mg-btn.danger {
		border-color: var(--mg-danger);
		color: var(--mg-danger);
	}

	/* ---- advanced settings ---- */
	.adv-toggle {
		display: flex;
		align-items: center;
		gap: 8px;
		min-height: 48px;
		padding: 0 18px;
		border: none;
		border-top: 1px solid var(--mg-border);
		background: color-mix(in srgb, var(--mg-text) 2.5%, transparent);
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--cr-fs-meta);
		font-weight: 600;
		text-align: left;
		cursor: pointer;
	}
	.adv-toggle:hover {
		color: var(--mg-text);
	}
	.adv-toggle :global(.chev) {
		flex-shrink: 0;
		transition: transform var(--mo-1) var(--mo-ease);
	}
	.adv-toggle[aria-expanded='true'] :global(.chev) {
		transform: rotate(90deg);
	}
	.adv-sum {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		text-align: right;
		font-family: var(--mg-mono);
		font-weight: 400;
		color: var(--mg-text-3);
	}
	.adv-sum.warn {
		font-family: inherit;
		color: var(--mg-warn);
	}
	.advanced {
		border-top: 1px solid var(--mg-border);
	}
	.backend-code {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: color-mix(in srgb, var(--mg-text) 3%, var(--mg-surface));
		font-size: var(--cr-fs-meta);
	}
	.code-top {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.code-id {
		flex: 1;
		min-width: 0;
	}
	.status {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 4px 8px;
		font-size: var(--cr-fs-meta);
	}
	.status.ok :global(svg) {
		color: var(--mg-ok);
	}
	.status.warn :global(svg) {
		color: var(--mg-warn);
	}
	.files summary {
		cursor: pointer;
		font-size: var(--cr-fs-meta);
		font-weight: 600;
		color: var(--mg-text-2);
	}
	.status .files {
		flex-basis: 100%;
	}
	/* Log panel: copy button in the top-right corner; dark terminal style in both themes. */
	.logwrap {
		position: relative;
	}
	.copy-log {
		position: absolute;
		top: 14px;
		right: 10px;
		z-index: 1;
		padding: 3px 12px;
		border: 1px solid rgba(255, 255, 255, 0.14);
		border-radius: var(--mg-r-sm);
		background: rgba(255, 255, 255, 0.06);
		color: #c9d1d9 !important;
		font-size: var(--cr-fs-micro);
	}
	.log {
		max-height: 260px;
		overflow: auto;
		margin: 6px 0 0;
		padding: 12px 14px;
		border: 1px solid rgba(255, 255, 255, 0.06);
		border-radius: var(--mg-r);
		background: #14171b;
		font-family: var(--mg-mono);
		font-size: var(--cr-fs-micro);
		line-height: 1.55;
		white-space: pre-wrap;
		color: #e4e8ec;
		scrollbar-color: rgba(255, 255, 255, 0.2) transparent;
	}

	/* ---- connection stages ---- */
	.progress-list {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: 10px;
	}
	.progress-list li {
		display: flex;
		align-items: flex-start;
		gap: 10px;
		min-width: 0;
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-surface);
		font-size: var(--cr-fs-meta);
		color: var(--mg-text-3);
	}
	.progress-list li.done,
	.progress-list li.now {
		color: var(--mg-text);
	}
	.progress-list li.now {
		border-color: color-mix(in srgb, var(--mg-accent-base) 50%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-accent-base) 6%, var(--mg-surface));
	}
	.progress-list li.failed {
		border-color: color-mix(in srgb, var(--mg-danger) 45%, var(--mg-border));
		background: var(--mg-danger-soft);
		color: var(--mg-danger);
	}
	.p-text {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		font-weight: 600;
		line-height: 1.35;
	}
	.tick {
		display: grid;
		place-items: center;
		flex-shrink: 0;
		width: 22px;
		height: 22px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--mg-text) 6%, transparent);
		color: var(--mg-text-3);
	}
	.done > .tick {
		background: var(--mg-ok);
		color: var(--mg-surface);
	}
	.now > .tick {
		background: color-mix(in srgb, var(--mg-accent-base) 14%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent-base));
	}
	.failed > .tick {
		background: var(--mg-danger);
		color: var(--mg-surface);
	}
	.progress-list li:not(.done, .now, .failed) .tick::before {
		content: '';
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: var(--mg-border-strong);
	}
	.detail {
		overflow-wrap: anywhere;
		font-size: var(--cr-fs-micro);
		font-weight: 400;
		color: var(--mg-text-3);
	}
	.box {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 16px;
		border: 1px solid color-mix(in srgb, var(--mg-accent-base) 45%, var(--mg-border));
		border-radius: var(--mg-r);
		background: color-mix(in srgb, var(--mg-accent-base) 5%, var(--mg-surface));
		box-shadow: 0 0 0 4px color-mix(in srgb, var(--mg-accent-base) 8%, transparent);
	}
	.box-label {
		font-size: var(--cr-fs-micro);
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--mg-accent-ink, var(--mg-accent-base));
	}
	.asked {
		margin: 0;
		font-family: var(--mg-mono);
		font-size: var(--cr-fs-meta);
		white-space: pre-wrap;
	}
	.question {
		white-space: pre-line;
	}
	.error {
		display: flex;
		align-items: flex-start;
		gap: 8px;
		padding: 12px 16px;
		border: 1px solid color-mix(in srgb, var(--mg-danger) 45%, var(--mg-border));
		border-radius: var(--mg-r);
		background: var(--mg-danger-soft);
		font-size: var(--cr-fs-meta);
	}
	.error :global(svg) {
		flex-shrink: 0;
		margin-top: 3px;
		color: var(--mg-danger);
	}

	/* ---- key and account ---- */
	/* Connect button while starting: spinner and moving sheen. */
	.connect {
		position: relative;
		overflow: hidden;
		transition: min-width 0.2s ease;
	}
	.connect.going {
		opacity: 1 !important;
		cursor: progress;
	}
	.connect.going::after {
		content: '';
		position: absolute;
		inset: 0;
		background: linear-gradient(100deg, transparent 20%, rgba(255, 255, 255, 0.28) 50%, transparent 80%);
		animation: connect-sheen calc(1.4s * var(--mo-loop, 1)) linear infinite;
	}
	@keyframes connect-sheen {
		from {
			transform: translateX(-100%);
		}
		to {
			transform: translateX(100%);
		}
	}
	.recent {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 6px 8px;
		margin-top: 8px;
	}
	.chip-key {
		padding: 3px 10px;
		border: 1px solid var(--mg-border);
		border-radius: 99px;
		background: var(--mg-surface);
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-xs);
		cursor: pointer;
	}
	.chip-key:hover,
	.chip-key.on {
		border-color: var(--mg-accent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.wsl-steps {
		display: flex;
		flex-direction: column;
		gap: 10px;
		margin: 10px 0;
		list-style: none;
	}
	.wsl-steps li {
		display: flex;
		gap: 10px;
	}
	.wsl-steps li.ok b {
		color: var(--mg-text-2);
	}
	.wsl-steps li.ok .num {
		border-color: var(--mg-ok);
		background: var(--mg-ok);
		color: #fff;
	}
	.wsl-steps b {
		font-weight: 500;
	}
	.wsl-steps .cmd {
		margin-top: 4px;
	}
	.detail.stale {
		color: var(--mg-warn);
	}
	.keywarn {
		padding: 8px 12px;
		border-left: 3px solid var(--mg-warn);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-warn) 8%, transparent);
		color: var(--mg-text-2);
		font-size: var(--mg-fs-xs);
	}
	.manual {
		display: flex;
		flex-direction: column;
		gap: 14px;
	}
	.cmd {
		position: relative;
	}
	.cmd pre {
		margin: 0;
		padding: 12px 48px 12px 14px;
		overflow: auto;
		border-radius: var(--mg-r);
		background: #14171b;
		color: #e4e8ec;
		font-family: var(--mg-mono);
		font-size: var(--cr-fs-micro);
		line-height: 1.6;
	}
	.cmd .mg-icon-btn {
		position: absolute;
		top: 6px;
		right: 6px;
		color: #c9d1d9;
	}
	.cmd .mg-icon-btn:hover {
		background: rgba(255, 255, 255, 0.1);
		color: #fff;
	}
	/* Sign in / create pill tray. */
	.tabs {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 2px;
		padding: 3px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-text) 4%, var(--mg-surface));
	}
	.tabs button {
		height: calc(var(--mg-ctl-sm) - 8px);
		padding: 0 12px;
		border: none;
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--cr-fs-meta);
		font-weight: 500;
		cursor: pointer;
	}
	.tabs button[aria-selected='true'] {
		background: var(--mg-seg-sel);
		box-shadow:
			var(--mg-shadow-sm),
			0 0 0 1px var(--mg-border);
		color: var(--mg-accent-ink, var(--mg-text));
		font-weight: 600;
	}
	.foot {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		font-size: var(--cr-fs-meta);
		color: var(--mg-text-3);
		text-align: center;
	}
	:global(.spin) {
		animation: mg-spin calc(1.1s * var(--mo-loop, 1)) linear infinite;
	}
	.toasts {
		position: fixed;
		right: 18px;
		bottom: 18px;
		z-index: 50;
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 8px;
	}
	.toast {
		display: flex;
		align-items: center;
		gap: 10px;
		max-width: min(440px, calc(100vw - 36px));
		padding: 10px 16px 10px 14px;
		border: 1px solid var(--mg-border);
		border-radius: calc(var(--mg-r) + 4px);
		background: var(--mg-surface);
		box-shadow: var(--cr-pop-shadow);
		font-size: var(--cr-fs-meta);
	}
	.toast-dot {
		flex: none;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--mg-accent-base);
	}
	.toast.ok .toast-dot {
		background: var(--mg-ok);
	}
	.toast.error .toast-dot {
		background: var(--mg-danger);
	}
	@media (max-width: 1100px) {
		.progress-list {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@media (max-width: 860px) {
		.pair,
		.halves {
			grid-template-columns: minmax(0, 1fr);
		}
		.halves > .card-body + .card-body {
			border-left: 0;
			border-top: 1px solid var(--mg-border);
		}
	}
	@media (max-width: 720px) {
		.page {
			padding: 16px 14px 48px;
			gap: 16px;
		}
		.st-head {
			grid-template-columns: minmax(0, 1fr);
			grid-template-areas: 'title' 'lede' 'meta';
		}
		.st-head :global(.cr-lede) {
			padding-left: 0;
		}
		.st-head :global(.cr-meta) {
			justify-self: start;
		}
		.choices,
		.fields,
		.progress-list {
			grid-template-columns: minmax(0, 1fr);
		}
		.steps {
			grid-template-columns: minmax(0, 1fr);
			border-radius: calc(var(--mg-r) + 8px);
		}
		.conn-text {
			display: none;
		}
	}
</style>
