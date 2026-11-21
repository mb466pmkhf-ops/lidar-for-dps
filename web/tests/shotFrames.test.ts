import { describe, expect, it } from 'vitest';
import { frameRect } from '../src/sync/shotFrames';

describe('frameRect', () => {
  it('fits a wide frame to 92 % of the width', () => {
    const r = frameRect(1000, 800, 2.39);
    expect(r.w).toBeCloseTo(920);
    expect(r.h).toBeCloseTo(920 / 2.39);
    expect(r.x).toBeCloseTo(40);
    expect(r.y).toBeCloseTo((800 - 920 / 2.39) / 2);
  });
  it('fits a tall frame to 92 % of the height', () => {
    const r = frameRect(1600, 900, 4 / 3);
    expect(r.h).toBeCloseTo(828);
    expect(r.w).toBeCloseTo(828 * 4 / 3);
    expect(r.x + r.w / 2).toBeCloseTo(800);
  });
  it('falls back to 16:9 for a missing ratio', () => {
    const r = frameRect(1600, 900, 0);
    expect(r.w / r.h).toBeCloseTo(16 / 9);
  });
});
