// Shared parts for the 3D view: materials, small geometry helpers and the textures drawn in code
// (no image files, so the planner stays one small download).
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';

export const rad = (d: number) => (d * Math.PI) / 180;
export const v = (x: number, y: number, z: number) => new THREE.Vector3(x, y, z);

/** A material shared between many meshes; rebuilds must not dispose it. */
const shared = <T extends THREE.Material>(m: T): T => { m.userData.shared = true; return m; };
export const mat = (color: number | string, opts: THREE.MeshStandardMaterialParameters = {}) =>
  new THREE.MeshStandardMaterial({ color, roughness: 0.6, metalness: 0.1, ...opts });

export const STEEL = shared(mat(0xb4b8bc, { metalness: 1, roughness: 0.28 }));
export const CHROME = shared(mat(0xd8dadc, { metalness: 1, roughness: 0.12 }));
export const BLACK = shared(mat(0x101112, { metalness: 0.55, roughness: 0.5 }));
export const SATIN = shared(mat(0x1b1c1e, { metalness: 0.7, roughness: 0.36 }));
export const DARK = shared(mat(0x2a2b2d, { metalness: 0.6, roughness: 0.42 }));
export const RUBBER = shared(mat(0x0c0c0c, { metalness: 0, roughness: 0.95 }));
export const FABRIC_BLACK = shared(mat(0x0b0b0c, { metalness: 0, roughness: 1, side: THREE.DoubleSide }));
export const SILVER_LINING = shared(mat(0xcfd2d4, { metalness: 0.9, roughness: 0.35, side: THREE.DoubleSide }));
export const SAND = shared(mat(0x5d5138, { roughness: 0.98, metalness: 0 }));
export const WOOD_LEG = shared(mat(0x6a5038, { roughness: 0.55, metalness: 0 }));
export const GLASS_LENS = shared(new THREE.MeshPhysicalMaterial({ color: 0x0a1020, roughness: 0.05, metalness: 0.2, clearcoat: 1, clearcoatRoughness: 0.04 }));

export function mesh(g: THREE.BufferGeometry, m: THREE.Material, parent: THREE.Object3D, pos?: THREE.Vector3, rot?: THREE.Euler) {
  const o = new THREE.Mesh(g, m);
  if (pos) o.position.copy(pos);
  if (rot) o.rotation.copy(rot);
  parent.add(o);
  return o;
}

const UP = new THREE.Vector3(0, 1, 0);
/** A round bar between two points (optionally tapered). */
export function bar(a: THREE.Vector3, b: THREE.Vector3, r: number, m: THREE.Material, parent: THREE.Object3D, r2 = r) {
  const d = new THREE.Vector3().subVectors(b, a);
  const len = d.length();
  const o = new THREE.Mesh(new THREE.CylinderGeometry(r2, r, Math.max(len, 0.001), 14), m);
  o.position.copy(a).addScaledVector(d, 0.5);
  if (len > 1e-6) o.quaternion.setFromUnitVectors(UP, d.normalize());
  parent.add(o);
  return o;
}
/** A rounded limb between two points. */
export function limb(a: THREE.Vector3, b: THREE.Vector3, r: number, m: THREE.Material, parent: THREE.Object3D) {
  const d = new THREE.Vector3().subVectors(b, a);
  const len = d.length();
  const o = new THREE.Mesh(new THREE.CapsuleGeometry(r, Math.max(len, 0.001), 6, 14), m);
  o.position.copy(a).addScaledVector(d, 0.5);
  if (len > 1e-6) o.quaternion.setFromUnitVectors(UP, d.normalize());
  parent.add(o);
  return o;
}
export const rbox = (w: number, h: number, d: number, r = 0.02, seg = 3) =>
  new RoundedBoxGeometry(w, h, d, seg, Math.min(r, w / 2 - 1e-4, h / 2 - 1e-4, d / 2 - 1e-4));
export const ALONG = new THREE.Euler(Math.PI / 2, 0, 0); // a Y-up cylinder laid along Z

/** Small repeatable random numbers, so a texture looks the same every time. */
function rng(seed: number) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}

function canvas(size: number) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  return { c, g: c.getContext('2d')! };
}
function finish(c: HTMLCanvasElement, srgb: boolean, repeat = true) {
  const t = new THREE.CanvasTexture(c);
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  t.anisotropy = 8;
  return t;
}

