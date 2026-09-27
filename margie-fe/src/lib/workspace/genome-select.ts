/**
 * Selects genomes by a case-insensitive pattern: comma-separated terms, a name
 * matching any of them:
 *
 *   a           starts with "a"
 *   a-c         starts with a letter from a to c
 *   1-9         starts with a digit from 1 to 9
 *   GCA*        a glob over the whole file name
 *   *.fasta     likewise -- the extension is part of the name
 *   "my file"   quoted, for a name with a comma or a space in it
 */

export type Term =
	| { kind: 'range'; from: string; to: string }
	| { kind: 'glob'; re: RegExp }
	| { kind: 'prefix'; text: string };

/** Splits on commas, but not inside quotes. */
function split(pattern: string): string[] {
	const out: string[] = [];
	let current = '';
	let quote = '';
	for (const ch of pattern) {
		if (quote) {
			if (ch === quote) quote = '';
			else current += ch;
		} else if (ch === '"' || ch === "'") {
			quote = ch;
		} else if (ch === ',') {
			out.push(current);
			current = '';
		} else {
			current += ch;
		}
	}
	out.push(current);
	return out.map((t) => t.trim()).filter(Boolean);
}

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export function parseSelection(pattern: string): Term[] {
	return split(pattern).map((term) => {
		// Only "x-y" with single characters is a range; longer terms are prefixes containing a dash.
		const range = /^(.)-(.)$/.exec(term);
		if (range) {
			const [from, to] = [range[1].toLowerCase(), range[2].toLowerCase()];
			// A backwards range ("c-a") means the same span.
			return { kind: 'range', from: from <= to ? from : to, to: from <= to ? to : from };
		}
		if (term.includes('*') || term.includes('?')) {
			const re = escape(term).replace(/\\\*/g, '.*').replace(/\\\?/g, '.');
			return { kind: 'glob', re: new RegExp(`^${re}$`, 'i') };
		}
		return { kind: 'prefix', text: term.toLowerCase() };
	});
}

export function matchesTerm(name: string, term: Term): boolean {
	const lower = name.toLowerCase();
	switch (term.kind) {
		case 'range': {
			const first = lower[0] ?? '';
			return first >= term.from && first <= term.to;
		}
		case 'glob':
			return term.re.test(name);
		case 'prefix':
			return lower.startsWith(term.text);
	}
}

/** Returns the names matching the pattern; an empty pattern matches nothing. */
export function selectByPattern(names: string[], pattern: string): string[] {
	const terms = parseSelection(pattern);
	if (!terms.length) return [];
	return names.filter((name) => terms.some((term) => matchesTerm(name, term)));
}

/** Describes a pattern in plain words before it is applied. */
export function describeSelection(pattern: string): string {
	const terms = parseSelection(pattern);
	if (!terms.length) return '';
	return terms
		.map((t) =>
			t.kind === 'range' ? `${t.from}–${t.to}` : t.kind === 'glob' ? t.re.source.slice(1, -1).replace(/\\/g, '') : `${t.text}…`
		)
		.join(', ');
}
