import { describe, expect, it } from 'vitest';
import { area, feetInches, fromInput, metres, roomSize, toInput } from '../src/ui/format';

describe('lengths in metres or feet', () => {
  it('formats feet and inches to the nearest inch', () => {
    expect(feetInches(3.048)).toBe('10′ 0″');
    expect(feetInches(1.65)).toBe('5′ 5″');
    expect(metres(2.1, 'imperial')).toBe('6′ 11″');
    expect(metres(2.1, 'metric')).toBe('2.10 m');
    expect(roomSize(4.8, 6.2, 'imperial')).toBe('15′ 9″ × 20′ 4″');
    expect(area(29.76, 'imperial')).toBe('320 ft²');
  });
  it('reads typed feet, feet and inches, and metres', () => {
    expect(fromInput('10', 'imperial')).toBeCloseTo(3.048, 6);
    expect(fromInput(`12'6"`, 'imperial')).toBeCloseTo(12.5 * 0.3048, 6);
    expect(fromInput('12 6', 'imperial')).toBeCloseTo(12.5 * 0.3048, 6);
    expect(fromInput('12′ 6″', 'imperial')).toBeCloseTo(12.5 * 0.3048, 6);
    expect(fromInput('4,5', 'metric')).toBe(4.5);
    expect(fromInput('abc', 'imperial')).toBeUndefined();
  });
  it('round-trips a field value', () => {
    expect(toInput(3.048, 'imperial')).toBe(10);
    expect(toInput(4.5, 'metric')).toBe(4.5);
  });
});
