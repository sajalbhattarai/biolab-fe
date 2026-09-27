/**
 * Interface preferences (interface, mode, theme, type, motion, layout), their
 * validation, and the CSS variables built from them. Shared by server and page,
 * so nothing Node-only is imported.
 */

import { FACE_IDS, face, isMono } from './fonts';
import { SHADES, SHADE_LEVELS } from './shades';
import { presetOf, TOKEN_KEYS } from './themes';
import { paletteFor, TYPICAL_CATEGORIES, TYPICAL_TIERS, VISION_IDS, type Vision } from './vision';

export type PanelId = 'status' | 'paths' | 'workflow' | 'run' | 'genomes' | 'activity' | 'results' | 'machine';

export interface PanelPref {
	id: PanelId;
	span: 1 | 2;
	visible: boolean;
}

/** Every face id in lib/workspace/fonts.ts. */
export const TYPEFACES = FACE_IDS;
export type Typeface = string;

export interface UiPrefs {
	/** 'crisp' is Modern (its pages live under /crisp); 'classic' the app's own pages. */
	interface: 'crisp' | 'classic';
	/** guided adds a step bar and highlights one panel at a time. */
	mode: 'guided' | 'clean';
	/** The first-launch choice between guided and clean has been made. */
	welcomed: boolean;
	theme: 'light' | 'dark' | 'system';
	/** An ACCENTS id, or a #RRGGBB colour. */
	accent: string;
	radius: 0 | 6 | 10;
	density: 'compact' | 'comfortable';
	textSize: 's' | 'm' | 'l';
	/** Text size as a multiple of the interface's medium size, 0.8 to 1.5 (S, M, L in TEXT_STEPS). */
	textScale: number;
	/** How tall input boxes, menus and buttons are, and how large what is typed in them: 0.8 to 1.6. */
	fieldScale: number;
	/** The interface face; code and paths use `monoface`. */
	typeface: Typeface;
	/** The face for logs, paths, sequences and anything else that must line up. */
	monoface: Typeface;
	motion: 'full' | 'subtle' | 'off';
	/** How fast animations play: 1 is normal, 2 twice as fast, 0.5 half speed. */
	speed: (typeof SPEEDS)[number];
	/** Collapsed sections, by id (e.g. "panel:run", "bench:genomes"). */
	folded: string[];
	/** Sections opened by hand that start collapsed (the other half of `folded`). */
	unfolded: string[];
	/** Widths in pixels of resizable side panes, by id (e.g. "app:nav"). */
	sizes: Record<string, number>;
	columns: 2 | 3;
	sidebar: 'full' | 'icons';
	/** How much colour the plain interface washes its headers and tags with. */
	tint: 'plain' | 'soft' | 'strong';
	/** How wide a page's content runs before it stops growing. */
	pageWidth: 'narrow' | 'wide' | 'full';
	/** Shade every other row of a long table. */
	stripes: boolean;
	/** How much each block carries its own hue in the plain interface. */
	shades: 'off' | 'trace' | 'soft' | 'medium' | 'vivid' | 'bold';
	/** How far text and lines are pushed away from the page behind them. */
	contrast: 'normal' | 'more' | 'high';
	/** A theme preset's id (themes.ts), or '' for the interface's own. */
	palette: string;
	/** Colours changed by hand in the theme editor, per light: token key -> #RRGGBB. */
	colours: { light: Record<string, string>; dark: Record<string, string> };
	/** Which colour vision the meaningful colours are chosen for (vision.ts). */
	vision: Vision;
	/** How weak a weak cone type is, 0.1 to 1: tunes how figures are recoloured and the preview. */
	visionStrength: number;
	/** Show the whole page as this vision sees it ('typical' is off); kept like any other choice. */
	previewVision: Vision;
	/** Recolour figures and images for the chosen vision (where that helps: red-green). */
	recolour: boolean;
	/** A symbol beside each state word -- a tick, an exclamation, a cross -- so colour is never the only sign. */
	marks: boolean;
	/** Crisp: a soft wash of the page's colour behind its head, as Atlas has, or a plain page. */
	backdrop: 'glow' | 'plain';
	/** How much the next run annotates (Custom uses the hand-picked tools), kept across restarts. */
	toolDepth: 'quick' | 'standard' | 'licensed' | 'custom';
	toolPick: string[] | null;
	panels: PanelPref[];
	/** Which arrangement of the board the saved panels belong to (see BOARD). */
	board: number;
	/** Unused; kept so older saved files still load. */
	step: 0 | 1 | 2 | 3;
}

