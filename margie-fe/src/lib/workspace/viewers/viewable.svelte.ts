/**
 * Resolves a file URL an <img> or <iframe> can load: the URL itself here, or a
 * local copy fetched with sign-in where files need one (cluster).
 */

import { viewableUrl } from '$lib/api';

export function viewable(src: () => string) {
	let url = $state('');
	let error = $state('');
	$effect(() => {
		const from = src();
		let made = '';
		let live = true;
		url = '';
		error = '';
		viewableUrl(from)
			.then((u) => {
				if (u.startsWith('blob:')) made = u;
				if (live) url = u;
				else if (made) URL.revokeObjectURL(made);
			})
			.catch((e) => {
				if (live) error = e instanceof Error ? e.message : String(e);
			});
		return () => {
			live = false;
			if (made) URL.revokeObjectURL(made);
		};
	});
	return {
		get url() {
			return url;
		},
		get error() {
			return error;
		}
	};
}
