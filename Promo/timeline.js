// Shared by the frame renderer (browser) and the synthesizer (Bun), so picture and
// sound land on the same grid.

export const W = 1920;
export const H = 1080;
export const FPS = 30;

export const BPM = 125;
export const BEAT = 60 / BPM;
export const BAR = BEAT * 4;
export const S16 = BEAT / 4;
export const S32 = BEAT / 8;
export const bar = (n) => n * BAR;

export const DURATION = 38;

export const T = {
  page: 0,
  headline1: 0.4,
  headline2: 3.84,
  collapse: bar(4),
  singularity: bar(4) + BEAT * 3,
  impact: bar(5),
  rsvp: bar(5),
  library: bar(9),
  hold: bar(10),
  pause: bar(11),
  resume: bar(11) + BEAT * 2,
  chapter: bar(12),
  climax: bar(13),
  squeeze: bar(16) - BEAT,
  cut: bar(16),
  tagline: bar(16) + BEAT,
  logo: bar(16) + BEAT * 5,
  end: DURATION,
};

export const MOBY_OPENING =
  "Call me Ishmael. Some years ago—never mind how long precisely—having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world. It is a way I have of driving off the spleen and regulating the circulation. Whenever I find myself growing grim about the mouth; whenever it is a damp, drizzly November in my soul; whenever I find myself involuntarily pausing before coffin warehouses, and bringing up the rear of every funeral I meet; and especially whenever my hypos get such an upper hand of me, that it requires a strong moral principle to prevent me from deliberately stepping into the street, and methodically knocking people’s hats off—then, I account it high time to get to sea as soon as I can. This is my substitute for pistol and ball. With a philosophical flourish Cato throws himself upon his sword; I quietly take to the ship. There is nothing surprising in this. If they but knew it, almost all men in their degree, some time or other, cherish very nearly the same feelings towards the ocean with me.";

/// Splits like the app's tokenizer: whitespace, plus em dashes kept on the first word.
export function tokenize(text) {
  const out = [];
  for (const raw of text.split(/\s+/)) {
    if (!raw) continue;
    const parts = raw.split(/(?<=—)/);
    for (const p of parts) if (p) out.push(p);
  }
  return out;
}

/// The chapter read from the announcement to the cut: "The Symphony".
const CHAPTER = 132;
const CHAPTER_OPENING =
  "It was a clear steel-blue day. The firmaments of air and sea were hardly separable in that all-pervading azure; only, the pensive air was transparently pure and soft, with a woman’s look, and the robust and man-like sea heaved with long, strong, lingering swells, as Samson’s chest in his sleep. Hither, and thither, on high, glided the snow-white wings of small, unspeckled birds; these were the gentle thoughts of the feminine air; but to and fro in the deeps, far down in the bottomless blue, rushed mighty leviathans, sword-fish, and sharks; and these were the strong, troubled, murderous thinkings of the masculine sea.";

const CHAPTER_WORDS = tokenize(CHAPTER_OPENING);

/// The words shown at the fixation point, from the impact to the cut.
/// Each entry: { text, start, end, kind } where kind is "word", "chapter" or "gap".
function buildSchedule() {
  const list = [];
  let t = T.rsvp;
  const push = (text, sixteenths, kind = "word") => {
    const d = sixteenths * S16;
    list.push({ text, start: t, end: t + d, kind });
    t += d;
  };
  const line = (spec) => {
    for (const [text, n] of spec) push(text, n, text === null ? "gap" : "word");
  };

  // Bar 5–6: eighth notes, 250 wpm.
  line([["One", 2], ["word", 2], ["at", 2], ["a", 2], ["time.", 8]]);
  line([["Right", 2], ["where", 2], ["your", 2], ["eyes", 2], ["already", 2], ["are.", 6]]);
  // Bar 7: sixteenths, 500 wpm.
  line([["No", 1], ["jumping.", 3], ["No", 1], ["searching.", 3], ["No", 1], ["losing", 1], ["your", 1], ["place.", 5]]);
  // Bar 8.
  line([["Up", 2], ["to", 2], ["1,000", 4], ["words", 2], ["a", 1], ["minute.", 5]]);
  // Bar 9.
  line([["Books.", 4], ["Papers.", 4], ["Articles.", 4], [null, 4]]);
  // Bar 10: the finger holds until "pause.", which lands on the freeze at bar 11.
  line([["Hold", 2], ["to", 2], ["read.", 6], ["Let", 2], ["go", 2], ["to", 2], ["pause.", 8]]);
  line([["Slide", 2], ["for", 2], ["speed.", 4]]);
  // Bar 12: chapter announcement, then the chapter's first sentence over the snare roll,
  // with the compound and the sentence end held longer, as the app's timing does.
  push(`Chapter ${CHAPTER}`, 8, "chapter");
  let i = 0;
  for (const n of [1, 1, 1, 1, 2, 2]) push(CHAPTER_WORDS[i++], n);
  // Bars 13–15: thirty-second notes, 1,000 wpm, until the cut.
  while (t < T.cut - 1e-6) {
    const w = CHAPTER_WORDS[i++ % CHAPTER_WORDS.length];
    const d = S32;
    list.push({ text: w, start: t, end: t + d, kind: "word" });
    t += d;
  }
  return list;
}

