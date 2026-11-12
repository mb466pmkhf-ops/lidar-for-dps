// A stress-test sweep: 150 lighting setups built the way the planner builds them (drawn rooms,
// furniture, people sitting and standing, units with modifiers, gels and barn doors, grip with rags
// and frame gels, studio backdrops round one or more walls, windows with sun, sky and curtains,
// cameras and exposures), from a fixed seed so every run makes the same scenes.
//
// web/tests/sweep.test.ts checks the readings for sanity and (in CI) against the Swift calculator,
// which reads the same scenes from tests/fixtures/sweep-bundles.json. The scenes are also loaded
// into the desktop 3D view by scripts/sweep-3d.mjs to look for drawing faults and console errors.
import type { CameraRig, ExposureSettings, FloorPlan, LightFixture, LightMeter, Location, PlanPoint, PrevisCharacter, ProjectBundle, Shot } from '../../src/model/types';
import { buildRoom, type RoomSpec } from '../../src/model/room';
import { applyProfile, modifiersFor, profiles, filters, profileByID, type FixtureProfile } from '../../src/model/photometrics';
import { bearingFrom, planDist } from '../../src/model/calculator';
import { newCamera, newCharacter, newLight, newMeter, newProject } from '../../src/model/factory';
import { DRAPES, FRAME_GELS, GRIP_SIZES, applyDrape, applyGripSize, drapesFor, setFloppyOpen, sizesFor, type GripKind } from '../../src/model/grip';
import { FURNITURE_PRESETS, placeFurniture } from '../../src/model/setPieces';
import { settlePeople } from '../../src/model/placement';
import { LIGHTING_SETUPS, buildSetup } from '../../src/model/setups';
import { BACKDROPS, FLOORS, type StudioSetup } from '../../src/model/stage';
import { sensorPresets } from '../../src/model/camera';
import { eyeHeight } from '../../src/model/characters';
import { isoSteps, frameRates, shutterAngles, thirdStops } from '../../src/model/exposure';
import type { CharacterType, HairStyle } from '../../src/model/types';

export type Family = 'empty' | 'classic' | 'location' | 'studio' | 'daylight' | 'grip' | 'edge';
export interface SweepCase { id: string; family: Family; title: string; bundle: ProjectBundle }

// MARK: Seeded randomness

function mulberry32(seed: number) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
class Rng {
  next: () => number;
  constructor(seed: number) { this.next = mulberry32(seed); }
  range(lo: number, hi: number) { return lo + (hi - lo) * this.next(); }
  int(lo: number, hi: number) { return Math.floor(this.range(lo, hi + 1)); }
  pick<T>(a: readonly T[]): T { return a[Math.floor(this.next() * a.length)]; }
  chance(p: number) { return this.next() < p; }
  r2(lo: number, hi: number) { return Math.round(this.range(lo, hi) * 100) / 100; }
}

const r2 = (v: number) => Math.round(v * 100) / 100;
const P = (x: number, z: number): PlanPoint => ({ x: r2(x), z: r2(z) });

// MARK: Pieces

interface Built { loc: Location; scanID: string; plan: FloorPlan; spec: RoomSpec }

function room(rng: Rng, spec?: Partial<RoomSpec>): Built {
  const full: RoomSpec = {
    shape: rng.chance(0.2) ? 'l' : 'box',
    length: rng.r2(4, 9), width: rng.r2(3, 6.5), ceiling: rng.r2(2.4, 3.4),
    windows: rng.int(0, 3), door: rng.chance(0.8),
    ...spec,
  };
  if (full.width > full.length) [full.width, full.length] = [full.length, full.width];
  const { location, scanID, plan } = buildRoom('Sweep room', full);
  location.scans[0].northOffset = rng.int(0, 359);
  return { loc: location, scanID, plan, spec: full };
}

/** A point inside the room, `margin` clear of the walls (the L's missing quarter avoided). */
function inside(rng: Rng, b: Built, margin = 0.6): PlanPoint {
  const { minX, maxX, minZ, maxZ } = b.plan.bounds;
  for (let i = 0; i < 40; i++) {
    const p = P(rng.range(minX + margin, maxX - margin), rng.range(minZ + margin, maxZ - margin));
    if (b.spec.shape === 'l' && p.x > -margin && p.z > -margin) continue;
    return p;
  }
  return P((minX + maxX) / 2 - 0.5, (minZ + maxZ) / 2 - 0.5);
}

