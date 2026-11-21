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

import { BATTERY_USABLE, SUPPLIES, batteryMinutes, circuitPlan, circuitWatts, kitCost, parseRate, parseRates, ratesJSON, runTimeLabel, supplyByID } from '../src/model/kit';
import { applyProfile, profileByID } from '../src/model/photometrics';
import { newLight } from '../src/model/factory';

describe('power planning', () => {
  const unit = (id: string) => applyProfile(newLight('fresnel', { x: 0, z: 0 }, 0), profileByID(id)!);
  it('a UK 13 A socket carries about 2.4 kW for hours, a US 15 A circuit about 1.4 kW', () => {
    expect(circuitWatts(supplyByID('uk13'))).toBeCloseTo(2392, 0);
    expect(circuitWatts(supplyByID('us15'))).toBeCloseTo(1440, 0);
    expect(SUPPLIES.map(s => s.id)).toEqual(['uk13', 'eu16', 'us15', 'us20']);
  });
  it('packs units onto circuits without splitting one, and flags units too big for any', () => {
    const lights = [unit('cob-1200-d'), unit('cob-1200-d'), unit('cob-600-d'), unit('hmi-4000-par')];
    const uk = circuitPlan(lights, supplyByID('uk13'));
    expect(uk.tooBig).toEqual(['4K HMI PAR']);
    expect(uk.circuits).toBe(2);
    expect(circuitPlan(lights, supplyByID('us15')).circuits).toBe(3);
    expect(circuitPlan([], supplyByID('uk13'))).toEqual({ supply: supplyByID('uk13'), circuits: 0, tooBig: [] });
  });
  it('battery run time uses 85 % of the pack', () => {
    expect(BATTERY_USABLE).toBe(0.85);
    expect(batteryMinutes(100, 98)).toBeCloseTo(49.98, 1);
    expect(runTimeLabel(50, 98)).toBe('1 h 40 min');
    expect(runTimeLabel(100, 98)).toBe('50 min');
    expect(runTimeLabel(1200, 98)).toBe('mains');
    expect(runTimeLabel(0, 98)).toBe('');
  });
});

describe('your day rates', () => {
  const loc = demoBundle().project.locations[0];
  const k = kitList(loc.lights ?? []);
  it('prices only the lines with a rate and lists the rest as missing', () => {
    const c = kitCost(k, { currency: '£', items: { 'Combo stand': 10, 'C-stand': 8, 'Bounce': 0 } });
    expect(c.perDay).toBe(2 * 10 + 8);
    expect(c.missing).toContain('1200 W COB LED · daylight');
    expect(c.lines.find(l => l.item === 'Bounce')?.total).toBe(0);
  });
  it('round-trips through JSON and rejects anything else', () => {
    const r = { currency: '$', items: { 'C-stand': 12.5 } };
    expect(parseRates(ratesJSON(r))).toEqual(r);
    expect(parseRates('{"items":{}}')).toBeUndefined();
    expect(parseRates('not json')).toBeUndefined();
    expect(parseRates('{"framescanRates":1,"items":{"a":-1,"b":"x","c":3}}')).toEqual({ currency: '£', items: { c: 3 } });
  });
  it('reads a typed rate with either decimal mark', () => {
    expect(parseRate('12.5')).toBe(12.5);
    expect(parseRate('12,50')).toBe(12.5);
    expect(parseRate('1,250')).toBe(1250);
    expect(parseRate('1,250.50')).toBe(1250.5);
    expect(parseRate('1.250,50')).toBe(1250.5);
    expect(parseRate('1.250.000')).toBe(1250000);
    expect(parseRate(' 0 ')).toBe(0);
    expect(parseRate('12.')).toBe(12);
    expect(parseRate('0.125')).toBe(0.125);
    expect(parseRate('0,125')).toBe(0.125);
    expect(parseRate('1.250')).toBe(1.25);
    expect(parseRate('')).toBeUndefined();
    expect(parseRate('-3')).toBeUndefined();
    expect(parseRate('abc')).toBeUndefined();
    expect(parseRate('1e20')).toBeUndefined();
    expect(parseRate('99999999999')).toBeUndefined();
    expect(parseRates('{"framescanRates":1,"items":{"a":1e20,"c":3}}')).toEqual({ currency: '£', items: { c: 3 } });
  });
  it('kit text adds circuits and rates when given', () => {
    const t = kitText(k, 'Sample', loc.lights, { currency: '£', items: { 'C-stand': 8 } });
    expect(t).toMatch(/UK 13 A sockets: 1 separate circuit/);
    expect(t).toMatch(/Your day rates\n  1 × C-stand at £8 = £8\n  Per day: £8 \(no rate for /);
  });
});
