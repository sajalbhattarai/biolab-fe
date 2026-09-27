/**
 * Generates the app icons (icon.icns via iconutil, icon.png, icon.ico), the menu bar template
 * glyph and the title bar mark. Uses the rendered logo in build/logo when present, otherwise
 * draws a supersampled double helix on a teal-to-indigo squircle, encoded as PNG with Node's zlib.
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.resolve(HERE, '..', 'build');
const ICONSET = path.join(OUT_DIR, 'icon.iconset');

// ---- a minimal PNG writer ----

const CRC_TABLE = (() => {
	const t = new Int32Array(256);
	for (let n = 0; n < 256; n++) {
		let c = n;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		t[n] = c;
	}
	return t;
})();

function crc32(buf) {
	let c = -1;
	for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
	return (c ^ -1) >>> 0;
}

function chunk(type, data) {
	const head = Buffer.alloc(8);
	head.writeUInt32BE(data.length, 0);
	head.write(type, 4, 'ascii');
	const crc = Buffer.alloc(4);
	crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
	return Buffer.concat([head, data, crc]);
}

/**
 * Encodes RGBA pixels as a PNG (filter 0 rows, zlib-deflated IDAT).
 * @param {Uint8Array} rgba  width*height*4
 */
function encodePng(rgba, width, height) {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(width, 0);
	ihdr.writeUInt32BE(height, 4);
	ihdr[8] = 8; // bit depth
	ihdr[9] = 6; // colour type: RGBA
	// 10..12: deflate, adaptive filtering, no interlace — all zero.

	// Filter byte 0 (None) in front of every scanline.
	const raw = Buffer.alloc(height * (width * 4 + 1));
	for (let y = 0; y < height; y++) {
		const from = y * width * 4;
		raw[y * (width * 4 + 1)] = 0;
		Buffer.from(rgba.buffer, rgba.byteOffset + from, width * 4).copy(raw, y * (width * 4 + 1) + 1);
	}

	return Buffer.concat([
		Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
		chunk('IHDR', ihdr),
		chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
		chunk('IEND', Buffer.alloc(0))
	]);
}

// ---- the mark ----

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const lerp = (a, b, t) => a + (b - a) * t;

/** Signed distance to a rounded rectangle; negative inside. */
function roundRectSdf(px, py, cx, cy, halfW, halfH, r) {
	const qx = Math.abs(px - cx) - (halfW - r);
	const qy = Math.abs(py - cy) - (halfH - r);
	const ox = Math.max(qx, 0);
	const oy = Math.max(qy, 0);
	return Math.hypot(ox, oy) + Math.min(Math.max(qx, qy), 0) - r;
}

/** Shortest distance from a point to a line segment. */
function segDist(px, py, ax, ay, bx, by) {
	const vx = bx - ax;
	const vy = by - ay;
	const wx = px - ax;
	const wy = py - ay;
	const len2 = vx * vx + vy * vy;
	const t = len2 ? clamp01((wx * vx + wy * vy) / len2) : 0;
	return Math.hypot(px - (ax + t * vx), py - (ay + t * vy));
}

const TEAL = [14, 165, 164];
const INDIGO = [79, 70, 229];

/**
 * Draws one square icon at `size` device pixels, supersampled and averaged down.
 * @returns {Uint8Array} RGBA
 */
