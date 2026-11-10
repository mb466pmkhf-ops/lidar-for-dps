// Cross-checks the TypeScript lighting maths against the Swift original. CI's core-tests job runs
// the Swift calculator over tests/fixtures/parity-bundle.json (a project written by the web app,
// so it also proves the phone can decode web edits) and saves its readings; this test compares.
// Locally, without Swift, the comparison is skipped and only the fixture is checked.
import { describe, expect, it } from 'vitest';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { buildScene, grid, meterPoints, reading, vec } from '../src/model/calculator';
import { demoBundle } from '../src/model/demo';
import type { ProjectBundle } from '../src/model/types';

const fixture = new URL('./fixtures/parity-bundle.json', import.meta.url);
if (process.env.UPDATE_FIXTURE) writeFileSync(fixture, JSON.stringify(demoBundle(), null, 2));
const bundle: ProjectBundle = JSON.parse(readFileSync(fixture, 'utf8'));

export function webReadings(b: ProjectBundle) {
  const loc = b.project.locations[0];
  const scanID = loc.primaryScanID;
  const plan = scanID ? b.plans[scanID] : undefined;
  const lights = (loc.lights ?? []).filter(l => !l.scanID || l.scanID === scanID);
  const scene = buildScene(lights, plan, loc.display?.windowTransmission ?? 0.78);
  const out: Record<string, number> = {};
  for (const m of meterPoints(loc, scanID)) out[m.key] = reading(m.point, m.normal, scene).lux;
  const g = grid(plan!.bounds, 12, 10, 1.5, scene, () => vec(0, 1, 0));
  return { out, g };
}

describe('Swift parity', () => {
  const { out, g } = webReadings(bundle);
  it('the fixture has lights and meters', () => {
    expect(Object.keys(out).length).toBeGreaterThanOrEqual(3);
    expect(Object.values(out).some(v => v > 1)).toBe(true);
  });
  const path = process.env.PARITY_READINGS;
  it.skipIf(!path || !existsSync(path))('matches the Swift calculator at every meter, face and grid cell', () => {
    const swift = JSON.parse(readFileSync(path!, 'utf8')) as { readings: Record<string, number>; grid: number[] };
    expect(Object.keys(swift.readings).sort()).toEqual(Object.keys(out).sort());
    for (const [k, v] of Object.entries(out)) expect(Math.abs(swift.readings[k] - v)).toBeLessThan(1e-6 * Math.max(1, v));
    expect(swift.grid.length).toBe(g.length);
    g.forEach((v, i) => expect(Math.abs(swift.grid[i] - v)).toBeLessThan(1e-6 * Math.max(1, v)));
  });
});
