<script lang="ts">
	/**
	 * Sign-in for the hosted site (lib/hosted.ts): MARGIE's own look, one card.
	 * Signs in to the cluster API, or creates an account there with the cluster
	 * login and SSH key the API will use; then opens the interface.
	 */
	import '@fontsource/ibm-plex-sans/400.css';
	import '@fontsource/ibm-plex-sans/500.css';
	import '@fontsource/ibm-plex-sans/600.css';
	import '@fontsource/ibm-plex-sans/700.css';
	import '@fontsource/ibm-plex-mono/400.css';
	import '$lib/workspace/workspace.css';
	import '$lib/crisp/crisp.css';
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';
	import { CircleAlert, LoaderCircle, Server } from 'lucide-svelte';
	import CrispMark from '$lib/crisp/CrispMark.svelte';
	import Corner from '$lib/workspace/Corner.svelte';
	import SizeSliders from '$lib/workspace/SizeSliders.svelte';
	import { crispVars } from '$lib/crisp/theme';
	import { isLoggedIn, setToken } from '$lib/auth';
	import { getApiUrl } from '$lib/config';
	import { styleString } from '$lib/workspace/prefs';
	import { ui } from '$lib/workspace/ui.svelte';

	let mode = $state<'signin' | 'create'>('signin');
	let username = $state('');
	let password = $state('');
	let clusterHost = $state('');
	let clusterUser = $state('');
	let privateKey = $state('');
	let busy = $state(false);
	let problem = $state('');

	onMount(() => {
		if (isLoggedIn()) {
			ui.restore();
			location.replace(ui.home());
			return;
		}
		ui.restore();
		const dark = matchMedia('(prefers-color-scheme: dark)');
		ui.systemDark = dark.matches;
		const onDark = (e: MediaQueryListEvent) => (ui.systemDark = e.matches);
		dark.addEventListener('change', onDark);
		return () => dark.removeEventListener('change', onDark);
	});

	// FastAPI sends a string for handled errors and a list for validation errors.
	function describe(detail: unknown, fallback: string): string {
		if (typeof detail === 'string') return detail;
		if (Array.isArray(detail)) return detail.map((d) => `${d?.loc?.at(-1) ?? 'field'}: ${d?.msg ?? 'invalid'}`).join('; ');
		return fallback;
	}

	async function signIn() {
		const res = await fetch(`${getApiUrl()}/v1/auth/login`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ username, password })
		});
		if (res.status === 401) throw new Error('Wrong username or password.');
		if (!res.ok) throw new Error(describe((await res.json().catch(() => ({}))).detail, `Could not sign in (${res.status}).`));
		setToken((await res.json()).access_token);
		ui.restore();
		location.assign(ui.home());
	}

	async function createAccount() {
		const res = await fetch(`${getApiUrl()}/v1/auth/register`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ username, password, cluster_host: clusterHost.trim(), cluster_username: clusterUser.trim(), private_key: privateKey })
		});
		if (!res.ok) throw new Error(describe((await res.json().catch(() => ({}))).detail, `Could not create the account (${res.status}).`));
		// Registration also checks that SSH to the cluster works, so signing in follows at once.
		await signIn();
	}

	async function submit(e: Event) {
		e.preventDefault();
		busy = true;
		problem = '';
		try {
			if (mode === 'signin') await signIn();
			else await createAccount();
		} catch (e) {
			problem = e instanceof TypeError ? `Can't reach the server at ${getApiUrl() || location.origin}.` : e instanceof Error ? e.message : String(e);
		} finally {
			busy = false;
		}
	}

	const canSubmit = $derived(!!username && !!password && (mode === 'signin' || (!!clusterHost.trim() && !!clusterUser.trim() && !!privateKey.trim())));
	const vars = $derived(styleString(crispVars(ui.prefs, ui.dark)) + '; --cr-page: var(--mg-accent); ' + ui.motionStyle);
</script>

<svelte:head><title>Sign in | MARGIE</title></svelte:head>

