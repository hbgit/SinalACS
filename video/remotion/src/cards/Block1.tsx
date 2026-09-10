/**
 * Bloco 1 — O problema (0:00–0:20).
 *
 * Abre em silêncio. A frase-chave entra no frame 330 (local: 330 - 0).
 *
 * INVARIANTE: nenhum vermelho neste bloco. A cor só passa a significar
 * gravidade a partir do bloco 3 — usar vermelho aqui a esvaziaria de sentido
 * antes de a triagem lhe dar significado.
 */

import React from 'react';
import { AbsoluteFill, interpolate, useCurrentFrame } from 'remotion';
import { theme } from '../theme';
import { blockById } from '../timing';

export const Block1: React.FC = () => {
  const block = blockById(1);
  const frame = useCurrentFrame();
  const hero = block.hero!;
  const heroLocal = hero.inFrame - block.startFrame;

  const opacity = interpolate(frame, [heroLocal, heroLocal + 20], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  // Deriva lenta: dá vida à cartela sem chamar atenção para si.
  const drift = interpolate(frame, [heroLocal, block.endFrame - block.startFrame], [14, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill
      style={{
        backgroundColor: theme.bg,
        justifyContent: 'center',
        alignItems: 'center',
        padding: 140,
      }}
    >
      <div
        style={{
          opacity,
          transform: `translateY(${drift}px)`,
          color: theme.fg,
          fontFamily: theme.font.sans,
          fontSize: theme.size.hero,
          fontWeight: 700,
          lineHeight: 1.15,
          letterSpacing: '-0.02em',
          textAlign: 'center',
          maxWidth: 1400,
        }}
      >
        {hero.text}
      </div>
    </AbsoluteFill>
  );
};
