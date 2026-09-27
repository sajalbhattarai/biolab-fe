/**
 * Windows only: checks what running MARGIE through WSL 2 needs (distribution,
 * basics, Node.js, a container runtime) and the commands that install each.
 */

import { execFile } from 'node:child_process';

export interface WslStep {
	id: 'wsl' | 'basics' | 'node' | 'containers';
	label: string;
	ok: boolean;
	/** What is there, in a few words. */
	detail: string;
	/** How to get it: where to type it, and the commands. */
	how: { where: string; commands: string[] };
}
export interface WslStatus {
	distro: string;
	version: number | null;
	steps: WslStep[];
	ready: boolean;
}

/** Runs wsl.exe; decodes UTF-16 output (distribution lists) or UTF-8. */
function wsl(args: string[], timeout = 15000): Promise<{ code: number; out: string }> {
	return new Promise((resolve) => {
		execFile('wsl.exe', args, { encoding: 'buffer', timeout, windowsHide: true }, (err, stdout) => {
			const buf = stdout as unknown as Buffer;
			const text = buf.includes(0) ? buf.toString('utf16le') : buf.toString('utf8');
			const code = err ? (typeof (err as { code?: unknown }).code === 'number' ? (err as { code: number }).code : 1) : 0;
			resolve({ code, out: text.replace(/\0/g, '').replace(/\r/g, '') });
		});
	});
}

let cached: { at: number; value: WslStatus } | null = null;

/** Probes WSL and the default distribution; cached for 30 s, null off Windows. */
export async function wslStatus(): Promise<WslStatus | null> {
	if (process.platform !== 'win32') return null;
	if (cached && Date.now() - cached.at < 30_000) return cached.value;

	const list = await wsl(['-l', '-v']);
	// "* Ubuntu    Running    2": the starred one is the default.
	const rows = list.code === 0 ? list.out.split('\n').map((l) => l.trim()).filter((l) => l && !/^NAME\s/i.test(l)) : [];
	const def = rows.find((r) => r.startsWith('*')) ?? rows[0] ?? '';
	const parts = def.replace(/^\*\s*/, '').split(/\s+/);
	const distro = parts[0] ?? '';
	const version = Number(parts.at(-1)) || null;

	let have = new Set<string>();
	let nodeVersion = '';
	if (distro) {
		const probe = await wsl(
			['-d', distro, '-e', 'sh', '-lc', 'for t in bash git curl node docker podman apptainer; do command -v $t >/dev/null 2>&1 && echo $t; done; node -v 2>/dev/null'],
			30000
		);
		const lines = probe.out.split('\n').map((l) => l.trim()).filter(Boolean);
		have = new Set(lines.filter((l) => !l.startsWith('v')));
		nodeVersion = lines.find((l) => /^v\d+/.test(l)) ?? '';
	}
	const nodeMajor = Number(nodeVersion.slice(1).split('.')[0]) || 0;
	const runtime = ['docker', 'podman', 'apptainer'].find((t) => have.has(t)) ?? '';
	const inLinux = `In ${distro || 'Ubuntu'} (open it from the Start menu, or type wsl in a terminal)`;

	const steps: WslStep[] = [
		{
			id: 'wsl',
			label: 'WSL 2 with a Linux distribution',
			ok: !!distro && version === 2,
			detail: distro ? `${distro}, WSL ${version ?? '?'}` : 'not installed',
			how: {
				where: 'In PowerShell, opened with "Run as administrator"; then restart Windows',
				commands: distro && version !== 2 ? [`wsl --set-version ${distro} 2`] : ['wsl --install -d Ubuntu']
			}
		},
		{
			id: 'basics',
			label: 'bash, git and curl',
			ok: have.has('bash') && have.has('git') && have.has('curl'),
			detail: ['bash', 'git', 'curl'].map((t) => `${t} ${have.has(t) ? 'yes' : 'no'}`).join(' | '),
			how: { where: inLinux, commands: ['sudo apt update && sudo apt install -y git curl'] }
		},
		{
			id: 'node',
			label: 'Node.js 20 or newer',
			ok: nodeMajor >= 20,
			detail: nodeVersion || 'not installed',
			how: {
				where: inLinux,
				commands: ['curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -', 'sudo apt install -y nodejs']
			}
		},
		{
			id: 'containers',
			label: 'A container app',
			ok: !!runtime,
			detail: runtime || 'none found',
			how: {
				where: `Either Docker Desktop for Windows, with "WSL integration" turned on for ${distro || 'Ubuntu'} in its settings; or, ${inLinux.toLowerCase()}`,
				commands: ['sudo apt install -y podman']
			}
		}
	];
	const value = { distro, version, steps, ready: steps.every((s) => s.ok) };
	cached = { at: Date.now(), value };
	return value;
}
