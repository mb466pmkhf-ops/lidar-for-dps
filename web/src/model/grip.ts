// Grip catalogue: flag and frame sizes, and the drapes (rags) that go on them. Port of
// FrameScout/Core/Models/Grip.swift; web/tests/grip.test.ts parses the Swift tables, so keep the
// ids, names and numbers identical on both sides.
//
// Every figure here is an estimate (General crew practice): stops for nets, silks and grids are what
// crews quote, and gaffers measure the real rag on the day. Diffusion gels reuse the unit gel figures
// (LEE datasheets) so a frame of full white cuts the same as a sheet of it on a lamp.
import type { LightFixture, LightKind } from './types';
import { filterByID, filters, type LightFilter } from './photometrics';

export type GripKind = Extract<LightKind, 'bounce' | 'negative' | 'flag' | 'diffusion'>;
export const GRIP_KINDS: GripKind[] = ['bounce', 'negative', 'flag', 'diffusion'];
export const isGrip = (k: LightKind): k is GripKind => (GRIP_KINDS as string[]).includes(k);

export interface GripSize {
  id: string; name: string;
  /** Frame width and height (m). */
  width: number; height: number;
  /** A floppy: a second panel of the same size that opens down from the bottom edge. */
  floppy?: boolean;
  /** Stands a frame this size goes up on: 1, or 2 (one at each side). */
  stands: 1 | 2;
  /** Grip kinds this size is sold as. */
  kinds: GripKind[];
}

const inch = 0.0254, foot = 0.3048;
const r2 = (v: number) => Math.round(v * 100) / 100;

export const GRIP_SIZES: GripSize[] = [
  { id: 'flag-12x18', name: '12×18" flag', width: r2(12 * inch), height: r2(18 * inch), stands: 1, kinds: ['flag', 'negative', 'diffusion'] },
  { id: 'flag-18x24', name: '18×24" flag', width: r2(18 * inch), height: r2(24 * inch), stands: 1, kinds: ['flag', 'negative', 'diffusion'] },
  { id: 'flag-24x36', name: '24×36" flag', width: r2(24 * inch), height: r2(36 * inch), stands: 1, kinds: ['flag', 'negative', 'diffusion'] },
  { id: 'floppy-4x4', name: '4×4 floppy', width: r2(4 * foot), height: r2(4 * foot), floppy: true, stands: 1, kinds: ['flag', 'negative'] },
  { id: 'frame-4x4', name: '4×4 frame', width: r2(4 * foot), height: r2(4 * foot), stands: 1, kinds: ['bounce', 'negative', 'flag', 'diffusion'] },
  { id: 'frame-6x6', name: '6×6 frame', width: r2(6 * foot), height: r2(6 * foot), stands: 1, kinds: ['bounce', 'negative', 'flag', 'diffusion'] },
  { id: 'frame-8x8', name: '8×8 frame', width: r2(8 * foot), height: r2(8 * foot), stands: 2, kinds: ['bounce', 'negative', 'flag', 'diffusion'] },
  { id: 'frame-12x12', name: '12×12 frame', width: r2(12 * foot), height: r2(12 * foot), stands: 2, kinds: ['bounce', 'negative', 'flag', 'diffusion'] },
];

export interface Drape {
  id: string; name: string;
  /** Grip kinds this rag works as; the first is used when it's picked on something else. */
  kinds: GripKind[];
  /** Share of the light that gets through (0…1). */
  transmission: number;
  /** Share of what gets through that is scattered soft (1 = full diffusion; 0 = a net, it only cuts). */
  scatter: number;
  /** Share thrown back off the lit face. */
  reflectance: number;
  /** Colour for drawing (sRGB hex). */
  color: number;
  pattern?: 'checker' | 'net';
  note: string;
}

const crew = 'General crew practice';

