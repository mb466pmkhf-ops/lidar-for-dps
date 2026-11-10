import { describe, expect, it } from 'vitest';
import { defaultExposure, keyLux, stopLabel } from '../src/model/exposure';
import { reading, readingShort, readingText, readingUnit } from '../src/ui/format';

describe('reading units', () => {
  const e = defaultExposure();
  it('defaults to T-stop', () => {
    expect(readingUnit()).toBe('tStop');
    expect(reading(keyLux(e), e)).toBe(stopLabel(e.tStop));
  });
  it('reads one stop higher for double the light', () => {
    expect(reading(keyLux(e) * 2, e, 'tStop')).toBe(stopLabel(e.tStop * Math.SQRT2));
    expect(reading(keyLux(e) * 2, e, 'stops')).toBe('+1');
  });
  it('keeps lux and adds foot-candles', () => {
    expect(reading(536, e, 'lux')).toBe('536 lx');
    expect(reading(1076.4, e, 'footCandles')).toBe('100 fc');
  });
  it('marks every form as approximate', () => {
    for (const u of ['tStop', 'stops', 'lux', 'footCandles'] as const) {
      expect(readingShort(300, e, u).startsWith('≈')).toBe(true);
      expect(readingText(300, e, u).startsWith('≈')).toBe(true);
    }
  });
});
