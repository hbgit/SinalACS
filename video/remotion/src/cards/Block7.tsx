/**
 * Bloco 7 — O pedido (2:45–3:00).
 *
 * Cartela final. Corresponde ao critério de aceite M3.5 do PRD.
 * Termina em silêncio: a última legenda sai em 5340 e esta cartela fica
 * sozinha no ar pelos 2 s finais — não acrescentar movimento no fim.
 */

import React from 'react';
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion';
import { theme } from '../theme';
import { blockById } from '../timing';

export const Block7: React.FC = () => {
  const block = blockById(7);
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const ask = block.ask!;

  return (
    <AbsoluteFill
      style={{
        backgroundColor: theme.bg,
        justifyContent: 'center',
        alignItems: 'center',
        padding: '0 130px',
        gap: 64,
      }}
    >
      <div style={{ display: 'flex', gap: 90, justifyContent: 'center' }}>
        {ask.map((item, index) => {
          const enter = spring({
            frame: frame - 30 - index * 12,
            fps,
            config: { damping: 200 },
            durationInFrames: 20,
          });
          return (
            <div
              key={item}
              style={{
                opacity: enter,
                transform: `translateY(${interpolate(enter, [0, 1], [24, 0])}px)`,
                color: theme.fg,
                fontFamily: theme.font.sans,
                fontSize: theme.size.hero,
                fontWeight: 700,
                letterSpacing: '-0.02em',
              }}
            >
              {item}
            </div>
          );
        })}
      </div>

      <div
        style={{
          opacity: interpolate(frame, [90, 115], [0, 1], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          }),
          color: theme.muted,
          fontFamily: theme.font.sans,
          fontSize: theme.size.caption,
          letterSpacing: '0.1em',
          textTransform: 'uppercase',
          fontWeight: 600,
        }}
      >
        SinalACS · Piloto de atenção primária
      </div>
    </AbsoluteFill>
  );
};
