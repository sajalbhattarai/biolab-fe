/**
 * Shades: one hue per kind of block (genomes cyan, setup blue, results green...)
 * in every interface, mixed over the plain colours so strength 0 is the plain page.
 */

/** Hue per name: [light page, dark page], legible as title text and distinct in both themes. */
export const SHADES: Record<string, [string, string]> = {
	blue: ['#2563EB', '#7FA8FF'],
	cyan: ['#0E7490', '#4FC3DE'],
	violet: ['#6D28D9', '#B49BFF'],
	amber: ['#B45309', '#EBA94E'],
	green: ['#15803D', '#5FC684'],
	sky: ['#0369A1', '#6BBBEA'],
	rose: ['#BE123C', '#F58098'],
	slate: ['#475569', '#A3B2C4'],
	plum: ['#A21CAF', '#E290F0'],
	teal: ['#0F766E', '#3FD0BD'],
	indigo: ['#4338CA', '#A5B4FC']
};

/**
 * How far each part of a block is washed with its hue.
 *
 *   head   the banded header, as a percentage over the plain head colour
 *   rail   the hairline down the block's leading edge and under a page title
 *   title  how much of the hue the block's own heading takes
 *   field  the wash under a row, a chip or a striped table row
 *   accent whether controls inside the block follow the block's hue (as in "vivid")
 */
export const SHADE_LEVELS = {
	off: { head: 0, rail: 0, title: 0, field: 0, accent: 0 },
	trace: { head: 4, rail: 55, title: 70, field: 1.5, accent: 0 },
	soft: { head: 8, rail: 90, title: 100, field: 3.5, accent: 0 },
	medium: { head: 12, rail: 100, title: 100, field: 5, accent: 0 },
	vivid: { head: 16, rail: 100, title: 100, field: 6, accent: 100 },
	bold: { head: 26, rail: 100, title: 100, field: 9.5, accent: 100 }
} as const;

/** Shade levels, weakest first, for a control that steps through them. */
export const SHADE_ORDER = ['off', 'trace', 'soft', 'medium', 'vivid', 'bold'] as const;

export const SHADE_NAMES: Record<string, string> = {
	off: 'Off',
	trace: 'Trace',
	soft: 'Soft',
	medium: 'Medium',
	vivid: 'Vivid',
	bold: 'Bold'
};

export type ShadeLevel = keyof typeof SHADE_LEVELS;

/** Hue per page, read by top bars to colour the current page's underline (blocks map theirs in workspace.css). */
export const PAGE_SHADE: Record<string, keyof typeof SHADES> = {
	// In the order of the tabs, round the colour wheel: teal to amber.
	'/crisp/home': 'teal',
	'/crisp': 'cyan',
	'/crisp/genomes': 'blue',
	'/crisp/results': 'indigo',
	'/crisp/files': 'violet',
	'/crisp/view': 'violet',
	'/crisp/runs': 'plum',
	'/crisp/setup': 'rose',
	'/crisp/settings': 'amber'
};
