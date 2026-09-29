// Procedural score and sound design, rendered to out/audio.wav on the same grid as the picture.

import { BEAT, BAR, S16, bar, T, DURATION, SCHEDULE, TAGLINE, FIXATIONS, kicks, mulberry32 } from "./timeline.js";
import { join } from "node:path";

const SR = 48000;
const LEN = DURATION + 0.5;
const N = Math.ceil(LEN * SR);
const TAU = Math.PI * 2;
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, u) => a + (b - a) * u;
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const rng = mulberry32(2024);
const noise = () => rng() * 2 - 1;

function hash32(n) {
  n = Math.imul(n ^ (n >>> 16), 0x7feb352d);
  n = Math.imul(n ^ (n >>> 15), 0x846ca68b);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}

const bus = () => ({ L: new Float32Array(N), R: new Float32Array(N) });
const B = {
  drums: bus(), duck: bus(), music: bus(), fx: bus(),
  verbWarp: bus(), verbFx: bus(), delay: bus(),
};

function voice(t0, dur, pan, gen, outs) {
  const s0 = Math.round(t0 * SR);
  const n = Math.round(dur * SR);
  const gl = Math.cos(((pan + 1) * Math.PI) / 4);
  const gr = Math.sin(((pan + 1) * Math.PI) / 4);
  for (let i = 0; i < n; i++) {
    const idx = s0 + i;
    if (idx < 0) continue;
    if (idx >= N) break;
    const v = gen(i / SR, i);
    if (v === 0) continue;
    for (const [b, amt] of outs) {
      b.L[idx] += v * gl * amt;
      b.R[idx] += v * gr * amt;
    }
  }
}

function svf() {
  let ic1 = 0, ic2 = 0;
  return (x, fc, q = 0.707, mode = 0) => {
    const g = Math.tan((Math.PI * Math.min(Math.max(fc, 10), SR * 0.45)) / SR);
    const k = 1 / q;
    const a1 = 1 / (1 + g * (g + k));
    const a2 = g * a1;
    const a3 = g * a2;
    const v3 = x - ic2;
    const v1 = a1 * ic1 + a2 * v3;
    const v2 = ic2 + a2 * ic1 + a3 * v3;
    ic1 = 2 * v1 - ic1;
    ic2 = 2 * v2 - ic2;
    return mode === 0 ? v2 : mode === 1 ? v1 : x - k * v1 - v2;
  };
}

function polyblep(t, dt) {
  if (t < dt) {
    t /= dt;
    return t + t - t * t - 1;
  }
  if (t > 1 - dt) {
    t = (t - 1) / dt;
    return t * t + t + t + 1;
  }
  return 0;
}
function saw(phase0 = rng()) {
  let ph = phase0;
  return (f) => {
    const dt = f / SR;
    ph += dt;
    if (ph >= 1) ph -= 1;
    return 2 * ph - 1 - polyblep(ph, dt);
  };
}
function sine(phase0 = 0) {
  let ph = phase0;
  return (f) => {
    ph += f / SR;
    if (ph >= 1) ph -= 1;
    return Math.sin(TAU * ph);
  };
}

// ---------------------------------------------------------------- instruments

function kick(t0, amp = 1, big = false) {
  const o = sine();
  const dec = big ? 3.2 : 7;
  voice(t0, big ? 1.6 : 0.6, 0, (t) => {
    const f = (big ? 38 : 46) + (big ? 150 : 120) * Math.exp(-t * 30);
    const click = t < 0.004 ? noise() * (1 - t / 0.004) * 0.5 : 0;
    return (Math.tanh(o(f) * 2.2) * Math.exp(-t * dec) + click) * amp;
  }, [[B.drums, 1]]);
}

function clap(t0, amp = 1) {
  const f = svf();
  voice(t0, 0.5, 0.05, (t) => {
    let env = Math.exp(-t * 18);
    for (const d of [0, 0.011, 0.023]) if (t >= d && t < d + 0.01) env = Math.max(env, 1 - (t - d) / 0.01);
    return f(noise(), 1700, 1.2, 1) * env * amp * 1.6;
  }, [[B.drums, 1], [B.verbWarp, 0.35]]);
}

