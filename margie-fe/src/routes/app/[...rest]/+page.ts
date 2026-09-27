import { redirect } from '@sveltejs/kit';
import { modernPath } from '$lib/crisp/retired';

/** Redirects links to the retired Workspace interface to the same page in Modern. */
export function load({ params, url }) {
	redirect(308, modernPath(params.rest, url.search));
}
