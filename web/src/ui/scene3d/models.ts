// Equipment and people for the 3D view: generic lighting units, stands, a cinema camera, figures.
// Everything faces −Z in its own frame. Shapes are generic on purpose (no maker's designs).
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import type { BarnDoors, CameraRig, LightFixture, LightMeter, PrevisCharacter } from '../../model/types';
import { fixtureProfile, type ResolvedPhotometrics } from '../../model/photometrics';
import { cameraSupport, gripStandCount, type LightSupport } from '../../model/rigging';
import { drape, drapeOptics, frameGels, gripSize } from '../../model/grip';
import { boardOptics } from '../../model/calculator';
import { hairOf, isChild, shapeBlend, skinRGB } from '../../model/characters';
import {
  ALONG, BLACK, CHROME, DARK, FABRIC_BLACK, GLASS_LENS, RUBBER, SAND, SATIN, SILVER_LINING, STEEL, WOOD_LEG,
  bar, cached, fabricBump, fresnelTexture, gridTexture, ledTexture, limb, mat, mesh, rbox, v,
} from './kit';

// MARK: Stands

/** A telescoping riser: three sections, each slimmer than the last, with a locking collar at every joint. */
function riser(x: number, z: number, y0: number, y1: number, r: number, parent: THREE.Object3D) {
  const n = y1 - y0 > 1.2 ? 3 : y1 - y0 > 0.5 ? 2 : 1;
  for (let i = 0; i < n; i++) {
    const a = y0 + ((y1 - y0) * i) / n, b = y0 + ((y1 - y0) * (i + 1)) / n, ri = r * (1 - i * 0.2);
    bar(v(x, a, z), v(x, b, z), ri, i === 0 ? STEEL : CHROME, parent);
    if (i > 0) {
      bar(v(x, a - 0.03, z), v(x, a + 0.02, z), ri * 1.55, SATIN, parent);
      bar(v(x + ri * 1.4, a - 0.005, z), v(x + ri * 1.4 + 0.045, a - 0.005, z), 0.007, SATIN, parent); // locking knob
    }
  }
}

/** Stand from the floor (y = -height) up to `top`, in the unit's pan space. */
export function stand(support: LightSupport, height: number, top: number, parent: THREE.Object3D) {
  const floor = -height;
  const legs = (o: THREE.Vector3, hub: number, spread: number, r: number, opts: { sandbag?: boolean; braced?: boolean; wheels?: boolean; stagger?: number }) => {
    for (let i = 0; i < 3; i++) {
      const a = (i * 2 * Math.PI) / 3 + Math.PI / 3;
      const lift = opts.wheels ? 0.09 : 0.018;
      const foot = v(o.x + Math.sin(a) * spread, floor + lift, o.z + Math.cos(a) * spread);
      const from = v(o.x, hub - i * (opts.stagger ?? 0), o.z);
      bar(from, foot, r, STEEL, parent);
      if (opts.braced) bar(v(o.x, hub - 0.3, o.z), v(o.x + Math.sin(a) * spread * 0.55, floor + lift + (hub - floor) * 0.42, o.z + Math.cos(a) * spread * 0.55), r * 0.6, STEEL, parent);
      if (opts.wheels) {
        const wheel = mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.035, 20), RUBBER, parent, v(foot.x, floor + 0.05, foot.z), new THREE.Euler(0, a, Math.PI / 2));
        wheel.castShadow = true;
        bar(foot, v(foot.x, floor + 0.05, foot.z), 0.012, SATIN, parent);
      } else mesh(new THREE.SphereGeometry(r * 1.5, 10, 8), RUBBER, parent, foot);
      if (opts.sandbag && i === 2) {
        const bag = mesh(new THREE.CapsuleGeometry(0.075, 0.3, 6, 12), SAND, parent, v((o.x + foot.x) / 2, (hub + foot.y) / 2 + 0.035, (o.z + foot.z) / 2));
        bag.rotation.set(0, a, Math.PI / 2 - 0.55);
        bag.scale.set(1, 1, 0.75);
      }
    }
    bar(v(o.x, hub - 0.1, o.z), v(o.x, hub + 0.04, o.z), r * 1.9, SATIN, parent); // leg collar
  };
  switch (support) {
    case 'cStand':
      legs(v(0, 0, 0), floor + 0.32, 0.42, 0.012, { sandbag: true, stagger: 0.04 });
      riser(0, 0, floor + 0.2, top, 0.016, parent);
      break;
    case 'comboStand':
      legs(v(0, 0, 0), floor + 0.55, 0.58, 0.016, { braced: true });
      riser(0, 0, floor + 0.2, top, 0.024, parent);
      break;
    case 'rollerStand':
      legs(v(0, 0, 0), floor + 0.6, 0.62, 0.018, { braced: true, wheels: true });
      riser(0, 0, floor + 0.25, top, 0.027, parent);
      break;
    case 'windUp': {
      // Crank-up stand: wide braced legs, a fat inner column and the crank box on the first section.
      legs(v(0, 0, 0), floor + 0.7, 0.75, 0.02, { braced: true });
      riser(0, 0, floor + 0.3, top, 0.032, parent);
      mesh(rbox(0.09, 0.14, 0.08, 0.015), SATIN, parent, v(0.06, floor + 0.95, 0));
      bar(v(0.105, floor + 0.95, 0), v(0.17, floor + 0.95, 0), 0.008, CHROME, parent);
      bar(v(0.17, floor + 0.95, 0), v(0.17, floor + 0.87, 0), 0.006, CHROME, parent); // crank handle
      break;
    }
    case 'turtleBase':
      legs(v(0, 0, 0), floor + 0.07, 0.36, 0.012, {});
      bar(v(0, floor + 0.04, 0), v(0, top, 0), 0.016, STEEL, parent);
      break;
    case 'megaBoom': {
      const reach = 2.2, armY = top + 0.12;
      legs(v(0, 0, reach), floor + 0.6, 0.62, 0.018, { braced: true, wheels: true });
      riser(0, reach, floor + 0.25, armY, 0.027, parent);
      bar(v(0, armY, -0.05), v(0, armY, reach + 0.9), 0.02, STEEL, parent);
      mesh(rbox(0.15, 0.2, 0.17, 0.02), DARK, parent, v(0, armY - 0.06, reach + 0.95)); // counterweight
      mesh(rbox(0.09, 0.09, 0.09, 0.015), SATIN, parent, v(0, armY, reach));
      bar(v(0, armY, 0), v(0, top, 0), 0.01, STEEL, parent);
      break;
    }
    case 'overhead':
      bar(v(0, top, 0), v(0, top + 0.45, 0), 0.01, STEEL, parent);
      bar(v(-0.8, top + 0.48, 0), v(0.8, top + 0.48, 0), 0.024, STEEL, parent);
      mesh(rbox(0.07, 0.08, 0.07, 0.01), SATIN, parent, v(0, top + 0.46, 0)); // clamp
      break;
    case 'floor': bar(v(0, floor + 0.01, 0), v(0, top, 0), 0.01, STEEL, parent); break;
    case 'none': break;
  }
}

