/**
 * Detects this computer's platform and usable container runtimes for the
 * setup wizard, and starts a stopped runtime on request.
 */

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { resolveRuntime, setting } from './pipeline';

export type RuntimeId = 'docker' | 'podman' | 'container' | 'apptainer';

export interface RuntimeInfo {
	id: RuntimeId;
	label: string;
	installed: boolean;
	/** The daemon/service answers (always true for Apptainer, which has none). */
	running: boolean;
	/** Where images live: the runtime's own store, or .sif files in a folder. */
	storesImages: 'runtime' | 'sif-folder';
	/** What to do if it is not ready. */
	hint: string;
	install: string;
}

export interface PlatformInfo {
	os: 'macos' | 'linux' | 'wsl' | 'other';
	arch: string;
	runtimes: RuntimeInfo[];
	recommended: RuntimeId | null;
}

/** Returns a command's exit code, or null if it is missing or timed out. */
function probe(cmd: string, args: string[], timeoutMs = 8000): Promise<number | null> {
	return new Promise((resolve) => {
		let settled = false;
		const done = (v: number | null) => {
			if (!settled) {
				settled = true;
				resolve(v);
			}
		};
		try {
			const child = spawn(cmd, args, { stdio: 'ignore' });
			const timer = setTimeout(() => {
				child.kill('SIGKILL');
				done(null);
			}, timeoutMs);
			child.on('error', () => {
				clearTimeout(timer);
				done(null);
			});
			child.on('close', (code) => {
				clearTimeout(timer);
				done(code);
			});
		} catch {
			done(null);
		}
	});
}

const has = async (cmd: string) => (await probe('bash', ['-c', `command -v ${cmd}`], 3000)) === 0;

function detectOs(): PlatformInfo['os'] {
	if (process.platform === 'darwin') return 'macos';
	if (process.platform !== 'linux') return 'other';
	try {
		return /microsoft/i.test(fs.readFileSync('/proc/version', 'utf8')) ? 'wsl' : 'linux';
	} catch {
		return 'linux';
	}
}

export async function detectPlatform(): Promise<PlatformInfo> {
	const os = detectOs();
	const arch = process.arch === 'x64' ? 'x86_64' : process.arch;
	const onMac = os === 'macos';

	const [docker, podman, container, apptainer, singularity] = await Promise.all([
		has('docker'),
		has('podman'),
		onMac ? has('container') : Promise.resolve(false),
		has('apptainer'),
		has('singularity')
	]);
	const [dockerUp, podmanUp, containerUp] = await Promise.all([
		docker ? probe('docker', ['info']).then((c) => c === 0) : false,
		podman ? probe('podman', ['info']).then((c) => c === 0) : false,
		container ? probe('container', ['system', 'status']).then((c) => c === 0) : false
	]);

	const runtimes: RuntimeInfo[] = [];
	if (onMac) {
		runtimes.push({
			id: 'container',
			label: "Apple's container",
			installed: container,
			running: containerUp,
			storesImages: 'runtime',
			hint: container
				? 'Start it with: container system start (the first time, also: container system kernel set --recommended)'
				: 'Needs a Mac with Apple silicon and macOS 15 or later.',
			install: 'https://github.com/apple/container/releases'
		});
	}
	runtimes.push(
		{
			id: 'docker',
			label: 'Docker',
			installed: docker,
			running: dockerUp,
			storesImages: 'runtime',
			hint: docker ? (onMac ? 'Open Docker Desktop and wait for it to start.' : 'Start the Docker service.') : '',
			install: 'https://docs.docker.com/get-docker/'
		},
		{
			id: 'podman',
			label: 'Podman',
			installed: podman,
			running: podmanUp,
			storesImages: 'runtime',
			hint: podman ? (onMac ? 'Start its VM with: podman machine start' : 'Check that podman info works.') : '',
			install: 'https://podman.io/docs/installation'
		},
		{
			id: 'apptainer',
			label: singularity && !apptainer ? 'Singularity' : 'Apptainer',
			installed: apptainer || singularity,
			running: apptainer || singularity,
			storesImages: 'sif-folder',
			hint: onMac ? 'Linux only (HPC clusters and Linux workstations).' : '',
			install: 'https://apptainer.org/docs/admin/main/installation.html'
		}
	);

	// Prefer what is ready, in the order that suits this kind of machine.
	const order: RuntimeId[] =
		os === 'macos'
			? ['container', 'docker', 'podman']
			: os === 'wsl'
				? ['docker', 'podman', 'apptainer']
				: ['apptainer', 'docker', 'podman'];
	const byId = new Map(runtimes.map((r) => [r.id, r]));
	const recommended =
		order.find((id) => byId.get(id)?.running) ?? order.find((id) => byId.get(id)?.installed) ?? null;

	return { os, arch, runtimes, recommended };
}

