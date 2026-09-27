<script lang="ts">
	/** Miniature sketch of one tab for the home page, drawn in theme colours instead of a screenshot. */
	let { tab }: { tab: string } = $props();

	// Results: genome ring in confidence tiers, as in the report's map.
	const RING = [0, 0, 1, 0, 2, 1, 0, 0, 3, 1, 0, 1, 2, 0, 0, 4, 1, 0, 0, 1, 2, 0, 1, 5, 0, 0, 1, 3, 0, 1, 0, 2];
	const arc = (r: number, i: number, n: number) => {
		const c = 2 * Math.PI * r;
		return { dash: `${c / n - 1.6} ${c - c / n + 1.6}`, offset: -(c / n) * i };
	};
	// Analyze: evidence grid (genomes down, tools across) filling in.
	const GRID = [
		[0, 0, 1, 0, 0, 1],
		[0, 1, 0, 0, 2, 0],
		[1, 0, 0, 1, 0, 0],
		[0, 0, 2, -1, -1, -1],
		[-1, -1, -1, -1, -1, -1]
	];
</script>

<svg viewBox="0 0 360 220" role="img" aria-hidden="true" class="pic">
	<!-- window -->
	<rect class="frame" x="1" y="1" width="358" height="218" rx="10" />
	<path class="bar" d="M1 11a10 10 0 0 1 10-10h338a10 10 0 0 1 10 10v15H1z" />
	<circle class="dot" cx="15" cy="13.5" r="3.5" /><circle class="dot" cx="27" cy="13.5" r="3.5" /><circle class="dot" cx="39" cy="13.5" r="3.5" />

	{#if tab === 'analyze'}
		<!-- genomes chosen -->
		{#each ['E. coli', 'B. vulgatus', 'S. suillum'] as g, i (g)}
			<rect class="chip" x="16" y={42 + i * 26} width="100" height="19" rx="9.5" />
			<circle class="acc" cx="27" cy={51.5 + i * 26} r="4" />
			<text x="36" y={55 + i * 26} class="sp">{g}</text>
		{/each}
		<text class="muted" x="16" y="136">3 genomes</text>
		<!-- steps -->
		{#each ['Genomes', 'Tools', 'Run'] as s, i (s)}
			<circle class={i < 2 ? 'okf' : 'accf'} cx="144" cy={52 + i * 30} r="9" />
			{#if i < 2}
				<path class="tick" d="M139.5 {52 + i * 30} l3 3 l6 -6" />
			{:else}
				<text class="on" x="144" y={56 + i * 30} text-anchor="middle">3</text>
			{/if}
			<text x="160" y={56 + i * 30}>{s}</text>
			{#if i < 2}<line class="rule" x1="144" y1={62 + i * 30} x2="144" y2={72 + i * 30} />{/if}
		{/each}
		<g class="pulse">
			<rect class="accf" x="132" y="150" width="112" height="34" rx="17" />
			<path class="onf" d="M160 159 l0 16 l13 -8 z" />
			<text class="on big" x="182" y="172">Run</text>
		</g>
		<!-- evidence grid -->
		<text class="muted" x="262" y="44">evidence</text>
		{#each GRID as row, r (r)}
			{#each row as t, c (c)}
				<rect
					class={t < 0 ? 'empty' : r === 3 && c === 3 ? 'now' : ''}
					style={t >= 0 ? `fill: var(--mg-tier-${t})` : undefined}
					x={262 + c * 14}
					y={54 + r * 14}
					width="11"
					height="11"
					rx="2.5"
				/>
			{/each}
		{/each}
		<text class="muted" x="262" y="140">fills in as</text>
		<text class="muted" x="262" y="153">tools finish</text>
	{:else if tab === 'genomes'}
		<!-- files dropping into the input folder -->
		<rect class="drop" x="16" y="96" width="112" height="106" rx="10" />
		<text class="muted" x="72" y="186" text-anchor="middle">drop FASTA here</text>
		{#each [0, 1] as i (i)}
			<g class={i === 1 ? 'fall' : ''} transform="translate({34 + i * 40} {i === 1 ? 44 : 118})">
				<path class="doc" d="M0 0h24l10 10v36H0z" />
				<path class="fold" d="M24 0v10h10" />
				<text class="tiny" x="17" y="32" text-anchor="middle">.fa</text>
			</g>
		{/each}
		<!-- table: name, domain, genetic code -->
		<text class="muted" x="146" y="46">genome</text><text class="muted" x="238" y="46">domain</text><text class="muted" x="312" y="46">code</text>
		<line class="rule" x1="146" y1="52" x2="344" y2="52" />
		{#each [['E. coli', 'Bacteria', '11'], ['M. jannaschii', 'Archaea', '11'], ['M. genitalium', 'Bacteria', '4'], ['new_isolate', '', '']] as [n, d, g], i (n)}
			<text x="146" y={72 + i * 34} class:sp={/^[A-Z]\. [a-z]/.test(n)}>{n}</text>
			{#if d}
				<rect class="badge" x="236" y={60 + i * 34} width="58" height="17" rx="8.5" />
				<text class="acct" x="265" y={72 + i * 34} text-anchor="middle">{d}</text>
				<text x="316" y={72 + i * 34}>{g}</text>
			{:else}
				<rect class="warnb" x="236" y={60 + i * 34} width="104" height="17" rx="8.5" />
				<text class="warnt" x="288" y={72 + i * 34} text-anchor="middle">found for you</text>
			{/if}
			<line class="rule faint" x1="146" y1={84 + i * 34} x2="344" y2={84 + i * 34} />
		{/each}
	{:else if tab === 'results'}
		<!-- genome ring -->
		<g transform="rotate(-90 88 122)">
			{#each RING as t, i (i)}
				{@const a = arc(62, i, RING.length)}
				<circle cx="88" cy="122" r="62" class="ring" style="stroke: var(--mg-tier-{t})" stroke-dasharray={a.dash} stroke-dashoffset={a.offset} />
			{/each}
			{#each RING.slice().reverse() as t, i (i)}
				{@const a = arc(48, i, RING.length)}
				<circle cx="88" cy="122" r="48" class="ring thin" style="stroke: var(--mg-tier-{(t + 1) % 6})" stroke-dasharray={a.dash} stroke-dashoffset={a.offset} />
			{/each}
		</g>
		<text class="big" x="88" y="120" text-anchor="middle">4.6 Mb</text>
		<text class="muted" x="88" y="135" text-anchor="middle">4,301 genes</text>
		<!-- numbers and tiers -->
		<rect class="card" x="172" y="40" width="80" height="44" rx="8" />
		<text class="num" x="182" y="63">812</text><text class="muted" x="182" y="77">operons</text>
		<rect class="card" x="262" y="40" width="82" height="44" rx="8" />
		<text class="num" x="272" y="63">94%</text><text class="muted" x="272" y="77">with support</text>
		<text class="muted" x="172" y="104">confidence</text>
		{#each [30, 26, 18, 12, 9, 5] as w, i (i)}
			<rect x={172 + [0, 30, 56, 74, 86, 95].map((v) => v * 1.72)[i]} y="110" width={w * 1.72 - 1.5} height="12" rx="2" style="fill: var(--mg-tier-{i})" />
		{/each}
		{#each ['DNA polymerase III', 'ribosomal protein L7', 'hypothetical protein'] as p, i (p)}
			<circle cx="178" cy={146 + i * 22} r="4.5" style="fill: var(--mg-tier-{[0, 1, 5][i]})" />
			<text x="190" y={150 + i * 22}>{p}</text>
		{/each}
	{:else if tab === 'files'}
		<!-- where -->
		<rect class="accsoft" x="16" y="38" width="96" height="20" rx="10" /><text class="acct" x="64" y="52" text-anchor="middle">Cluster</text>
		<rect class="chip" x="118" y="38" width="96" height="20" rx="10" /><text x="166" y="52" text-anchor="middle">This computer</text>
		<!-- tree -->
		{#each [[0, 'margie-output', true], [1, '2026-09-24-1310', true], [2, 'genomes', true], [3, 'E_coli', true], [4, 'FINAL_ANNOTATION.tsv', false], [4, 'GENOME_VIEWER.html', false], [1, 'input', false]] as [d, n, folder], i (i)}
			{@const x = 18 + (d as number) * 13}
			{@const y = 78 + i * 19}
			{#if folder}
				<path class="folder" d="M{x} {y - 9}h6l2 2h8v9h-16z" />
			{:else}
				<path class="doc sm" d="M{x + 2} {y - 10}h9l3 3v10h-12z" />
			{/if}
			<text class={i === 4 ? 'acct' : ''} x={x + 21} y={y}>{n}</text>
		{/each}
		<!-- preview of the selected file -->
		<rect class="card" x="232" y="68" width="112" height="136" rx="8" />
		{#each Array(7) as _, r (r)}
			{#each [0, 1, 2] as c (c)}
				<rect class={r === 0 ? 'cellh' : 'cell'} x={240 + c * 33} y={78 + r * 17} width={c === 2 ? 22 : 29} height="10" rx="2" />
			{/each}
		{/each}
	{:else if tab === 'jobs'}
		{#each [['Annotate 6 genomes', 'running'], ['Annotate E. coli', 'finished'], ['Install databases', 'failed']] as [n, s], i (n)}
			{@const y = 40 + i * 42}
			<rect class="card" x="16" y={y} width="176" height="34" rx="8" />
			{#if s === 'running'}
				<circle class="accf spin" cx="32" cy={y + 17} r="6" />
				<rect class="track" x="46" y={y + 22} width="134" height="4" rx="2" />
				<rect class="accf grow" x="46" y={y + 22} width="80" height="4" rx="2" />
			{:else if s === 'finished'}
				<circle class="okf" cx="32" cy={y + 17} r="7" /><path class="tick" d="M28.5 {y + 17} l2.5 2.5 l5 -5" />
			{:else}
				<circle class="dangerf" cx="32" cy={y + 17} r="7" /><path class="tick" d="M29.5 {y + 14.5} l5 5 m0 -5 l-5 5" />
			{/if}
			<text x="46" y={y + 16}>{#if n.endsWith('E. coli')}{n.slice(0, -7)}<tspan class="sp">E. coli</tspan>{:else}{n}{/if}</text>
		{/each}
		<text class="muted" x="16" y="186">stop it, or read its log</text>
		<!-- log -->
		<rect class="term" x="204" y="40" width="140" height="164" rx="8" />
		{#each ['genes     done', 'proteins  done', 'operons   …', '', '', ''] as l, i (i)}
			<text class="mono" x="214" y={60 + i * 16}>{l}</text>
		{/each}
		<rect class="cursor" x="214" y="124" width="7" height="11" />
	{:else if tab === 'install'}
		<text class="muted" x="16" y="46">containers</text>
		{#each [0, 1, 2, 3] as i (i)}
			{@const x = 20 + i * 40}
			<path class="cube" d="M{x} 62 l14 -7 l14 7 v16 l-14 7 l-14 -7z M{x} 62 l14 7 l14 -7 M{x + 14} 69 v16" />
			<circle class="okf" cx={x + 27} cy="82" r="5.5" /><path class="tick sm" d="M{x + 24.5} 82 l2 2 l3.5 -3.5" />
		{/each}
		<text class="muted" x="16" y="116">databases</text>
		{#each [0, 1, 2] as i (i)}
			{@const x = 20 + i * 40}
			<ellipse class="cyl" cx={x + 14} cy="132" rx="13" ry="4.5" />
			<path class="cyl" d="M{x + 1} 132 v20 a13 4.5 0 0 0 26 0 v-20" />
			{#if i < 2}
				<circle class="okf" cx={x + 27} cy="152" r="5.5" /><path class="tick sm" d="M{x + 24.5} 152 l2 2 l3.5 -3.5" />
			{:else}
				<circle class="warnf" cx={x + 27} cy="152" r="5.5" /><text class="on tiny" x={x + 27} y="155.5" text-anchor="middle">!</text>
			{/if}
		{/each}
		<rect class="accf" x="138" y="136" width="46" height="20" rx="10" /><text class="on" x="161" y="150" text-anchor="middle">Install</text>
		<!-- ready count and licence -->
		<circle class="track ring-bg" cx="272" cy="86" r="34" />
		<circle class="okring" cx="272" cy="86" r="34" stroke-dasharray="{2 * Math.PI * 34 * 0.86} 999" transform="rotate(-90 272 86)" />
		<text class="num" x="272" y="92" text-anchor="middle">12/14</text>
		<text class="muted" x="272" y="136" text-anchor="middle">ready</text>
		<path class="doc" d="M246 152h36l8 8v38h-44z" />
		<line class="rule" x1="253" y1="166" x2="280" y2="166" /><line class="rule" x1="253" y1="175" x2="276" y2="175" />
		<circle class="okf" cx="286" cy="192" r="7" /><path class="tick" d="M282.5 192 l2.5 2.5 l5 -5" />
		<text class="muted" x="300" y="180">licences</text>
	{:else if tab === 'settings'}
		{#each [['cores', 0.55], ['memory', 0.7], ['time', 0.35]] as [n, v], i (n)}
			{@const y = 52 + i * 34}
			<text class="muted" x="16" y={y}>{n}</text>
			<rect class="track" x="16" y={y + 8} width="150" height="5" rx="2.5" />
			<rect class="accf" x="16" y={y + 8} width={150 * (v as number)} height="5" rx="2.5" />
			<circle class="knob" cx={16 + 150 * (v as number)} cy={y + 10.5} r="7" />
		{/each}
		{#each [['Classify genome', true], ['Optional step', false]] as [n, on], i (n)}
			{@const y = 50 + i * 30}
			<rect class={on ? 'accf' : 'track'} x="200" y={y - 10} width="30" height="16" rx="8" />
			<circle class="knob" cx={on ? 222 : 208} cy={y - 2} r="6" />
			<text x="238" y={y + 2}>{n}</text>
		{/each}
		<text class="muted" x="16" y="166">output folder</text>
		<rect class="field" x="16" y="174" width="328" height="26" rx="6" />
		<path class="folder" d="M26 181h6l2 2h8v9h-16z" />
		<text class="mono" x="50" y="191">/scratch/…/margie-output</text>
		<text class="muted" x="200" y="120">SLURM account</text>
		<rect class="field" x="200" y="128" width="100" height="22" rx="6" />
		<text class="mono" x="208" y="143">my-lab</text>
	{/if}
</svg>

<style>
	.pic {
		display: block;
		width: 100%;
		height: auto;
		font-family: var(--mg-font);
	}
	text {
		font-size: 10.5px;
		fill: var(--mg-text);
	}
	.muted {
		fill: var(--mg-text-3);
		font-size: 9.5px;
	}
	.tiny {
		font-size: 8.5px;
		fill: var(--mg-text-3);
	}
	.big {
		font-size: 13px;
		font-weight: 700;
	}
	.num {
		font-size: 16px;
		font-weight: 700;
	}
	.mono {
		font-family: var(--mg-mono);
		font-size: 9.5px;
	}
	.on {
		fill: var(--mg-on-accent, #fff);
		font-weight: 600;
	}
	.acct {
		fill: var(--mg-accent-ink, var(--mg-accent));
		font-weight: 600;
	}
	.frame {
		fill: var(--mg-surface);
		stroke: var(--mg-border);
	}
	.bar {
		fill: var(--mg-surface-2);
	}
	.dot {
		fill: var(--mg-border-strong);
	}
	.chip,
	.card,
	.field {
		fill: var(--mg-surface-2);
		stroke: var(--mg-border);
	}
	.acc,
	.accf {
		fill: var(--mg-accent);
	}
	.accsoft,
	.badge {
		fill: color-mix(in srgb, var(--mg-accent) 16%, transparent);
	}
	.onf {
		fill: var(--mg-on-accent, #fff);
	}
	.okf {
		fill: var(--mg-ok);
	}
	.warnf {
		fill: var(--mg-warn);
	}
	.dangerf {
		fill: var(--mg-danger);
	}
	.warnb {
		fill: var(--mg-warn-soft, color-mix(in srgb, var(--mg-warn) 18%, transparent));
	}
	.warnt {
		fill: var(--mg-warn);
		font-weight: 600;
	}
	.tick {
		fill: none;
		stroke: #fff;
		stroke-width: 2;
		stroke-linecap: round;
		stroke-linejoin: round;
	}
	.tick.sm {
		stroke-width: 1.6;
	}
	.rule {
		stroke: var(--mg-border-strong);
		stroke-width: 1.5;
	}
	.rule.faint {
		stroke: var(--mg-border);
		stroke-width: 1;
	}
	.empty {
		fill: none;
		stroke: var(--mg-border);
		stroke-dasharray: 2 2;
	}
	.now {
		fill: var(--mg-accent);
		animation: blink 1.1s ease-in-out infinite;
	}
	.drop {
		fill: color-mix(in srgb, var(--mg-accent) 6%, transparent);
		stroke: var(--mg-accent);
		stroke-dasharray: 5 4;
	}
	.doc {
		fill: var(--mg-surface);
		stroke: var(--mg-text-3);
		stroke-width: 1.3;
	}
	.fold {
		fill: none;
		stroke: var(--mg-text-3);
		stroke-width: 1.3;
	}
	.ring {
		fill: none;
		stroke-width: 12;
	}
	.ring.thin {
		stroke-width: 7;
		opacity: 0.75;
	}
	.folder {
		fill: color-mix(in srgb, var(--mg-accent) 30%, transparent);
		stroke: var(--mg-accent);
		stroke-width: 1;
	}
	.cell {
		fill: var(--mg-border);
	}
	.cellh {
		fill: var(--mg-text-3);
	}
	.track {
		fill: var(--mg-border);
	}
	.ring-bg {
		fill: none;
		stroke: var(--mg-border);
		stroke-width: 9;
	}
	.okring {
		fill: none;
		stroke: var(--mg-ok);
		stroke-width: 9;
		stroke-linecap: round;
	}
	/* Scientific names in italics. */
	.sp {
		font-style: italic;
	}
	.term {
		fill: #14171b;
	}
	.term ~ .mono {
		fill: color-mix(in srgb, #e4e8ec 75%, var(--mg-ok));
	}
	.cursor {
		fill: var(--mg-ok);
		animation: blink 1s steps(2) infinite;
	}
	.cube,
	.cyl {
		fill: color-mix(in srgb, var(--mg-accent) 12%, var(--mg-surface));
		stroke: var(--mg-accent);
		stroke-width: 1.3;
		stroke-linejoin: round;
	}
	.knob {
		fill: var(--mg-surface);
		stroke: var(--mg-border-strong);
		stroke-width: 1.5;
	}
	.pulse {
		transform-origin: 188px 167px;
		animation: pulse 2.4s ease-in-out infinite;
	}
	.fall {
		animation: fall 2.6s ease-in infinite;
	}
	.spin {
		animation: blink 1.2s ease-in-out infinite;
	}
	.grow {
		animation: grow 3s ease-in-out infinite alternate;
		transform-origin: 46px 0;
	}
	@keyframes blink {
		50% {
			opacity: 0.35;
		}
	}
	@keyframes pulse {
		50% {
			transform: scale(1.05);
		}
	}
	@keyframes fall {
		0% {
			transform: translate(74px, 30px);
			opacity: 0;
		}
		20% {
			opacity: 1;
		}
		70%,
		100% {
			transform: translate(74px, 118px);
			opacity: 1;
		}
	}
	@keyframes grow {
		from {
			transform: scaleX(0.4);
		}
		to {
			transform: scaleX(1.6);
		}
	}
	:global([data-motion='off']) .pic * {
		animation: none !important;
	}
</style>
