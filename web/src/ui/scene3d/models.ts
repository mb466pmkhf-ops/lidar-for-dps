// Equipment and people for the 3D view: generic lighting units, stands, a cinema camera, figures.
// Everything faces −Z in its own frame. Shapes are generic on purpose (no maker's designs).
import * as THREE from 'three';
import type { BarnDoors, CameraRig, LightFixture, LightMeter, PrevisCharacter } from '../../model/types';
import { fixtureProfile, type ResolvedPhotometrics } from '../../model/photometrics';
import { cameraSupport, type LightSupport } from '../../model/rigging';
import { skinRGB } from '../../model/characters';
import {
  ALONG, BLACK, CHROME, DARK, FABRIC_BLACK, GLASS_LENS, RUBBER, SAND, SATIN, SILVER_LINING, STEEL, WOOD_LEG,
  bar, cached, fresnelTexture, gridTexture, ledTexture, limb, mat, mesh, rbox, v,
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
  return on
    ? new THREE.MeshStandardMaterial({ color: 0x000000, emissive: color, emissiveIntensity: level, emissiveMap: map ?? null, roughness: 0.6, metalness: 0 })
    : new THREE.MeshStandardMaterial({ color: 0xcfcfcb, map: map ?? null, roughness: 0.75, metalness: 0 });
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
  const level = 2.2 + 1.6 * Math.min(1, Math.log10(1 + pm.flux / 800) / 2);
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
      const shade = new THREE.MeshStandardMaterial({ color: on ? 0x000000 : 0xd8d2c6, emissive: on ? color : 0x000000, emissiveIntensity: on ? level * 0.22 : 0, roughness: 0.9, side: THREE.DoubleSide });
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

/** A flag, bounce, neg or diffusion frame. */
/** Grip on its frame: two faces back to back, so each side can show what it does with the light
 *  (the far face of a diffusion glows with what it passes; see Scene3D). Face `+1` looks the way the
 *  board faces (the calculator's normal), `-1` the other way. Each face's albedo is the board's
 *  reflectance, so a flag or neg shows a faint sheen on the side the light hits. */
export function board(l: LightFixture, parent: THREE.Object3D, reflectance: number): number {
  const h = (l.boardHeight as number | undefined) ?? (l.kind === 'flag' ? Math.min(l.width, 0.9) : l.width);
  const w = l.width;
  const albedo = new THREE.Color().setRGB(reflectance, reflectance, reflectance, THREE.LinearSRGBColorSpace);
  for (const side of [1, -1]) {
    const face = mat(0xffffff, { roughness: l.kind === 'bounce' || l.kind === 'diffusion' ? 0.92 : 1, metalness: 0, side: THREE.FrontSide });
    face.color.copy(albedo);
    // The board's normal is the way a unit would point: local −Z. The plane faces +Z, so turn the front face round.
    const m = mesh(new THREE.PlaneGeometry(w - 0.02, h - 0.02), face, parent, v(0, 0, side * -0.002), side > 0 ? new THREE.Euler(0, Math.PI, 0) : undefined);
    m.userData.face = side;
  }
  // A slim metal frame round the cloth.
  for (const s of [-1, 1]) {
    bar(v(-w / 2, (s * h) / 2, 0), v(w / 2, (s * h) / 2, 0), 0.008, l.kind === 'flag' ? SATIN : STEEL, parent);
    bar(v((s * w) / 2, -h / 2, 0), v((s * w) / 2, h / 2, 0), 0.008, l.kind === 'flag' ? SATIN : STEEL, parent);
  }
  return h;
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

const CLOTH_TOP = 0x74787d, CLOTH_LEGS = 0x3c4046, HAIR = 0x191614;

/** A mannequin with the height, build, skin tone and posture set in the planner. Faces −Z. */
export function person(c: PrevisCharacter): THREE.Group {
  const g = new THREE.Group();
  g.position.set(c.position.x, 0, c.position.z);
  g.rotation.y = -rad(c.facing);
  const h = c.height, sitting = c.posture === 'sitting';
  const child = c.type === 'girl' || c.type === 'boy', female = c.type === 'woman' || c.type === 'girl';
  const headH = h / (child ? 6 : 7.5);
  const hip0 = h * 0.52, seat = Math.min(0.45, hip0 * 0.5), drop = sitting ? hip0 - seat : 0;
  const hipY = hip0 - drop, shoulderY = h - headH * 1.42 - drop, headY = h - headH / 2 - drop;
  const build = Math.min(Math.max(c.build, 0), 1);
  const sw = h * (0.1 + 0.035 * build + (female ? 0 : 0.008)), hw = h * (0.078 + 0.03 * build + (female ? 0.006 : 0));
  const depth = h * (0.105 + 0.05 * build);
  const top = mat(CLOTH_TOP, { roughness: 0.9, metalness: 0 }), legsM = mat(CLOTH_LEGS, { roughness: 0.9, metalness: 0 });
  const skin = mat(skinRGB[Math.min(Math.max(c.skinTone, 1), 6) - 1], { roughness: 0.5, metalness: 0 });
  const shoe = mat(0x191919, { roughness: 0.7, metalness: 0 });

  // Torso: chest and pelvis.
  const torsoH = shoulderY - hipY;
  mesh(rbox(sw * 2, torsoH * 0.68, depth, depth * 0.42, 5), top, g, v(0, shoulderY - torsoH * 0.3, 0));
  mesh(rbox(hw * 2.05, torsoH * 0.5, depth * 0.95, depth * 0.4, 5), top, g, v(0, hipY + torsoH * 0.22, 0));
  mesh(rbox(hw * 2.1, h * 0.09, depth * 0.98, depth * 0.4, 5), legsM, g, v(0, hipY + h * 0.012, 0));
  // Neck and head.
  bar(v(0, shoulderY, 0), v(0, headY - headH * 0.3, -0.005), headH * 0.2, skin, g);
  const r = headH / 2;
  const skull = mesh(new THREE.SphereGeometry(r, 28, 20), skin, g, v(0, headY, 0));
  skull.scale.set(0.8, 1, 0.9);
  mesh(new THREE.SphereGeometry(r * 0.12, 10, 8), skin, g, v(0, headY - r * 0.12, -r * 0.9)); // nose
  const hair = mat(HAIR, { roughness: 0.85, metalness: 0 });
  const cap = mesh(new THREE.SphereGeometry(r * 1.05, 28, 16, 0, Math.PI * 2, 0, Math.PI * 0.46), hair, g, v(0, headY + r * 0.02, r * 0.04));
  cap.scale.set(0.83, 1, 0.93); cap.rotation.x = 0.62;
  if (female) mesh(new THREE.SphereGeometry(r * 0.8, 20, 14), hair, g, v(0, headY - r * 0.35, r * 0.42)).scale.set(0.95, 1.25, 0.6);

  // Arms.
  const ar = h * (0.021 + 0.008 * build);
  for (const s of [-1, 1]) {
    const shoulder = v(s * (sw - ar * 0.2), shoulderY - ar, 0);
    const elbow = sitting ? v(s * (sw + h * 0.02), shoulderY - h * 0.175, -h * 0.025) : v(s * (sw + h * 0.022), shoulderY - h * 0.185, h * 0.008);
    const wrist = sitting ? v(s * sw * 0.72, hipY + h * 0.075, -h * 0.17) : v(s * (sw + h * 0.03), shoulderY - h * 0.345, -h * 0.03);
    limb(shoulder, elbow, ar, top, g);
    limb(elbow, wrist, ar * 0.82, top, g);
    mesh(new THREE.SphereGeometry(h * 0.025, 14, 10), skin, g, wrist.clone().add(v(0, sitting ? 0 : -h * 0.025, sitting ? -h * 0.02 : 0))).scale.set(0.8, 1.15, 1);
  }
  // Legs.
  const tr = h * (0.042 + 0.016 * build), sr = h * (0.03 + 0.008 * build);
  for (const s of [-1, 1]) {
    const hip = v(s * hw * 0.55, hipY, 0);
    const knee = sitting ? v(s * hw * 0.7, hipY + h * 0.005, -h * 0.245) : v(s * hw * 0.55, h * 0.285, -h * 0.008);
    const ankle = sitting ? v(s * hw * 0.7, h * 0.05, -h * 0.245 - Math.max(0, h * 0.24 - hipY) * 0.9) : v(s * hw * 0.55, h * 0.05, h * 0.008);
    limb(hip, knee, tr, legsM, g);
    limb(knee, ankle, sr, legsM, g);
    mesh(rbox(h * 0.055, h * 0.04, h * 0.145, h * 0.016), shoe, g, v(ankle.x, h * 0.02, ankle.z - h * 0.04));
  }
  return g;
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
