import { json } from '@sveltejs/kit';
import { listResults } from '$lib/server/results';
import type { RequestHandler } from './$types';

/**
 * Lists every organism with results: per-tool output under
 * <OUTPUT_ROOT>/<tool>/<genome>/ and final products under <GENOME_RESULTS_DIR>/<genome>/.
 */
export const GET: RequestHandler = async () => json(listResults());
