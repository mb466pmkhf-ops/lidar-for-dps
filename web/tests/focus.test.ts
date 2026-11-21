import { describe, expect, it } from 'vitest';
import { blurDiameter, circleOfConfusion, depthOfField, depthOfFieldFor, focusFor, focusLabel, hazeLevel, MIN_FOCUS } from '../src/model/focus';
import type { CameraRig } from '../src/model/types';

const rig = (patch: Partial<CameraRig> = {}): CameraRig => ({
  position: { x: 0, z: 0 }, height: 1.5, pan: 0, tilt: 0, focalLength: 50, sensorID: 'arri-minilf-og', aspect: 'sensor', ...patch,
});

describe('depth of field', () => {
  it('matches a published depth-of-field table (50 mm, f/2.8, 3 m, CoC 0.030 mm)', () => {
    // Thin-lens tables (e.g. DOFMaster) give near 2.73 m, far 3.33 m, hyperfocal 29.8 m.
    const d = depthOfField(50, 2.8, 3, 0.03);
    expect(d.near).toBeCloseTo(2.73, 2);
    expect(d.far).toBeCloseTo(3.33, 2);
    expect(d.hyperfocal).toBeCloseTo(29.81, 1);
  });

  it('reaches infinity at and past the hyperfocal distance', () => {
    const d = depthOfField(24, 8, 10, 0.03);
    expect(d.hyperfocal).toBeLessThan(10);
    expect(d.far).toBe(Infinity);
    expect(focusLabel(d)).toMatch(/to infinity$/);
  });

  it('gets shallower when opening up, longer or closer', () => {
    const span = (f: number, n: number, s: number) => { const d = depthOfField(f, n, s, 0.03); return d.far - d.near; };
    expect(span(50, 1.4, 3)).toBeLessThan(span(50, 4, 3));
    expect(span(85, 2.8, 3)).toBeLessThan(span(35, 2.8, 3));
    expect(span(50, 2.8, 1.5)).toBeLessThan(span(50, 2.8, 4));
  });

  it('uses the frame diagonal / 1500 for the circle of confusion', () => {
    // Mini LF open gate 36.70 × 25.54 → diagonal 44.7 mm → 0.030 mm.
    expect(circleOfConfusion(rig())).toBeCloseTo(0.0298, 3);
    // A 2.39 crop of the same sensor is a smaller frame, so a smaller circle.
    expect(circleOfConfusion(rig({ aspect: 'r239' }))).toBeLessThan(circleOfConfusion(rig()));
  });

  it('blurs nothing at the focus distance and approaches f²/(N(s−f)) far behind', () => {
    expect(blurDiameter(50, 2, 3, 3)).toBeCloseTo(0, 6);
    const atInfinity = (0.05 * 0.05) / (2 * (3 - 0.05)) * 1000;
    expect(blurDiameter(50, 2, 3, 1e6)).toBeCloseTo(atInfinity, 3);
    expect(blurDiameter(50, 2, 3, 6)).toBeCloseTo(atInfinity / 2, 3);
  });
});

describe('focus distance', () => {
  it('uses the rig distance when set, else the subject’s eyes, else nothing', () => {
    expect(focusFor(rig({ focusDistance: 4.2 }))).toEqual({ metres: 4.2, from: 'set' });
    const s = focusFor(rig(), { x: 3, z: 4 }, 1.75)!;
    expect(s.from).toBe('subject');
    expect(s.metres).toBeCloseTo(Math.hypot(3, 4, 1.75 * 0.94 - 1.5), 6);
    expect(focusFor(rig())).toBeUndefined();
  });

  it('never focuses closer than the minimum', () => {
    expect(focusFor(rig({ focusDistance: 0.05 }))!.metres).toBe(MIN_FOCUS);
    expect(depthOfFieldFor(rig(), 2, 0.3).near).toBeGreaterThan(0);
  });
});

describe('haze levels', () => {
  it('falls back to no haze for an unknown or missing level', () => {
    expect(hazeLevel(undefined).id).toBe('none');
    expect(hazeLevel('fog machine').id).toBe('none');
    expect(hazeLevel('heavy').veil).toBeGreaterThan(hazeLevel('light').veil);
  });
});
