/**
 * Acesso tipado ao roteiro cronometrado.
 *
 * `video/roteiro.timing.json` é a fonte única de verdade de tempo: as cartelas,
 * a camada de legendas e o `assemble.sh` leem todos o mesmo arquivo, para que
 * nenhum timecode seja digitado duas vezes.
 */

import raw from '../../roteiro.timing.json';

export type BlockKind = 'card' | 'device' | 'terminal';

export type Subtitle = {
  text: string;
  inFrame: number;
  outFrame: number;
};

export type Block = {
  id: number;
  title: string;
  timecode: string;
  startFrame: number;
  endFrame: number;
  kind: BlockKind;
  notes?: string;
  source?: string;
  subtitles: Subtitle[];
  hero?: { text: string; inFrame: number; outFrame: number };
  columns?: { label: string; verb: string; inFrame: number; highlight: boolean }[];
  capacityLabel?: string;
  capacity?: string[];
  phases?: { label: string; done: boolean }[];
  ask?: string[];
  highlights?: string[];
  hold?: { atFrame: number; freezeFrames: number; zoom: number };
};

export type Timing = {
  fps: number;
  width: number;
  height: number;
  totalFrames: number;
  blocks: Block[];
  subtitleRules: {
    maxLines: number;
    maxCharsPerLine: number;
    minFramesOnScreen: number;
  };
};

export const timing = raw as unknown as Timing;

export const blockById = (id: number): Block => {
  const block = timing.blocks.find((b) => b.id === id);
  if (!block) {
    throw new Error(`Bloco ${id} não existe em roteiro.timing.json`);
  }
  return block;
};

export const blockDuration = (id: number): number => {
  const block = blockById(id);
  return block.endFrame - block.startFrame;
};
