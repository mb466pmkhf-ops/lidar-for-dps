import { describe, expect, it } from 'vitest';
import { buildRoomPlan } from '../src/model/room';
import {
  FURNITURE_PRESETS, OPENING_PRESETS, addObject, addSegment, backOntoWall, furniturePreset, openingPreset, placeFurniture, placeOpening,
  removeSegment, replaceSegment, resizeOpening, setOpeningHeight, slideOpening, turnObject,
} from '../src/model/setPieces';
import { mergeDocuments } from '../src/sync/merge';
import { upperKeys } from '../src/sync/merge';

// A 6 × 4 m box, 2.7 m high, no windows or door: walls at x = ±3 and z = ±2.
const room = () => buildRoomPlan({ shape: 'box', length: 6, width: 4, ceiling: 2.7, windows: 0, door: false });
const len = (s: { a: { x: number; z: number }; b: { x: number; z: number } }) => Math.hypot(s.b.x - s.a.x, s.b.z - s.a.z);

describe('set pieces by hand', () => {
  it('puts a window in the wall nearest the click, at its typical size', () => {
    const w = placeOpening(room(), { x: 1, z: -1.6 }, openingPreset('window')!)!;
    expect(w.kind).toBe('window');
    expect(w.a.z).toBe(-2); expect(w.b.z).toBe(-2);
    expect(len(w)).toBeCloseTo(1.2);
    expect((w.a.x + w.b.x) / 2).toBeCloseTo(1);
    expect(w.bottom).toBe(0.85); expect(w.height).toBe(1.4);
    expect(w.byHand).toBe(true);
  });

  it('refuses a door far from any wall', () => {
    expect(placeOpening(room(), { x: 0, z: 0 }, openingPreset('door')!)).toBeUndefined();
    expect(placeOpening(undefined, { x: 0, z: 0 }, openingPreset('door')!)).toBeUndefined();
  });

  it('keeps openings inside the wall: ends and height', () => {
    const d = placeOpening(room(), { x: 2.95, z: 1.9 }, openingPreset('double-door')!)!;
    // On the bottom wall (z = 2) or the right wall (x = 3); either way inside its ends.
    const xs = [d.a.x, d.b.x], zs = [d.a.z, d.b.z];
    expect(Math.max(...xs)).toBeLessThanOrEqual(3); expect(Math.max(...zs)).toBeLessThanOrEqual(2);
    const low = buildRoomPlan({ shape: 'box', length: 6, width: 4, ceiling: 2.0, windows: 0, door: false });
    const t = placeOpening(low, { x: 0, z: -2 }, openingPreset('tall-window')!)!;
    expect(t.bottom + t.height).toBeLessThanOrEqual(1.95 + 1e-9);
  });

  it('slides an opening along and onto another wall, same width', () => {
    const plan = room();
    const w = placeOpening(plan, { x: 0, z: -2 }, openingPreset('window')!)!;
    const moved = slideOpening(plan, w, { x: -2, z: -2.2 });
    expect((moved.a.x + moved.b.x) / 2).toBeCloseTo(-2); expect(moved.a.z).toBe(-2);
    const other = slideOpening(plan, w, { x: 2.9, z: 0.5 });
    expect(other.a.x).toBe(3); expect(len(other)).toBeCloseTo(1.2);
    expect(other.id).toBe(w.id);
  });

  it('resizes about the centre and keeps the sill under the top', () => {
    const plan = room();
    const w = placeOpening(plan, { x: 0, z: -2 }, openingPreset('window')!)!;
    const wide = resizeOpening(plan, w, 2);
    expect(len(wide)).toBeCloseTo(2); expect((wide.a.x + wide.b.x) / 2).toBeCloseTo(0);
    expect(len(resizeOpening(plan, w, 50))).toBeCloseTo(5.9);
    const h = setOpeningHeight(plan, w, 3, 2);
    expect(h.bottom + h.height).toBeLessThanOrEqual(2.65 + 1e-9);
  });

  it('backs furniture onto a nearby wall and leaves it square in the middle', () => {
    const plan = room();
    const sofa = placeFurniture(plan, { x: 0, z: 1.6 }, furniturePreset('sofa')!);
    expect(sofa.center.z).toBeCloseTo(2 - 0.45 - 0.02);
    expect(Math.abs(Math.sin(sofa.rotation))).toBeCloseTo(0);
    const side = placeFurniture(plan, { x: -2.6, z: 0 }, furniturePreset('wardrobe')!);
    expect(side.center.x).toBeCloseTo(-3 + 0.3 + 0.02);
    expect(Math.abs(Math.cos(side.rotation))).toBeCloseTo(0);
    const mid = placeFurniture(plan, { x: 0, z: 0 }, furniturePreset('dining-table')!);
    expect(mid.center).toEqual({ x: 0, z: 0 }); expect(mid.rotation).toBe(0);
    expect(backOntoWall(plan, { x: 0, z: 0 }, 0.9)).toBeUndefined();
  });

  it('turns by quarters and stays in range', () => {
    const o = placeFurniture(room(), { x: 0, z: 0 }, furniturePreset('bed')!);
    let t = o;
    for (let i = 0; i < 5; i++) t = turnObject(t, Math.PI / 2);
    expect(t.rotation).toBeCloseTo(Math.PI / 2, 3);
    expect(t.rotation).toBeGreaterThan(-Math.PI); expect(t.rotation).toBeLessThanOrEqual(Math.PI);
  });

  it('moves a segment between lists when its kind changes', () => {
    let plan = room();
    const d = placeOpening(plan, { x: 0, z: 2 }, openingPreset('door')!)!;
    plan = addSegment(plan, d);
    expect(plan.doors).toHaveLength(1);
    plan = replaceSegment(plan, { ...d, kind: 'opening' });
    expect(plan.doors).toHaveLength(0); expect(plan.openings).toHaveLength(1);
    plan = removeSegment(plan, d.id);
    expect(plan.openings).toHaveLength(0);
  });

  it('has the same presets as the phone', () => {
    // FrameScout/Core/Models/SetPieces.swift lists these ids in this order.
    expect(OPENING_PRESETS.map(p => p.id)).toEqual(['door', 'double-door', 'window', 'tall-window', 'opening']);
    expect(FURNITURE_PRESETS.map(p => p.id)).toEqual(['sofa', 'armchair', 'chair', 'dining-table', 'coffee-table', 'desk', 'bed', 'wardrobe', 'sideboard', 'shelves', 'fridge', 'cooker', 'sink', 'bath', 'toilet', 'fireplace', 'box']);
  });
});

describe('plan sync', () => {
  it('keeps a piece added on the phone and one added here', () => {
    const base = upperKeys({ 'abc-1': room() });
    const phone = { ...base, 'ABC-1': addObject(base['ABC-1'], placeFurniture(base['ABC-1'], { x: 0, z: 0 }, furniturePreset('sofa')!)) };
    const here = { ...base, 'ABC-1': addSegment(base['ABC-1'], placeOpening(base['ABC-1'], { x: 0, z: -2 }, openingPreset('window')!)!) };
    const merged = mergeDocuments(base, here, phone);
    expect(merged['ABC-1'].objects).toHaveLength(1);
    expect(merged['ABC-1'].windows).toHaveLength(1);
  });

  it('a piece deleted here stays deleted when the phone did not touch it', () => {
    const start = room();
    const sofa = placeFurniture(start, { x: 0, z: 0 }, furniturePreset('sofa')!);
    const base = { K: addObject(start, sofa) };
    const here = { K: { ...base.K, objects: [] } };
    const merged = mergeDocuments(base, here, base);
    expect(merged.K.objects).toHaveLength(0);
  });
});