/** Yoke round the head (pan space). Returns the stud's height. */
export function yoke(half: number, below: number, hanging: boolean, parent: THREE.Object3D): number {
  const x = half + 0.03, y = (below + 0.035) * (hanging ? 1 : -1);
  for (const s of [-1, 1]) {
    bar(v(s * x, 0, 0), v(s * x, y, 0), 0.009, SATIN, parent);
    bar(v(s * (x - 0.03), 0, 0), v(s * (x + 0.035), 0, 0), 0.02, SATIN, parent); // tilt lock
  }
  bar(v(-x, y, 0), v(x, y, 0), 0.009, SATIN, parent);
  const stud = y + (hanging ? 0.08 : -0.08);
  bar(v(0, y, 0), v(0, stud, 0), 0.012, CHROME, parent);
  return stud;
}

// MARK: Lighting units

/** The glowing face of a unit. Off, it is a plain diffuser. Brightness here is for looks only. */
function glow(color: THREE.Color, on: boolean, level: number, map?: THREE.Texture) {
  // On and off use the same texture slots, so they share one shader, and `relight` can switch a
  // built unit without rebuilding it.
  const m = new THREE.MeshStandardMaterial({ emissiveMap: map ?? null, map: map ?? null, metalness: 0 });
  m.userData.glow = level;
  setGlow(m, color, on, level);
  return m;
}
function setGlow(m: THREE.MeshStandardMaterial, color: THREE.Color, on: boolean, level: number) {
  m.color.set(on ? 0x000000 : 0xcfcfcb);
  m.emissive.copy(on ? color : BLACK_COLOUR);
  m.emissiveIntensity = on ? level : 0;
  m.roughness = on ? 0.6 : 0.75;
}
function setShade(m: THREE.MeshStandardMaterial, color: THREE.Color, on: boolean, level: number) {
  m.color.set(on ? 0x000000 : 0xd8d2c6);
  m.emissive.copy(on ? color : BLACK_COLOUR);
  m.emissiveIntensity = on ? level * 0.22 : 0;
}
const BLACK_COLOUR = new THREE.Color(0x000000);

/** How bright a unit's face glows, from its output. */
export function glowLevel(pm: ResolvedPhotometrics) { return 2.2 + 1.6 * Math.min(1, Math.log10(1 + pm.flux / 800) / 2); }

/** Switches, dims or recolours a unit built by `head` in place: only material values change, so
 *  nothing is rebuilt and no shader is compiled. `built` is the glow level it was built with. */
export function relight(root: THREE.Object3D, color: THREE.Color, on: boolean, level: number, built: number) {
  root.traverse(o => {
    const m = (o as THREE.Mesh).material as THREE.MeshStandardMaterial | undefined;
    if (!m || !(o as THREE.Mesh).isMesh) return;
    if (m.userData.glow !== undefined) setGlow(m, color, on, m.userData.glow * level / built);
    else if (m.userData.shade) setShade(m, color, on, level);
  });
}

/** Four leaves hinged round a face of half-size `hs` at depth `front`; each sits at its cut angle. */
function barnDoors(doors: BarnDoors, hs: number, front: number, parent: THREE.Object3D) {
  const len = hs * 1.35, wide = hs * 1.8;
  const leaf = (x: number, y: number, rx: number, ry: number, horizontal: boolean) => {
    const hinge = new THREE.Group();
    hinge.position.set(x, y, -front);
    hinge.rotation.set(rx, ry, 0);
    const m = mesh(new THREE.BoxGeometry(horizontal ? wide : 0.004, horizontal ? 0.004 : wide, len), BLACK, hinge, v(0, 0, -len / 2));
    m.userData.noShadow = true; // the beam's shape comes from the calculator's cut, not from this mesh
    parent.add(hinge);
  };
  // A door's value is how far its edge of the beam is from the axis; 90 means wide open.
  const a = (d: number) => (Math.min(Math.max(d, 6), 78) * Math.PI) / 180;
  leaf(hs, 0, 0, -a(doors.right), false);
  leaf(-hs, 0, 0, a(doors.left), false);
  leaf(0, hs, a(doors.top), 0, true);
  leaf(0, -hs, -a(doors.bottom), 0, true);
}

export interface HeadSize { half: number; below: number; front: number }