function snare(t0, amp = 1, pan = 0) {
  const f = svf();
  const o = sine();
  voice(t0, 0.3, pan, (t) => {
    const n = f(noise(), 3200, 0.8, 1) * Math.exp(-t * 22);
    const b = o(190 * (1 + 0.3 * Math.exp(-t * 40))) * Math.exp(-t * 30) * 0.6;
    return (n * 1.3 + b) * amp;
  }, [[B.drums, 1], [B.verbWarp, 0.25]]);
}

function hat(t0, amp = 1, open = false, pan = 0) {
  const f = svf();
  const dec = open ? 9 : 55;
  voice(t0, open ? 0.35 : 0.08, pan, (t) => f(noise(), 8200, 0.7, 2) * Math.exp(-t * dec) * amp, [[B.drums, 1]]);
}

function pluck(t0, midi, amp = 1, pan = 0, dec = 9, outs = null) {
  const fr = mtof(midi);
  voice(t0, 1.2, pan, (t) => {
    const idx = 2.2 * Math.exp(-t * 20);
    const v = Math.sin(TAU * (fr * t) + idx * Math.sin(TAU * fr * 2 * t));
    const att = Math.min(1, t / 0.002);
    return v * att * Math.exp(-t * dec) * amp;
  }, outs ?? [[B.music, 1], [B.delay, 0.35], [B.verbWarp, 0.3]]);
}

function bell(t0, midi, amp = 1, pan = 0, dur = 4, outs = null) {
  const fr = mtof(midi);
  voice(t0, dur, pan, (t) => {
    const idx = 3.0 * Math.exp(-t * 3);
    const v = Math.sin(TAU * fr * t + idx * Math.sin(TAU * fr * 3.5 * t)) * 0.7 + Math.sin(TAU * fr * 2 * t) * 0.15 * Math.exp(-t * 2);
    return v * Math.min(1, t / 0.004) * Math.exp(-t * (4 / dur) * 1.2) * amp;
  }, outs ?? [[B.fx, 1], [B.verbFx, 0.6]]);
}

function pad(t0, dur, notes, amp, cutoff = 1400, outBus = B.duck, attack = 0.35, release = 0.9) {
  const oscs = notes.flatMap((m) => [-7, 0, 7].map((cents) => ({ o: saw(), f: mtof(m) * Math.pow(2, cents / 1200) })));
  const fL = svf();
  voice(t0, dur + release, 0, (t) => {
    let s = 0;
    for (const x of oscs) s += x.o(x.f);
    s /= oscs.length;
    const env = Math.min(1, t / attack) * (t > dur ? Math.exp(-(t - dur) * (4 / release)) : 1);
    const fc = cutoff * (1 + 0.25 * Math.sin(t * 1.3));
    return fL(s, fc, 0.8) * env * amp;
  }, [[outBus, 1], [B.verbWarp, 0.35]]);
}

function supersaw(t0, dur, notes, amp, cutoff0, cutoff1) {
  const oscs = notes.flatMap((m) => [-19, -11, -5, 0, 6, 12, 20].map((c) => ({ o: saw(), f: mtof(m) * Math.pow(2, c / 1200) })));
  const fL = svf(), fR = svf();
  const s0 = Math.round(t0 * SR);
  const n = Math.round((dur + 0.3) * SR);
  for (let i = 0; i < n; i++) {
    const idx = s0 + i;
    if (idx >= N) break;
    const t = i / SR;
    let l = 0, r = 0;
    oscs.forEach((x, k) => {
      const v = x.o(x.f);
      if (k % 2) l += v; else r += v;
    });
    const env = Math.min(1, t / 0.02) * (t > dur ? Math.exp(-(t - dur) * 14) : 1);
    const fc = lerp(cutoff0, cutoff1, clamp(t / dur));
    const g = (amp * env) / oscs.length * 2;
    B.duck.L[idx] += fL(l, fc, 0.9) * g;
    B.duck.R[idx] += fR(r, fc, 0.9) * g;
  }
}

