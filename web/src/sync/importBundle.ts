// Checks a project file someone picked to import (a phone backup ZIP or a .framescan.json) before it
// goes into the workspace. A file that isn't a project is refused with plain words; a project from
// an older build that lacks a list or a name gets an empty one, so the planner never stores something
// it then can't draw (which would break the page on every start).
import type { FloorPlan, Location, Project, ProjectBundle } from '../model/types';
import { isoNow, uuid } from '../model/factory';

const NOT_A_PROJECT = 'That file is not a FrameScan project.';
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const str = (v: unknown, fallback: string) => (typeof v === 'string' ? v : fallback);
const list = <T>(v: unknown): T[] => (Array.isArray(v) ? v.filter(isObj) as T[] : []);
const num = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const point = (v: unknown) => isObj(v) && num(v.x) && num(v.z);
/// Segments (walls, doors, windows, openings) need both ends to be drawn; others are dropped.
const segments = (v: unknown) => list<Record<string, unknown>>(v).filter(s => point(s.a) && point(s.b));
type Item = Record<string, unknown>;
const hasID = (o: Item) => typeof o.id === 'string' && o.id.length > 0;
const placed = (o: Item) => hasID(o) && point(o.position);
const rigged = (o: Item) => hasID(o) && isObj(o.rig) && point(o.rig.position);
const light = (o: Item) => placed(o) && typeof o.kind === 'string';
/// What every item in a location's lists needs before the planner can draw it. Items without it
/// are dropped (the rest of the file still imports).
const ITEM_CHECKS: Record<string, (o: Item) => boolean> = {
  scans: hasID, cameraPositions: rigged, shots: rigged,
  lights: light, characters: placed, meters: placed,
  looks: o => hasID(o) && (o.lights === undefined || Array.isArray(o.lights)),
};
/// Lists a location may leave out: when present they must be lists of drawable items.
const OPTIONAL_LISTS = ['lights', 'characters', 'meters', 'looks'] as const;
const items = (key: string, v: unknown) => {
  const out = list<Item>(v).filter(ITEM_CHECKS[key]);
  return key === 'looks' ? out.map(l => (l.lights === undefined ? l : { ...l, lights: list<Item>(l.lights).filter(light) })) : out;
};

function location(v: unknown): Location | undefined {
  if (!isObj(v)) return undefined;
  return {
    ...v,
    id: typeof v.id === 'string' && v.id ? v.id : uuid(),
    name: str(v.name, 'Location'), address: str(v.address, ''), notes: str(v.notes, ''),
    createdAt: str(v.createdAt, isoNow()),
    scans: items('scans', v.scans), cameraPositions: items('cameraPositions', v.cameraPositions), shots: items('shots', v.shots),
    ...Object.fromEntries(OPTIONAL_LISTS.filter(k => k in v).map(k => [k, items(k, v[k])])),
  } as Location;
}

export function checkedBundle(input: unknown): ProjectBundle {
  const raw = isObj(input) && isObj(input.project) ? input : { project: input, plans: {} };
  const p = (raw as { project: unknown }).project;
  if (!isObj(p) || !Array.isArray(p.locations)) throw new Error(NOT_A_PROJECT);
  const now = isoNow();
  const project: Project = {
    ...p,
    id: typeof p.id === 'string' && p.id ? p.id : uuid(),
    name: str(p.name, 'Imported project'), client: str(p.client, ''), notes: str(p.notes, ''),
    createdAt: str(p.createdAt, now), modifiedAt: str(p.modifiedAt, now),
    locations: p.locations.map(location).filter((l): l is Location => !!l),
  };
  const plansIn = (raw as { plans?: unknown }).plans;
  const plans: Record<string, FloorPlan> = {};
  if (isObj(plansIn)) for (const [k, v] of Object.entries(plansIn)) {
    // A plan needs its walls and numeric bounds to be drawn at all. Entries that can't be drawn are
    // dropped and the lists it lacks start empty.
    if (!isObj(v) || !Array.isArray(v.walls) || !isObj(v.bounds)) continue;
    const b = v.bounds;
    if (!num(b.minX) || !num(b.minZ) || !num(b.maxX) || !num(b.maxZ)) continue;
    plans[k.toUpperCase()] = {
      ...v,
      walls: segments(v.walls), doors: segments(v.doors), windows: segments(v.windows), openings: segments(v.openings),
      objects: list<Item>(v.objects).filter(o => typeof o.category === 'string' && point(o.center)),
      floorPolygons: (Array.isArray(v.floorPolygons) ? v.floorPolygons : []).filter(Array.isArray).map(poly => (poly as unknown[]).filter(point)),
      occupancy: (Array.isArray(v.occupancy) ? v.occupancy : []).filter(point),
      floorY: num(v.floorY) ? v.floorY : 0,
      occupancyCellSize: num(v.occupancyCellSize) && v.occupancyCellSize > 0 ? v.occupancyCellSize : 0.1,
    } as unknown as FloorPlan;
  }
  return { project, plans };
}
