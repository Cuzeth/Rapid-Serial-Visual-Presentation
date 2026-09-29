// WebGL2 post pipeline: accumulates motion-blur subframes of the 2D scene canvas,
// then composites bloom, chromatic aberration, grain, and vignette.

const VS = `#version 300 es
in vec2 p;
out vec2 uv;
void main() { uv = p * 0.5 + 0.5; gl_Position = vec4(p, 0.0, 1.0); }`;

const ACCUM_FS = `#version 300 es
precision highp float;
in vec2 uv;
uniform sampler2D src;
uniform float weight;
out vec4 o;
void main() { o = vec4(texture(src, vec2(uv.x, 1.0 - uv.y)).rgb * weight, weight); }`;

const BRIGHT_FS = `#version 300 es
precision highp float;
in vec2 uv;
uniform sampler2D src;
uniform vec2 texel;
uniform float threshold;
out vec4 o;
void main() {
  vec3 c = vec3(0.0);
  c += texture(src, uv + texel * vec2(-0.5, -0.5)).rgb;
  c += texture(src, uv + texel * vec2( 0.5, -0.5)).rgb;
  c += texture(src, uv + texel * vec2(-0.5,  0.5)).rgb;
  c += texture(src, uv + texel * vec2( 0.5,  0.5)).rgb;
  c *= 0.25;
  float m = max(c.r, max(c.g, c.b));
  float knee = 0.25;
  float soft = clamp(m - threshold + knee, 0.0, 2.0 * knee);
  soft = soft * soft / (4.0 * knee + 1e-4);
  float contrib = max(soft, m - threshold) / max(m, 1e-4);
  o = vec4(c * contrib, 1.0);
}`;

const DOWN_FS = `#version 300 es
precision highp float;
in vec2 uv;
uniform sampler2D src;
uniform vec2 texel;
out vec4 o;
void main() {
  vec3 c = texture(src, uv).rgb * 0.5;
  c += texture(src, uv + texel * vec2(-1.0, -1.0)).rgb * 0.125;
  c += texture(src, uv + texel * vec2( 1.0, -1.0)).rgb * 0.125;
  c += texture(src, uv + texel * vec2(-1.0,  1.0)).rgb * 0.125;
  c += texture(src, uv + texel * vec2( 1.0,  1.0)).rgb * 0.125;
  o = vec4(c, 1.0);
}`;

const BLUR_FS = `#version 300 es
precision highp float;
in vec2 uv;
uniform sampler2D src;
uniform vec2 dir;
out vec4 o;
void main() {
  float w[5] = float[](0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162);
  vec3 c = texture(src, uv).rgb * w[0];
  for (int i = 1; i < 5; i++) {
    c += texture(src, uv + dir * float(i)).rgb * w[i];
    c += texture(src, uv - dir * float(i)).rgb * w[i];
  }
  o = vec4(c, 1.0);
}`;

const COMPOSITE_FS = `#version 300 es
precision highp float;
in vec2 uv;
uniform sampler2D scene;
uniform sampler2D b0;
uniform sampler2D b1;
uniform sampler2D b2;
uniform sampler2D b3;
uniform sampler2D b4;
uniform float bloom;
uniform float ca;
uniform float grain;
uniform float vignette;
uniform float saturation;
uniform float exposure;
uniform float seed;
uniform vec2 res;
out vec4 o;

float hash(vec2 p) {
  p = fract(p * vec2(443.897, 441.423));
  p += dot(p, p.yx + 19.19);
  return fract((p.x + p.y) * p.x);
}

void main() {
  vec2 st = vec2(uv.x, 1.0 - uv.y);
  vec2 d = st - 0.5;
  float r2 = dot(d, d);
  vec2 off = d * (ca / max(res.x, res.y)) * (0.4 + 2.2 * r2);
  vec3 c;
  c.r = texture(scene, uv + vec2(off.x, -off.y)).r;
  c.g = texture(scene, uv).g;
  c.b = texture(scene, uv - vec2(off.x, -off.y)).b;

  vec3 bl = texture(b0, uv).rgb * 0.6
          + texture(b1, uv).rgb * 0.8
          + texture(b2, uv).rgb * 1.0
          + texture(b3, uv).rgb * 1.1
          + texture(b4, uv).rgb * 1.2;
  c += bl * bloom;
  c *= exposure;

  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  c = mix(vec3(l), c, saturation);

  c = c / (1.0 + max(c - 0.85, 0.0) * 0.9);

  float v = smoothstep(0.95, 0.15, length(d * vec2(1.0, 0.82)));
  c *= mix(1.0 - vignette, 1.0, v);

  float n = hash(st * res + seed * 17.0) + hash(st * res * 1.37 - seed * 11.0) - 1.0;
  c += n * grain * (0.6 + 0.4 * (1.0 - l));

  o = vec4(clamp(c, 0.0, 1.0), 1.0);
}`;