function bassNote(t0, dur, midi, amp, cutoff = 700) {
  const o1 = saw(), o2 = saw(), sub = sine();
  const f = svf();
  const fr = mtof(midi);
  voice(t0, dur + 0.05, 0, (t) => {
    const env = Math.min(1, t / 0.004) * (t > dur ? Math.max(0, 1 - (t - dur) / 0.05) : 1) * Math.exp(-t * 2);
    const fc = cutoff * (1 + 3 * Math.exp(-t * 18));
    const s = f((o1(fr) + o2(fr * 1.006)) * 0.5, fc, 1.1) + sub(fr) * 0.8;
    return Math.tanh(s * 1.4) * env * amp;
  }, [[B.duck, 1]]);
}

function noiseSweep(t0, dur, f0, f1, amp, shape = 2, outs = null, q = 1.4, pan = 0) {
  const f = svf();
  voice(t0, dur, pan, (t) => {
    const u = t / dur;
    const fc = f0 * Math.pow(f1 / f0, u);
    return f(noise(), fc, q, 1) * Math.pow(u, shape) * amp;
  }, outs ?? [[B.fx, 1], [B.verbFx, 0.4]]);
}

function toneSweep(t0, dur, f0, f1, amp, shape = 2, outs = null) {
  const o = sine();
  voice(t0, dur, 0, (t) => {
    const u = t / dur;
    return o(f0 * Math.pow(f1 / f0, u * u)) * Math.pow(u, shape) * amp;
  }, outs ?? [[B.fx, 1], [B.verbFx, 0.3]]);
}

function tick(t0, freq, amp, pan, outs = null) {
  const f = svf();
  const o = sine();
  voice(t0, 0.06, pan, (t) => (f(noise(), freq * 2.2, 2, 1) * Math.exp(-t * 400) * 1.5 + o(freq) * Math.exp(-t * 90)) * amp,
    outs ?? [[B.fx, 1], [B.verbFx, 0.3], [B.delay, 0.25]]);
}

function whoosh(t0, dur, amp, pan = 0, up = true) {
  const f = svf();
  voice(t0, dur, pan, (t) => {
    const u = t / dur;
    const env = Math.sin(Math.PI * u) ** 2;
    const fc = up ? lerp(400, 5000, u * u) : lerp(5000, 300, u);
    return f(noise(), fc, 2, 1) * env * amp;
  }, [[B.fx, 1], [B.verbFx, 0.5]]);
}

function boom(t0, amp, f0 = 62, f1 = 28, dur = 2.2) {
  const o = sine();
  voice(t0, dur, 0, (t) => {
    const f = f1 + (f0 - f1) * Math.exp(-t * 3);
    return Math.tanh(o(f) * 1.8) * Math.exp(-t * (3 / dur)) * Math.min(1, t / 0.003) * amp;
  }, [[B.fx, 1]]);
}

function crash(t0, amp, dur = 2.4, outs = null) {
  const f = svf(), g = svf();
  voice(t0, dur, 0, (t) => {
    const x = noise();
    return (f(x, 6000, 0.6, 2) * 0.8 + g(x, 3000, 3, 1) * 0.4) * Math.exp(-t * (4 / dur)) * amp;
  }, outs ?? [[B.fx, 1], [B.verbFx, 0.5]]);
}

function shatter(t0, amp) {
  const r = mulberry32(99);
  for (let k = 0; k < 70; k++) {
    const dt = Math.pow(r(), 1.8) * 0.7;
    const fr = 2200 + r() * 6500;
    const a = amp * (0.25 + r() * 0.75) * Math.exp(-dt * 3);
    const pan = r() * 2 - 1;
    voice(t0 + dt, 0.25, pan, (t) => Math.sin(TAU * fr * t) * Math.exp(-t * 30) * a, [[B.fx, 1], [B.verbFx, 0.5]]);
  }
  const f = svf();
  voice(t0, 0.6, 0, (t) => f(noise(), 5000, 0.7, 2) * Math.exp(-t * 9) * amp * 0.8, [[B.fx, 1], [B.verbFx, 0.4]]);
}

// ---------------------------------------------------------------- harmony

const CHORDS = {
  Am: { root: 33, notes: [45, 52, 55, 59, 60, 64], tones: [69, 72, 76, 79, 83] },
  F: { root: 29, notes: [41, 48, 52, 55, 57, 64], tones: [65, 69, 72, 76, 79] },
  C: { root: 36, notes: [48, 55, 60, 62, 64], tones: [67, 72, 74, 76, 79] },
  G: { root: 31, notes: [43, 50, 55, 59, 64], tones: [67, 71, 74, 79, 83] },
};
const PROG = ["Am", "F", "C", "G"];
const chordAt = (t) => CHORDS[PROG[((Math.floor(t / BAR) - 5) % 4 + 4) % 4]];

