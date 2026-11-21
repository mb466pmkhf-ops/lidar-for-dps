// Same cases as "Lighting setups" in Tests/CoreLogicTests/main.swift.
import { describe, expect, it } from 'vitest';
import { LIGHTING_SETUPS, buildSetup, keyStopsUnder, ratioLabel } from '../src/model/setups';
import { at, buildScene, direction, reading } from '../src/model/calculator';
import { defaultExposure, keyLux } from '../src/model/exposure';
import { eyeHeight } from '../src/model/characters';
import { newCharacter } from '../src/model/factory';
import { buildRoomPlan } from '../src/model/room';

describe('lighting setups', () => {
  const plan = buildRoomPlan({ shape: 'box', length: 6, width: 4, ceiling: 2.6, windows: 0, door: false });
  const person = { ...newCharacter('woman', { x: 0, z: 1 }, 'Maya'), facing: 0 };
  const exposure = { ...defaultExposure(), iso: 800, tStop: 2.8 };
  const camera = { x: 0, z: -1.5 };
  const face = at(person.position, eyeHeight(person) - 0.03);
  const lux = (lights: ReturnType<typeof buildSetup>['lights'], id: string) =>
    reading(face, direction(0, 0), buildScene(lights, plan)).contributions.filter(c => c.lightID === id).reduce((s, c) => s + c.lux, 0);

  it('three-point: key at the set stop, fill two stops under, all inside the room', () => {
    const s = buildSetup('threePoint', person, camera, exposure, plan);
    expect(s.lights.map(l => l.role)).toEqual(['key', 'fill', 'back']);
    expect(s.notes).toHaveLength(3);
    for (const l of s.lights) { expect(Math.abs(l.position.x)).toBeLessThan(3); expect(Math.abs(l.position.z)).toBeLessThan(2); }
    const key = lux(s.lights, s.lights[0].id), fill = lux(s.lights, s.lights[1].id);
    expect(Math.abs(Math.log2(key / keyLux(exposure)))).toBeLessThan(0.2);
    expect(Math.abs(Math.log2(key / fill) - 2)).toBeLessThan(0.4);
  });
  it('names key to fill as a ratio', () => {
    expect([0, 1, 2, 3].map(ratioLabel)).toEqual(['1:1', '2:1', '4:1', '8:1']);
    expect(ratioLabel(1.5)).toBe('2.8:1');
  });
  it('moonlight is a blue hard source a stop under; interview adds a neg and a hair light', () => {
    const m = buildSetup('moonlight', person, camera, exposure, plan).lights[0];
    expect(m.filterIDs).toEqual(['ctb-full']);
    expect(keyStopsUnder('moonlight')).toBe(1);
    const i = buildSetup('interview', person, camera, exposure, plan).lights;
    expect(i.map(l => l.role)).toEqual(['key', 'fill', 'back']);
    expect(i[1].kind).toBe('negative');
  });
  it('soft side light adds a neg fill', () => {
    expect(buildSetup('softSide', person, camera, exposure, plan).lights.some(l => l.kind === 'negative')).toBe(true);
  });
  it('every setup keys the face at the set stop and works without a camera or a plan', () => {
    for (const { id } of LIGHTING_SETUPS) {
      const s = buildSetup(id, person, camera, exposure, plan);
      expect(Math.abs(Math.log2(lux(s.lights, s.lights[0].id) / keyLux(exposure)) + keyStopsUnder(id)), id).toBeLessThan(0.2);
      expect(s.notes.every(n => !/couldn't|even at full/.test(n)), `${id}: ${s.notes.join(' / ')}`).toBe(true);
      expect(buildSetup(id, person, undefined, exposure).lights.length).toBe(s.lights.length);
    }
  });
});
