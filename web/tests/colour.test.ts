import { describe, expect, it } from 'vitest';
import { colourShift, colourSummary } from '../src/model/colour';
import { cameraExposure } from '../src/model/exposure';
import { newLight } from '../src/model/factory';

describe('colour at the camera white balance', () => {
  it('reads tungsten on a daylight camera as about full CTO warm', () => {
    const s = colourShift(3200, 5600);
    expect(s.tone).toBe('warm');
    expect(Math.round(s.mired)).toBe(134);
    expect(s.label).toBe('reads warm, about ⅞ CTO');
  });
  it('reads daylight on a tungsten camera as cool, in CTB', () => {
    const s = colourShift(5600, 3200);
    expect(s.tone).toBe('cool');
    expect(s.label).toBe('reads cool, about full CTB');
  });
  it('calls a near match white', () => {
    expect(colourShift(5300, 5600).tone).toBe('match');
    expect(colourShift(5000, 5600).label).toBe('reads warm, about ⅛ CTO');
    expect(colourShift(5600, 5600).label).toBe('reads white');
  });
  it('names big shifts in whole gels', () => {
    expect(colourShift(2000, 6500).label).toBe('reads warm, about 2× full CTO');
    // Just past a full gel but under the whole-number step still reads "full", never "undefined".
    expect(colourShift(2800, 5600).label).toBe('reads warm, about full CTO');
  });
  it('sums up only the lights that are on and give light', () => {
    const a = { ...newLight('fresnel', { x: 0, z: 0 }), name: 'Key' };
    const b = { ...newLight('bounce', { x: 1, z: 0 }), name: 'Bounce' };
    const c = { ...newLight('fresnel', { x: 2, z: 0 }), name: 'Off', isOn: false };
    const s = colourSummary([a, b, c], 5600);
    expect(s.rows.map(r => r.name)).toEqual(['Key']);
    expect(s.line.startsWith('At 5600 K: 1 ')).toBe(true);
  });
});

describe('settings per camera', () => {
  it('uses the camera’s own settings when it has them, else the location’s', () => {
    const loc = { exposure: { iso: 800, frameRate: 24, shutterAngle: 180, tStop: 2.8, lensTransmission: 0.85, ndStops: 0 } };
    expect(cameraExposure(loc).iso).toBe(800);
    expect(cameraExposure(loc, {}).iso).toBe(800);
    expect(cameraExposure(loc, { exposure: { ...loc.exposure, iso: 1600, whiteBalance: 3200 } }).whiteBalance).toBe(3200);
  });
});
