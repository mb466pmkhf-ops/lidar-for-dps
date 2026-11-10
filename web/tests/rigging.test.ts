import { describe, expect, it } from 'vitest';
import { automaticCameraSupport, automaticLightSupport, lightSupportWarning, planReach } from '../src/model/rigging';
import { newLight } from '../src/model/factory';
import type { FloorPlan } from '../src/model/types';

describe('stands', () => {
  it('picks a stand from the unit and its height', () => {
    const l = ({ ...newLight('fresnel', { x: 0, z: 0 }), profileID: 'cob-600-d' });
    expect(automaticLightSupport({ ...l, height: 2 })).toBe('cStand');
    expect(automaticLightSupport({ ...l, height: 0.5 })).toBe('turtleBase');
    expect(automaticLightSupport({ ...l, height: 2, modifierID: 'softbox-150' })).toBe('comboStand');
    expect(automaticLightSupport({ ...newLight('fresnel', { x: 0, z: 0 }), profileID: 'hmi-1800-par', height: 2 })).toBe('comboStand');
    expect(automaticCameraSupport(1.5)).toBe('tripod');
    expect(automaticCameraSupport(0.3)).toBe('highHat');
    expect(lightSupportWarning({ ...l, height: 3.8, support: 'cStand' })).toMatch(/Higher than a C-stand/);
  });

  it('stops a drawn beam at the wall', () => {
    const wall = { id: 'W', kind: 'wall' as const, a: { x: -5, z: -2 }, b: { x: 5, z: -2 }, height: 2.5, bottom: 0, isOpen: false };
    const plan = { walls: [wall], doors: [], windows: [], openings: [] } as unknown as FloorPlan;
    expect(planReach({ x: 0, z: 0 }, 0, 6, plan)).toBeCloseTo(2, 5);
    expect(planReach({ x: 0, z: 0 }, 180, 6, plan)).toBeCloseTo(6, 5);
  });
});
