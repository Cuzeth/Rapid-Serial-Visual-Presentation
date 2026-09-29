import {
  FORMATS, FPS, BEAT, BAR, S16, bar, T, SCHEDULE, TAGLINE, FIXATIONS, MOBY_OPENING,
  wpmAt, slideAt, kicks, mulberry32,
} from "./timeline.js";
import { createPost } from "./post.js";

const { w: W, h: H } = FORMATS[new URLSearchParams(location.search).get("format") ?? "wide"];
const TALL = H > W;

// Where things sit in each frame shape. The vertical cut uses a narrower, taller page and
// keeps text and controls out of the top and bottom bands and the lower right edge, which
// TikTok, Reels and Shorts cover with their own buttons and captions.
const LAYOUT = TALL
  ? {
      page: { width: 860, near: [-460, 540, -600], far: [40, 90, -1900], target: [0, 190, 0], motes: [-700, 700, -800, 1500] },
      headline: { x: 90, y: 1150, scrim: 950 },
      hud: { y: 262, scale: 1.35 },
      stream: [0.8, 1.3],
      streaks: [0.8, 1.2],
      guide: 1000,
      giant: 0.62,
      paused: 610,
      touch: { x: 330, hold: 1200, from: 1270, to: 1100, scale: 1.25 },
      speed: { y: 1390, scale: 1.3 },
      squash: { rings: 1, sparks: 1, burst: 1 },
      finale: { logo: 780, tagline: 1010, stores: 1110, url: 1178, scale: 1.3 },
    }
  : {
      page: { width: 1320, near: [-460, 540, -600], far: [60, 90, -2050], target: [40, 150, 0], motes: [-1000, 1000, -800, 1000] },
      headline: { x: 150, y: 812, scrim: 560 },
      hud: { y: 86, scale: 1 },
      stream: [1.3, 0.8],
      streaks: [1.2, 0.8],
      guide: 560,
      giant: 1,
      paused: 150,
      touch: { x: 1480, hold: 720, from: 880, to: 640, scale: 1 },
      speed: { y: 986, scale: 1 },
      squash: { rings: 0.62, sparks: 0.75, burst: 0.8 },
      finale: { logo: 468, tagline: 668, stores: 748, url: 802, scale: 1 },
    };

// ---------------------------------------------------------------- math

const TAU = Math.PI * 2;
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, u) => a + (b - a) * u;
const range = (t, a, b) => clamp((t - a) / (b - a));
const smooth = (u) => u * u * (3 - 2 * u);
const easeOutExpo = (u) => (u >= 1 ? 1 : 1 - Math.pow(2, -10 * u));
const easeInExpo = (u) => (u <= 0 ? 0 : Math.pow(2, 10 * u - 10));
const easeOutCubic = (u) => 1 - Math.pow(1 - u, 3);
const easeInCubic = (u) => u * u * u;
const easeInOutCubic = (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);

const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const scale = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (a) => scale(a, 1 / Math.hypot(a[0], a[1], a[2]));
const lerp3 = (a, b, u) => [lerp(a[0], b[0], u), lerp(a[1], b[1], u), lerp(a[2], b[2], u)];

function rotateAxis(v, k, a) {
  const c = Math.cos(a), s = Math.sin(a);
  const kv = cross(k, v);
  const kd = dot(k, v) * (1 - c);
  return [v[0] * c + kv[0] * s + k[0] * kd, v[1] * c + kv[1] * s + k[1] * kd, v[2] * c + kv[2] * s + k[2] * kd];
}

function hash32(n) {
  n = Math.imul(n ^ (n >>> 16), 0x7feb352d);
  n = Math.imul(n ^ (n >>> 15), 0x846ca68b);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}
const rnd = (i, s = 0) => hash32(Math.imul(i + 1, 73856093) ^ Math.imul(s + 7, 19349663));

// ---------------------------------------------------------------- color

const INK = [244, 236, 225];
const WHITE = [255, 255, 255];
const RED = [255, 69, 58];
const ACCENT = [255, 59, 48];
const rgba = (c, a) => `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${clamp(a)})`;
const mixc = (a, b, u) => [lerp(a[0], b[0], u), lerp(a[1], b[1], u), lerp(a[2], b[2], u)];

const COVER_TONES = [0x4a1c2a, 0x1c2b44, 0x1e3b30, 0x3d2344, 0x4b3424, 0x16393d, 0x2e343b, 0x3f3d1e, 0x221f40, 0x4f2c1c, 0x2a3a22, 0x3a2a33];
const hex = (n) => [(n >> 16) & 255, (n >> 8) & 255, n & 255];

// ---------------------------------------------------------------- canvases

const out = document.getElementById("out");
out.width = W;
out.height = H;
const post = createPost(out, W, H);
const makeCanvas = (w = W, h = H) => {
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  return c;
};
const sc = makeCanvas();
const ctx = sc.getContext("2d", { alpha: false });
const mctx = makeCanvas(8, 8).getContext("2d");
const logoLayer = makeCanvas();
const lctx = logoLayer.getContext("2d");

// ---------------------------------------------------------------- type

const FR = (w, s) => `${w} ${s}px Fraunces`;
const SG = (w, s) => `${w} ${s}px "Space Grotesk"`;
const JB = (w, s) => `${w} ${s}px "JetBrains Mono"`;

const mcache = new Map();
function measure(font, text, ls = 0) {
  const k = font + "|" + ls + "|" + text;
  let w = mcache.get(k);
  if (w === undefined) {
    mctx.font = font;
    mctx.letterSpacing = ls + "px";
    w = mctx.measureText(text).width;
    mcache.set(k, w);
  }
  return w;
}

/// The app's Optimal Recognition Point: the anchor sits on the 1st, 2nd, 3rd, 4th
/// or 5th letter or digit as the word grows.
function redIndex(word) {
  const chars = Array.from(word);
  const idx = [];
  chars.forEach((c, i) => {
    if (/[\p{L}\p{Nd}]/u.test(c)) idx.push(i);
  });
  if (!idx.length) return Math.floor(chars.length / 2);
  const n = idx.length;
  const pos = n < 2 ? 0 : n <= 5 ? 1 : n <= 9 ? 2 : n <= 13 ? 3 : 4;
  return idx[pos];
}

/// A word split around its anchor letter, with fonts and widths.
function anchorParts(word, size, o = {}) {
  const family = o.family ?? "Fraunces";
  const weight = o.weight ?? 400;
  const aw = o.anchorWeight ?? 700;
  const chars = Array.from(word);
  const ri = redIndex(word);
  const before = chars.slice(0, ri).join("");
  const anchor = chars[ri] ?? "";
  const after = chars.slice(ri + 1).join("");
  const fR = `${weight} ${size}px ${family === "Fraunces" ? "Fraunces" : `"${family}"`}`;
  const fB = `${aw} ${size}px ${family === "Fraunces" ? "Fraunces" : `"${family}"`}`;
  return { before, anchor, after, fR, fB, wb: measure(fR, before), wa: measure(fB, anchor), wr: measure(fR, after) };
}

/// How far a word reaches to either side of its anchor letter's center.
function anchorReach(word, size) {
  const { wb, wa, wr } = anchorParts(word, size);
  return Math.max(wb + wa / 2, wa / 2 + wr);
}

/// Draws a word with its anchor letter centered on (cx, cy). Returns its extent.
function drawAnchored(c, word, cx, cy, size, o = {}) {
  const { before, anchor, after, fR, fB, wb, wa, wr } = anchorParts(word, size, o);
  const x = cx - wb - wa / 2;
  const y = cy + size * (o.baseline ?? 0.3);
  c.textAlign = "left";
  c.textBaseline = "alphabetic";
  c.letterSpacing = "0px";
  c.font = fR;
  c.fillStyle = o.color ?? "#fff";
  if (before) c.fillText(before, x, y);
  if (after) c.fillText(after, x + wb + wa, y);
  c.font = fB;
  c.fillStyle = o.anchorColor ?? rgba(RED, 1);
  c.fillText(anchor, x + wb, y);
  return { left: x, right: x + wb + wa + wr };
}

// Canvas text snaps its baseline to whole pixels, so text that drifts or scales by
// fractions of a pixel a frame moves in visible steps. Text that moves slowly is
// drawn from these pre-rendered, double-resolution images instead.
const SPRITE_SCALE = 2;
const sprites = new Map();

/// `box` is [x0, y0, x1, y1] around the origin that `paint` draws relative to.
function sprite(key, box, paint) {
  let s = sprites.get(key);
  if (!s) {
    const [x0, y0, x1, y1] = box;
    const c = makeCanvas(Math.ceil((x1 - x0) * SPRITE_SCALE), Math.ceil((y1 - y0) * SPRITE_SCALE));
    const x = c.getContext("2d");
    x.scale(SPRITE_SCALE, SPRITE_SCALE);
    x.translate(-x0, -y0);
    x.textBaseline = "alphabetic";
    paint(x);
    s = { c, x0, y0, w: x1 - x0, h: y1 - y0 };
    sprites.set(key, s);
  }
  return s;
}

function drawSprite(c, s, x, y, alpha = 1) {
  if (alpha <= 0) return;
  c.globalAlpha = alpha;
  c.imageSmoothingQuality = "high";
  c.drawImage(s.c, x + s.x0, y + s.y0, s.w, s.h);
  c.imageSmoothingQuality = "low";
  c.globalAlpha = 1;
}

/// A line of text with its alignment point at the origin.
function textSprite(font, ls, text, color, align = "left") {
  const w = measure(font, text, ls);
  const size = parseFloat(font.split(" ")[1]);
  const x0 = align === "center" ? -w / 2 : 0;
  return sprite(`${font}|${ls}|${color}|${align}|${text}`, [x0 - size * 0.5, -size * 1.1, x0 + w + size * 0.5, size * 0.45], (c) => {
    c.font = font;
    c.letterSpacing = ls + "px";
    c.textAlign = align;
    c.fillStyle = color;
    c.fillText(text, 0, 0);
  });
}

// ---------------------------------------------------------------- camera

function lookAt(pos, target, roll = 0, f = 1400) {
  const fwd = norm(sub(target, pos));
  const right = norm(cross(fwd, [0, -1, 0]));
  const down = cross(fwd, right);
  return { pos, fwd, right, down, f, cr: Math.cos(roll), sr: Math.sin(roll), dist: Math.hypot(...sub(target, pos)) };
}

function project(cam, p) {
  const q0 = p[0] - cam.pos[0], q1 = p[1] - cam.pos[1], q2 = p[2] - cam.pos[2];
  const x = q0 * cam.right[0] + q1 * cam.right[1] + q2 * cam.right[2];
  const y = q0 * cam.down[0] + q1 * cam.down[1] + q2 * cam.down[2];
  const z = q0 * cam.fwd[0] + q1 * cam.fwd[1] + q2 * cam.fwd[2];
  const s = cam.f / z;
  return { x: W / 2 + (x * cam.cr - y * cam.sr) * s, y: H / 2 + (x * cam.sr + y * cam.cr) * s, z, s };
}

