// The lens sets must match FrameScout/Core/Models/Lenses.swift, so the phone's viewfinder, the
// phone's plan and the desktop offer the same lenses.
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { COVERAGE, LENS_SERIES, PLAN_LENS_SERIES, mayVignette, nearestFocal, rangeLabel } from '../src/model/lenses';
import { sensorPresets } from '../src/model/camera';

const read = (rel: string) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

describe('lens sets', () => {
  it('match the Swift library entry for entry', () => {
    const swift = read('../../FrameScout/Core/Models/Lenses.swift');
    const body = swift.slice(swift.indexOf('static let series: [LensSeries] = ['));
    const re = /LensSeries\(id: "([^"]+)", maker: "([^"]*)", name: "([^"]+)",\s*focalLengths: \[([^\]]+)\](, isZoom: true)?(?:, squeeze: ([\d.]+))?, coverage: \.(\w+)\)/g;
    const sw = [...body.matchAll(re)].map(m => ({
      id: m[1], maker: m[2], name: m[3], focalLengths: m[4].split(',').map(Number), isZoom: !!m[5], squeeze: m[6] ? Number(m[6]) : 1, coverage: m[7],
    }));
    expect(sw.length).toBeGreaterThan(20);
    expect(LENS_SERIES.map(s => ({ ...s, isZoom: !!s.isZoom }))).toEqual(sw);
    const cov = (c: string) => Number(swift.match(new RegExp(`case \\.${c}: return (\\d+)`))![1]);
    for (const c of ['super35', 'fullFrame', 'largeFormat'] as const) expect(COVERAGE[c].maxDiagonal).toBe(cov(c));
  });

  it('leave anamorphic sets out of the plan', () => {
    expect(PLAN_LENS_SERIES.every(s => s.squeeze === 1)).toBe(true);
    expect(PLAN_LENS_SERIES.some(s => s.id === 'cooke-s4i')).toBe(true);
  });

  it('snap, label and warn the same way as the phone', () => {
    const cooke = LENS_SERIES.find(s => s.id === 'cooke-s4i')!;
    const zoom = LENS_SERIES.find(s => s.id === 'angenieux-24-290')!;
    expect(nearestFocal(cooke, 30)).toBe(32);
    expect(nearestFocal(zoom, 12)).toBe(24);
    expect(nearestFocal(zoom, 61)).toBe(61);
    expect(rangeLabel(LENS_SERIES.find(s => s.id === 'canon-cne-15-47')!)).toBe('15.5–47 mm');
    expect(rangeLabel(cooke)).toBe('18 lenses, 12–300 mm');
    const lf = sensorPresets.find(s => s.id === 'arri-minilf-og')!, ff = sensorPresets.find(s => s.id === 'generic-ff')!;
    const cp3 = LENS_SERIES.find(s => s.id === 'zeiss-cp3')!;
    expect(mayVignette(cp3, lf)).toBe(true);
    expect(mayVignette(cp3, lf, 2.39)).toBe(false);
    expect(mayVignette(cp3, ff)).toBe(false);
  });
});