/** Head facing −Z, sized by fixture category. `front` is how far ahead of the tilt axis the light leaves it. */
export function head(l: LightFixture, pm: ResolvedPhotometrics, color: THREE.Color, parent: THREE.Object3D): HeadSize {
  const p = fixtureProfile(l);
  const on = l.isOn;
  const level = glowLevel(pm);
  const mod = pm.modifier?.id ?? '';
  const doors = l.barnDoors && pm.barnDoorsAvailable ? l.barnDoors : undefined;
  let size: HeadSize;
  switch (p.category) {
    case 'panel': case 'soft': {
      const w = p.emitterWidth, h = p.emitterHeight;
      mesh(rbox(w + 0.05, h + 0.05, 0.06, 0.012), BLACK, parent, v(0, 0, 0.032));
      for (let i = -2; i <= 2; i++) mesh(new THREE.BoxGeometry(w * 0.7, 0.012, 0.02), SATIN, parent, v(0, (i * h) / 6, 0.07)); // cooling fins
      mesh(rbox(Math.min(0.2, w * 0.6), 0.09, 0.05, 0.01), DARK, parent, v(0, -h * 0.2, 0.09));
      let front = 0.003;
      if (mod === 'panel-softbox') {
        const s = pm.modifier?.size ?? 0.6, depth = 0.22;
        const box = mesh(new THREE.CylinderGeometry(s / Math.SQRT2, Math.max(w, h) / Math.SQRT2, depth, 4, 1, true), FABRIC_BLACK, parent, v(0, 0, -depth / 2));
        box.rotation.set(-Math.PI / 2, 0, 0); box.rotateY(Math.PI / 4);
        mesh(new THREE.PlaneGeometry(s, s), glow(color, on, level), parent, v(0, 0, -depth - 0.002), new THREE.Euler(0, Math.PI, 0));
        front = depth + 0.004;
        size = { half: w / 2 + 0.03, below: h / 2 + 0.03, front };
        break;
      }
      const face = mod === 'panel-grid-40' ? cached('grid8', () => gridTexture(8)) : p.category === 'panel' ? cached('led', ledTexture) : undefined;
      mesh(new THREE.PlaneGeometry(w, h), glow(color, on, level, face), parent, v(0, 0, -front), new THREE.Euler(0, Math.PI, 0));
      size = { half: w / 2 + 0.03, below: h / 2 + 0.03, front };
      if (doors) barnDoors(doors, Math.max(w, h) / 2 + 0.02, 0.005, parent);
      break;
    }
    case 'tube': {
      const len = p.emitterWidth;
      mesh(new THREE.CylinderGeometry(0.021, 0.021, len - 0.08, 20), glow(color, on, level), parent, v(0, 0, 0), new THREE.Euler(0, 0, Math.PI / 2));
      for (const s of [-1, 1]) mesh(new THREE.CylinderGeometry(0.023, 0.023, 0.045, 20), SATIN, parent, v((s * (len - 0.04)) / 2, 0, 0), new THREE.Euler(0, 0, Math.PI / 2));
      size = { half: 0.05, below: 0.04, front: 0.03 };
      break;
    }
    case 'spaceLight': {
      mesh(new THREE.CylinderGeometry(0.32, 0.3, 0.52, 32, 1, true), glow(color, on, level * 0.8), parent, v(0, -0.02, 0)).material.side = THREE.DoubleSide;
      mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.004, 32), glow(color, on, level), parent, v(0, -0.28, 0));
      mesh(new THREE.CylinderGeometry(0.33, 0.33, 0.05, 32), BLACK, parent, v(0, 0.26, 0));
      size = { half: 0.35, below: 0.3, front: 0.34 };
      break;
    }
    case 'practical': {
      // A table or floor lamp: bulb, fabric shade, and its own slim pole (added by the caller).
      mesh(new THREE.SphereGeometry(0.035, 16, 12), glow(color, on, level * 1.6), parent, v(0, 0, 0));
      const shade = new THREE.MeshStandardMaterial({ roughness: 0.9, side: THREE.DoubleSide });
      shade.userData.shade = true;
      setShade(shade, color, on, level);
      mesh(new THREE.CylinderGeometry(0.11, 0.17, 0.2, 32, 1, true), shade, parent, v(0, 0.03, 0));
      size = { half: 0.1, below: 0.1, front: 0 };
      break;
    }
    case 'hmi': case 'fresnel': case 'tungsten': {
      const r = p.category === 'hmi' ? 0.17 : Math.min(0.2, Math.max(0.11, p.emitterWidth / 2 + 0.03));
      const softbox = mod.startsWith('softbox');
      mesh(new THREE.CylinderGeometry(r, r * 0.92, 0.34, 32), BLACK, parent, v(0, 0, 0.11), ALONG);
      mesh(new THREE.SphereGeometry(r * 0.92, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2), BLACK, parent, v(0, 0, 0.28), new THREE.Euler(Math.PI / 2, 0, 0)).scale.set(1, 0.45, 1);
      for (let i = 0; i < 4; i++) mesh(new THREE.TorusGeometry(r * 0.99, 0.006, 6, 32), SATIN, parent, v(0, 0, 0.08 + i * 0.05)); // vents
      mesh(new THREE.CylinderGeometry(r * 1.06, r * 1.06, 0.03, 32), SATIN, parent, v(0, 0, -0.055), ALONG); // lens ring
      bar(v(-r * 0.5, r + 0.035, 0.12), v(r * 0.5, r + 0.035, 0.12), 0.008, SATIN, parent); // handle
      for (const s of [-1, 1]) bar(v(s * r * 0.5, r - 0.01, 0.12), v(s * r * 0.5, r + 0.035, 0.12), 0.006, SATIN, parent);
      if (softbox) { size = { half: r + 0.02, below: r + 0.02, front: softboxOn(pm, color, on, level, 0.07, parent) }; break; }
      const lens = p.category === 'hmi' ? undefined : cached('fresnel', fresnelTexture);
      mesh(new THREE.CircleGeometry(r * 0.9, 40), glow(color, on, level * 1.25, lens), parent, v(0, 0, -0.071), new THREE.Euler(0, Math.PI, 0));
      size = { half: r + 0.02, below: r + 0.02, front: 0.075 };
      if (doors) barnDoors(doors, r * 1.02, 0.072, parent);
      break;
    }
    default: {
      // COB: compact body, mount ring, and its reflector, softbox or lantern.
      mesh(rbox(0.16, 0.17, 0.25, 0.02), BLACK, parent, v(0, 0, 0.12));
      mesh(new THREE.CylinderGeometry(0.06, 0.06, 0.006, 24), DARK, parent, v(0, 0, 0.247), ALONG); // fan grille
      mesh(new THREE.CylinderGeometry(0.075, 0.075, 0.03, 32), SATIN, parent, v(0, 0, -0.012), ALONG); // mount
      bar(v(-0.05, 0.11, 0.12), v(0.05, 0.11, 0.12), 0.008, SATIN, parent);
      let front: number;
      if (mod.startsWith('softbox')) front = softboxOn(pm, color, on, level, 0.03, parent);
      else if (mod.startsWith('lantern')) {
        const r = (pm.modifier?.size ?? 0.65) / 2;
        mesh(new THREE.SphereGeometry(r, 32, 20), glow(color, on, level * 0.8), parent, v(0, 0, -0.03 - r));
        front = 0.03 + r;
      } else if (mod === 'fresnel-attachment' || mod === 'projector') {
        const len = mod === 'projector' ? 0.36 : 0.2, r = mod === 'projector' ? 0.07 : 0.1;
        mesh(new THREE.CylinderGeometry(r, r * 0.85, len, 32), BLACK, parent, v(0, 0, -0.03 - len / 2), ALONG);
        mesh(new THREE.CircleGeometry(r * 0.9, 32), glow(color, on, level * 1.25, cached('fresnel', fresnelTexture)), parent, v(0, 0, -0.032 - len), new THREE.Euler(0, Math.PI, 0));
        front = 0.035 + len;
        if (doors) barnDoors(doors, r * 1.05, front, parent);
      } else if (mod === 'cob-bare') {
        mesh(new THREE.SphereGeometry(0.04, 20, 10, 0, Math.PI * 2, 0, Math.PI / 2), glow(color, on, level * 1.5), parent, v(0, 0, -0.027), new THREE.Euler(-Math.PI / 2, 0, 0));
        front = 0.07;
      } else {
        // Reflector: the narrower the beam, the deeper the dish.
        const deep = pm.beamAngle <= 20 ? 0.3 : pm.beamAngle <= 35 ? 0.2 : 0.14, r = pm.beamAngle <= 20 ? 0.13 : 0.115;
        const dish = mesh(new THREE.CylinderGeometry(r, 0.06, deep, 40, 1, true), SILVER_LINING, parent, v(0, 0, -0.027 - deep / 2));
        dish.rotation.x = -Math.PI / 2;
        mesh(new THREE.TorusGeometry(r, 0.004, 6, 40), SATIN, parent, v(0, 0, -0.027 - deep));
        mesh(new THREE.CircleGeometry(0.05, 24), glow(color, on, level * 1.6), parent, v(0, 0, -0.03), new THREE.Euler(0, Math.PI, 0));
        front = 0.03 + deep;
        if (doors) barnDoors(doors, r * 1.05, front, parent);
      }
      size = { half: 0.12, below: 0.13, front };
    }
  }
  return size;
}

