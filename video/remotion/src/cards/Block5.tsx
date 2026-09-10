/**
 * Bloco 5 — A prova técnica (2:05–2:25).
 *
 * Renderização da saída REAL de `video/rpc_demo/bin/red_alert_cycle.dart`,
 * capturada em `video/rpc_demo/captured/cycle.txt` e `mqtt.txt` contra a stack
 * do docker compose, e convertida em `block5Data.ts` por um script. Não é uma
 * captura de tela: é o texto verdadeiro, apresentado com tipografia legível
 * para projeção.
 *
 * HONESTIDADE: a correspondência auditável é o `alertId` — o mesmo UUID aparece
 * na saída do ciclo e no payload MQTT, porque vieram da mesma execução. Os .txt
 * ficam versionados para quem quiser conferir.
 *
 * DESVIO DELIBERADO DO ROTEIRO: o roteiro pede realce **amarelo** sobre
 * `published: true` e a linha de ACK. Uso o azul de acento: o payload em quadro
 * contém `"risk_level":"red"`, e um realce amarelo ao lado disso convidaria a
 * ler a cor como classificação de risco, contra a invariante do projeto.
 */

import React from 'react';
import { AbsoluteFill, interpolate, useCurrentFrame } from 'remotion';
import { cycleLines, mqttPayload, mqttTopic } from '../block5Data';
import { theme } from '../theme';
import { blockById } from '../timing';

/** Linhas destacadas: são as três afirmações que o bloco precisa provar. */
const isHighlighted = (line: string) =>
  line.includes('published: true') ||
  line.includes('acknowledged: true') ||
  line.includes('mesmo alertId');

const REVEAL_START = 30;
const FRAMES_PER_LINE = 13;

/** O painel MQTT entra quando o ciclo anuncia a publicação. */
const MQTT_LINE = cycleLines.findIndex((l) => l.includes('published: true'));
const MQTT_AT = REVEAL_START + (MQTT_LINE + 1) * FRAMES_PER_LINE;

const Pane: React.FC<{
  title: string;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ title, children, style }) => (
  <div
    style={{
      background: theme.bgElevated,
      border: `1px solid ${theme.border}`,
      borderRadius: 14,
      display: 'flex',
      flexDirection: 'column',
      overflow: 'hidden',
      ...style,
    }}
  >
    <div
      style={{
        padding: '12px 20px',
        borderBottom: `1px solid ${theme.border}`,
        color: theme.muted,
        fontFamily: theme.font.mono,
        fontSize: 17,
        letterSpacing: '0.04em',
      }}
    >
      {title}
    </div>
    <div style={{ padding: '18px 24px', flex: 1, overflow: 'hidden' }}>{children}</div>
  </div>
);

export const Block5: React.FC = () => {
  const block = blockById(5);
  const frame = useCurrentFrame();
  const duration = block.endFrame - block.startFrame;

  const visibleLines = Math.max(
    0,
    Math.floor((frame - REVEAL_START) / FRAMES_PER_LINE) + 1,
  );

  const mqttOpacity = interpolate(frame, [MQTT_AT, MQTT_AT + 18], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Saída suave no fim, para o corte seco para a cartela do bloco 6.
  const fade = interpolate(frame, [duration - 12, duration], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill
      style={{
        backgroundColor: theme.bg,
        padding: 56,
        gap: 20,
        flexDirection: 'row',
        opacity: fade,
      }}
    >
      <Pane title="$ dart run bin/red_alert_cycle.dart" style={{ flex: 1.35 }}>
        {cycleLines.slice(0, visibleLines).map((line, i) => (
          <div
            key={i}
            style={{
              fontFamily: theme.font.mono,
              fontSize: 22,
              lineHeight: 1.45,
              whiteSpace: 'pre',
              color: isHighlighted(line) ? theme.accent : theme.fg,
              fontWeight: isHighlighted(line) ? 700 : 400,
              background: isHighlighted(line) ? 'rgba(56,189,248,0.12)' : 'transparent',
              borderRadius: 4,
            }}
          >
            {line || ' '}
          </div>
        ))}
      </Pane>

      <Pane title="mosquitto_sub · TLS 8883" style={{ flex: 1, opacity: mqttOpacity }}>
        <div
          style={{
            fontFamily: theme.font.mono,
            fontSize: 17,
            color: theme.accent,
            wordBreak: 'break-all',
            marginBottom: 14,
            lineHeight: 1.4,
          }}
        >
          {mqttTopic}
        </div>
        <div
          style={{
            fontFamily: theme.font.mono,
            fontSize: 19,
            lineHeight: 1.5,
            color: theme.fg,
            whiteSpace: 'pre',
          }}
        >
          {mqttPayload}
        </div>
      </Pane>
    </AbsoluteFill>
  );
};