/// Affine approximation of a plane at point o with axes u, v, projected to screen.
function planeAffine(cam, o, u, v, k = 6) {
  const p = project(cam, o);
  const pu = project(cam, [o[0] + u[0] * k, o[1] + u[1] * k, o[2] + u[2] * k]);
  const pv = project(cam, [o[0] + v[0] * k, o[1] + v[1] * k, o[2] + v[2] * k]);
  return { a: (pu.x - p.x) / k, b: (pu.y - p.y) / k, c: (pv.x - p.x) / k, d: (pv.y - p.y) / k, e: p.x, f: p.y, z: p.z, s: p.s, ok: p.z > 40 && pu.z > 40 && pv.z > 40 };
}

const identityCam = (f, roll) => ({ pos: [0, 0, 0], fwd: [0, 0, 1], right: [1, 0, 0], down: [0, 1, 0], f, cr: Math.cos(roll), sr: Math.sin(roll) });

// ---------------------------------------------------------------- depth of field

const BLURS = [0, 1.6, 3.2, 5.5, 9, 14, 21, 30];
const layerSets = { far: [], near: [] };
let drawables = [];

function addDrawable(z, blur, draw) {
  drawables.push({ z, blur, draw });
}

function layer(group, i) {
  let L = layerSets[group][i];
  if (!L) {
    const c = makeCanvas();
    L = layerSets[group][i] = { c, x: c.getContext("2d"), used: false };
  }
  return L;
}

function flushDrawables(target, focusZ) {
  drawables.sort((a, b) => b.z - a.z);
  for (const d of drawables) {
    const group = d.z > focusZ ? "far" : "near";
    let i = 0;
    while (i < BLURS.length - 1 && d.blur > (BLURS[i] + BLURS[i + 1]) / 2) i++;
    const L = layer(group, i);
    if (!L.used) {
      L.x.setTransform(1, 0, 0, 1, 0, 0);
      L.x.clearRect(0, 0, W, H);
      L.used = true;
    }
    L.x.save();
    d.draw(L.x);
    L.x.restore();
  }
  drawables = [];
  const comp = (L, i) => {
    if (!L || !L.used) return;
    target.filter = BLURS[i] > 0 ? `blur(${BLURS[i]}px)` : "none";
    target.drawImage(L.c, 0, 0);
    target.filter = "none";
    L.used = false;
  };
  for (let i = BLURS.length - 1; i >= 0; i--) comp(layerSets.far[i], i);
  for (let i = 0; i < BLURS.length; i++) comp(layerSets.near[i], i);
}

// ---------------------------------------------------------------- the page

const P2 =
  "There now is your insular city of the Manhattoes, belted round by wharves as Indian isles by coral reefs—commerce surrounds it with her surf. Right and left, the streets take you waterward. Its extreme downtown is the battery, where that noble mole is washed by waves, and cooled by breezes, which a few hours previous were out of sight of land. Look at the crowds of water-gazers there.";

const BODY_FONT = FR(400, 31);
const PAGE = (() => {
  const items = [];
  const lines = [];
  const put = (text, x, y, font, baseAlpha, col, extra = {}) => {
    const w = measure(font, text, extra.ls ?? 0);
    items.push({ text, x: x + w / 2, y, w, font, baseAlpha, col, ls: extra.ls ?? 0, ...extra });
  };
  return { items, lines, put, bounds: null };
})();

function buildPage() {
  const { put, items, lines } = PAGE;
  const colW = LAYOUT.page.width;
  const left = -colW / 2;
  put("MOBY-DICK", left, -560, SG(500, 17), 0.5, INK, { ls: 5, deco: true });
  put("3", left + colW - 10, -560, SG(500, 17), 0.5, INK, { deco: true });
  put("CHAPTER 1", left, -468, SG(600, 18), 0.85, RED, { ls: 6, deco: true });
  put("Loomings.", left, -392, FR(600, 66), 0.9, INK, { deco: true });

  const LH = 50;
  const space = measure(BODY_FONT, " ");
  let y = -296;
  for (const para of [MOBY_OPENING, P2]) {
    const words = para.split(/\s+/).filter(Boolean);
    let i = 0;
    let first = true;
    while (i < words.length) {
      const indent = first ? 52 : 0;
      const avail = colW - indent;
      const lw = [];
      let wsum = 0;
      while (i < words.length) {
        const w = measure(BODY_FONT, words[i]);
        if (lw.length && wsum + w + lw.length * space > avail) break;
        lw.push({ t: words[i], w });
        wsum += w;
        i++;
      }
      const last = i >= words.length;
      const gap = last || lw.length < 2 ? space : (avail - wsum) / (lw.length - 1);
      let x = left + indent;
      const idx = [];
      for (const w of lw) {
        idx.push(items.length);
        items.push({ text: w.t, x: x + w.w / 2, y, w: w.w, font: BODY_FONT, baseAlpha: 0.4, col: INK, ls: 0, line: lines.length });
        x += w.w + gap;
      }
      lines.push(idx);
      y += LH;
      first = false;
    }
    y += 8;
  }
  PAGE.bounds = { x0: left - 110, x1: left + colW + 110, y0: -640, y1: y + 40 };
  for (const it of items) it.fix = [];
}

let FIX = [];
function mapFixations() {
  const rng = mulberry32(5);
  let line = 0;
  let k = 0;
  FIX = FIXATIONS.map((f, i) => {
    let type = f.type;
    if (i > 0) {
      if (type === "regress") {
        k = Math.max(0, k - 1 - (rng() < 0.35 ? 1 : 0));
      } else {
        const cur = PAGE.items[PAGE.lines[line][k]];
        k += cur.text.length <= 3 || rng() < 0.25 ? 2 : 1;
        if (k >= PAGE.lines[line].length) {
          line = (line + 1) % PAGE.lines.length;
          k = rng() < 0.6 ? 0 : 1;
          type = "return";
        }
      }
    }
    const wi = PAGE.lines[line][k];
    const it = PAGE.items[wi];
    const off = (rng() * 0.3 - 0.12) * it.w;
    it.fix.push(i);
    return { ...f, type, word: wi, p: [it.x + off, it.y - 10, 0], sd: type === "return" ? 0.085 : 0.045 };
  });
}

function litAmount(it, t) {
  let v = 0;
  for (const j of it.fix) {
    const f = FIX[j];
    if (t < f.start) continue;
    const end = f.start + f.dur;
    const x = t < end ? clamp((t - f.start) / 0.03) : 0.8 * Math.exp(-(t - end) / 0.5);
    v = Math.max(v, x);
  }
  return v;
}

function fixIndexAt(t) {
  let j = -1;
  for (let i = 0; i < FIX.length; i++) if (FIX[i].start - FIX[i].sd <= t) j = i;
  return j;
}

function gazeAt(t) {
  const j = fixIndexAt(t);
  if (j < 0) return FIX[0].p;
  const f = FIX[j];
  if (t >= f.start || j === 0) return f.p;
  const u = easeInOutCubic((t - (f.start - f.sd)) / f.sd);
  return lerp3(FIX[j - 1].p, f.p, u);
}

function gazeSmooth(t) {
  let acc = [0, 0, 0];
  let wsum = 0;
  for (const f of FIX) {
    if (f.start > t) break;
    const w = smooth(range(t, f.start, f.start + 0.5)) * Math.exp(-Math.max(0, t - f.start - 0.5) / 0.9);
    acc = add(acc, scale(f.p, w));
    wsum += w;
  }
  return wsum > 1e-4 ? scale(acc, 1 / wsum) : FIX[0].p;
}

function pageCamera(t) {
  const pull = 0.1 * smooth(range(t, 0, 3.4)) + 0.9 * easeInOutCubic(range(t, 3.0, T.impact - 0.3));
  const { near, far, target: whole } = LAYOUT.page;
  const target = lerp3(gazeSmooth(Math.min(t, T.collapse)), whole, Math.pow(pull, 1.2));
  const off = lerp3(near, far, pull);
  off[0] += Math.sin(t * 0.9) * 16 + Math.sin(t * 2.3 + 0.4) * 5;
  off[1] += Math.sin(t * 1.1 + 1) * 11 + Math.sin(t * 2.9) * 3;
  const cam = lookAt(add(target, off), target, lerp(-0.13, 0.015, pull), 1400);
  return cam;
}

// Vortex launch times, from each word's place on screen at the collapse.
function prepareVortex() {
  const cam = pageCamera(T.collapse);
  let dmax = 1;
  for (const it of PAGE.items) {
    const p = project(cam, [it.x, it.y, 0]);
    it.d0 = Math.min(1800, Math.hypot(p.x - W / 2, p.y - H / 2));
    dmax = Math.max(dmax, it.d0);
  }
  PAGE.items.forEach((it, i) => {
    it.tl = T.collapse + 0.12 + 0.95 * Math.pow(it.d0 / dmax, 0.85) + rnd(i, 3) * 0.12;
    it.dur = 0.5 + rnd(i, 4) * 0.25;
    it.spin = (2.2 + rnd(i, 5) * 1.4) * (rnd(i, 6) < 0.85 ? 1 : 0.7);
  });
}

function vortex(x, y, M, t, tl, dur, spin) {
  const u = range(t, tl, tl + dur);
  const e = Math.pow(u, 2.3);
  const dx = x - W / 2, dy = y - H / 2;
  const r = Math.hypot(dx, dy) * (1 - e);
  const th = Math.atan2(dy, dx) + spin * e;
  const s = 1 - 0.92 * e;
  const rc = Math.cos(spin * e * 0.8), rs = Math.sin(spin * e * 0.8);
  return {
    u, e,
    x: W / 2 + r * Math.cos(th),
    y: H / 2 + r * Math.sin(th),
    a: (rc * M.a - rs * M.b) * s,
    b: (rs * M.a + rc * M.b) * s,
    c: (rc * M.c - rs * M.d) * s,
    d: (rs * M.c + rc * M.d) * s,
  };
}

const [MX0, MX1, MY0, MY1] = LAYOUT.page.motes;
const MOTES = Array.from({ length: 90 }, (_, i) => ({
  p: [lerp(MX0, MX1, rnd(i, 10)), lerp(MY0, MY1, rnd(i, 11)), lerp(-900, 120, rnd(i, 12))],
  r: 1.5 + rnd(i, 13) * 3.5,
  v: [(rnd(i, 14) - 0.5) * 30, -8 - rnd(i, 15) * 20, (rnd(i, 16) - 0.5) * 20],
  red: rnd(i, 17) < 0.18,
}));

// Headlines: per-character reveal, screen space.
const HEAD_FONT = FR(600, 88);
const HEADLINES = [
  {
    t0: T.headline1,
    t1: T.headline2 - 0.5,
    rows: TALL
      ? [[["Your eyes ", INK], ["jump", RED]], [["hundreds of times", INK]], [["a page.", INK]]]
      : [[["Your eyes ", INK], ["jump", RED]], [["hundreds of times a page.", INK]]],
  },
  { t0: T.headline2 + 0.06, t1: null, rows: [[["What if the words", INK]], [["came to ", INK], ["you?", RED]]] },
];
function layoutHeadlines() {
  for (const h of HEADLINES) {
    h.chars = [];
    h.rows.forEach((row, ri) => {
      const y = LAYOUT.headline.y + ri * 100;
      let text = "";
      for (const [seg, col] of row) {
        for (const ch of Array.from(seg)) {
          const x = LAYOUT.headline.x + measure(HEAD_FONT, text);
          text += ch;
          h.chars.push({ ch, x, y, col, w: measure(HEAD_FONT, ch) });
        }
      }
    });
  }
}