/** An octagonal softbox on a mount at `z0` ahead of the axis. Returns where its front is. */
function softboxOn(pm: ResolvedPhotometrics, color: THREE.Color, on: boolean, level: number, z0: number, parent: THREE.Object3D): number {
  const s = pm.modifier?.size ?? 0.9, depth = s * 0.5, r = s / 2;
  const shell = mesh(new THREE.CylinderGeometry(r, 0.085, depth, 8, 1, true), FABRIC_BLACK, parent, v(0, 0, -z0 - depth / 2));
  shell.rotation.set(-Math.PI / 2, 0, 0); shell.rotateY(Math.PI / 8);
  const grid = pm.modifier?.id.includes('grid') ? cached('grid14', () => gridTexture(14)) : undefined;
  const face = mesh(new THREE.CircleGeometry(r, 8), glow(color, on, level, grid), parent, v(0, 0, -z0 - depth + (grid ? 0.03 : 0.004)), new THREE.Euler(0, Math.PI, 0));
  face.rotateZ(Math.PI / 8);
  const rim = mesh(new THREE.CylinderGeometry(r * 1.005, r * 1.005, 0.035, 8, 1, true), FABRIC_BLACK, parent, v(0, 0, -z0 - depth + 0.012));
  rim.rotation.set(-Math.PI / 2, 0, 0); rim.rotateY(Math.PI / 8);
  // Eight thin rods give the cloth its shape.
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2 + Math.PI / 8;
    bar(v(Math.cos(a) * 0.085, Math.sin(a) * 0.085, -z0), v(Math.cos(a) * r, Math.sin(a) * r, -z0 - depth), 0.004, SATIN, parent).userData.noShadow = true;
  }
  return z0 + depth + 0.01;
}

/** Tint a frame gel puts on the cloth, so a gelled frame reads at a glance. Drawing only. */
function gelTint(id: string): number | undefined {
  if (id.startsWith('cto')) return id.endsWith('full') ? 0xf2a65a : id.endsWith('half') ? 0xf6c48e : 0xf9dcb8;
  if (id.startsWith('ctb')) return id.endsWith('full') ? 0x7fa6e6 : id.endsWith('half') ? 0xa9c3ee : 0xcdddf5;
  if (id.startsWith('plus-green')) return 0xc8e8b8;
  if (id.startsWith('minus-green')) return 0xeac0e0;
  if (id.startsWith('nd')) return 0x9a9a96;
  return undefined;
}

function checkerTexture(): THREE.Texture {
  return cached('tex:checker', () => {
    const c = document.createElement('canvas'); c.width = c.height = 128;
    const g = c.getContext('2d')!;
    for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) { g.fillStyle = (x + y) % 2 ? '#c9ccd0' : '#f6f6f4'; g.fillRect(x * 32, y * 32, 32, 32); }
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping;
    return t;
  });
}

/** Grip on its frame with its rag: two faces back to back, so each side can show what it does with the
 *  light (the far face of a diffusion glows with what it passes; see Scene3D). Face `+1` looks the way
 *  the board faces (the calculator's normal), `-1` the other way. A plain face's albedo is the board's
 *  reflectance, so a flag or neg shows a faint sheen on the side the light hits; coloured rags (lamé,
 *  muslin, checkerboard) and frame gels show their colour; nets stay see-through. A floppy opened shows
 *  its second panel below the first. Returns the frame's height and how far its lowest point sits below
 *  the pivot (pan space). */
export function board(l: LightFixture, parent: THREE.Object3D, reflectance: number, tiltDeg = 0): { h: number; lowest: number } {
  const h = (l.boardHeight as number | undefined) ?? (l.kind === 'flag' ? Math.min(l.width, 0.9) : l.width);
  const w = l.width;
  const rag = drape(l);
  const open = l.floppyOpen === true && gripSize(l)?.floppy === true;
  const lo = open ? -h * 1.5 : -h / 2, hi = h / 2;
  const see = (drapeOptics(l) ?? boardOptics(l.kind)).transmission;
  const tint = frameGels(l).map(g => gelTint(g.id)).filter((x): x is number => x !== undefined).pop();
  const coloured = rag && (rag.kinds[0] === 'bounce' && rag.id !== 'white-board' || rag.pattern === 'checker');
  const lame = rag?.id.endsWith('lame') === true;
  const big = w >= 1.7, tube = big ? 0.016 : w >= 1 ? 0.011 : 0.007;
  for (const side of [1, -1]) {
    const face = mat(0xffffff, { roughness: lame ? 0.38 : l.kind === 'bounce' || l.kind === 'diffusion' ? 0.92 : 1, metalness: lame ? 0.6 : 0, side: THREE.FrontSide });
    if (coloured) face.color.set(rag!.color);
    else face.color.setRGB(reflectance, reflectance, reflectance, THREE.LinearSRGBColorSpace);
    if (tint !== undefined) face.color.multiply(new THREE.Color(tint));
    if (rag?.pattern === 'checker') face.map = checkerTexture();
    if (rag?.pattern === 'net') { face.color.set(rag.color); Object.assign(face, { transparent: true, opacity: 1 - rag.transmission * 0.9, depthWrite: false }); }
    // A rag that lets light through lets you see through it a little too, so a silk doesn't hide the set.
    else if (see > 0) Object.assign(face, { transparent: true, opacity: 1 - see * 0.8, depthWrite: false });
    // The board's normal is the way a unit would point: local −Z. The plane faces +Z, so turn the front face round.
    const m = mesh(new THREE.PlaneGeometry(w - tube * 2, hi - lo - tube * 2), face, parent, v(0, (lo + hi) / 2, side * -0.002), side > 0 ? new THREE.Euler(0, Math.PI, 0) : undefined);
    m.userData.face = side;
    if (rag?.pattern === 'net') { m.userData.noShadow = true; m.userData.noAO = true; }
  }
  // The frame round the rag (two panels for an opened floppy).
  const frameMat = l.kind === 'flag' || l.kind === 'negative' ? SATIN : STEEL;
  const panel = (y0: number, y1: number) => {
    for (const y of [y0, y1]) bar(v(-w / 2, y, 0), v(w / 2, y, 0), tube, frameMat, parent);
    for (const s of [-1, 1]) bar(v((s * w) / 2, y0, 0), v((s * w) / 2, y1, 0), tube, frameMat, parent);
  };
  panel(-h / 2, h / 2);
  if (open) panel(-h * 1.5, -h / 2);
  // Ears at the sides of a big frame, where it pivots on its stands.
  if (gripStandCount(l) === 2) for (const s of [-1, 1]) mesh(rbox(0.06, 0.1, 0.05, 0.01), SATIN, parent, v(s * (w / 2 + 0.03), 0, 0));
  return { h, lowest: -lo * Math.abs(Math.cos(rad(tiltDeg))) };
}

