// Studio builds, daylight and curtains (model/stage.ts). The parity fixture runs through the Swift
// calculator in CI (STAGE_READINGS), like parity.test.ts.
import { describe, expect, it } from 'vitest';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { buildScene, meterPoints, reading, vec, type Vec } from '../src/model/calculator';
import { buildRoomPlan } from '../src/model/room';
import { demoBundle } from '../src/model/demo';
import { newLight } from '../src/model/factory';
import { solarPosition } from '../src/model/solar';
import {
  AMBIENT_IDS, BACKDROPS, CYC_CORNER_RADIUS, FLOORS, backdropLayout, backdropPlacement, cornerFootprint, wallNames, daylightLevels, environment, insideRoom, inwardNormal, sunPlacement, windowViewLuminance,
} from '../src/model/stage';
import type { FloorPlan, Location, ProjectBundle } from '../src/model/types';

const room = (): FloorPlan => buildRoomPlan({ shape: 'box', length: 6, width: 4.5, ceiling: 2.7, windows: 1, door: false });
const loc = (patch: Partial<Location> = {}): Location => ({
  id: 'L', name: 'L', address: '', createdAt: '2026-01-01T00:00:00Z', notes: '', scans: [], cameraPositions: [], shots: [], ...patch,
});
const lux = (l: Location, plan: FloorPlan, p: Vec, n: Vec, id?: string) => {
  const r = reading(p, n, buildScene(l.lights ?? [], plan, 0.78, environment(l, plan)));
  return id ? r.contributions.filter(c => c.lightID === id).reduce((s, c) => s + c.lux, 0) : r.lux;
};
const withCurtain = (plan: FloorPlan, curtain?: 'sheer' | 'blackout'): FloorPlan => ({ ...plan, windows: plan.windows.map(w => ({ ...w, curtain })) });

// The drawn room's window is on the top wall (z = -2.25), so a sun at plan bearing 0 shines in through it.
const sunIn = loc({ daylight: { isOn: true, sky: 'clear', sunBearing: 0, sunElevation: 30 } });
const facingWindow = vec(0, 0, -1);
const nearWindow = vec(0, 1.2, -1.2);

describe('daylight levels', () => {
  it('follow the IES daylight availability model', () => {
    const zenith = daylightLevels('clear', 90);
    expect(zenith.directNormal).toBeGreaterThan(95000);
    expect(zenith.directNormal).toBeLessThan(110000);
    expect(daylightLevels('clear', 60).skyHorizontal).toBeCloseTo(800 + 15500 * Math.sqrt(Math.sin(Math.PI / 3)), 0);
    expect(daylightLevels('overcast', 50).directNormal).toBe(0);
    expect(daylightLevels('overcast', 50).skyHorizontal).toBeGreaterThan(15000);
    expect(daylightLevels('hazy', 40).directNormal).toBeLessThan(daylightLevels('clear', 40).directNormal);
  });
  it('fade through twilight and stop at night', () => {
    expect(daylightLevels('clear', -3).directNormal).toBe(0);
    expect(daylightLevels('clear', -3).skyHorizontal).toBeCloseTo(400, 6);
    expect(daylightLevels('clear', -8).skyHorizontal).toBe(0);
  });
  it('a window shows sky and sunlit ground', () => {
    const l = daylightLevels('clear', 40);
    expect(windowViewLuminance(l, 40)).toBeGreaterThan(l.skyHorizontal / Math.PI / 2);
  });
});

describe('sun position', () => {
  it('matches the NOAA algorithm at midsummer noon in London', () => {
    const p = solarPosition(new Date(Date.UTC(2024, 5, 21, 12, 2)), 51.5074, -0.1278);
    expect(p.elevation).toBeGreaterThan(61.4);
    expect(p.elevation).toBeLessThan(62.4);
    expect(Math.abs(p.azimuth - 180)).toBeLessThan(3);
  });
  it('turns true bearings into plan bearings with the scan north', () => {
    const l = loc({ coordinate: { latitude: 51.5, longitude: -0.13 }, daylight: { isOn: true, fromClock: true, time: Date.UTC(2024, 5, 21, 12, 2) / 1000 } });
    const s = sunPlacement(l, { id: 's', name: 's', kind: 'room', createdAt: '', stats: {}, northOffset: 90 });
    expect(s.from).toBe('clock');
    expect(s.bearing).toBeCloseTo((s.azimuth! - 90 + 360) % 360, 9);
    // Without north the sun stays where it was put by hand.
    expect(sunPlacement(l, { id: 's', name: 's', kind: 'room', createdAt: '', stats: {} }).from).toBe('hand');
  });
});

