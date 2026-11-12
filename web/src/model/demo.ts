// The iOS app's demo location (FrameScout/App/DemoContent.swift), so the planner has something to
// show before the first sync. Ids differ from the phone's demo so the two never collide.
import type { FloorPlan, LightFixture, PlanPoint, ProjectBundle, CameraRig } from './types';
import { applyProfile, profileByID } from './photometrics';
import { bearingFrom } from './calculator';
import { newCharacter, newLight, newLocation, newMeter, newProject, uuid, isoNow } from './factory';

const P = (x: number, z: number): PlanPoint => ({ x, z });

export function demoBundle(): ProjectBundle {
  const scanID = uuid();
  const corners = [P(-3.1, -2.4), P(3.1, -2.4), P(3.1, 2.4), P(-3.1, 2.4)];
  const seg = (kind: 'wall' | 'door' | 'window', a: PlanPoint, b: PlanPoint, height: number, bottom: number) =>
    ({ id: uuid(), kind, a, b, height, bottom, isOpen: false });
  const plan: FloorPlan = {
    walls: corners.map((c, i) => seg('wall', c, corners[(i + 1) % 4], 2.74, 0)),
    doors: [seg('door', P(-3.1, 1.6), P(-3.1, 0.7), 2.05, 0)],
    windows: [seg('window', P(-1.9, -2.4), P(-0.5, -2.4), 1.5, 0.8), seg('window', P(0.7, -2.4), P(2.1, -2.4), 1.5, 0.8)],
    openings: [], floorPolygons: [corners], occupancy: [], occupancyCellSize: 0.1, floorY: 0,
    objects: [
      { id: uuid(), category: 'Sofa', center: P(0.4, 1.8), width: 2.2, depth: 0.9, height: 0.8, rotation: 0 },
      { id: uuid(), category: 'Table', center: P(0.4, 0.4), width: 1.2, depth: 0.6, height: 0.45, rotation: 0 },
      { id: uuid(), category: 'Storage', center: P(2.8, 0.2), width: 0.4, depth: 1.6, height: 1.9, rotation: 0 },
    ],
    bounds: { minX: -3.1, minZ: -2.4, maxX: 3.1, maxZ: 2.4 },
  };

  const rig = (position: PlanPoint, pan: number, focalLength: number, height = 1.5): CameraRig =>
    ({ position, height, pan, tilt: 0, focalLength, sensorID: 'arri-minilf-og', aspect: 'sensor' });
  const wide = rig(P(-2.2, -1.6), 135, 24);
  const single = rig(P(1.6, -1.2), 200, 50, 1.35);

  const sofa = P(0.4, 1.8);
  const aimed = (name: string, kind: LightFixture['kind'], at: PlanPoint, to: PlanPoint, profile?: string) => {
    let l = newLight(kind, at, bearingFrom(at, to), scanID);
    if (profile) l = applyProfile(l, profileByID(profile)!);
    l.name = name;
    return l;
  };
  const key = { ...aimed('Key', 'softbox', P(-1.2, 0.2), sofa, 'cob-600-d'), modifierID: 'softbox-90-grid', role: 'key' as const, height: 2.1, tilt: -25, dimmer: 0.25 };
  const fill = { ...aimed('Fill', 'ledPanel', P(2.2, -0.6), sofa, 'panel-1x1-bi'), role: 'fill' as const, colorTemperature: 4300, dimmer: 0.3, height: 1.8, tilt: -15 };
  const back = { ...aimed('Back', 'fresnel', P(-0.9, 2.25), P(0, 1.8), 'fresnel-led-200-bi'), role: 'back' as const, height: 2.4, tilt: -50, beamAngle: 30, dimmer: 0.4, barnDoors: { top: 12, bottom: 90, left: 90, right: 10 } };
  const bounce = { ...aimed('Bounce', 'bounce', P(1.7, 1.0), sofa), width: 1.2 };
  const neg = { ...aimed('Neg', 'negative', P(-1.4, 2.0), sofa), width: 1.2 };
  const lamp = { ...aimed('Lamp', 'practical', P(2.6, 1.9), sofa, 'bulb-tungsten-100'), role: 'practical' as const, height: 1.4 };

  const maya = { ...newCharacter('woman', P(0, 1.8), 'Maya', scanID), facing: 330, posture: 'sitting' as const, skinTone: 4 };
  const leo = { ...newCharacter('boy', P(0.9, 1.8), 'Leo', scanID), facing: 340, posture: 'sitting' as const, skinTone: 2, build: 0.4 };
  const meter = { ...newMeter(P(0.4, 0.4), 'Table', scanID), height: 0.5, facing: 'up' as const };

  const location = {
    ...newLocation('Hackney Flat — Living Room'),
    address: 'Hackney, London',
    scans: [{ id: scanID, name: 'Living room', kind: 'room' as const, createdAt: isoNow(), segmentCount: 1, deviceModel: '', notes: '',
      stats: { width: 4.8, length: 6.2, ceilingHeight: 2.74, floorAreaIsEstimate: false, wallCount: 4, doorCount: 1, windowCount: 2, openingCount: 0, floorCount: 1, objectCount: 3, objectCategories: {}, doors: [], windows: [], meshVertexCount: 0, meshFaceCount: 0 },
      northOffset: 172 }],
    primaryScanID: scanID,
    cameraPositions: [{ id: uuid(), name: 'A · Window corner', rig: wide, scanID, notes: '', createdAt: isoNow() }],
    shots: [
      { id: uuid(), number: 1, title: 'Wide, family on sofa', rig: wide, subject: sofa, subjectHeight: 1.75, scanID, notes: '', createdAt: isoNow() },
      { id: uuid(), number: 2, title: 'Single on Maya', rig: single, subject: P(0, 1.8), subjectHeight: 1.75, scanID, notes: '', createdAt: isoNow() },
    ],
    lights: [key, fill, back, bounce, neg, lamp],
    characters: [maya, leo],
    meters: [meter],
    exposure: { iso: 800, frameRate: 24, shutterAngle: 180, tStop: 5.6, lensTransmission: 0.85, ndStops: 0 },
    display: {},
  };
  const project = { ...newProject('Family on the sofa (sample)'), client: 'Sample job', locations: [location] };
  return { project, plans: { [scanID]: plan } };
}
