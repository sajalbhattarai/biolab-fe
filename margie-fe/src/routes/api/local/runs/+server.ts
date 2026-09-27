import { error, json } from '@sveltejs/kit';
import fs from 'node:fs';
import path from 'node:path';
import { LICENCE_TOOLS, getSettings, getTools, licenceAccepted, registry, setting } from '$lib/server/pipeline';
import { runtimeStatus } from '$lib/server/platform';
import { inspectSetupRepo } from '$lib/server/setupRepo';
import { RunError, clearHistory, listRuns, runFiles, runProgressDetail, runReason, startRun, type RunOptions } from '$lib/server/runs';
import { listGenomes, metadataPath, stageGenomes } from '$lib/server/files';
import { passwordMatches } from '$lib/server/install-lock';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async () =>
	json({
		runs: listRuns().map((r) => {
			const p = runProgressDetail(r);
			return { ...r, progress: p.percent, progressText: p.text, files: runFiles(r), reason: runReason(r) };
		})
	});

/** Clears finished runs after copying them to run-history/<when>/. */
export const DELETE: RequestHandler = async () => json(clearHistory());

const SETUP_TOOL = /^[a-z0-9_-]+$/;

/**
 * Starts annotate.sh, setup.sh or margie-build's build.sh, building arguments
 * from checked fields rather than text from the page.
 *
 *   { kind: 'annotate', tools: string[] }  -- or { all: true } for every tool
 *   { kind: 'setup', phase?: 'both'|'containers'|'databases', mode?: 'build'|'pull',
 *     tool?: string, redo?: boolean }
 *   { kind: 'build', what?: 'containers'|'databases'|'all', tools?: string[], dryRun?: boolean }
 *     -- the setup repository's build.sh, with the saved runtime and folders
 */