function furnish(rng: Rng, b: Built, n: number) {
  for (let i = 0; i < n; i++) {
    const preset = rng.pick(FURNITURE_PRESETS);
    b.plan.objects.push(placeFurniture(b.plan, inside(rng, b, 0.4), preset));
  }
}

const TYPES: CharacterType[] = ['man', 'woman', 'universal', 'girl', 'boy'];
const HAIR: HairStyle[] = ['short', 'long', 'tied', 'cropped', 'bald'];

function people(rng: Rng, b: Built, n: number, sitting = 0.4): PrevisCharacter[] {
  const seats = b.plan.objects.filter(o => /sofa|chair|bed/i.test(o.category));
  const out: PrevisCharacter[] = [];
  for (let i = 0; i < n; i++) {
    const sit = rng.chance(sitting);
    const seat = sit && seats.length ? rng.pick(seats) : undefined;
    const c = newCharacter(rng.pick(TYPES), seat ? seat.center : inside(rng, b, 0.8), `Person ${i + 1}`, b.scanID);
    c.facing = rng.int(0, 359); c.skinTone = rng.int(1, 6); c.build = rng.r2(0.2, 0.8);
    if (rng.chance(0.4)) c.hair = rng.pick(HAIR);
    if (sit) c.posture = 'sitting';
    out.push(c);
  }
  return settlePeople(out, b.plan, b.scanID, [], true);
}

const EMITTERS = profiles;

function unit(rng: Rng, b: Built, target: PlanPoint, targetHeight: number, profile: FixtureProfile = rng.pick(EMITTERS), at?: PlanPoint): LightFixture {
  const pos = at ?? inside(rng, b, 0.5);
  let l = applyProfile(newLight(profile.kind, pos, bearingFrom(pos, target), b.scanID), profile);
  l.name = profile.name.split(' · ')[0];
  l.height = r2(Math.min(b.spec.ceiling - 0.25, rng.range(profile.category === 'practical' ? 0.5 : 1.2, 3.2)));
  const d = Math.max(0.3, planDist(pos, target));
  l.tilt = r2(-Math.atan2(l.height - targetHeight, d) * 180 / Math.PI);
  const mods = modifiersFor(profile);
  if (mods.length && rng.chance(0.6)) l.modifierID = rng.pick(mods).id;
  if (profile.beamRange && rng.chance(0.6)) l.beamAngle = r2(rng.range(profile.beamRange[0], profile.beamRange[1]));
  if (rng.chance(0.35)) {
    const n = rng.int(1, 2);
    l.filterIDs = Array.from(new Set(Array.from({ length: n }, () => rng.pick(filters).id)));
  }
  l.dimmer = rng.chance(0.3) ? 1 : r2(rng.range(Math.max(0.05, profile.minOutput), 1));
  if (rng.chance(0.12)) l.isOn = false;
  if (profile.hasBarnDoors && rng.chance(0.35)) l.barnDoors = { top: rng.int(0, 90), bottom: rng.int(20, 90), left: rng.int(0, 90), right: rng.int(10, 90) };
  if (profile.color.rgb && rng.chance(0.4)) { l.colorMode = 'rgb'; l.hue = rng.int(0, 359); l.saturation = rng.r2(0.2, 1); }
  else if (profile.color.maxKelvin > profile.color.minKelvin) l.colorTemperature = rng.int(profile.color.minKelvin, profile.color.maxKelvin);
  return l;
}

const GRIP: GripKind[] = ['bounce', 'negative', 'flag', 'diffusion'];

function grip(rng: Rng, b: Built, target: PlanPoint, kind: GripKind = rng.pick(GRIP), opts: { overhead?: boolean; at?: PlanPoint } = {}): LightFixture {
  const pos = opts.at ?? inside(rng, b, 0.6);
  let l = newLight(kind, pos, bearingFrom(pos, target), b.scanID);
  l.height = r2(rng.range(1.2, Math.min(2.4, b.spec.ceiling - 0.3)));
  const size = rng.pick(sizesFor(kind));
  l = applyGripSize(l, size);
  const drape = rng.pick(drapesFor(kind));
  l = applyDrape(l, drape);
  if (size.floppy && rng.chance(0.5)) l = setFloppyOpen(l, true);
  if (l.kind === 'diffusion' && rng.chance(0.35)) l.filterIDs = [rng.pick(FRAME_GELS).id];
  if (opts.overhead) {
    // Flown flat over the action.
    l.position = target; l.tilt = -90; l.height = r2(Math.min(b.spec.ceiling - 0.2, Math.max(2.4, l.height + 0.6)));
    l.support = 'overhead';
  } else if (rng.chance(0.25)) l.tilt = rng.int(-45, 30);
  return l;
}

