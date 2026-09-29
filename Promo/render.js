// Renders the ad frame by frame in headless Chrome and pipes raw frames to FFmpeg.
//
//   bun render.js                       full video → out/video.mp4, muxed with out/audio.wav
//   bun render.js --stills 1.2,9.6      PNG stills at those times → out/stills/
//   bun render.js --from 9 --to 12      partial render (seconds)
//   options: --pages N (parallel tabs), --sub N (motion-blur subframes)

import puppeteer from "puppeteer-core";
import { mkdirSync, existsSync } from "node:fs";
import { join, dirname, extname } from "node:path";
import { FPS, DURATION, W, H } from "./timeline.js";

const HERE = import.meta.dir;
const ROOT = dirname(HERE);
const OUT = join(HERE, "out");
mkdirSync(join(OUT, "stills"), { recursive: true });

const arg = (name, fallback) => {
  const i = process.argv.indexOf("--" + name);
  return i >= 0 ? process.argv[i + 1] : fallback;
};
const stills = arg("stills", null)?.split(",").map(Number);
const from = Number(arg("from", 0));
const to = Number(arg("to", DURATION));
const pages = Number(arg("pages", 6));
const sub = Number(arg("sub", 10));

const TYPES = { ".html": "text/html", ".js": "text/javascript", ".ttf": "font/ttf", ".ttc": "font/collection" };

let ffmpeg = null;
let nextFrame = 0;
const pending = new Map();
let flushing = Promise.resolve();

async function flush() {
  while (pending.has(nextFrame)) {
    const buf = pending.get(nextFrame);
    pending.delete(nextFrame);
    ffmpeg.stdin.write(buf);
    await ffmpeg.stdin.flush();
    nextFrame++;
  }
}

const server = Bun.serve({
  port: 0,
  async fetch(req) {
    const url = new URL(req.url);
    if (req.method === "POST" && url.pathname === "/frame") {
      const n = Number(url.searchParams.get("n"));
      pending.set(n, new Uint8Array(await req.arrayBuffer()));
      flushing = flushing.then(flush);
      await flushing;
      return new Response("ok");
    }
    if (req.method === "POST" && url.pathname === "/still") {
      const name = url.searchParams.get("name");
      await Bun.write(join(OUT, "stills", name + ".png"), await req.arrayBuffer());
      return new Response("ok");
    }
    const path = join(ROOT, decodeURIComponent(url.pathname));
    if (!path.startsWith(ROOT) || !existsSync(path)) return new Response("not found", { status: 404 });
    return new Response(Bun.file(path), {
      headers: { "content-type": TYPES[extname(path)] ?? "application/octet-stream" },
    });
  },
});

const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
  protocolTimeout: 0,
  args: [
    "--enable-gpu",
    "--ignore-gpu-blocklist",
    "--enable-unsafe-webgpu",
    "--use-angle=metal",
    "--disable-background-timer-throttling",
    "--disable-renderer-backgrounding",
    "--disable-backgrounding-occluded-windows",
    "--force-color-profile=srgb",
  ],
});

async function openPage() {
  const page = await browser.newPage();
  await page.setViewport({ width: W, height: H, deviceScaleFactor: 1 });
  page.on("console", (m) => console.log("[page]", m.text()));
  page.on("pageerror", (e) => console.error("[page error]", e.message));
  await page.goto(`http://localhost:${server.port}/Promo/scene.html`);
  await page.waitForFunction("window.ready === true", { timeout: 60000 });
  return page;
}

const started = performance.now();

if (stills) {
  const page = await openPage();
  for (const t of stills) {
    const n = Math.round(t * FPS);
    await page.evaluate((n, sub, name) => window.renderStill(n, sub, name), n, sub, t.toFixed(2).replace(".", "_"));
    console.log(`still ${t}s`);
  }
} else {
  const first = Math.round(from * FPS);
  const last = Math.min(Math.round(to * FPS), Math.round(DURATION * FPS));
  nextFrame = first;
  const partial = from > 0 || to < DURATION;
  const videoPath = join(OUT, partial ? "partial.mp4" : "video.mp4");
  ffmpeg = Bun.spawn(
    [
      "ffmpeg", "-y", "-loglevel", "error",
      "-f", "rawvideo", "-pix_fmt", "rgba", "-s", `${W}x${H}`, "-r", String(FPS), "-i", "-",
      "-vf", "vflip",
      "-c:v", "libx264", "-preset", "slow", "-crf", "14", "-tune", "film",
      "-pix_fmt", "yuv420p", "-movflags", "+faststart",
      videoPath,
    ],
    { stdin: "pipe", stdout: "inherit", stderr: "inherit" },
  );

  const tabs = await Promise.all(Array.from({ length: pages }, openPage));
  let done = 0;
  await Promise.all(
    tabs.map(async (page, i) => {
      for (let n = first + i; n < last; n += pages) {
        await page.evaluate((n, sub) => window.renderAndSend(n, sub), n, sub);
        done++;
        if (done % 30 === 0) {
          const el = (performance.now() - started) / 1000;
          console.log(`${done}/${last - first} frames  ${el.toFixed(0)}s`);
        }
      }
    }),
  );
  await flushing;
  ffmpeg.stdin.end();
  await ffmpeg.exited;

  const audio = join(OUT, "audio.wav");
  if (!partial && existsSync(audio)) {
    const final = join(OUT, "strobe-ad.mp4");
    const mux = Bun.spawn([
      "ffmpeg", "-y", "-loglevel", "error", "-i", videoPath, "-i", audio,
      "-c:v", "copy", "-c:a", "aac", "-b:a", "320k", "-shortest", "-movflags", "+faststart", final,
    ]);
    await mux.exited;
    console.log("wrote", final);
  } else {
    console.log("wrote", videoPath);
  }
}

console.log(`done in ${((performance.now() - started) / 1000).toFixed(1)}s`);
await browser.close();
server.stop(true);
