import { describe, expect, it } from 'vitest';
import { demoBundle } from '../src/model/demo';
import { inFrameSentence, unitsInFrame } from '../src/model/frameCheck';
import { newLight } from '../src/model/factory';
import type { CameraRig, FloorPlan, LightFixture, LightKind } from '../src/model/types';

const rig: CameraRig = { position: { x: 0, z: 0 }, height: 1.5, pan: 0, tilt: 0, focalLength: 35, sensorID: 'arri-minilf-og', aspect: 'sensor' };
const light = (name: string, x: number, z: number, height = 2, kind: LightKind = 'fresnel'): LightFixture =>
  ({ ...newLight(kind, { x, z }, 180), name, height });

describe('frame check (units and stands in shot)', () => {
  it('lists only units in front of the lens and inside the frame', () => {
    expect(unitsInFrame(rig, [light('Ahead', 0, -3), light('Behind', 0, 3), light('Wide', 3, -1)]).map(i => i.name)).toEqual(['Ahead']);
  });
  it('sees the stand of a head above frame, unless the unit is rigged', () => {
    const high = light('High', 0, -1.5, 3.6);
    expect(unitsInFrame(rig, [high])[0]?.part).toBe('stand');
    expect(unitsInFrame(rig, [{ ...high, support: 'overhead' }])).toEqual([]);
  });
  it('never lists practicals', () => {
    expect(unitsInFrame(rig, [light('Lamp', 0, -3, 1.2, 'practical')])).toEqual([]);
  });
  it('a wall between hides the unit', () => {
    const plan = { walls: [{ id: 'w', kind: 'wall', a: { x: -5, z: -2 }, b: { x: 5, z: -2 }, height: 2.7, bottom: 0, isOpen: false }] } as unknown as FloorPlan;
    expect(unitsInFrame(rig, [light('Ahead', 0, -3)], plan)).toEqual([]);
  });
  it('says what is in shot', () => {
    expect(inFrameSentence([{ id: '1', name: 'Key', part: 'unit' }, { id: '2', name: 'Fill', part: 'unit' }, { id: '3', name: 'Back', part: 'stand' }]))
      .toBe("Key and Fill are in shot; Back's stand is in shot.");
    expect(inFrameSentence([])).toBe('');
  });
  it('the sample room has a clean frame in both shots', () => {
    const b = demoBundle(); const loc = b.project.locations[0]; const plan = Object.values(b.plans)[0];
    for (const s of loc.shots) expect(inFrameSentence(unitsInFrame(s.rig, loc.lights ?? [], plan))).toBe('');
  });
});
