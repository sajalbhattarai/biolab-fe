<script lang="ts">
	import { Cpu, Server, X } from 'lucide-svelte';
	import { goto } from '$app/navigation';
	import { fly } from 'svelte/transition';
	import { ui } from '$lib/workspace/ui.svelte';

	/**
	 * Header toggle (HPC mode) for where MARGIE's server runs: the login node or
	 * a compute node (a SLURM job with the chosen resources). Applies on the next
	 * connection; "Save and reconnect" applies it now.
	 */
	type S = { compute: string; computeCpus: string; computeMemGb: string; computeHours: string; computePartition: string; computeAccount: string };
	let s = $state<S | null>(null);
	let open = $state(false);
	let saving = $state(false);
	let problem = $state('');
	let form = $state({ compute: false, cpus: 4, memGb: 16, hours: 8, partition: '', account: '' });

	/** Loads the saved compute settings from /api/connect into the form. */
	async function load() {
		try {
			const r = await fetch('/api/connect');
			if (!r.ok) return;
			s = (await r.json()).settings as S;
			form = {
				compute: s.compute === '1',
				cpus: Number(s.computeCpus) || 4,
				memGb: Number(s.computeMemGb) || 16,
				hours: Number(s.computeHours) || 8,
				partition: s.computePartition ?? '',
				account: s.computeAccount ?? ''
			};
		} catch {
			// The app's server is restarting; the button waits.
		}
	}
	$effect(() => {
		load();
	});

	/** Saves the compute choice and optionally reconnects. */
	async function save(reconnect: boolean) {
		saving = true;
		problem = '';
		try {
			const r = await fetch('/api/connect', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ action: 'compute-set', ...form })
			});
			if (!r.ok) {
				problem = (await r.json().catch(() => ({}))).message ?? `Could not save (${r.status}).`;
				return;
			}
			await load();
			open = false;
			if (reconnect) goto('/start?reconnect=1');
			else ui.notify('Saved. It applies the next time MARGIE connects to the HPC.', 'ok');
		} finally {
			saving = false;
		}
	}

	const label = $derived(s?.compute === '1' ? `Compute node | ${s.computeCpus || 4} cores, ${s.computeMemGb || 16} GB` : 'Login node');
</script>

<div class="ct">
	<button type="button" class="ct-btn" class:on={s?.compute === '1'} aria-expanded={open} title="Where MARGIE's server runs on the HPC" onclick={() => (open = !open)}>
		{#if s?.compute === '1'}<Cpu size={15} />{:else}<Server size={15} />{/if}
		<span>{label}</span>
	</button>
	{#if open}
		<div class="ct-pop" role="dialog" aria-label="Where MARGIE runs on the HPC" transition:fly={{ y: -6, duration: ui.ms(160) }}>
			<header>
				<h2>Where MARGIE runs on the HPC</h2>
				<button type="button" class="ct-x" aria-label="Close" onclick={() => (open = false)}><X size={16} /></button>
			</header>
			<div class="ct-choice" role="radiogroup" aria-label="Where MARGIE runs">
				<label class:on={!form.compute}>
					<input type="radio" name="ct-where" checked={!form.compute} onchange={() => (form.compute = false)} />
					<span><b>Login node</b> (default). Quick to start. Shared with other users, so heavy work there leaves less for them.</span>
				</label>
				<label class:on={form.compute}>
					<input type="radio" name="ct-where" checked={form.compute} onchange={() => (form.compute = true)} />
					<span><b>Compute node</b>. A SLURM job with the cores and memory you choose. May wait in the queue first.</span>
				</label>
			</div>
			{#if form.compute}
				<div class="ct-grid">
					<label><span>Cores</span><input class="mg-input" type="number" min="1" max="256" bind:value={form.cpus} /></label>
					<label><span>Memory (GB)</span><input class="mg-input" type="number" min="1" max="4096" bind:value={form.memGb} /></label>
					<label><span>Hours</span><input class="mg-input" type="number" min="1" max="336" bind:value={form.hours} /></label>
					<label><span>Partition</span><input class="mg-input" bind:value={form.partition} placeholder="cluster default" spellcheck="false" /></label>
					<label class="wide"><span>Account</span><input class="mg-input" bind:value={form.account} placeholder="cluster default" spellcheck="false" /></label>
				</div>
				<p class="ct-note">
					If the job waits in the queue, MARGIE says why and asks whether to use the login node instead. Annotation runs go to SLURM either way.
				</p>
			{/if}
			<p class="ct-note">Follow your institution's policy on what may run on login nodes.</p>
			{#if problem}<p class="ct-note bad">{problem}</p>{/if}
			<div class="ct-acts">
				<button type="button" class="mg-btn" disabled={saving} onclick={() => save(false)}>Save</button>
				<button type="button" class="mg-btn primary" disabled={saving} onclick={() => save(true)}>Save and reconnect</button>
			</div>
		</div>
	{/if}
</div>

<style>
	.ct {
		position: relative;
	}
	.ct-btn {
		display: inline-flex;
		align-items: center;
		gap: 7px;
		height: 32px;
		padding: 0 12px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		background: var(--mg-surface);
		color: var(--mg-text-2);
		font: inherit;
		font-size: var(--mg-fs-xs);
		white-space: nowrap;
		cursor: pointer;
	}
	.ct-btn:hover {
		color: var(--mg-text);
		border-color: var(--mg-border-strong);
	}
	.ct-btn.on {
		border-color: color-mix(in srgb, var(--mg-accent) 45%, var(--mg-border));
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.ct-pop {
		position: absolute;
		top: calc(100% + 8px);
		right: 0;
		z-index: 40;
		display: flex;
		flex-direction: column;
		gap: 12px;
		width: min(420px, 90vw);
		padding: 14px 16px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r);
		background: var(--mg-surface);
		box-shadow: var(--cr-pop-shadow, var(--mg-shadow-lg));
		font-size: var(--mg-fs-sm);
		-webkit-app-region: no-drag;
	}
	header {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}
	h2 {
		font-size: var(--mg-fs);
		font-weight: 500;
		color: var(--cr-t2, var(--mg-text));
	}
	.ct-x {
		display: grid;
		place-items: center;
		width: 26px;
		height: 26px;
		border: none;
		border-radius: var(--mg-r-sm);
		background: none;
		color: var(--mg-text-3);
		cursor: pointer;
	}
	.ct-choice {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.ct-choice label {
		display: flex;
		gap: 10px;
		padding: 8px 10px;
		border: 1px solid var(--mg-border);
		border-radius: var(--mg-r-sm);
		color: var(--mg-text-2);
		cursor: pointer;
	}
	.ct-choice label.on {
		border-color: color-mix(in srgb, var(--mg-accent) 50%, var(--mg-border));
		background: color-mix(in srgb, var(--mg-accent) 6%, transparent);
	}
	.ct-choice b {
		font-weight: 500;
		color: var(--mg-text);
	}
	.ct-grid {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 8px;
	}
	.ct-grid label {
		display: flex;
		flex-direction: column;
		gap: 4px;
		font-size: var(--mg-fs-xs);
		color: var(--cr-t4, var(--mg-text-2));
	}
	.ct-grid .wide {
		grid-column: span 2;
	}
	.ct-note {
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-3);
	}
	.ct-note.bad {
		color: var(--mg-danger);
	}
	.ct-acts {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
	}
</style>