export const DRAPES: Drape[] = [
  // Bounce
  { id: 'white-board', name: 'White bounce board', kinds: ['bounce'], transmission: 0, scatter: 0, reflectance: 0.8, color: 0xf4f4f2, note: `${crew}. Foam-core or white card.` },
  { id: 'ultrabounce-white', name: 'Ultrabounce (white side)', kinds: ['bounce'], transmission: 0, scatter: 0, reflectance: 0.85, color: 0xf7f7f5, note: `${crew}. Opaque; the back is black.` },
  { id: 'griffolyn-white', name: 'Griffolyn (white side)', kinds: ['bounce'], transmission: 0, scatter: 0, reflectance: 0.75, color: 0xeeeeea, note: `${crew}. Opaque laminate; the back is black.` },
  { id: 'muslin-bleached', name: 'Bleached muslin', kinds: ['bounce', 'diffusion'], transmission: 0.2, scatter: 1, reflectance: 0.65, color: 0xefede6, note: `${crew}. Soft, slightly lossy bounce; lets some light through.` },
  { id: 'muslin-unbleached', name: 'Unbleached muslin', kinds: ['bounce', 'diffusion'], transmission: 0.15, scatter: 1, reflectance: 0.55, color: 0xe2d6bc, note: `${crew}. Warms the bounce a little (colour not in the readings).` },
  { id: 'checkerboard', name: 'Checkerboard (white/silver)', kinds: ['bounce'], transmission: 0, scatter: 0, reflectance: 0.85, color: 0xdcdcdc, pattern: 'checker', note: `${crew}. Punchier than white; the silver squares add a harder edge the readings treat as soft.` },
  { id: 'silver-lame', name: 'Silver lamé', kinds: ['bounce'], transmission: 0, scatter: 0, reflectance: 0.9, color: 0xc9ccd0, note: `${crew}. Specular and directional; readings treat it as a soft bounce, so the spot it throws is brighter than shown.` },
  { id: 'gold-lame', name: 'Gold lamé', kinds: ['bounce'], transmission: 0, scatter: 0, reflectance: 0.75, color: 0xd4b46a, note: `${crew}. Warms the bounce (colour not in the readings).` },
  // Negative and flags
  { id: 'solid', name: 'Solid (black duvetyne)', kinds: ['flag', 'negative'], transmission: 0, scatter: 0, reflectance: 0.03, color: 0x0a0a0a, note: `${crew}. A little sheen on the lit face.` },
  { id: 'ultrabounce-black', name: 'Ultrabounce (black side)', kinds: ['negative', 'flag'], transmission: 0, scatter: 0, reflectance: 0.05, color: 0x101010, note: `${crew}. Opaque; the white side faces away.` },
  { id: 'griffolyn-black', name: 'Griffolyn (black side)', kinds: ['negative', 'flag'], transmission: 0, scatter: 0, reflectance: 0.05, color: 0x121212, note: `${crew}. Opaque laminate; the white side faces away.` },
  // Diffusion
  { id: 'silk', name: 'Silk', kinds: ['diffusion'], transmission: 0.35, scatter: 1, reflectance: 0.35, color: 0xf5f3ee, note: `${crew}: about 1½ stops.` },
  { id: 'china-silk', name: 'China silk', kinds: ['diffusion'], transmission: 0.6, scatter: 0.75, reflectance: 0.2, color: 0xf6f4ef, note: `${crew}: about ¾ stop, keeps some of the source's shape.` },
  { id: 'grid-quarter', name: '¼ grid cloth', kinds: ['diffusion'], transmission: 0.7, scatter: 0.85, reflectance: 0.2, color: 0xf3f3f1, note: `${crew}: about ½ stop.` },
  { id: 'grid-half', name: '½ grid cloth', kinds: ['diffusion'], transmission: 0.5, scatter: 1, reflectance: 0.3, color: 0xf2f2f0, note: `${crew}: about 1 stop.` },
  { id: 'grid-full', name: 'Full grid cloth', kinds: ['diffusion'], transmission: 0.35, scatter: 1, reflectance: 0.35, color: 0xf0f0ee, note: `${crew}: about 1½ stops.` },
  { id: 'frost-light', name: 'Opal / ¼ frost', kinds: ['diffusion'], transmission: 0.8, scatter: 0.5, reflectance: 0.15, color: 0xf6f6f6, note: 'Same figure as the light diffusion gel (LEE datasheet).' },
  { id: 'white-half', name: '½ white diffusion', kinds: ['diffusion'], transmission: 0.6, scatter: 0.85, reflectance: 0.25, color: 0xf3f3f3, note: 'Same figure as the medium diffusion gel (LEE datasheet).' },
  { id: 'white-full', name: 'Full white diffusion', kinds: ['diffusion'], transmission: 0.36, scatter: 1, reflectance: 0.35, color: 0xf1f1f1, note: 'Same figure as the heavy diffusion gel (LEE datasheet).' },
  { id: 'net-single', name: 'Single net', kinds: ['diffusion', 'flag'], transmission: 0.7, scatter: 0, reflectance: 0, color: 0x1a1a1a, pattern: 'net', note: `${crew}: about ½ stop. Cuts without softening.` },
  { id: 'net-double', name: 'Double net', kinds: ['diffusion', 'flag'], transmission: 0.5, scatter: 0, reflectance: 0, color: 0x141414, pattern: 'net', note: `${crew}: about 1 stop. Cuts without softening.` },
  { id: 'clear', name: 'Clear (gel only)', kinds: ['diffusion'], transmission: 1, scatter: 0, reflectance: 0, color: 0xffffff, note: 'An empty frame for a colour or ND gel.' },
];

