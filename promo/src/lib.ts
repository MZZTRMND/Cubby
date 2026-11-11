import {Easing, interpolate, spring} from 'remotion';

export const FPS = 60;
export const W = 1920;
export const H = 1080;
export const FONT = 'system-ui, -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif';
export const INK = '#1d1d1f';

export const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
export const ease = Easing.bezier(0.45, 0, 0.2, 1);
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** from → to between frames a and b, eased and clamped. */
export const tween = (f: number, a: number, b: number, from: number, to: number, e = ease) =>
  interpolate(f, [a, b], [from, to], {...clamp, easing: e});

/** A spring that starts at `start`. */
export const sp = (f: number, start: number, config: Partial<{damping: number; stiffness: number; mass: number}> = {}) =>
  spring({frame: f - start, fps: FPS, config: {damping: 14, stiffness: 140, mass: 0.8, ...config}});

export type Key = [frame: number, x: number, y: number];

/** A point moving through keyframes, eased between each pair. */
export const track = (f: number, keys: Key[], e = ease): [number, number] => {
  if (f <= keys[0][0]) return [keys[0][1], keys[0][2]];
  for (let i = 0; i < keys.length - 1; i++) {
    const [f0, x0, y0] = keys[i];
    const [f1, x1, y1] = keys[i + 1];
    if (f <= f1) {
      const t = f1 === f0 ? 1 : e((f - f0) / (f1 - f0));
      return [lerp(x0, x1, t), lerp(y0, y1, t)];
    }
  }
  const last = keys[keys.length - 1];
  return [last[1], last[2]];
};

/** A throw from one point to another along an arc that rises by `lift`. */
export const arc = (t: number, x0: number, y0: number, x1: number, y1: number, lift: number): [number, number] => [
  lerp(x0, x1, t),
  lerp(y0, y1, t) - lift * 4 * t * (1 - t),
];

/** Where the eyes look: a direction up to 1 long, shorter when the target is close. */
export const lookAt = (ex: number, ey: number, tx: number, ty: number, reach = 460): [number, number] => {
  const dx = tx - ex;
  const dy = ty - ey;
  const d = Math.hypot(dx, dy);
  if (d < 1) return [0, 0];
  const r = Math.min(1, d / reach);
  return [(dx / d) * r, (dy / d) * r];
};

/** The lid, 1 open: dips to a line for each blink in `times`. */
export const blink = (f: number, times: number[]) => {
  let lid = 1;
  for (const t of times) {
    const d = f - t;
    if (d < 0 || d > 13) continue;
    lid = Math.min(lid, d < 4 ? 1 - (d / 4) * 0.9 : 0.1 + ((d - 4) / 9) * 0.9);
  }
  return lid;
};

/** A little damped wobble after `start`, for landings and bumps. */
export const wobble = (f: number, start: number, amount = 0.08, speed = 4, decay = 9) =>
  f < start ? 0 : amount * Math.exp(-(f - start) / decay) * Math.cos((f - start) / speed);
