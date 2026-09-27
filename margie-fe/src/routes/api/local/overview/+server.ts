import { json } from '@sveltejs/kit';
import os from 'node:os';
import { LICENCE_TOOLS, getSettings, licenceAccepted } from '$lib/server/pipeline';
import { freeBytes, runtimeStatus } from '$lib/server/platform';
import { hostPython } from '$lib/server/python';
import { inspectSetupRepo } from '$lib/server/setupRepo';
import type { RequestHandler } from './$types';

/**
 * Returns the Setup panel's quick checks: container runtime, build recipes,
 * Python, licences and platform (images and databases come from /api/check).
 */
export const GET: RequestHandler = async () => {
	const settings = Object.fromEntries(getSettings().settings.map((s) => [s.key, s.value]));
	const rt = await runtimeStatus();
	const repo = inspectSetupRepo(settings.SETUP_REPO ?? '');
	const intendedUse = (settings.LICENCE_INTENDED_USE ?? '').trim();
	const accepted = LICENCE_TOOLS.filter((t) => licenceAccepted(t, settings));
	const cpus = os.cpus();
	return json({
		user: os.userInfo().username,
		runtime: { setting: rt.setting, active: rt.active, label: rt.label, ready: rt.ready },
		runtimes: rt.platform.runtimes,
		recommended: rt.platform.recommended,
		repo: { ok: repo.ok, path: (settings.SETUP_REPO ?? '').trim() ? repo.path : '', reason: repo.reason ?? '', containers: repo.containers, databases: repo.databases },
		python: hostPython(),
		licences: { tools: LICENCE_TOOLS, accepted, intendedUse },
		gtdbtk: settings.RUN_GTDBTK === '1',
		machine: {
			os: rt.platform.os,
			arch: rt.platform.arch,
			chip: cpus[0]?.model?.trim() ?? '',
			cores: cpus.length,
			memory: os.totalmem(),
			diskFree: await freeBytes(settings.DB_ROOT ?? ''),
			dbRoot: settings.DB_ROOT ?? ''
		}
	});
};
