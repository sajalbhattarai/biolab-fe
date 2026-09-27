/**
 * Colour-vision support, shared by server and page (no Node-only code):
 *   simulate()       Machado, Oliveira & Fernandes (2009) cone model, luminance for monochromacy.
 *   FAMILY_PALETTES  offline-fitted status, tier, section and category colours per
 *                    deficiency family: hue kept, 4.5:1 text, pairs spread in CAM02-UCS.
 *   recolour()       daltonising for figures and fills (red-green only).
 */

export type Vision =
	| 'typical'
	| 'protanomaly'
	| 'deuteranomaly'
	| 'tritanomaly'
	| 'protanopia'
	| 'deuteranopia'
	| 'tritanopia'
	| 'achromatomaly'
	| 'achromatopsia';

type Axis = 'protan' | 'deutan' | 'tritan';
export type Family = Axis | 'achro';

export interface VisionInfo {
	id: Vision;
	/** The clinical name. */
	name: string;
	/** What it is in two words. */
	plain: string;
	group: 'typical' | 'anomalous' | 'dichromacy' | 'monochromacy';
	family: Family | null;
	/** Weak rather than missing: how weak is a setting (visionStrength). */
	graded: boolean;
	note: string;
	/** Roughly how common, for orientation only. */
	common: string;
}

export const VISIONS: VisionInfo[] = [
	{ id: 'typical', name: 'Typical', plain: 'Typical colour vision', group: 'typical', family: null, graded: false, note: 'All three cone types, working as usual.', common: '' },
	{ id: 'deuteranomaly', name: 'Deuteranomaly', plain: 'Partial green deficiency', group: 'anomalous', family: 'deutan', graded: true, note: 'Green cones shifted toward red: reds, greens, browns and oranges run together.', common: 'about 5 in 100 men' },
	{ id: 'protanomaly', name: 'Protanomaly', plain: 'Partial red deficiency', group: 'anomalous', family: 'protan', graded: true, note: 'Red cones shifted toward green: reds look duller and darker.', common: 'about 1 in 100 men' },
	{ id: 'tritanomaly', name: 'Tritanomaly', plain: 'Partial blue deficiency', group: 'anomalous', family: 'tritan', graded: true, note: 'Blue cones weak: blue and green, yellow and pink run together.', common: 'rare' },
	{ id: 'deuteranopia', name: 'Deuteranopia', plain: 'Complete green deficiency', group: 'dichromacy', family: 'deutan', graded: false, note: 'No working green cones: reds and greens look alike.', common: 'about 1 in 100 men' },
	{ id: 'protanopia', name: 'Protanopia', plain: 'Complete red deficiency', group: 'dichromacy', family: 'protan', graded: false, note: 'No working red cones: red is dark, and red and green look alike.', common: 'about 1 in 100 men' },
	{ id: 'tritanopia', name: 'Tritanopia', plain: 'Complete blue deficiency', group: 'dichromacy', family: 'tritan', graded: false, note: 'No working blue cones: blue and green, and yellow and pink, look alike.', common: 'about 1 in 10,000' },
	{ id: 'achromatomaly', name: 'Achromatomaly', plain: 'Partial colour deficiency', group: 'monochromacy', family: 'achro', graded: true, note: 'Very weak colour vision throughout, as in blue cone monochromacy.', common: 'rare' },
	{ id: 'achromatopsia', name: 'Achromatopsia', plain: 'Complete colour deficiency', group: 'monochromacy', family: 'achro', graded: false, note: 'Rod monochromacy: only light and dark are seen.', common: 'about 1 in 30,000' }
];

export const VISION_IDS = VISIONS.map((v) => v.id);
export const visionInfo = (v: Vision) => VISIONS.find((x) => x.id === v) ?? VISIONS[0];

