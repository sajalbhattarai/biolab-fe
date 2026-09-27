/**
 * Builds Crisp's CSS variables: colours from themeVars (preset, colour vision,
 * hand edits) plus Crisp's own --cr-* type scale, header tint, page width and
 * head wash, and the --at-* variables Atlas's parts read.
 */

import { fieldVars, textSize, themeVars, type UiPrefs } from '$lib/workspace/prefs';

/** Corners as chosen: sharp, soft (6px) or round. */
const radius = (p: UiPrefs) => (p.radius === 0 ? 3 : p.radius === 6 ? 6 : 10);

/** How strongly a block's head and a tag are washed with colour. */
const TINT = {
	plain: { head: 0, tag: 0.1 },
	soft: { head: 0.05, tag: 0.14 },
	strong: { head: 0.12, tag: 0.22 }
};

/* Wide and Full use the whole window (Full with a narrower gutter); Narrow keeps a reading width. */
const WIDTH = { narrow: '1180px', wide: '100%', full: '100%' };

export function crispVars(p: UiPrefs, dark: boolean): Record<string, string> {
	const base = themeVars(p, dark, 'crisp');
	const accent = base['--mg-accent'];
	const t = TINT[p.tint] ?? TINT.soft;
	// Desktop-app text size: 14px at Medium rather than a web page's 16.
	const fs = textSize(p, { s: 13, m: 14, l: 15.5 });
	const px = (n: number) => `${Math.round(n * 10) / 10}px`;
	// Shared parts read --mg-fs*, so pointing them at this scale makes them grow with the page.
	const dens = p.density === 'compact' ? { pad: 10, padY: 6, gap: 10, ctl: 28, ctlSm: 26, row: 30 } : { pad: 14, padY: 8, gap: 14, ctl: 32, ctlSm: 30, row: 36 };
	const ink = base['--mg-text'];
	// Light mode, default look (Modern, no hand-picked colours): pure white with the faintest greys.
	// A chosen preset or hand-picked colours keep their own backgrounds, as in dark mode.
	const own = p.colours?.light ?? {};
	const plainLight = !dark && (!p.palette || p.palette === 'crisp');
	const pure = plainLight && !['bg', 'surface', 'surface2', 'border', 'borderStrong'].some((k) => k in own);
	const WHITE: [string, string, string][] = [
		['--mg-bg', 'bg', '#FFFFFF'],
		['--mg-surface', 'surface', '#FFFFFF'],
		['--mg-surface-2', 'surface2', '#F5F6F7'],
		['--mg-border', 'border', '#E3E5E8'],
		['--mg-border-strong', 'borderStrong', '#C9CDD2'],
		['--mg-seg-sel', '', '#FFFFFF']
	];
	const white: Record<string, string> = plainLight ? Object.fromEntries(WHITE.filter(([, key]) => !key || !(key in own)).map(([v, , hex]) => [v, hex])) : {};
	return {
		...base,
		...white,
		'--mg-fs': px(fs),
		'--mg-fs-sm': px(fs * 0.93),
		'--mg-fs-xs': px(fs * 0.86),
		'--mg-fs-lg': px(fs * 1.14),
		'--mg-fs-xl': px(fs * 1.6),
		'--mg-pad': `${dens.pad}px`,
		'--mg-pad-y': `${dens.padY}px`,
		'--mg-gap': `${dens.gap}px`,
		...fieldVars(p, dens, fs),
		'--mg-r': `${radius(p)}px`,
		'--mg-r-sm': `${Math.max(2, radius(p) - 2)}px`,
		'--mg-shadow-sm': dark ? '0 1px 2px rgba(0, 0, 0, 0.4)' : '0 1px 2px rgba(16, 24, 40, 0.06)',
		'--mg-shadow-lg': dark ? '0 8px 24px rgba(0, 0, 0, 0.5)' : '0 8px 24px rgba(16, 24, 40, 0.12)',
		// Cards lie flat on the page, as the classic pages' panels do.
		'--cr-card-shadow': 'none',
		// Only what floats over the page (a menu, a drawer, a notice) casts one.
		'--cr-pop-shadow': dark ? '0 8px 24px rgba(0, 0, 0, 0.5)' : '0 8px 24px rgba(16, 24, 40, 0.14)',
		// One scale, relative to the text size the user picked.
		'--cr-fs-page': px(fs * 1.6),
		'--cr-fs-section': px(fs * 1.07),
		'--cr-fs-body': px(fs),
		'--cr-fs-meta': px(fs * 0.93),
		'--cr-fs-micro': px(fs * 0.86),
		// Headings are set in the same face as the text, just heavier.
		'--cr-display': 'var(--mg-font)',
		'--cr-gutter': p.pageWidth === 'full'
			? (p.density === 'compact' ? '12px' : '16px')
			: p.density === 'compact' ? 'clamp(12px, 1.4vw, 22px)' : 'clamp(14px, 1.8vw, 30px)',
		'--cr-pad': p.density === 'compact' ? '8px 12px' : '10px 14px',
		'--cr-width': WIDTH[p.pageWidth] ?? WIDTH.wide,
		'--cr-rule': dark ? `color-mix(in srgb, ${base['--mg-border']} 80%, ${base['--mg-surface']})` : '#ECEEF1',
		'--cr-zebra': `color-mix(in srgb, ${ink} ${dark ? 3 : 2.4}%, transparent)`,
		// A section is a grey panel on the page, as in the classic pages; what
		// is typed or picked inside it sits on white (--mg-surface).
		'--cr-card': dark ? `color-mix(in srgb, ${ink} 5%, ${base['--mg-bg']})` : pure ? '#F8F9FA' : `color-mix(in srgb, ${ink} 3%, ${base['--mg-bg']})`,
		'--cr-card-edge': dark ? `color-mix(in srgb, ${ink} 6%, transparent)` : pure ? '#ECEEF1' : base['--mg-border'],
		'--cr-card-inner': base['--mg-surface-2'],
		// Headers -- a block's, a table's, the top bar -- sit on grey.
		'--cr-head-bg': dark ? `color-mix(in srgb, ${ink} 7%, ${base['--mg-surface']})` : pure ? '#F5F6F7' : base['--mg-surface-2'],
		'--cr-bar-bg': dark ? `color-mix(in srgb, ${base['--mg-surface']} 82%, transparent)` : pure ? '#FFFFFF' : base['--mg-surface'],
		// Cards sit flat on the page: the hairline is enough.
		'--cr-shadow': 'none',
		// How much more of its hue a block's head takes than Shades alone gives it.
		'--cr-tint-head': `${t.head * 40}%`,
		'--cr-tag-bg': `color-mix(in srgb, currentColor ${t.tag * 100}%, transparent)`,
		'--cr-zebra-on': p.stripes ? 'var(--cr-zebra)' : 'transparent',
		// Titles by rank, all shades of the accent: a block's title dark, a
		// section label lighter, a field's label lightest (the page title has
		// the page's own hue, or the accent's ink when Shades is off).
		'--cr-t2': `color-mix(in srgb, ${accent} 58%, ${ink})`,
		'--cr-t3': `color-mix(in srgb, ${accent} 66%, ${base['--mg-text-2']})`,
		'--cr-t4': `color-mix(in srgb, ${accent} 34%, ${base['--mg-text-2']})`,
		// Fields and the heads of blocks take a little of the accent too.
		'--cr-field-edge': `color-mix(in srgb, ${accent} ${dark ? 22 : 16}%, ${base['--mg-border-strong'] ?? base['--mg-border']})`,
		'--cr-head-wash': `color-mix(in srgb, ${accent} ${t.head * 60}%, transparent)`,
		// Atlas's second colour, the warm one: what is happening now.
		'--cr-warm': dark ? '#F2B443' : '#C0620C',
		// How much of the page's colour washes the space behind its head.
		'--cr-glow': p.backdrop === 'plain' ? '0%' : dark ? '10%' : '7%',
		// The accent as chosen, kept aside: a block in vivid shades mixes its own
		// hue into --mg-accent, and everything else has to keep reading this one.
		'--mg-accent-base': accent,
		// The accent a shaded block falls back to; the shade palette comes from themeVars.
		'--sh': accent,
		// Atlas's parts (the evidence grid, the run ring, the journey) read --at-*:
		// here they wear Crisp's colours, and so follow the theme and colour vision.
		'--at-teal': accent,
		'--at-teal-hi': accent,
		'--at-teal-soft': `color-mix(in srgb, ${accent} 12%, transparent)`,
		'--at-on-teal': base['--mg-on-accent'],
		'--at-amber': 'var(--cr-warm)',
		'--at-amber-soft': 'color-mix(in srgb, var(--cr-warm) 15%, transparent)',
		'--at-amber-ink': 'var(--cr-warm)',
		'--at-ink': ink,
		'--at-ink-2': base['--mg-text-2'],
		'--at-ink-3': base['--mg-text-3'],
		'--at-line': base['--mg-border'],
		'--at-line-strong': base['--mg-border-strong'],
		'--at-track': `color-mix(in srgb, ${ink} 9%, transparent)`,
		'--at-glass-strong': base['--mg-surface'],
		'--at-bg-a': base['--mg-surface'],
		'--at-display': 'var(--mg-font)',
		...Object.fromEntries([0, 1, 2, 3, 4, 5].map((i) => [`--at-t${i}`, `var(--mg-tier-${i})`]))
	};
}