// ---------------------------------------------------------------- score

// Opening: drone, air, and the eye's saccades.
{
  const oscs = [33, 40, 45, 52].map((m) => [saw(), saw(), mtof(m)]);
  const f = svf();
  voice(0, T.impact + 0.2, 0, (t) => {
    let s = 0;
    for (const [a, b, fr] of oscs) s += a(fr * 0.997) + b(fr * 1.003);
    s /= oscs.length * 2;
    const fc = lerp(160, 1400, clamp(t / T.impact) ** 2) * (1 + 0.15 * Math.sin(t * 0.7));
    const env = Math.min(1, t / 1.5) * (t > T.singularity ? Math.max(0, 1 - (t - T.singularity) / 0.35) : 1);
    return f(s, fc, 0.9) * env * 0.5;
  }, [[B.fx, 1], [B.verbFx, 0.4]]);
  const air = svf();
  voice(0, T.impact, 0, (t) => air(noise(), 2500, 0.5, 1) * 0.03 * Math.min(1, t / 1) * (1 - clamp((t - T.singularity) / 0.3)), [[B.fx, 1]]);
}
FIXATIONS.forEach((f, i) => {
  if (i === 0) return;
  const reg = f.type === "regress";
  const u = f.start / T.collapse;
  tick(f.start - 0.01, reg ? 1250 : 1900 + 400 * u, 0.22 + 0.12 * u, f.pan * 0.7);
});
for (let b = 2 * 4; b < 16; b++) {
  const t0 = b * BEAT;
  const o = sine();
  voice(t0, 0.5, 0, (t) => o(52 + 40 * Math.exp(-t * 25)) * Math.exp(-t * 9) * (0.25 + 0.25 * (b / 16)), [[B.fx, 1]]);
}
whoosh(T.headline1 - 0.15, 0.9, 0.25, -0.4);
whoosh(T.headline2 - 0.4, 0.5, 0.2, 0.4, false);
whoosh(T.headline2 - 0.1, 0.9, 0.25, -0.2);

// Collapse: suction, silence, four converging rings, impact.
noiseSweep(T.collapse, T.singularity - T.collapse + 0.1, 250, 7000, 0.7, 2.2, null, 2.5);
toneSweep(T.collapse, T.singularity - T.collapse + 0.1, 70, 900, 0.22, 2.5);
for (let k = 1; k <= 3; k++) tick(T.singularity + k * S16, 1200 * Math.pow(1.5, k), 0.5, 0, [[B.fx, 1], [B.verbFx, 0.6]]);
{
  // Reverse swell into the hit.
  const f = svf();
  const d = BEAT;
  voice(T.impact - d, d, 0, (t) => f(noise(), 1500 + 6000 * (t / d) ** 3, 0.8, 1) * (t / d) ** 4 * 0.9, [[B.fx, 1]]);
}
boom(T.impact, 1.0, 70, 30, 3.0);
kick(T.impact, 1.0, true);
crash(T.impact, 0.28, 2.0);
pad(T.impact, BAR * 2 - 0.4, [33, 45, 52, 57, 60, 64], 0.5, 900, B.fx, 0.01, 2.5);

