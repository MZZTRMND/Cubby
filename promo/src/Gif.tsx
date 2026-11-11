import React from 'react';
import {AbsoluteFill, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {Footage} from './Film';
import {tween} from './lib';

// A short loop of the real app in dark mode for the README: the folder wakes up, a drag
// gets shaken and the folder pops up for it, then the card opens and finds by typing.
// The camera holds still in each shot, which keeps the file small.
// Recorded with `Scripts/record-demo.sh --dark`; scene times from demo-dark-markers.json.
const SRC = staticFile('demo-dark.mov');
const M = {meet: 0, summon: 27.31, card: 43.92};
const FADE = 10;
type Cam = [number, number, number, number];
const SHOTS: {from: number; seconds: number; rate: number; cam: Cam}[] = [
  {from: M.meet + 1.0, seconds: 4.2, rate: 1.2, cam: [0, 1280, 800, 700]},
  {from: M.summon + 0.7, seconds: 5.0, rate: 1.25, cam: [0, 1450, 740, 1150]},
  {from: M.card + 1.2, seconds: 3.0, rate: 1.2, cam: [0, 1055, 800, 820]},
  {from: M.card + 9.2, seconds: 3.0, rate: 1, cam: [0, 1055, 800, 820]},
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
      <Footage src={SRC} from={SHOTS[0].from} rate={0.0001} cams={[SHOTS[0].cam]} dur={durs[0]} />
    </Sequence>
    {SHOTS.map((s, i) => (
      <Sequence key={i} from={starts[i]} durationInFrames={durs[i]}>
        <Fade dur={durs[i]} first={i === 0} last={i === SHOTS.length - 1}>
          <Footage src={SRC} from={s.from} rate={s.rate} cams={[s.cam]} dur={durs[i]} />
        </Fade>
      </Sequence>
    ))}
  </AbsoluteFill>
);
