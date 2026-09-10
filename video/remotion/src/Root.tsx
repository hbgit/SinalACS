/**
 * Composições do vídeo do sponsor.
 *
 * Todas as durações vêm de `video/roteiro.timing.json` — nenhum número de frame
 * é digitado aqui, para que roteiro, cartelas, legendas e montagem não possam
 * divergir.
 *
 *  · Block1/2/6/7 — as cartelas, SEM legenda (a legenda vem da camada única).
 *  · Subtitles    — camada transparente de 5400 frames com todas as legendas.
 *  · Preview      — os 180 s completos, com marcadores no lugar das tomadas.
 */

import React from 'react';
import { Composition } from 'remotion';
import { Block1 } from './cards/Block1';
import { Block2 } from './cards/Block2';
import { Block5 } from './cards/Block5';
import { Block6 } from './cards/Block6';
import { Block7 } from './cards/Block7';
import { Preview } from './Preview';
import { SubtitleTrack } from './SubtitleTrack';
import { blockDuration, timing } from './timing';

const base = {
  width: timing.width,
  height: timing.height,
  fps: timing.fps,
} as const;

export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="Block1" component={Block1} durationInFrames={blockDuration(1)} {...base} />
    <Composition id="Block2" component={Block2} durationInFrames={blockDuration(2)} {...base} />
    <Composition id="Block5" component={Block5} durationInFrames={blockDuration(5)} {...base} />

    <Composition id="Block6" component={Block6} durationInFrames={blockDuration(6)} {...base} />
    <Composition id="Block7" component={Block7} durationInFrames={blockDuration(7)} {...base} />

    <Composition
      id="Subtitles"
      component={SubtitleTrack}
      durationInFrames={timing.totalFrames}
      {...base}
    />

    <Composition
      id="Preview"
      component={Preview}
      durationInFrames={timing.totalFrames}
      {...base}
    />
  </>
);
