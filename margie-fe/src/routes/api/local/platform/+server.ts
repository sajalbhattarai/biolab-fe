import { json } from '@sveltejs/kit';
import { freeBytes, runtimeStatus } from '$lib/server/platform';
import { setting } from '$lib/server/pipeline';
import type { RequestHandler } from './$types';

/** Returns this computer's platform, container runtimes, and free space for images and databases. */
export const GET: RequestHandler = async () => {
	const rt = await runtimeStatus();
	const dbRoot = setting('DB_ROOT');
	const sifDir = setting('SIF_DIR');
	const [dbFree, sifFree] = await Promise.all([freeBytes(dbRoot), freeBytes(sifDir)]);
	return json({
		...rt.platform,
		runtime: { setting: rt.setting, active: rt.active, label: rt.label, ready: rt.ready },
		storage: {
			databases: { path: dbRoot, free: dbFree, needed: 170 * 1024 ** 3 },
			sif: { path: sifDir, free: sifFree, needed: 25 * 1024 ** 3 }
		}
	});
};
