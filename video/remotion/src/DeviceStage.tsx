/**
 * Palco 16:9 para a filmagem em retrato do celular.
 *
 * Usado apenas na composição `Preview` (para conferir enquadramento e legendas
 * antes de existirem as tomadas). Na entrega final quem faz esta composição é o
 * `assemble.sh`, com ffmpeg — ver a Fase 6 do plano.
 *
 * Sem a tomada gravada, mostra um marcador com o nome do arquivo esperado, para
 * que o preview seja legível hoje, sem celular plugado.
 */

import React from 'react';
import { AbsoluteFill } from 'remotion';
import { stage, theme } from './theme';

export const DeviceStage: React.FC<{
  label: string;
  expectedFile: string;
  children?: React.ReactNode;
}> = ({ label, expectedFile, children }) => (
  <AbsoluteFill style={{ backgroundColor: theme.bg }}>
    <div
      style={{
        position: 'absolute',
        left: 0,
        top: 0,
        width: stage.devicePane.width,
        height: stage.height,
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
      }}
    >
      {/* Retrato 1080x2400 reduzido para caber nos 1080 px de altura do palco. */}
      <div
        style={{
          width: (1080 / 2400) * 1000,
          height: 1000,
          borderRadius: 36,
          border: `2px solid ${theme.border}`,
          backgroundColor: theme.bgElevated,
          overflow: 'hidden',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          alignItems: 'center',
          gap: 16,
          padding: 24,
          textAlign: 'center',
        }}
      >
        {children ?? (
          <>
            <div
              style={{
                color: theme.fg,
                fontFamily: theme.font.sans,
                fontSize: 26,
                fontWeight: 600,
              }}
            >
              {label}
            </div>
            <div
              style={{
                color: theme.muted,
                fontFamily: theme.font.mono,
                fontSize: 15,
                wordBreak: 'break-all',
              }}
            >
              {expectedFile}
            </div>
            <div
              style={{
                color: theme.muted,
                fontFamily: theme.font.sans,
                fontSize: 15,
                marginTop: 8,
              }}
            >
              tomada ainda não gravada
            </div>
          </>
        )}
      </div>
    </div>
  </AbsoluteFill>
);