/** Pale, neutral floorboards: one tile is 2.4 m square. Colour map plus a height map for the joints. */
export function floorTextures(): { map: THREE.Texture; bump: THREE.Texture; tile: number } {
  const N = 1024, tile = 2.4, rows = 12; // 20 cm boards
  const col = canvas(N), bmp = canvas(N);
  const r = rng(7);
  bmp.g.fillStyle = '#808080'; bmp.g.fillRect(0, 0, N, N);
  const rowH = N / rows;
  for (let i = 0; i < rows; i++) {
    let x = -r() * N * 0.5;
    while (x < N) {
      const len = N * (0.35 + r() * 0.4);
      const tone = 150 + Math.round(r() * 26), warm = 4 + r() * 8;
      col.g.fillStyle = `rgb(${tone + warm},${tone},${tone - warm * 1.4})`;
      col.g.fillRect(x, i * rowH, len, rowH);
      // Grain: faint long streaks.
      for (let k = 0; k < 26; k++) {
        const y = i * rowH + r() * rowH, a = 0.03 + r() * 0.05;
        col.g.strokeStyle = r() > 0.5 ? `rgba(60,45,30,${a})` : `rgba(255,250,240,${a})`;
        col.g.lineWidth = 0.6 + r() * 1.2;
        col.g.beginPath(); col.g.moveTo(x, y); col.g.bezierCurveTo(x + len * 0.3, y + (r() - 0.5) * 5, x + len * 0.7, y + (r() - 0.5) * 5, x + len, y + (r() - 0.5) * 3); col.g.stroke();
      }
      // Joints.
      for (const g of [col.g, bmp.g]) {
        g.fillStyle = g === col.g ? 'rgba(40,32,24,.55)' : '#404040';
        g.fillRect(x + len - 1.5, i * rowH, 3, rowH);
        g.fillRect(x, i * rowH - 1, len, 2.5);
      }
      x += len;
    }
  }
  return { map: finish(col.c, true), bump: finish(bmp.c, false), tile };
}

/** Painted plaster: almost flat, with just enough unevenness to catch a raking light. */
export function plasterBump(): THREE.Texture {
  const N = 256, { c, g } = canvas(N), r = rng(3);
  const img = g.createImageData(N, N);
  for (let i = 0; i < N * N; i++) { const n = 122 + Math.round(r() * 12); img.data.set([n, n, n, 255], i * 4); }
  g.putImageData(img, 0, 0);
  g.filter = 'blur(1.2px)'; g.drawImage(c, 0, 0);
  return finish(c, false);
}

/** Woven cloth for sofas and chairs. */
export function fabricBump(): THREE.Texture {
  const N = 128, { c, g } = canvas(N);
  g.fillStyle = '#808080'; g.fillRect(0, 0, N, N);
  for (let y = 0; y < N; y += 4) for (let x = 0; x < N; x += 4) {
    g.fillStyle = (x + y) % 8 === 0 ? '#a0a0a0' : '#606060';
    g.fillRect(x, y, 2, 4); g.fillRect(x + 2, y + 1, 2, 2);
  }
  return finish(c, false);
}

/** An egg-crate grid for the front of a gridded softbox or panel. */
export function gridTexture(cells: number): THREE.Texture {
  const N = 256, { c, g } = canvas(N);
  g.fillStyle = '#fff'; g.fillRect(0, 0, N, N);
  g.strokeStyle = '#050505'; g.lineWidth = N / cells * 0.24;
  for (let i = 0; i <= cells; i++) {
    const p = (i / cells) * N;
    g.beginPath(); g.moveTo(p, 0); g.lineTo(p, N); g.stroke();
    g.beginPath(); g.moveTo(0, p); g.lineTo(N, p); g.stroke();
  }
  return finish(c, true, false);
}

/** Concentric rings of a fresnel lens. */
export function fresnelTexture(): THREE.Texture {
  const N = 256, { c, g } = canvas(N);
  g.fillStyle = '#fff'; g.fillRect(0, 0, N, N);
  for (let i = 1; i < 14; i++) {
    g.strokeStyle = `rgba(0,0,0,${i % 2 ? 0.2 : 0.08})`; g.lineWidth = 3;
    g.beginPath(); g.arc(N / 2, N / 2, (i / 14) * N / 2, 0, Math.PI * 2); g.stroke();
  }
  return finish(c, true, false);
}

/** LED panel face: rows of emitters behind a diffuser. */
export function ledTexture(): THREE.Texture {
  const N = 256, { c, g } = canvas(N);
  g.fillStyle = '#d8d8d8'; g.fillRect(0, 0, N, N);
  g.fillStyle = '#fff';
  for (let y = 8; y < N; y += 16) for (let x = 8; x < N; x += 16) { g.beginPath(); g.arc(x, y, 4.5, 0, Math.PI * 2); g.fill(); }
  g.filter = 'blur(2.5px)'; g.drawImage(c, 0, 0);
  return finish(c, true, false);
}

/** Vertical gradient behind the set: dark studio grey falling to black. */
export function backdropTexture(): THREE.Texture {
  const N = 512, { c, g } = canvas(N);
  const grad = g.createLinearGradient(0, 0, 0, N);
  grad.addColorStop(0, '#16181a'); grad.addColorStop(0.55, '#0c0d0e'); grad.addColorStop(1, '#050505');
  g.fillStyle = grad; g.fillRect(0, 0, N, N);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

const texCache = new Map<string, unknown>();
/** Build a texture (or texture set) once and keep it for the life of the page. */
export function cached<T>(key: string, make: () => T): T {
  if (!texCache.has(key)) texCache.set(key, make());
  return texCache.get(key) as T;
}
