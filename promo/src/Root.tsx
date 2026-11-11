import React from 'react';
import {Composition} from 'remotion';
import {FPS, H, W} from './lib';
import {Film, FILM_FRAMES} from './Film';
import {Gif, GIF_FRAMES} from './Gif';

export const Root: React.FC = () => (
  <>
    {/* The film, cut from a recording of the real app (Scripts/record-demo.sh). */}
    <Composition id="CubbyFilm" component={Film} durationInFrames={FILM_FRAMES} fps={FPS} width={W} height={H} />
    {/* A short loop for the README. */}
    <Composition id="CubbyGif" component={Gif} durationInFrames={GIF_FRAMES} fps={FPS} width={640} height={360} />
  </>
);
