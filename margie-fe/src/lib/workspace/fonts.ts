/**
 * Typefaces MARGIE can use: system faces plus bundled IBM Plex Sans, IBM Plex
 * Mono and Bricolage Grotesque; nothing is fetched. `installed()` asks the
 * browser which system faces exist.
 */

export type FontKind = 'sans' | 'serif' | 'mono' | 'display';

export interface Face {
	id: string;
	name: string;
	kind: FontKind;
	/** The full CSS stack, including fallbacks. */
	stack: string;
	/** Bundled with the app, so always present. */
	bundled?: boolean;
}

const SANS_FALLBACK = 'system-ui, -apple-system, sans-serif';
const SERIF_FALLBACK = 'Georgia, "Times New Roman", serif';
const MONO_FALLBACK = 'ui-monospace, Menlo, Monaco, monospace';

const sans = (id: string, name: string, family = name): Face => ({
	id,
	name,
	kind: 'sans',
	stack: `"${family}", ${SANS_FALLBACK}`
});
const serif = (id: string, name: string, family = name): Face => ({
	id,
	name,
	kind: 'serif',
	stack: `"${family}", ${SERIF_FALLBACK}`
});
const mono = (id: string, name: string, family = name): Face => ({
	id,
	name,
	kind: 'mono',
	stack: `"${family}", ${MONO_FALLBACK}`
});
const display = (id: string, name: string, family = name): Face => ({
	id,
	name,
	kind: 'display',
	stack: `"${family}", ${SANS_FALLBACK}`
});

export const FACES: Face[] = [
	// ---------------------------------------------------------------- sans
	{ id: 'system', name: 'System', kind: 'sans', stack: `system-ui, -apple-system, "Segoe UI", sans-serif` },
	{ id: 'helvetica', name: 'Helvetica Neue', kind: 'sans', stack: `"Helvetica Neue", Helvetica, Arial, sans-serif` },
	{ id: 'plex', name: 'IBM Plex Sans', kind: 'sans', stack: `"IBM Plex Sans", ${SANS_FALLBACK}`, bundled: true },
	sans('arial', 'Arial'),
	sans('avenir', 'Avenir'),
	sans('avenirnext', 'Avenir Next'),
	sans('optima', 'Optima'),
	sans('futura', 'Futura'),
	sans('gillsans', 'Gill Sans'),
	sans('lucida', 'Lucida Grande'),
	sans('verdana', 'Verdana'),
	sans('tahoma', 'Tahoma'),
	sans('trebuchet', 'Trebuchet MS'),
	sans('geneva', 'Geneva'),
	sans('segoe', 'Segoe UI'),
	sans('inter', 'Inter'),
	sans('roboto', 'Roboto'),
	sans('notosans', 'Noto Sans'),
	sans('opensans', 'Open Sans'),
	sans('lato', 'Lato'),
	sans('sourcesans', 'Source Sans 3'),
	sans('ptsans', 'PT Sans'),
	sans('ubuntu', 'Ubuntu'),
	sans('firasans', 'Fira Sans'),
	sans('worksans', 'Work Sans'),
	sans('nunito', 'Nunito'),
	sans('rubik', 'Rubik'),
	sans('manrope', 'Manrope'),
	sans('karla', 'Karla'),
	sans('dmsans', 'DM Sans'),
	sans('helvetica-classic', 'Helvetica'),

	// --------------------------------------------------------------- serif
	serif('georgia', 'Georgia'),
	serif('times', 'Times New Roman'),
	serif('palatino', 'Palatino'),
	serif('baskerville', 'Baskerville'),
	serif('didot', 'Didot'),
	serif('hoefler', 'Hoefler Text'),
	serif('garamond', 'Apple Garamond', 'Garamond'),
	serif('iowan', 'Iowan Old Style'),
	serif('charter', 'Charter'),
	serif('newyork', 'New York'),
	serif('cochin', 'Cochin'),
	serif('bodoni', 'Bodoni 72'),
	serif('bigcaslon', 'Big Caslon'),
	serif('athelas', 'Athelas'),
	serif('sourceserif', 'Source Serif 4'),
	serif('merriweather', 'Merriweather'),
	serif('librebaskerville', 'Libre Baskerville'),
	serif('lora', 'Lora'),
	serif('ptserif', 'PT Serif'),
	serif('crimson', 'Crimson Text'),

	// ---------------------------------------------------------------- mono
	{ id: 'menlo', name: 'Menlo', kind: 'mono', stack: `Menlo, ${MONO_FALLBACK}` },
	{ id: 'plexmono', name: 'IBM Plex Mono', kind: 'mono', stack: `"IBM Plex Mono", ${MONO_FALLBACK}`, bundled: true },
	mono('monaco', 'Monaco'),
	mono('sfmono', 'SF Mono'),
	mono('courier', 'Courier New'),
	mono('andale', 'Andale Mono'),
	mono('consolas', 'Consolas'),
	mono('firacode', 'Fira Code'),
	mono('jetbrains', 'JetBrains Mono'),
	mono('sourcecode', 'Source Code Pro'),
	mono('robotomono', 'Roboto Mono'),
	mono('spacemono', 'Space Mono'),
	mono('inconsolata', 'Inconsolata'),
	mono('ubuntumono', 'Ubuntu Mono'),
	mono('ptmono', 'PT Mono'),
	mono('couriernew', 'Courier'),

	// ------------------------------------------------------------- display
	{ id: 'bricolage', name: 'Bricolage Grotesque', kind: 'display', stack: `"Bricolage Grotesque Variable", "Bricolage Grotesque", ${SANS_FALLBACK}`, bundled: true },
	display('americantypewriter', 'American Typewriter'),
	display('copperplate', 'Copperplate'),
	display('impact', 'Impact'),
	display('chalkboard', 'Chalkboard SE'),
	display('markerfelt', 'Marker Felt'),
	display('bradley', 'Bradley Hand'),
	display('snell', 'Snell Roundhand'),
	display('luminari', 'Luminari'),
	display('phosphate', 'Phosphate'),
	display('silom', 'Silom'),
	display('herculanum', 'Herculanum'),
	display('trattatello', 'Trattatello')
];

export const FACE_IDS = FACES.map((f) => f.id);

const BY_ID = new Map(FACES.map((f) => [f.id, f]));

export const face = (id: string): Face => BY_ID.get(id) ?? FACES[0];

export const isMono = (id: string): boolean => face(id).kind === 'mono';

export const KIND_NAMES: Record<FontKind, string> = {
	sans: 'Sans serif',
	serif: 'Serif',
	mono: 'Monospace',
	display: 'Display'
};

/**
 * Checks with document.fonts.check whether a face is on the machine; bundled
 * faces, and every face before the font set is ready, count as present.
 */
export function installed(f: Face): boolean {
	if (f.bundled) return true;
	if (typeof document === 'undefined' || !document.fonts?.check) return true;
	// Only the first family is checked; the fallbacks would always match.
	const first = f.stack.split(',')[0].trim().replace(/^["']|["']$/g, '');
	if (!first || first === 'system-ui') return true;
	try {
		return document.fonts.check(`12px "${first}"`);
	} catch {
		return true;
	}
}
