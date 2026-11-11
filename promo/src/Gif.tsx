import React from 'react';
import {AbsoluteFill, Sequence, useCurrentFrame} from 'remotion';
import {Footage, M} from './Film';
import {tween} from './lib';

// A short loop of the real app for the README: the folder wakes up, things go in, the
// card opens. The camera holds still, which keeps the file small.
const FADE = 12;
const SHOTS: {from: number; seconds: number; rate: number; cams: [number, number, number, number][]}[] = [
  {from: M.meet + 1.0, seconds: 4.2, rate: 1.2, cams: [[0, 1280, 800, 700], [1, 1280, 800, 700]]},
  {from: M.takes, seconds: 5.2, rate: 1.7, cams: [[0, 1280, 790, 1250], [1, 1280, 790, 1250]]},
  {from: M.card + 1.6, seconds: 6.2, rate: 1.6, cams: [[0, 1055, 800, 820], [1, 1055, 800, 820]]},
];
const durs = SHOTS.map((s) => Math.round((s.seconds / s.rate) * 60));
const starts = durs.reduce<number[]>((acc, _, i) => [...acc, i === 0 ? 0 : acc[i - 1] + durs[i - 1] - FADE], []);
export const GIF_FRAMES = starts[starts.length - 1] + durs[durs.length - 1];

const Fade: React.FC<{dur: number; first: boolean; last: boolean; children: React.ReactNode}> = ({dur, first, last, children}) => {
  const f = useCurrentFrame();
  // The last shot fades out to the first shot's opening, so the loop has no seam.
  const o = (first ? 1 : tween(f, 0, FADE, 0, 1)) * (last ? tween(f, dur - FADE, dur, 1, 0) : 1);
  return <AbsoluteFill style={{opacity: o}}>{children}</AbsoluteFill>;
};

export const Gif: React.FC = () => (
  <AbsoluteFill style={{background: '#000'}}>
    {/* Under everything: the first frame, for the last shot to fade into. */}
    <Sequence from={GIF_FRAMES - FADE} durationInFrames={FADE}>
      <Footage from={SHOTS[0].from} rate={0.0001} cams={SHOTS[0].cams} dur={durs[0]} />
    </Sequence>
    {SHOTS.map((s, i) => (
      <Sequence key={i} from={starts[i]} durationInFrames={durs[i]}>
        <Fade dur={durs[i]} first={i === 0} last={i === SHOTS.length - 1}>
          <Footage from={s.from} rate={s.rate} cams={s.cams} dur={durs[i]} />
        </Fade>
      </Sequence>
    ))}
  </AbsoluteFill>
);