function drawHeadlines(t) {
  let scrim = 0;
  for (const h of HEADLINES) {
    const vis = range(t, h.t0 - 0.2, h.t0 + 0.3) * (h.t1 ? 1 - range(t, h.t1 + 0.1, h.t1 + 0.5) : 1 - range(t, T.collapse + 0.2, T.collapse + 1.0));
    scrim = Math.max(scrim, vis);
  }
  if (scrim > 0) {
    const top = LAYOUT.headline.scrim;
    const g = ctx.createLinearGradient(0, top, 0, H);
    g.addColorStop(0, "rgba(5,5,5,0)");
    g.addColorStop(0.55, `rgba(5,5,5,${0.72 * scrim})`);
    g.addColorStop(1, `rgba(5,5,5,${0.92 * scrim})`);
    ctx.fillStyle = g;
    ctx.fillRect(0, top, W, H - top);
  }
  ctx.font = HEAD_FONT;
  ctx.textBaseline = "alphabetic";
  ctx.textAlign = "left";
  ctx.letterSpacing = "0px";
  for (const h of HEADLINES) {
    h.chars.forEach((c, i) => {
      if (c.ch === " ") return;
      const a = t - (h.t0 + i * 0.021);
      if (a < 0) return;
      const u = range(a, 0, 0.6);
      const e = easeOutExpo(u);
      let y = c.y + (1 - e) * 64;
      let x = c.x;
      let alpha = clamp(u * 2.4);
      let rot = (1 - e) * 0.18;
      let s = 1;
      if (h.t1 !== null) {
        const v = range(t - (h.t1 + i * 0.011), 0, 0.34);
        y -= easeInCubic(v) * 90;
        alpha *= 1 - v;
        rot -= easeInCubic(v) * 0.12;
      } else {
        const M = { a: 1, b: 0, c: 0, d: 1 };
        const vx = vortex(x + c.w / 2, y - 30, M, t, T.collapse + 0.18 + i * 0.016, 0.62, 2.8);
        if (vx.u >= 1) return;
        if (vx.u > 0) {
          ctx.setTransform(vx.a, vx.b, vx.c, vx.d, vx.x, vx.y);
          ctx.fillStyle = rgba(mixc(c.col, WHITE, vx.e), 1);
          ctx.fillText(c.ch, -c.w / 2, 30);
          ctx.setTransform(1, 0, 0, 1, 0, 0);
          return;
        }
      }
      if (alpha <= 0) return;
      ctx.setTransform(Math.cos(rot) * s, Math.sin(rot) * s, -Math.sin(rot) * s, Math.cos(rot) * s, x, y);
      ctx.fillStyle = rgba(c.col, alpha);
      ctx.fillText(c.ch, 0, 0);
      ctx.setTransform(1, 0, 0, 1, 0, 0);
    });
  }
}

function drawOpeningHUD(t) {
  const a = range(t, 0.3, 0.9) * (1 - range(t, T.collapse, T.collapse + 0.4));
  if (a <= 0) return;
  const j = Math.max(0, fixIndexAt(t) + 1);
  const regress = FIX.slice(0, j).filter((f) => f.type === "regress").length;
  const { y, scale: s } = LAYOUT.hud;
  ctx.globalAlpha = a;
  ctx.textBaseline = "alphabetic";
  ctx.textAlign = "left";
  ctx.font = SG(600, 15 * s);
  ctx.letterSpacing = 4 * s + "px";
  ctx.fillStyle = rgba(INK, 0.75);
  ctx.fillText("EYE TRACE", 72 + 24 * s, y);
  const blink = Math.floor(t * 2.08) % 2 === 0 ? 1 : 0.35;
  ctx.fillStyle = rgba(RED, blink);
  ctx.beginPath();
  ctx.arc(72 + 6 * s, y - 5 * s, 5 * s, 0, TAU);
  ctx.fill();
  ctx.font = JB(400, 15 * s);
  ctx.letterSpacing = 1 * s + "px";
  ctx.fillStyle = rgba(INK, 0.5);
  ctx.fillText(`FIXATIONS ${String(j).padStart(3, "0")}   REGRESSIONS ${String(regress).padStart(2, "0")}`, 72, y + 28 * s);
  ctx.textAlign = "right";
  ctx.font = SG(500, 15 * s);
  ctx.letterSpacing = 4 * s + "px";
  ctx.fillStyle = rgba(INK, 0.45);
  ctx.fillText("MOBY-DICK  ·  CHAPTER 1", W - 72, y);
  ctx.font = JB(400, 15 * s);
  ctx.letterSpacing = 1 * s + "px";
  ctx.fillText(`T+${t.toFixed(2)}s`, W - 72, y + 28 * s);
  ctx.letterSpacing = "0px";
  ctx.globalAlpha = 1;
}

function drawOpening(t) {
  const cam = pageCamera(t);
  const focus = cam.dist;
  const A = lerp(16, 7, smooth(range(t, 0, T.collapse)));
  const blurOf = (z) => Math.min(34, (A * Math.abs(z - focus)) / Math.max(z, 1));
  const U = [1, 0, 0], V = [0, 1, 0];
  const gaze = gazeAt(t);
  const gp = project(cam, gaze);

  // The page as a lit sheet.
  const pageA = 1 - range(t, T.collapse + 0.1, T.collapse + 1.2);
  if (pageA > 0) {
    const b = PAGE.bounds;
    const corners = [[b.x0, b.y0, 0], [b.x1, b.y0, 0], [b.x1, b.y1, 0], [b.x0, b.y1, 0]].map((p) => project(cam, p));
    if (corners.every((p) => p.z > 10)) {
      ctx.save();
      ctx.beginPath();
      corners.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      ctx.closePath();
      const g = ctx.createRadialGradient(gp.x, gp.y, 0, gp.x, gp.y, 1100);
      g.addColorStop(0, `rgba(34,31,28,${pageA})`);
      g.addColorStop(0.5, `rgba(18,17,16,${pageA})`);
      g.addColorStop(1, `rgba(10,10,10,${pageA})`);
      ctx.fillStyle = g;
      ctx.fill();
      ctx.strokeStyle = `rgba(255,255,255,${0.05 * pageA})`;
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.restore();
    }
  }

  // Words.
  PAGE.items.forEach((it, i) => {
    const M = planeAffine(cam, [it.x, it.y - 10, 0], U, V);
    if (!M.ok) return;
    let lit = it.deco ? 0 : litAmount(it, t);
    const col0 = mixc(it.col, WHITE, lit);
    let alpha = lerp(it.baseAlpha, 1, lit);
    const blur0 = blurOf(M.z);
    const vx = vortex(M.e, M.f, M, t, it.tl, it.dur, it.spin);
    if (vx.u >= 1) return;
    let x = M.e, y = M.f, m = M, col = col0, blur = blur0;
    if (vx.u > 0) {
      x = vx.x; y = vx.y; m = vx;
      col = vx.e < 0.6 ? mixc(col0, WHITE, vx.e / 0.6) : mixc(WHITE, [255, 120, 90], (vx.e - 0.6) / 0.4);
      alpha = lerp(alpha, 1, Math.min(1, vx.e * 1.5));
      blur = blur0 * (1 - vx.e);
    } else if (x < -500 || x > W + 500 || y < -300 || y > H + 300) {
      return;
    }
    addDrawable(M.z, blur, (c) => {
      c.setTransform(m.a, m.b, m.c, m.d, x, y);
      c.font = it.font;
      c.letterSpacing = it.ls + "px";
      c.textAlign = "center";
      c.textBaseline = "alphabetic";
      c.fillStyle = rgba(col, alpha);
      c.fillText(it.text, 0, 10);
      if (lit > 0.05 && vx.u <= 0) {
        c.globalCompositeOperation = "lighter";
        c.fillStyle = rgba([255, 200, 190], lit * 0.35);
        c.fillText(it.text, 0, 10);
      }
    });
  });

  // Eye-tracking scanpath on the page plane.
  const pathA = 1 - range(t, T.collapse, T.collapse + 0.5);
  if (pathA > 0) {
    const j = fixIndexAt(t);
    for (let i = 1; i <= j; i++) {
      const f = FIX[i];
      const u = clamp((t - (f.start - f.sd)) / f.sd);
      const p0 = project(cam, FIX[i - 1].p);
      const p1raw = u < 1 ? lerp3(FIX[i - 1].p, f.p, easeInOutCubic(u)) : f.p;
      const p1 = project(cam, p1raw);
      if (p0.z < 40 || p1.z < 40) continue;
      const age = t - f.start;
      const segA = pathA * (0.28 + 0.5 * Math.exp(-Math.max(0, age) / 1.2));
      const back = f.type !== "forward";
      addDrawable((p0.z + p1.z) / 2 - 1, blurOf((p0.z + p1.z) / 2) * 0.8, (c) => {
        c.strokeStyle = rgba(back ? [255, 140, 110] : RED, segA);
        c.lineWidth = Math.max(1, 2.2 * (p0.s + p1.s) / 2);
        if (back) c.setLineDash([6, 6]);
        c.beginPath();
        c.moveTo(p0.x, p0.y);
        c.lineTo(p1.x, p1.y);
        c.stroke();
      });
    }
    for (let i = 0; i <= j; i++) {
      const f = FIX[i];
      if (t < f.start) continue;
      const held = Math.min(t - f.start, f.dur);
      const r = 9 + 30 * Math.sqrt(held / 0.48);
      const M = planeAffine(cam, f.p, U, V);
      if (!M.ok) continue;
      const age = t - f.start;
      const cA = pathA * (0.35 + 0.55 * Math.exp(-age / 1.0));
      addDrawable(M.z - 2, blurOf(M.z) * 0.8, (c) => {
        c.setTransform(M.a, M.b, M.c, M.d, M.e, M.f);
        c.beginPath();
        c.arc(0, 0, r, 0, TAU);
        c.fillStyle = rgba(RED, cA * 0.12);
        c.fill();
        c.lineWidth = 2;
        c.strokeStyle = rgba(RED, cA);
        c.stroke();
        c.font = JB(700, 13);
        c.letterSpacing = "0px";
        c.textAlign = "left";
        c.fillStyle = rgba(RED, cA * 0.9);
        c.fillText(String(i + 1), r + 5, -r + 4);
      });
    }
    if (gp.z > 40) {
      const f = FIX[Math.max(0, j)];
      const land = clamp((t - f.start) / 0.18);
      addDrawable(gp.z - 5, blurOf(gp.z) * 0.6, (c) => {
        c.globalCompositeOperation = "lighter";
        const g = c.createRadialGradient(gp.x, gp.y, 0, gp.x, gp.y, 46 * gp.s);
        g.addColorStop(0, rgba([255, 120, 100], 0.9 * pathA));
        g.addColorStop(0.25, rgba(RED, 0.35 * pathA));
        g.addColorStop(1, rgba(RED, 0));
        c.fillStyle = g;
        c.beginPath();
        c.arc(gp.x, gp.y, 46 * gp.s, 0, TAU);
        c.fill();
        c.fillStyle = rgba([255, 235, 230], pathA);
        c.beginPath();
        c.arc(gp.x, gp.y, 5.5 * gp.s, 0, TAU);
        c.fill();
        if (land < 1) {
          c.strokeStyle = rgba(RED, (1 - land) * 0.9 * pathA);
          c.lineWidth = 2;
          c.beginPath();
          c.arc(gp.x, gp.y, (10 + 50 * easeOutCubic(land)) * gp.s, 0, TAU);
          c.stroke();
        }
      });
    }
  }

  // Dust in the air above the page, pulled into the vortex with the words.
  MOTES.forEach((m, i) => {
    const p = add(m.p, scale(m.v, t));
    const q = project(cam, p);
    if (q.z < 60) return;
    const vx = vortex(q.x, q.y, { a: 1, b: 0, c: 0, d: 1 }, t, T.collapse + 0.1 + rnd(i, 20) * 0.9, 0.7, 2.5);
    if (vx.u >= 1) return;
    const x = vx.u > 0 ? vx.x : q.x, y = vx.u > 0 ? vx.y : q.y;
    const r = m.r * q.s;
    addDrawable(q.z, blurOf(q.z), (c) => {
      c.fillStyle = rgba(m.red ? RED : [255, 245, 230], 0.35);
      c.beginPath();
      c.arc(x, y, Math.max(0.8, r), 0, TAU);
      c.fill();
    });
  });

  flushDrawables(ctx, focus);

  // The singularity gathering at the center.
  const absorbed = smooth(range(t, T.collapse + 0.3, T.collapse + 1.45));
  if (absorbed > 0) {
    const flick = 0.85 + 0.15 * Math.sin(t * 90) * Math.sin(t * 37);
    const r = 6 + 40 * absorbed;
    ctx.globalCompositeOperation = "lighter";
    const g = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, r * 4);
    g.addColorStop(0, rgba(WHITE, absorbed * flick));
    g.addColorStop(0.12, rgba([255, 150, 130], 0.8 * absorbed));
    g.addColorStop(0.4, rgba(RED, 0.25 * absorbed));
    g.addColorStop(1, rgba(RED, 0));
    ctx.fillStyle = g;
    ctx.fillRect(W / 2 - r * 4, H / 2 - r * 4, r * 8, r * 8);
    const sw = ((1700 * W) / 1920) * absorbed;
    const lg = ctx.createLinearGradient(W / 2 - sw / 2, 0, W / 2 + sw / 2, 0);
    lg.addColorStop(0, rgba(RED, 0));
    lg.addColorStop(0.5, rgba([255, 200, 190], 0.7 * absorbed));
    lg.addColorStop(1, rgba(RED, 0));
    ctx.fillStyle = lg;
    ctx.fillRect(W / 2 - sw / 2, H / 2 - 1.5, sw, 3);
    for (let k = 1; k <= 4; k++) {
      const hit = T.singularity + k * S16;
      const u = range(t, hit - 0.42, hit);
      if (u <= 0 || u >= 1) continue;
      ctx.strokeStyle = rgba(RED, 0.55 * u);
      ctx.lineWidth = 1.5 + 2 * u;
      ctx.beginPath();
      ctx.arc(W / 2, H / 2, 760 * (1 - easeInCubic(u)) + 4, 0, TAU);
      ctx.stroke();
    }
    ctx.globalCompositeOperation = "source-over";
  }

  drawHeadlines(t);
  drawOpeningHUD(t);

  const fadeIn = 1 - range(t, 0, 0.7);
  if (fadeIn > 0) {
    ctx.fillStyle = `rgba(0,0,0,${fadeIn})`;
    ctx.fillRect(0, 0, W, H);
  }
}

