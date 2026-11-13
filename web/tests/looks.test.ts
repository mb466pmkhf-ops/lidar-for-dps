import { describe, expect, it } from 'vitest';
import { demoBundle } from '../src/model/demo';
import { activeLook, deleteLook, looksOf, renameLook, saveLook, setShotLook, switchLook } from '../src/model/looks';

const room = () => demoBundle().project.locations[0];

describe('named looks per room', () => {
  it('saves the live lights as a look and makes it active', () => {
    const loc = saveLook(room(), 'Day');
    expect(looksOf(loc)).toHaveLength(1);
    expect(activeLook(loc)?.name).toBe('Day');
    expect(activeLook(loc)?.lights).toEqual(loc.lights);
    expect(activeLook(loc)?.lights).not.toBe(loc.lights);
  });
  it('switching keeps edits in the look you leave and loads the other', () => {
    let loc = saveLook(room(), 'Day');
    const day = activeLook(loc)!.id;
    loc = { ...loc, lights: (loc.lights ?? []).slice(0, 2) };
    loc = saveLook(loc, 'Night');
    const night = activeLook(loc)!.id;
    expect(loc.lights).toHaveLength(2);
    loc = { ...loc, lights: (loc.lights ?? []).map(l => ({ ...l, dimmer: 0.05 })) }; // edit Night
    loc = switchLook(loc, day);
    expect(loc.lights!.length).toBe(room().lights!.length);
    expect(loc.activeLookID).toBe(day);
    loc = switchLook(loc, night);
    expect(loc.lights).toHaveLength(2);
    expect(loc.lights!.every(l => l.dimmer === 0.05)).toBe(true);
  });
  it('switching to the look you are on changes nothing', () => {
    const loc = saveLook(room(), 'Day');
    expect(switchLook(loc, loc.activeLookID!)).toBe(loc);
  });
  it('rename and delete; deleting clears shot links and keeps the lights', () => {
    let loc = saveLook(room(), 'Day');
    const id = loc.activeLookID!;
    loc = renameLook(loc, id, 'Morning');
    expect(activeLook(loc)?.name).toBe('Morning');
    loc = setShotLook(loc, loc.shots[0].id, id);
    expect(loc.shots[0].lookID).toBe(id);
    const lights = loc.lights;
    loc = deleteLook(loc, id);
    expect(loc.looks).toBeUndefined();
    expect(loc.activeLookID).toBeUndefined();
    expect('lookID' in loc.shots[0]).toBe(false);
    expect(loc.lights).toBe(lights);
  });
  it('a nameless look gets a number', () => {
    expect(activeLook(saveLook(room(), '  '))?.name).toBe('Look 1');
  });
});
