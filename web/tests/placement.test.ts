// Same cases as "Placement" in Tests/CoreLogicTests/main.swift.
import { describe, expect, it } from 'vitest';
import type { FloorPlan, PlanObject, PlanPoint, PrevisCharacter } from '../src/model/types';
import { carryPeople, bodyRadius, seatAt, settlePeople, settlePerson } from '../src/model/placement';
import { eyeHeight } from '../src/model/characters';
import { newCharacter } from '../src/model/factory';

const P = (x: number, z: number): PlanPoint => ({ x, z });
const corners = [P(-3, -2.5), P(3, -2.5), P(3, 2.5), P(-3, 2.5)];
const sofa: PlanObject = { id: 'sofa', category: 'Sofa', center: P(0, 2), width: 2, depth: 0.9, height: 0.85, rotation: 0 };
const table: PlanObject = { id: 'table', category: 'Table', center: P(0, 0.8), width: 1.1, depth: 0.6, height: 0.45, rotation: 0 };
const chair: PlanObject = { id: 'chair', category: 'Chair', center: P(-2, 0), width: 0.48, depth: 0.5, height: 0.9, rotation: Math.PI / 2 };
const plan: FloorPlan = {
  walls: corners.map((a, i) => ({ id: 'w' + i, kind: 'wall', a, b: corners[(i + 1) % 4], height: 2.6, bottom: 0, isOpen: false })),
  doors: [], windows: [], openings: [], floorPolygons: [corners], occupancy: [], occupancyCellSize: 0.1, floorY: 0,
  objects: [sofa, table, chair], bounds: { minX: -3, minZ: -2.5, maxX: 3, maxZ: 2.5 },
};
const person = (at: PlanPoint, posture: 'standing' | 'sitting' = 'standing', facing = 180): PrevisCharacter =>
  ({ ...newCharacter('man', at, 'Ed'), posture, facing });
const clear = (c: PrevisCharacter) => plan.objects.every(o => {
  const dx = c.position.x - o.center.x, dz = c.position.z - o.center.z;
  const lx = dx * Math.cos(o.rotation) + dz * Math.sin(o.rotation), lz = -dx * Math.sin(o.rotation) + dz * Math.cos(o.rotation);
  return Math.hypot(Math.max(0, Math.abs(lx) - o.width / 2), Math.max(0, Math.abs(lz) - o.depth / 2)) >= bodyRadius(c) - 1e-3;
});

