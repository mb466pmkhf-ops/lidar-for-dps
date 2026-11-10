// Eye height from FigureProportions (Characters.swift).
import type { CharacterType, PrevisCharacter } from './types';

export const characterDefaults: Record<CharacterType, number> = { man: 1.78, woman: 1.65, girl: 1.30, boy: 1.34 };
export const skinTones = ['Very light', 'Light', 'Medium', 'Olive / tan', 'Brown', 'Deep'];
export const skinRGB = ['#f5d6c2', '#e8bd9e', '#cc9975', '#ab7a57', '#80573d', '#523626'];
const reflectance = [0.45, 0.38, 0.30, 0.22, 0.15, 0.09];
export const skinStopsFromGrey = (tone: number) => Math.log2(reflectance[Math.min(Math.max(tone, 1), 6) - 1] / 0.18);

export function eyeHeight(c: PrevisCharacter): number {
  const h = c.height;
  const child = c.type === 'girl' || c.type === 'boy';
  const head = h / (child ? 6 : 7.5);
  const standingHip = h * 0.52;
  const sitting = c.posture === 'sitting';
  const seat = sitting ? Math.min(0.45, standingHip * 0.5) : 0;
  const drop = sitting ? standingHip - seat : 0;
  return h - head * 0.48 - drop;
}