describe('sun and sky through a window', () => {
  const plan = room();
  it('the room geometry knows inside from outside', () => {
    expect(insideRoom({ x: 0, z: 0 }, plan)).toBe(true);
    expect(insideRoom({ x: 0, z: -3 }, plan)).toBe(false);
    const n = inwardNormal(plan.windows[0], plan);
    expect(n.z).toBeCloseTo(1, 9);
  });
  it('sun comes in as a beam through bare glass, and the sky adds soft light', () => {
    const sun = lux(sunIn, plan, nearWindow, facingWindow, AMBIENT_IDS.sun);
    const sky = lux(sunIn, plan, nearWindow, facingWindow, AMBIENT_IDS.sky);
    const l = daylightLevels('clear', 30);
    expect(sun).toBeCloseTo(l.directNormal * Math.cos(Math.PI / 6) * 0.78, 3);
    expect(sky).toBeGreaterThan(200);
    expect(sky).toBeLessThan(5000);
  });
  it('the sun does not come through the ceiling or a solid wall', () => {
    expect(lux(sunIn, plan, vec(0, 1.2, 1.8), facingWindow, AMBIENT_IDS.sun)).toBe(0); // too far in for 30° through a 1.5 m window
    const behind = loc({ daylight: { isOn: true, sunBearing: 180, sunElevation: 30 } });
    expect(lux(behind, plan, nearWindow, vec(0, 0, 1), AMBIENT_IDS.sun)).toBe(0);
    const high = loc({ daylight: { isOn: true, sunBearing: 0, sunElevation: 85 } });
    expect(lux(high, plan, vec(0, 1, 0), vec(0, 1, 0), AMBIENT_IDS.sun)).toBe(0);
  });
  it('outdoors the sun just shines', () => {
    expect(lux(sunIn, plan, vec(0, 1, -5), vec(0, 1, 0), AMBIENT_IDS.sun)).toBeCloseTo(daylightLevels('clear', 30).directNormal * 0.5, 3);
  });
  it('a sheer stops the beam and glows instead; blackout stops everything', () => {
    const bareSky = lux(sunIn, plan, nearWindow, facingWindow, AMBIENT_IDS.sky);
    const sheer = withCurtain(plan, 'sheer');
    expect(lux(sunIn, sheer, nearWindow, facingWindow, AMBIENT_IDS.sun)).toBe(0);
    expect(lux(sunIn, sheer, nearWindow, facingWindow, AMBIENT_IDS.sky)).toBeGreaterThan(bareSky);
    const black = withCurtain(plan, 'blackout');
    expect(lux(sunIn, black, nearWindow, facingWindow)).toBe(0);
  });
  it('curtains work on lamps outside the window too', () => {
    const outside = newLight('hmi', { x: 0, z: -5 }, 180);
    outside.height = 1.5;
    const l = loc({ lights: [outside] });
    const p = vec(0, 1.5, 0), n = vec(0, 0, -1);
    const bare = lux(l, plan, p, n);
    expect(bare).toBeGreaterThan(0);
    expect(lux(l, withCurtain(plan, 'sheer'), p, n)).toBeCloseTo(bare * 0.5, 6);
    expect(lux(l, withCurtain(plan, 'blackout'), p, n)).toBe(0);
  });
  it('daylight off gives nothing', () => {
    expect(environment(loc({ daylight: { isOn: false } }), plan)).toBeUndefined();
  });
});

