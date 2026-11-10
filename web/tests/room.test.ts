import { describe, expect, it } from 'vitest';
import { buildRoom, buildRoomPlan, normalise, roomArea, roomOutline } from '../src/model/room';

describe('drawn rooms', () => {
  it('builds a box with four walls and the typed sizes', () => {
    const plan = buildRoomPlan({ shape: 'box', length: 6.2, width: 4.8, ceiling: 2.74, windows: 2, door: true });
    expect(plan.walls).toHaveLength(4);
    expect(plan.windows).toHaveLength(2);
    expect(plan.doors).toHaveLength(1);
    expect(plan.bounds).toEqual({ minX: -3.1, minZ: -2.4, maxX: 3.1, maxZ: 2.4 });
    expect(plan.walls.every(w => w.height === 2.74)).toBe(true);
    // Windows sit on the top wall, inside it.
    for (const w of plan.windows) { expect(w.a.z).toBe(-2.4); expect(w.a.x).toBeGreaterThan(-3.1); expect(w.b.x).toBeLessThan(3.1); }
  });

  it('builds an L with six walls and three quarters of the area', () => {
    const spec = { shape: 'l' as const, length: 8, width: 6, ceiling: 3, windows: 0, door: false };
    expect(roomOutline(spec)).toHaveLength(6);
    expect(buildRoomPlan(spec).walls).toHaveLength(6);
    expect(roomArea(spec)).toBeCloseTo(36);
  });

  it('clamps silly sizes', () => {
    const s = normalise({ shape: 'box', length: 0, width: NaN, ceiling: 99, windows: 9, door: true });
    expect(s.length).toBe(1.5); expect(s.width).toBe(1.5); expect(s.ceiling).toBe(20); expect(s.windows).toBe(4);
    const plan = buildRoomPlan(s);
    expect(plan.doors[0].a.z).toBeLessThanOrEqual(0.75);
    expect(plan.doors[0].b.z).toBeGreaterThanOrEqual(-0.75);
  });

  it('makes a location whose scan points at the plan', () => {
    const { location, scanID, plan } = buildRoom('  Studio A ', { shape: 'box', length: 5, width: 4, ceiling: 2.7, windows: 1, door: true });
    expect(location.name).toBe('Studio A');
    expect(location.primaryScanID).toBe(scanID);
    expect(location.scans[0].stats.length).toBe(5);
    expect(location.scans[0].stats.width).toBe(4);
    expect(plan.floorPolygons[0]).toHaveLength(4);
  });
});
