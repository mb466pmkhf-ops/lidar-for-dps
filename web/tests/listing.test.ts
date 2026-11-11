// "Build from a listing": the shared cases in fixtures/listings.json run here and in the Swift core
// tests (ListingReader.swift), so the phone and the planner read the same text the same way.
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { readListing, roomFromListing, sizeNote } from '../src/model/listing';
import { defaultRoom } from '../src/model/room';

interface Case { name: string; text: string; expect: Record<string, number | boolean | string> }
const fixture = JSON.parse(readFileSync(new URL('./fixtures/listings.json', import.meta.url), 'utf8')) as { cases: Case[] };
const KEYS = ['length', 'width', 'ceiling', 'area', 'windows', 'door'] as const;

describe('reading a studio listing', () => {
  for (const c of fixture.cases) {
    it(c.name, () => {
      const r = readListing(c.text);
      for (const k of KEYS) expect(r[k], k).toEqual(c.expect[k]);
      expect(r.sizeSource).toBe(c.expect.sizeSource);
      expect(r.alternatives).toHaveLength(c.expect.alternatives as number);
    });
  }

  it('quotes the listing as it was written', () => {
    const r = readListing('Studio 2: 15m × 10m × 6m to grid');
    expect(r.findings[0].quote).toBe('Studio 2: 15m × 10m × 6m to grid');
  });

  it('keeps what the listing does not say', () => {
    const spec = roomFromListing(readListing('Ceiling height 5 m'), { ...defaultRoom, length: 9, width: 7 });
    expect(spec).toMatchObject({ length: 9, width: 7, ceiling: 5, windows: defaultRoom.windows, door: defaultRoom.door });
  });

  it('clamps a huge stage to what a drawn room can be', () => {
    const spec = roomFromListing(readListing('Stage 90m x 45m x 18m'));
    expect(spec.length).toBe(60);
    expect(spec.width).toBe(45);
    expect(spec.ceiling).toBe(18);
  });

  it('says where the size came from', () => {
    expect(sizeNote(readListing('100 sqm loft'))).toMatch(/square/);
    expect(sizeNote(readListing('nothing here'))).toMatch(/No room size/);
  });
});
