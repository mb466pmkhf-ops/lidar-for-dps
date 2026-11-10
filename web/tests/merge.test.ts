import { describe, expect, it } from 'vitest';
import { mergeDocuments } from '../src/sync/merge';

const base = {
  id: 'P', name: 'Shoot', modifiedAt: '2026-11-01T10:00:00Z',
  locations: [{ id: 'L1', name: 'Flat', lights: [{ id: 'A', name: 'Key', dimmer: 1 }, { id: 'B', name: 'Fill', dimmer: 0.5 }] }],
};
const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));

describe('three-way merge', () => {
  it('keeps edits to different lights from both devices', () => {
    const phone = clone(base); phone.locations[0].lights[0].dimmer = 0.7;
    const web = clone(base); web.locations[0].lights[1].name = 'Fill (bounce)';
    const m = mergeDocuments(base, web, phone);
    expect(m.locations[0].lights[0].dimmer).toBe(0.7);
    expect(m.locations[0].lights[1].name).toBe('Fill (bounce)');
  });

  it('keeps lights added on both sides, in place', () => {
    const phone = clone(base); phone.locations[0].lights.push({ id: 'C', name: 'Back', dimmer: 1 });
    const web = clone(base); web.locations[0].lights.splice(1, 0, { id: 'D', name: 'Edge', dimmer: 1 });
    const m = mergeDocuments(base, web, phone);
    expect(m.locations[0].lights.map(l => l.id)).toEqual(['A', 'D', 'B', 'C']);
  });

  it('deletes on one side unless the other side changed the item', () => {
    const phone = clone(base); phone.locations[0].lights.splice(0, 1);
    const web = clone(base); web.locations[0].lights[1].dimmer = 0.2;
    expect(mergeDocuments(base, web, phone).locations[0].lights.map(l => l.id)).toEqual(['B']);
    const web2 = clone(base); web2.locations[0].lights[0].dimmer = 0.2;
    expect(mergeDocuments(base, web2, phone).locations[0].lights.map(l => l.id)).toEqual(['A', 'B']);
  });

  it('same field on both sides keeps the local value; modifiedAt takes the later', () => {
    const phone = clone(base); phone.name = 'Phone'; phone.modifiedAt = '2026-11-02T10:00:00Z';
    const web = clone(base); web.name = 'Web'; web.modifiedAt = '2026-11-01T12:00:00Z';
    const m = mergeDocuments(base, web, phone);
    expect(m.name).toBe('Web');
    expect(m.modifiedAt).toBe('2026-11-02T10:00:00Z');
  });

  it('keeps unknown keys from newer app versions', () => {
    const phone = { ...clone(base), setups: [{ id: 'S', name: 'Night' }] };
    const web = clone(base); web.name = 'Renamed';
    const m = mergeDocuments(base, web, phone) as typeof phone;
    expect(m.setups).toEqual([{ id: 'S', name: 'Night' }]);
    expect(m.name).toBe('Renamed');
  });
});
