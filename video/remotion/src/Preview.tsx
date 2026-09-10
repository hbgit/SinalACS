/**
 * Montagem completa de 180 s para conferência.
 *
 * Serve para validar ritmo, timecodes e legibilidade das legendas ANTES de
 * existirem as tomadas do celular e do terminal — os blocos `device` e
 * `terminal` aparecem como marcadores. A entrega final não sai daqui: o
 * `assemble.sh` compõe as tomadas reais com as cartelas e a camada de legendas.
 */

import React from 'react';
import { AbsoluteFill, Sequence } from 'remotion';
import { Block1 } from './cards/Block1';
import { Block2 } from './cards/Block2';
import { Block5 } from './cards/Block5';
import { Block6 } from './cards/Block6';
import { Block7 } from './cards/Block7';
import { DeviceStage } from './DeviceStage';
import { SubtitleTrack } from './SubtitleTrack';
import { theme } from './theme';
import { timing, type Block } from './timing';

const cards: Record<number, React.FC> = {
  1: Block1,
  2: Block2,
  5: Block5,
  6: Block6,
  7: Block7,
};

const BlockBody: React.FC<{ block: Block }> = ({ block }) => {
  const Card = cards[block.id];
  if (Card) {
    return <Card />;
  }
  return (
    <DeviceStage
      label={block.title}
      expectedFile={block.source ?? '(sem fonte definida)'}
    />
  );
};

export const Preview: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: theme.bg }}>
    {timing.blocks.map((block) => (
      <Sequence
        key={block.id}
        from={block.startFrame}
        durationInFrames={block.endFrame - block.startFrame}
        premountFor={30}
      >
        <BlockBody block={block} />
      </Sequence>
    ))}

    {/* A camada de legendas cobre a linha do tempo inteira, por cima de tudo. */}
    <SubtitleTrack />
  </AbsoluteFill>
);