function drawIcon(size) {
	// Large sizes use 2x supersampling to bound the sample count.
	const SS = size >= 512 ? 2 : 4;
	const W = size * SS;
	const big = new Float32Array(W * W * 4);

	// Squircle geometry, in supersampled units.
	const inset = W * 0.06;
	const half = (W - inset * 2) / 2;
	const c = W / 2;
	const radius = half * 0.45;

	// --- helix geometry -----------------------------------------------------
	// Two strands, half a period apart, over the middle ~62% of the tile.
	const top = c - half * 0.72;
	const bottom = c + half * 0.72;
	const amp = half * 0.55;
	const turns = 2;
	// Proportional stroke, but never thinner than about one final pixel.
	const strand = Math.max(W * 0.024, SS * 1.0); // stroke half-width

	const strandX = (u, phase) => c + amp * Math.sin(u * turns * Math.PI * 2 + phase);
	const yAt = (u) => lerp(top, bottom, u);

	// Samples both strands densely and marks each segment as near or far side of the turn;
	// the weave (near strand unbroken, far strand stopping short) is what reads as a helix.
	const STEPS = Math.max(160, W);
	const segments = [];
	for (const phase of [0, Math.PI]) {
		for (let i = 1; i <= STEPS; i++) {
			const u0 = (i - 1) / STEPS;
			const u1 = i / STEPS;
			const mid = (u0 + u1) / 2;
			segments.push({
				ax: strandX(u0, phase),
				ay: yAt(u0),
				bx: strandX(u1, phase),
				by: yAt(u1),
				// The depth of a helix is the cosine to its sine.
				near: Math.cos(mid * turns * Math.PI * 2 + phase) > 0,
				// How far the other strand is at this height. Near zero means
				// the two are crossing here.
				gap: Math.abs(strandX(mid, phase) - strandX(mid, phase + Math.PI))
			});
		}
	}

	// --- the helix, stamped into a coverage buffer --------------------------
	// Each segment is stamped over its own bounding box, which keeps this fast.
	const ink = new Float32Array(W * W);

	/** Runs `apply(index, coverage)` over the pixels a fat segment touches. */
	const along = (ax, ay, bx, by, rad, apply) => {
		const x0 = Math.max(0, Math.floor(Math.min(ax, bx) - rad - 1));
		const x1 = Math.min(W - 1, Math.ceil(Math.max(ax, bx) + rad + 1));
		const y0 = Math.max(0, Math.floor(Math.min(ay, by) - rad - 1));
		const y1 = Math.min(W - 1, Math.ceil(Math.max(ay, by) + rad + 1));
		for (let y = y0; y <= y1; y++) {
			for (let x = x0; x <= x1; x++) {
				const cov = clamp01(rad - segDist(x + 0.5, y + 0.5, ax, ay, bx, by) + 0.5);
				if (cov > 0) apply(y * W + x, cov);
			}
		}
	};

	const stamp = (ax, ay, bx, by, rad) =>
		along(ax, ay, bx, by, rad, (i, cov) => {
			if (cov > ink[i]) ink[i] = cov;
		});

	/** Clears a little wider than the stroke, leaving the gap that reads as depth. */
	const erase = (ax, ay, bx, by, rad) => along(ax, ay, bx, by, rad, (i, cov) => (ink[i] *= 1 - cov));

	// Back to front: far halves, a gap cleared under the near halves, then the near halves.
	for (const s of segments) if (!s.near) stamp(s.ax, s.ay, s.bx, s.by, strand);
	// The gap is cleared only at crossings, so a near strand does not erode its own continuation.
	const CROSSING = strand * 7;
	for (const s of segments) if (s.near && s.gap < CROSSING) erase(s.ax, s.ay, s.bx, s.by, strand * 1.9);
	for (const s of segments) if (s.near) stamp(s.ax, s.ay, s.bx, s.by, strand);

	// --- rasterise ----------------------------------------------------------
	for (let y = 0; y < W; y++) {
		for (let x = 0; x < W; x++) {
			const px = x + 0.5;
			const py = y + 0.5;

			// Background tile.
			const d = roundRectSdf(px, py, c, c, half, half, radius);
			if (d > 0) continue; // outside the squircle: stays transparent

			const t = clamp01((px + py) / (W * 2));
			let r = lerp(TEAL[0], INDIGO[0], t);
			let g = lerp(TEAL[1], INDIGO[1], t);
			let b = lerp(TEAL[2], INDIGO[2], t);

			// A soft top-left sheen, so the tile does not read as flat.
			const sheen = clamp01(1 - Math.hypot(px - W * 0.3, py - W * 0.24) / (W * 0.62)) * 0.16;
			r = lerp(r, 255, sheen);
			g = lerp(g, 255, sheen);
			b = lerp(b, 255, sheen);

			// The helix, in white.
			const cov = ink[y * W + x];
			if (cov > 0) {
				r = lerp(r, 255, 0.93 * cov);
				g = lerp(g, 255, 0.93 * cov);
				b = lerp(b, 255, 0.93 * cov);
			}

			const o = (y * W + x) * 4;
			big[o] = r;
			big[o + 1] = g;
			big[o + 2] = b;
			big[o + 3] = 255;
		}
	}

	// --- downsample ---------------------------------------------------------
	const out = new Uint8Array(size * size * 4);
	for (let y = 0; y < size; y++) {
		for (let x = 0; x < size; x++) {
			let r = 0;
			let g = 0;
			let b = 0;
			let a = 0;
			for (let sy = 0; sy < SS; sy++) {
				for (let sx = 0; sx < SS; sx++) {
					const o = ((y * SS + sy) * W + (x * SS + sx)) * 4;
					// Alpha-weighted colour keeps transparent edge samples from darkening the rim.
					const av = big[o + 3] / 255;
					r += big[o] * av;
					g += big[o + 1] * av;
					b += big[o + 2] * av;
					a += av;
				}
			}
			const o = (y * size + x) * 4;
			if (a > 0) {
				out[o] = Math.round(r / a);
				out[o + 1] = Math.round(g / a);
				out[o + 2] = Math.round(b / a);
			}
			out[o + 3] = Math.round((a / (SS * SS)) * 255);
		}
	}
	return out;
}

