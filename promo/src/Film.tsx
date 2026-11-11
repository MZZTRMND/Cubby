import React from 'react';
import {AbsoluteFill, Img, OffthreadVideo, Sequence, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {ease, FONT, lerp, sp, tween} from './lib';

// The real app, recorded by Scripts/record-demo.sh: 2560×1440 points at 2× (5120×2880).
const SRC = staticFile('demo.mov');
const PT_W = 2560;
const PT_H = 1440;
/** The recording starts this long before the demo's first marker. */
const LEAD = 1.1;
// When each scene of the demo began, from footage/demo-markers.json.
export const M = {meet: 0, takes: 7.96, screenshots: 21.24, summon: 27.41, more: 34.6, card: 43.98, giveback: 57.2, outro: 62.94};

type Cam = [at: number, x: number, y: number, w: number];

/** A shot of the recording: a stretch of it, at `rate`, seen through a camera that moves
 *  between `cams` (centre and visible width, in points) as the shot plays. */
export const Footage: React.FC<{from: number; rate?: number; cams: Cam[]; dur: number; src?: string}> = ({from, rate = 1, cams, dur, src = SRC}) => {
  const f = useCurrentFrame();
  const {width, height} = useVideoConfig();
  const p = f / dur;
  let [, x, y, w] = cams[0];
  for (let i = 0; i < cams.length - 1; i++) {
    const [a, x0, y0, w0] = cams[i];
    const [b, x1, y1, w1] = cams[i + 1];
    if (p >= a) {
      const t = ease(Math.min(1, (p - a) / (b - a)));
      x = lerp(x0, x1, t);
      y = lerp(y0, y1, t);
      w = lerp(w0, w1, t);
    }
  }
  const s = width / w;
  return (
    <AbsoluteFill style={{overflow: 'hidden', background: '#000'}}>
      <OffthreadVideo
        src={src}
        muted
        trimBefore={Math.round((from + LEAD) * 60)}
        playbackRate={rate}
        style={{position: 'absolute', width: PT_W * s, height: PT_H * s, left: width / 2 - x * s, top: height / 2 - y * s, maxWidth: 'none'}}
      />
    </AbsoluteFill>
  );
};

type Edge = 'zoom' | 'whip' | 'cut' | 'fade';

/** A segment that comes in and goes out in Apple's ways: zooming through a blur, a whip
 *  pan, or a plain fade. */
const Segment: React.FC<{dur: number; enter: Edge; exit: Edge; children: React.ReactNode}> = ({dur, enter, exit, children}) => {
  const f = useCurrentFrame();
  const IN = 20;
  const OUT = 18;
  const i = tween(f, 0, IN, 0, 1);
  const o = tween(f, dur - OUT, dur, 0, 1);
  let scale = 1;
  let blur = 0;
  let opacity = 1;
  let x = 0;
  if (enter === 'zoom') {
    scale *= lerp(1.18, 1, i);
    blur += (1 - i) * 26;
    opacity *= i;
  } else if (enter === 'whip') {
    x += (1 - i) * 1300;
    blur += Math.sin(i * Math.PI) * 30;
  } else if (enter === 'fade') {
    opacity *= i;
  }
  if (exit === 'zoom') {
    scale *= lerp(1, 1.1, o);
    blur += o * 22;
    opacity *= 1 - o;
  } else if (exit === 'whip') {
    x -= o * 1300;
    blur += Math.sin(o * Math.PI) * 30;
  } else if (exit === 'fade') {
    opacity *= 1 - o;
  }
  return (
    <AbsoluteFill style={{opacity, transform: `translateX(${x}px) scale(${scale})`, filter: blur > 0.3 ? `blur(${blur}px)` : undefined}}>
      {children}
    </AbsoluteFill>
  );
};

/** Big words on black, each arriving out of a blur, as in Apple's films. */
const Title: React.FC<{lines: string[]; dur: number; size?: number}> = ({lines, dur, size = 132}) => {
  const f = useCurrentFrame();
  let n = 0;
  const glow = tween(f, 0, dur, 0.9, 1.1, (t) => t);
  return (
    <AbsoluteFill style={{background: '#000', alignItems: 'center', justifyContent: 'center', fontFamily: FONT}}>
      <div
        style={{
          position: 'absolute',
          width: 1400,
          height: 700,
          borderRadius: '50%',
          background: 'radial-gradient(ellipse, rgba(120,90,255,0.32), rgba(255,90,140,0.12) 45%, transparent 70%)',
          transform: `scale(${glow})`,
          filter: 'blur(40px)',
        }}
      />
      <div style={{textAlign: 'center', transform: `scale(${tween(f, 0, dur, 0.97, 1.02, (t) => t)})`}}>
        {lines.map((line, li) => (
          <div key={li} style={{fontSize: size, fontWeight: 700, letterSpacing: '-0.045em', lineHeight: 1.04}}>
            {line.split(' ').map((word, wi) => {
              const p = sp(f, 4 + n++ * 4, {damping: 22, stiffness: 120});
              return (
                <span
                  key={wi}
                  style={{
                    display: 'inline-block',
                    marginRight: '0.24em',
                    opacity: p,
                    transform: `translateY(${(1 - p) * 34}px)`,
                    filter: `blur(${(1 - p) * 14}px)`,
                    backgroundImage: 'linear-gradient(180deg, #ffffff 30%, #c9c9d6 100%)',
                    WebkitBackgroundClip: 'text',
                    color: 'transparent',
                  }}
                >
                  {word}
                </span>
              );
            })}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

/** A line of text over the footage, low on the left. */
const Lower: React.FC<{text: string; at: number; out: number}> = ({text, at, out}) => {
  const f = useCurrentFrame();
  const p = sp(f, at, {damping: 22, stiffness: 120});
  const o = tween(f, out, out + 14, 1, 0);
  return (
    <div
      style={{
        position: 'absolute',
        left: 110,
        bottom: 96,
        fontFamily: FONT,
        fontSize: 64,
        fontWeight: 700,
        letterSpacing: '-0.035em',
        color: '#fff',
        textShadow: '0 4px 30px rgba(0,0,0,0.35)',
        opacity: p * o,
        transform: `translateY(${(1 - p) * 24}px)`,
        filter: `blur(${(1 - p) * 10}px)`,
      }}
    >
      {text}
    </div>
  );
};

const EndCard: React.FC<{dur: number}> = ({dur}) => {
  const f = useCurrentFrame();
  const back = tween(f, 0, 50, 0, 1);
  const icon = sp(f, 24, {damping: 13, stiffness: 120});
  const name = sp(f, 40, {damping: 20});
  const tag = sp(f, 52, {damping: 20});
  const pill = sp(f, 66, {damping: 20});
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{filter: `blur(${back * 70}px) brightness(${1 - back * 0.62}) saturate(${1 + back * 0.3})`, transform: `scale(${1 + back * 0.08})`}}>
        <Footage from={M.outro + 0.4} dur={dur} cams={[[0, 1280, 800, 900], [1, 1280, 800, 760]]} />
      </AbsoluteFill>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', fontFamily: FONT, color: '#fff'}}>
        <div style={{width: 230, height: 230, borderRadius: 52, overflow: 'hidden', boxShadow: '0 30px 80px rgba(0,0,0,0.45)', transform: `scale(${icon})`, marginTop: -40}}>
          <Img src={staticFile('icon.png')} style={{width: '100%', height: '100%'}} />
        </div>
        <div style={{marginTop: 42, fontSize: 150, fontWeight: 700, letterSpacing: '-0.05em', opacity: name, filter: `blur(${(1 - name) * 12}px)`}}>Cubby</div>
        <div style={{marginTop: 4, fontSize: 40, fontWeight: 500, color: 'rgba(255,255,255,0.78)', opacity: tag, transform: `translateY(${(1 - tag) * 16}px)`}}>
          A little folder for everything on your desktop.
        </div>
        <div
          style={{
            marginTop: 40,
            padding: '12px 30px',
            borderRadius: 40,
            fontSize: 26,
            fontWeight: 600,
            background: 'rgba(255,255,255,0.14)',
            border: '1px solid rgba(255,255,255,0.25)',
            backdropFilter: 'blur(20px)',
            opacity: pill,
          }}
        >
          For macOS Tahoe
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// ---- The cut ----

type Part = {dur: number; enter: Edge; exit: Edge; node: (dur: number) => React.ReactNode};

const OVERLAP = 18;
const title = (lines: string[], dur = 74): Part => ({dur, enter: 'fade', exit: 'fade', node: (d) => <Title lines={lines} dur={d} />});
const shot = (from: number, seconds: number, rate: number, cams: Cam[], enter: Edge, exit: Edge, lower?: string): Part => {
  const dur = Math.round((seconds / rate) * 60);
  return {
    dur,
    enter,
    exit,
    node: (d) => (
      <>
        <Footage from={from} rate={rate} cams={cams} dur={d} />
        {lower && <Lower text={lower} at={24} out={d - 30} />}
      </>
    ),
  };
};

const PARTS: Part[] = [
  title(['Say hello', 'to Cubby.'], 96),
  // The folder wakes up and watches the pointer go round.
  shot(M.meet + 0.6, 7.2, 1, [[0, 1280, 790, 560], [0.35, 1280, 800, 760], [1, 1280, 800, 1150]], 'zoom', 'zoom'),
  title(['Drop in anything.']),
  shot(M.takes, 12.6, 1.55, [[0, 1280, 780, 1450], [1, 1280, 790, 1250]], 'zoom', 'zoom'),
  title(['Screenshots', 'land right in it.']),
  shot(M.screenshots + 0.6, 5.4, 1.1, [[0, 1250, 760, 1300], [0.55, 1400, 790, 1150], [1, 1660, 900, 760]], 'zoom', 'zoom'),
  title(['Shake a drag.', 'It comes to you.']),
  shot(M.summon + 0.5, 6.6, 1.2, [[0, 1220, 760, 1300], [0.45, 1320, 770, 1300], [1, 1520, 830, 1150]], 'zoom', 'whip'),
  shot(M.more + 0.5, 8.8, 1.7, [[0, 1300, 790, 1350], [1, 1340, 800, 1280]], 'whip', 'zoom', 'Links, words and colors too.'),
  title(['Everything,', 'one click away.']),
  shot(M.card + 0.5, 12.6, 1.35, [[0, 1080, 790, 1150], [0.2, 1060, 800, 900], [1, 1050, 800, 720]], 'zoom', 'whip'),
  shot(M.giveback + 0.3, 5.6, 1.1, [[0, 1250, 780, 1250], [1, 1360, 770, 1180]], 'whip', 'zoom', 'And right back out.'),
  {dur: 330, enter: 'fade', exit: 'cut', node: (d) => <EndCard dur={d} />},
];

const starts = PARTS.reduce<number[]>((acc, part, i) => [...acc, i === 0 ? 0 : acc[i - 1] + PARTS[i - 1].dur - OVERLAP], []);
export const FILM_FRAMES = starts[starts.length - 1] + PARTS[PARTS.length - 1].dur;

export const Film: React.FC = () => (
  <AbsoluteFill style={{background: '#000'}}>
    {PARTS.map((part, i) => (
      <Sequence key={i} from={starts[i]} durationInFrames={part.dur}>
        <Segment dur={part.dur} enter={part.enter} exit={part.exit}>
          {part.node(part.dur)}
        </Segment>
      </Sequence>
    ))}
  </AbsoluteFill>
);
