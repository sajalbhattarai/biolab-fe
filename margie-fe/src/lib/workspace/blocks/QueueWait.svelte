<script lang="ts">
	import { post } from '$lib/api';
	import { ui } from '$lib/workspace/ui.svelte';
	import type { StoreOp } from '$lib/workspace/data.svelte';

	/**
	 * Shown on an HPC while a copy job is pending in SLURM: explains the wait and offers to run it
	 * on the login node instead.
	 */
	let { op, onchange }: { op: StoreOp; onchange?: (op: StoreOp | null) => void } = $props();
	let going = $state(false);

	const REASONS: Record<string, string> = {
		Resources: 'the cluster is busy: no node has the room yet',
		Priority: 'jobs with higher priority are ahead of it',
		QOSMaxJobsPerUserLimit: 'you already have as many jobs running as your account allows',
		AssocGrpCpuLimit: "your group's share of cores is in use",
		ReqNodeNotAvail: 'the nodes it needs are unavailable (maintenance?)',
		BeginTime: 'it is set to start later'
	};
	const why = $derived(op.slurm_reason ? (REASONS[op.slurm_reason] ?? op.slurm_reason) : '');

	async function runHere() {
		if (
			!confirm(
				"Run this copy on the login node instead of waiting?\n\nThe login node is shared with other users. Follow your institution's policy on what may run there."
			)
		)
			return;
		going = true;
		try {
			const d = await post<{ op: StoreOp | null }>('/stores/run-here');
			onchange?.(d.op);
			ui.notify('The copy is running on the login node.', 'ok');
		} catch (e) {
			ui.notify(e instanceof Error ? e.message : String(e), 'error');
		} finally {
			going = false;
		}
	}
</script>

{#if op.state === 'queued' && op.slurm_state === 'PENDING'}
	<div class="qw">
		<span>Waiting in the SLURM queue{why ? `: ${why}` : ''}.</span>
		<button type="button" class="mg-btn small" disabled={going} onclick={runHere}>{going ? 'Starting…' : 'Run on the login node instead'}</button>
	</div>
{/if}

<style>
	.qw {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 14px;
		margin-top: 8px;
		padding: 8px 12px;
		border-left: 3px solid var(--mg-warn);
		border-radius: var(--mg-r-sm);
		background: color-mix(in srgb, var(--mg-warn) 7%, transparent);
		font-size: var(--mg-fs-xs);
		color: var(--mg-text-2);
	}
</style>