// ---------------------------------------------------------------- reading

const PAUSE_DECEL = 0.2;
const RESUME_ACCEL = 0.14;
function tau(t) {
  const p = T.pause, r = T.resume;
  if (t < p) return t;
  if (t < p + PAUSE_DECEL) {
    const d = t - p;
    return p + d - (d * d) / (2 * PAUSE_DECEL);
  }
  const held = p + PAUSE_DECEL / 2;
  if (t < r) return held;
  if (t < r + RESUME_ACCEL) {
    const d = t - r;
    return held + (d * d) / (2 * RESUME_ACCEL);
  }
  return held + RESUME_ACCEL / 2 + (t - r - RESUME_ACCEL);
}

const TAU_CHAPTER = tau(T.chapter);
const TAU_CLIMAX = tau(T.climax);
const TAU_B15 = tau(bar(15));
const TAU_CUT = tau(T.cut);

function streamSpeed(x) {
  if (x < T.library) return 2300;
  if (x < TAU_CLIMAX) return lerp(2300, 3600, easeInCubic(range(x, T.library, TAU_CLIMAX)));
  if (x < TAU_B15) return 5600;
  return lerp(5600, 12000, easeInCubic(range(x, TAU_B15, TAU_CUT)));
}
const DT = 0.002;
const DTAB = (() => {
  const n = Math.ceil(44 / DT) + 2;
  const a = new Float64Array(n);
  for (let i = 0; i < n - 1; i++) a[i + 1] = a[i] + streamSpeed(i * DT) * DT;
  return a;
})();
function dist(x) {
  if (x <= 0) return x * 2300;
  const i = x / DT;
  const i0 = Math.floor(i);
  return lerp(DTAB[i0], DTAB[i0 + 1], i - i0);
}

const STREAM = SCHEDULE.filter((e) => e.kind !== "gap").map((e, k) => ({
  text: e.text,
  d: dist(tau(e.start)),
  phi: k * 2.39996 + (rnd(k, 30) - 0.5) * 0.5,
  rho: 440 + rnd(k, 31) * 900,
}));

function streamIntensity(t) {
  if (t < T.impact) return 0;
  let v = 0.3 * smooth(range(t, T.impact, T.impact + 1.0));
  v += 0.08 * range(t, bar(7), bar(8));
  v += 0.06 * range(t, bar(8), T.library);
  v += 0.4 * range(t, T.chapter, T.climax);
  v += 0.15 * range(t, bar(15), T.cut);
  return v;
}

const KICKS = kicks();
function pulse(t, from, to, decay = 9) {
  let p = 0;
  for (const k of KICKS) {
    if (k < from || k >= to || k > t) continue;
    p = Math.max(p, Math.exp(-(t - k) * decay));
  }
  return p;
}

// Generated covers, in the app's style.
const BOOKS = [
  ["Moby-Dick", "EPUB"], ["Frankenstein", "EPUB"], ["On the Origin of Species", "PDF"], ["Dracula", "EPUB"],
  ["Walden", "EPUB"], ["Field Notes", "TEXT"], ["The Odyssey", "EPUB"], ["Relativity", "PDF"],
  ["Middlemarch", "EPUB"], ["Pride and Prejudice", "EPUB"], ["The Republic", "PDF"], ["Jane Eyre", "EPUB"],
  ["On Attention", "TEXT"], ["Leaves of Grass", "EPUB"], ["The Time Machine", "EPUB"], ["The Wealth of Nations", "PDF"],
  ["Great Expectations", "EPUB"], ["Meditations", "EPUB"], ["Candide", "EPUB"], ["Hamlet", "EPUB"],
  ["Persuasion", "EPUB"], ["The Iliad", "EPUB"], ["Principia", "PDF"], ["Reading Notes", "TEXT"],
];
const COVER_W = 320, COVER_H = 480;
const PER_TURN = 8;
const COVERS = [];

function renderCover(title, kind, tone) {
  const S = 2;
  const w = COVER_W * S, h = COVER_H * S;
  const c = makeCanvas(w, h);
  const x = c.getContext("2d");
  x.fillStyle = rgba(tone, 1);
  x.fillRect(0, 0, w, h);
  const g = x.createLinearGradient(0, 0, w, h);
  g.addColorStop(0, "rgba(255,255,255,0.07)");
  g.addColorStop(0.5, "rgba(255,255,255,0)");
  g.addColorStop(1, "rgba(0,0,0,0.14)");
  x.fillStyle = g;
  x.fillRect(0, 0, w, h);
  const spine = Math.max(3, COVER_W * 0.045) * S;
  x.fillStyle = "rgba(0,0,0,0.28)";
  x.fillRect(0, 0, spine, h);
  x.fillStyle = "rgba(255,255,255,0.08)";
  x.fillRect(spine, 0, S, h);
  const inset = COVER_W * 0.09 * S;
  const size = COVER_W * 0.13 * S;
  const font = FR(600, size);
  x.font = font;
  x.textBaseline = "alphabetic";
  x.fillStyle = "rgb(244,236,225)";
  const maxW = w - spine - inset * 2;
  const words = title.split(" ");
  const lines = [];
  let line = "";
  for (const wd of words) {
    const test = line ? line + " " + wd : wd;
    if (line && x.measureText(test).width > maxW) {
      lines.push(line);
      line = wd;
    } else line = test;
  }
  lines.push(line);
  let y = inset + size * 0.92;
  for (const l of lines) {
    x.fillText(l, spine + inset, y);
    y += size * 1.1;
  }
  x.fillStyle = "rgba(244,236,225,0.35)";
  x.fillRect(spine + inset, y - size * 0.55 + COVER_W * 0.07 * S, COVER_W * 0.14 * S, S);
  x.font = `600 ${COVER_W * 0.065 * S}px system-ui`;
  x.letterSpacing = `${COVER_W * 0.012 * S}px`;
  x.fillStyle = "rgba(244,236,225,0.55)";
  x.fillText(kind, spine + inset, h - inset);
  x.strokeStyle = "rgba(255,255,255,0.07)";
  x.lineWidth = S;
  x.strokeRect(S / 2, S / 2, w - S, h - S);

  const back = makeCanvas(w / 2, h / 2);
  const bx = back.getContext("2d");
  bx.fillStyle = rgba(mixc(tone, [0, 0, 0], 0.45), 1);
  bx.fillRect(0, 0, w / 2, h / 2);
  bx.fillStyle = "rgba(0,0,0,0.3)";
  bx.fillRect(w / 2 - spine / 2, 0, spine / 2, h / 2);
  return { front: c, back };
}

function buildCovers() {
  BOOKS.forEach(([title, kind], i) => {
    const tone = hex(COVER_TONES[(i * 5 + 3) % COVER_TONES.length]);
    COVERS.push({ title, kind, ...renderCover(title, kind, tone), i });
  });
}

const ZC = 1850;
function helixCam(x) {
  const a = T.library, b = a + 1.5, c = TAU_CHAPTER, d = TAU_CLIMAX;
  let cy, cz, f, roll;
  if (x < b) {
    const u = easeInOutCubic(range(x, a, b));
    cz = lerp(0, -1150, u); cy = lerp(0, -620, u); f = lerp(1400, 1120, u); roll = lerp(0, 0.07, u);
  } else if (x < c) {
    const u = smooth(range(x, b, c));
    cz = lerp(-1150, -1350, u); cy = lerp(-620, 520, u); f = 1120; roll = 0.07 * Math.cos(u * Math.PI);
  } else {
    const u = easeInCubic(range(x, c, d));
    cz = lerp(-1350, -40, u); cy = lerp(520, 0, u); f = lerp(1120, 1400, u); roll = lerp(-0.07, 0, u);
  }
  return lookAt([0, cy, cz], [0, cy * 0.12, ZC], roll, f);
}

