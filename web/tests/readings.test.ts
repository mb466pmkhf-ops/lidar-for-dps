import { describe, expect, it } from 'vitest';
import { defaultExposure, keyLux, meterStop, steppedISO, steppedStop, stopLabel } from '../src/model/exposure';
import { migratedExtra, reading, readingExtra, readingShort, readingText } from '../src/ui/format';

// Same cases as "Readings (T-stop first, lux optional)" in Tests/CoreLogicTests/main.swift.
describe('readings lead with the T-stop', () => {
  const e = defaultExposure();
  it('shows the stop only until lux is switched on', () => {
    expect(readingExtra()).toBe('off');
    expect(reading(keyLux(e), e)).toBe(stopLabel(e.tStop));
  });
  it('reads one stop higher for double the light', () => {
    expect(reading(keyLux(e) * 2, e, 'off')).toBe(stopLabel(e.tStop * Math.SQRT2));
  });
  it('puts lux or foot-candles after the stop', () => {
    expect(reading(536, e, 'lux').endsWith(' · 536 lx')).toBe(true);
    expect(reading(1076.4, e, 'footCandles').endsWith(' · 100 fc')).toBe(true);
    expect(readingShort(300, e, 'lux').startsWith('≈ T')).toBe(true);
    expect(readingText(300, e, 'off')).toContain(`at ${stopLabel(e.tStop)}`);
  });
  it('never reads T0 when there is no light', () => {
    expect(meterStop(e, 0)).toBe('under T0.5');
    expect(meterStop(e, 1e-4)).toBe('under T0.5');
  });
  it('keeps an old lux choice', () => {
    expect(migratedExtra('lux')).toBe('lux');
    expect(migratedExtra('footCandles')).toBe('footCandles');
    expect(migratedExtra('stops')).toBeUndefined();
  });
  it('steps the stop and ISO in thirds and stops at the ends', () => {
    expect(steppedStop(2.8, 1)).toBeCloseTo(3.1748, 3);
    expect(steppedStop(2.8, 3)).toBeCloseTo(4, 9);
    expect(steppedStop(1, -1)).toBe(1);
    expect(steppedISO(800, 1)).toBe(1000);
    expect(steppedISO(12800, 1)).toBe(12800);
  });
});