describe('placement', () => {
  it('moves a standing person out of the sofa to the nearest clear side', () => {
    const c = settlePerson(person(P(0.3, 1.75)), plan);
    expect(clear(c)).toBe(true);
    // The sofa backs onto the wall at z = 2.5, so the only way out is the front.
    expect(c.position.z).toBeCloseTo(2 - 0.45 - bodyRadius(c) - 0.02, 3);
    expect(c.position.x).toBeCloseTo(0.3, 3);
    expect(c.seatHeight).toBeUndefined();
  });

  it('leaves a person who is clear where they are', () => {
    const c = person(P(1.8, -1));
    expect(settlePerson(c, plan)).toEqual(c);
  });

  it('seats a sitting person on the sofa, facing out, at the cushion height', () => {
    const c = settlePerson(person(P(-0.4, 2.1), 'sitting', 90), plan);
    expect(c.posture).toBe('sitting');
    expect(c.seatHeight).toBeCloseTo(0.44, 3);
    expect(c.position.x).toBeCloseTo(-0.4, 3);
    expect(c.position.z).toBeCloseTo(2, 3);          // hips just in front of the back cushions
    expect(c.facing).toBe(0);                        // squared up: 90° was too far round
    expect(eyeHeight(c)).toBeCloseTo(eyeHeight({ ...c, seatHeight: undefined }) + 0.44 - 0.45, 3);
  });

  it('keeps a small turn on the seat, and stays on the seat between the arms', () => {
    const c = settlePerson(person(P(5, 2), 'sitting', 330), { ...plan, objects: [{ ...sofa, width: 4 }], walls: [], floorPolygons: [] });
    expect(c.seatHeight).toBeUndefined();            // 5 m is well off a 4 m sofa: no seat
    const on = settlePerson(person(P(2.05, 2), 'sitting', 330), { ...plan, objects: [{ ...sofa, width: 4 }] });
    expect(on.facing).toBe(330);
    expect(on.position.x).toBeCloseTo(2 - 0.2 - 0.25, 3);
  });

  it('sits on a chair turned on the plan', () => {
    const c = settlePerson(person(P(-2, 0), 'sitting'), plan);
    expect(c.seatHeight).toBeCloseTo(0.485, 3);
    // Width along z, depth along x; its back is to the wall at x = −3, so they face +x (90°).
    expect(c.facing).toBe(90);
    expect(c.position.x).toBeCloseTo(-2 - 0.09, 3);
  });

  it('switching to Sitting next to a sofa sits them on it; standing up steps out in front', () => {
    const before = person(P(0.5, 1.2));
    const sat = settlePerson({ ...before, posture: 'sitting' }, plan, before);
    expect(sat.seatHeight).toBeCloseTo(0.44, 3);
    expect(sat.position.z).toBeCloseTo(2, 3);
    const up = settlePerson({ ...sat, posture: 'standing' }, plan, sat);
    expect(up.seatHeight).toBeUndefined();
    // In front of the sofa, squeezed clear of the coffee table that is in the way.
    expect(up.position.z).toBeLessThan(2 - 0.45 - bodyRadius(up));
    expect(up.position.z).toBeGreaterThan(0.8 + 0.3 + bodyRadius(up));
    expect(clear(up)).toBe(true);
    // With nothing in front they step straight out.
    const open = { ...plan, objects: [sofa] };
    const up2 = settlePerson({ ...sat, posture: 'standing' }, open, sat);
    expect(up2.position.z).toBeCloseTo(2 - 0.45 - bodyRadius(up2) - 0.05, 3);
  });

  it('a sitting person off any seat keeps the usual chair height and is kept out of the table', () => {
    const c = settlePerson(person(P(0, 0.8), 'sitting'), plan);
    expect(c.seatHeight).toBeUndefined();
    expect(clear(c)).toBe(true);
  });

  it('only settles people an edit changed, and returns the same list when nothing moved', () => {
    const a = person(P(0, 2)), b = person(P(1.8, -1));
    const list = [a, b];
    expect(settlePeople(list, plan, undefined, list)).toBe(list);
    const settled = settlePeople(list, plan, undefined, [], true);
    expect(settled).not.toBe(list);
    expect(settled[1]).toBe(b);
    expect(clear(settled[0])).toBe(true);
  });

  it('seated people ride along when the sofa moves or turns', () => {
    const c = settlePerson(person(P(0.5, 2), 'sitting', 0), plan);
    const moved = { ...plan, objects: [{ ...sofa, center: P(0, -2), rotation: Math.PI }, table, chair] };
    const [after] = carryPeople([c], plan, moved, undefined);
    expect(after.seatHeight).toBeCloseTo(0.44, 3);
    expect(after.position.x).toBeCloseTo(-0.5, 2);
    expect(after.position.z).toBeCloseTo(-2, 2);
    expect(after.facing).toBe(180);
    expect(seatAt(after.position, moved)?.object.id).toBe('sofa');
  });

  it('a piece moved onto a standing person pushes them aside', () => {
    const c = person(P(1.8, -1));
    const moved = { ...plan, objects: [{ ...table, center: P(1.8, -1.1) }] };
    const [after] = carryPeople([c], plan, moved, undefined);
    expect(after.position).not.toEqual(c.position);
  });
});

describe('placement: plan edits that touch nobody', () => {
  it('returns the same list when a piece moves away from everyone', () => {
    const list = [person(P(1.8, -1))];
    const moved = { ...plan, objects: [{ ...table, center: P(-1, 0.8) }, sofa, chair] };
    expect(carryPeople(list, plan, moved, undefined)).toBe(list);
  });
});
