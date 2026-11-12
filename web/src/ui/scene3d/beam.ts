// A soft beam: light in haze. The haze is marched through in the shader, and at every point it
// asks how far the light gets in that direction before something stops it (a grid of rays cast
// once from the unit: the room, flags, frames, boards and people). So a flag in the beam leaves
// nothing behind it, a person casts a shadow through the haze, and a beam stops where it meets
// the floor or a wall. It fades towards its edge and its far end, so it reads as light in the air.
import * as THREE from 'three';
import type { LightFixture } from '../../model/types';
import type { ResolvedPhotometrics } from '../../model/photometrics';
import { rad, v } from './kit';

const BEAM_MAX = 7;
/** Rays a side across the beam: enough for a flag's edge to read, few enough to cast in a blink. */
const GRID = 40;

const beamVertex = `
  varying vec3 vWorld;
  void main() {
    vec4 w = modelMatrix * vec4(position, 1.0);
    vWorld = w.xyz;
    gl_Position = projectionMatrix * viewMatrix * w;
  }`;
const beamFragment = `
  uniform vec3 color;
  uniform float strength;
  uniform sampler2D reach;
  uniform vec4 limits;   // left, right, down, up, as tangents of the angle off the axis
  uniform float spread;  // tangent of the half-angle where the haze has faded out
  uniform float depthMax;
  uniform mat4 toLocal;
  varying vec3 vWorld;
  const int STEPS = 64;
  bool inside(vec3 p) {
    float d = -p.z;
    if (d <= 0.0 || d > depthMax) return false;
    vec2 t = p.xy / d;
    return t.x >= -limits.x && t.x <= limits.y && t.y >= -limits.z && t.y <= limits.w;
  }
  void main() {
    vec3 eye = (toLocal * vec4(cameraPosition, 1.0)).xyz;
    vec3 hit = (toLocal * vec4(vWorld, 1.0)).xyz;
    vec3 ray = hit - eye;
    float far = length(ray);
    ray /= far;
    bool eyeInside = inside(eye);
    // Looking in from outside, start where the view enters the volume (its front face) and go on
    // through it; from inside, go from the eye to the wall of the volume (a back face).
    if (eyeInside == gl_FrontFacing) discard;
    vec3 start = eyeInside ? eye : hit;
    float span = eyeInside ? far : depthMax * 2.2;
    float stepLen = span / float(STEPS);
    float jitter = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715)))); // even dither, no salt-and-pepper
    float glow = 0.0;
    for (int i = 0; i < STEPS; i++) {
      vec3 p = start + ray * ((float(i) + jitter) * stepLen);
      if (!inside(p)) continue;
      float d = -p.z;
      vec2 t = p.xy / d;
      vec2 uv = vec2((t.x + limits.x) / (limits.x + limits.y), (t.y + limits.z) / (limits.z + limits.w));
      if (d > texture2D(reach, uv).r * depthMax) continue;
      float edge = 1.0 - smoothstep(0.5, 1.0, length(t) / spread);
      float along = d / depthMax;
      float fade = (1.0 - smoothstep(0.45, 1.0, along)) * smoothstep(0.0, 0.06, along);
      glow += edge * fade * stepLen;
    }
    gl_FragColor = vec4(color * strength * glow * 0.75, 1.0);
  }`;

/** How bright the haze is for a unit's output. */
export function beamStrength(pm: ResolvedPhotometrics) { return 0.16 + 0.12 * Math.min(1, Math.log10(1 + pm.flux / 500)); }

/** How far the light gets across the beam: a GRID × GRID depth map, and the furthest depth. */
export interface Reach { depths: Float32Array; deepest: number }

/** Remembered reach maps, by everything that shapes them (see Scene3D). Switching a unit off and
 *  on, dimming it or changing its colour doesn't move anything, so its beam comes back at once. */
export type ReachCache = Map<string, Reach>;
const CACHE_SIZE = 64;

/** Casts the grid of rays. Each ray tests the solid things in order of where their bounding box
 *  starts along it and stops once the nearest hit so far is closer than the next box: the same
 *  nearest hit as testing everything, without walking every triangle of every person and sofa. */
