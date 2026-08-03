/**
 * Shared helpers for working with the backend's dotted configurable_params
 * paths (e.g. "margie_sb.input_path", "compute.cluster_default.account")
 * against the nested config/formValues objects read from and written to
 * GET/PUT /v1/ssh/config. Used by both the Profile page (full config form)
 * and the Analyze page (inline per-workflow path settings).
 */

// Per-workflow root-path settings (sif_path, db_root, input_path, output_path).
export const PATH_PARAM_KEYS = ['sif_path', 'db_root', 'input_path', 'output_path'];

// Extra workflow-scoped storage paths that do not fit the simple two-part
// '<workflow>.<key>' convention but should still appear under Workflow Settings.
const EXTENDED_WORKFLOW_PATH_PARAMS = new Set([
	'margie_sb.operon_database.occ_reference_pkl',
	'margie_sb.fingerprint_database.path',
	'margie_sb.genome_pool.path',
	'margie_sb.scoring_results_historical.path',
	'margie_sb.final_tables_depot.path',
	'margie_sb.report_figures.operon_db',
	'margie_sb.sqlite_pipeline_snapshot.path',
]);

export function isWorkflowPathParam(param: string): boolean {
	if (EXTENDED_WORKFLOW_PATH_PARAMS.has(param)) {
		return true;
	}
	const parts = param.split('.');
	return parts.length === 2 && PATH_PARAM_KEYS.includes(parts[1]);
}

export function getNestedValue(obj: any, path: string[]): any {
	return path.reduce((current, key) => current?.[key], obj);
}

export function setNestedValue(obj: any, path: string[], value: any) {
	const lastKey = path[path.length - 1];
	const parent = path.slice(0, -1).reduce((current, key) => {
		if (!current[key]) current[key] = {};
		return current[key];
	}, obj);
	parent[lastKey] = value;
}