export const SPEEDS = [0.5, 0.75, 1, 1.5, 2] as const;

export const PANEL_IDS: PanelId[] = ['status', 'paths', 'workflow', 'run', 'genomes', 'activity', 'results', 'machine'];

export const PANEL_TITLES: Record<PanelId, string> = {
	status: 'Pipeline status',
	paths: 'Input and output',
	workflow: 'Workflow setup',
	run: 'Run',
	genomes: 'Genomes',
	activity: 'Activity',
	results: 'Results',
	machine: 'This computer'
};

const layout = (rows: [PanelId, 1 | 2, boolean][]): PanelPref[] => rows.map(([id, span, visible]) => ({ id, span, visible }));

/**
 * Version of the board's panel arrangement (readiness, folders, plan, Start);
 * a saved board with another number is replaced, not merged.
 */
export const BOARD = 3;

export const LAYOUTS = {
	default: () =>
		layout([['status', 2, true], ['paths', 2, true], ['workflow', 2, true], ['run', 2, true], ['results', 1, false], ['activity', 1, false], ['genomes', 2, false], ['machine', 1, false]]),
	focus: () =>
		layout([['workflow', 2, true], ['run', 2, true], ['status', 2, false], ['paths', 2, false], ['results', 1, false], ['activity', 1, false], ['genomes', 2, false], ['machine', 1, false]]),
	monitor: () =>
		layout([['activity', 2, true], ['status', 1, true], ['results', 2, true], ['machine', 1, true], ['paths', 2, false], ['workflow', 2, false], ['genomes', 2, false], ['run', 1, false]])
};
export type LayoutName = keyof typeof LAYOUTS;

export const ACCENTS = [
	{ id: 'teal', name: 'Teal', light: '#0F766E', dark: '#2DB3A5' },
	{ id: 'blue', name: 'Blue', light: '#2757D6', dark: '#6C95F5' },
	{ id: 'violet', name: 'Violet', light: '#6B3FD4', dark: '#A78BFA' },
	{ id: 'amber', name: 'Amber', light: '#A15C07', dark: '#E7A63A' },
	{ id: 'rose', name: 'Rose', light: '#B4234A', dark: '#F07896' },
	{ id: 'graphite', name: 'Graphite', light: '#30343B', dark: '#C9CDD4' }
] as const;

export const DEFAULT_PREFS: UiPrefs = {
	interface: 'crisp',
	mode: 'clean',
	welcomed: false,
	theme: 'system',
	accent: 'teal',
	radius: 6,
	density: 'comfortable',
	textSize: 'm',
	textScale: 1,
	fieldScale: 1,
	typeface: 'helvetica',
	monoface: 'menlo',
	motion: 'full',
	speed: 1,
	folded: [],
	unfolded: [],
	sizes: {},
	columns: 3,
	sidebar: 'full',
	tint: 'soft',
	pageWidth: 'full',
	stripes: true,
	shades: 'soft',
	contrast: 'normal',
	palette: '',
	colours: { light: {}, dark: {} },
	vision: 'typical',
	visionStrength: 0.6,
	previewVision: 'typical',
	recolour: true,
	marks: false,
	backdrop: 'plain',
	toolDepth: 'standard',
	toolPick: null,
	panels: LAYOUTS.default(),
	board: BOARD,
	step: 0
};

/** Keys "Set as default" keeps: the look, not folded sections, pane widths or panels. */
export const LOOK_KEYS = [
	'interface',
	'mode',
	'theme',
	'accent',
	'radius',
	'density',
	'textSize',
	'textScale',
	'fieldScale',
	'typeface',
	'monoface',
	'motion',
	'speed',
	'columns',
	'sidebar',
	'tint',
	'pageWidth',
	'stripes',
	'shades',
	'contrast',
	'palette',
	'colours',
	'vision',
	'visionStrength',
	'previewVision',
	'recolour',
	'marks',
	'backdrop'
] as const satisfies readonly (keyof UiPrefs)[];

/** The look part of some preferences, checked as saved preferences are. */
export function lookOf(raw: unknown): Partial<UiPrefs> {
	if (!raw || typeof raw !== 'object') return {};
	const full = sanitizePrefs(raw) as unknown as Record<string, unknown>;
	const given = raw as Record<string, unknown>;
	return Object.fromEntries(LOOK_KEYS.filter((k) => k in given).map((k) => [k, full[k]])) as Partial<UiPrefs>;
}