describe('studio builds', () => {
  const plan = room();
  it('every backdrop and floor has a label and a colour', () => {
    for (const b of [...BACKDROPS, ...FLOORS]) { expect(b.label.length).toBeGreaterThan(2); expect(b.colour).toMatch(/^#[0-9a-f]{6}$/); }
    expect(new Set(BACKDROPS.map(b => b.id)).size).toBe(BACKDROPS.length);
  });
  it('a backdrop goes on the wall the camera looks at', () => {
    const l = loc({ studio: { backdrop: 'paper-grey' }, shots: [{ id: 's', number: 1, title: '', rig: { position: { x: 0, z: -1 }, height: 1.5, pan: 180, tilt: 0, focalLength: 35, sensorID: 's35', aspect: 'sensor' }, subjectHeight: 1.6, notes: '', createdAt: '' }] });
    const bd = backdropPlacement(l, plan)!;
    expect(bd.width).toBeCloseTo(2.72, 9);
    expect((bd.wall.a.z + bd.wall.b.z) / 2).toBeCloseTo(2.25, 6); // the bottom wall
    expect(bd.inward.z).toBeCloseTo(-1, 9);
    // "a" is on the left seen from the room: looking towards +z, left is +x.
    expect(bd.a.x).toBeGreaterThan(bd.b.x);
  });
  it('a cyc fills the wall; size and offset stay on the wall', () => {
    const wall = plan.walls[1];
    const l = loc({ studio: { backdrop: 'cyc-white', wallID: wall.id } });
    expect(backdropPlacement(l, plan)!.width).toBeCloseTo(Math.hypot(wall.b.x - wall.a.x, wall.b.z - wall.a.z), 9);
    const big = backdropPlacement(loc({ studio: { backdrop: 'led-wall', wallID: wall.id, width: 50, offset: 9 } }), plan)!;
    expect(big.width).toBeCloseTo(4.5, 9);
  });
  it('an LED wall lights the subject; paper does not', () => {
    const top = plan.walls[0];
    const p = vec(0, 1.5, -0.25), n = vec(0, 0, -1); // 2 m in front of the top wall, facing it
    const led = loc({ studio: { backdrop: 'led-wall', wallID: top.id, width: 6, height: 2.7, nits: 300 } });
    const e = lux(led, plan, p, n, AMBIENT_IDS.ledWall);
    // A 6 × 2.7 m wall 2 m away fills a good part of the view: well under π·L (942 lx), well over a tenth of it.
    expect(e).toBeGreaterThan(250);
    expect(e).toBeLessThan(800);
    expect(lux(loc({ studio: { ...led.studio, nits: 600 } }), plan, p, n, AMBIENT_IDS.ledWall)).toBeCloseTo(2 * e, 6);
    expect(lux(loc({ studio: { backdrop: 'paper-white', wallID: top.id } }), plan, p, n)).toBe(0);
    // Facing away from it: nothing.
    expect(lux(led, plan, p, vec(0, 0, 1), AMBIENT_IDS.ledWall)).toBe(0);
  });
  it('a big LED wall up close approaches π × luminance', () => {
    const plan2 = buildRoomPlan({ shape: 'box', length: 40, width: 10, ceiling: 20, windows: 0, door: false });
    const l = loc({ studio: { backdrop: 'led-wall', wallID: plan2.walls[0].id, width: 40, height: 20, nits: 100 } });
    const e = lux(l, plan2, vec(0, 10, -4.6), vec(0, 0, -1), AMBIENT_IDS.ledWall);
    expect(e).toBeGreaterThan(Math.PI * 100 * 0.85);
    expect(e).toBeLessThan(Math.PI * 100 * 1.02);
  });
});

// MARK: Backdrops on several walls

describe('backdrop round several walls', () => {
  const plan = room();
  const [top, right, bottom] = plan.walls;
  const near = (a: { x: number; z: number }, x: number, z: number) => Math.hypot(a.x - x, a.z - z) < 1e-9;
  it('a corner cyc curves round the corner and each piece stops at the bend', () => {
    const l = loc({ studio: { backdrop: 'cyc-white', wallID: top.id, moreWalls: [{ wallID: right.id }] } });
    const lay = backdropLayout(l, plan)!;
    expect(lay.pieces).toHaveLength(2);
    expect(lay.corners).toHaveLength(1);
    const c = lay.corners[0];
    // Faces 2 cm off the walls meet at (2.98, −2.23); a 90° bend of 0.75 m starts 0.75 m back on each.
    expect(near(c.point, 2.98, -2.23)).toBe(true);
    expect(c.radius).toBeCloseTo(CYC_CORNER_RADIUS, 9);
    expect(near(c.centre, 2.98 - 0.75, -2.23 + 0.75)).toBe(true);
    const [p0, p1] = lay.pieces;
    expect([p0.a, p0.b].some(e => near(e, 2.23, -2.23))).toBe(true);
    expect([p1.a, p1.b].some(e => near(e, 2.98, -1.48))).toBe(true);
    expect(p0.width).toBeCloseTo(6 - 0.02 - 0.75, 9);
    expect(cornerFootprint(c, 1.5)).toHaveLength(6);
  });
  it('a narrower piece goes into the corner it shares', () => {
    const l = loc({ studio: { backdrop: 'paper-white', wallID: top.id, moreWalls: [{ wallID: right.id }] } });
    const [p0, p1] = backdropLayout(l, plan)!.pieces;
    // Paper hangs 35 cm off the wall, so the two rolls butt at (2.65, −1.90).
    expect([p0.a, p0.b].some(e => near(e, 2.65, -1.9))).toBe(true);
    expect([p1.a, p1.b].some(e => near(e, 2.65, -1.9))).toBe(true);
    expect(p0.width).toBeCloseTo(2.72 - 0.35, 9);
  });
  it('a U has two corners; walls that do not meet have none', () => {
    const u = backdropLayout(loc({ studio: { backdrop: 'cyc-green', wallID: top.id, moreWalls: [{ wallID: right.id }, { wallID: bottom.id }] } }), plan)!;
    expect(u.pieces).toHaveLength(3);
    expect(u.corners).toHaveLength(2);
    const apart = backdropLayout(loc({ studio: { backdrop: 'cyc-green', wallID: top.id, moreWalls: [{ wallID: bottom.id }] } }), plan)!;
    expect(apart.corners).toHaveLength(0);
    expect(apart.pieces.every(p => Math.abs(p.width - 6) < 1e-9)).toBe(true);
  });
  it('walls are named by where they sit on the plan', () => {
    expect(plan.walls.map(w => wallNames(plan).get(w.id))).toEqual(['Top wall', 'Right wall', 'Bottom wall', 'Left wall']);
  });
  it('a missing or repeated wall is skipped, and one wall is as before', () => {
    const one = loc({ studio: { backdrop: 'cyc-white', wallID: top.id } });
    const odd = loc({ studio: { backdrop: 'cyc-white', wallID: top.id, moreWalls: [{ wallID: top.id }, { wallID: 'nope' }] } });
    expect(backdropLayout(odd, plan)!.pieces).toEqual(backdropLayout(one, plan)!.pieces);
    expect(backdropPlacement(one, plan)!.width).toBeCloseTo(6, 9);
  });
  it('an LED volume round a corner lights more than one wall of it, as one "LED wall"', () => {
    const p = vec(2, 1.5, -1.2), n = vec(0.7071, 0, -0.7071);
    const one = lux(loc({ studio: { backdrop: 'led-wall', wallID: top.id, nits: 300 } }), plan, p, n, AMBIENT_IDS.ledWall);
    const two = loc({ studio: { backdrop: 'led-wall', wallID: top.id, moreWalls: [{ wallID: right.id }], nits: 300 } });
    const both = lux(two, plan, p, n, AMBIENT_IDS.ledWall);
    expect(both).toBeGreaterThan(one * 1.2);
    const r = reading(p, n, buildScene([], plan, 0.78, environment(two, plan)));
    expect(r.contributions.filter(c => c.lightID === AMBIENT_IDS.ledWall)).toHaveLength(1);
  });
});

// MARK: Parity with Swift

const fixture = new URL('./fixtures/stage-bundle.json', import.meta.url);
function stageBundle(): ProjectBundle {
  const b = demoBundle();
  const l = b.project.locations[0];
  const scanID = l.primaryScanID!;
  const plan = b.plans[scanID];
  plan.windows[0] = { ...plan.windows[0], curtain: 'sheer' };
  l.coordinate = { latitude: 51.5074, longitude: -0.1278 };
  l.daylight = { isOn: true, sky: 'clear', fromClock: true, time: Date.UTC(2026, 5, 21, 15, 30) / 1000 };
  // An LED volume round a corner: 4 m on the top wall and 3 m on the right, pushed into the corner they share.
  l.studio = { backdrop: 'led-wall', wallID: plan.walls[0].id, width: 4, moreWalls: [{ wallID: plan.walls[1].id, width: 3 }], nits: 450, floor: 'concrete-grey' };
  return b;
}
if (process.env.UPDATE_FIXTURE) writeFileSync(fixture, JSON.stringify(stageBundle(), null, 2));

export function stageReadings(b: ProjectBundle) {
  const l = b.project.locations[0];
  const scanID = l.primaryScanID;
  const plan = scanID ? b.plans[scanID] : undefined;
  const scan = l.scans.find(s => s.id === scanID);
  const lights = (l.lights ?? []).filter(x => !x.scanID || x.scanID === scanID);
  const scene = buildScene(lights, plan, l.display?.windowTransmission ?? 0.78, environment(l, plan, scan));
  const out: Record<string, number> = {};
  for (const m of meterPoints(l, scanID)) out[m.key] = reading(m.point, m.normal, scene).lux;
  const sun = sunPlacement(l, scan);
  return { out, sun };
}

describe('Swift parity (studio and daylight)', () => {
  const bundle: ProjectBundle = JSON.parse(readFileSync(fixture, 'utf8'));
  const { out, sun } = stageReadings(bundle);
  it('the fixture has daylight, a curtain and an LED wall', () => {
    expect(sun.from).toBe('clock');
    expect(Object.values(out).some(v => v > 100)).toBe(true);
  });
  const path = process.env.STAGE_READINGS;
  it.skipIf(!path || !existsSync(path))('matches the Swift calculator', () => {
    const swift = JSON.parse(readFileSync(path!, 'utf8')) as { readings: Record<string, number>; sunBearing: number; sunElevation: number };
    expect(Math.abs(swift.sunBearing - sun.bearing)).toBeLessThan(1e-6);
    expect(Math.abs(swift.sunElevation - sun.elevation)).toBeLessThan(1e-6);
    expect(Object.keys(swift.readings).sort()).toEqual(Object.keys(out).sort());
    for (const [k, v] of Object.entries(out)) expect(Math.abs(swift.readings[k] - v)).toBeLessThan(1e-6 * Math.max(1, v));
  });
});
