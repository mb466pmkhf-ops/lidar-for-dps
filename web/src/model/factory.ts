// Constructors matching the Swift initialisers, so new items decode on the phone.
import type { CharacterType, LightFixture, LightKind, LightMeter, PlanPoint, PrevisCharacter, Project, Location, UUID } from './types';
import { KIND_INFO } from './photometrics';
import { characterDefaults } from './characters';

/// Uppercase like Foundation's UUID().uuidString, so ids compare equal across platforms.
export function uuid(): UUID {
  const c = globalThis.crypto;
  if (c && 'randomUUID' in c) return c.randomUUID().toUpperCase();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, ch => {
    const r = (Math.random() * 16) | 0;
    return (ch === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  }).toUpperCase();
}

/// ISO 8601 without fractional seconds — what JSONEncoder's .iso8601 strategy writes and reads.
export const isoNow = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

export function newLight(kind: LightKind, position: PlanPoint, pan = 0, scanID?: UUID): LightFixture {
  const k = KIND_INFO[kind];
  const l: LightFixture = {
    id: uuid(), name: k.label, kind, position, height: k.height, pan, tilt: k.emits ? -20 : 0,
    beamAngle: k.beam, width: k.width, power: '', colorTemperature: 5600, gel: '', modifier: '',
    dimmer: 1, isOn: true, notes: '',
  };
  if (scanID) l.scanID = scanID;
  return l;
}

export function newCharacter(type: CharacterType, position: PlanPoint, name: string, scanID?: UUID): PrevisCharacter {
  const c: PrevisCharacter = { id: uuid(), name, type, height: characterDefaults[type], build: 0.5, skinTone: 3, position, facing: 180, posture: 'standing' };
  if (scanID) c.scanID = scanID;
  return c;
}

export function newMeter(position: PlanPoint, name: string, scanID?: UUID): LightMeter {
  const m: LightMeter = { id: uuid(), name, position, height: 1.5, facing: 'camera', bearing: 0 };
  if (scanID) m.scanID = scanID;
  return m;
}

export function newProject(name: string): Project {
  const now = isoNow();
  return { id: uuid(), name, client: '', notes: '', createdAt: now, modifiedAt: now, locations: [], objects: [] };
}

export function newLocation(name: string): Location {
  return { id: uuid(), name, address: '', createdAt: isoNow(), tags: [], notes: '', lightingNotes: '', productionNotes: '', quickNotes: [], scans: [], photos: [], measurements: [], cameraPositions: [], shots: [] };
}
