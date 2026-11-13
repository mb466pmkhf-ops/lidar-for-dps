// 150 generated lighting setups (tests/support/sweep.ts), each checked for sane readings: finite and
// never negative, the parts adding up to the total, nothing from a unit that's off, flags never
// adding direct light, T-stops that round-trip, and levels the setups solve for actually reached.
// In CI the Swift calculator reads the same scenes (tests/fixtures/sweep-bundles.json) and its
// readings are compared here (SWEEP_READINGS), so the phone and the desktop agree on all of them.
import { describe, expect, it } from 'vitest';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { buildScene, grid, meterPoints, reading, solveOutput, vec, type MeterPoint } from '../src/model/calculator';
import { environment, AMBIENT_IDS } from '../src/model/stage';
import { KIND_INFO, fixtureProfile } from '../src/model/photometrics';
import { meterStop, tStopForLux, luxForTStop, withDefaults, stopLabel } from '../src/model/exposure';
import { bodyRadius, isSolid } from '../src/model/placement';
import type { FloorPlan, LightFixture, Location, ProjectBundle } from '../src/model/types';
import { sweepCases, type SweepCase } from './support/sweep';

const fixture = new URL('./fixtures/sweep-bundles.json', import.meta.url);
const cases = sweepCases();
if (process.env.UPDATE_FIXTURE) writeFileSync(fixture, JSON.stringify(cases.map(c => ({ id: c.id, family: c.family, title: c.title, bundle: c.bundle }))));

interface Parts { loc: Location; plan: FloorPlan; lights: LightFixture[]; scanID: string }
const parts = (b: ProjectBundle): Parts => {
  const loc = b.project.locations[0];
  const scanID = loc.primaryScanID!;
  return { loc, plan: b.plans[scanID], lights: (loc.lights ?? []).filter(l => !l.scanID || l.scanID === scanID), scanID };
};
/** What the planner shows: same scene as Planner.tsx builds. */
const sceneOf = (p: Parts, lights = p.lights, loc = p.loc) =>
  buildScene(lights, p.plan, loc.display?.windowTransmission ?? 0.78, environment(loc, p.plan, loc.scans.find(s => s.id === p.scanID)));

export function sweepReadings(c: SweepCase) {
  const p = parts(c.bundle);
  const scene = sceneOf(p);
  const readings: Record<string, number> = {};
  for (const m of meterPoints(p.loc, p.scanID)) readings[m.key] = reading(m.point, m.normal, scene).lux;
  return { readings, grid: grid(p.plan.bounds, 8, 6, 1.2, scene, () => vec(0, 1, 0)) };
}

const emits = (l: LightFixture) => KIND_INFO[l.kind].emits;
const direct = (r: ReturnType<typeof reading>, id: string) => r.contributions.filter(x => x.lightID === id && !x.viaBounce).reduce((s, x) => s + x.lux, 0);