/** Confidence tiers, highest first, as the figures and the Excel file colour them. */
export const TIER_NAMES = ['highest', 'high', 'medium', 'fair', 'low'] as const;
export const TYPICAL_TIERS = ['#1F77FF', '#00B84D', '#FFCC00', '#FF8C00', '#EE2233'];
/** Soft colours for other categories, in the order the values are most common. */
export const TYPICAL_CATEGORIES = ['#2F6FDE', '#1E9E6A', '#C8860A', '#8B5CF6', '#0E9AA7', '#D6456A', '#6B7280', '#E0702B', '#4F7F2F', '#B04FB8', '#3D8FC4', '#9C6B3F'];

interface FamilyPalette {
	/** ok, warn, danger: text colours. */
	status: { light: string[]; dark: string[] };
	/** highest ... low, then no tier: fills. */
	tiers: { light: string[]; dark: string[] };
	/** In SHADES order (blue, cyan, violet, amber, green, sky, rose, slate, plum). None for
	 *  monochromacy: nine hues cannot be told apart by lightness alone, so the usual ones stay. */
	shades?: { light: string[]; dark: string[] };
	categories: string[];
}


/** Which palette family a vision uses, or null for typical vision. */
export const familyOf = (v: Vision): Family | null => visionInfo(v).family;

/** How far along its axis a vision is: 1 for a missing cone type, the chosen strength for a weak one. */
export function severityOf(v: Vision, strength: number): number {
	const info = visionInfo(v);
	if (!info.family) return 0;
	return info.graded ? Math.min(1, Math.max(0, strength)) : 1;
}

// ---------------------------------------------------------------- colour maths

type Rgb = [number, number, number];
type Mat = number[]; // 3x3, row-major

const IDENTITY: Mat = [1, 0, 0, 0, 1, 0, 0, 0, 1];
const LUMA = [0.2126, 0.7152, 0.0722];

const toLinear = (c: number) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const toGamma = (c: number) => {
	const v = Math.min(1, Math.max(0, c));
	return v <= 0.0031308 ? v * 12.92 : 1.055 * v ** (1 / 2.4) - 0.055;
};
export const HEX = /^#[0-9a-fA-F]{6}$/;
const rgbOf = (hex: string): Rgb => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255) as Rgb;
const hexOf = (rgb: Rgb) =>
	'#' + rgb.map((v) => Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16).padStart(2, '0')).join('').toUpperCase();
const linearOf = (hex: string): Rgb => rgbOf(hex).map(toLinear) as Rgb;
const hexOfLinear = (rgb: Rgb) => hexOf(rgb.map(toGamma) as Rgb);
const apply = (m: Mat, [r, g, b]: Rgb): Rgb => [m[0] * r + m[1] * g + m[2] * b, m[3] * r + m[4] * g + m[5] * b, m[6] * r + m[7] * g + m[8] * b];
const mul = (a: Mat, b: Mat): Mat =>
	[0, 1, 2].flatMap((i) => [0, 1, 2].map((j) => a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j]));
const lerp = (a: Mat, b: Mat, t: number): Mat => a.map((v, i) => v * (1 - t) + b[i] * t);

/** Returns the simulation matrix in linear RGB. */
export function simMatrix(v: Vision, strength: number): Mat {
	const fam = familyOf(v);
	const s = severityOf(v, strength);
	if (!fam || s <= 0) return IDENTITY;
	if (fam === 'achro') return lerp(IDENTITY, [...LUMA, ...LUMA, ...LUMA], s);
	const table = MACHADO[fam];
	const x = s * 10;
	const i = Math.min(9, Math.floor(x));
	return lerp(table[i], table[i + 1], x - i);
}

/** Returns the recolouring matrix in linear RGB, or null where recolouring does not help. */
export function recolourMatrix(v: Vision, strength: number): Mat | null {
	const fam = familyOf(v);
	const e = fam && fam !== 'achro' ? REDISTRIBUTE[fam] : undefined;
	if (!e) return null;
	const s = simMatrix(v, strength);
	const lost = IDENTITY.map((x, i) => x - s[i]);
	// out = in + E (in - S in)
	return IDENTITY.map((x, i) => x + mul(e, lost)[i]);
}