function rig(rng: Rng, at: PlanPoint, toward: PlanPoint, height = rng.r2(0.6, 1.9)): CameraRig {
  return {
    position: at, height, pan: r2(bearingFrom(at, toward)), tilt: rng.int(-12, 6), focalLength: rng.pick([14, 18, 24, 32, 40, 50, 65, 85, 135]),
    sensorID: rng.pick(sensorPresets).id, aspect: rng.pick(['sensor', 'r239', 'r200', 'r185', 'r178', 'r143'] as const),
  };
}

function cameras(rng: Rng, b: Built, subject: PlanPoint, subjectHeight: number, n = 1) {
  const loc = b.loc;
  for (let i = 0; i < n; i++) {
    const at = inside(rng, b, 0.5);
    const r = rig(rng, at, subject);
    if (i === 0 || rng.chance(0.5)) {
      const s: Shot = { id: crypto.randomUUID().toUpperCase(), number: loc.shots.length + 1, title: `Shot ${loc.shots.length + 1}`, rig: r, subject, subjectHeight, scanID: b.scanID, notes: '', createdAt: '2026-11-12T00:00:00Z' };
      loc.shots.push(s);
    } else {
      const c = newCamera(at, `Camera ${i + 1}`, r.pan, b.scanID);
      c.rig = r;
      loc.cameraPositions.push(c);
    }
  }
}

function exposure(rng: Rng): ExposureSettings {
  const e: ExposureSettings = {
    iso: rng.pick(isoSteps), frameRate: rng.pick(frameRates), shutterAngle: rng.pick(shutterAngles),
    tStop: r2(rng.pick(thirdStops)), lensTransmission: rng.r2(0.8, 0.95), ndStops: rng.pick([0, 0, 0, 1, 2, 3, 6]),
  };
  if (rng.chance(0.1)) e.shutterSeconds = rng.pick([1 / 50, 1 / 100, 1 / 1000]);
  return e;
}

function meters(rng: Rng, b: Built, n: number): LightMeter[] {
  return Array.from({ length: n }, (_, i) => {
    const m = newMeter(inside(rng, b, 0.4), `Meter ${i + 1}`, b.scanID);
    m.height = rng.r2(0.4, 2);
    m.facing = rng.pick(['camera', 'bearing', 'up'] as const);
    m.bearing = rng.int(0, 359);
    if (rng.chance(0.3)) m.targetLux = rng.int(50, 3000);
    return m;
  });
}

function studio(rng: Rng, b: Built, walls = rng.int(1, 3)): StudioSetup {
  const backdrop = rng.pick(BACKDROPS);
  const first = rng.int(0, b.plan.walls.length - 1);
  const s: StudioSetup = { backdrop: backdrop.id, wallID: b.plan.walls[first].id };
  const more = [];
  for (let i = 1; i < walls; i++) more.push({ wallID: b.plan.walls[(first + i) % b.plan.walls.length].id, ...(rng.chance(0.3) ? { width: rng.r2(1.5, 4) } : {}) });
  if (more.length) s.moreWalls = more;
  if (rng.chance(0.3)) s.offset = rng.r2(-0.8, 0.8);
  if (rng.chance(0.3)) s.width = rng.r2(2, 6);
  if (backdrop.kind === 'led') { s.nits = rng.int(30, 1500); s.kelvin = rng.int(3200, 6500); }
  if (backdrop.pickColour) s.colour = rng.pick(['#c84a3a', '#3a6ec8', '#e0c050']);
  if (rng.chance(0.5)) s.floor = rng.pick(FLOORS).id;
  return s;
}

function finish(b: Built, rng: Rng, lights: LightFixture[], cast: PrevisCharacter[], ms: LightMeter[], e: ExposureSettings) {
  b.loc.lights = lights; b.loc.characters = cast; b.loc.meters = ms; b.loc.exposure = e; b.loc.display = {};
  if (rng.chance(0.15)) b.loc.display.windowTransmission = rng.r2(0.3, 1);
}

function bundleOf(id: string, title: string, b: Built): ProjectBundle {
  b.loc.name = `${id} · ${title}`;
  const project = { ...newProject(b.loc.name), locations: [b.loc] };
  return { project, plans: { [b.scanID]: b.plan } };
}