/**
 * Draws the menu bar glyph: the same helix, no tile, black on transparent.
 * macOS uses a "Template" image's alpha only, as a mask.
 */
function drawTray(size) {
	const SS = 4;
	const W = size * SS;
	const ink = new Float32Array(W * W);

	const c = W / 2;
	const top = W * 0.1;
	const bottom = W * 0.9;
	const amp = W * 0.27;
	const turns = 1.5;
	// Heavier in proportion than the app icon, to stay visible at 16pt.
	const strand = Math.max(W * 0.05, SS * 1.1);

	const strandX = (u, phase) => c + amp * Math.sin(u * turns * Math.PI * 2 + phase);
	const yAt = (u) => lerp(top, bottom, u);

	const STEPS = 160;
	const segments = [];
	for (const phase of [0, Math.PI]) {
		for (let i = 1; i <= STEPS; i++) {
			const u0 = (i - 1) / STEPS;
			const u1 = i / STEPS;
			const mid = (u0 + u1) / 2;
			segments.push({
				ax: strandX(u0, phase),
				ay: yAt(u0),
				bx: strandX(u1, phase),
				by: yAt(u1),
				near: Math.cos(mid * turns * Math.PI * 2 + phase) > 0,
				gap: Math.abs(strandX(mid, phase) - strandX(mid, phase + Math.PI))
			});
		}
	}

	const along = (ax, ay, bx, by, rad, apply) => {
		const x0 = Math.max(0, Math.floor(Math.min(ax, bx) - rad - 1));
		const x1 = Math.min(W - 1, Math.ceil(Math.max(ax, bx) + rad + 1));
		const y0 = Math.max(0, Math.floor(Math.min(ay, by) - rad - 1));
		const y1 = Math.min(W - 1, Math.ceil(Math.max(ay, by) + rad + 1));
		for (let y = y0; y <= y1; y++) {
			for (let x = x0; x <= x1; x++) {
				const cov = clamp01(rad - segDist(x + 0.5, y + 0.5, ax, ay, bx, by) + 0.5);
				if (cov > 0) apply(y * W + x, cov);
			}
		}
	};
	const stamp = (s, rad) =>
		along(s.ax, s.ay, s.bx, s.by, rad, (i, cov) => {
			if (cov > ink[i]) ink[i] = cov;
		});
	const erase = (s, rad) => along(s.ax, s.ay, s.bx, s.by, rad, (i, cov) => (ink[i] *= 1 - cov));

	for (const s of segments) if (!s.near) stamp(s, strand);
	for (const s of segments) if (s.near && s.gap < strand * 7) erase(s, strand * 1.9);
	for (const s of segments) if (s.near) stamp(s, strand);

	const out = new Uint8Array(size * size * 4);
	for (let y = 0; y < size; y++) {
		for (let x = 0; x < size; x++) {
			let a = 0;
			for (let sy = 0; sy < SS; sy++) for (let sx = 0; sx < SS; sx++) a += ink[(y * SS + sy) * W + (x * SS + sx)];
			const o = (y * size + x) * 4;
			// Black; only the alpha carries the shape.
			out[o + 3] = Math.round(clamp01(a / (SS * SS)) * 255);
		}
	}
	return out;
}

