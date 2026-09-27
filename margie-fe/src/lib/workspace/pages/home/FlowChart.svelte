<script lang="ts">
	import { Database, Dna, FileText, Gauge, Network, RefreshCw, ScanSearch } from 'lucide-svelte';

	/**
	 * Six-step genome-to-report flow following margie_sb.smk's phases: icon, name and description.
	 * No tools are named, since several are licence-gated and optional.
	 */
	const STEPS = [
		{ id: 'genome', icon: Dna, title: 'Your genome', text: 'An assembled genome, as a FASTA file.' },
		{ id: 'know', icon: ScanSearch, title: 'Know it', text: 'Check the assembly, place it in the tree of life and find its genes.' },
		{ id: 'annotate', icon: Database, title: 'Ask many tools', text: 'Compare every protein with a range of reference databases.' },
		{ id: 'cell', icon: Network, title: 'Place it in the cell', text: 'Group genes into operons and predict where each protein sits.' },
		{ id: 'score', icon: Gauge, title: 'Name and score', text: 'Merge the evidence into one name per gene, with a confidence.' },
		{ id: 'report', icon: FileText, title: 'Compare and report', text: 'Compare with related genomes; write the map and the table.' }
	];
</script>

<ol class="flow">
	{#each STEPS as s, i (s.id)}
		<li class="step" style="--i: {i}">
			<span class="icon"><s.icon size={19} strokeWidth={1.75} /></span>
			<span class="n">Step {i + 1}</span>
			<h3>{s.title}</h3>
			<p>{s.text}</p>
		</li>
	{/each}
</ol>
<p class="reuse">
	<RefreshCw size={16} strokeWidth={2} />
	A genome or protein MARGIE has annotated before is reused, not run again.
</p>

<style>
	.flow {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(6, minmax(0, 1fr));
		gap: 14px;
	}
	.step {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		text-align: center;
		animation: rise 300ms ease-out both;
		animation-delay: calc(var(--i) * 70ms);
	}
	/* Connector line to the next step. */
	.step:not(:last-child)::after {
		content: '';
		position: absolute;
		top: 21px;
		left: calc(50% + 30px);
		width: calc(100% - 60px + 14px);
		height: 1px;
		background: var(--mg-border-strong);
	}
	.icon {
		display: grid;
		place-items: center;
		width: 42px;
		height: 42px;
		margin-bottom: 4px;
		border: 1px solid var(--mg-border);
		border-radius: 12px;
		background: var(--mg-surface);
		color: var(--mg-accent-ink, var(--mg-accent));
	}
	.n {
		font-size: var(--mg-fs-xs);
		font-weight: 600;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--mg-text-3);
	}
	h3 {
		margin: 0;
		font-size: var(--mg-fs-sm);
		font-weight: 650;
		color: var(--mg-text);
	}
	p {
		margin: 0;
		font-size: var(--mg-fs-xs);
		line-height: 1.45;
		color: var(--mg-text-2);
	}
	.reuse {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		margin: 20px 0 0;
		font-size: var(--mg-fs-sm);
		color: var(--mg-text-2);
	}
	.reuse :global(svg) {
		flex: none;
		color: var(--mg-ok);
	}

	/* Steps appear once, left to right. */
	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(6px);
		}
	}
	:global([data-motion='off']) .step {
		animation: none;
	}

	/* Narrow: steps stacked with a vertical line. */
	@media (max-width: 860px) {
		.flow {
			grid-template-columns: minmax(0, 1fr);
			gap: 20px;
		}
		.step {
			display: grid;
			grid-template-columns: 42px minmax(0, 1fr);
			column-gap: 16px;
			row-gap: 2px;
			align-items: start;
			text-align: left;
		}
		.icon {
			grid-row: 1 / 4;
		}
		.step:not(:last-child)::after {
			top: 50px;
			left: 21px;
			width: 1px;
			height: calc(100% - 50px + 20px);
		}
	}
</style>