const HEX = /^#[0-9a-fA-F]{6}$/;
const ID = /^[\w:.-]{1,80}$/;

function sizesOf(raw: unknown, fallback: Record<string, number>): Record<string, number> {
	if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return fallback;
	const out: Record<string, number> = {};
	for (const [k, v] of Object.entries(raw).slice(0, 60)) {
		if (ID.test(k) && typeof v === 'number' && Number.isFinite(v)) out[k] = Math.round(Math.min(1600, Math.max(0, v)));
	}
	return out;
}
const oneOf = <T>(v: unknown, allowed: readonly T[], fallback: T): T => (allowed.includes(v as T) ? (v as T) : fallback);

/** Validates hand-changed colours: known tokens only, as #RRGGBB. */
function coloursOf(raw: unknown, fallback: UiPrefs['colours']): UiPrefs['colours'] {
	if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return fallback;
	const r = raw as Record<string, unknown>;
	const side = (v: unknown) => {
		const out: Record<string, string> = {};
		if (v && typeof v === 'object' && !Array.isArray(v))
			for (const [k, c] of Object.entries(v)) if (TOKEN_KEYS.has(k) && typeof c === 'string' && HEX.test(c)) out[k] = c.toUpperCase();
		return out;
	};
	return { light: side(r.light), dark: side(r.dark) };
}

/** Clamps a slider's value to its range in steps of 0.05. */
function scaleOf(v: unknown, min: number, max: number, fallback: number): number {
	if (typeof v !== 'number' || !Number.isFinite(v)) return fallback;
	return Math.round(Math.min(max, Math.max(min, v)) * 20) / 20;
}

/** Keeps only valid values; anything missing or wrong falls back to `base`. */
export function sanitizePrefs(raw: unknown, base: UiPrefs = DEFAULT_PREFS): UiPrefs {
	const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
	const accent =
		typeof r.accent === 'string' && (HEX.test(r.accent) || ACCENTS.some((a) => a.id === r.accent)) ? r.accent : base.accent;
	let panels = base.panels;
	if (Array.isArray(r.panels) && r.board === BOARD) {
		const seen = new Set<PanelId>();
		const list: PanelPref[] = [];
		for (const p of r.panels as Record<string, unknown>[]) {
			const id = p?.id as PanelId;
			if (!PANEL_IDS.includes(id) || seen.has(id)) continue;
			seen.add(id);
			list.push({ id, span: p.span === 2 ? 2 : 1, visible: p.visible !== false });
		}
		for (const p of base.panels) if (!seen.has(p.id)) list.push({ ...p });
		panels = list;
	}
	return {
		// Every saved interface opens Modern.
		interface: 'crisp',
		mode: oneOf(r.mode, ['guided', 'clean'] as const, base.mode),
		welcomed: typeof r.welcomed === 'boolean' ? r.welcomed : base.welcomed,
		theme: oneOf(r.theme, ['light', 'dark', 'system'] as const, base.theme),
		accent,
		radius: oneOf(r.radius, [0, 6, 10] as const, base.radius),
		density: oneOf(r.density, ['compact', 'comfortable'] as const, base.density),
		textSize: oneOf(r.textSize, ['s', 'm', 'l'] as const, base.textSize),
		// A file with only S, M or L starts the slider at that step.
		textScale: scaleOf(r.textScale, 0.8, 1.5, TEXT_STEPS[oneOf(r.textSize, ['s', 'm', 'l'] as const, 'm')] ?? base.textScale),
		fieldScale: scaleOf(r.fieldScale, 0.8, 1.6, base.fieldScale),
		typeface: oneOf(r.typeface, TYPEFACES, base.typeface),
		monoface: oneOf(r.monoface, TYPEFACES, base.monoface),
		motion: oneOf(r.motion, ['full', 'subtle', 'off'] as const, base.motion),
		speed: oneOf(r.speed, SPEEDS, base.speed),
		folded: Array.isArray(r.folded)
			? [...new Set((r.folded as unknown[]).filter((x): x is string => typeof x === 'string' && ID.test(x)))].slice(0, 200)
			: base.folded,
		unfolded: Array.isArray(r.unfolded)
			? [...new Set((r.unfolded as unknown[]).filter((x): x is string => typeof x === 'string' && ID.test(x)))].slice(0, 200)
			: base.unfolded,
		sizes: sizesOf(r.sizes, base.sizes),
		columns: oneOf(r.columns, [2, 3] as const, base.columns),
		sidebar: oneOf(r.sidebar, ['full', 'icons'] as const, base.sidebar),
		tint: oneOf(r.tint, ['plain', 'soft', 'strong'] as const, base.tint),
		pageWidth: oneOf(r.pageWidth, ['narrow', 'wide', 'full'] as const, base.pageWidth),
		stripes: typeof r.stripes === 'boolean' ? r.stripes : base.stripes,
		shades: oneOf(r.shades, ['off', 'trace', 'soft', 'medium', 'vivid', 'bold'] as const, base.shades),
		contrast: oneOf(r.contrast, ['normal', 'more', 'high'] as const, base.contrast),
		palette: typeof r.palette === 'string' && (r.palette === '' || presetOf(r.palette, '').id === r.palette) ? r.palette : base.palette,
		colours: coloursOf(r.colours, base.colours),
		vision: oneOf(r.vision, VISION_IDS, base.vision),
		visionStrength:
			typeof r.visionStrength === 'number' && Number.isFinite(r.visionStrength)
				? Math.round(Math.min(1, Math.max(0.1, r.visionStrength)) * 20) / 20
				: base.visionStrength,
		previewVision: oneOf(r.previewVision, VISION_IDS, base.previewVision),
		recolour: typeof r.recolour === 'boolean' ? r.recolour : base.recolour,
		marks: typeof r.marks === 'boolean' ? r.marks : base.marks,
		backdrop: oneOf(r.backdrop, ['glow', 'plain'] as const, base.backdrop),
		toolDepth: oneOf(r.toolDepth, ['quick', 'standard', 'licensed', 'custom'] as const, base.toolDepth),
		toolPick: Array.isArray(r.toolPick)
			? [...new Set(r.toolPick.filter((t): t is string => typeof t === 'string' && /^[\w.-]{1,40}$/.test(t)))].slice(0, 80)
			: r.toolPick === null
				? null
				: base.toolPick,
		panels,
		board: BOARD,
		step: oneOf(r.step, [0, 1, 2, 3] as const, base.step)
	};
}