// MARK: Camera

export function cameraModel(rig: CameraRig): THREE.Group {
  const g = new THREE.Group();
  g.position.set(rig.position.x, rig.height, rig.position.z);
  g.rotation.y = -rad(rig.pan);
  const tilt = new THREE.Group();
  tilt.rotation.x = rad(rig.tilt);
  g.add(tilt);
  // Body with a top handle, side monitor and a battery on the back.
  mesh(rbox(0.13, 0.14, 0.2, 0.015), SATIN, tilt, v(0, 0, 0.07));
  mesh(rbox(0.1, 0.11, 0.07, 0.012), DARK, tilt, v(0, -0.005, 0.2));
  bar(v(0, 0.075, 0.0), v(0, 0.105, 0.0), 0.008, BLACK, tilt); bar(v(0, 0.075, 0.13), v(0, 0.105, 0.13), 0.008, BLACK, tilt);
  mesh(rbox(0.03, 0.022, 0.19, 0.01), BLACK, tilt, v(0, 0.112, 0.065));
  const monitor = mesh(rbox(0.012, 0.075, 0.12, 0.004), BLACK, tilt, v(-0.085, 0.045, 0.05));
  monitor.rotation.y = -0.25;
  mesh(new THREE.PlaneGeometry(0.105, 0.062), GLASS_LENS, tilt, v(-0.093, 0.045, 0.048), new THREE.Euler(0, -Math.PI / 2 - 0.25, 0));
  // Lens: longer for longer focal lengths, with focus and iris rings and a coated front element.
  const len = Math.min(0.3, 0.08 + rig.focalLength / 520), lr = 0.047;
  mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.03, 32), CHROME, tilt, v(0, 0, -0.04), ALONG);
  mesh(new THREE.CylinderGeometry(lr, lr * 0.94, len, 32), BLACK, tilt, v(0, 0, -0.05 - len / 2), ALONG);
  for (const t of [0.3, 0.62]) mesh(new THREE.CylinderGeometry(lr * 1.07, lr * 1.07, len * 0.16, 40), DARK, tilt, v(0, 0, -0.05 - len * t), ALONG);
  mesh(new THREE.CircleGeometry(lr * 0.86, 32), GLASS_LENS, tilt, v(0, 0, -0.052 - len), new THREE.Euler(0, Math.PI, 0));
  // Matte box with a top flag, on two rods.
  const mz = -0.05 - len;
  const hood = mesh(new THREE.CylinderGeometry(0.105, 0.07, 0.085, 4, 1, true), mat(0x0c0c0c, { roughness: 0.9, metalness: 0.1, side: THREE.DoubleSide }), tilt, v(0, 0, mz - 0.04));
  hood.rotation.set(-Math.PI / 2, 0, 0); hood.rotateY(Math.PI / 4); hood.scale.set(1.25, 1, 0.85);
  const flag = mesh(new THREE.BoxGeometry(0.19, 0.003, 0.1), BLACK, tilt, v(0, 0.068, mz - 0.12));
  flag.rotation.x = 0.2;
  for (const s of [-1, 1]) bar(v(s * 0.03, -0.085, 0.1), v(s * 0.03, -0.085, mz - 0.02), 0.0075, CHROME, tilt);
  mesh(rbox(0.1, 0.02, 0.16, 0.006), DARK, tilt, v(0, -0.08, 0.05)); // base plate

  const support = cameraSupport(rig);
  const floor = -rig.height;
  if (support === 'tripod' || support === 'babyLegs' || support === 'highHat' || support === 'dolly') {
    // Fluid head with a pan bar.
    mesh(new THREE.CylinderGeometry(0.06, 0.07, 0.1, 28), DARK, g, v(0, -0.15, 0.03));
    mesh(new THREE.CylinderGeometry(0.075, 0.05, 0.05, 28), SATIN, g, v(0, -0.225, 0.03));
    bar(v(0.065, -0.14, 0.07), v(0.21, -0.25, 0.46), 0.011, CHROME, g);
    bar(v(0.18, -0.227, 0.38), v(0.215, -0.253, 0.47), 0.017, RUBBER, g);
  }
  if (support === 'tripod' || support === 'babyLegs') {
    const spread = 0.5 * Math.min(1, rig.height / 1.4 + 0.2), hubY = -0.25;
    for (let i = 0; i < 3; i++) {
      const a = (i * 2 * Math.PI) / 3 + Math.PI;
      const hip = v(Math.sin(a) * 0.07, hubY, 0.03 + Math.cos(a) * 0.07), foot = v(Math.sin(a) * spread, floor + 0.015, 0.03 + Math.cos(a) * spread);
      const knee = hip.clone().lerp(foot, 0.52);
      // Two-stage legs: twin upper tubes, single lower.
      const side = v(Math.cos(a), 0, -Math.sin(a)).multiplyScalar(0.022);
      bar(hip.clone().add(side), knee.clone().add(side), 0.011, BLACK, g); bar(hip.clone().sub(side), knee.clone().sub(side), 0.011, BLACK, g);
      mesh(rbox(0.07, 0.035, 0.035, 0.008), SATIN, g, knee).rotation.y = a;
      bar(knee, foot, 0.009, CHROME, g);
      mesh(new THREE.SphereGeometry(0.02, 10, 8), RUBBER, g, foot);
      if (support === 'tripod') bar(v(0, floor + (hubY - floor) * 0.3, 0.03), knee.clone().lerp(foot, 0.35), 0.005, SATIN, g); // mid spreader
    }
  } else if (support === 'highHat') {
    mesh(rbox(0.36, 0.03, 0.36, 0.008), WOOD_LEG, g, v(0, floor + 0.015, 0.03));
    bar(v(0, floor + 0.03, 0.03), v(0, -0.25, 0.03), 0.05, DARK, g);
  } else if (support === 'dolly') {
    mesh(rbox(0.62, 0.1, 0.95, 0.03), DARK, g, v(0, floor + 0.17, 0.25));
    mesh(rbox(0.56, 0.012, 0.9, 0.004), RUBBER, g, v(0, floor + 0.226, 0.25));
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) mesh(new THREE.CylinderGeometry(0.085, 0.085, 0.06, 24), RUBBER, g, v(sx * 0.33, floor + 0.085, 0.25 + sz * 0.36), new THREE.Euler(0, 0, Math.PI / 2));
    bar(v(0, floor + 0.22, 0.03), v(0, -0.25, 0.03), 0.05, STEEL, g, 0.04);
    bar(v(-0.2, floor + 0.22, 0.68), v(-0.2, floor + 0.95, 0.72), 0.012, CHROME, g); bar(v(0.2, floor + 0.22, 0.68), v(0.2, floor + 0.95, 0.72), 0.012, CHROME, g);
    bar(v(-0.2, floor + 0.95, 0.72), v(0.2, floor + 0.95, 0.72), 0.014, RUBBER, g); // push bar
  } else if (support === 'slider') {
    mesh(rbox(0.1, 0.03, 0.95, 0.008), STEEL, g, v(0, -0.105, 0));
    mesh(rbox(0.14, 0.03, 0.14, 0.008), SATIN, g, v(0, -0.09, 0.03));
    for (const z of [-0.42, 0.42]) {
      bar(v(0, -0.12, z), v(0, floor + 0.3, z), 0.014, CHROME, g);
      for (let i = 0; i < 3; i++) { const a = (i * 2 * Math.PI) / 3; bar(v(0, floor + 0.32, z), v(Math.sin(a) * 0.3, floor + 0.015, z + Math.cos(a) * 0.3), 0.01, STEEL, g); }
    }
  } else if (support === 'gimbal') {
    bar(v(0, -0.09, 0.05), v(0, -0.2, 0.05), 0.02, SATIN, g);
    bar(v(-0.17, -0.2, 0.05), v(0.17, -0.2, 0.05), 0.014, SATIN, g);
    for (const s of [-1, 1]) bar(v(s * 0.17, -0.2, 0.05), v(s * 0.17, -0.36, 0.05), 0.017, RUBBER, g);
  }
  return g;
}
const rad = (d: number) => (d * Math.PI) / 180;