// ---- write the iconset and convert it ----

const VARIANTS = [
	[16, 'icon_16x16.png'],
	[32, 'icon_16x16@2x.png'],
	[32, 'icon_32x32.png'],
	[64, 'icon_32x32@2x.png'],
	[128, 'icon_128x128.png'],
	[256, 'icon_128x128@2x.png'],
	[256, 'icon_256x256.png'],
	[512, 'icon_256x256@2x.png'],
	[512, 'icon_512x512.png'],
	[1024, 'icon_512x512@2x.png']
];

fs.rmSync(ICONSET, { recursive: true, force: true });
fs.mkdirSync(ICONSET, { recursive: true });

/**
 * Rendered logo artwork per size in build/logo (made by scripts/logo/make-logo.py and
 * render-logo.mjs); the drawn helix is the fallback and the menu bar glyph.
 */
const LOGO = path.join(OUT_DIR, 'logo');
const artwork = (size) => {
	const f = path.join(LOGO, `icon-${size}.png`);
	return fs.existsSync(f) ? fs.readFileSync(f) : null;
};
const cache = new Map();
for (const [size, name] of VARIANTS) {
	if (!cache.has(size)) cache.set(size, artwork(size) ?? encodePng(drawIcon(size), size, size));
	fs.writeFileSync(path.join(ICONSET, name), cache.get(size));
	process.stdout.write(`  ${name}\n`);
}

// iconutil exists only on macOS; other builds use the PNG and .ico.
if (process.platform === 'darwin') {
	execFileSync('iconutil', ['-c', 'icns', ICONSET, '-o', path.join(OUT_DIR, 'icon.icns')], { stdio: 'inherit' });
}
fs.rmSync(ICONSET, { recursive: true, force: true });

// electron-builder uses a large PNG for non-mac targets and the DMG.
fs.writeFileSync(path.join(OUT_DIR, 'icon.png'), cache.get(512));

// Windows .ico: a 6-byte header, a 16-byte entry per image, then the PNGs themselves.
{
	const sizes = [16, 24, 32, 48, 64, 128, 256];
	const pngs = sizes.map((n) => cache.get(n) ?? artwork(n) ?? encodePng(drawIcon(n), n, n));
	const head = Buffer.alloc(6 + 16 * sizes.length);
	head.writeUInt16LE(0, 0);
	head.writeUInt16LE(1, 2); // 1 = icon
	head.writeUInt16LE(sizes.length, 4);
	let offset = head.length;
	sizes.forEach((n, i) => {
		const e = 6 + 16 * i;
		head.writeUInt8(n >= 256 ? 0 : n, e); // 0 means 256
		head.writeUInt8(n >= 256 ? 0 : n, e + 1);
		head.writeUInt8(0, e + 2); // no palette
		head.writeUInt8(0, e + 3);
		head.writeUInt16LE(1, e + 4); // colour planes
		head.writeUInt16LE(32, e + 6); // bits per pixel
		head.writeUInt32LE(pngs[i].length, e + 8);
		head.writeUInt32LE(offset, e + 12);
		offset += pngs[i].length;
	});
	fs.writeFileSync(path.join(OUT_DIR, 'icon.ico'), Buffer.concat([head, ...pngs]));
}

// The menu bar glyph goes in src/assets, inside the asar.
const ASSETS = path.resolve(HERE, '..', 'src', 'assets');
fs.mkdirSync(ASSETS, { recursive: true });
for (const [size, name] of [
	[16, 'trayTemplate.png'],
	[32, 'trayTemplate@2x.png']
]) {
	fs.writeFileSync(path.join(ASSETS, name), encodePng(drawTray(size), size, size));
	console.log(`  src/assets/${name}`);
}

// A 64px copy of the Dock icon, inlined into the title strip as a data URI.
fs.writeFileSync(path.join(ASSETS, 'titlebar.png'), cache.get(64) ?? encodePng(drawIcon(64), 64, 64));
console.log('  src/assets/titlebar.png');

if (process.platform === 'darwin') {
	console.log(`\nicon.icns  ${(fs.statSync(path.join(OUT_DIR, 'icon.icns')).size / 1024).toFixed(0)} KB  →  ${OUT_DIR}`);
}
