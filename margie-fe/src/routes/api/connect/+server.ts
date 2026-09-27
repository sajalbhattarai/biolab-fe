/**
 * Start page API (lib/connect): GET returns the chosen target and the status of each;
 * POST { action, ... } chooses, prepares, and connects to the HPC.
 * It runs ssh and writes ~/.ssh, so POST accepts only same-origin JSON (blocks cross-site requests).
 */

import { wslStatus } from '$lib/connect/wsl';
import { error, json } from '@sveltejs/kit';
import { answerPrompt, hpcStatus, replyQuestion, startHpc, stopHpc } from '$lib/connect/hpc';
import { createKey, installKey, keyStatus, privateKey, verifyKey } from '$lib/connect/keys';
import { clonePipeline, isPipeline, localStatus } from '$lib/connect/local';
import { DEFAULT_BACKEND_REPO, cleanCompute, expandHome, readSettings, validHost, validRemotePath, withRecentKey, writeSettings } from '$lib/connect/settings';
import { commitAndPush, pushSource, sourceStatus } from '$lib/connect/source';
import type { RequestHandler } from './$types';

async function snapshot(fetchSource = false) {
	const settings = readSettings();
	return {
		settings,
		local: localStatus(),
		/** Windows only: what running on this computer through WSL needs. */
		wsl: await wslStatus(),
		hpc: hpcStatus(),
		key: keyStatus(settings.sshKey || undefined),
		source: await sourceStatus(fetchSource)
	};
}

/** Returns the snapshot; ?fetch=1 also queries GitHub for the backend's branch (a few seconds). */
export const GET: RequestHandler = async ({ url }) => json(await snapshot(url.searchParams.has('fetch')));

const API = (import.meta.env.VITE_PUBLIC_API_URL as string | undefined) || 'http://localhost:8000';
const str = (v: unknown, max = 4096) => (typeof v === 'string' && v.length <= max ? v.trim() : '');

export const POST: RequestHandler = async ({ request, url }) => {
	const origin = request.headers.get('origin');
	if (origin && origin !== url.origin) error(403, 'Not from this app.');
	if (!request.headers.get('content-type')?.includes('application/json')) error(415, 'Send JSON.');
	const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
	if (!body) error(400, 'Send JSON.');

	const settings = readSettings();
	try {
		switch (body.action) {
			// ------------------------------------------------ where MARGIE runs
			case 'choose': {
				const target = body.target === 'local' || body.target === 'hpc' ? body.target : '';
				writeSettings({ target });
				break;
			}

			// ------------------------------------------------ this computer
			case 'local-clone':
				clonePipeline();
				break;
			case 'local-use': {
				const dir = expandHome(str(body.dir));
				if (!isPipeline(dir)) error(400, `No pipeline in ${dir || 'that folder'}: it should hold annotate.sh and pipeline.conf.sh.`);
				writeSettings({ pipelineRoot: dir, target: 'local' });
				process.env.MARGIE_PIPELINE_ROOT = dir;
				break;
			}

			// ------------------------------------------------ the HPC
			case 'hpc-start': {
				const host = str(body.host);
				const backendDir = str(body.backendDir);
				if (!validHost(host)) error(400, 'The HPC login should look like you@cluster.address.');
				if (!validRemotePath(backendDir)) error(400, 'The backend folder should be a full path on the HPC, starting with /.');
				writeSettings({ target: 'hpc', hpcHost: host, backendDir });
				const source = await sourceStatus();
				startHpc({
					host,
					backendDir,
					mode: body.mode === 2 ? 2 : 1,
					key: settings.sshKey,
					repo: settings.backendRepo || DEFAULT_BACKEND_REPO,
					branch: source.branch,
					local: source.local
				});
				break;
			}
			case 'hpc-reply':
				replyQuestion(str(body.id, 64), str(body.value, 64));
				break;

			// ------------------------------------------------ the backend's code
			case 'source-push':
				await pushSource();
				return json(await snapshot());
			case 'source-commit':
				await commitAndPush(str(body.message, 2000));
				return json(await snapshot());
			case 'hpc-stop':
				await stopHpc();
				break;
			case 'hpc-answer':
				answerPrompt(str(body.id, 64), typeof body.text === 'string' ? body.text : '', body.cancel === true);
				break;

			// ------------------------------------------------ passwordless login
			case 'key-setup': {
				const hpc = hpcStatus();
				if (hpc.phase !== 'ready') error(409, 'Connect to the HPC first: the key goes on over that connection.');
				const key = await createKey(settings.sshKey || undefined);
				// Installs over the open connection, so no password is asked.
				const added = await installKey(hpc.host, hpc.socket, key.path);
				const works = await verifyKey(settings.hpcHost || hpc.host, key.path);
				writeSettings({ sshKey: key.path, recentKeys: withRecentKey(settings.recentKeys, key.path) });
				return json({ ...(await snapshot()), result: { added, works } });
			}
			case 'key-verify': {
				const works = await verifyKey(settings.hpcHost, settings.sshKey || undefined);
				return json({ ...(await snapshot()), result: { works } });
			}
			case 'key-use': {
				// Uses an existing key set up by hand.
				const p = expandHome(str(body.path));
				if (!keyStatus(p).exists) error(400, `No key at ${p} (and ${p}.pub).`);
				writeSettings({ sshKey: p, recentKeys: withRecentKey(settings.recentKeys, p) });
				break;
			}
			case 'compute-set': {
				// Login or compute node and job size; applies from the next connection.
				try {
					writeSettings(cleanCompute(body));
				} catch (e) {
					error(400, e instanceof Error ? e.message : String(e));
				}
				break;
			}
			case 'key-clear': {
				// Stops using the key (the file stays); the next connection asks for the password.
				writeSettings({ sshKey: '' });
				break;
			}
			case 'key-forget-recent': {
				writeSettings({ recentKeys: '' });
				break;
			}

			// ------------------------------------------------ the MARGIE account
			case 'register': {
				// Sends the local key (or a pasted one) straight to the backend, so the browser never holds it.
				const [user, address] = settings.hpcHost.split('@');
				const pasted = str(body.privateKey, 20_000);
				const key = pasted || (settings.sshKey && keyStatus(settings.sshKey).exists ? privateKey(settings.sshKey) : '');
				if (!key) error(400, 'Set up passwordless login first, or paste a private key.');
				const res = await fetch(`${API}/v1/auth/register`, {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					body: JSON.stringify({
						username: str(body.username, 200),
						password: typeof body.password === 'string' ? body.password : '',
						cluster_host: address,
						cluster_username: user,
						private_key: key.trim() + '\n'
					})
				}).catch(() => null);
				if (!res) error(502, `Can't reach MARGIE's server at ${API}. Is the connection still open?`);
				const data = await res.json().catch(() => ({}));
				if (!res.ok) {
					const d = (data as { detail?: unknown }).detail;
					error(res.status, typeof d === 'string' ? d : 'The account could not be created.');
				}
				break;
			}

			default:
				error(400, 'Unknown action.');
		}
	} catch (e) {
		if (e && typeof e === 'object' && 'status' in e) throw e;
		error(400, e instanceof Error ? e.message : String(e));
	}
	return json(await snapshot());
};
