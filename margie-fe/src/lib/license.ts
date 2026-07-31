/**
 * License-gate API client.
 *
 * The analyze page is gated: a user must accept the current licensing terms
 * (recorded once per account, re-prompted when the terms change) before running
 * any workflow. These helpers talk to the /v1/license backend routes.
 */
import { authHeaders } from '$lib/auth.js';

const API_URL =
	typeof window !== 'undefined' && window.location.hostname === 'localhost'
		? 'http://localhost:8000'
		: '';

export interface ToolProvenance {
	version?: string;
	downloaded_from?: string[];
	build_recipe?: string[];
	base_image?: string;
	notes?: string;
}

export interface CatalogTool {
	id: string;
	name: string;
	phase: number;
	category?: string;
	license: string;
	redistribution?: string;
	commercial_use?: string;
	academic_use?: string;
	research_use?: string;
	user_action: string;
	tier: string;
	obtain_url: string;
	allowed: string[];
	not_allowed: string[];
	citation?: string;
	license_quote?: string;
	license_quote_source?: string;
	license_quote_kind?: string;
	provenance?: ToolProvenance;
}

export interface Acknowledgment {
	id: string;
	label: string;
}

export interface UsageType {
	id: string;
	label: string;
}

export interface TermsPayload {
	terms_version: string;
	terms_sha256: string;
	terms_markdown: string;
	acknowledgments: Acknowledgment[];
	usage_types: UsageType[];
	catalog_version: string;
	gated_tools: CatalogTool[];
	tools: CatalogTool[];
	tier_definitions: Record<string, string>;
}

export interface LicenseStatus {
	accepted: boolean;
	current_terms_version: string;
	usage_type: string | null;
	licensed_tools: string[];
	disabled_tools: string[];
}

async function jsonOrThrow(res: Response): Promise<any> {
	if (!res.ok) {
		let detail = `Request failed (${res.status})`;
		try {
			const body = await res.json();
			if (body?.detail) detail = body.detail;
		} catch {
			/* ignore */
		}
		throw new Error(detail);
	}
	return res.json();
}

/** Returns the current user's acceptance status. Throws on 401 (caller handles). */
export async function fetchLicenseStatus(): Promise<LicenseStatus> {
	const res = await fetch(`${API_URL}/v1/license/status`, { headers: authHeaders() });
	if (res.status === 401) throw new Error('unauthorized');
	return jsonOrThrow(res);
}

/** Returns the full terms payload (text, catalog, acknowledgments). */
export async function fetchTerms(): Promise<TermsPayload> {
	const res = await fetch(`${API_URL}/v1/license/terms`, { headers: authHeaders() });
	if (res.status === 401) throw new Error('unauthorized');
	return jsonOrThrow(res);
}

/** Records the user's acceptance. Returns the acceptance result. */
export async function acceptTerms(body: {
	accepted_items: string[];
	terms_version: string;
	terms_sha256: string;
	usage_type: string;
	licensed_tools: string[];
}): Promise<any> {
	const res = await fetch(`${API_URL}/v1/license/accept`, {
		method: 'POST',
		headers: authHeaders(),
		body: JSON.stringify(body)
	});
	if (res.status === 401) throw new Error('unauthorized');
	return jsonOrThrow(res);
}

/** Revokes the current user's acceptance so the gate re-prompts next time. */
export async function revokeLicense(): Promise<{ revoked: boolean; rows_removed: number }> {
	const res = await fetch(`${API_URL}/v1/license/revoke`, {
		method: 'POST',
		headers: authHeaders()
	});
	if (res.status === 401) throw new Error('unauthorized');
	return jsonOrThrow(res);
}