export function createPost(canvas, W, H) {
  const gl = canvas.getContext("webgl2", {
    preserveDrawingBuffer: true,
    antialias: false,
    premultipliedAlpha: false,
  });
  if (!gl) throw new Error("WebGL2 unavailable");
  if (!gl.getExtension("EXT_color_buffer_float")) throw new Error("EXT_color_buffer_float unavailable");
  gl.getExtension("OES_texture_float_linear");

  const compile = (type, src) => {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  };
  const program = (fs) => {
    const p = gl.createProgram();
    gl.attachShader(p, compile(gl.VERTEX_SHADER, VS));
    gl.attachShader(p, compile(gl.FRAGMENT_SHADER, fs));
    gl.bindAttribLocation(p, 0, "p");
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    const u = {};
    const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) {
      const info = gl.getActiveUniform(p, i);
      u[info.name] = gl.getUniformLocation(p, info.name);
    }
    return { p, u };
  };

  const quad = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, quad);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

  const texture = (w, h, float) => {
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    if (float) gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, w, h, 0, gl.RGBA, gl.HALF_FLOAT, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  };
  const target = (w, h) => {
    const tex = texture(w, h, true);
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
    return { tex, fb, w, h };
  };

  const sceneTex = texture(W, H, false);
  const accum = target(W, H);
  const levels = [];
  let lw = W >> 1, lh = H >> 1;
  for (let i = 0; i < 5; i++) {
    levels.push({ a: target(lw, lh), b: target(lw, lh) });
    lw = Math.max(1, lw >> 1);
    lh = Math.max(1, lh >> 1);
  }

  const P = {
    accum: program(ACCUM_FS),
    bright: program(BRIGHT_FS),
    down: program(DOWN_FS),
    blur: program(BLUR_FS),
    composite: program(COMPOSITE_FS),
  };

  const draw = (prog, fbo, w, h, setup) => {
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
    gl.viewport(0, 0, w, h);
    gl.useProgram(prog.p);
    setup(prog.u);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  };
  const bind = (unit, tex, loc) => {
    gl.activeTexture(gl.TEXTURE0 + unit);
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.uniform1i(loc, unit);
  };

  return {
    begin() {
      gl.bindFramebuffer(gl.FRAMEBUFFER, accum.fb);
      gl.viewport(0, 0, W, H);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
    },
    add(sourceCanvas, weight) {
      gl.bindTexture(gl.TEXTURE_2D, sceneTex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, sourceCanvas);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.ONE, gl.ONE);
      draw(P.accum, accum.fb, W, H, (u) => {
        bind(0, sceneTex, u.src);
        gl.uniform1f(u.weight, weight);
      });
      gl.disable(gl.BLEND);
    },
    finish(fx) {
      const l0 = levels[0];
      draw(P.bright, l0.a.fb, l0.a.w, l0.a.h, (u) => {
        bind(0, accum.tex, u.src);
        gl.uniform2f(u.texel, 1 / W, 1 / H);
        gl.uniform1f(u.threshold, fx.threshold);
      });
      for (let i = 0; i < levels.length; i++) {
        const L = levels[i];
        if (i > 0) {
          const prev = levels[i - 1].a;
          draw(P.down, L.a.fb, L.a.w, L.a.h, (u) => {
            bind(0, prev.tex, u.src);
            gl.uniform2f(u.texel, 1 / prev.w, 1 / prev.h);
          });
        }
        draw(P.blur, L.b.fb, L.a.w, L.a.h, (u) => {
          bind(0, L.a.tex, u.src);
          gl.uniform2f(u.dir, 1.5 / L.a.w, 0);
        });
        draw(P.blur, L.a.fb, L.a.w, L.a.h, (u) => {
          bind(0, L.b.tex, u.src);
          gl.uniform2f(u.dir, 0, 1.5 / L.a.h);
        });
      }
      draw(P.composite, null, W, H, (u) => {
        bind(0, accum.tex, u.scene);
        for (let i = 0; i < 5; i++) bind(i + 1, levels[i].a.tex, u["b" + i]);
        gl.uniform1f(u.bloom, fx.bloom);
        gl.uniform1f(u.ca, fx.ca);
        gl.uniform1f(u.grain, fx.grain);
        gl.uniform1f(u.vignette, fx.vignette);
        gl.uniform1f(u.saturation, fx.saturation);
        gl.uniform1f(u.exposure, fx.exposure);
        gl.uniform1f(u.seed, fx.seed);
        gl.uniform2f(u.res, W, H);
      });
    },
    readPixels() {
      const px = new Uint8Array(W * H * 4);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.readPixels(0, 0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, px);
      return px;
    },
  };
}