/** Ready-made grip in the Add menus (phone and web): size plus rag. */
export interface GripPreset { id: string; label: string; size: string; drape: string }
export const GRIP_PRESETS: GripPreset[] = [
  { id: 'floppy', label: '4×4 floppy', size: 'floppy-4x4', drape: 'solid' },
  { id: 'net-24x36', label: '24×36 net', size: 'flag-24x36', drape: 'net-single' },
  { id: 'silk-6x6', label: '6×6 silk', size: 'frame-6x6', drape: 'silk' },
  { id: 'ultrabounce-8x8', label: '8×8 Ultrabounce', size: 'frame-8x8', drape: 'ultrabounce-white' },
  { id: 'grid-12x12', label: '12×12 grid cloth', size: 'frame-12x12', drape: 'grid-half' },
];

export const gripSizeByID = (id?: string) => (id ? GRIP_SIZES.find(s => s.id === id) : undefined);
export const drapeByID = (id?: string) => (id ? DRAPES.find(d => d.id === id) : undefined);
export const sizesFor = (k: GripKind) => GRIP_SIZES.filter(s => s.kinds.includes(k));
export const drapesFor = (k: GripKind) => DRAPES.filter(d => d.kinds.includes(k));

/** The rag a frame of this kind gets when none is picked: matches the board's built-in optics. */
export const DEFAULT_DRAPE: Record<GripKind, string> = { bounce: 'white-board', negative: 'solid', flag: 'solid', diffusion: 'grid-half' };

/** Gels that can go on a frame: colour correction and ND. Diffusion is the rag itself. */
export const FRAME_GELS: LightFilter[] = filters.filter(f => !f.diffusion);

/** The size, if it was picked and still matches the board. */
export function gripSize(l: LightFixture): GripSize | undefined {
  const s = gripSizeByID(l.gripSizeID as string | undefined);
  return s && Math.abs(s.width - l.width) < 0.01 ? s : undefined;
}

/** The rag on this board, if one was picked and it works as the board's kind. */
export function drape(l: LightFixture): Drape | undefined {
  if (!isGrip(l.kind)) return undefined;
  const d = drapeByID(l.drapeID as string | undefined);
  return d && d.kinds.includes(l.kind) ? d : undefined;
}

/** Frame gels on a diffusion frame. */
export function frameGels(l: LightFixture): LightFilter[] {
  if (l.kind !== 'diffusion') return [];
  return ((l.filterIDs ?? []) as string[]).map(filterByID).filter((f): f is LightFilter => !!f && !f.diffusion);
}

