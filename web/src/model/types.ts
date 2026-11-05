// JSON shapes of the iOS app's Codable model (FrameScout/Core/Models). The web app reads and writes
// project.json as plain JSON and only touches the fields it edits, so keys added by newer iOS builds
// survive a round trip. Non-optional Swift fields must always be written (synthesized Codable
// requires them); optional ones are omitted when unset, as Swift does.

export type UUID = string;
export type Provenance = 'measured' | 'estimated' | 'manual';

export interface PlanPoint { x: number; z: number }
export interface PlanRect { minX: number; minZ: number; maxX: number; maxZ: number }

export type PlanSegmentKind = 'wall' | 'door' | 'window' | 'opening';
export interface PlanSegment {
  id: UUID; kind: PlanSegmentKind; a: PlanPoint; b: PlanPoint;
  height: number; bottom: number; isOpen: boolean;
}
export interface PlanObject {
  id: UUID; category: string; center: PlanPoint;
  width: number; depth: number; height: number; rotation: number;
}
export interface FloorPlan {
  walls: PlanSegment[]; doors: PlanSegment[]; windows: PlanSegment[]; openings: PlanSegment[];
  floorPolygons: PlanPoint[][]; objects: PlanObject[]; occupancy: PlanPoint[];
  occupancyCellSize: number; floorY: number; bounds: PlanRect;
}

export type LightKind = 'fresnel' | 'hmi' | 'ledPanel' | 'tube' | 'softbox' | 'spaceLight' | 'practical'
  | 'bounce' | 'negative' | 'flag' | 'diffusion';
export type LightRole = 'key' | 'fill' | 'back' | 'edge' | 'background' | 'ambient' | 'practical' | 'effect';

export interface PhotometricReference {
  lux: number; distance: number; beamAngle?: number; provenance: Provenance; note: string;
}
export interface BarnDoors { top: number; bottom: number; left: number; right: number }

export interface LightFixture {
  id: UUID; name: string; kind: LightKind; role?: LightRole; position: PlanPoint;
  height: number; pan: number; tilt: number; beamAngle: number; width: number;
  power: string; colorTemperature: number; gel: string; modifier: string;
  dimmer: number; isOn: boolean; scanID?: UUID; notes: string;
  profileID?: string; modifierID?: string; filterIDs?: string[]; barnDoors?: BarnDoors;
  colorMode?: 'cct' | 'rgb'; hue?: number; saturation?: number;
  photometricOverride?: PhotometricReference; boardHeight?: number;
  [key: string]: unknown;
}

export type CharacterType = 'man' | 'woman' | 'girl' | 'boy';
export interface PrevisCharacter {
  id: UUID; name: string; type: CharacterType; height: number; build: number; skinTone: number;
  position: PlanPoint; facing: number; posture: 'standing' | 'sitting'; scanID?: UUID;
  [key: string]: unknown;
}

export type MeterFacing = 'camera' | 'bearing' | 'up';
export interface LightMeter {
  id: UUID; name: string; position: PlanPoint; height: number; facing: MeterFacing;
  bearing: number; targetLux?: number; scanID?: UUID;
  [key: string]: unknown;
}

export interface ExposureSettings {
  iso: number; frameRate: number; shutterAngle: number; shutterSeconds?: number;
  tStop: number; lensTransmission: number; ndStops: number;
}

export interface SensorFormat { id: string; manufacturer: string; name: string; width: number; height: number }
export type FrameAspect = 'sensor' | 'r239' | 'r200' | 'r185' | 'r178' | 'r143';
export interface CameraRig {
  position: PlanPoint; height: number; pan: number; tilt: number; focalLength: number;
  sensorID: string; customSensor?: SensorFormat; aspect: FrameAspect;
  [key: string]: unknown;
}
export interface CameraPosition {
  id: UUID; name: string; rig: CameraRig; scanID?: UUID; notes: string; createdAt: string;
  [key: string]: unknown;
}
export interface Shot {
  id: UUID; number: number; title: string; rig: CameraRig; subject?: PlanPoint; subjectHeight: number;
  cameraPositionID?: UUID; scanID?: UUID; notes: string; photoID?: UUID; createdAt: string;
  [key: string]: unknown;
}

export interface SceneDisplay {
  hiddenItems?: string[]; hiddenGroups?: string[]; hiddenLabels?: string[];
  windowOpacity?: number; windowTransmission?: number; wallOpacity?: number; showLuxMap?: boolean;
  [key: string]: unknown;
}

export interface ScanRecord {
  id: UUID; name: string; kind: 'room' | 'mesh'; createdAt: string;
  stats: { width?: number; length?: number; ceilingHeight?: number; [key: string]: unknown };
  northOffset?: number;
  [key: string]: unknown;
}

export interface Location {
  id: UUID; name: string; address: string; createdAt: string; notes: string;
  scans: ScanRecord[]; primaryScanID?: UUID;
  cameraPositions: CameraPosition[]; shots: Shot[];
  lights?: LightFixture[]; characters?: PrevisCharacter[]; meters?: LightMeter[];
  exposure?: ExposureSettings; display?: SceneDisplay;
  [key: string]: unknown;
}

export interface Project {
  id: UUID; name: string; client: string; notes: string; createdAt: string; modifiedAt: string;
  locations: Location[];
  [key: string]: unknown;
}

/// What syncs: the project document plus the small 2D plan of each scan (walls, openings, set
/// pieces). Meshes, textures and photos stay on the phone.
export interface ProjectBundle {
  project: Project;
  plans: Record<UUID, FloorPlan>;
}
