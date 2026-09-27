<script lang="ts">
	import { onMount } from 'svelte';
	import { Database } from 'lucide-svelte';
	import { formatBytes } from '$lib/api';
	import Fold from './motion/Fold.svelte';
	import FoldTitle from './motion/FoldTitle.svelte';
	import FoldToggle from './motion/FoldToggle.svelte';
	import ProgressBar from './ProgressBar.svelte';
	import QueueWait from './blocks/QueueWait.svelte';
	import { ws, type BackupCheck, type StoreOp } from './data.svelte';
	import { ui } from './ui.svelte';

	/**
	 * Settings card for the user's cluster databases: working copy, newest depot backup,
	 * and a "Back up to depot" action that asks first (api/services/user_stores.py).
	 */

	onMount(() => {
		ws.loadStores();
	});

	let asking = $state<BackupCheck | null>(null);
	let checking = $state('');

	async function ask(id: string) {
		checking = id;
		try {
			asking = await ws.checkBackup(id);
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		} finally {
			checking = '';
		}
	}

	async function yes() {
		const id = asking?.id;
		asking = null;
		if (id) await ws.backupStore(id);
	}

	const st = $derived(ws.stores);
	const op = $derived(ws.storesOp);
	const busy = $derived(ws.storesBusy);
	const gb = (n: number | null) => (n === null ? 'unknown' : formatBytes(n));

	/** Describes the copy for the progress bar. */
	function opLabel(o: StoreOp) {
		if (o.state === 'queued') return 'Waiting for a SLURM slot';
		const what = o.op?.startsWith('backup:') ? 'Backing up' : o.op === 'assets' ? 'Setting up tools and reference data' : 'Setting up your databases';
		return o.label && o.label !== 'Starting' && o.label !== 'Finished' ? `${what}: ${o.label}` : what;
	}
</script>