/** Simulates how a colour looks with vision `v`. */
export const simulate = (hex: string, v: Vision, strength = 1) =>
	HEX.test(hex) && v !== 'typical' ? hexOfLinear(apply(simMatrix(v, strength), linearOf(hex))) : hex;

/** Moves a colour into what vision `v` can tell apart; unchanged where that does not help. */
export function recolour(hex: string, v: Vision, strength = 1): string {
	const m = HEX.test(hex) ? recolourMatrix(v, strength) : null;
	return m ? hexOfLinear(apply(m, linearOf(hex))) : hex;
}

/** An SVG feColorMatrix's values for a 3x3 matrix, alpha untouched. */
export const feValues = (m: Mat) => `${m[0]} ${m[1]} ${m[2]} 0 0 ${m[3]} ${m[4]} ${m[5]} 0 0 ${m[6]} ${m[7]} ${m[8]} 0 0 0 0 0 1 0`;

/** WCAG relative luminance and contrast ratio. */
export const luminance = (hex: string) => linearOf(hex).reduce((a, c, i) => a + c * LUMA[i], 0);
export function contrast(a: string, b: string): number {
	const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p);
	return (x + 0.05) / (y + 0.05);
}

/** Converts to OKLab (Ottosson) for perceptual distances. */
function oklab(hex: string): Rgb {
	const [r, g, b] = linearOf(hex);
	const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
	const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
	const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
	return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s, 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s];
}

/** Returns how different two colours look (OKLab x 100): under 6 alike, 6-9 close, above 9 distinct. */
export function distance(a: string, b: string, v: Vision = 'typical', strength = 1): number {
	const [p, q] = [oklab(simulate(a, v, strength)), oklab(simulate(b, v, strength))];
	return Math.hypot(p[0] - q[0], p[1] - q[1], p[2] - q[2]) * 100;
}
export const ALIKE = 6;
export const CLOSE = 9;

// ---------------------------------------------------------------- palettes

/** Returns a family's palette in the given light, or null for typical vision. */
export function paletteFor(v: Vision, dark: boolean) {
	const fam = familyOf(v);
	if (!fam) return null;
	const p = FAMILY_PALETTES[fam];
	const mode = dark ? 'dark' : 'light';
	return { status: p.status[mode], tiers: p.tiers[mode], shades: p.shades?.[mode], categories: p.categories };
}

/** How many category colours a table cycles through. */
export const categoryCount = (v: Vision) => (familyOf(v) ? 8 : TYPICAL_CATEGORIES.length);

/** The tier colours as make-final-excel.py tints a whole row: 72% of the way to white. */
const ROW_TINT = 0.72;
const TIER_ROWS = TYPICAL_TIERS.map((h) => hexOf(rgbOf(h).map((c) => c + (1 - c) * ROW_TINT) as Rgb));

/**
 * Maps a workbook colour for this reader: tier colours (or their row tints)
 * become the current tier colour; anything else is recoloured for `v`.
 */
export function dataColour(hex: string, v: Vision, strength: number): string {
	if (!HEX.test(hex)) return hex;
	const up = hex.toUpperCase();
	const i = TYPICAL_TIERS.indexOf(up);
	if (i >= 0) return `var(--mg-tier-${i})`;
	const row = TIER_ROWS.indexOf(up);
	if (row >= 0) return `color-mix(in srgb, var(--mg-tier-${row}) ${Math.round((1 - ROW_TINT) * 100)}%, #FFFFFF)`;
	return v === 'typical' ? hex : recolour(hex, v, strength);
}

// ---------------------------------------------------------------- tables
// Machado et al.'s matrices (as shipped by colorspacious), severity 0, 0.1, ... 1;
// rows sum to 1 so greys stay grey.

