/**
 * Builds margie-fe and stages what the .app ships: .stage/gui (adapter-node build, scripts,
 * runtime-only node_modules) and .stage/pipeline (this repository's margie-pipeline folder at its last commit, via git archive,
 * without its own GUI). electron-builder copies both into Contents/Resources; `npm start` uses them directly.
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DESKTOP = path.resolve(HERE, '..');
const FE = path.resolve(DESKTOP, '..', 'margie-fe');
const STAGE = path.join(DESKTOP, '.stage');
const GUI = path.join(STAGE, 'gui');
const PIPELINE = path.join(STAGE, 'pipeline');
// The pipeline this repository carries (margie-frontend/margie-pipeline), taken at its last commit.
const REPO = path.resolve(DESKTOP, '..');
const PIPELINE_DIR = 'margie-pipeline';

const step = (s) => console.log(`\n\u001b[1m==> ${s}\u001b[0m`);
const run = (cmd, args, cwd, extraEnv = {}) =>
	execFileSync(cmd, args, {
		cwd,
		stdio: 'inherit',
		// On Windows npm is npm.cmd, which Node starts only through a shell.
		shell: process.platform === 'win32',
		env: { ...process.env, npm_config_update_notifier: 'false', ...extraEnv }
	});

if (!fs.existsSync(path.join(FE, 'package.json'))) {
	console.error(`margie-fe is not where it should be: ${FE}`);
	process.exit(1);
}

// ---------------------------------------------------------------------------
// 1. Build the front-end
// ---------------------------------------------------------------------------
step('Installing the front-end’s build dependencies');
run('npm', ['install', '--no-audit', '--no-fund'], FE);

step('Building the front-end (vite build → build/)');
// Pins the cluster API to the local end of hpc-connect.sh's SSH tunnel, instead of
// whatever margie-fe/.env (rewritten by scripts/margie.sh) holds.
run('npm', ['run', 'build'], FE, { VITE_PUBLIC_API_URL: 'http://localhost:8000' });

const built = path.join(FE, 'build', 'handler.js');
if (!fs.existsSync(built)) {
	console.error(`the build did not produce ${built}`);
	process.exit(1);
}

// ---------------------------------------------------------------------------
// 2. Lay out .stage/gui
// ---------------------------------------------------------------------------
step('Staging the front-end');
fs.rmSync(STAGE, { recursive: true, force: true });
fs.mkdirSync(GUI, { recursive: true });

fs.cpSync(path.join(FE, 'build'), path.join(GUI, 'build'), { recursive: true });
fs.cpSync(path.join(FE, 'scripts'), path.join(GUI, 'scripts'), { recursive: true });
for (const f of ['package.json', 'package-lock.json']) {
	fs.copyFileSync(path.join(FE, f), path.join(GUI, f));
}

// The scripts are spawned by path and Resources is read-only, so they need their exec bit here.
step('Making the scripts executable');
for (const f of fs.readdirSync(path.join(GUI, 'scripts'))) {
	if (f.endsWith('.sh')) {
		fs.chmodSync(path.join(GUI, 'scripts', f), 0o755);
		console.log(`  chmod +x scripts/${f}`);
	}
}

// ---------------------------------------------------------------------------
// 3. Runtime dependencies only
// ---------------------------------------------------------------------------
step('Installing runtime dependencies (omit=dev)');
// --ignore-scripts: no runtime dependency needs an install hook.
run('npm', ['ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'], GUI);

// The lockfile is only needed for the install.
fs.rmSync(path.join(GUI, 'package-lock.json'), { force: true });

// ---------------------------------------------------------------------------
// 4. The pipeline
// ---------------------------------------------------------------------------
step(`Staging ${PIPELINE_DIR} from ${REPO}`);
const git = (...args) => execFileSync('git', ['-C', REPO, ...args], { encoding: 'utf8' }).trim();
let commit;
try {
	commit = git('log', '-1', '--format=%H', '--', PIPELINE_DIR);
} catch {
	console.error(`${REPO} is not a git checkout`);
	process.exit(1);
}
if (!commit) {
	console.error(`${PIPELINE_DIR} is not committed in ${REPO}`);
	process.exit(1);
}
const dirty = git('status', '--porcelain', '--untracked-files=no', '--', PIPELINE_DIR);
if (dirty) console.warn(`  note: uncommitted changes in ${PIPELINE_DIR} are not included:\n${dirty}`);
fs.mkdirSync(PIPELINE, { recursive: true });
const tarball = path.join(STAGE, 'pipeline.tar');
// Only the pipeline folder, as committed, with its paths relative to it.
execFileSync('git', ['-C', REPO, 'archive', '--format=tar', '-o', tarball, `HEAD:${PIPELINE_DIR}`]);
// bsdtar (macOS, Windows 10+) keeps the scripts' exec bits.
execFileSync('tar', ['-xf', tarball, '-C', PIPELINE]);
fs.rmSync(tarball);
const describe = git('log', '-1', '--format=%h %cs %s', '--', PIPELINE_DIR);
fs.writeFileSync(
	path.join(PIPELINE, 'margie-bundle.json'),
	JSON.stringify({ commit, describe, staged: new Date().toISOString() }, null, 2) + '\n'
);
console.log(`  ${describe}`);

// ---------------------------------------------------------------------------
// 5. Report
// ---------------------------------------------------------------------------
const bytes = (dir) => {
	let total = 0;
	for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) total += bytes(p);
		else if (e.isFile()) total += fs.statSync(p).size;
	}
	return total;
};
const mb = (n) => `${(n / 1024 / 1024).toFixed(1)} MB`;

step('Staged');
console.log(`  build/        ${mb(bytes(path.join(GUI, 'build')))}`);
console.log(`  node_modules/ ${mb(bytes(path.join(GUI, 'node_modules')))}`);
console.log(`  scripts/      ${mb(bytes(path.join(GUI, 'scripts')))}`);
console.log(`  total         ${mb(bytes(GUI))}   →  ${GUI}`);
console.log(`  pipeline      ${mb(bytes(PIPELINE))}   →  ${PIPELINE}`);