// Reading: pads, the word melody, a gentle beat that grows.
for (let b = 5; b <= 15; b++) {
  const t0 = bar(b);
  const ch = chordAt(t0 + 0.01);
  if (b >= 9 && b < 13) continue;
  const amp = b < 13 ? 0.22 : 0;
  if (amp) pad(t0, BAR, ch.notes, amp, b < 7 ? 1100 : 1600, B.duck, 0.3, 0.6);
}
for (const e of SCHEDULE) {
  if (e.kind === "gap" || e.start >= T.cut) continue;
  const ch = chordAt(e.start + 0.001);
  const i = Math.round(e.start / S16 * 2);
  if (e.start < T.library) {
    const end = /[.?!]$/.test(e.text);
    const m = end ? ch.tones[0] - 12 : ch.tones[Math.floor(hash32(i) * ch.tones.length)];
    pluck(e.start, m, end ? 0.26 : 0.18, (hash32(i + 3) - 0.5) * 0.6, end ? 5 : 11);
  } else if (e.start < T.climax) {
    if (e.kind === "chapter") continue;
    const m = ch.tones[Math.floor(hash32(i) * ch.tones.length)] + 12;
    pluck(e.start, m, 0.09, (hash32(i + 3) - 0.5) * 0.8, 16);
  } else {
    tick(e.start, 3000 + hash32(i) * 3000, 0.07, (hash32(i + 5) - 0.5) * 1.2, [[B.music, 1], [B.delay, 0.15]]);
  }
}
for (let b = 5; b < 9; b++) {
  const t0 = bar(b);
  const beats = b < 7 ? [0, 2] : [0, 1, 2, 3];
  for (const k of beats) kick(t0 + k * BEAT, b < 7 ? 0.45 : 0.6);
  if (b >= 7) for (let s = 0; s < 16; s++) hat(t0 + s * S16, s % 2 ? 0.05 : 0.09, false, 0.3);
  if (b >= 7) {
    const ch = chordAt(t0 + 0.01);
    for (let s = 0; s < 8; s++) bassNote(t0 + s * (BEAT / 2), BEAT / 2 - 0.02, ch.root + (s % 2 ? 12 : 0), 0.22, 500);
  }
}
noiseSweep(bar(8) + BEAT * 2, BEAT * 2, 400, 9000, 0.35, 3);
snare(bar(8) + BEAT * 3, 0.3); snare(bar(8) + BEAT * 3 + S16 * 2, 0.35); snare(bar(8) + BEAT * 3 + S16 * 3, 0.4);

// Library: full groove.
for (let b = 9; b < 13; b++) {
  const t0 = bar(b);
  const ch = chordAt(t0 + 0.01);
  for (let k = 0; k < 4; k++) {
    kick(t0 + k * BEAT, 0.85);
    if (k % 2) clap(t0 + k * BEAT, 0.5);
    hat(t0 + k * BEAT + BEAT / 2, 0.14, true, -0.2);
  }
  for (let s = 0; s < 16; s++) hat(t0 + s * S16, s % 4 === 2 ? 0.09 : 0.05, false, 0.35);
  for (let s = 0; s < 8; s++) bassNote(t0 + s * (BEAT / 2), BEAT / 2 - 0.02, ch.root + (s % 2 ? 12 : 0), 0.34, 650 + b * 40);
  pad(t0, BAR, ch.notes, 0.16, 2200, B.duck, 0.05, 0.4);
  for (let s = 0; s < 16; s++) {
    const m = ch.tones[(s * 3) % ch.tones.length] + (s % 8 >= 4 ? 12 : 0);
    pluck(t0 + s * S16, m, 0.07, s % 2 ? 0.5 : -0.5, 14, [[B.duck, 1], [B.delay, 0.3]]);
  }
}
for (const [w, m] of [["Books.", 45], ["Papers.", 48], ["Articles.", 52]]) {
  const e = SCHEDULE.find((x) => x.text === w);
  bell(e.start, m + 24, 0.18, 0, 2.0, [[B.music, 1], [B.verbWarp, 0.5]]);
  supersaw(e.start, 0.18, CHORDS.Am.notes.map((n) => n + 12), 0.35, 4000, 1500);
}
{
  // Touch down on "Hold" and lift off on "pause.".
  const o = sine();
  voice(T.hold, 0.25, 0.4, (t) => o(140 - 60 * t) * Math.exp(-t * 18) * 0.35, [[B.fx, 1], [B.verbFx, 0.2]]);
  const o2 = sine();
  voice(T.pause, 0.2, 0.4, (t) => o2(300 + 900 * t) * Math.exp(-t * 20) * 0.25, [[B.fx, 1], [B.verbFx, 0.3]]);
}
// The paused beat: room tone, a held low note.
{
  const f = svf();
  const o = sine();
  voice(T.pause + 0.15, T.resume - T.pause - 0.1, 0, (t) => {
    const d = T.resume - T.pause - 0.1;
    const env = Math.min(1, t / 0.1) * Math.min(1, (d - t) / 0.08);
    return (f(noise(), 900, 0.6, 0) * 0.08 + o(mtof(45)) * 0.1 + (rng() < 0.0008 ? noise() * 0.6 : 0)) * env;
  }, [[B.fx, 1], [B.verbFx, 0.3]]);
  tick(T.pause, 700, 0.3, 0);
}
// Slide for speed: a rising sweep under the drag.
toneSweep(T.resume + 0.1, BEAT * 2 - 0.1, 200, 1600, 0.12, 1.2);
noiseSweep(T.resume, BEAT * 2, 600, 6000, 0.25, 1.5);
// Chapter stinger and the build.
bell(T.chapter, 69, 0.22, -0.2, 3);
bell(T.chapter + 0.005, 76, 0.14, 0.2, 3);
{
  const b12 = bar(12);
  for (let k = 0; k < 8; k++) snare(b12 + BEAT * 2 + k * S16, 0.18 + k * 0.03, (k % 2 ? 0.2 : -0.2));
  for (let k = 0; k < 8; k++) snare(b12 + BEAT * 2 + k * S16 + S16 / 2, 0.15 + k * 0.03, 0);
  noiseSweep(b12, BAR, 300, 12000, 0.55, 3.2);
  toneSweep(b12 + BEAT, BAR - BEAT, 110, 1760, 0.12, 3);
}

