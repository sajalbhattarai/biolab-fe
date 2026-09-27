/** Wording shared by the genome reports: the gene caller and a methods paragraph with references. */

import { CITATIONS, MARGIE_CITATION } from './citations';
import type { GenomeSummary } from './data.svelte';

export const callerName = (s: GenomeSummary) =>
	s.geneCaller === 'rasttk' ? 'RASTtk' : s.geneCaller === 'prodigal' ? 'Prodigal' : s.geneCaller || '';

/** Builds a methods paragraph for the tools behind this genome's results, with references. */
export function methodsFor(s: GenomeSummary): { text: string; refs: string[] } {
	const used = s.tools.filter((t) => CITATIONS[t] && !['rasttk', 'prodigal', 'operon'].includes(t));
	const callerKey = s.geneCaller === 'rasttk' ? 'rasttk' : 'prodigal';
	const list = (xs: string[]) => (xs.length < 2 ? xs.join('') : `${xs.slice(0, -1).join(', ')} and ${xs.at(-1)}`);
	const text =
		`Genes were predicted with ${CITATIONS[callerKey].name}${s.geneticCode ? ` using genetic code ${s.geneticCode}` : ''}, ` +
		`and operons with ${CITATIONS.operon.name}. ` +
		(used.length ? `Proteins were annotated with ${list(used.map((t) => CITATIONS[t].name))}. ` : '') +
		'Results were combined, labelled and scored with MARGIE.';
	return { text, refs: [callerKey, 'operon', ...used].map((k) => CITATIONS[k].cite).concat(MARGIE_CITATION) };
}

/** Joins the methods paragraph and numbered references into one block of text to copy. */
export const methodsText = (m: { text: string; refs: string[] }) => `${m.text}\n\n${m.refs.map((r, i) => `${i + 1}. ${r}`).join('\n')}`;
