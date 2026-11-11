// Known quirks (web/src/model/quirks.ts) and the order of the fixture and camera libraries.
// The quirk table must match FrameScout/Core/Models/KnownQuirks.swift word for word, so the phone,
// the web and the desktop say the same thing about each unit.
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { fixtureQuirks, sensorQuirks, type UnitQuirk } from '../src/model/quirks';
import { categoryLabel, profiles, type FixtureCategory } from '../src/model/photometrics';
import { sensorPresets, sensorFor } from '../src/model/camera';

const read = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8');
const unescape = (s: string) => s.replace(/\\"/g, '"').replace(/\\\\/g, '\\');

function swiftQuirks(): { fixtures: Record<string, UnitQuirk[]>; sensors: Record<string, UnitQuirk[]> } {
  const swift = read('../../FrameScout/Core/Models/KnownQuirks.swift');
  const consts = new Map<string, UnitQuirk>();
  const re = /private static let (\w+) = UnitQuirk\(text: "((?:[^"\\]|\\.)*)",\s*source: "((?:[^"\\]|\\.)*)"(?:, url: "((?:[^"\\]|\\.)*)")?\)/g;
  for (const m of swift.matchAll(re)) consts.set(m[1], m[4] ? { text: unescape(m[2]), source: unescape(m[3]), url: unescape(m[4]) } : { text: unescape(m[2]), source: unescape(m[3]) });
  const table = (name: string) => {
    const body = swift.split(`static let ${name}: [String: [UnitQuirk]] = [`)[1].split('\n    ]')[0];
    const out: Record<string, UnitQuirk[]> = {};
    for (const m of body.matchAll(/"([^"]+)": \[([^\]]*)\]/g)) out[m[1]] = m[2].split(',').map(x => consts.get(x.trim())!);
    return out;
  };
  return { fixtures: table('fixtures'), sensors: table('sensors') };
}

describe('known quirks', () => {
  it('match the Swift table word for word', () => {
    const sw = swiftQuirks();
    expect(Object.keys(sw.fixtures).length).toBe(profiles.length);
    expect(sw.fixtures).toEqual(fixtureQuirks);
    expect(sw.sensors).toEqual(sensorQuirks);
  });

  it('cover every fixture type and camera format, and nothing else', () => {
    expect(Object.keys(fixtureQuirks).sort()).toEqual(profiles.map(p => p.id).sort());
    expect(Object.keys(sensorQuirks).sort()).toEqual(sensorPresets.map(s => s.id).sort());
    for (const list of [...Object.values(fixtureQuirks), ...Object.values(sensorQuirks)]) expect(list.length).toBeGreaterThan(0);
  });

  it('are short, sourced, and keep fixture text free of brand names', () => {
    const all = [...Object.values(fixtureQuirks), ...Object.values(sensorQuirks)].flat();
    for (const q of all) {
      expect(q.text.length).toBeLessThanOrEqual(170);
      expect(q.source.length).toBeGreaterThan(0);
      if (q.url) expect(q.url.startsWith('https://')).toBe(true);
    }
    const brands = /\b(ARRI|Aputure|Amaran|Litepanels|Astera|Nanlite|Godox|Creamsource|Kino|Mole|Quasar|SkyPanel|Titan|Orbiter)\b/i;
    for (const q of Object.values(fixtureQuirks).flat()) expect(q.text).not.toMatch(brands);
  });
});

describe('library order', () => {
  it('lists fixtures family by family, small to large', () => {
    const order = Object.keys(categoryLabel) as FixtureCategory[];
    for (let i = 1; i < profiles.length; i++) {
      const a = profiles[i - 1], b = profiles[i];
      expect(order.indexOf(a.category)).toBeLessThanOrEqual(order.indexOf(b.category));
      if (a.category === b.category) expect(a.ratedPower).toBeLessThanOrEqual(b.ratedPower);
    }
  });

  it('lists camera makers A to Z with generic formats last, same as the phone', () => {
    expect([...new Set(sensorPresets.map(s => s.manufacturer))]).toEqual(['ARRI', 'RED', 'Sony', '']);
    const swift = read('../../FrameScout/Core/Models/Camera.swift');
    const sw = [...swift.matchAll(/SensorFormat\(id: "([^"]+)", manufacturer: "([^"]*)", name: "([^"]+)", width: ([\d.]+), height: ([\d.]+)\)/g)]
      .map(m => ({ id: m[1], manufacturer: m[2], name: m[3], width: Number(m[4]), height: Number(m[5]) }));
    expect(sw).toEqual(sensorPresets);
  });

  it('falls back to the default camera for an unknown format', () => {
    expect(sensorFor({ sensorID: 'no-such-camera' } as never).id).toBe('arri-minilf-og');
  });
});