// Climax.
shatter(T.climax, 0.5);
crash(T.climax, 0.32, 2.2);
boom(T.climax, 0.7, 80, 34, 1.5);
for (const k of kicks()) if (k >= T.climax && k < T.cut) kick(k, k >= bar(15) + BEAT * 2 ? 0.75 : 1.0);
for (let b = 13; b < 16; b++) {
  const t0 = bar(b);
  const ch = chordAt(t0 + 0.01);
  if (b < 15) for (const k of [1, 3]) clap(t0 + k * BEAT, 0.6);
  for (let s = 0; s < 16; s++) hat(t0 + s * S16, s % 2 ? 0.07 : 0.12, false, 0.3);
  for (let k = 0; k < 4; k++) hat(t0 + k * BEAT + BEAT / 2, 0.16, true, -0.3);
  for (let s = 0; s < 16; s++) bassNote(t0 + s * S16, S16 - 0.01, ch.root + (s % 4 === 3 ? 12 : 0), 0.38, 900);
  for (let h = 0; h < 2; h++) supersaw(t0 + h * BAR / 2, BAR / 2 - 0.02, ch.notes.map((n) => n + 12), 0.5, 1800 + b * 300, 5000);
  for (let s = 0; s < 16; s++) {
    const m = ch.tones[(s * 2 + (s >> 2)) % ch.tones.length] + 12;
    pluck(t0 + s * S16, m, 0.06, s % 2 ? 0.6 : -0.6, 18, [[B.duck, 1], [B.delay, 0.3]]);
  }
  if (b === 14) crash(t0, 0.2, 1.6);
}
{
  const b15 = bar(15);
  noiseSweep(b15, BAR, 500, 14000, 0.6, 2.6);
  toneSweep(b15, BAR, 220, 3520, 0.14, 2.5);
  for (let k = 0; k < 16; k++) snare(b15 + BEAT * 2 + k * (BEAT * 2 / 16), 0.15 + k * 0.025, k % 2 ? 0.25 : -0.25);
  // The collapse into the line: a falling zap.
  const o = sine();
  voice(T.squeeze, T.cut - T.squeeze, 0, (t) => {
    const u = t / (T.cut - T.squeeze);
    return o(3000 * Math.pow(60 / 3000, u)) * 0.2 * (0.4 + 0.6 * u);
  }, [[B.fx, 1]]);
}

// ---------------------------------------------------------------- mix

function sidechain() {
  const env = new Float32Array(N);
  const ks = kicks().concat([T.impact]);
  for (let i = 0; i < N; i++) env[i] = 1;
  for (const k of ks) {
    const s0 = Math.round(k * SR);
    for (let i = 0; i < SR * 0.4 && s0 + i < N; i++) {
      const t = i / SR;
      const d = 1 - 0.75 * Math.exp(-t * 9) * Math.min(1, t / 0.003 + 0.3);
      env[s0 + i] = Math.min(env[s0 + i], d);
    }
  }
  return env;
}