// ---------------------------------------------------------------- theme

const rgb = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const mix = (a: string, b: string, w: number) =>
	'#' + rgb(a).map((v, i) => Math.round(v * (1 - w) + rgb(b)[i] * w).toString(16).padStart(2, '0')).join('');
const luminance = (h: string) => {
	const c = rgb(h).map((v) => {
		v /= 255;
		return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
	});
	return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
};

export function accentColor(p: UiPrefs, dark: boolean): string {
	if (HEX.test(p.accent)) return p.accent.toUpperCase();
	const a = ACCENTS.find((x) => x.id === p.accent) ?? ACCENTS[0];
	return dark ? a.dark : a.light;
}

/** Status colours for typical vision: [ok, warn, danger]. */
const STATUS = { light: ['#2F7A4D', '#95600A', '#B3261E'], dark: ['#6FAF86', '#D9A441', '#EC7B68'] };
/** "No tier", beside the tier colours. */
const NO_TIER = { light: '#C3CFCB', dark: '#4A5654' };

/**
 * Resolves every theme-editor colour: preset neutrals, then status, section and
 * tier colours (colour-vision palette if chosen), then hand edits, then contrast.
 */
export function resolveColours(p: UiPrefs, dark: boolean, preset = 'paper'): Record<string, string> {
	const mode = dark ? 'dark' : 'light';
	const theme = presetOf(p.palette, preset);
	const vision = paletteFor(p.vision, dark);
	const status = vision?.status ?? theme.status?.[mode] ?? STATUS[mode];
	const tiers = vision?.tiers ?? [...TYPICAL_TIERS, NO_TIER[mode]];
	const shades = Object.keys(SHADES);
	const out: Record<string, string> = {
		...theme[mode],
		ok: status[0],
		warn: status[1],
		danger: status[2],
		...Object.fromEntries(shades.map((name, i) => [`sh-${name}`, vision?.shades?.[i] ?? SHADES[name][dark ? 1 : 0]])),
		...Object.fromEntries(tiers.map((c, i) => [`tier-${i}`, c])),
		...p.colours[mode]
	};

	// Contrast applies last and moves only text and lines, not surfaces.
	const boost = CONTRAST[p.contrast] ?? 0;
	if (boost) {
		const far = dark ? '#FFFFFF' : '#000000';
		for (const k of ['text', 'text2', 'text3']) out[k] = mixHex(out[k], far, boost);
		// Lines move towards the text colour rather than black, staying in the palette.
		for (const k of ['border', 'borderStrong']) out[k] = mixHex(out[k], out.text, boost * 0.55);
	}
	return out;
}

