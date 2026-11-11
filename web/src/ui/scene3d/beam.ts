// A soft beam: a smooth cone in light haze. It fades towards its edges and its far end, so it
// reads as light in the air rather than a solid shape. Each direction round the rim stops at the
// first surface it meets (smoothed, so one stray hit doesn't make a shard).
import * as THREE from 'three';
import type { LightFixture } from '../../model/types';
import type { ResolvedPhotometrics } from '../../model/photometrics';
import { rad, v } from './kit';

const BEAM_SEGMENTS = 64, BEAM_RINGS = 12, BEAM_MAX = 7;
const beamVertex = `
  attribute float along;
  varying float vAlong;
  varying vec3 vNormal;
  varying vec3 vView;
  void main() {
    vAlong = along;
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    vView = normalize(-mv.xyz);
    vNormal = normalize(normalMatrix * normal);
    gl_Position = projectionMatrix * mv;
  }`;
const beamFragment = `
  uniform vec3 color;
  uniform float strength;
  varying float vAlong;
  varying vec3 vNormal;
  varying vec3 vView;
  void main() {
    // Faces seen edge-on (the cone's outline) fade out; faces seen head-on carry the glow.
    float facing = abs(dot(normalize(vNormal), normalize(vView)));
    float edge = pow(facing, 1.6);
    float fade = (1.0 - smoothstep(0.55, 1.0, vAlong)) * smoothstep(0.0, 0.08, vAlong);
    gl_FragColor = vec4(color * strength * edge * fade, 1.0);
  }`;


export function beam(l: LightFixture, pm: ResolvedPhotometrics, origin: THREE.Vector3, q: THREE.Quaternion, color: THREE.Color, hitTargets: THREE.Object3D[]): THREE.Mesh | undefined {
  if (pm.distribution !== 'beam' && pm.distribution !== 'lambertian') return undefined;
  const half = Math.min(pm.distribution === 'beam' ? pm.beamAngle * 0.6 : 50, 70);
  const th = Math.tan(rad(half));
  const doors = l.barnDoors;
  const lim = (d: number) => Math.tan(rad(Math.min(half, doors ? d : 90)));
  const L = lim(doors?.left ?? 90), R = lim(doors?.right ?? 90), U = lim(doors?.top ?? 90), D = lim(doors?.bottom ?? 90);

  // Rim directions (in the unit's frame, -Z forward) and how far each goes before a surface.
  const ray = new THREE.Raycaster();
  ray.far = BEAM_MAX;
  const dirs: THREE.Vector3[] = [], reach: number[] = [];
  for (let k = 0; k < BEAM_SEGMENTS; k++) {
    const a = (k / BEAM_SEGMENTS) * 2 * Math.PI;
    const d = v(Math.min(Math.max(Math.cos(a) * th, -L), R), Math.min(Math.max(Math.sin(a) * th, -D), U), -1);
    dirs.push(d);
    ray.set(origin, d.clone().normalize().applyQuaternion(q));
    const hit = ray.intersectObjects(hitTargets, true).find(h => h.distance > 0.05);
    reach.push((hit?.distance ?? BEAM_MAX) / d.length()); // as a depth along -Z
  }
  // Smooth round the rim so neighbouring directions agree, keeping the nearer surface where they don't.
  const smooth = reach.map((_, k) => {
    let sum = 0, w = 0;
    for (let j = -3; j <= 3; j++) { const wt = 4 - Math.abs(j); sum += reach[(k + j + BEAM_SEGMENTS) % BEAM_SEGMENTS] * wt; w += wt; }
    return Math.min(sum / w, reach[k] * 1.15);
  });

  const pos: number[] = [], along: number[] = [], index: number[] = [];
  for (let r = 0; r <= BEAM_RINGS; r++) {
    const t = r / BEAM_RINGS;
    for (let k = 0; k <= BEAM_SEGMENTS; k++) {
      const i = k % BEAM_SEGMENTS, depth = smooth[i] * t;
      pos.push(dirs[i].x * depth, dirs[i].y * depth, -depth);
      along.push(t);
    }
  }
  const row = BEAM_SEGMENTS + 1;
  for (let r = 0; r < BEAM_RINGS; r++) for (let k = 0; k < BEAM_SEGMENTS; k++) {
    const a = r * row + k, b = a + row;
    index.push(a, b, a + 1, a + 1, b, b + 1);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('along', new THREE.Float32BufferAttribute(along, 1));
  geo.setIndex(index);
  geo.computeVertexNormals();
  const strength = 0.16 + 0.12 * Math.min(1, Math.log10(1 + pm.flux / 500));
  const material = new THREE.ShaderMaterial({
    uniforms: { color: { value: color.clone() }, strength: { value: strength } },
    vertexShader: beamVertex, fragmentShader: beamFragment,
    transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(geo, material);
  mesh.userData.noShadow = true;
  mesh.userData.noAO = true;
  mesh.raycast = () => {}; // clicks go through the haze to what's behind it
  return mesh;
}