function helixAngle(x) {
  const base = 0.5 * (x - T.library);
  const ramp = Math.max(0, x - TAU_CHAPTER);
  return 0.35 + base + (2.9 * ramp * ramp) / (2 * (TAU_CLIMAX - TAU_CHAPTER));
}

function coverState(i, x) {
  const th = i * (TAU / PER_TURN) + helixAngle(x);
  const R = lerp(2900, 900, easeOutCubic(range(x, T.library + i * 0.02, T.library + 1.3 + i * 0.02)));
  const y = (i - (BOOKS.length - 1) / 2) * 150;
  const C = [R * Math.sin(th), y, ZC - R * Math.cos(th)];
  const U = [Math.cos(th), 0, Math.sin(th)];
  const V = [0, 1, 0];
  const N = [Math.sin(th), 0, -Math.cos(th)];
  return { C, U, V, N };
}

function kindFocus(t) {
  const words = { "Books.": "EPUB", "Papers.": "PDF", "Articles.": "TEXT" };
  for (const e of SCHEDULE) if (t >= e.start && t < e.end && words[e.text]) return words[e.text];
  return null;
}

function drawCover(cv, cam, st, alpha, t, blurOf) {
  const M = planeAffine(cam, st.C, st.U, st.V);
  if (!M.ok || alpha <= 0) return;
  if (M.e < -900 || M.e > W + 900 || M.f < -900 || M.f > H + 900) return;
  const toCam = norm(sub(cam.pos, st.C));
  const facing = dot(st.N, toCam);
  const front = M.a * M.d - M.b * M.c > 0;
  const kf = kindFocus(t);
  const dim = kf && cv.kind !== kf ? 0.55 : 0;
  const lift = kf && cv.kind === kf ? 1 : 0;
  addDrawable(M.z, blurOf(M.z), (c) => {
    c.setTransform(M.a, M.b, M.c, M.d, M.e, M.f);
    c.globalAlpha = alpha;
    c.drawImage(front ? cv.front : cv.back, -COVER_W / 2, -COVER_H / 2, COVER_W, COVER_H);
    const shade = 0.5 * (1 - Math.abs(facing)) + dim;
    if (shade > 0) {
      c.fillStyle = `rgba(0,0,0,${clamp(shade, 0, 0.92)})`;
      c.fillRect(-COVER_W / 2, -COVER_H / 2, COVER_W, COVER_H);
    }
    const sheen = Math.pow(Math.max(0, facing), 10) * 0.16 + lift * 0.1;
    if (sheen > 0.005 && front) {
      c.globalCompositeOperation = "lighter";
      c.fillStyle = `rgba(255,255,255,${sheen})`;
      c.fillRect(-COVER_W / 2, -COVER_H / 2, COVER_W, COVER_H);
    }
    if (lift > 0 && front) {
      c.globalCompositeOperation = "lighter";
      c.strokeStyle = rgba(RED, 0.9);
      c.lineWidth = 3;
      c.strokeRect(-COVER_W / 2 - 6, -COVER_H / 2 - 6, COVER_W + 12, COVER_H + 12);
    }
  });
}

// Covers break into fragments on the first downbeat of the climax.
const SHARD_COLS = 3, SHARD_ROWS = 4;
function drawShards(t, cam, blurOf) {
  const ts = t - T.climax;
  if (ts < 0 || ts > 1.9) return;
  const x0 = TAU_CLIMAX;
  COVERS.forEach((cv, i) => {
    const st = coverState(i, x0);
    for (let gy = 0; gy < SHARD_ROWS; gy++) {
      for (let gx = 0; gx < SHARD_COLS; gx++) {
        const k = i * 100 + gy * 10 + gx;
        const fw = COVER_W / SHARD_COLS, fh = COVER_H / SHARD_ROWS;
        const lx = -COVER_W / 2 + fw * (gx + 0.5), ly = -COVER_H / 2 + fh * (gy + 0.5);
        const p0 = add(st.C, add(scale(st.U, lx), scale(st.V, ly)));
        const radial = norm([st.C[0], 0, st.C[2] - ZC]);
        const speed = 700 + rnd(k, 40) * 1500;
        const vel = add(scale(radial, speed), [(rnd(k, 41) - 0.5) * 900, (rnd(k, 42) - 0.5) * 900, -rnd(k, 43) * 1600]);
        const drag = ts - 0.28 * ts * ts;
        const p = add(p0, scale(vel, drag));
        const axis = norm([rnd(k, 44) - 0.5, rnd(k, 45) - 0.5, rnd(k, 46) - 0.5]);
        const ang = (4 + rnd(k, 47) * 9) * ts;
        const U = rotateAxis(st.U, axis, ang);
        const V = rotateAxis(st.V, axis, ang);
        const M = planeAffine(cam, p, U, V);
        if (!M.ok) continue;
        const a = (1 - range(ts, 0.5 + rnd(k, 48) * 0.6, 1.8)) * range(M.z, 180, 650);
        if (a <= 0) continue;
        const front = M.a * M.d - M.b * M.c > 0;
        addDrawable(M.z, blurOf(M.z), (c) => {
          c.setTransform(M.a, M.b, M.c, M.d, M.e, M.f);
          c.globalAlpha = a;
          const img = front ? cv.front : cv.back;
          const sx = img.width / SHARD_COLS, sy = img.height / SHARD_ROWS;
          c.drawImage(img, gx * sx, gy * sy, sx, sy, -fw / 2, -fh / 2, fw, fh);
          c.globalCompositeOperation = "lighter";
          c.fillStyle = rgba([255, 120, 90], 0.5 * Math.exp(-ts * 5));
          c.fillRect(-fw / 2, -fh / 2, fw, fh);
        });
      }
    }
  });
}

const DOTS = Array.from({ length: 170 }, (_, i) => ({
  phi: rnd(i, 60) * TAU, rho: 200 + Math.pow(rnd(i, 61), 0.7) * 1700, off: rnd(i, 62) * 7000, r: 1.2 + rnd(i, 63) * 2.4, red: rnd(i, 64) < 0.2,
}));
const STREAKS = Array.from({ length: 220 }, (_, i) => ({
  phi: rnd(i, 70) * TAU, rho: 260 + Math.pow(rnd(i, 71), 0.6) * 1900, off: rnd(i, 72) * 9000, red: rnd(i, 73) < 0.22, w: 1 + rnd(i, 74) * 2,
}));

function entryAt(list, t) {
  let lo = 0, hi = list.length - 1;
  while (lo <= hi) {
    const m = (lo + hi) >> 1;
    if (list[m].end <= t) lo = m + 1;
    else if (list[m].start > t) hi = m - 1;
    else return { e: list[m], i: m };
  }
  return null;
}

function shakeAt(t) {
  let amp = 0;
  if (t >= T.impact) amp += 24 * Math.exp(-(t - T.impact) * 7);
  if (t >= T.climax && t < T.cut) amp += 7 * pulse(t, T.climax, T.cut, 12) + 5 * easeInCubic(range(t, bar(15), T.cut));
  if (t >= T.climax && t < T.climax + 0.6) amp += 18 * Math.exp(-(t - T.climax) * 6);
  const n = (s) => Math.sin(t * 71 + s) * 0.6 + Math.sin(t * 131 + s * 2) * 0.4;
  return [n(0) * amp, n(3) * amp, n(5) * amp * 0.0015];
}

function drawGuide(t, cam, hs, alphaScale = 1) {
  // Full-height hairline with a bright core around the word, like the app icon.
  const top = H / 2 - hs, bot = H / 2 + hs;
  if (cam && cam.sr !== 0) {
    ctx.save();
    ctx.translate(W / 2, H / 2);
    ctx.rotate(Math.atan2(cam.sr, cam.cr));
    ctx.translate(-W / 2, -H / 2);
  }
  const g = ctx.createLinearGradient(0, top, 0, bot);
  g.addColorStop(0, rgba(RED, 0));
  g.addColorStop(0.3, rgba(RED, 0.22 * alphaScale));
  g.addColorStop(0.5, rgba(RED, 0.35 * alphaScale));
  g.addColorStop(0.7, rgba(RED, 0.22 * alphaScale));
  g.addColorStop(1, rgba(RED, 0));
  ctx.fillStyle = g;
  ctx.fillRect(W / 2 - 1, top - 200, 2, bot - top + 400);
  const core = Math.min(hs, 150);
  const g2 = ctx.createLinearGradient(0, H / 2 - core, 0, H / 2 + core);
  g2.addColorStop(0, rgba([255, 140, 125], 0));
  g2.addColorStop(0.2, rgba([255, 140, 125], 0.5 * alphaScale));
  g2.addColorStop(0.8, rgba([255, 140, 125], 0.5 * alphaScale));
  g2.addColorStop(1, rgba([255, 140, 125], 0));
  ctx.fillStyle = g2;
  ctx.fillRect(W / 2 - 2, H / 2 - core, 4, core * 2);
  if (cam && cam.sr !== 0) ctx.restore();
}

function drawTouch(t) {
  const { x: fx, hold, from, to, scale: k } = LAYOUT.touch;
  const draw = (x, y, a, s, ripples) => {
    if (a <= 0) return;
    ctx.save();
    ctx.globalAlpha = a;
    for (const r0 of ripples) {
      const u = range(t, r0, r0 + 0.7);
      if (u <= 0 || u >= 1) continue;
      ctx.strokeStyle = `rgba(255,255,255,${0.45 * (1 - u)})`;
      ctx.lineWidth = 2 * k;
      ctx.beginPath();
      ctx.arc(x, y, (40 + 90 * easeOutCubic(u)) * k, 0, TAU);
      ctx.stroke();
    }
    const g = ctx.createRadialGradient(x, y, 0, x, y, 44 * s * k);
    g.addColorStop(0, "rgba(255,255,255,0.28)");
    g.addColorStop(0.8, "rgba(255,255,255,0.12)");
    g.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y, 44 * s * k, 0, TAU);
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.7)";
    ctx.lineWidth = 2 * k;
    ctx.beginPath();
    ctx.arc(x, y, 34 * s * k, 0, TAU);
    ctx.stroke();
    ctx.restore();
  };
  const hold0 = T.hold, hold1 = T.pause;
  if (t >= hold0 - 0.05 && t < hold1 + 0.4) {
    const down = easeOutCubic(range(t, hold0 - 0.05, hold0 + 0.12));
    const up = range(t, hold1, hold1 + 0.35);
    draw(fx, hold, down * (1 - up), lerp(1.4, 1, down) + up * 0.6, [0, 1, 2, 3].map((n) => hold0 + n * BEAT));
  }
  // Letting go pauses, so the finger stays down while the book plays on.
  const s0 = T.resume, s1 = T.climax;
  if (t >= s0 - 0.05 && t < s1 + 0.3) {
    const down = easeOutCubic(range(t, s0 - 0.05, s0 + 0.12));
    const vis = down * (1 - range(t, s1 - 0.05, s1 + 0.25));
    const y = lerp(from, to, slideAt(t));
    const trail = vis * (1 - range(t, T.chapter - 0.1, T.chapter + 0.1));
    for (let i = 1; i <= 6 && trail > 0; i++) {
      const yi = lerp(from, to, slideAt(t - i * 0.03));
      ctx.fillStyle = `rgba(255,255,255,${0.05 * trail})`;
      ctx.beginPath();
      ctx.arc(fx, yi, 30 * k, 0, TAU);
      ctx.fill();
    }
    draw(fx, y, vis, lerp(1.4, 1, down), [s0]);
    ctx.font = SG(600, 14 * k);
    ctx.letterSpacing = 4 * k + "px";
    ctx.textAlign = "left";
    ctx.fillStyle = `rgba(255,255,255,${0.55 * vis * (1 - range(t, T.chapter - 0.05, T.chapter + 0.35))})`;
    ctx.fillText("↑  FASTER", fx + 60 * k, y + 5 * k);
    ctx.letterSpacing = "0px";
  }
}