/** Returns free bytes on the disk that holds `p` (or its nearest existing parent). */
export async function freeBytes(p: string): Promise<number | null> {
	let dir = path.resolve(p);
	while (!fs.existsSync(dir) && path.dirname(dir) !== dir) dir = path.dirname(dir);
	try {
		const st = await fs.promises.statfs(dir);
		return st.bavail * st.bsize;
	} catch {
		return null;
	}
}

export interface RuntimeStatus {
	/** RUNTIME as saved (auto, docker, podman, container, apptainer). */
	setting: string;
	/** What the scripts will actually use ('' if nothing usable). */
	active: RuntimeId | '';
	label: string;
	ready: boolean;
	platform: PlatformInfo;
}

export async function runtimeStatus(): Promise<RuntimeStatus> {
	const platform = await detectPlatform();
	const resolved = resolveRuntime();
	const active = (resolved === 'singularity' ? 'apptainer' : resolved) as RuntimeId | '';
	const info = platform.runtimes.find((r) => r.id === active);
	return {
		setting: setting('RUNTIME') || 'auto',
		active,
		label: info?.label ?? (active || 'none'),
		ready: !!info?.running,
		platform
	};
}

/** Runs a command to completion, returning its exit code and combined output. */
function runCapture(cmd: string, args: string[], timeoutMs: number): Promise<{ code: number | null; output: string }> {
	return new Promise((resolve) => {
		let output = '';
		const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
		child.stdout.on('data', (d) => (output += d));
		child.stderr.on('data', (d) => (output += d));
		const timer = setTimeout(() => child.kill('SIGTERM'), timeoutMs);
		child.on('error', (e) => {
			clearTimeout(timer);
			resolve({ code: null, output: String(e) });
		});
		child.on('close', (code) => {
			clearTimeout(timer);
			resolve({ code, output: output.replace(/\x1b\[[0-9;]*m/g, '').trim() });
		});
	});
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Starts an installed, stopped runtime with its own start command; on Linux,
 * where services need root, it returns the command to run instead.
 */
export async function startRuntime(id: RuntimeId): Promise<{ ok: boolean; message: string }> {
	const os = detectOs();
	if (id === 'container') {
		if (os !== 'macos') return { ok: false, message: "Apple's container runs only on macOS." };
		// Installs the default kernel on first use instead of prompting for it.
		const r = await runCapture('container', ['system', 'start', '--enable-kernel-install'], 300_000);
		return { ok: r.code === 0, message: r.output || (r.code === 0 ? 'Started.' : 'container system start failed.') };
	}
	if (id === 'docker') {
		if (os !== 'macos') {
			return { ok: false, message: 'Start the Docker service with your system tools, e.g.: sudo systemctl start docker' };
		}
		await runCapture('open', ['-a', 'Docker'], 30_000);
		for (let i = 0; i < 45; i++) {
			if ((await probe('docker', ['info'], 5000)) === 0) return { ok: true, message: 'Docker Desktop is running.' };
			await sleep(2000);
		}
		return { ok: false, message: 'Docker Desktop was opened but is not answering yet; give it a minute and check again.' };
	}
	if (id === 'podman') {
		const r = await runCapture('podman', ['machine', 'start'], 300_000);
		return { ok: r.code === 0, message: r.output || (r.code === 0 ? 'Started.' : 'podman machine start failed.') };
	}
	return { ok: false, message: 'Apptainer has no service to start.' };
}