<div class="crisp signin" data-mg-root data-theme={ui.dark ? 'dark' : 'light'} data-motion={ui.motion} style={vars}>
	<header class="bar">
		<span class="brand"><CrispMark size={22} /><span class="word">MARGIE</span></span>
		<span class="grow"></span>
		<Corner base="crisp" account={false}>
			{#snippet customize()}
				<SizeSliders />
			{/snippet}
		</Corner>
	</header>

	<main class="content">
		<div class="page">
			<header class="st-head">
				<h1 class="cr-title">{mode === 'signin' ? 'Sign in' : 'New account'}</h1>
				<p class="cr-lede">Sign in to run MARGIE on your cluster.</p>
			</header>

			<section class="card">
				<header class="card-head"><h2><span class="num"><Server size={14} /></span>Account</h2></header>
				<div class="card-body">
					<div class="tabs" role="tablist" aria-label="Account">
						<button type="button" role="tab" aria-selected={mode === 'signin'} onclick={() => (mode = 'signin')}>Sign in</button>
						<button type="button" role="tab" aria-selected={mode === 'create'} onclick={() => (mode = 'create')}>Create account</button>
					</div>

					{#if problem}
						<p class="error" role="alert" transition:fade={{ duration: ui.ms(150) }}><CircleAlert size={16} /> <span>{problem}</span></p>
					{/if}

					<form class="form" onsubmit={submit}>
						<div class="fields">
							<label class="field">
								<span class="label">Username</span>
								<input class="mg-input" bind:value={username} autocomplete="username" spellcheck="false" required />
							</label>
							<label class="field">
								<span class="label">Password</span>
								<input class="mg-input" type="password" bind:value={password} autocomplete={mode === 'signin' ? 'current-password' : 'new-password'} required />
							</label>
							{#if mode === 'create'}
								<p class="hint span">This is your MARGIE login. Jobs run on the cluster under the cluster account below.</p>
								<label class="field">
									<span class="label">Cluster address</span>
									<input class="mg-input" bind:value={clusterHost} placeholder="negishi.rcac.purdue.edu" spellcheck="false" required />
								</label>
								<label class="field">
									<span class="label">Cluster username</span>
									<input class="mg-input" bind:value={clusterUser} placeholder="jdoe" autocomplete="off" spellcheck="false" required />
								</label>
								<label class="field span">
									<span class="label">SSH private key</span>
									<textarea class="mg-input mono" rows="5" bind:value={privateKey} placeholder="-----BEGIN OPENSSH PRIVATE KEY-----" spellcheck="false" required></textarea>
									<span class="hint">Paste a private key whose public key is already in ~/.ssh/authorized_keys on the cluster. It is stored encrypted.</span>
								</label>
							{/if}
						</div>
						<div class="acts">
							<button type="submit" class="mg-btn primary" disabled={!canSubmit || busy}>
								{#if busy}<LoaderCircle size={15} class="spin" />{/if}
								{mode === 'signin' ? 'Sign in' : 'Create account'}
							</button>
						</div>
					</form>
				</div>
			</section>

			<p class="foot">Want to run MARGIE on your own computer? Get the desktop app, or use the <code>margie</code> command.</p>
		</div>
	</main>
</div>

<style>
	.signin {
		display: flex;
		flex-direction: column;
		height: 100vh;
		height: 100dvh;
		color: var(--mg-text);
		font-family: var(--mg-font);
		font-size: var(--cr-fs-body);
	}
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
	.content {
		flex-grow: 1;
		min-height: 0;
		overflow: auto;
		background: var(--mg-bg);
	}
	.page {
		width: 100%;
		max-width: 560px;
		margin: 0 auto;
		padding: calc(var(--cr-gutter) * 2) var(--cr-gutter) calc(var(--cr-gutter) * 3);
		display: flex;
		flex-direction: column;
		gap: var(--cr-gutter);
	}
	.st-head {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding: 4px 0 2px;
	}
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
	.card-head {
		display: flex;
		align-items: center;
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
	.num {
		display: grid;
		place-items: center;
		width: 26px;
		height: 26px;
		border-radius: 50%;
		background: color-mix(in srgb, var(--mg-accent-base) 12%, var(--mg-surface));
		color: var(--mg-accent-ink, var(--mg-accent-base));
	}
	.card-body {
		display: flex;
		flex-direction: column;
		gap: 14px;
		padding: 18px;
	}
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
	.hint {
		font-size: var(--cr-fs-meta);
		color: var(--mg-text-3);
	}
	.acts {
		display: flex;
		justify-content: flex-end;
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
	.foot {
		text-align: center;
		font-size: var(--cr-fs-meta);
		color: var(--mg-text-3);
	}
	code {
		font-family: var(--mg-mono);
		font-size: 0.9em;
	}
	:global(.spin) {
		animation: spin 0.8s linear infinite;
	}
	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}
	@media (max-width: 520px) {
		.fields {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
