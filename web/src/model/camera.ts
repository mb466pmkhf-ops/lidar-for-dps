// Ports of SensorLibrary / Optics / FrameAspect (Camera.swift, Optics.swift) needed by the planner.
import type { CameraRig, FrameAspect, SensorFormat } from './types';

export const sensorPresets: SensorFormat[] = [
  { id: 'arri-35-og', manufacturer: 'ARRI', name: 'Alexa 35 · 4.6K 3:2 Open Gate', width: 27.99, height: 19.22 },
  { id: 'arri-35-46-169', manufacturer: 'ARRI', name: 'Alexa 35 · 4.6K 16:9', width: 27.99, height: 15.75 },
  { id: 'arri-35-169', manufacturer: 'ARRI', name: 'Alexa 35 · 4K 16:9', width: 24.88, height: 14.00 },
  { id: 'arri-35-65', manufacturer: 'ARRI', name: 'Alexa 35 · 3.3K 6:5 anamorphic', width: 20.22, height: 16.95 },
  { id: 'arri-minilf-og', manufacturer: 'ARRI', name: 'Alexa Mini LF · 4.5K LF 3:2 Open Gate', width: 36.70, height: 25.54 },
  { id: 'arri-minilf-169', manufacturer: 'ARRI', name: 'Alexa Mini LF · 3.8K LF 16:9 UHD', width: 31.68, height: 17.82 },
  { id: 'arri-minilf-239', manufacturer: 'ARRI', name: 'Alexa Mini LF · 4.5K LF 2.39:1', width: 36.70, height: 15.31 },
  { id: 'arri-65-og', manufacturer: 'ARRI', name: 'Alexa 65 · 6.5K Open Gate', width: 54.12, height: 25.58 },
  { id: 'arri-mini-og', manufacturer: 'ARRI', name: 'Alexa Mini · 3.4K Open Gate', width: 28.25, height: 18.17 },
  { id: 'arri-mini-32k', manufacturer: 'ARRI', name: 'Alexa Mini · 3.2K 16:9', width: 26.40, height: 14.85 },
  { id: 'arri-mini-43', manufacturer: 'ARRI', name: 'Alexa Mini · 2.8K 4:3 anamorphic', width: 23.76, height: 17.82 },
  { id: 'bmd-ursacine-12k', manufacturer: 'Blackmagic', name: 'URSA Cine 12K LF · 3:2', width: 35.64, height: 23.32 },
  { id: 'bmd-ursa-12k', manufacturer: 'Blackmagic', name: 'URSA Mini Pro 12K · 17:9', width: 27.03, height: 14.25 },
  { id: 'bmd-pocket-6k', manufacturer: 'Blackmagic', name: 'Pocket 6K · S35 6K 16:9', width: 23.10, height: 12.99 },
  { id: 'bmd-pocket-4k', manufacturer: 'Blackmagic', name: 'Pocket 4K · 4/3 4K DCI', width: 18.96, height: 10.00 },
  { id: 'canon-c500-2', manufacturer: 'Canon', name: 'C500 Mark II · 5.9K FF 17:9', width: 38.10, height: 20.10 },
  { id: 'canon-c300-3', manufacturer: 'Canon', name: 'C300 Mark III / C70 · S35 4K', width: 26.20, height: 13.80 },
  { id: 'red-vraptor-8k-vv', manufacturer: 'RED', name: 'V-Raptor · 8K VV 17:9', width: 40.96, height: 21.60 },
  { id: 'red-vraptor-6k-s35', manufacturer: 'RED', name: 'V-Raptor · 6K S35 17:9', width: 30.72, height: 16.20 },
  { id: 'red-vraptor-8k-s35', manufacturer: 'RED', name: 'V-Raptor 8K S35 · 17:9', width: 26.21, height: 13.82 },
  { id: 'red-komodo-6k', manufacturer: 'RED', name: 'Komodo · 6K S35 17:9', width: 27.03, height: 14.26 },
  { id: 'sony-venice2-86k', manufacturer: 'Sony', name: 'Venice 2 · 8.6K 3:2 FF', width: 35.90, height: 24.00 },
  { id: 'sony-venice2-86k-179', manufacturer: 'Sony', name: 'Venice 2 · 8.6K 17:9 FF', width: 35.90, height: 19.00 },
  { id: 'sony-venice2-82k-239', manufacturer: 'Sony', name: 'Venice 2 · 8.2K 2.39:1 FF', width: 34.10, height: 14.30 },
  { id: 'sony-venice2-58k-65', manufacturer: 'Sony', name: 'Venice 2 · 5.8K 6:5 S35 anamorphic', width: 24.10, height: 20.20 },
  { id: 'sony-venice2-58k-43', manufacturer: 'Sony', name: 'Venice 2 · 5.8K 4:3 S35', width: 24.10, height: 17.80 },
  { id: 'sony-venice-6k-179', manufacturer: 'Sony', name: 'Venice · 6K 17:9 FF', width: 35.90, height: 18.90 },
  { id: 'sony-venice-4k-s35', manufacturer: 'Sony', name: 'Venice · 4K 17:9 S35', width: 24.30, height: 12.80 },
  { id: 'sony-fx6', manufacturer: 'Sony', name: 'FX6 / FX3 · FF 4K UHD 16:9', width: 35.60, height: 20.00 },
  { id: 'generic-ff', manufacturer: '', name: 'Full Frame 3:2', width: 36.00, height: 24.00 },
  { id: 'generic-s35-4perf', manufacturer: '', name: 'Super 35 · 4-perf', width: 24.89, height: 18.66 },
  { id: 'generic-s35-3perf', manufacturer: '', name: 'Super 35 · 3-perf', width: 24.89, height: 13.87 },
  { id: 'generic-s35-169', manufacturer: '', name: 'Super 35 · 16:9', width: 24.89, height: 14.00 },
  { id: 'generic-academy', manufacturer: '', name: '35 mm Academy', width: 21.95, height: 16.00 },
  { id: 'generic-65-5perf', manufacturer: '', name: '65 mm · 5-perf', width: 52.48, height: 23.01 },
  { id: 'generic-imax-1570', manufacturer: '', name: 'IMAX · 15-perf 65 mm', width: 70.41, height: 52.63 },
  { id: 'generic-m43', manufacturer: '', name: 'Micro Four Thirds', width: 17.30, height: 13.00 },
  { id: 'generic-s16', manufacturer: '', name: 'Super 16', width: 12.52, height: 7.41 },
  { id: 'generic-16', manufacturer: '', name: 'Standard 16', width: 10.26, height: 7.49 },
];

const aspectRatio: Record<FrameAspect, number | undefined> = { sensor: undefined, r239: 2.39, r200: 2.0, r185: 1.85, r178: 16 / 9, r143: 1.43 };

export function sensorFor(rig: CameraRig): SensorFormat {
  if (rig.sensorID === 'custom' && rig.customSensor) return rig.customSensor;
  return sensorPresets.find(s => s.id === rig.sensorID) ?? sensorPresets.find(s => s.id === 'arri-minilf-og')!;
}

export function imageArea(rig: CameraRig): { width: number; height: number } {
  const s = sensorFor(rig);
  const ratio = aspectRatio[rig.aspect];
  if (ratio === undefined) return { width: s.width, height: s.height };
  return ratio >= s.width / s.height ? { width: s.width, height: s.width / ratio } : { width: s.height * ratio, height: s.height };
}

export const fieldOfView = (size: number, focal: number) => (focal > 0 ? 2 * Math.atan(size / (2 * focal)) * 180 / Math.PI : 0);
export const horizontalFOV = (rig: CameraRig) => fieldOfView(imageArea(rig).width, rig.focalLength);