// MARK: People

const CLOTH_TOP = 0x74787d, CLOTH_LEGS = 0x3c4046, HAIR = 0x221a15, SHOE = 0x1c1917, SOLE = 0x34312e, BELT = 0x201b17;

/** A limb that narrows from `r1` at `a` to `r2` at `b`, rounded at both ends. */
function taper(a: THREE.Vector3, b: THREE.Vector3, r1: number, r2: number, m: THREE.Material, parent: THREE.Object3D) {
  bar(a, b, r1, m, parent, r2);
  mesh(new THREE.SphereGeometry(r1, 16, 12), m, parent, a);
  mesh(new THREE.SphereGeometry(r2, 16, 12), m, parent, b);
}
/** A rounded shell turned round the Y axis from (radius, height) pairs, flattened front to back by `depth`. */
function shell(profile: [number, number][], depth: number, m: THREE.Material, parent: THREE.Object3D, shape?: (p: THREE.Vector3) => void) {
  const geo = new THREE.LatheGeometry(profile.map(([r, y]) => new THREE.Vector2(Math.max(r, 1e-4), y)), 48);
  if (shape) {
    const a = geo.attributes.position as THREE.BufferAttribute, p = new THREE.Vector3();
    for (let i = 0; i < a.count; i++) { p.fromBufferAttribute(a, i); shape(p); a.setXYZ(i, p.x, p.y, p.z); }
    geo.computeVertexNormals();
  }
  const o = mesh(geo, m, parent);
  o.scale.z = depth;
  return o;
}
function blob(r: number, m: THREE.Material, parent: THREE.Object3D, at: THREE.Vector3, sx = 1, sy = 1, sz = 1, seg = 18) {
  const o = mesh(new THREE.SphereGeometry(r, seg, Math.round(seg * 0.7)), m, parent, at);
  o.scale.set(sx, sy, sz);
  return o;
}

/** A hand hanging from the wrist along `dir`: palm, four fingers and a thumb. `s` is the side (±1); `roll` turns the palm. */
function hand(wrist: THREE.Vector3, dir: THREE.Vector3, h: number, s: number, roll: number, skin: THREE.Material, parent: THREE.Object3D) {
  const g = new THREE.Group();
  g.position.copy(wrist);
  g.quaternion.setFromUnitVectors(new THREE.Vector3(0, -1, 0), dir.clone().normalize());
  g.rotateY(roll);
  const palmL = h * 0.058, width = h * 0.044, thick = h * 0.019, fingerL = h * 0.046, fr = width / 8.6;
  mesh(rbox(thick, palmL, width, thick * 0.45, 3), skin, g, v(0, -palmL / 2, 0));
  [0.92, 1, 0.95, 0.78].forEach((len, i) => {
    const z = (-1.5 + i) * (width / 4) * 0.98;
    const base = v(-s * thick * 0.05, -palmL + fr * 0.6, z), l = fingerL * len;
    const mid = base.clone().add(v(-s * l * 0.12, -l * 0.55, 0));
    const tip = mid.clone().add(v(-s * l * 0.22, -l * 0.4, 0)); // a relaxed curl towards the palm
    limb(base, mid, fr, skin, g); limb(mid, tip, fr * 0.92, skin, g);
  });
  const t0 = v(-s * thick * 0.25, -palmL * 0.3, -width * 0.44);
  const t1 = t0.clone().add(v(-s * h * 0.012, -h * 0.022, -h * 0.01));
  const t2 = t1.clone().add(v(-s * h * 0.008, -h * 0.016, -h * 0.002));
  limb(t0, t1, fr * 1.25, skin, g); limb(t1, t2, fr * 1.1, skin, g);
  parent.add(g);
}

/** Hair over the skull (centre `c`, radius `r`, flattened like the skull). */
function hair(style: string, c: THREE.Vector3, r: number, headY: number, m: THREE.Material, parent: THREE.Object3D) {
  if (style === 'bald') return;
  const cap = (grow: number, cover: number, tilt: number) => {
    const o = mesh(new THREE.SphereGeometry(r * grow, 36, 22, 0, Math.PI * 2, 0, Math.PI * cover), m, parent, c);
    o.scale.set(0.79, 0.9, 0.91); o.rotation.x = tilt;
    return o;
  };
  if (style === 'cropped') { cap(1.025, 0.56, 0.52); return; }
  if (style === 'short') { cap(1.07, 0.6, 0.5).scale.y = 0.95; return; }
  if (style === 'tied') { cap(1.04, 0.6, 0.42); blob(r * 0.36, m, parent, v(0, headY + r * 0.3, r * 1.02)); return; }
  // Long: a full cap, a fall of hair down the back to the shoulders and curtains over the ears.
  cap(1.07, 0.6, 0.4);
  blob(r * 0.92, m, parent, v(0, headY - r * 0.62, r * 0.5), 0.9, 1.45, 0.52, 28);
  for (const s of [-1, 1]) blob(r * 0.85, m, parent, v(s * r * 0.7, headY - r * 0.72, r * 0.25), 0.26, 1.5, 0.85, 24).rotation.z = -s * 0.1;
}

