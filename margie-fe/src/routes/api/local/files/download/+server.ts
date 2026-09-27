import { error } from '@sveltejs/kit';
import fs from 'node:fs';
import { Readable } from 'node:stream';
import { FileError, openDownload } from '$lib/server/files';
import type { RequestHandler } from './$types';

const TYPES: Record<string, string> = {
	'.html': 'text/html; charset=utf-8',
	'.htm': 'text/html; charset=utf-8',
	'.svg': 'image/svg+xml',
	'.png': 'image/png',
	'.jpg': 'image/jpeg',
	'.jpeg': 'image/jpeg',
	'.gif': 'image/gif',
	'.webp': 'image/webp',
	'.pdf': 'application/pdf',
	'.json': 'application/json; charset=utf-8',
	'.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
};

const EMBED_STYLE = `<style>
@media (min-width: 520px) {
  .wrap { flex-wrap: nowrap !important; max-width: none !important; padding: 12px !important; gap: 12px !important; }
  .left { flex: 1 1 auto !important; min-width: 0 !important; }
  .right { flex: 0 0 min(380px, 42%) !important; min-width: 210px !important; position: sticky; top: 12px;
           align-self: flex-start; max-height: calc(100vh - 24px); overflow: auto; }
}
@media (min-width: 900px) and (min-height: 820px) {
  .right { flex: 0 0 min(560px, 40%) !important; }
  #circPlate { max-width: min(100%, calc(100vh - 180px)) !important; }
}
</style>`;

/**
 * ?path= streams a file; &inline=1 lets the browser display it instead of
 * saving it; &embed=1 (HTML) adjusts the page for a frame inside the GUI.
 */
export const GET: RequestHandler = async ({ url }) => {
	let file;
	try {
		file = openDownload(url.searchParams.get('path') ?? '');
	} catch (e) {
		if (e instanceof FileError) error(e.status, e.message);
		throw e;
	}
	const inline = url.searchParams.get('inline') === '1';
	const ext = file.name.slice(file.name.lastIndexOf('.')).toLowerCase();
	const type = TYPES[ext] ?? (inline ? 'text/plain; charset=utf-8' : 'application/octet-stream');
	const headers: Record<string, string> = {
		'content-type': type,
		'content-length': String(file.size),
		'content-disposition': `${inline ? 'inline' : 'attachment'}; filename="${file.name.replace(/"/g, '')}"`
	};
	// Sandboxed HTML gets an opaque origin, so hooks.server.ts refuses its /api calls;
	// allow-downloads lets the genome viewer save its own files. SVG gets no scripts.
	if (type.startsWith('text/html')) headers['content-security-policy'] = 'sandbox allow-scripts allow-downloads';
	else if (type.startsWith('image/svg')) headers['content-security-policy'] = 'sandbox';
	// &embed=1 keeps the genome viewer's details panel beside the map in a narrow frame.
	if (inline && type.startsWith('text/html') && url.searchParams.get('embed') === '1') {
		const html = fs.readFileSync(file.abs, 'utf8').replace(/<\/head>/i, `${EMBED_STYLE}</head>`);
		headers['content-length'] = String(Buffer.byteLength(html));
		return new Response(html, { headers });
	}
	return new Response(Readable.toWeb(fs.createReadStream(file.abs)) as ReadableStream, { headers });
};
