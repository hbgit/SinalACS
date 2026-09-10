/**
 * Bloco 6 — Escala e roadmap (2:25–2:45).
 *
 * HONESTIDADE (guardrail do roteiro): os números são dimensionamento do PRD,
 * não base instalada. O rótulo "Capacidade projetada por 2 UBS" fica em tela
 * junto dos números, não em nota de rodapé — é o que impede a banca de ler
 * 5.000 pacientes como usuários existentes.
 */

import React from 'react';
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion';
import { theme } from '../theme';
import { blockById } from '../timing';

export const Block6: React.FC = () => {
  const block = blockById(6);
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const capacity = block.capacity!;
  const phases = block.phases!;

  const labelOpacity = interpolate(frame, [0, 18], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill
      style={{
        backgroundColor: theme.bg,
        justifyContent: 'center',
        alignItems: 'center',
        padding: '0 130px',
        gap: 72,
      }}
    >
      <div style={{ textAlign: 'center', opacity: labelOpacity }}>
        <div
          style={{
            color: theme.muted,
            fontFamily: theme.font.sans,
            fontSize: theme.size.eyebrow,
            fontWeight: 600,
            letterSpacing: '0.14em',
            textTransform: 'uppercase',
            marginBottom: 34,
          }}
        >
          {block.capacityLabel}
        </div>

        <div style={{ display: 'flex', gap: 80, justifyContent: 'center' }}>
          {capacity.map((item, index) => {
            const enter = spring({
              frame: frame - 20 - index * 10,
              fps,
              config: { damping: 200 },
              durationInFrames: 18,
            });
            return (
              <div
                key={item}
                style={{
                  opacity: enter,
                  transform: `translateY(${interpolate(enter, [0, 1], [20, 0])}px)`,
                  color: theme.fg,
                  fontFamily: theme.font.sans,
                  fontSize: theme.size.title,
                  fontWeight: 700,
                  letterSpacing: '-0.01em',
                }}
              >
                {item}
              </div>
            );
          })}
        </div>
      </div>

      <div style={{ display: 'flex', gap: 24, width: '100%' }}>
        {phases.map((phase, index) => {
          const enter = spring({
            frame: frame - 170 - index * 14,
            fps,
            config: { damping: 200 },
            durationInFrames: 20,
          });
          const fill = phase.done ? enter : 0;
          return (
            <div key={phase.label} style={{ flex: 1, opacity: interpolate(enter, [0, 0.3], [0, 1], { extrapolateRight: 'clamp' }) }}>
              <div
                style={{
                  height: 10,
                  borderRadius: 999,
                  backgroundColor: theme.border,
                  overflow: 'hidden',
                  marginBottom: 20,
                }}
              >
                <div
                  style={{
                    width: `${fill * 100}%`,
                    height: '100%',
                    backgroundColor: theme.accent,
                  }}
                />
              </div>
              <div
                style={{
                  color: phase.done ? theme.fg : theme.muted,
                  fontFamily: theme.font.sans,
                  fontSize: theme.size.caption,
                  fontWeight: phase.done ? 600 : 400,
                }}
              >
                {phase.label}
                {phase.done ? ' ✓' : ''}
              </div>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