const mainSubject = (b: Built, cast: PrevisCharacter[]) => cast[0]?.position ?? inside(new Rng(1), b);
const faceY = (cast: PrevisCharacter[]) => (cast[0] ? eyeHeight(cast[0]) : 1.5);

// MARK: Families

function emptyCase(rng: Rng, i: number): [string, Built] {
  const b = room(rng, { windows: i % 4, door: i % 3 !== 0, shape: i % 5 === 4 ? 'l' : 'box' });
  if (i % 2) b.loc.daylight = { isOn: true, sky: rng.pick(['clear', 'hazy', 'overcast'] as const), sunBearing: rng.int(0, 359), sunElevation: rng.int(-5, 70) };
  if (i >= 7) b.loc.studio = studio(rng, b, 1 + (i % 3));
  finish(b, rng, [], [], i % 3 ? meters(rng, b, 1) : [], exposure(rng));
  return [`Empty room ${b.spec.shape === 'l' ? 'L ' : ''}${b.spec.length}×${b.spec.width}${b.loc.daylight ? ', daylight' : ''}${b.loc.studio ? ', backdrop' : ''}`, b];
}

function classicCase(rng: Rng, i: number): [string, Built] {
  const b = room(rng);
  furnish(rng, b, rng.int(0, 3));
  const cast = people(rng, b, rng.int(1, 2), 0.5);
  const setup = LIGHTING_SETUPS[i % LIGHTING_SETUPS.length];
  const e = exposure(rng);
  const camAt = inside(rng, b, 0.5);
  const built = buildSetup(setup.id, cast[0], camAt, e, b.plan);
  b.loc.shots.push({ id: crypto.randomUUID().toUpperCase(), number: 1, title: setup.label, rig: rig(rng, camAt, cast[0].position, r2(eyeHeight(cast[0]))), subject: cast[0].position, subjectHeight: cast[0].height, scanID: b.scanID, notes: built.notes.join('\n'), createdAt: '2026-11-12T00:00:00Z' });
  finish(b, rng, built.lights, cast, meters(rng, b, 1), e);
  return [`${setup.label} on ${cast[0].type}${cast[0].posture === 'sitting' ? ' (sitting)' : ''}`, b];
}

function locationCase(rng: Rng): [string, Built] {
  const b = room(rng, { windows: rng.int(0, 3) });
  furnish(rng, b, rng.int(1, 5));
  const cast = people(rng, b, rng.int(0, 3), 0.6);
  const s = mainSubject(b, cast), y = faceY(cast);
  const lights = Array.from({ length: rng.int(1, 6) }, () => unit(rng, b, s, y));
  for (let i = rng.int(0, 2); i > 0; i--) lights.push(grip(rng, b, s));
  if (rng.chance(0.4)) b.loc.daylight = { isOn: true, sky: rng.pick(['clear', 'hazy', 'overcast'] as const), sunBearing: rng.int(0, 359), sunElevation: rng.int(-8, 60) };
  cameras(rng, b, s, y, rng.int(1, 2));
  finish(b, rng, lights, cast, meters(rng, b, rng.int(0, 2)), exposure(rng));
  return [`Location: ${lights.length} units, ${cast.length} people, ${b.plan.objects.length} pieces`, b];
}

function studioCase(rng: Rng, i: number): [string, Built] {
  const b = room(rng, { length: rng.r2(8, 20), width: rng.r2(6, 14), ceiling: rng.r2(4, 8), windows: 0, door: true, shape: 'box' });
  b.loc.studio = studio(rng, b, 1 + (i % 3));
  const cast = people(rng, b, rng.int(1, 3), 0.2);
  if (i % 4 === 0) { furnish(rng, b, 1); }
  const s = mainSubject(b, cast), y = faceY(cast);
  const lights = Array.from({ length: rng.int(2, 6) }, () => unit(rng, b, s, y));
  if (i % 3 === 0) lights.push(grip(rng, b, s, 'diffusion', { overhead: true }));
  for (let k = rng.int(0, 2); k > 0; k--) lights.push(grip(rng, b, s));
  cameras(rng, b, s, y, rng.int(1, 2));
  finish(b, rng, lights, cast, meters(rng, b, rng.int(0, 2)), exposure(rng));
  const bd = BACKDROPS.find(x => x.id === b.loc.studio!.backdrop)!;
  return [`Studio: ${bd.label} on ${1 + (b.loc.studio!.moreWalls?.length ?? 0)} wall(s), ${lights.length} units`, b];
}