<section class="db-card" id="databases" data-shade="folders">
	<header class="db-head">
		<span class="db-ico" aria-hidden="true"><Database size={16} /></span>
		<FoldTitle id="settings:databases" class="db-title">Your databases</FoldTitle>
		<span class="db-where" title={st?.root}>{st ? (st.ready ? `in ${st.root}` : 'not set up yet') : ''}</span>
		<span class="mg-grow"></span>
		<FoldToggle id="settings:databases" />
	</header>
	<Fold id="settings:databases">
		<div class="db-body">
			<p class="mg-note lede">
				The databases every run reads and adds to. Each person works on their own copy, in the working folder below, made from
				the base copies on depot the first time; a backup puts a copy of yours back on depot, beside the bases.
			</p>

			{#if op && (busy || op.state === 'failed')}
				<ProgressBar
					percent={op.percent}
					state={op.state}
					label={opLabel(op)}
					detail={op.state === 'failed'
						? op.message || 'The copy did not finish.'
						: op.job
							? `SLURM job ${op.job}`
							: ''}
					log={[...(op.log ?? []), ...(op.slurm_out ?? [])]}
				/>
				<QueueWait {op} onchange={(o) => (ws.storesOp = o)} />
			{/if}

			{#if st && !st.ready && !busy}
				<div class="setup">
					<span>Your databases are copied here once, before your first run: from your newest backup if you have one, otherwise from the base copies.</span>
					<button type="button" class="mg-btn small primary" onclick={() => ws.setupStores()}>Set them up now</button>
				</div>
			{/if}

			{#if st}
				<ul class="stores">
					{#each st.stores as s (s.id)}
						<li class="store">
							<div class="name">
								<b>{s.label}</b>
								<span class="mg-note">{s.note}</span>
							</div>
							<div class="where">
								{#if s.version}
									<span>Working copy <b class="ver">v{s.version}</b></span>
									<span class="mg-mono path" title={s.path}>{s.path}</span>
								{:else}
									<span class="mg-note">Not set up yet</span>
								{/if}
								<span class="mg-note">
									{s.backup ? `Newest backup: v${s.backup.version} on depot` : 'No backup yet'}{s.backups > 1 ? ` (${s.backups} kept)` : ''}
								</span>
							</div>
							<div class="act">
								<button
									type="button"
									class="mg-btn small"
									disabled={!s.version || busy || checking !== ''}
									title={s.version ? 'Copy this database to depot' : 'Set it up first'}
									onclick={() => ask(s.id)}
								>
									{checking === s.id ? 'Checking…' : 'Back up to depot'}
								</button>
							</div>
							{#if asking?.id === s.id}
								<div class="ask" role="alertdialog" aria-label="Back up {s.label}">
									{#if asking.fits}
										<p>
											Back up <b>{asking.label} v{asking.version}</b> ({gb(asking.size)}) to depot? Depot has <b>{gb(asking.free)}</b> free.
											Your working copy becomes v{asking.version + 1}; nothing is deleted.
										</p>
										<p class="mg-note mg-mono target" title={asking.target}>{asking.target}</p>
										<div class="ask-btns">
											<button type="button" class="mg-btn small primary" onclick={yes}>Yes, back it up</button>
											<button type="button" class="mg-btn small" onclick={() => (asking = null)}>No</button>
										</div>
									{:else}
										<p class="no-room">
											It would not fit: {asking.label} v{asking.version} is {gb(asking.size)} and depot has {gb(asking.free)} free (5 GB is
											kept spare for everyone). Free some space on depot, or change the backup location in the Folders section.
										</p>
										<div class="ask-btns">
											<button type="button" class="mg-btn small" onclick={() => (asking = null)}>No</button>
										</div>
									{/if}
								</div>
							{/if}
						</li>
					{/each}
				</ul>
			{:else}
				<p class="mg-note">Reading where your databases are…</p>
			{/if}
		</div>
	</Fold>
</section>

<style>
	.db-card {
		display: flex;
		flex-direction: column;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: color-mix(in srgb, var(--mg-surface-2) 70%, transparent);
		overflow: hidden;
	}
	.db-head {
		display: flex;
		align-items: center;
		gap: 10px;
		min-width: 0;
		padding: 12px var(--mg-pad);
	}
	.db-ico {
		display: grid;
		place-items: center;
		flex: none;
		width: 30px;
		height: 30px;
		border-radius: 9px;
		background: color-mix(in srgb, var(--mg-accent) 16%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.db-head :global(.db-title) {
		margin: 0;
		font-size: var(--mg-fs-lg);
		font-weight: 650;
		line-height: 1.2;
	}
	.db-where {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.db-body {
		display: flex;
		flex-direction: column;
		gap: 14px;
		padding: 14px var(--mg-pad) var(--mg-pad);
		border-top: 1px solid var(--mg-border);
	}
	.lede {
		margin: 0;
		max-width: 90ch;
	}
	.setup {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 10px 16px;
		padding: 10px 14px;
		border: 1px solid color-mix(in srgb, var(--mg-accent) 40%, var(--mg-border));
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-accent) 7%, var(--mg-surface));
		font-size: var(--mg-fs-sm);
	}
	.setup span {
		flex: 1 1 32ch;
	}
	/* One tile per database in even columns. */
	.stores {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
		gap: 10px;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.store {
		display: flex;
		flex-direction: column;
		gap: 10px;
		min-width: 0;
		padding: 12px 14px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		font-size: var(--mg-fs-sm);
	}
	.name,
	.where {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.ver {
		display: inline-block;
		padding: 0 7px;
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-accent) 14%, transparent);
		color: var(--mg-accent-ink, var(--mg-accent));
		font-size: var(--mg-fs-xs);
	}
	.path {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-2);
	}
	.act {
		margin-top: auto;
	}
	.ask {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 10px 12px;
		border: 1px solid var(--mg-border-strong);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface-2);
	}
	.ask p {
		margin: 0;
	}
	.target {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--mg-fs-xs);
	}
	.no-room {
		color: var(--mg-warn);
	}
	.ask-btns {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}
</style>
