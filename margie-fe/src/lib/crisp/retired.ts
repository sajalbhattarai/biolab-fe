/**
 * Maps links to the retired Workspace (/app) and Atlas (/atlas) pages onto
 * Modern (/crisp): /jobs opens the runs, /atlas/genome/<name> that genome's results.
 */
const SAME = new Set(['genomes', 'results', 'files', 'runs', 'setup', 'settings', 'view', 'home']);

export function modernPath(rest: string, search: string): string {
	const [first = '', ...more] = rest.split('/').filter(Boolean);
	if (first === 'jobs') return `/crisp/runs${more.length ? `/${more.join('/')}` : ''}${search}`;
	if (first === 'genome' && more[0]) return `/crisp/results?g=${encodeURIComponent(more[0])}`;
	if (SAME.has(first)) return `/crisp/${[first, ...more].join('/')}${search}`;
	return `/crisp${search}`;
}

/** Maps a retired classic page to its Modern match; /view and /map keep their query, /jobs/<id> opens that run. */
export function classicPath(pathname: string, search: string): string {
	const [first = '', ...more] = pathname.split('/').filter(Boolean);
	const q = new URLSearchParams(search);
	switch (first) {
		case 'analyze':
			return '/crisp';
		case 'filesearch':
			return '/crisp/files';
		case 'jobs':
			return more[0] ? `/crisp/runs/${more[0]}` : '/crisp/runs';
		case 'view':
			return `/crisp/view${search}`;
		case 'map': {
			const organism = q.get('organism') ?? q.get('path')?.split('/').pop() ?? '';
			return organism ? `/crisp/results?g=${encodeURIComponent(organism)}&tab=map` : '/crisp/results';
		}
		case 'results':
			return '/crisp/results';
		case 'profile':
			return '/crisp/setup';
		default:
			return '/crisp';
	}
}
