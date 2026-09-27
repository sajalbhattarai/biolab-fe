import { json } from '@sveltejs/kit';
import { PIPELINE_ROOT, getSettings } from '$lib/server/pipeline';
import { runtimeStatus } from '$lib/server/platform';
import { listGenomes } from '$lib/server/files';
import { activeRun } from '$lib/server/runs';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async () => {
	const settings = Object.fromEntries(getSettings().settings.map((s) => [s.key, s.value]));
	const { genomes } = listGenomes();
	const rt = await runtimeStatus();
	return json({
		pipelineRoot: PIPELINE_ROOT,
		runtime: { setting: rt.setting, active: rt.active, label: rt.label, ready: rt.ready },
		folders: {
			input: settings.USER_INPUT_DIR,
			output: settings.OUTPUT_ROOT,
			databases: settings.DB_ROOT
		},
		genomes: { total: genomes.length, described: genomes.filter((g) => g.domain && g.genetic_code).length },
		activeRun: activeRun()
	});
};
