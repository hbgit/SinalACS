/**
 * Bloco 2 — A solução e o moat (0:20–0:35).
 *
 * Três colunas entram uma a uma; a terceira (SinalACS) fica destacada.
 * O destaque usa o azul de acento, não vermelho: aqui a cor é hierarquia
 * visual, e as cores de risco estão reservadas para gravidade clínica.
 */

import React from 'react';
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion';
import { theme } from '../theme';
import { blockById } from '../timing';

const Column: React.FC<{
  label: string;
  verb: string;
  highlight: boolean;
  localIn: number;
}> = ({ label, verb, highlight, localIn }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const enter = spring({
    frame: frame - localIn,
    fps,
    config: { damping: 200 },
    durationInFrames: 20,
  });
  const opacity = interpolate(enter, [0, 1], [0, 1]);
  const lift = interpolate(enter, [0, 1], [28, 0]);

  return (
    <div
      style={{
        opacity,
        transform: `translateY(${lift}px)`,
        flex: 1,
        padding: '52px 40px',
        borderRadius: 20,
        backgroundColor: highlight ? theme.bgElevated : 'transparent',
        border: `1px solid ${highlight ? theme.accent : theme.border}`,
        display: 'flex',
        flexDirection: 'column',
        gap: 18,
        alignItems: 'center',
        textAlign: 'center',
      }}
    >
      <div
        style={{
          color: highlight ? theme.accent : theme.fg,
          fontFamily: theme.font.sans,
          fontSize: theme.size.title,
          fontWeight: 700,
          letterSpacing: '-0.01em',
        }}
      >
        {label}
      </div>
      <div
        style={{
          color: theme.muted,
          fontFamily: theme.font.sans,
          fontSize: theme.size.body,
          fontWeight: 400,
        }}
      >
        {verb}
      </div>
    </div>
  );
};

export const Block2: React.FC = () => {
  const block = blockById(2);
  const columns = block.columns!;

  return (
    <AbsoluteFill
      style={{
        backgroundColor: theme.bg,
        justifyContent: 'center',
        alignItems: 'center',
        padding: '0 130px',
      }}
    >
      <div style={{ display: 'flex', gap: 32, width: '100%', alignItems: 'stretch' }}>
        {columns.map((column) => (
          <Column
            key={column.label}
            label={column.label}
            verb={column.verb}
            highlight={column.highlight}
            localIn={column.inFrame - block.startFrame}
          />
        ))}
      </div>
    </AbsoluteFill>
  );
};