/**
 * A stand-in person with the height, build, skin tone, hair and posture set in the planner. Faces −Z.
 * Neutral grey clothes so the light on the figure reads; a face (eyes, brow, nose, lips, ears) so you can see
 * where the light falls, and glossy eyes so catchlights show.
 */
export function person(c: PrevisCharacter): THREE.Group {
  const g = new THREE.Group();
  g.position.set(c.position.x, 0, c.position.z);
  g.rotation.y = -rad(c.facing);
  const h = c.height, sitting = c.posture === 'sitting';
  const child = isChild(c.type), fem = shapeBlend[c.type] ?? 0.5, bust = !child && fem > 0.75;
  const headH = h / (child ? 6 : 7.5), r = headH / 2;
  const hip0 = h * 0.52, seat = Math.min(0.45, hip0 * 0.5), drop = sitting ? hip0 - seat : 0;
  const hipY = hip0 - drop, shoulderY = h - headH * 1.42 - drop, headY = h - r - drop;
  const build = Math.min(Math.max(c.build, 0), 1);
  const sw = h * (0.1 + 0.035 * build + 0.008 * (1 - fem)), hw = h * (0.078 + 0.03 * build + 0.006 * fem);
  const depth = h * (0.105 + 0.05 * build);
  const tone = skinRGB[Math.min(Math.max(c.skinTone, 1), 6) - 1];
  const top = mat(CLOTH_TOP, { roughness: 0.92, metalness: 0, bumpMap: cached('fabric', fabricBump), bumpScale: 0.25 });
  const legsM = mat(CLOTH_LEGS, { roughness: 0.9, metalness: 0, bumpMap: cached('fabric', fabricBump), bumpScale: 0.25 });
  const skin = mat(tone, { roughness: 0.52, metalness: 0 });
  const lip = mat('#' + new THREE.Color(tone).lerp(new THREE.Color(0x8c3f3c), 0.28).multiplyScalar(0.88).getHexString(), { roughness: 0.4, metalness: 0 });
  const hairM = mat(HAIR, { roughness: 0.72, metalness: 0 });
  const eyeWhite = new THREE.MeshPhysicalMaterial({ color: 0xc4bdb2, roughness: 0.2, clearcoat: 1, clearcoatRoughness: 0.03 });
  const iris = new THREE.MeshPhysicalMaterial({ color: 0x2e2119, roughness: 0.15, clearcoat: 1, clearcoatRoughness: 0.02 });
  const shoeM = mat(SHOE, { roughness: 0.45, metalness: 0 }), soleM = mat(SOLE, { roughness: 0.9, metalness: 0 });

  // Torso: trousers to a belt, then a loose top with a crew neck.
  const torsoH = shoulderY - hipY;
  const waistY = hipY + torsoH * 0.36, chestY = shoulderY - torsoH * 0.3;
  const chestR = sw * 0.88, waistR = hw * (0.98 - 0.12 * fem) + h * 0.012 * build, neckR = r * (0.44 - 0.06 * fem);
  const k = depth / (2 * chestR);
  const beltY = hipY + h * 0.06, crotchY = hipY - h * 0.035;
  shell([[0, crotchY], [hw * 0.7, crotchY + h * 0.004], [hw * 0.97, hipY], [hw * 1.01, hipY + h * 0.035], [hw * 0.99, beltY + h * 0.012], [0, beltY + h * 0.012]], k * 1.08, legsM, g);
  const belt = mesh(new THREE.TorusGeometry(hw * 1.0, h * 0.007, 8, 40), mat(BELT, { roughness: 0.5, metalness: 0 }), g, v(0, beltY, 0), new THREE.Euler(Math.PI / 2, 0, 0));
  belt.scale.y = k * 1.1;
  mesh(rbox(h * 0.03, h * 0.022, h * 0.006, h * 0.002), CHROME, g, v(0, beltY, -hw * k * 1.1 - h * 0.004)); // buckle
  shell([
    [hw * 1.03, beltY + h * 0.016], [(hw + waistR) * 0.53, waistY - torsoH * 0.12], [waistR * 1.02, waistY], [chestR, chestY],
    [sw * 0.92, shoulderY - h * 0.045], [sw * 0.84, shoulderY - h * 0.01], [sw * 0.58, shoulderY + h * 0.012],
    [neckR * 1.55, shoulderY + h * 0.024], [neckR * 1.12, shoulderY + h * 0.03],
  ], k, top, g, bust ? p => {
    // A soft bust pushed out of the front of the top (in the shell's unflattened space).
    if (p.z >= 0) return;
    const dx = Math.abs(p.x) - chestR * 0.42, dy = p.y - (chestY - h * 0.02);
    const lift = h * 0.032 * Math.exp(-(dx * dx) / (chestR * chestR * 0.09) - (dy * dy) / (h * h * 0.0018));
    p.z -= (lift / k) * Math.min(1, -p.z / chestR);
  } : undefined);
  const collar = mesh(new THREE.TorusGeometry(neckR * 1.14, h * 0.0035, 8, 32), top, g, v(0, shoulderY + h * 0.028, 0), new THREE.Euler(Math.PI / 2 - 0.22, 0, 0));
  collar.scale.y = 0.9;

  // Neck and head. The skull sits a little back; the jaw, cheeks, nose, brow and lips build the face.
  bar(v(0, shoulderY + h * 0.012, h * 0.006), v(0, headY - r * 0.38, r * 0.16), neckR, skin, g, neckR * 0.94);
  const skullC = v(0, headY + r * 0.06, r * 0.1);
  blob(r, skin, g, skullC, 0.78, 0.9, 0.9, 32);
  blob(r * 0.55, skin, g, v(0, headY - r * 0.4, -r * 0.3), 1.12 - 0.12 * fem, 1, 1, 24);           // jaw and mouth
  blob(r * 0.24, skin, g, v(0, headY - r * 0.83, -r * 0.55), 1.15 - 0.15 * fem, 0.8, 0.9);         // chin
  for (const s of [-1, 1]) {
    blob(r * 0.25, skin, g, v(s * r * 0.77, headY - r * 0.1, r * 0.12), 0.34, 1, 0.62).rotation.y = s * 0.3; // ear
    const eye = v(s * r * 0.29, headY - r * 0.04, -r * 0.7);
    blob(r * 0.1, eyeWhite, g, eye);
    blob(r * 0.062, iris, g, eye.clone().add(v(0, 0, -r * 0.07)), 1, 1, 0.55, 14);
    const lid = mesh(new THREE.SphereGeometry(r * 0.106, 16, 8, 0, Math.PI * 2, 0, Math.PI * 0.3), skin, g, eye);
    lid.rotation.x = -0.3;
    limb(v(s * r * 0.13, headY + r * 0.155, -r * 0.83), v(s * r * 0.44, headY + r * 0.165, -r * 0.74), r * 0.022, hairM, g); // eyebrow
  }
  limb(v(-r * 0.4, headY + r * 0.09, -r * 0.76), v(r * 0.4, headY + r * 0.09, -r * 0.76), r * 0.06, skin, g); // brow ridge
  bar(v(0, headY + r * 0.02, -r * 0.82), v(0, headY - r * 0.3, -r * 0.96), r * 0.055, skin, g, r * 0.085);   // nose bridge
  blob(r * 0.1, skin, g, v(0, headY - r * 0.33, -r * 0.97), 1, 0.85, 0.9);                           // nose tip
  for (const s of [-1, 1]) blob(r * 0.068, skin, g, v(s * r * 0.09, headY - r * 0.37, -r * 0.89));
  blob(r * 0.16, lip, g, v(0, headY - r * 0.56, -r * 0.84), 1, 0.22, 0.34);
  blob(r * 0.14, lip, g, v(0, headY - r * 0.63, -r * 0.82), 1, 0.27, 0.34);
  hair(hairOf(c), skullC, r, headY, hairM, g);

  // Arms: sleeves to the wrist, a cuff, then the hand.
  const ar = h * (0.021 + 0.008 * build);
  for (const s of [-1, 1]) {
    const shoulder = v(s * (sw * 0.86 - ar * 0.2), shoulderY - ar * 0.95, 0);
    const elbow = sitting ? v(s * (sw + h * 0.02), shoulderY - h * 0.175, -h * 0.025) : v(s * (sw + h * 0.022), shoulderY - h * 0.185, h * 0.008);
    const wrist = sitting ? v(s * sw * 0.72, hipY + h * 0.085, -h * 0.17) : v(s * (sw + h * 0.03), shoulderY - h * 0.345, -h * 0.03);
    taper(shoulder, elbow, ar * 1.18, ar * 0.86, top, g);
    const fore = new THREE.Vector3().subVectors(wrist, elbow);
    const cuff = wrist.clone().addScaledVector(fore.clone().normalize(), -h * 0.012);
    taper(elbow, cuff, ar * 0.9, ar * 0.7, top, g);
    bar(cuff, wrist, ar * 0.5, skin, g, ar * 0.46);
    hand(wrist, fore, h, s, sitting ? s * Math.PI / 2 : 0, skin, g);
  }

  // Legs: trousers with a soft knee, then shoes with a sole.
  const tr = h * (0.044 + 0.016 * build), sr = h * (0.029 + 0.008 * build);
  for (const s of [-1, 1]) {
    const hip = v(s * hw * 0.5, hipY - h * 0.008, 0);
    const knee = sitting ? v(s * hw * 0.68, hipY + h * 0.005, -h * 0.245) : v(s * hw * 0.5, h * 0.285, -h * 0.008);
    const ankle = sitting ? v(s * hw * 0.68, h * 0.055, -h * 0.245 - Math.max(0, h * 0.24 - hipY) * 0.9) : v(s * hw * 0.48, h * 0.055, h * 0.006);
    taper(hip, knee, tr, sr * 1.08, legsM, g);
    taper(knee, ankle, sr * 1.05, sr * 0.82, legsM, g);
    const foot = v(ankle.x, 0, ankle.z);
    mesh(rbox(h * 0.05, h * 0.012, h * 0.152, h * 0.005), soleM, g, foot.clone().add(v(0, h * 0.006, -h * 0.038)));
    blob(h * 0.027, shoeM, g, foot.clone().add(v(0, h * 0.026, -h * 0.078)), 0.95, 0.62, 1.55);   // toe box
    blob(h * 0.029, shoeM, g, foot.clone().add(v(0, h * 0.03, h * 0.006)), 0.9, 0.95, 1.05);      // heel and collar
  }
  return mergeByMaterial(g);
}

