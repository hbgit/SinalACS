/**
 * Linguagem visual do vídeo do sponsor.
 *
 * Espelha o tema escuro dos apps Flutter (spec/ui_design.md) para que as
 * cartelas e a filmagem do celular pareçam a mesma peça.
 *
 * INVARIANTE DO PROJETO: vermelho, amarelo e verde são sinal clínico, nunca
 * decoração. Só podem aparecer representando RiskLevel. O bloco 1 não pode
 * usar vermelho de forma alguma — a cor só passa a significar gravidade a
 * partir do bloco 3, quando a triagem da Maria a introduz.
 */

export const theme = {
  bg: '#030712',
  bgElevated: '#0b1220',
  fg: '#e5e7eb',
  muted: '#94a3b8',
  border: '#1e293b',
  accent: '#38bdf8',

  /** Só para significar gravidade. Ver invariante acima. */
  risk: {
    red: '#ef4444',
    yellow: '#f59e0b',
    green: '#22c55e',
  },

  font: {
    sans: '"Inter", "Segoe UI", system-ui, -apple-system, sans-serif',
    mono: '"JetBrains Mono", "Fira Code", ui-monospace, monospace',
  },

  size: {
    hero: 96,
    title: 56,
    body: 34,
    subtitle: 38,
    caption: 24,
    eyebrow: 22,
  },
} as const;

/** Palco 16:9. A filmagem do celular é retrato e entra centralizada. */
export const stage = {
  width: 1920,
  height: 1080,
  fps: 30,
  /**
   * Coluna esquerda: aparelho. Coluna direita: legendas dos blocos "device".
   * Um retrato 9:20 em um palco 16:9 sempre sobra espaço; a divisão dá ao
   * aparelho só a largura de que ele precisa e devolve o resto à legenda.
   */
  devicePane: { x: 0, width: 880 },
  subtitlePane: { x: 880, width: 1040, padding: 80 },
} as const;
