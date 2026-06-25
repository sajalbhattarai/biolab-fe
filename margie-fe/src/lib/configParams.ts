/**
 * Shared helpers for working with the backend's dotted configurable_params
 * paths (e.g. "margie_sb.input_path", "compute.cluster_default.account")
 * against the nested config/formValues objects read from and written to
 * GET/PUT /v1/ssh/config. Used by both the Profile page (full config form)
 * and the Analyze page (inline per-workflow path settings).
 */

// Per-workflow root-path settings (sif_path, db_root, input_path, output_path).
export const PATH_PARAM_KEYS = ['sif_path', 'db_root', 'input_path', 'output_path'];

export function isWorkflowPathParam(param: string): boolean {
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