/** Bakes a figure's many small parts into one mesh per material, so a person costs a handful of draw calls. */
function mergeByMaterial(g: THREE.Group): THREE.Group {
  const pos = g.position.clone(), rot = g.rotation.clone();
  g.position.set(0, 0, 0); g.rotation.set(0, 0, 0);
  g.updateMatrixWorld(true);
  const parts = new Map<THREE.Material, THREE.BufferGeometry[]>();
  g.traverse(o => {
    const m = o as THREE.Mesh;
    if (!m.isMesh) return;
    const geo = (m.geometry.index ? m.geometry.toNonIndexed() : m.geometry.clone()).applyMatrix4(m.matrixWorld);
    for (const k of Object.keys(geo.attributes)) if (k !== 'position' && k !== 'normal' && k !== 'uv') geo.deleteAttribute(k);
    const mat = m.material as THREE.Material;
    parts.set(mat, [...(parts.get(mat) ?? []), geo]);
    m.geometry.dispose();
  });
  const out = new THREE.Group();
  out.position.copy(pos); out.rotation.copy(rot);
  for (const [mat, geos] of parts) {
    const merged = mergeGeometries(geos);
    geos.forEach(x => x.dispose());
    if (merged) out.add(new THREE.Mesh(merged, mat));
  }
  return out;
}

// MARK: Light meter

/** An incident meter on a slim pole: white dome on a dark body, set at its reading height. */
export function meterModel(m: LightMeter): THREE.Group {
  const g = new THREE.Group();
  g.position.set(m.position.x, m.height, m.position.z);
  mesh(new THREE.SphereGeometry(0.03, 20, 12, 0, Math.PI * 2, 0, Math.PI / 2), mat(0xf4f4f0, { roughness: 0.35, metalness: 0, emissive: 0x555555 }), g, v(0, 0, 0));
  mesh(rbox(0.06, 0.12, 0.028, 0.012), SATIN, g, v(0, -0.062, 0));
  mesh(new THREE.PlaneGeometry(0.04, 0.035), GLASS_LENS, g, v(0, -0.045, 0.0145));
  bar(v(0, -0.12, 0), v(0, -m.height + 0.01, 0), 0.005, STEEL, g);
  mesh(new THREE.CylinderGeometry(0.07, 0.08, 0.012, 24), DARK, g, v(0, -m.height + 0.006, 0));
  return g;
}