const MACHADO: Record<Axis, number[][]> = {
	protan: [
		[1, 0, 0, 0, 1, 0, 0, 0, 1],
		[0.856167, 0.182038, -0.038205, 0.029342, 0.955115, 0.015544, -0.00288, -0.001563, 1.004443],
		[0.734766, 0.334872, -0.069637, 0.05184, 0.919198, 0.028963, -0.004928, -0.004209, 1.009137],
		[0.630323, 0.465641, -0.095964, 0.069181, 0.890046, 0.040773, -0.006308, -0.007724, 1.014032],
		[0.539009, 0.579343, -0.118352, 0.082546, 0.866121, 0.051332, -0.007136, -0.011959, 1.019095],
		[0.458064, 0.679578, -0.137642, 0.092785, 0.846313, 0.060902, -0.007494, -0.016807, 1.024301],
		[0.38545, 0.769005, -0.154455, 0.100526, 0.829802, 0.069673, -0.007442, -0.02219, 1.029632],
		[0.319627, 0.849633, -0.169261, 0.106241, 0.815969, 0.07779, -0.007025, -0.028051, 1.035076],
		[0.259411, 0.923008, -0.18242, 0.110296, 0.80434, 0.085364, -0.006276, -0.034346, 1.040622],
		[0.203876, 0.990338, -0.194214, 0.112975, 0.794542, 0.092483, -0.005222, -0.041043, 1.046265],
		[0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998],
	],
	deutan: [
		[1, 0, 0, 0, 1, 0, 0, 0, 1],
		[0.866435, 0.177704, -0.044139, 0.049567, 0.939063, 0.01137, -0.003453, 0.007233, 0.99622],
		[0.760729, 0.319078, -0.079807, 0.090568, 0.889315, 0.020117, -0.006027, 0.013325, 0.992702],
		[0.675425, 0.43385, -0.109275, 0.125303, 0.847755, 0.026942, -0.00795, 0.018572, 0.989378],
		[0.605511, 0.52856, -0.134071, 0.155318, 0.812366, 0.032316, -0.009376, 0.023176, 0.9862],
		[0.547494, 0.607765, -0.155259, 0.181692, 0.781742, 0.036566, -0.01041, 0.027275, 0.983136],
		[0.498864, 0.674741, -0.173604, 0.205199, 0.754872, 0.039929, -0.011131, 0.030969, 0.980162],
		[0.457771, 0.731899, -0.18967, 0.226409, 0.731012, 0.042579, -0.011595, 0.034333, 0.977261],
		[0.422823, 0.781057, -0.203881, 0.245752, 0.709602, 0.044646, -0.011843, 0.037423, 0.974421],
		[0.392952, 0.82361, -0.216562, 0.263559, 0.69021, 0.046232, -0.01191, 0.040281, 0.97163],
		[0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.01182, 0.04294, 0.968881],
	],
	tritan: [
		[1, 0, 0, 0, 1, 0, 0, 0, 1],
		[0.92667, 0.092514, -0.019184, 0.021191, 0.964503, 0.014306, 0.008437, 0.054813, 0.93675],
		[0.89572, 0.13333, -0.02905, 0.029997, 0.9454, 0.024603, 0.013027, 0.104707, 0.882266],
		[0.905871, 0.127791, -0.033662, 0.026856, 0.941251, 0.031893, 0.01341, 0.148296, 0.838294],
		[0.948035, 0.08949, -0.037526, 0.014364, 0.946792, 0.038844, 0.010853, 0.193991, 0.795156],
		[1.017277, 0.027029, -0.044306, -0.006113, 0.958479, 0.047634, 0.006379, 0.248708, 0.744913],
		[1.104996, -0.046633, -0.058363, -0.032137, 0.971635, 0.060503, 0.001336, 0.317922, 0.680742],
		[1.193214, -0.109812, -0.083402, -0.058496, 0.97941, 0.079086, -0.002346, 0.403492, 0.598854],
		[1.257728, -0.139648, -0.118081, -0.078003, 0.975409, 0.102594, -0.003316, 0.501214, 0.502102],
		[1.278864, -0.125333, -0.153531, -0.084748, 0.957674, 0.127074, -0.000989, 0.601151, 0.399838],
		[1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.3039],
	]
};