export const POST: RequestHandler = async ({ request }) => {
	const body = await request.json().catch(() => ({}));
	// Every installation needs the install statement (a dry run only plans, and needs none).
	if ((body.kind === 'build' || body.kind === 'setup') && body.dryRun !== true && !passwordMatches(body.password)) {
		error(403, 'Installing needs the install statement, typed exactly as shown.');
	}
	let args: string[] = [];
	let label: string;
	let opts: RunOptions = {};
	let skipped: string[] = [];

	if (body.kind === 'annotate') {
		const { annotation } = getTools();
		const known = new Map(annotation.map((t) => [t.name, t]));
		const tools: string[] = Array.isArray(body.tools) ? body.tools : [];
		for (const t of tools) {
			const info = known.get(t);
			if (!info) error(400, `Unknown tool: ${t}`);
			if (!info.licensed) error(403, `${t} needs its licence accepted in Settings first.`);
		}
		// An empty selection means --genes-only; every tool needs an explicit `all: true`.
		const genesOnly = !tools.length && body.all !== true;
		args = genesOnly ? ['--genes-only'] : tools.flatMap((t) => ['--tool', t]);
		label = genesOnly ? 'Annotate: gene calls only' : tools.length ? `Annotate: ${tools.join(', ')}` : 'Annotate (all tools)';
		// Records the genome names now, as the folder may change later.
		const present = listGenomes().genomes.map((g) => g.name);

		// { genomes: [...] } narrows the run; omitted or empty means the whole folder.
		const asked: string[] = Array.isArray(body.genomes) ? body.genomes.map(String) : [];
		const unknown = asked.filter((n) => !present.includes(n));
		if (unknown.length) error(400, `Not in the genome folder: ${unknown.join(', ')}`);

		const files = asked.length ? present.filter((n) => asked.includes(n)) : present;
		if (asked.length && !files.length) error(400, 'No genomes were selected.');

		// Stages a symlink folder only for a true subset.
		const subset = asked.length > 0 && files.length < present.length;
		opts = {
			tools,
			files,
			outputDir: setting('OUTPUT_ROOT'),
			...(subset
				? {
						env: {
							USER_INPUT_DIR: stageGenomes(files),
							// The staging folder has no genome table, so the real one is passed.
							GENOME_METADATA: metadataPath()
						}
					}
				: {})
		};
		if (subset) label += ` — ${files.length} of ${present.length} genomes`;
	} else if (body.kind === 'setup') {
		const phase = body.phase ?? 'both';
		if (phase === 'containers') args.push('--containers-only');
		else if (phase === 'databases') args.push('--databases-only');
		else if (phase !== 'both') error(400, 'phase must be both, containers or databases.');
		if (body.mode === 'pull') args.push('--pull');
		else if (body.mode && body.mode !== 'build') error(400, 'mode must be build or pull.');
		if (body.tool) {
			if (typeof body.tool !== 'string' || !SETUP_TOOL.test(body.tool)) error(400, 'Invalid tool name.');
			args.push('--tool', body.tool);
		}
		if (body.redo === true) args.push('--redo');
		opts = {
			tools: body.tool ? [String(body.tool)] : [],
			outputDir: setting(phase === 'containers' ? 'SIF_DIR' : 'DB_ROOT')
		};
		const what = phase === 'both' ? 'images + databases' : phase === 'containers' ? 'images' : 'databases';
		label = `Setup: ${what}${body.tool ? ` (${body.tool})` : ''}${body.mode === 'pull' ? ', pull' : ''}`;
	} else if (body.kind === 'build') {
		const repo = inspectSetupRepo(setting('SETUP_REPO'));
		if (!repo.ok) error(400, `Setup repository: ${repo.reason}`);
		const what = body.what ?? 'all';
		if (!['containers', 'databases', 'all'].includes(what)) error(400, 'what must be containers, databases or all.');

		const rt = await runtimeStatus();
		if (!rt.active) error(400, 'Choose a container runtime first.');
		// A dry run only plans, so it may go ahead before the runtime is up.
		if (!rt.ready && body.dryRun !== true) error(400, `${rt.label} is not running. Start it, or do a dry run first.`);
		const apptainerFamily = rt.active === 'apptainer';
		// margie-build names the apptainer family by its binary.
		const runtimeName = apptainerFamily ? (rt.label === 'Singularity' ? 'singularity' : 'apptainer') : rt.active;

		const offered = new Map<string, boolean>(); // name -> gated
		const buildGated = new Set<string>(); // gated by build.sh, which takes --accept-<name>-licence
		for (const i of [...(what === 'databases' ? [] : repo.containers), ...(what === 'containers' ? [] : repo.databases)]) {
			offered.set(i.name, offered.get(i.name) || i.gated);
			if (i.buildGated) buildGated.add(i.name);
		}
		const explicit = Array.isArray(body.tools) && body.tools.length > 0;
		// GTDB-Tk is built only while it is switched on.
		const wantGtdbtk = setting('RUN_GTDBTK') === '1';
		const tools: string[] = explicit ? body.tools : [...offered.keys()].filter((t) => t !== 'gtdbtk' || wantGtdbtk);
		for (const t of tools) if (!offered.has(t)) error(400, `The setup repository cannot build ${t} here.`);

		// Gated tools build only with the licence accepted; unaccepted ones are left
		// out, since build.sh without a terminal would refuse the whole run.
		const values = Object.fromEntries(getSettings().settings.map((s) => [s.key, s.value]));
		const accepted = (t: string) => LICENCE_TOOLS.includes(t) && licenceAccepted(t, values);
		const blocked = tools.filter((t) => offered.get(t) && !accepted(t));
		if (explicit && blocked.length) error(403, `Accept the licence first, by typing the licence statement (Settings → Licences): ${blocked.join(', ')}.`);

		// Phobius needs the user's own copy; without it, it is skipped, or refused when named.
		const phobius = setting('PHOBIUS_TARBALL').trim();
		const needsPhobius = tools.includes('phobius') && !phobius;
		if (explicit && needsPhobius) {
			error(400, 'phobius builds only from your own download. Put its path in Settings → Phobius download first.');
		}
		skipped = [...blocked, ...(needsPhobius ? ['phobius'] : [])];
		const inScope = tools.filter((t) => !skipped.includes(t));
		if (inScope.length === 0) error(400, 'Nothing left to build.');

		const dbDir = setting('DB_ROOT');
		const sifDir = setting('SIF_DIR');
		args = [
			`--${what}`,
			...inScope,
			'--runtime', runtimeName,
			'--db-dir', dbDir,
			...(apptainerFamily ? ['--sif-dir', sifDir] : []),
			...inScope.filter((t) => buildGated.has(t)).map((t) => `--accept-${t}-licence`),
			// One tool that cannot build here (a missing download, say) should not
			// stop the rest, nor the databases that follow.
			...(inScope.length > 1 ? ['--continue-on-error'] : []),
			...(body.dryRun === true ? ['--dry-run'] : [])
		];
		opts = {
			tools: inScope,
			outputDir: what === 'containers' ? sifDir : dbDir,
			script: path.join(repo.path, 'build.sh'),
			cwd: repo.path,
			shown: `${path.basename(repo.path)}/build.sh`,
			// IMAGE_PREFIX: build.sh tags <prefix>/<tool>:latest, the name the pipeline runs.
			env: {
				QUIET_NOTICE: '1',
				IMAGE_PREFIX: registry(),
				CONTAINER_RUNTIME: runtimeName,
				DB_DIR: dbDir,
				SIF_DIR: sifDir,
				// A folder is an unpacked Phobius; anything else is its tarball.
				...(phobius && inScope.includes('phobius')
					? fs.statSync(phobius, { throwIfNoEntry: false })?.isDirectory()
						? { PHOBIUS_VENDOR_DIR: phobius }
						: { PHOBIUS_TARBALL: phobius }
					: {})
			}
		};
		const scope = explicit ? inScope.join(', ') : 'all tools';
		const whatText = what === 'all' ? 'images + databases' : what === 'containers' ? 'images' : 'databases';
		label = `Build: ${whatText} (${scope}) with ${rt.label}${body.dryRun ? ', dry run' : ''}`;
	} else {
		error(400, 'kind must be annotate, setup or build.');
	}

	try {
		return json({ run: startRun(body.kind, args, label, opts), skipped }, { status: 201 });
	} catch (e) {
		if (e instanceof RunError) error(e.status, e.message);
		throw e;
	}
};
