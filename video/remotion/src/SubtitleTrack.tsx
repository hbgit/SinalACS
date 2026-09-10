/**
 * Camada única de legendas, com fundo transparente, cobrindo os 5400 frames.
 *
 * O ffmpeg sobrepõe esta camada à linha do tempo já concatenada, por isso ela
 * contém as legendas de TODOS os blocos e as cartelas não trazem texto próprio
 * — do contrário o texto apareceria duas vezes.
 *
 * Posicionamento: nos blocos `device` a legenda fica na coluna à direita do
 * aparelho, nunca sobre a UI. Nos blocos `card` e `terminal` ela fica
 * centralizada na faixa inferior.
 */

import React from 'react';
import { AbsoluteFill, Sequence, interpolate, useCurrentFrame } from 'remotion';
import { stage, theme } from './theme';
import { timing, type BlockKind, type Subtitle } from './timing';

const FADE = 8;

const SubtitleCard: React.FC<{
  subtitle: Subtitle;
  kind: BlockKind;
}> = ({ subtitle, kind }) => {
  const frame = useCurrentFrame();
  const duration = subtitle.outFrame - subtitle.inFrame;

  // Fade de entrada e saída, mais um leve deslocamento vertical na entrada.
  const opacity = interpolate(
    frame,
    [0, FADE, duration - FADE, duration],
    [0, 1, 1, 0],
    { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' },
  );
  const lift = interpolate(frame, [0, FADE], [10, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  const beside = kind === 'device';

  return (
    <AbsoluteFill
      style={{
        justifyContent: beside ? 'center' : 'flex-end',
        alignItems: beside ? 'flex-start' : 'center',
        paddingLeft: beside ? stage.subtitlePane.x + stage.subtitlePane.padding : 0,
        paddingRight: beside ? stage.subtitlePane.padding : 0,
        paddingBottom: beside ? 0 : 96,
      }}
    >
      <div
        style={{
          opacity,
          transform: `translateY(${lift}px)`,
          maxWidth: beside
            ? stage.subtitlePane.width - stage.subtitlePane.padding * 2
            : 1400,
          color: theme.fg,
          fontFamily: theme.font.sans,
          fontSize: theme.size.subtitle,
          lineHeight: 1.35,
          fontWeight: 500,
          textAlign: beside ? 'left' : 'center',
          whiteSpace: 'pre-line',
          // Legibilidade sobre filmagem: sombra em vez de caixa opaca, para
          // não tapar a UI do aparelho.
          textShadow: '0 2px 12px rgba(3,7,18,0.95), 0 0 3px rgba(3,7,18,0.9)',
        }}
      >
        {subtitle.text}
      </div>
    </AbsoluteFill>
  );
};

export const SubtitleTrack: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: 'transparent' }}>
    {timing.blocks.flatMap((block) =>
      block.subtitles.map((subtitle) => (
        <Sequence
          key={`${block.id}-${subtitle.inFrame}`}
          from={subtitle.inFrame}
          durationInFrames={subtitle.outFrame - subtitle.inFrame}
          premountFor={30}
        >
          <SubtitleCard subtitle={subtitle} kind={block.kind} />
        </Sequence>
      )),
    )}
  </AbsoluteFill>
);