function drawSpeedHUD(t, tf) {
  const inU = range(t, T.rsvp + 0.4, T.rsvp + 1.0);
  const vis = inU * (1 - range(t, T.squeeze - 0.3, T.squeeze + 0.05));
  if (vis <= 0) return;
  const s = LAYOUT.speed.scale;
  const y = LAYOUT.speed.y + (1 - easeOutCubic(inU)) * 50 * s;
  const wpm = Math.round(wpmAt(tf) / 10) * 10;
  const x = W / 2 - 250 * s, w = 500 * s, h = 70 * s;
  ctx.save();
  ctx.globalAlpha = vis;
  ctx.fillStyle = "rgba(17,17,17,0.86)";
  ctx.strokeStyle = "rgba(255,255,255,0.06)";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.roundRect(x, y - h / 2, w, h, 22 * s);
  ctx.fill();
  ctx.stroke();
  ctx.textBaseline = "middle";
  ctx.textAlign = "right";
  ctx.font = SG(600, 32 * s);
  ctx.fillStyle = rgba(ACCENT, 1);
  ctx.fillText(wpm.toLocaleString("en-US"), x + 128 * s, y + 1 * s);
  ctx.textAlign = "left";
  ctx.font = SG(400, 19 * s);
  ctx.fillStyle = "rgba(160,160,160,1)";
  ctx.fillText("wpm", x + 140 * s, y + 2 * s);
  const tx0 = x + 212 * s, tx1 = x + w - 36 * s;
  const u = (wpm - 100) / 900;
  const kx = lerp(tx0 + 20 * s, tx1 - 20 * s, u);
  ctx.fillStyle = "#2c2c2e";
  ctx.beginPath();
  ctx.roundRect(tx0, y - 3 * s, tx1 - tx0, 6 * s, 3 * s);
  ctx.fill();
  ctx.fillStyle = rgba(ACCENT, 1);
  ctx.beginPath();
  ctx.roundRect(tx0, y - 3 * s, kx - tx0, 6 * s, 3 * s);
  ctx.fill();
  ctx.fillStyle = "#fff";
  ctx.shadowColor = "rgba(0,0,0,0.5)";
  ctx.shadowBlur = 8 * s;
  ctx.beginPath();
  ctx.roundRect(kx - 20 * s, y - 13 * s, 40 * s, 26 * s, 13 * s);
  ctx.fill();
  ctx.restore();
}

// The vertical frame is narrower than the longest words at the wide cut's sizes, so all
// the words shrink together until every one fits with a margin, as the app keeps one size.
let WORD_SCALE = 1;
function fitWordScale() {
  if (!TALL) return 1;
  let reach = 0;
  for (const e of SCHEDULE) if (e.kind === "word") reach = Math.max(reach, anchorReach(e.text, 168));
  return Math.min(1, (W / 2 - 64) / reach);
}