function traceReach(origin: THREE.Vector3, q: THREE.Quaternion, L: number, R: number, D: number, U: number, th: number, hitTargets: THREE.Object3D[]): Reach {
  const ray = new THREE.Raycaster();
  ray.far = BEAM_MAX * 1.8;
  const solids: { o: THREE.Object3D; box: THREE.Box3 }[] = [];
  for (const t of hitTargets) t.traverse(o => {
    const g = (o as THREE.Mesh).geometry as THREE.BufferGeometry | undefined;
    if (!g || !o.layers.test(ray.layers)) return;
    if (!g.boundingBox) g.computeBoundingBox();
    solids.push({ o, box: g.boundingBox!.clone().applyMatrix4(o.matrixWorld) });
  });
  const at = new THREE.Vector3(), hits: THREE.Intersection[] = [], order: { o: THREE.Object3D; entry: number }[] = [];
  const depths = new Float32Array(GRID * GRID);
  let deepest = 0.3;
  for (let j = 0; j < GRID; j++) for (let i = 0; i < GRID; i++) {
    const x = -L + ((i + 0.5) / GRID) * (L + R), y = -D + ((j + 0.5) / GRID) * (D + U);
    if (Math.hypot(x, y) > th * 1.02) continue;
    const d = v(x, y, -1);
    ray.set(origin, d.clone().normalize().applyQuaternion(q));
    order.length = 0;
    for (const s of solids) {
      if (s.box.containsPoint(origin)) { order.push({ o: s.o, entry: 0 }); continue; }
      const p = ray.ray.intersectBox(s.box, at);
      if (p) order.push({ o: s.o, entry: p.distanceTo(origin) });
    }
    order.sort((a, b) => a.entry - b.entry);
    let nearest = ray.far + 1;
    for (const { o, entry } of order) {
      if (entry > nearest) break;
      hits.length = 0;
      o.raycast(ray, hits);
      for (const h of hits) if (h.distance > 0.05 && h.distance <= ray.far && h.distance < nearest) nearest = h.distance;
    }
    const depth = Math.min(BEAM_MAX, (nearest <= ray.far ? nearest : BEAM_MAX * 1.8) / d.length());
    deepest = Math.max(deepest, depth);
    depths[j * GRID + i] = depth;
  }
  return { depths, deepest };
}

export function beam(l: LightFixture, pm: ResolvedPhotometrics, origin: THREE.Vector3, q: THREE.Quaternion, color: THREE.Color, hitTargets: THREE.Object3D[], cache?: { store: ReachCache; key: string }): THREE.Mesh | undefined {
  if (pm.distribution !== 'beam' && pm.distribution !== 'lambertian') return undefined;
  const half = Math.min(pm.distribution === 'beam' ? pm.beamAngle * 0.6 : 50, 70);
  const th = Math.tan(rad(half));
  const doors = l.barnDoors;
  const lim = (d: number) => Math.tan(rad(Math.min(half, doors ? d : 90)));
  const L = lim(doors?.left ?? 90), R = lim(doors?.right ?? 90), D = lim(doors?.bottom ?? 90), U = lim(doors?.top ?? 90);

  // How far the light gets along each direction across the beam, as a depth along −Z.
  const key = cache && `${cache.key}|${[origin.x, origin.y, origin.z, q.x, q.y, q.z, q.w, L, R, D, U, th].map(n => n.toFixed(5)).join(',')}`;
  let found = key ? cache!.store.get(key) : undefined;
  if (!found) {
    found = traceReach(origin, q, L, R, D, U, th, hitTargets);
    if (key) {
      cache!.store.set(key, found);
      if (cache!.store.size > CACHE_SIZE) cache!.store.delete(cache!.store.keys().next().value!);
    }
  }
  const { depths, deepest } = found;
  const data = new Uint8Array(GRID * GRID * 4);
  depths.forEach((d, k) => { const c = Math.round(255 * d / BEAM_MAX); data.set([c, c, c, 255], k * 4); });
  const reach = new THREE.DataTexture(data, GRID, GRID, THREE.RGBAFormat);
  reach.magFilter = reach.minFilter = THREE.LinearFilter;
  reach.wrapS = reach.wrapT = THREE.ClampToEdgeWrapping;
  reach.needsUpdate = true;

  // The volume the haze can be in: a closed pyramid from the lens to the furthest reach.
  // Its far end sits just short of the furthest surface reached, so it never pokes out past a flag.
  const far = Math.min(BEAM_MAX, deepest - 0.03), n = 0.02;
  const corners = [[-L, -D], [R, -D], [R, U], [-L, U]];
  const pos: number[] = [];
  for (const [x, y] of corners) pos.push(x * n, y * n, -n);
  for (const [x, y] of corners) pos.push(x * far, y * far, -far);
  const index = [0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 5, 1, 0, 4, 5, 1, 6, 2, 1, 5, 6, 2, 7, 3, 2, 6, 7, 3, 4, 0, 3, 7, 4]; // wound so the faces look outwards
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setIndex(index);
  geo.computeVertexNormals();

  const strength = beamStrength(pm);
  const uniforms = {
    color: { value: color.clone() }, strength: { value: strength }, reach: { value: reach },
    limits: { value: new THREE.Vector4(L, R, D, U) }, spread: { value: th }, depthMax: { value: BEAM_MAX },
    toLocal: { value: new THREE.Matrix4() },
  };
  const material = new THREE.ShaderMaterial({
    uniforms, vertexShader: beamVertex, fragmentShader: beamFragment,
    transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
  });
  material.addEventListener('dispose', () => reach.dispose());
  // Freed without disposing the material, so its shader stays built for the next beam: a unit
  // switched off and on again shows its beam at once instead of waiting for a recompile.
  material.userData.release = () => reach.dispose();
  const mesh = new THREE.Mesh(geo, material);
  mesh.userData.uniforms = uniforms; // colour and strength follow the unit without a rebuild
  mesh.onBeforeRender = () => { uniforms.toLocal.value.copy(mesh.matrixWorld).invert(); };
  mesh.frustumCulled = false; // the camera can sit inside it
  mesh.userData.noShadow = true;
  mesh.userData.noAO = true;
  mesh.raycast = () => {}; // clicks go through the haze to what's behind it
  return mesh;
}