export interface BoardOpticsOverride { transmission: number; scatter: number; reflectance: number }

/** Optics from the picked rag and gels; undefined leaves the board's built-in figures for its kind. */
export function drapeOptics(l: LightFixture): BoardOpticsOverride | undefined {
  const d = drape(l);
  const gels = frameGels(l);
  if (!d && gels.length === 0) return undefined;
  const base = d ?? drapeByID(DEFAULT_DRAPE[l.kind as GripKind])!;
  const gelPass = gels.reduce((t, g) => t * g.transmission, 1);
  return { transmission: base.transmission * gelPass, scatter: base.scatter, reflectance: base.reflectance };
}

/** The board's face: width, and the bottom and top edges (m above the floor). A floppy opened drops
 *  its second panel below the first, so the top edge stays where it was. */
export function gripSpan(l: LightFixture): { width: number; bottom: number; top: number } {
  const h = l.boardHeight ?? (l.kind === 'flag' ? Math.min(l.width, 0.9) : l.width);
  const open = l.floppyOpen === true && gripSize(l)?.floppy === true;
  return { width: l.width, bottom: l.height - h / 2 - (open ? h : 0), top: l.height + h / 2 };
}

/** Name for lists and the plan: "12×12 Silk", "4×4 floppy (open)", "Bounce". */
export function gripLabel(l: LightFixture): string {
  const size = gripSize(l);
  const d = drape(l);
  const parts: string[] = [];
  if (size) parts.push(size.floppy ? size.name + (l.floppyOpen ? ' (open)' : '') : size.name.replace(/ (frame|flag)$/, ''));
  if (d && !(size?.floppy && d.id === 'solid')) parts.push(d.name);
  else if (!d && !size?.floppy) parts.push(KIND_NAME[l.kind as GripKind] ?? '');
  const gels = frameGels(l);
  if (gels.length) parts.push('+ ' + gels.map(g => g.name).join(', '));
  return parts.filter(Boolean).join(' ');
}

const KIND_NAME: Record<GripKind, string> = { bounce: 'Bounce', negative: 'Negative fill', flag: 'Flag', diffusion: 'Diffusion frame' };

/** Applies a size: width, height and the floppy flag. */
export function applyGripSize(l: LightFixture, s: GripSize): LightFixture {
  const n: LightFixture = { ...l, gripSizeID: s.id, width: s.width, boardHeight: s.height };
  if (!s.floppy) delete n.floppyOpen;
  // Keep the frame clear of the floor: the centre at least half the frame (plus a little) up.
  const lowest = s.height / 2 + 0.15;
  if (n.height < lowest) n.height = r2(lowest);
  return renamed(l, n);
}

/** Applies a rag, switching the board's kind when the rag doesn't work as the current one. */
export function applyDrape(l: LightFixture, d: Drape): LightFixture {
  const kind = d.kinds.includes(l.kind as GripKind) ? l.kind : d.kinds[0];
  const n: LightFixture = { ...l, kind, drapeID: d.id };
  if (kind !== 'diffusion') delete n.filterIDs;
  return renamed(l, n);
}

/** Opens or closes a floppy. */
export function setFloppyOpen(l: LightFixture, open: boolean): LightFixture {
  const n: LightFixture = { ...l };
  if (open) n.floppyOpen = true; else delete n.floppyOpen;
  // The flap drops down: lift the floppy so the opened panel clears the floor.
  const span = gripSpan(n);
  if (span.bottom < 0.05) n.height = r2(n.height + 0.05 - span.bottom);
  return renamed(l, n);
}

/** Keeps a name the user typed; replaces one the app made. */
function renamed(before: LightFixture, after: LightFixture): LightFixture {
  const auto = new Set([gripLabel(before), KIND_NAME[before.kind as GripKind]]);
  const base = before.name.replace(/ \d+$/, '');
  return auto.has(base) || auto.has(before.name) ? { ...after, name: gripLabel(after) } : after;
}