function drawReading(t, tf) {
  const [sx, sy, srot] = shakeAt(t);
  const squeeze = range(t, T.squeeze, T.cut);
  const sqx = 1 - easeInExpo(squeeze) * 0.997;
  const sqy = 1 + 0.08 * easeInCubic(squeeze);
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.translate(W / 2 + sx, H / 2 + sy);
  ctx.rotate(srot);
  ctx.scale(sqx, sqy);
  ctx.translate(-W / 2, -H / 2);

  const x = tau(t);
  const inLibrary = t >= T.library && t < T.climax;
  const inClimax = t >= T.climax;
  const p4 = pulse(t, T.library, T.climax, 8);
  const p5 = pulse(t, T.climax, T.cut, 8);

  // Background light.
  const glow = 0.5 + 0.5 * p5;
  const bg = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, 1100);
  bg.addColorStop(0, rgba(mixc([14, 9, 9], [70, 14, 10], p5 * 0.55), 1));
  bg.addColorStop(1, rgba(mixc([5, 5, 5], [20, 5, 4], p5 * 0.6), 1));
  ctx.fillStyle = bg;
  ctx.fillRect(-200, -200, W + 400, H + 400);

  // Light rays from the fixation point during the climax.
  const rays = range(t, T.climax - 0.2, T.climax + 0.4) * glow;
  if (rays > 0 && inClimax) {
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    ctx.translate(W / 2, H / 2);
    for (let k = 0; k < 16; k++) {
      const a0 = k * (TAU / 16) + t * 0.25 + rnd(k, 80) * 0.3;
      const wdt = 0.05 + rnd(k, 81) * 0.08;
      const g = ctx.createRadialGradient(0, 0, 60, 0, 0, 1300);
      g.addColorStop(0, rgba(RED, 0.08 * rays));
      g.addColorStop(1, rgba(RED, 0));
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.arc(0, 0, 1400, a0, a0 + wdt);
      ctx.closePath();
      ctx.fill();
    }
    ctx.restore();
  }

  // Giant speed numeral behind everything.
  const giant = range(t, bar(14) - 0.1, bar(14) + 0.3);
  if (giant > 0 && inClimax) {
    ctx.save();
    const s = lerp(1.35, 1.0, easeOutCubic(range(t, bar(14), T.cut))) * (1 + 0.03 * p5) * LAYOUT.giant;
    ctx.translate(W / 2, H / 2);
    ctx.rotate(-0.04 + 0.02 * Math.sin(t * 1.3));
    ctx.scale(s, s);
    ctx.font = FR(800, 640);
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.letterSpacing = "-10px";
    ctx.lineWidth = 2.5;
    ctx.strokeStyle = rgba(RED, (0.1 + 0.18 * p5) * giant);
    ctx.strokeText("1,000", 0, 30);
    ctx.letterSpacing = "0px";
    ctx.restore();
  }

  // Camera for everything in depth.
  let cam;
  if (inLibrary) cam = helixCam(x);
  else if (inClimax) {
    cam = helixCam(TAU_CLIMAX);
    const roll = 0.03 * Math.sin(t * 1.6) + 0.02 * Math.sin(t * 3.1) * range(t, bar(14), T.cut);
    cam = { ...cam, cr: Math.cos(roll), sr: Math.sin(roll) };
  } else cam = identityCam(1400, 0.012 * Math.sin(t * 0.8));
  const fBase = cam.f * (1 + 0.05 * p5 + 0.015 * p4);
  const scam = identityCam(fBase, Math.atan2(cam.sr, cam.cr));
  const focusZ = fBase;
  const aperture = inClimax ? 7 : 9;
  const blurOf = (z) => Math.min(34, (aperture * Math.abs(z - focusZ)) / Math.max(z, 1));

  // Words streaming through the fixation point.
  const I = streamIntensity(t);
  const D = dist(x);
  const copies = inClimax ? 3 : 1;
  for (const w of STREAM) {
    for (let c = 0; c < copies; c++) {
      const z = fBase + (w.d + c * 190) - D;
      if (z < 130 || z > fBase + 6800) continue;
      const cA = c === 0 ? 1 : range(t, T.climax, T.climax + 0.6);
      const phi = w.phi + c * 2.1;
      const rho = w.rho * (c ? 1.25 + c * 0.2 : 1);
      const px = rho * Math.cos(phi) * LAYOUT.stream[0], py = rho * Math.sin(phi) * LAYOUT.stream[1];
      const p = project(scam, [px, py, z]);
      if (p.x < -600 || p.x > W + 600 || p.y < -400 || p.y > H + 400) continue;
      const a = I * cA * (1 - range(z, fBase + 3800, fBase + 6800)) * range(z, 130, 600);
      if (a <= 0.004) continue;
      const s = p.s;
      addDrawable(z, blurOf(z), (cx) => {
        cx.setTransform(s * scam.cr, s * scam.sr, -s * scam.sr, s * scam.cr, p.x, p.y);
        drawAnchored(cx, w.text, 0, 0, 60, { color: rgba(INK, a), anchorColor: rgba(RED, Math.min(1, a * 1.6)) });
      });
    }
  }

  // Dust flowing with the stream.
  for (const d of DOTS) {
    const z = 150 + ((((d.off - D * 0.9) % 6850) + 6850) % 6850);
    const p = project(scam, [d.rho * Math.cos(d.phi), d.rho * Math.sin(d.phi), z]);
    if (p.x < -50 || p.x > W + 50 || p.y < -50 || p.y > H + 50) continue;
    const a = (0.2 + 0.5 * I) * range(z, 150, 500) * (1 - range(z, 5000, 7000));
    addDrawable(z, blurOf(z), (c) => {
      c.fillStyle = rgba(d.red ? RED : [255, 240, 225], a);
      c.beginPath();
      c.arc(p.x, p.y, Math.max(0.7, d.r * p.s), 0, TAU);
      c.fill();
    });
  }

  // Warp streaks as the speed climbs.
  const WS = range(t, T.chapter + BAR * 0.5, T.climax) * 0.35 + range(t, T.climax, T.climax + 0.2) * 0.4 + range(t, bar(15), T.cut) * 0.5;
  if (WS > 0) {
    const len = 250 + streamSpeed(x) * 0.09;
    for (const s of STREAKS) {
      const z = 120 + ((((s.off - D * 1.5) % 8900) + 8900) % 8900);
      const [ax, ay] = LAYOUT.streaks;
      const pa = project(scam, [s.rho * Math.cos(s.phi) * ax, s.rho * Math.sin(s.phi) * ay, z]);
      const pb = project(scam, [s.rho * Math.cos(s.phi) * ax, s.rho * Math.sin(s.phi) * ay, z + len]);
      if (pa.x < -800 || pa.x > W + 800 || pa.y < -800 || pa.y > H + 800) continue;
      const a = WS * range(z, 120, 900) * (1 - range(z, 6000, 9000));
      addDrawable(z, 0, (c) => {
        c.globalCompositeOperation = "lighter";
        c.strokeStyle = rgba(s.red ? RED : [255, 235, 225], a);
        c.lineWidth = Math.max(0.6, s.w * pa.s);
        c.beginPath();
        c.moveTo(pa.x, pa.y);
        c.lineTo(pb.x, pb.y);
        c.stroke();
      });
    }
  }

  // The library helix around the red axis.
  if (inLibrary) {
    const hcam = cam;
    const focus = Math.abs(dot(sub([0, 0, ZC], hcam.pos), hcam.fwd));
    const cblur = (z) => Math.min(30, (10 * Math.abs(z - focus)) / Math.max(z, 1));
    const appear = range(t, T.library - 0.05, T.library + 0.6);
    COVERS.forEach((cv, i) => drawCover(cv, hcam, coverState(i, x), appear, t, cblur));
  }
  if (inClimax) drawShards(t, helixCam(TAU_CLIMAX), blurOf);

  flushDrawables(ctx, focusZ);

  // The red axis. In the library it is the helix's spine in 3D.
  const lineGrow = easeOutExpo(range(t, T.impact, T.impact + 0.45));
  drawGuide(t, inLibrary || inClimax ? cam : scam, LAYOUT.guide * lineGrow + 10, 1 + 0.6 * p5);

  // Word, with a dark halo to keep it legible over the helix.
  const cur = entryAt(SCHEDULE, tf);
  const size = (inClimax ? 168 : inLibrary ? 150 : 156) * WORD_SCALE;
  const halo = t >= T.library ? 1 : 0.6;
  const hg = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, 560);
  hg.addColorStop(0, `rgba(5,5,5,${0.72 * halo})`);
  hg.addColorStop(0.45, `rgba(5,5,5,${0.4 * halo})`);
  hg.addColorStop(1, "rgba(5,5,5,0)");
  ctx.save();
  ctx.translate(W / 2, H / 2);
  ctx.scale(1, 0.42);
  ctx.translate(-W / 2, -H / 2);
  ctx.fillStyle = hg;
  ctx.fillRect(W / 2 - 560, H / 2 - 560, 1120, 1120);
  ctx.restore();

  if (cur && cur.e.kind === "word") {
    const paused = t >= T.pause && t < T.resume;
    if (inClimax) {
      ctx.save();
      ctx.globalCompositeOperation = "lighter";
      const rg = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, 260);
      rg.addColorStop(0, rgba(RED, 0.16 + 0.25 * p5));
      rg.addColorStop(1, rgba(RED, 0));
      ctx.fillStyle = rg;
      ctx.fillRect(W / 2 - 260, H / 2 - 260, 520, 520);
      ctx.restore();
    }
    const ext = drawAnchored(ctx, cur.e.text, W / 2, H / 2, size, { color: "#fff", anchorColor: rgba(RED, 1) });
    const ctxA = range(t, T.pause + 0.12, T.pause + 0.3) * (1 - range(t, T.resume - 0.06, T.resume));
    if (paused || ctxA > 0) {
      ctx.font = FR(400, size);
      ctx.fillStyle = `rgba(255,255,255,${0.35 * ctxA})`;
      ctx.textAlign = "right";
      ctx.fillText("to", ext.left - size * 0.42, H / 2 + size * 0.3);
      ctx.textAlign = "left";
      ctx.fillText("Slide", ext.right + size * 0.42, H / 2 + size * 0.3);
      const s = LAYOUT.hud.scale, y = LAYOUT.paused;
      ctx.font = SG(600, 15 * s);
      ctx.letterSpacing = 6 * s + "px";
      ctx.textAlign = "center";
      ctx.fillStyle = `rgba(244,236,225,${0.6 * ctxA})`;
      ctx.fillText("PAUSED", W / 2 + 12 * s, y);
      ctx.fillRect(W / 2 - 74 * s, y - 12 * s, 4 * s, 16 * s);
      ctx.fillRect(W / 2 - 66 * s, y - 12 * s, 4 * s, 16 * s);
      ctx.letterSpacing = "0px";
    }
  } else if (cur && cur.e.kind === "chapter") {
    const { start, end } = cur.e;
    const out = smooth(range(t, end - 0.25, end));
    const label = easeOutCubic(range(t, start, start + 0.35));
    const title = easeOutCubic(range(t, start + 0.06, start + 0.46));
    const k = WORD_SCALE;
    const lift = -10 * out;
    drawSprite(ctx, textSprite(SG(600, 24 * k), 9 * k, "MOBY-DICK", rgba(RED, 0.9), "center"), W / 2 + 4.5 * k, H / 2 + (-110 + 12 * (1 - label) + lift) * k, label * (1 - out));
    drawSprite(ctx, textSprite(FR(600, 132 * k), 0, cur.e.text, rgba(INK, 1), "center"), W / 2, H / 2 + (44 + 22 * (1 - title) + lift) * k, title * (1 - out));
  }

  // Impact: flash, shockwaves, sparks.
  const ti = t - T.impact;
  if (ti >= 0 && ti < 1.4) {
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    for (const [delay, maxR, wdt, col] of [[0, 1500, 34, [255, 180, 160]], [0.06, 1100, 10, RED], [0.12, 1900, 4, WHITE]]) {
      const u = range(ti, delay, delay + 0.95);
      if (u <= 0 || u >= 1) continue;
      ctx.strokeStyle = rgba(col, 0.7 * (1 - u));
      ctx.lineWidth = wdt * (1 - u) + 1;
      ctx.beginPath();
      ctx.arc(W / 2, H / 2, 20 + maxR * easeOutCubic(u), 0, TAU);
      ctx.stroke();
    }
    for (let k = 0; k < 220; k++) {
      const life = 0.35 + rnd(k, 90) * 0.9;
      if (ti > life) continue;
      const ang = rnd(k, 91) * TAU;
      const sp = 400 + Math.pow(rnd(k, 92), 1.6) * 2600;
      const r = sp * (ti - 0.45 * ti * ti / life);
      const r2 = Math.max(0, r - sp * 0.025);
      const a = 1 - ti / life;
      ctx.strokeStyle = rgba(rnd(k, 93) < 0.5 ? WHITE : [255, 110, 90], a);
      ctx.lineWidth = 1 + rnd(k, 94) * 2;
      ctx.beginPath();
      ctx.moveTo(W / 2 + Math.cos(ang) * r2, H / 2 + Math.sin(ang) * r2 * LAYOUT.squash.burst);
      ctx.lineTo(W / 2 + Math.cos(ang) * r, H / 2 + Math.sin(ang) * r * LAYOUT.squash.burst);
      ctx.stroke();
    }
    const fl = Math.exp(-ti * 14);
    ctx.fillStyle = `rgba(255,236,230,${0.75 * fl})`;
    ctx.fillRect(-200, -200, W + 400, H + 400);
    ctx.restore();
  }

  // Beat rings and sparks.
  if (t >= T.library) {
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    KICKS.forEach((k, ki) => {
      const u = (t - k) / 0.7;
      if (u < 0 || u >= 1 || k >= T.cut) return;
      const strong = k >= T.climax;
      ctx.strokeStyle = rgba(strong ? [255, 120, 100] : [255, 255, 255], (strong ? 0.45 : 0.1) * (1 - u));
      ctx.lineWidth = (strong ? 6 : 2) * (1 - u) + 0.5;
      ctx.beginPath();
      ctx.ellipse(W / 2, H / 2, 150 + 1300 * easeOutCubic(u), (150 + 1300 * easeOutCubic(u)) * LAYOUT.squash.rings, 0, 0, TAU);
      ctx.stroke();
      if (!strong) return;
      const ts = t - k;
      for (let s = 0; s < 46; s++) {
        const id = ki * 97 + s;
        const life = 0.25 + rnd(id, 95) * 0.4;
        if (ts > life) continue;
        const ang = rnd(id, 96) * TAU;
        const sp = 600 + rnd(id, 97) * 2200;
        const r = 90 + sp * ts;
        ctx.strokeStyle = rgba(rnd(id, 98) < 0.5 ? WHITE : RED, 0.9 * (1 - ts / life));
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        const sy = LAYOUT.squash.sparks;
        ctx.moveTo(W / 2 + Math.cos(ang) * r, H / 2 + Math.sin(ang) * r * sy);
        ctx.lineTo(W / 2 + Math.cos(ang) * (r + 30 + sp * 0.02), H / 2 + Math.sin(ang) * (r + 30 + sp * 0.02) * sy);
        ctx.stroke();
      }
    });
    ctx.restore();
  }

  ctx.setTransform(1, 0, 0, 1, 0, 0);

  // Everything collapses into the red line.
  if (squeeze > 0) {
    const g = ctx.createLinearGradient(W / 2 - 60, 0, W / 2 + 60, 0);
    const a = easeInCubic(squeeze);
    g.addColorStop(0, rgba(RED, 0));
    g.addColorStop(0.5, rgba([255, 200, 190], a));
    g.addColorStop(1, rgba(RED, 0));
    ctx.globalCompositeOperation = "lighter";
    ctx.fillStyle = g;
    ctx.fillRect(W / 2 - 60, 0, 120, H);
    ctx.fillStyle = `rgba(255,255,255,${0.25 * a * a})`;
    ctx.fillRect(0, 0, W, H);
    ctx.globalCompositeOperation = "source-over";
  }

  drawTouch(t);
  drawSpeedHUD(t, tf);
}

// ---------------------------------------------------------------- finale

const DUST = Array.from({ length: 80 }, (_, i) => ({
  x: rnd(i, 100) * W, y: rnd(i, 101) * H, r: 1 + Math.pow(rnd(i, 102), 3) * 9, v: 6 + rnd(i, 103) * 22, a: 0.03 + rnd(i, 104) * 0.1, red: rnd(i, 105) < 0.25,
}));

const LOGO = "strobe";
const LOGO_SIZE = 210;
function logoMetrics() {
  const letters = Array.from(LOGO);
  const ri = redIndex(LOGO);
  const fR = SG(500, LOGO_SIZE), fB = SG(700, LOGO_SIZE);
  const track = LOGO_SIZE * 0.035;
  const widths = letters.map((ch, i) => measure(i === ri ? fB : fR, ch));
  const xs = [];
  xs[ri] = -widths[ri] / 2;
  for (let i = ri - 1; i >= 0; i--) xs[i] = xs[i + 1] - track - widths[i];
  for (let i = ri + 1; i < letters.length; i++) xs[i] = xs[i - 1] + widths[i - 1] + track;
  const center = (xs[0] + xs[letters.length - 1] + widths[letters.length - 1]) / 2;
  return { letters, ri, fR, fB, xs, center };
}

function drawLogo(c, t, cx, cy, s) {
  const { letters, ri, fR, fB, xs } = logoMetrics();
  c.save();
  c.translate(cx, cy);
  c.scale(s, s);
  letters.forEach((ch, i) => {
    const d = Math.abs(i - ri);
    if (d === 0) {
      drawSprite(c, textSprite(fB, 0, ch, rgba(ACCENT, 1)), xs[i], LOGO_SIZE * 0.26);
      return;
    }
    const u = range(t, T.logo + (d - 1) * 0.06, T.logo + (d - 1) * 0.06 + 0.9);
    const e = easeOutExpo(u);
    const dir = i < ri ? -1 : 1;
    drawSprite(c, textSprite(fR, 0, ch, "rgb(242,242,246)"), xs[i] + dir * (1 - e) * (40 + 70 * d), LOGO_SIZE * 0.26, clamp(u * 3));
  });
  c.restore();
}