const CONTRAST: Record<UiPrefs['contrast'], number> = { normal: 0, more: 0.3, high: 0.62 };

/** Mixes two #RRGGBB colours; t = 0 is all `a`, t = 1 is all `b`. */
function mixHex(a: string, b: string, t: number): string {
	if (!/^#[0-9a-fA-F]{6}$/.test(a) || !/^#[0-9a-fA-F]{6}$/.test(b)) return a;
	const part = (s: string, i: number) => parseInt(s.slice(i, i + 2), 16);
	const to = (x: number, y: number) =>
		Math.round(x + (y - x) * t)
			.toString(16)
			.padStart(2, '0');
	return `#${to(part(a, 1), part(b, 1))}${to(part(a, 3), part(b, 3))}${to(part(a, 5), part(b, 5))}`.toUpperCase();
}

/** Where Small, Medium and Large sit on the text-size slider. */
export const TEXT_STEPS: Record<UiPrefs['textSize'], number> = { s: 0.9, m: 1, l: 1.15 };

/** Returns the S, M or L a slider value sits on, or '' between them. */
export const textStep = (scale: number) => (Object.entries(TEXT_STEPS).find(([, v]) => v === scale)?.[0] ?? '') as UiPrefs['textSize'] | '';

/** Returns body text size in pixels: `scale.m` times the slider, a little smaller for monospace faces. */
export function textSize(p: UiPrefs, scale: Record<UiPrefs['textSize'], number> = { s: 14, m: 15, l: 16 }): number {
	return scale.m * (p.textScale || 1) * (isMono(p.typeface) ? 0.92 : 1);
}

/** Builds control heights and typed-text size scaled by the field-size slider. */
export function fieldVars(p: UiPrefs, dens: { ctl: number; ctlSm: number; row: number }, fs: number, pad = 10): Record<string, string> {
	const k = p.fieldScale || 1;
	const px = (n: number) => `${Math.round(n * 10) / 10}px`;
	return {
		'--mg-ctl': px(dens.ctl * k),
		'--mg-ctl-sm': px(dens.ctlSm * k),
		'--mg-row': px(dens.row * Math.max(1, k)),
		// Text in a box grows half as fast as the box, so a tall box does not shout.
		'--mg-fs-field': px(fs * (1 + (k - 1) * 0.5)),
		'--mg-field-pad': px(pad * k)
	};
}

/** Builds the --mg-*, --sh-* and related CSS variables from the preferences. */
export function themeVars(p: UiPrefs, dark: boolean, preset = 'paper'): Record<string, string> {
	const shade = SHADE_LEVELS[p.shades] ?? SHADE_LEVELS.soft;
	const c = resolveColours(p, dark, preset);
	const base = dark
		? { neutral: '#6F6B64', scrim: 'rgba(0,0,0,.5)', shadowSm: '0 1px 1px rgba(0,0,0,.4)', shadowLg: '0 8px 30px rgba(0,0,0,.45)' }
		: { neutral: '#A29D94', scrim: 'rgba(30,28,24,.22)', shadowSm: '0 1px 1px rgba(30,28,24,.08)', shadowLg: '0 8px 30px rgba(30,28,24,.12)' };
	const accent = accentColor(p, dark);
	const L = luminance(accent);
	// Picks near-black or white, whichever contrasts more with the accent.
	const onAccent = (L + 0.05) / 0.0555 > 1.05 / (L + 0.05) ? '#0E1014' : '#FFFFFF';
	const dens = p.density === 'compact' ? { pad: 12, padY: 6, gap: 12, ctl: 32, ctlSm: 28, row: 34 } : { pad: 16, padY: 10, gap: 16, ctl: 38, ctlSm: 32, row: 42 };
	const fs = textSize(p);
	const px = (n: number) => `${Math.round(n * 10) / 10}px`;
	const vision = paletteFor(p.vision, dark);
	const categories = vision?.categories ?? TYPICAL_CATEGORIES;
	return {
		'--mg-bg': c.bg,
		'--mg-surface': c.surface,
		'--mg-surface-2': c.surface2,
		'--mg-border': c.border,
		'--mg-border-strong': c.borderStrong,
		'--mg-text': c.text,
		'--mg-text-2': c.text2,
		'--mg-text-3': c.text3,
		'--mg-ok': c.ok,
		'--mg-warn': c.warn,
		'--mg-danger': c.danger,
		'--mg-neutral': base.neutral,
		'--mg-scrim': base.scrim,
		'--mg-seg-sel': dark ? mix(c.surface2, c.borderStrong, 0.5) : c.surface,
		'--mg-shadow-sm': base.shadowSm,
		'--mg-shadow-lg': base.shadowLg,
		'--mg-accent': accent,
		// Kept aside because a block with a shade mixes its hue into --mg-accent;
		// everything that wants the chosen accent itself reads this one.
		'--mg-accent-base': accent,
		'--mg-on-accent': onAccent,
		'--mg-accent-soft': mix(c.surface, accent, dark ? 0.2 : 0.1),
		'--mg-accent-ink': dark ? mix(accent, '#FFFFFF', 0.3) : mix(accent, '#000000', 0.18),
		'--mg-accent-muted': mix(accent, c.surface, 0.5),
		'--mg-stripe-b': mix(accent, c.surface, 0.35),
		'--mg-danger-soft': mix(c.surface, c.danger, dark ? 0.18 : 0.08),
		'--mg-warn-soft': mix(c.surface, c.warn, dark ? 0.18 : 0.1),
		// Confidence tiers (highest ... low, then no tier) and the colours a
		// table gives other categories; both follow the colour-vision palette.
		...Object.fromEntries([0, 1, 2, 3, 4, 5].map((i) => [`--mg-tier-${i}`, c[`tier-${i}`]])),
		...Object.fromEntries(categories.map((h, i) => [`--mg-cat-${i}`, h])),
		'--mg-yes': vision ? c.ok : '#1E9E6A',
		'--mg-no': dark ? '#8F8B83' : '#8A857D',
		// Text on a tinted chip is its own colour held to a lightness that reads
		// on the tint: dark on a light page, light on a dark one (grid.ts, ink).
		'--mg-ink-lo': dark ? '0.8' : '0',
		'--mg-ink-hi': dark ? '1' : '0.5',
		'--mg-pad': px(dens.pad),
		'--mg-pad-y': px(dens.padY),
		'--mg-gap': px(dens.gap),
		...fieldVars(p, dens, fs - 1, 8),
		'--mg-fs': px(fs),
		'--mg-fs-sm': px(fs - 1),
		'--mg-fs-xs': px(fs - 2),
		'--mg-fs-lg': px(fs + 2),
		'--mg-fs-xl': px(fs + 8),
		'--mg-r': px(p.radius),
		'--mg-r-sm': px(Math.max(0, p.radius - 2)),
		// One hue per kind of block, and how strongly each part of it is washed;
		// an interface uses them by putting data-shade on a block (workspace.css).
		'--sh-head': `${shade.head}%`,
		'--sh-rail': `${shade.rail}%`,
		'--sh-title': `${shade.title}%`,
		'--sh-field': `${shade.field}%`,
		'--sh-accent': `${shade.accent}%`,
		...Object.fromEntries(Object.keys(SHADES).map((name) => [`--sh-${name}`, c[`sh-${name}`]])),
		'--mg-font': face(p.typeface).stack,
		'--mg-mono': face(p.monoface).stack
	};
}

// ---------------------------------------------------------------- motion

/** Returns the duration scale: 0 with motion off, shorter for subtle, divided by speed. */
export function motionScale(motion: UiPrefs['motion'], speed: number): number {
	return motion === 'off' ? 0 : (motion === 'subtle' ? 0.7 : 1) / speed;
}

/** Builds the --mo-* durations, easings and distances every animation reads. */
export function motionVars(motion: UiPrefs['motion'], speed: number): Record<string, string> {
	const k = motionScale(motion, speed);
	const ms = (n: number) => `${Math.round(n * k)}ms`;
	return {
		'--mo-k': String(k),
		// Looping animations (spinners, the breathing "now" cell) keep going at any speed.
		'--mo-loop': String(1 / speed),
		'--mo-1': ms(140),
		'--mo-2': ms(260),
		'--mo-3': ms(420),
		'--mo-ease': 'cubic-bezier(0.22, 1, 0.36, 1)',
		'--mo-ease-io': 'cubic-bezier(0.65, 0, 0.35, 1)',
		'--mo-rise': motion === 'full' ? '10px' : motion === 'subtle' ? '5px' : '0px'
	};
}

export const styleString = (vars: Record<string, string>) =>
	Object.entries(vars)
		.map(([k, v]) => `${k}: ${v}`)
		.join('; ');
