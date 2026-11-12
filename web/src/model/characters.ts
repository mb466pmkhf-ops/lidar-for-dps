// Eye height from FigureProportions (Characters.swift).
import type { CharacterType, HairStyle, PrevisCharacter } from './types';

export const characterTypes: CharacterType[] = ['man', 'woman', 'universal', 'girl', 'boy'];
export const characterLabel = (t: CharacterType) => t[0].toUpperCase() + t.slice(1);
export const characterDefaults: Record<CharacterType, number> = { man: 1.78, woman: 1.65, universal: 1.71, girl: 1.30, boy: 1.34 };
export const isChild = (t: CharacterType) => t === 'girl' || t === 'boy';
/** Body shape between broader shoulders / narrower hips (0) and narrower shoulders / wider hips (1). Universal sits halfway. */
export const shapeBlend: Record<CharacterType, number> = { man: 0, woman: 1, universal: 0.5, girl: 0.6, boy: 0 };

export const hairStyles: { id: HairStyle; label: string }[] = [
  { id: 'cropped', label: 'Cropped' }, { id: 'short', label: 'Short' }, { id: 'long', label: 'Long' }, { id: 'tied', label: 'Tied back' }, { id: 'bald', label: 'None' },
];
export const defaultHair: Record<CharacterType, HairStyle> = { man: 'short', woman: 'long', universal: 'cropped', girl: 'tied', boy: 'short' };
export const hairOf = (c: PrevisCharacter): HairStyle => (c.hair && hairStyles.some(h => h.id === c.hair) ? c.hair : defaultHair[c.type] ?? 'short');
export const skinTones = ['Very light', 'Light', 'Medium', 'Olive / tan', 'Brown', 'Deep'];
export const skinRGB = ['#f5d6c2', '#e8bd9e', '#cc9975', '#ab7a57', '#80573d', '#523626'];
const reflectance = [0.45, 0.38, 0.30, 0.22, 0.15, 0.09];
export const skinStopsFromGrey = (tone: number) => Math.log2(reflectance[Math.min(Math.max(tone, 1), 6) - 1] / 0.18);

/** Seat height of a sitting person: the sofa, chair or bed they sit on (placement.ts), else a usual chair. */
export const seatHeightOf = (c: PrevisCharacter) => c.seatHeight ?? Math.min(0.45, c.height * 0.52 * 0.5);

export function eyeHeight(c: PrevisCharacter): number {
  const h = c.height;
  const child = isChild(c.type);
  const head = h / (child ? 6 : 7.5);
  const standingHip = h * 0.52;
  const sitting = c.posture === 'sitting';
  const drop = sitting ? standingHip - seatHeightOf(c) : 0;
  return h - head * 0.48 - drop;
}
