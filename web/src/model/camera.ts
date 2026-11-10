// Ports of SensorLibrary / Optics / FrameAspect (Camera.swift, Optics.swift) needed by the planner.
import type { CameraRig, FrameAspect, SensorFormat } from './types';

export const sensorPresets: SensorFormat[] = [
  { id: 'arri-minilf-og', manufacturer: 'ARRI', name: 'Alexa Mini LF · 4.5K LF Open Gate', width: 36.70, height: 25.54 },
  { id: 'arri-minilf-169', manufacturer: 'ARRI', name: 'Alexa Mini LF · 4.3K LF 16:9 UHD', width: 31.68, height: 17.82 },
  { id: 'arri-35-og', manufacturer: 'ARRI', name: 'Alexa 35 · 4.6K 3:2 Open Gate', width: 27.99, height: 19.22 },
  { id: 'arri-35-169', manufacturer: 'ARRI', name: 'Alexa 35 · 4K 16:9', width: 24.88, height: 14.00 },
  { id: 'arri-mini-og', manufacturer: 'ARRI', name: 'Alexa Mini · 3.4K Open Gate', width: 28.25, height: 18.17 },
  { id: 'sony-venice2-86k', manufacturer: 'Sony', name: 'Venice 2 · 8.6K 3:2 FF', width: 35.90, height: 24.00 },
  { id: 'sony-venice-6k-179', manufacturer: 'Sony', name: 'Venice · 6K 17:9 FF', width: 35.90, height: 18.90 },
  { id: 'sony-venice-4k-s35', manufacturer: 'Sony', name: 'Venice · 4K 17:9 S35', width: 24.30, height: 12.80 },
  { id: 'sony-fx6', manufacturer: 'Sony', name: 'FX6 / FX3 · FF 16:9', width: 35.60, height: 20.00 },
  { id: 'red-vraptor-8k-vv', manufacturer: 'RED', name: 'V-Raptor · 8K VV 17:9', width: 40.96, height: 21.60 },
  { id: 'red-vraptor-6k-s35', manufacturer: 'RED', name: 'V-Raptor · 6K S35 17:9', width: 30.72, height: 16.20 },
  { id: 'red-komodo-6k', manufacturer: 'RED', name: 'Komodo · 6K S35 17:9', width: 27.03, height: 14.26 },
  { id: 'generic-ff', manufacturer: '', name: 'Full Frame 3:2', width: 36.00, height: 24.00 },
  { id: 'generic-s35-4perf', manufacturer: '', name: 'Super 35 · 4-perf', width: 24.89, height: 18.66 },
  { id: 'generic-s35-169', manufacturer: '', name: 'Super 35 · 16:9', width: 24.89, height: 14.00 },
  { id: 'generic-s16', manufacturer: '', name: 'Super 16', width: 12.52, height: 7.41 },
  { id: 'generic-m43', manufacturer: '', name: 'Micro Four Thirds', width: 17.30, height: 13.00 },
];

const aspectRatio: Record<FrameAspect, number | undefined> = { sensor: undefined, r239: 2.39, r200: 2.0, r185: 1.85, r178: 16 / 9, r143: 1.43 };

export function sensorFor(rig: CameraRig): SensorFormat {
  if (rig.sensorID === 'custom' && rig.customSensor) return rig.customSensor;
  return sensorPresets.find(s => s.id === rig.sensorID) ?? sensorPresets[0];
}

export function imageArea(rig: CameraRig): { width: number; height: number } {
  const s = sensorFor(rig);
  const ratio = aspectRatio[rig.aspect];
  if (ratio === undefined) return { width: s.width, height: s.height };
  return ratio >= s.width / s.height ? { width: s.width, height: s.width / ratio } : { width: s.height * ratio, height: s.height };
}

export const fieldOfView = (size: number, focal: number) => (focal > 0 ? 2 * Math.atan(size / (2 * focal)) * 180 / Math.PI : 0);
export const horizontalFOV = (rig: CameraRig) => fieldOfView(imageArea(rig).width, rig.focalLength);