describe('lighting sweep: 150 setups', () => {
  it('has 150 varied scenes and the fixture matches the generator', () => {
    expect(cases.length).toBe(150);
    expect(new Set(cases.map(c => c.family)).size).toBe(7);
    const saved = JSON.parse(readFileSync(fixture, 'utf8')) as { id: string; bundle: ProjectBundle }[];
    expect(saved.map(s => s.id)).toEqual(cases.map(c => c.id));
    // Same scenes byte for byte, so the Swift run reads what this test checks.
    expect(JSON.stringify(saved.map(s => s.bundle))).toBe(JSON.stringify(cases.map(c => c.bundle)));
  });

  for (const c of cases) {
    describe(`${c.id} ${c.title}`, () => {
      const p = parts(c.bundle);
      const scene = sceneOf(p);
      const meters = meterPoints(p.loc, p.scanID);
      const e = withDefaults(p.loc.exposure);

      it('readings are finite, never negative, and their parts add up', () => {
        for (const m of meters) {
          const r = reading(m.point, m.normal, scene);
          expect(Number.isFinite(r.lux), `${m.name}`).toBe(true);
          expect(r.lux).toBeGreaterThanOrEqual(0);
          const sum = r.contributions.reduce((s, x) => s + x.lux, 0);
          expect(Math.abs(sum - r.lux)).toBeLessThanOrEqual(1e-9 * Math.max(1, r.lux));
          for (const x of r.contributions) expect(x.lux).toBeGreaterThan(0);
          // Brighter than direct summer sun (≈ 100 klx) only close in front of a unit.
          if (r.lux > 150000) {
            const nearest = Math.min(...p.lights.filter(emits).map(l => Math.hypot(l.position.x - m.point.x, l.height - m.point.y, l.position.z - m.point.z)));
            expect(nearest, `${m.name} reads ${Math.round(r.lux)} lx`).toBeLessThan(1.5);
          }
        }
        for (const v of grid(p.plan.bounds, 8, 6, 1.2, scene, () => vec(0, 1, 0))) expect(Number.isFinite(v) && v >= 0).toBe(true);
      });

      it('a unit that is off gives nothing, and nothing on means dark', () => {
        const off = new Set(p.lights.filter(l => !l.isOn).map(l => l.id));
        for (const m of meters) for (const x of reading(m.point, m.normal, scene).contributions) expect(off.has(x.lightID)).toBe(false);
        const dark = sceneOf(p, p.lights.map(l => ({ ...l, isOn: false })), { ...p.loc, daylight: undefined, studio: p.loc.studio && { ...p.loc.studio, nits: 0 } });
        for (const m of meters) expect(reading(m.point, m.normal, dark).lux).toBe(0);
      });

      it('grip never adds direct light from a unit, and taking it away never darkens one', () => {
        const grip = p.lights.filter(l => !emits(l));
        if (!grip.length) return;
        const bare = sceneOf(p, p.lights.filter(emits));
        for (const m of meters) {
          const withGrip = reading(m.point, m.normal, scene), without = reading(m.point, m.normal, bare);
          for (const l of p.lights.filter(emits)) expect(direct(withGrip, l.id)).toBeLessThanOrEqual(direct(without, l.id) * (1 + 1e-9) + 1e-9);
          for (const id of [AMBIENT_IDS.sun]) expect(direct(withGrip, id)).toBeLessThanOrEqual(direct(without, id) * (1 + 1e-9) + 1e-9);
        }
      });

      it('more output never means less light', () => {
        for (const l of p.lights.filter(x => emits(x) && x.isOn && x.dimmer < 0.95)) {
          const up = sceneOf(p, p.lights.map(x => (x.id === l.id ? { ...x, dimmer: 1 } : x)));
          for (const m of meters) expect(reading(m.point, m.normal, up).lux).toBeGreaterThanOrEqual(reading(m.point, m.normal, scene).lux * (1 - 1e-9));
        }
      });

      it('stops are labelled and round-trip', () => {
        for (const m of meters) {
          const lux = reading(m.point, m.normal, scene).lux;
          const label = meterStop(e, lux);
          expect(label).toMatch(/^(under )?T\d/);
          expect(label).not.toMatch(/NaN|Infinity|T0(?![.]\d)/);
          if (lux > 0.01) expect(luxForTStop(e, tStopForLux(e, lux)) / lux).toBeCloseTo(1, 9);
        }
        expect(stopLabel(e.tStop)).toMatch(/^T\d/);
      });

      it('a level the planner solves for is the level you get', () => {
        const pick: MeterPoint[] = meters.slice(0, 2);
        for (const l of p.lights.filter(x => emits(x) && x.isOn).slice(0, 4)) for (const m of pick) {
          const target = luxForTStop(e, e.tStop);
          const s = solveOutput(l, target, m.point, m.normal, p.lights, p.plan, p.loc.display?.windowTransmission ?? 0.78, environment(p.loc, p.plan, p.loc.scans[0]));
          if (s.kind !== 'output') continue;
          expect(s.output).toBeGreaterThanOrEqual(fixtureProfile(l).minOutput - 1e-9);
          const set = sceneOf(p, p.lights.map(x => (x.id === l.id ? { ...x, dimmer: s.output } : x)));
          expect(reading(m.point, m.normal, set).lux / target).toBeCloseTo(1, 6);
        }
      });

      it('nobody stands inside furniture', () => {
        for (const ch of p.loc.characters ?? []) {
          if (ch.posture === 'sitting' && ch.seatHeight !== undefined) continue;
          for (const o of p.plan.objects.filter(isSolid)) {
            const dx = ch.position.x - o.center.x, dz = ch.position.z - o.center.z;
            const u = dx * Math.cos(o.rotation) + dz * Math.sin(o.rotation), v = -dx * Math.sin(o.rotation) + dz * Math.cos(o.rotation);
            const inside = Math.abs(u) < o.width / 2 + bodyRadius(ch) - 0.02 && Math.abs(v) < o.depth / 2 + bodyRadius(ch) - 0.02;
            expect(inside, `${ch.name} inside ${o.category}`).toBe(false);
          }
        }
      });
    });
  }

  const path = process.env.SWEEP_READINGS;
  it.skipIf(!path || !existsSync(path))('the Swift calculator gives the same readings for all 150', () => {
    const swift = JSON.parse(readFileSync(path!, 'utf8')) as Record<string, { readings: Record<string, number>; grid: number[] }>;
    expect(Object.keys(swift).sort()).toEqual(cases.map(c => c.id).sort());
    const off: string[] = [];
    for (const c of cases) {
      const web = sweepReadings(c), s = swift[c.id];
      if (Object.keys(s.readings).sort().join() !== Object.keys(web.readings).sort().join()) { off.push(`${c.id}: different meter points`); continue; }
      for (const [k, v] of Object.entries(web.readings)) if (!(Math.abs(s.readings[k] - v) <= 1e-6 * Math.max(1, v))) off.push(`${c.id} ${k}: web ${v} swift ${s.readings[k]}`);
      if (s.grid.length !== web.grid.length) { off.push(`${c.id}: grid size`); continue; }
      web.grid.forEach((v, i) => { if (!(Math.abs(s.grid[i] - v) <= 1e-6 * Math.max(1, v))) off.push(`${c.id} grid ${i}: web ${v} swift ${s.grid[i]}`); });
    }
    expect(off).toEqual([]);
  });
});
