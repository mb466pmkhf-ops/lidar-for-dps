// Constructors matching the Swift initialisers, so new items decode on the phone.
import type { CameraPosition, CharacterType, LightFixture, LightKind, LightMeter, PlanPoint, PrevisCharacter, Project, Location, UUID } from './types';
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

/// A camera position with every key the phone's CameraPosition / CameraRig decoders need.
export function newCamera(position: PlanPoint, name: string, pan = 0, scanID?: UUID): CameraPosition {
  const c: CameraPosition = {
    id: uuid(), name, notes: '', createdAt: isoNow(),
    rig: { position, height: 1.5, pan, tilt: 0, focalLength: 32, sensorID: 'arri-minilf-og', aspect: 'sensor' },
  };
  if (scanID) c.scanID = scanID;
  return c;
}

export function newProject(name: string): Project {
  const now = isoNow();
  return { id: uuid(), name, client: '', notes: '', createdAt: now, modifiedAt: now, locations: [], objects: [] };
}

export function newLocation(name: string): Location {
  return { id: uuid(), name, address: '', createdAt: isoNow(), tags: [], notes: '', lightingNotes: '', productionNotes: '', quickNotes: [], scans: [], photos: [], measurements: [], cameraPositions: [], shots: [] };
}

/// Short names crews use for grip (and the plan's add buttons and the built-in setups use).
const SHORT: Partial<Record<LightKind, string>> = { bounce: 'Bounce', negative: 'Neg', flag: 'Flag', diffusion: 'Diffusion' };

/// The name a unit should take when its kind changes: a name that is still the old kind's own
/// ("Negative fill", "Neg 2") follows the change ("Flag", "Flag 2"); a name the user gave it stays.
/// Same rule as LightKind.renamed(_:to:) on the iPhone.
export function renamedForKind(name: string, from: LightKind, to: LightKind): string {
  if (from === to) return name;
  const trimmed = name.trim();
  for (const [own, next] of [[KIND_INFO[from].label, KIND_INFO[to].label], [SHORT[from], SHORT[to] ?? KIND_INFO[to].label]] as const) {
    if (!own) continue;
    if (trimmed.toLowerCase() === own.toLowerCase()) return next;
    const m = trimmed.match(/^(.*) (\d+)$/);
    if (m && m[1].toLowerCase() === own.toLowerCase()) return `${next} ${m[2]}`;
  }
  return name;
}
