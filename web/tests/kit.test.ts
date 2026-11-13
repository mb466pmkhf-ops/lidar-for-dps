import { describe, expect, it } from 'vitest';
import { demoBundle } from '../src/model/demo';
import { kitList, kitText } from '../src/model/kit';

describe('kit list', () => {
  const loc = demoBundle().project.locations[0];
  const k = kitList(loc.lights ?? []);
  it('counts units, grip and stands from the sample', () => {
    const units = k.units.reduce((s, l) => s + l.qty, 0);
    expect(units).toBe((loc.lights ?? []).filter(l => !['bounce', 'negative', 'flag', 'diffusion'].includes(l.kind)).length);
    expect(k.grip.length).toBeGreaterThan(0);
    expect(k.stands.reduce((s, l) => s + l.qty, 0)).toBeGreaterThan(0);
  });
  it('rated power is at least the draw as set', () => {
    expect(k.drawRated).toBeGreaterThanOrEqual(k.drawNow);
    expect(k.drawNow).toBeGreaterThan(0);
  });
  it('writes a plain-text list', () => {
    const t = kitText(k, 'Sample');
    expect(t).toMatch(/^Sample\n/);
    expect(t).toContain('Units');
    expect(t).toMatch(/A at 230 V/);
  });
  it('lists a gel once per unit that carries it', () => {
    const l = { ...(loc.lights ?? [])[0], filterIDs: ['cto-half'] };
    expect(kitList([l, { ...l, id: 'x' }]).gels).toEqual([{ qty: 2, item: '½ CTO' }]);
  });
});