function freeverb(src, room = 0.86, damp = 0.25, wet = 1) {
  const scale = SR / 44100;
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  const aps = [556, 441, 341, 225];
  const outL = new Float32Array(N), outR = new Float32Array(N);
  for (const [ch, spread, out] of [[src.L, 0, outL], [src.R, 23, outR]]) {
    const cs = combs.map((d) => ({ buf: new Float32Array(Math.round((d + spread) * scale)), i: 0, f: 0 }));
    const as = aps.map((d) => ({ buf: new Float32Array(Math.round((d + spread) * scale)), i: 0 }));
    for (let n = 0; n < N; n++) {
      const x = ch[n] * 0.015;
      let s = 0;
      for (const c of cs) {
        const y = c.buf[c.i];
        c.f = y * (1 - damp) + c.f * damp;
        c.buf[c.i] = x + c.f * room;
        c.i = (c.i + 1) % c.buf.length;
        s += y;
      }
      for (const a of as) {
        const b = a.buf[a.i];
        const y = -s + b;
        a.buf[a.i] = s + b * 0.5;
        a.i = (a.i + 1) % a.buf.length;
        s = y;
      }
      out[n] = s * wet;
    }
  }
  return { L: outL, R: outR };
}

function pingpong(src, time, fb, wet) {
  const d = Math.round(time * SR);
  const L = new Float32Array(N), R = new Float32Array(N);
  const fl = svf(), fr = svf();
  for (let n = 0; n < N; n++) {
    const dl = n >= d ? L[n - d] : 0;
    const dr = n >= d ? R[n - d] : 0;
    L[n] = src.L[n] + src.R[n] * 0.5 + fl(dr, 3500) * fb;
    R[n] = fr(dl, 3500) * fb;
  }
  for (let n = 0; n < N; n++) {
    L[n] = (L[n] - src.L[n] - src.R[n] * 0.5) * wet;
    R[n] *= wet;
  }
  return { L, R };
}

// Tape stop on the pause and tape start on the resume, applied to the music.
const STOP = 0.32, START = 0.14;
function readPos(t) {
  const p = T.pause, r = T.resume;
  if (t < p) return [t, 1];
  if (t < p + STOP) {
    const d = t - p;
    return [p + d - (d * d) / (2 * STOP), 1 - d / STOP];
  }
  if (t < r) return [p + STOP / 2, 0];
  if (t < r + START) {
    const d = t - r;
    return [r + START / 2 + (d * d) / (2 * START), d / START];
  }
  return [t, 1];
}
function warp(src) {
  const L = new Float32Array(N), R = new Float32Array(N);
  for (let n = 0; n < N; n++) {
    const [pos, speed] = readPos(n / SR);
    const x = pos * SR;
    const i0 = Math.floor(x), f = x - i0;
    if (i0 + 1 >= N || i0 < 0) continue;
    const g = clamp(speed * 3);
    L[n] = (src.L[i0] * (1 - f) + src.L[i0 + 1] * f) * g;
    R[n] = (src.R[i0] * (1 - f) + src.R[i0 + 1] * f) * g;
  }
  return { L, R };
}