export const SCHEDULE = buildSchedule();

export const TAGLINE = [
  { text: "Read", start: T.tagline, end: T.tagline + BEAT },
  { text: "more.", start: T.tagline + BEAT, end: T.tagline + BEAT * 2 },
  { text: "Move", start: T.tagline + BEAT * 2, end: T.tagline + BEAT * 3 },
  { text: "less.", start: T.tagline + BEAT * 3, end: T.logo },
];

/// How far the finger has dragged the speed slider, 0 to 1. The readout follows it.
export function slideAt(t) {
  const a = T.resume + 0.12, b = T.chapter - 0.1;
  const u = Math.min(1, Math.max(0, (t - a) / (b - a)));
  return u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
}

/// Words per minute shown on the speed readout.
export function wpmAt(t) {
  if (t < bar(7)) return 250;
  if (t < bar(8) + BEAT * 1) return 500;
  if (t < bar(8) + BEAT * 2) {
    const u = (t - (bar(8) + BEAT)) / BEAT;
    return 500 + (1000 - 500) * u * u * (3 - 2 * u);
  }
  if (t < T.library) return 1000;
  if (t < T.library + BEAT) {
    const u = (t - T.library) / BEAT;
    return 1000 - 500 * u * u * (3 - 2 * u);
  }
  if (t < T.resume) return 500;
  return 500 + 500 * slideAt(t);
}

export function mulberry32(seed) {
  return function () {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/// Eye fixations over the opening page, on the sixteenth grid so each saccade
/// lands on the music. They get shorter and more erratic toward the collapse.
export const FIXATIONS = (() => {
  const rng = mulberry32(11);
  const out = [];
  let t = S16 * 3;
  while (t < T.collapse - S16 * 0.5) {
    const u = t / T.collapse;
    const pool = u < 0.3 ? [3, 3, 4, 2] : u < 0.62 ? [2, 2, 3, 2, 1] : u < 0.85 ? [1, 2, 1, 1] : [1];
    const n = pool[Math.floor(rng() * pool.length)];
    const regress = out.length > 2 && rng() < 0.06 + 0.22 * u;
    out.push({ start: t, dur: n * S16, type: regress ? "regress" : "forward", pan: rng() * 2 - 1 });
    t += n * S16;
  }
  return out;
})();

/// Kick times for the climax pulses and the groove.
export function kicks() {
  const out = [];
  for (let b = 0; b < 16; b++) out.push(T.library + b * BEAT);
  for (let b = 0; b < 8; b++) out.push(T.climax + b * BEAT);
  // Bar 15 accelerates: quarters, eighths, sixteenths.
  const b15 = bar(15);
  out.push(b15, b15 + BEAT);
  for (let k = 0; k < 2; k++) out.push(b15 + BEAT * 2 + k * BEAT / 2);
  for (let k = 0; k < 4; k++) out.push(b15 + BEAT * 3 + k * S16);
  return out.filter((k) => !(k >= T.pause && k < T.resume));
}
