// Same cases as "People" in Tests/CoreLogicTests/main.swift.
import { describe, expect, it } from 'vitest';
import { characterDefaults, characterTypes, defaultHair, eyeHeight, hairOf, isChild } from '../src/model/characters';
import { newCharacter } from '../src/model/factory';

describe('people', () => {
  it('has a universal adult between the man and the woman', () => {
    expect(characterTypes).toContain('universal');
    expect(isChild('universal')).toBe(false);
    expect(characterDefaults.universal).toBeGreaterThan(characterDefaults.woman);
    expect(characterDefaults.universal).toBeLessThan(characterDefaults.man);
    const u = newCharacter('universal', { x: 0, z: 0 }, 'Sam');
    expect(Math.abs(eyeHeight(u) / u.height - 0.936)).toBeLessThan(0.01);
  });
  it('hair follows the type until it is set, and ignores unknown values', () => {
    const u = newCharacter('universal', { x: 0, z: 0 }, 'Sam');
    expect(hairOf(u)).toBe('cropped');
    expect(hairOf({ ...u, hair: 'long' })).toBe('long');
    expect(hairOf({ ...u, hair: 'mohawk' as never })).toBe(defaultHair.universal);
  });
});
