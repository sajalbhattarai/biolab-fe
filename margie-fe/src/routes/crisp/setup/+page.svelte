<script lang="ts">
	import { Lock } from 'lucide-svelte';
	import InstallBoard from '$lib/crisp/InstallBoard.svelte';
	import { backend } from '$lib/workspace/backend.svelte';
	import { ws } from '$lib/workspace/data.svelte';
	import { installLock } from '$lib/workspace/install-lock.svelte';
	import { INSTALL_STATEMENT } from '$lib/workspace/install-statement';

	/** Install page, locked until the install statement is typed for this computer or cluster account. */
	$effect(() => {
		if (installLock.place) installLock.check();
	});

	let password = $state('');
	let wrong = $state('');
	let trying = $state(false);
	const where = $derived(backend.cluster ? (installLock.place ? `for ${installLock.place}` : 'for this account') : 'on this computer');

	async function unlock(e: SubmitEvent) {
		e.preventDefault();
		if (!password || trying) return;
		trying = true;
		wrong = await installLock.unlock(password);
		trying = false;
		if (!wrong) password = '';
	}
</script>

<svelte:head><title>Install | MARGIE</title></svelte:head>

<div class="cr-page" data-shade="page-setup">
	<div class="cr-head">
		<h1 class="cr-title">Install</h1>
		<p class="cr-lede">
			{#if !installLock.unlocked}
				Installing sets up tools under their own licences, so it opens once you confirm the statement below; it then stays open {where}.
			{:else if backend.cluster}
				What your cluster account needs before a run: a connection, a SLURM account and the licence terms. Tools and databases are
				installed by the cluster's administrators.
			{:else}
				What this computer needs before a run: a container app, the tools' images and their reference data. Folders and resource limits
				are in <a class="mg-link" href="/crisp/settings">Settings</a>.
			{/if}
		</p>
		<span class="cr-meta">{installLock.unlocked && ws.overview ? `${ws.setupReady.ok} of ${ws.setupReady.total} ready` : ''}</span>
	</div>

	{#if installLock.unlocked}
		<InstallBoard />
	{:else if !installLock.known}
		<p class="mg-note">Checking…</p>
	{:else}
		<form class="lock" onsubmit={unlock}>
			<span class="lock-ic" aria-hidden="true"><Lock size={22} strokeWidth={1.75} /></span>
			<h2>Before installing</h2>
			<p class="mg-note">Type this statement exactly as shown to confirm it (pasting is not allowed):</p>
			<blockquote class="lock-statement" oncopy={(e) => e.preventDefault()}>{INSTALL_STATEMENT}</blockquote>
			<div class="lock-row">
				<input
					class="mg-input"
					type="text"
					autocomplete="off"
					spellcheck="false"
					placeholder="Type the statement"
					aria-label="Install statement"
					bind:value={password}
					oninput={() => (wrong = '')}
					onpaste={(e) => e.preventDefault()}
					ondrop={(e) => e.preventDefault()}
				/>
				<button class="mg-btn primary" type="submit" disabled={!password || trying}>{trying ? 'Checking' : 'Agree and unlock'}</button>
			</div>
			{#if wrong}<p class="lock-wrong" role="alert">{wrong}</p>{/if}
		</form>
	{/if}
</div>

<style>
	.lock-statement {
		margin: 0;
		padding: 10px 14px;
		border-left: 3px solid var(--mg-accent);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-accent) 6%, transparent);
		color: var(--mg-text);
		text-align: left;
		user-select: none;
		-webkit-user-select: none;
	}
	.lock {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 10px;
		width: min(100%, 640px);
		margin: calc(var(--mg-gap) * 2) auto 0;
		padding: calc(var(--mg-gap) * 2.5) calc(var(--mg-gap) * 2);
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--cr-card, var(--mg-surface));
		text-align: center;
	}
	.lock-ic {
		display: grid;
		place-items: center;
		width: 48px;
		height: 48px;
		border-radius: 12px;
		background: color-mix(in srgb, var(--mg-accent) 12%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	h2 {
		margin: 4px 0 0;
		font-size: var(--mg-fs-lg);
		font-weight: 650;
	}
	.lock-row {
		display: flex;
		gap: 8px;
		width: 100%;
		margin-top: 6px;
	}
	.lock-row input {
		flex: 1;
		min-width: 0;
	}
	.lock-wrong {
		margin: 0;
		font-size: var(--mg-fs-sm);
		color: var(--mg-danger, var(--mg-warn));
	}
</style>