function drawFinale(t, tf) {
  const zoom = 1 + 0.04 * smooth(range(t, T.cut, T.end));
  ctx.setTransform(zoom, 0, 0, zoom, (W / 2) * (1 - zoom), (H / 2) * (1 - zoom));

  const u0 = t - T.cut;
  const logoMove = easeInOutCubic(range(t, T.logo + 0.9, T.logo + 1.8));
  const cy = lerp(H / 2, LAYOUT.finale.logo, logoMove);
  const ls = lerp(1, 0.86, logoMove);
  const lx = W / 2 - logoMetrics().center * ls * logoMove;

  // Ambient glow and dust.
  const amb = range(t, T.logo - 0.2, T.logo + 1.5);
  if (amb > 0) {
    const g = ctx.createRadialGradient(W / 2, cy, 0, W / 2, cy, 900);
    g.addColorStop(0, rgba([60, 12, 10], 0.55 * amb));
    g.addColorStop(1, rgba([5, 5, 5], 0));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
  }
  const dustA = range(t, T.cut + 0.6, T.logo + 1);
  for (const d of DUST) {
    const y = ((d.y - d.v * t) % H + H) % H;
    const x = d.x + Math.sin(t * 0.5 + d.y) * 20;
    const g = ctx.createRadialGradient(x, y, 0, x, y, d.r * 2);
    g.addColorStop(0, rgba(d.red ? RED : [255, 240, 225], d.a * dustA));
    g.addColorStop(1, rgba(d.red ? RED : [255, 240, 225], 0));
    ctx.fillStyle = g;
    ctx.fillRect(x - d.r * 2, y - d.r * 2, d.r * 4, d.r * 4);
  }

  // The line: flickers on out of the collapse, then shortens into the icon's mark.
  let lineA;
  if (u0 < 0.4) {
    const on = hash32(Math.floor(u0 * 38) + 5) > 0.35 ? 1 : 0.15;
    lineA = lerp(1.6, 0.9, u0 / 0.4) * on;
  } else lineA = 0.9;
  const shrink = easeInOutCubic(range(t, T.logo, T.logo + 0.9));
  const half = lerp(LAYOUT.guide, LOGO_SIZE * 0.66, shrink) * (shrink > 0 ? ls : 1);
  const lineY = shrink > 0 ? cy : H / 2;
  if (u0 < 0.12) {
    ctx.fillStyle = rgba([255, 210, 200], 1 - u0 / 0.12);
    ctx.fillRect(W / 2 - 14, 0, 28, H);
  }

  // Tagline, one word at a time on the line.
  const tag = entryAt(TAGLINE, tf);
  if (tag && tf < T.logo) {
    const word = sprite("tagline|" + tag.e.text, [-460, -160, 460, 130], (c) =>
      drawAnchored(c, tag.e.text, 0, 0, 156, { color: "#fff", anchorColor: rgba(RED, 1) }));
    drawSprite(ctx, word, W / 2, H / 2);
  }

  // Logo with a light sweep.
  if (t >= T.logo) {
    lctx.setTransform(1, 0, 0, 1, 0, 0);
    lctx.clearRect(0, 0, W, H);
    lctx.globalCompositeOperation = "source-over";
    drawLogo(lctx, t, lx, cy, ls);
    const sw = range(t, T.logo + 2.3, T.logo + 3.4);
    if (sw > 0 && sw < 1) {
      const sx = lerp(lx - 700, lx + 700, easeInOutCubic(sw));
      const g = lctx.createLinearGradient(sx - 160, 0, sx + 160, 0);
      g.addColorStop(0, "rgba(255,255,255,0)");
      g.addColorStop(0.5, "rgba(255,255,255,0.85)");
      g.addColorStop(1, "rgba(255,255,255,0)");
      lctx.globalCompositeOperation = "source-atop";
      lctx.setTransform(1, 0, 0, 1, 0, 0);
      lctx.fillStyle = g;
      lctx.fillRect(0, 0, W, H);
      lctx.globalCompositeOperation = "source-over";
    }
    const hit = Math.exp(-(t - T.logo) * 4);
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    const rg = ctx.createRadialGradient(lx, cy, 0, lx, cy, 380 * ls);
    rg.addColorStop(0, rgba(RED, 0.22 + 0.4 * hit));
    rg.addColorStop(1, rgba(RED, 0));
    ctx.fillStyle = rg;
    ctx.fillRect(lx - 400, cy - 400, 800, 800);
    const ru = range(t, T.logo, T.logo + 1.1);
    if (ru < 1) {
      ctx.strokeStyle = rgba([255, 150, 130], 0.5 * (1 - ru));
      ctx.lineWidth = 3 * (1 - ru) + 0.5;
      ctx.beginPath();
      ctx.ellipse(lx, cy, 60 + 1100 * easeOutCubic(ru), (60 + 1100 * easeOutCubic(ru)) * 0.55, 0, 0, TAU);
      ctx.stroke();
    }
    ctx.restore();
    ctx.drawImage(logoLayer, 0, 0);
  }

  // Line drawn over the letters, translucent, like the icon.
  {
    const top = lineY - half, bot = lineY + half;
    const g = ctx.createLinearGradient(0, top, 0, bot);
    const core = shrink > 0 ? lerp(0.4, 0.5, shrink) : 0.4;
    g.addColorStop(0, rgba([255, 120, 110], shrink > 0.5 ? core : 0));
    g.addColorStop(0.35, rgba([255, 120, 110], core * lineA));
    g.addColorStop(0.65, rgba([255, 120, 110], core * lineA));
    g.addColorStop(1, rgba([255, 120, 110], shrink > 0.5 ? core : 0));
    ctx.fillStyle = g;
    const lw = lerp(2.5, 5 * ls, shrink);
    ctx.fillRect(lx - lw / 2, top, lw, bot - top);
  }

  // Tagline and call to action under the logo.
  if (t > T.logo + 1.0) {
    const { tagline, stores, url, scale: k } = LAYOUT.finale;
    const f = FR(500, 58 * k);
    const totalW = measure(f, "Read more. Move less.");
    let text = "";
    const pieces = [["Read ", INK, 0], ["more", INK, 1], [".", RED, 1], [" Move ", INK, 2], ["less", INK, 3], [".", RED, 3]];
    for (const [s, col, wi] of pieces) {
      const x = W / 2 - totalW / 2 + measure(f, text);
      text += s;
      const u = range(t, T.logo + 1.15 + wi * 0.09, T.logo + 1.75 + wi * 0.09);
      drawSprite(ctx, textSprite(f, 0, s, rgba(col, 1)), x, tagline + (1 - easeOutCubic(u)) * 24 * k, u);
    }
    const u2 = range(t, T.logo + 1.7, T.logo + 2.3);
    drawSprite(ctx, textSprite(SG(400, 27 * k), 1.5 * k, "Free on iPhone, iPad, and Mac", "rgb(200,200,204)", "center"), W / 2, stores + (1 - easeOutCubic(u2)) * 16 * k, 0.8 * u2);
    const u3 = range(t, T.logo + 2.0, T.logo + 2.6);
    drawSprite(ctx, textSprite(JB(400, 21 * k), 3 * k, "strobefast.app", rgba(ACCENT, 1), "center"), W / 2, url + (1 - easeOutCubic(u3)) * 16 * k, 0.95 * u3);
  }

  ctx.setTransform(1, 0, 0, 1, 0, 0);
  const endFade = range(t, T.end - 0.7, T.end - 0.05);
  if (endFade > 0) {
    ctx.fillStyle = `rgba(0,0,0,${endFade})`;
    ctx.fillRect(0, 0, W, H);
  }
}

// ---------------------------------------------------------------- frame

function drawScene(t, tf) {
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.globalAlpha = 1;
  ctx.globalCompositeOperation = "source-over";
  ctx.filter = "none";
  ctx.fillStyle = "#050505";
  ctx.fillRect(0, 0, W, H);
  if (t < T.impact) drawOpening(t);
  else if (t < T.cut) drawReading(t, tf);
  else drawFinale(t, tf);
}

function fxAt(t) {
  const fx = { bloom: 0.45, threshold: 0.72, ca: 1.3, grain: 0.03, vignette: 0.5, saturation: 1, exposure: 1 };
  fx.bloom += 0.5 * range(t, T.collapse + 0.4, T.impact);
  if (t >= T.impact) {
    const imp = Math.exp(-(t - T.impact) * 6);
    fx.bloom += imp * 0.9;
    fx.ca += imp * 16;
  }
  const pz = range(t, T.pause, T.pause + 0.15) * (1 - range(t, T.resume - 0.05, T.resume + 0.1));
  fx.saturation = 1 - 0.75 * pz;
  fx.vignette += 0.2 * pz;
  fx.exposure -= 0.12 * pz;
  if (t >= T.library && t < T.climax) fx.bloom += 0.15 * pulse(t, T.library, T.climax);
  if (t >= T.climax && t < T.cut) {
    const p = pulse(t, T.climax, T.cut);
    fx.bloom += 0.25 + p * 0.5;
    fx.ca += 2 + p * 6 + 10 * easeInCubic(range(t, bar(15), T.cut));
    fx.bloom += 0.8 * easeInCubic(range(t, T.squeeze, T.cut));
  }
  if (t >= T.cut) {
    fx.bloom = 0.62 + 1.2 * Math.exp(-(t - T.cut) * 5);
    fx.ca = 1.2;
    fx.threshold = 0.66;
  }
  return fx;
}

function shutterAt(t) {
  if (t >= T.collapse && t < T.impact + 0.6) return 0.95;
  if (t >= T.chapter && t < T.cut) return 0.8;
  return 0.6;
}

function renderFrame(n, sub) {
  const tf = n / FPS;
  const sh = shutterAt(tf) / FPS;
  post.begin();
  for (let i = 0; i < sub; i++) {
    const t = Math.max(0, tf + ((i + 0.5) / sub - 0.5) * sh);
    drawScene(t, tf);
    post.add(sc, 1 / sub);
  }
  const fx = fxAt(tf);
  fx.seed = (n * 0.6180339) % 1;
  post.finish(fx);
}

window.renderAndSend = async (n, sub) => {
  renderFrame(n, sub);
  const px = post.readPixels();
  await fetch(`/frame?n=${n}`, { method: "POST", body: px });
};

window.renderStill = async (n, sub, name) => {
  renderFrame(n, sub);
  const blob = await new Promise((r) => out.toBlob(r, "image/png"));
  await fetch(`/still?name=${name}`, { method: "POST", body: blob });
};

await Promise.all([
  document.fonts.load(FR(400, 31)),
  document.fonts.load(FR(700, 31)),
  document.fonts.load(SG(500, 20)),
  document.fonts.load(SG(700, 20)),
  document.fonts.load(JB(400, 16)),
  document.fonts.load(JB(700, 16)),
]);
mcache.clear();
buildPage();
mapFixations();
layoutHeadlines();
prepareVortex();
buildCovers();
WORD_SCALE = fitWordScale();
window.ready = true;
