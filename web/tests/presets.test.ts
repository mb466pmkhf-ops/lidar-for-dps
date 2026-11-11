// Same cases as "Lighting presets" in Tests/CoreLogicTests/main.swift.
import { describe, expect, it } from 'vitest';
import { buildSetup } from '../src/model/setups';
import { buildPreset, capturePersonPreset, captureWindowPreset, decodePresets, encodePresets, nearestWindow, outwardBearing, buildPresetAtWindow } from '../src/model/presets';
import { at, buildScene, direction, planDist, reading } from '../src/model/calculator';
import { defaultExposure, keyLux } from '../src/model/exposure';
import { eyeHeight } from '../src/model/characters';
import { newCharacter, newLight } from '../src/model/factory';
import { buildRoomPlan } from '../src/model/room';
import type { LightFixture, PrevisCharacter } from '../src/model/types';

describe('lighting presets', () => {
  const plan = buildRoomPlan({ shape: 'box', length: 6, width: 4, ceiling: 2.6, windows: 1, door: false });
  const person = { ...newCharacter('woman', { x: 0, z: 1 }, 'Maya'), facing: 0 };
  const exposure = { ...defaultExposure(), iso: 800, tStop: 2.8 };
  const camera = { x: 0, z: -1.5 };
  const lux = (lights: LightFixture[], id: string, who: PrevisCharacter, bearing: number) =>
    reading(at(who.position, eyeHeight(who) - 0.03), direction(bearing, 0), buildScene(lights, plan)).contributions
      .filter(c => c.lightID === id).reduce((s, c) => s + c.lux, 0);

  it('saving a three-point setup and using it again puts the units back where they were', () => {
    const original = buildSetup('threePoint', person, camera, exposure, plan);
    const preset = capturePersonPreset('My three-point', original.lights, person, camera, exposure, plan);
    expect(preset.units.map(u => u.light.name)).toEqual(['Key', 'Fill', 'Back']);
    expect(preset.units[0].angle).toBeGreaterThan(0);
    expect(preset.units[1].stopsUnderKey).toBeCloseTo(2, 0);
    const again = buildPreset(preset, person, camera, exposure, plan);
    expect(again.lights).toHaveLength(3);
    again.lights.forEach((l, i) => {
      expect(planDist(l.position, original.lights[i].position)).toBeLessThan(0.02);
      expect(Math.abs(l.height - original.lights[i].height)).toBeLessThan(0.02);
      expect(l.name).toBe(original.lights[i].name);
      expect(l.profileID).toBe(original.lights[i].profileID);
    });
    expect(Math.abs(Math.log2(lux(again.lights, again.lights[0].id, person, 0) / keyLux(exposure)))).toBeLessThan(0.2);
  });

  it('follows the person, the camera and the stop', () => {
    const preset = capturePersonPreset('Mine', buildSetup('keyAndEdge', person, camera, exposure, plan).lights, person, camera, exposure, plan);
    const leo = { ...newCharacter('man', { x: 1.5, z: 0 }, 'Leo'), facing: 270 };
    const brighter = { ...exposure, tStop: 4 };
    const built = buildPreset(preset, leo, { x: -1.5, z: 0 }, brighter, plan);
    expect(built.lights.map(l => l.name)).toEqual(['Key · Leo', 'Edge · Leo']);
    for (const l of built.lights) { expect(Math.abs(l.position.x)).toBeLessThan(3); expect(Math.abs(l.position.z)).toBeLessThan(2); }
    expect(Math.abs(Math.log2(lux(built.lights, built.lights[0].id, leo, 270) / keyLux(brighter)))).toBeLessThan(0.2);
  });

  it('keeps the sides when asked, and mirrors to the roomier side otherwise', () => {
    const lights = buildSetup('hardSingle', person, camera, exposure, plan).lights;
    const preset = capturePersonPreset('Side', lights, person, camera, exposure, plan);
    const nearWall = { ...person, position: { x: 2.4, z: 0 } };
    const auto = buildPreset(preset, nearWall, { x: 2.4, z: -1.8 }, exposure, plan).lights[0];
    expect(auto.position.x).toBeLessThan(2.4); // away from the wall at x = 3
    const kept = buildPreset({ ...preset, keepSides: true }, nearWall, { x: 2.4, z: -1.8 }, exposure, plan).lights[0];
    expect(kept.position.x).toBeGreaterThan(auto.position.x);
  });

  it('window presets keep their place against the window', () => {
    const w = plan.windows[0];
    const out = outwardBearing(plan, w);
    const mid = { x: (w.a.x + w.b.x) / 2, z: (w.a.z + w.b.z) / 2 };
    // A big unit 3 m outside, aimed straight in, and a bounce just inside.
    const dir = { x: Math.sin(out * Math.PI / 180), z: -Math.cos(out * Math.PI / 180) };
    const sun = { ...newLight('hmi', { x: mid.x + dir.x * 3, z: mid.z + dir.z * 3 }, (out + 180) % 360), name: 'Sun', height: 3, tilt: -25, dimmer: 0.8 };
    const bounce = { ...newLight('bounce', { x: mid.x - dir.x * 0.5, z: mid.z - dir.z * 0.5 }, out), name: 'Bounce' };
    const preset = captureWindowPreset('Sun through window', [sun, bounce], w, plan);
    expect(preset.units[0].out).toBeCloseTo(3, 2);
    expect(preset.units[0].panOffset).toBeCloseTo(0, 1);
    expect(preset.units[1].out).toBeCloseTo(-0.5, 2);
    const built = buildPresetAtWindow(preset, w, plan);
    expect(planDist(built.lights[0].position, sun.position)).toBeLessThan(0.02);
    expect(built.lights[0].dimmer).toBe(0.8);
    expect(built.lights[0].tilt).toBe(-25);
    expect(nearestWindow(person.position, plan)).toBe(w);
    expect(buildPreset(preset, person, camera, exposure, plan).lights).toHaveLength(2);
    expect(buildPreset(preset, person, camera, exposure).notes[0]).toMatch(/needs a window/);
  });

  it('round-trips through the shared JSON and refuses anything else', () => {
    const preset = capturePersonPreset('Mine', buildSetup('softSide', person, camera, exposure, plan).lights, person, camera, exposure, plan);
    const back = decodePresets(encodePresets([preset]));
    expect(back).toEqual([preset]);
    expect(decodePresets(JSON.stringify(preset))).toEqual([preset]);
    expect(decodePresets('hello')).toBeUndefined();
    expect(decodePresets('{"presets":[{"name":1}]}')).toBeUndefined();
  });
});
