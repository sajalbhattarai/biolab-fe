/**
 * Downloads of cluster files. Cluster file links (lib/api fileUrl) cannot carry
 * the sign-in, so clicks on them are caught here, fetched with the sign-in and
 * saved under the file's own name.
 */

import { CLUSTER_FILE } from '$lib/api';
import { ui } from '$lib/workspace/ui.svelte';
import { fileBlob } from './backend';

/** Saves a blob under the given name through a temporary object URL. */
function save(blob: Blob, name: string) {
	const url = URL.createObjectURL(blob);
	const a = Object.assign(document.createElement('a'), { href: url, download: name });
	document.body.append(a);
	a.click();
	a.remove();
	setTimeout(() => URL.revokeObjectURL(url), 30_000);
}

/** Catches clicks on cluster file links for as long as the returned function is not called. */
export function catchDownloads(): () => void {
	const onClick = async (e: MouseEvent) => {
		if (e.defaultPrevented || e.button !== 0) return;
		const a = (e.target as Element | null)?.closest?.('a[href]') as HTMLAnchorElement | null;
		if (!a) return;
		const url = new URL(a.href, location.origin);
		if (url.origin !== location.origin || url.pathname !== CLUSTER_FILE) return;
		e.preventDefault();
		const path = url.searchParams.get('path') ?? '';
		const name = path.split('/').filter(Boolean).at(-1) ?? 'file';
		ui.notify(`Fetching ${name} from the cluster`, 'ok');
		try {
			save(await fileBlob(path), name);
		} catch (err) {
			ui.notify(err instanceof Error ? err.message : String(err), 'error');
		}
	};
	document.addEventListener('click', onClick, true);
	return () => document.removeEventListener('click', onClick, true);
}
