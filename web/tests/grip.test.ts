// Grip catalogue (web/src/model/grip.ts): flag and frame sizes, rags, frame gels, floppies, tilted
// overheads. The tables must match FrameScout/Core/Models/Grip.swift exactly.
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  DRAPES, GRIP_PRESETS, GRIP_SIZES, applyDrape, applyGripSize, drapeByID, drapeOptics, gripLabel, gripSizeByID, gripSpan, setFloppyOpen,
} from '../src/model/grip';
import { automaticLightSupport, gripStandCount } from '../src/model/rigging';
import { buildScene, direction, reading, vec } from '../src/model/calculator';
import { newLight } from '../src/model/factory';
import type { LightFixture, LightKind } from '../src/model/types';

const swift = readFileSync(new URL('../../FrameScout/Core/Models/Grip.swift', import.meta.url), 'utf8');
const kinds = (s: string) => s.split(',').map(k => k.trim().replace(/^\./, ''));

describe('grip tables match Swift', () => {
  it('sizes', () => {
    const sw = [...swift.matchAll(/GripSize\(id: "([^"]+)", name: "((?:[^"\\]|\\.)*)", width: ([\d.]+), height: ([\d.]+),( floppy: true,)? stands: (\d), kinds: \[([^\]]+)\]\)/g)]
      .map(m => ({ id: m[1], name: m[2].replace(/\\"/g, '"'), width: Number(m[3]), height: Number(m[4]), floppy: !!m[5], stands: Number(m[6]), kinds: kinds(m[7]) }));
    expect(sw).toEqual(GRIP_SIZES.map(s => ({ id: s.id, name: s.name, width: s.width, height: s.height, floppy: !!s.floppy, stands: s.stands, kinds: s.kinds })));
  });

  it('rags', () => {
    const sw = [...swift.matchAll(/Drape\(id: "([^"]+)", name: "([^"]+)", kinds: \[([^\]]+)\], transmission: ([\d.]+), scatter: ([\d.]+), reflectance: ([\d.]+), color: 0x([0-9a-f]+),(?: pattern: \.(\w+),)? note: "((?:[^"\\]|\\.)*)"\)/g)]
      .map(m => ({ id: m[1], name: m[2], kinds: kinds(m[3]), transmission: Number(m[4]), scatter: Number(m[5]), reflectance: Number(m[6]), color: parseInt(m[7], 16), pattern: m[8], note: m[9] }));
    expect(sw).toEqual(DRAPES.map(d => ({ id: d.id, name: d.name, kinds: d.kinds, transmission: d.transmission, scatter: d.scatter, reflectance: d.reflectance, color: d.color, pattern: d.pattern, note: d.note })));
  });

  it('add-menu presets', () => {
    const sw = [...swift.matchAll(/Preset\(id: "([^"]+)", label: "([^"]+)", size: "([^"]+)", drape: "([^"]+)"\)/g)].map(m => ({ id: m[1], label: m[2], size: m[3], drape: m[4] }));
    expect(sw).toEqual(GRIP_PRESETS);
    for (const p of GRIP_PRESETS) {
      expect(gripSizeByID(p.size)).toBeDefined();
      expect(gripSizeByID(p.size)!.kinds).toContain(drapeByID(p.drape)!.kinds[0]);
    }
  });

  it('every number is a sensible share and every rag says where its figure comes from', () => {
    for (const d of DRAPES) {
      for (const x of [d.transmission, d.scatter, d.reflectance]) { expect(x).toBeGreaterThanOrEqual(0); expect(x).toBeLessThanOrEqual(1); }
      expect(d.transmission + d.reflectance).toBeLessThanOrEqual(1);
      expect(d.note).toMatch(/General crew practice|LEE datasheet|gel/);
    }
  });
});

const grip = (kind: LightKind, patch: Partial<LightFixture> = {}): LightFixture => ({ ...newLight(kind, { x: 0, z: 1.5 }, 180), height: 1.5, ...patch });

describe('sizes, rags and floppies', () => {
  it('a size sets the frame and names it; a typed name is kept', () => {
    const f = applyGripSize(grip('diffusion'), gripSizeByID('frame-12x12')!);
    expect(f.width).toBeCloseTo(3.66, 2);
    expect(f.boardHeight).toBeCloseTo(3.66, 2);
    expect(f.height).toBeGreaterThanOrEqual(3.66 / 2 + 0.15 - 1e-9); // lifted clear of the floor
    expect(f.name).toBe('12×12 Diffusion frame');
    const silk = applyDrape(f, drapeByID('silk')!);
    expect(silk.name).toBe('12×12 Silk');
    const mine = applyDrape({ ...f, name: 'Overhead A' }, drapeByID('silk')!);
    expect(mine.name).toBe('Overhead A');
  });

  it('picking a rag that does not work as the current kind switches the kind', () => {
    const b = applyDrape(grip('diffusion'), drapeByID('ultrabounce-white')!);
    expect(b.kind).toBe('bounce');
    const neg = applyDrape(grip('bounce'), drapeByID('ultrabounce-black')!);
    expect(neg.kind).toBe('negative');
  });

  it('a 4×4 floppy opens to 4×8, downwards from its top edge', () => {
    const closed = applyGripSize(grip('flag', { height: 2 }), gripSizeByID('floppy-4x4')!);
    const open = setFloppyOpen(closed, true);
    const a = gripSpan(closed), b = gripSpan(open);
    expect(b.top).toBeCloseTo(a.top, 9);
    expect(b.top - b.bottom).toBeCloseTo(2 * (a.top - a.bottom), 9);
    expect(open.name).toBe('4×4 floppy (open)');
    expect(gripSpan({ ...open, gripSizeID: 'frame-4x4' }).bottom).toBeCloseTo(a.bottom, 9); // only floppies open
  });

  it('6×6 and up go on wind-ups; 8×8 and 12×12 on two', () => {
    const at = (id: string) => applyGripSize(grip('bounce'), gripSizeByID(id)!);
    expect(automaticLightSupport(at('frame-4x4'))).toBe('comboStand');
    expect(automaticLightSupport(at('frame-6x6'))).toBe('windUp');
    expect(gripStandCount(at('frame-6x6'))).toBe(1);
    expect(gripStandCount(at('frame-8x8'))).toBe(2);
    expect(gripStandCount(at('frame-12x12'))).toBe(2);
  });

  it('frame gels multiply into the frame and show in the name', () => {
    const f = applyDrape(grip('diffusion'), drapeByID('grid-half')!);
    const gelled = { ...f, filterIDs: ['cto-half'] };
    expect(drapeOptics(gelled)!.transmission).toBeCloseTo(0.5 * 0.7, 9);
    expect(gripLabel(gelled)).toBe('½ grid cloth + ½ CTO');
    expect(drapeOptics({ ...applyDrape(grip('diffusion'), drapeByID('clear')!), filterIDs: ['nd-6'] })!.transmission).toBeCloseTo(0.25, 9);
  });
});

describe('rags and tilt in the light maths', () => {
  // A narrow unit 3 m from a meter, the board half way (same layout as the grip behaviour tests).
  const spot = () => { const l = newLight('fresnel', { x: 0, z: 3 }); l.pan = 0; l.tilt = 0; l.height = 1.5; l.beamAngle = 12; return l; };
  const board = (rag: string) => applyDrape(applyGripSize(grip('diffusion', { width: 1.2, boardHeight: 1.2 }), gripSizeByID('frame-4x4')!), drapeByID(rag)!);
  const meter = vec(0, 1.5, 0), facingLight = direction(180, 0);
  const open = () => reading(meter, facingLight, buildScene([spot()])).lux;

  it('a net only cuts: the straight beam drops by its stop and nothing is scattered', () => {
    const net = reading(meter, facingLight, buildScene([spot(), board('net-single')]));
    expect(net.lux / open()).toBeCloseTo(0.7, 6);
    expect(net.contributions.some(c => c.viaBounce)).toBe(false);
    const dbl = reading(meter, facingLight, buildScene([spot(), board('net-double')])).lux;
    expect(dbl / open()).toBeCloseTo(0.5, 6);
  });

  it('a silk passes less than ½ grid, and all of it soft', () => {
    const silk = reading(meter, facingLight, buildScene([spot(), board('silk')]));
    const half = reading(meter, facingLight, buildScene([spot(), board('grid-half')]));
    expect(silk.lux).toBeLessThan(half.lux);
    expect(silk.contributions.every(c => c.viaBounce)).toBe(true);
  });

  it('a rag-less board keeps the built-in figures', () => {
    const plain = grip('diffusion', { width: 1.2, boardHeight: 1.2 });
    expect(drapeOptics(plain)).toBeUndefined();
  });

  it('a 12×12 flown flat overhead cuts a top light, and stops cutting when tilted out of the way', () => {
    const sun = newLight('fresnel', { x: 0, z: 0 }); sun.height = 5; sun.tilt = -90; sun.beamAngle = 30;
    const person = vec(0, 1.6, 0), up = vec(0, 1, 0);
    const solid = (tilt: number) => applyDrape(applyGripSize({ ...newLight('flag', { x: 0, z: 0 }, 0), height: 3.2, tilt }, gripSizeByID('frame-12x12')!), drapeByID('solid')!);
    const bare = reading(person, up, buildScene([sun])).lux;
    expect(bare).toBeGreaterThan(0);
    expect(reading(person, up, buildScene([sun, solid(90)])).lux).toBe(0);
    // Upright, the same frame stands edge-on to a light straight above it: nothing in the way.
    expect(reading(person, up, buildScene([sun, solid(0)])).lux).toBeCloseTo(bare, 6);
  });

  it('an open floppy cuts lower than a closed one', () => {
    const spotLow = spot(); spotLow.height = 0.6;
    const low = vec(0, 0.6, 0);
    const floppy = (open: boolean) => setFloppyOpen(applyGripSize(grip('flag', { height: 1.9 }), gripSizeByID('floppy-4x4')!), open);
    expect(reading(low, facingLight, buildScene([spotLow, floppy(false)])).lux).toBeGreaterThan(0);
    expect(reading(low, facingLight, buildScene([spotLow, floppy(true)])).lux).toBe(0);
  });
});
