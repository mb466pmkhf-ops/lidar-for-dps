import { describe, expect, it } from 'vitest';
import { checkedBundle } from '../src/sync/importBundle';

describe('importing a project file', () => {
  it('refuses something that is not a project', () => {
    expect(() => checkedBundle({ hello: 1 })).toThrow(/not a FrameScan project/);
    expect(() => checkedBundle(null)).toThrow();
    expect(() => checkedBundle({ project: { locations: 'x' } })).toThrow();
  });

  it('fills the lists an older file lacks, so the planner can draw it', () => {
    const b = checkedBundle({ name: 'Old', locations: [{ name: 'Kitchen' }, 7] });
    expect(b.project.id).toMatch(/^[0-9A-F-]{36}$/);
    expect(b.project.locations).toHaveLength(1);
    const l = b.project.locations[0];
    expect(l.scans).toEqual([]); expect(l.shots).toEqual([]); expect(l.cameraPositions).toEqual([]);
    expect(typeof l.id).toBe('string');
  });

  it('keeps a full bundle and its plans, keyed in upper case', () => {
    const plan = { walls: [], bounds: { minX: 0, minZ: 0, maxX: 1, maxZ: 1 }, floorY: 0, occupancyCellSize: 0.1 };
    const b = checkedBundle({ project: { id: 'P', name: 'N', client: 'C', notes: '', createdAt: 'a', modifiedAt: 'b', locations: [], extra: 1 },
      plans: { abc: plan, bad: { walls: 'no' } } });
    expect(b.project.extra).toBe(1);
    expect(Object.keys(b.plans)).toEqual(['ABC']);
    expect(b.plans.ABC.doors).toEqual([]);
  });

  it('drops plan entries and lists that could not be drawn', () => {
    const b = checkedBundle({ project: { id: 'P', locations: [{ id: 'L', lights: {}, meters: [null, { id: 'M' }] }] },
      plans: {
        good: { walls: [null, { a: { x: 0, z: 0 }, b: { x: 1, z: 0 } }], floorPolygons: [null, [{ x: 0, z: 0 }, null]], bounds: { minX: 0, minZ: 0, maxX: 1, maxZ: 1 } },
        noBounds: { walls: [], bounds: {} },
      } });
    const l = b.project.locations[0];
    expect(l.lights).toEqual([]);
    expect(l.meters).toEqual([{ id: 'M' }]);
    expect('characters' in l).toBe(false);
    expect(Object.keys(b.plans)).toEqual(['GOOD']);
    expect(b.plans.GOOD.walls).toHaveLength(1);
    expect(b.plans.GOOD.floorPolygons).toEqual([[{ x: 0, z: 0 }]]);
    expect(b.plans.GOOD.occupancyCellSize).toBe(0.1);
  });
});