function daylightCase(rng: Rng, i: number): [string, Built] {
  const b = room(rng, { windows: 1 + (i % 4) });
  furnish(rng, b, rng.int(0, 3));
  const cast = people(rng, b, rng.int(0, 2), 0.5);
  const elevation = [-6, 2, 10, 25, 40, 60, 85][i % 7];
  b.loc.daylight = { isOn: true, sky: (['clear', 'hazy', 'overcast'] as const)[i % 3], sunBearing: rng.int(0, 359), sunElevation: elevation };
  if (i % 5 === 4) {
    // From the clock: the sun placed from the time and the location's coordinates.
    b.loc.coordinate = { latitude: rng.r2(-40, 60), longitude: rng.r2(-120, 140) };
    b.loc.daylight = { isOn: true, sky: 'clear', fromClock: true, time: 1782000000 + rng.int(0, 86400) };
  }
  for (const w of b.plan.windows) { const c = rng.pick([undefined, undefined, 'sheer', 'blackout'] as const); if (c) w.curtain = c; }
  const s = mainSubject(b, cast), y = faceY(cast);
  const lights = Array.from({ length: rng.int(0, 3) }, () => unit(rng, b, s, y));
  if (rng.chance(0.4)) lights.push(grip(rng, b, s));
  cameras(rng, b, s, y, 1);
  finish(b, rng, lights, cast, meters(rng, b, rng.int(1, 2)), exposure(rng));
  const curtains = b.plan.windows.map(w => w.curtain ?? 'bare').join('/');
  return [`Daylight: ${b.loc.daylight.fromClock ? 'from the clock' : `sun ${elevation}°`}, ${b.loc.daylight.sky}, windows ${curtains}`, b];
}

function gripCase(rng: Rng, i: number): [string, Built] {
  const b = room(rng, { ceiling: rng.r2(2.8, 5) });
  const cast = people(rng, b, rng.int(1, 2), 0.3);
  const s = mainSubject(b, cast), y = faceY(cast);
  const key = unit(rng, b, s, y, profileByID(rng.pick(['cob-600-d', 'hmi-1800-par', 'tungsten-2k', 'fresnel-led-600-d', 'cob-1200-d']))!);
  key.isOn = true;
  const lights = [key];
  // Grip right in the key's path, half-way to the person, plus some round the person.
  const mid = P((key.position.x + s.x) / 2, (key.position.z + s.z) / 2);
  const kind = GRIP[i % 4];
  const g = grip(rng, b, s, kind, { at: mid, overhead: i % 6 === 5 });
  g.pan = r2(bearingFrom(mid, key.position));
  g.height = r2(Math.max(g.height, (key.height + y) / 2));
  lights.push(g);
  for (let k = rng.int(0, 3); k > 0; k--) lights.push(grip(rng, b, s));
  if (rng.chance(0.5)) lights.push(unit(rng, b, s, y));
  cameras(rng, b, s, y, 1);
  finish(b, rng, lights, cast, meters(rng, b, rng.int(1, 2)), exposure(rng));
  return [`Grip: ${g.name} between ${key.name} and the person, ${lights.length - 2} more`, b];
}

