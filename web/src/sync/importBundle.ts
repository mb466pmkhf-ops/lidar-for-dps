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

function location(v: unknown): Location | undefined {
  if (!isObj(v)) return undefined;
  return {
    ...v,
    id: typeof v.id === 'string' && v.id ? v.id : uuid(),
    name: str(v.name, 'Location'), address: str(v.address, ''), notes: str(v.notes, ''),
    createdAt: str(v.createdAt, isoNow()),
    scans: list(v.scans), cameraPositions: list(v.cameraPositions), shots: list(v.shots),
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
    // A plan needs its walls and bounds to be drawn at all; the lists it lacks start empty.
    if (!isObj(v) || !Array.isArray(v.walls) || !isObj(v.bounds)) continue;
    plans[k.toUpperCase()] = {
      ...v, doors: list(v.doors), windows: list(v.windows), openings: list(v.openings), objects: list(v.objects),
      floorPolygons: Array.isArray(v.floorPolygons) ? v.floorPolygons : [], occupancy: Array.isArray(v.occupancy) ? v.occupancy : [],
    } as unknown as FloorPlan;
  }
  return { project, plans };
}