console.log("mixing");
const sc = sidechain();
const delayed = pingpong(B.delay, BEAT * 0.75, 0.42, 0.5);
const verbW = freeverb(B.verbWarp, 0.84, 0.3, 1);
const verbF = freeverb(B.verbFx, 0.9, 0.2, 1.2);
const group = { L: new Float32Array(N), R: new Float32Array(N) };
for (let n = 0; n < N; n++) {
  group.L[n] = B.drums.L[n] * 0.9 + B.duck.L[n] * sc[n] + B.music.L[n] + delayed.L[n] + verbW.L[n];
  group.R[n] = B.drums.R[n] * 0.9 + B.duck.R[n] * sc[n] + B.music.R[n] + delayed.R[n] + verbW.R[n];
}
const warped = warp(group);
const L = new Float32Array(N), R = new Float32Array(N);
const cutS = Math.round(T.cut * SR);
const hpL = svf(), hpR = svf();
for (let n = 0; n < N; n++) {
  let l = warped.L[n] + B.fx.L[n] + verbF.L[n];
  let r = warped.R[n] + B.fx.R[n] + verbF.R[n];
  l = hpL(l, 28, 0.7, 2);
  r = hpR(r, 28, 0.7, 2);
  L[n] = l;
  R[n] = r;
}
// Hard cut to silence at the collapse: only sound started after it survives.
{
  const fade = Math.round(0.004 * SR);
  for (let n = cutS - fade; n < N; n++) {
    const g = n < cutS ? (cutS - n) / fade : 0;
    L[n] *= g;
    R[n] *= g;
  }
}
// Finale, mixed on its own after the cut: the line flickers on, the tagline chimes,
// and the logo lands on a chord.
{
  const finaleFx = bus(), finaleVerb = bus();
  const saveFx = B.fx, saveVerb = B.verbFx;
  B.fx = finaleFx;
  B.verbFx = finaleVerb;
  {
    const f = svf();
    let ph = 0;
    voice(T.cut, 0.45, 0, (t) => {
      const on = hash32(Math.floor(t * 38) + 5) > 0.35 ? 1 : 0.1;
      ph += 100 / SR;
      const sq = (ph % 1) < 0.5 ? 1 : -1;
      return f(sq, 2400, 0.7, 0) * on * 0.06 * (1 - t / 0.45);
    }, [[B.fx, 1]]);
    tick(T.cut + 0.01, 4000, 0.3, 0, [[B.fx, 1], [B.verbFx, 0.9]]);
  }
  [76, 79, 74, 72].forEach((m, i) => {
    bell(TAGLINE[i].start, m, 0.3, (i - 1.5) * 0.15, 3.2);
    bell(TAGLINE[i].start, m - 12, 0.1, 0, 2.5);
  });
  const cmaj9 = [36, 48, 55, 59, 62, 64, 67];
  pad(T.logo, T.end - T.logo - 1.2, cmaj9, 0.4, 1800, B.fx, 0.02, 2.0);
  boom(T.logo, 0.55, 60, 30, 3);
  bell(T.logo, 76, 0.35, 0, 5);
  bell(T.logo, 88, 0.1, 0.3, 4);
  noiseSweep(T.logo - BEAT, BEAT, 800, 6000, 0.12, 3);
  [88, 91, 95, 100].forEach((m, i) => bell(T.logo + 2.3 + i * 0.09, m, 0.05, -0.5 + i * 0.33, 2));
  const v = freeverb(finaleVerb, 0.9, 0.35, 0.9);
  for (let n = cutS; n < N; n++) {
    L[n] += finaleFx.L[n] + v.L[n];
    R[n] += finaleFx.R[n] + v.R[n];
  }
  B.fx = saveFx;
  B.verbFx = saveVerb;
}

// Master: gentle glue, soft clip, fade, normalize.
let peak = 0;
for (let n = 0; n < N; n++) {
  const t = n / SR;
  const fade = 1 - clamp((t - (T.end - 0.6)) / 0.6);
  L[n] = Math.tanh(L[n] * 1.2) * fade;
  R[n] = Math.tanh(R[n] * 1.2) * fade;
  peak = Math.max(peak, Math.abs(L[n]), Math.abs(R[n]));
}
// AAC overshoots sample peaks by about a decibel; this keeps the muxed file under -1 dBTP.
const gain = 0.8 / peak;
const pcm = Buffer.alloc(44 + N * 4);
pcm.write("RIFF", 0);
pcm.writeUInt32LE(36 + N * 4, 4);
pcm.write("WAVE", 8);
pcm.write("fmt ", 12);
pcm.writeUInt32LE(16, 16);
pcm.writeUInt16LE(1, 20);
pcm.writeUInt16LE(2, 22);
pcm.writeUInt32LE(SR, 24);
pcm.writeUInt32LE(SR * 4, 28);
pcm.writeUInt16LE(4, 32);
pcm.writeUInt16LE(16, 34);
pcm.write("data", 36);
pcm.writeUInt32LE(N * 4, 40);
for (let n = 0; n < N; n++) {
  pcm.writeInt16LE(Math.round(clamp(L[n] * gain, -1, 1) * 32767), 44 + n * 4);
  pcm.writeInt16LE(Math.round(clamp(R[n] * gain, -1, 1) * 32767), 46 + n * 4);
}
await Bun.write(join(import.meta.dir, "out", "audio.wav"), pcm);
console.log("wrote out/audio.wav, peak", peak.toFixed(3));