/** Awkward cases: things right on top of each other, at the limits of the controls, or outside. */
function edgeCase(rng: Rng, i: number): [string, Built] {
  const cases: [string, Partial<RoomSpec>][] = [
    ['A light 10 cm from a meter', {}], ['Light outside the room, through a window', { windows: 2 }], ['Light inside a wall', {}],
    ['Units on the floor pointing straight up', {}], ['Units pointing straight down', { ceiling: 4 }], ['Every dimmer at 0', {}],
    ['Tiny room', { length: 1.5, width: 1.5, ceiling: 1.8, windows: 1 }], ['Hall 40×30 m, 12 m ceiling', { length: 40, width: 30, ceiling: 12, windows: 4 }],
    ['ISO 12800, T1, ND 9 at 360°', {}], ['Meter facing away from every light', {}], ['All units off', {}],
    ['A person standing in a wardrobe', {}], ['Grip flown flat under a light', { ceiling: 5 }], ['RGB at full saturation, every hue', {}],
    ['Twelve units on one person', {}],
  ];
  const [title, spec] = cases[i % cases.length];
  const b = room(rng, { shape: 'box', ...spec });
  const cast = people(rng, b, 1, 0);
  const s = cast[0].position, y = faceY(cast);
  let lights: LightFixture[] = [unit(rng, b, s, y), unit(rng, b, s, y)];
  let ms = meters(rng, b, 1);
  const e = exposure(rng);
  switch (i % cases.length) {
    case 0: ms[0].position = P(lights[0].position.x + 0.1, lights[0].position.z); ms[0].height = lights[0].height; ms[0].facing = 'bearing'; ms[0].bearing = r2((lights[0].pan + 180) % 360); break;
    case 1: { const w = b.plan.windows[0]; const o = P((w.a.x + w.b.x) / 2, w.a.z - 2); lights = [unit(rng, b, s, y, profileByID('hmi-4000-par')!, o)]; lights[0].isOn = true; lights[0].height = 2; break; }
    case 2: { const w = b.plan.walls[1]; lights[0].position = P((w.a.x + w.b.x) / 2, (w.a.z + w.b.z) / 2); break; }
    case 3: for (const l of lights) { l.height = 0.1; l.tilt = 90; } break;
    case 4: for (const l of lights) { l.position = s; l.height = 3.6; l.tilt = -90; } break;
    case 5: for (const l of lights) { l.dimmer = 0; l.isOn = true; } break;
    case 8: Object.assign(e, { iso: 12800, tStop: 1, ndStops: 9, shutterAngle: 360, frameRate: 24 }); delete e.shutterSeconds; break;
    case 9: ms[0].facing = 'bearing'; ms[0].position = P(s.x, s.z); ms[0].bearing = r2((bearingFrom(s, lights[0].position) + 180) % 360); lights[1].position = lights[0].position; lights[1].pan = lights[0].pan; break;
    case 10: for (const l of lights) l.isOn = false; break;
    case 11: { b.plan.objects.push(placeFurniture(b.plan, s, FURNITURE_PRESETS.find(f => f.id === 'wardrobe')!)); cast.splice(0, 1, ...settlePeople([{ ...cast[0], position: s }], b.plan, b.scanID, [], true)); break; }
    case 12: { const g = grip(rng, b, s, 'diffusion', { overhead: true }); lights[0].position = s; lights[0].height = 4.6; lights[0].tilt = -90; lights.push(g); break; }
    case 13: lights = Array.from({ length: 6 }, (_, k) => { const l = unit(rng, b, s, y, profileByID('panel-2x1-rgb')!); l.colorMode = 'rgb'; l.hue = k * 60; l.saturation = 1; l.isOn = true; l.dimmer = 1; return l; }); break;
    case 14: lights = Array.from({ length: 12 }, () => unit(rng, b, s, y)); break;
  }
  cameras(rng, b, s, y, 1);
  finish(b, rng, lights, cast, ms, e);
  return [title, b];
}

// MARK: The sweep

export const SWEEP_PLAN: [Family, number][] = [['empty', 10], ['classic', 25], ['location', 30], ['studio', 25], ['daylight', 25], ['grip', 20], ['edge', 15]];

const UUID_RE = /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/g;
const TIME_RE = /"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)"/g;

/** Makes the ids and dates fixed, so the same seed always writes the same file. */
function frozen(b: ProjectBundle, n: number): ProjectBundle {
  const ids = new Map<string, string>();
  const text = JSON.stringify(b)
    .replace(UUID_RE, u => {
      const k = u.toUpperCase();
      if (!ids.has(k)) ids.set(k, `5EED${String(n).padStart(4, '0')}-0000-4000-8000-${String(ids.size).padStart(12, '0')}`);
      return ids.get(k)!;
    })
    .replace(TIME_RE, '"2026-11-12T00:00:00Z"');
  return JSON.parse(text);
}

export function sweepCases(seed = 150): SweepCase[] {
  const out: SweepCase[] = [];
  let n = 0;
  for (const [family, count] of SWEEP_PLAN) {
    for (let i = 0; i < count; i++) {
      const rng = new Rng(seed * 1000 + n);
      const [title, b] = family === 'empty' ? emptyCase(rng, i) : family === 'classic' ? classicCase(rng, i)
        : family === 'location' ? locationCase(rng) : family === 'studio' ? studioCase(rng, i)
        : family === 'daylight' ? daylightCase(rng, i) : family === 'grip' ? gripCase(rng, i) : edgeCase(rng, i);
      const id = `S${String(n + 1).padStart(3, '0')}`;
      out.push({ id, family, title, bundle: frozen(bundleOf(id, title, b), n + 1) });
      n++;
    }
  }
  return out;
}

export { DRAPES, GRIP_SIZES };