// Fitted per family: out = in + E (in - simulated).
const REDISTRIBUTE: Partial<Record<Axis, number[]>> = {
	protan: [0.6, 0.095, 1.241, 0.485, 1.445, -0.763, 0.305, -0.353, -0.212],
	deutan: [0.213, 0.038, 1.209, 0.65, 1.189, -1.021, 0.576, 0.285, 1.5]
};

export const FAMILY_PALETTES: Record<Family, FamilyPalette> = {
	protan: {
		status: { light: ['#2C49FE', '#87760D', '#7F0535'], dark: ['#7391FC', '#FCDE20', '#E66965'] },
		tiers: { light: ['#252A6A', '#0989E8', '#EFF223', '#AE7C0E', '#750104', '#D1D0D1'], dark: ['#3B40F4', '#AFD7FE', '#F2F4B2', '#E78814', '#BE0307', '#7C7F85'] },
		shades: { light: ['#816E9B', '#037F6C', '#5718AF', '#990125', '#3B801C', '#3A5FE3', '#8D4408', '#3A515B', '#740F56'], dark: ['#659AFF', '#00B497', '#E8B7FE', '#EFBD45', '#9CE79C', '#80DFE4', '#D68450', '#99A7B9', '#D670B1'] },
		categories: ['#AA7513', '#ACB8FB', '#9FD02A', '#950870', '#E24D76', '#8064E6', '#A30209', '#EBA99F']
	},
	deutan: {
		status: { light: ['#5063FE', '#946D11', '#6D204C'], dark: ['#6D92FE', '#FDDE0A', '#C96274'] },
		tiers: { light: ['#070A9D', '#229AFE', '#F9EF01', '#B56807', '#561E27', '#D6CDD5'], dark: ['#4136FE', '#89DEFF', '#FAF71B', '#CEA487', '#AD3607', '#4E575A'] },
		shades: { light: ['#54789F', '#067569', '#7F58E9', '#936D0A', '#424801', '#203EBB', '#B32B51', '#344657', '#67303E'], dark: ['#BDABFF', '#3DB097', '#CA77BB', '#F2C734', '#90DF8A', '#3D9FF5', '#EA802F', '#A0DCEB', '#FEBACF'] },
		categories: ['#A96F01', '#C2C712', '#5C4B7F', '#C75391', '#E7AAAF', '#35633B', '#59CEF2', '#6581F8']
	},
	tritan: {
		status: { light: ['#187D8F', '#85760E', '#D51626'], dark: ['#59AEC0', '#F4D965', '#FE102D'] },
		tiers: { light: ['#003A4A', '#1FEEDB', '#F1EF6A', '#FF6434', '#641D28', '#868686'], dark: ['#008CB1', '#2DF4E1', '#ECF892', '#F79A77', '#B1262F', '#5C5453'] },
		shades: { light: ['#5400A2', '#194B6B', '#733569', '#BE5819', '#474C10', '#1A7E83', '#8D1818', '#6D6B83', '#A048D2'], dark: ['#9886F4', '#4AECCF', '#C17CBE', '#FEBB43', '#9EAA48', '#2CAADF', '#E67634', '#AEC6D2', '#DCBBFE'] },
		categories: ['#ACCE1A', '#EB92FC', '#951C53', '#6AB2FC', '#8C7313', '#6830AF', '#F96445', '#167275']
	},
	achro: {
		status: { light: ['#0A5831', '#AD6404', '#51000D'], dark: ['#BAFED6', '#F2A310', '#FA174D'] },
		tiers: { light: ['#07059D', '#085624', '#78683D', '#D26F06', '#FB8A92', '#D5CED0'], dark: ['#BBDAFF', '#3FD366', '#A3A070', '#C86C07', '#BB4250', '#58545C'] },
		categories: ['#F45B5B', '#D3A1D9', '#166D41', '#A1790B', '#31DE93', '#53A9D8', '#892F5C', '#7D57D2']
	}
};
