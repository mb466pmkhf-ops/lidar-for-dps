// 3D view of the lighting plan, built from the synced data (the 2D floor plan, lights, people,
// cameras, meters). Like the phone's 3D view: units on their stands, beams that stop where they
// meet the room, walls between you and the room cut away. Looks only; lux comes from the calculator.
import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import type { CameraRig, FloorPlan, LightFixture, Location } from '../model/types';
import { KIND_INFO, fixtureProfile, photometrics } from '../model/photometrics';
import { cameraSupport, lightSupport, type CameraSupport, type LightSupport } from '../model/rigging';
import { skinRGB } from '../model/characters';
import type { Selection } from './PlanCanvas';
import { Icon } from './icons';

interface Props {
  location: Location;
  plan?: FloorPlan;
  scanID?: string;
  lights: LightFixture[];
  selection?: Selection;
  /** Draw every unit's beam, not just the selected one's (the plan's Beams layer). */
  beams?: boolean;
  onSelect(s?: Selection): void;
}

const rad = (d: number) => (d * Math.PI) / 180;
const mat = (color: number | string, opts: THREE.MeshStandardMaterialParameters = {}) =>
  new THREE.MeshStandardMaterial({ color, roughness: 0.6, metalness: 0.1, ...opts });
const STEEL = mat(0x9a9a9a, { metalness: 0.8, roughness: 0.35 });
const BLACK = mat(0x161616, { metalness: 0.6, roughness: 0.45 });
const DARK = mat(0x2c2c2c, { metalness: 0.6, roughness: 0.4 });
const SAND = mat(0x6b5c3d, { roughness: 0.95 });

/** A round bar between two points. */
function bar(a: THREE.Vector3, b: THREE.Vector3, r: number, m: THREE.Material, parent: THREE.Object3D) {
  const d = new THREE.Vector3().subVectors(b, a);
  const len = d.length();
  const mesh = new THREE.Mesh(new THREE.CylinderGeometry(r, r, Math.max(len, 0.001), 10), m);
  mesh.position.copy(a).addScaledVector(d, 0.5);
  if (len > 1e-6) mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.normalize());
  parent.add(mesh);
  return mesh;
}
const v = (x: number, y: number, z: number) => new THREE.Vector3(x, y, z);

/** Stand from the floor (y = -height) up to `top`, in the unit's pan space (−Z is where it faces). */
function stand(support: LightSupport, height: number, top: number, parent: THREE.Object3D) {
  const floor = -height;
  const legs = (o: THREE.Vector3, hub: number, spread: number, r: number, sandbag: boolean) => {
    for (let i = 0; i < 3; i++) {
      const a = (i * 2 * Math.PI) / 3 + Math.PI / 3;
      const foot = v(o.x + Math.sin(a) * spread, floor + 0.02, o.z + Math.cos(a) * spread);
      bar(v(o.x, hub - i * 0.04, o.z), foot, r, STEEL, parent);
      if (sandbag && i === 2) {
        const bag = new THREE.Mesh(new THREE.CapsuleGeometry(0.07, 0.3, 4, 8), SAND);
        bag.position.set((o.x + foot.x) / 2, (hub + foot.y) / 2 + 0.03, (o.z + foot.z) / 2);
        bag.rotation.set(0, a, Math.PI / 2 - 0.55);
        parent.add(bag);
      }
    }
  };
  switch (support) {
    case 'cStand': legs(v(0, 0, 0), floor + 0.32, 0.42, 0.012, true); bar(v(0, floor + 0.3, 0), v(0, top, 0), 0.015, STEEL, parent); break;
    case 'comboStand': case 'rollerStand': legs(v(0, 0, 0), floor + 0.55, 0.58, 0.016, false); bar(v(0, floor + 0.2, 0), v(0, top, 0), 0.022, STEEL, parent); break;
    case 'turtleBase': legs(v(0, 0, 0), floor + 0.07, 0.36, 0.012, false); bar(v(0, floor + 0.04, 0), v(0, top, 0), 0.016, STEEL, parent); break;
    case 'megaBoom': {
      const reach = 2.2, armY = top + 0.12;
      legs(v(0, 0, reach), floor + 0.55, 0.6, 0.016, false);
      bar(v(0, floor + 0.2, reach), v(0, armY, reach), 0.024, STEEL, parent);
      bar(v(0, armY, -0.05), v(0, armY, reach + 0.9), 0.02, STEEL, parent);
      const w = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.2, 0.16), DARK);
      w.position.set(0, armY - 0.06, reach + 0.95);
      parent.add(w);
      bar(v(0, armY, 0), v(0, top, 0), 0.01, STEEL, parent);
      break;
    }
    case 'overhead': bar(v(0, top, 0), v(0, top + 0.45, 0), 0.01, STEEL, parent); bar(v(-0.8, top + 0.48, 0), v(0.8, top + 0.48, 0), 0.024, STEEL, parent); break;
    case 'floor': bar(v(0, floor + 0.01, 0), v(0, top, 0), 0.01, STEEL, parent); break;
    case 'none': break;
  }
}

/** Head facing −Z with a glowing face, sized by fixture category. Returns half-width and depth below the axis. */
function head(l: LightFixture, color: THREE.Color, on: boolean, parent: THREE.Object3D): { half: number; below: number } {
  const p = fixtureProfile(l);
  const glow = new THREE.MeshBasicMaterial({ color: on ? color : 0x555555 });
  const add = (g: THREE.BufferGeometry, m: THREE.Material, pos: THREE.Vector3, rot?: THREE.Euler) => {
    const mesh = new THREE.Mesh(g, m); mesh.position.copy(pos); if (rot) mesh.rotation.copy(rot); parent.add(mesh); return mesh;
  };
  const along = new THREE.Euler(Math.PI / 2, 0, 0);
  switch (p.category) {
    case 'panel': case 'soft': {
      const w = p.emitterWidth, h = p.emitterHeight;
      add(new THREE.BoxGeometry(w + 0.04, h + 0.04, 0.05), BLACK, v(0, 0, 0.02));
      add(new THREE.PlaneGeometry(w, h), glow, v(0, 0, -0.006), new THREE.Euler(0, Math.PI, 0));
      return { half: w / 2 + 0.03, below: h / 2 + 0.03 };
    }
    case 'tube':
      add(new THREE.CylinderGeometry(0.022, 0.022, p.emitterWidth, 12), glow, v(0, 0, 0), new THREE.Euler(0, 0, Math.PI / 2));
      return { half: 0.05, below: 0.04 };
    case 'spaceLight':
      add(new THREE.CylinderGeometry(0.32, 0.32, 0.55, 24), glow, v(0, 0, 0));
      return { half: 0.35, below: 0.3 };
    case 'practical': {
      add(new THREE.SphereGeometry(0.04, 12, 8), glow, v(0, 0, 0));
      const shade = new THREE.MeshStandardMaterial({ color: on ? color : 0xbbbbbb, emissive: on ? color : 0x000000, emissiveIntensity: 0.5, side: THREE.DoubleSide });
      add(new THREE.CylinderGeometry(0.11, 0.17, 0.2, 24, 1, true), shade, v(0, 0.03, 0));
      return { half: 0.1, below: 0.1 };
    }
    case 'hmi': case 'fresnel': case 'tungsten': {
      const r = p.category === 'hmi' ? 0.17 : 0.13;
      add(new THREE.CylinderGeometry(r, r, 0.32, 24), BLACK, v(0, 0, 0.1), along);
      add(new THREE.CylinderGeometry(r * 0.78, r * 0.78, 0.01, 24), glow, v(0, 0, -0.065), along);
      return { half: r + 0.02, below: r + 0.02 };
    }
    default: {
      // COB: body, mount, and its reflector or softbox.
      add(new THREE.BoxGeometry(0.2, 0.22, 0.26), BLACK, v(0, 0, 0.1));
      const mod = l.modifierID ?? p.defaultModifierID ?? '';
      if (mod.startsWith('softbox')) {
        const size = mod.includes('150') ? 1.5 : 0.9;
        const cone = new THREE.Mesh(new THREE.CylinderGeometry(size / 2, 0.08, size * 0.55, 8, 1, true), mat(0x121212, { side: THREE.DoubleSide }));
        cone.rotation.x = -Math.PI / 2; cone.position.set(0, 0, -0.06 - size * 0.275); parent.add(cone);
        add(new THREE.CylinderGeometry(size / 2, size / 2, 0.004, 8), glow, v(0, 0, -0.06 - size * 0.55), along);
      } else if (mod.startsWith('lantern')) {
        add(new THREE.SphereGeometry(0.32, 20, 14), glow, v(0, 0, -0.4));
      } else {
        const dish = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.065, 0.14, 24, 1, true), mat(0xbbbbbb, { metalness: 0.9, roughness: 0.2, side: THREE.DoubleSide }));
        dish.rotation.x = -Math.PI / 2; dish.position.set(0, 0, -0.13); parent.add(dish);
        add(new THREE.CylinderGeometry(0.05, 0.05, 0.01, 16), glow, v(0, 0, -0.07), along);
      }
      return { half: 0.12, below: 0.13 };
    }
  }
}

/** Yoke round the head (pan space). Returns the stud's height. */
function yoke(half: number, below: number, hanging: boolean, parent: THREE.Object3D): number {
  const x = half + 0.025, y = (below + 0.03) * (hanging ? 1 : -1);
  for (const s of [-1, 1]) bar(v(s * x, 0, 0), v(s * x, y, 0), 0.008, BLACK, parent);
  bar(v(-x, y, 0), v(x, y, 0), 0.008, BLACK, parent);
  const stud = y + (hanging ? 0.07 : -0.07);
  bar(v(0, y, 0), v(0, stud, 0), 0.008, STEEL, parent);
  return stud;
}

function cameraModel(rig: CameraRig, selected: boolean): THREE.Group {
  const g = new THREE.Group();
  g.position.set(rig.position.x, rig.height, rig.position.z);
  g.rotation.y = -rad(rig.pan);
  const tilt = new THREE.Group();
  tilt.rotation.x = rad(rig.tilt);
  g.add(tilt);
  const body = mat(selected ? 0x8fa6bd : 0x222222, { metalness: 0.5 });
  const box = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.14, 0.2), body); box.position.z = 0.06; tilt.add(box);
  const lensLen = Math.min(0.3, 0.07 + rig.focalLength / 520);
  const lens = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.045, lensLen, 20), BLACK);
  lens.rotation.x = Math.PI / 2; lens.position.z = -0.04 - lensLen / 2; tilt.add(lens);
  const mb = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.11, 0.1), mat(0x111111, { side: THREE.DoubleSide, wireframe: true }));
  mb.position.z = -0.1 - lensLen; tilt.add(mb);
  const support: CameraSupport = cameraSupport(rig);
  const floor = -rig.height;
  if (support === 'tripod' || support === 'babyLegs' || support === 'highHat' || support === 'dolly') {
    const fluid = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.1, 0.16), DARK); fluid.position.set(0, -0.14, 0.02); g.add(fluid);
    bar(v(0.06, -0.12, 0.08), v(0.2, -0.22, 0.48), 0.011, STEEL, g);
  }
  if (support === 'tripod' || support === 'babyLegs') {
    const spread = 0.5 * Math.min(1, rig.height / 1.4 + 0.2);
    for (let i = 0; i < 3; i++) {
      const a = (i * 2 * Math.PI) / 3 + Math.PI;
      bar(v(Math.sin(a) * 0.07, -0.25, Math.cos(a) * 0.07), v(Math.sin(a) * spread, floor, Math.cos(a) * spread), 0.011, mat(0x6e5236), g);
    }
  } else if (support === 'highHat') {
    bar(v(0, floor + 0.02, 0), v(0, -0.25, 0.02), 0.04, DARK, g);
  } else if (support === 'dolly') {
    const chassis = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.16, 0.8), DARK); chassis.position.set(0, floor + 0.17, 0.25); g.add(chassis);
    bar(v(0, floor + 0.25, 0), v(0, -0.25, 0.02), 0.045, STEEL, g);
  } else if (support === 'slider') {
    const rail = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.03, 0.9), STEEL); rail.position.set(0, -0.18, 0); g.add(rail);
    for (const z of [-0.4, 0.4]) bar(v(0, -0.18, z), v(0, floor, z), 0.012, STEEL, g);
  }
  return g;
}

/** Beam rays from the unit's front, each stopped at the first surface; rays that meet nothing aren't drawn. */
function beam(l: LightFixture, origin: THREE.Vector3, q: THREE.Quaternion, color: THREE.Color, hitTargets: THREE.Object3D[]): THREE.Mesh | undefined {
  const pm = photometrics(l);
  if (pm.distribution !== 'beam' && pm.distribution !== 'lambertian') return undefined;
  const half = Math.min(pm.distribution === 'beam' ? pm.beamAngle * 0.68 : 60, 75);
  const th = Math.tan(rad(half));
  const doors = l.barnDoors;
  const lim = (d: number) => Math.tan(rad(Math.min(half, doors ? d : 90)));
  const L = lim(doors?.left ?? 90), R = lim(doors?.right ?? 90), U = lim(doors?.top ?? 90), D = lim(doors?.bottom ?? 90);
  const ray = new THREE.Raycaster();
  ray.far = 12;
  const N = 28;
  const ends: (THREE.Vector3 | undefined)[] = [];
  for (let k = 0; k <= N; k++) {
    const a = (k / N) * 2 * Math.PI;
    const local = k === N ? v(0, 0, -1) : v(Math.min(Math.max(Math.cos(a) * th, -L), R), Math.min(Math.max(Math.sin(a) * th, -D), U), -1).normalize();
    const dir = local.clone().applyQuaternion(q);
    ray.set(origin, dir);
    const hit = ray.intersectObjects(hitTargets, true).find(h => h.distance > 0.05);
    ends.push(hit ? local.multiplyScalar(hit.distance) : undefined);
  }
  const pos: number[] = [0, 0, 0], col: number[] = [color.r * 0.16, color.g * 0.16, color.b * 0.16];
  const idx: (number | undefined)[] = ends.map(e => {
    if (!e) return undefined;
    const f = 0.09 / (1 + e.length() * 0.35);
    pos.push(e.x, e.y, e.z); col.push(color.r * f, color.g * f, color.b * f);
    return pos.length / 3 - 1;
  });
  const centre = idx[N];
  const tris: number[] = [];
  for (let k = 0; k < N; k++) {
    const i0 = idx[k], i1 = idx[(k + 1) % N];
    if (i0 === undefined || i1 === undefined) continue;
    tris.push(0, i0, i1);
    if (centre !== undefined) tris.push(centre, i1, i0);
  }
  if (!tris.length) return undefined;
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  geo.setIndex(tris);
  return new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ vertexColors: true, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
}

export function Scene3D(p: Props) {
  const host = useRef<HTMLDivElement>(null);
  const api = useRef<{ renderer: THREE.WebGLRenderer; scene: THREE.Scene; camera: THREE.PerspectiveCamera; controls: OrbitControls; room: THREE.Group; items: THREE.Group; walls: { mesh: THREE.Mesh; mid: THREE.Vector3 }[]; centre: THREE.Vector3; span: number }>(undefined);
  const onSelect = useRef(p.onSelect);
  onSelect.current = p.onSelect;

  // Renderer, camera, controls: once.
  useEffect(() => {
    const el = host.current!;
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor(0x0b0b0b);
    el.appendChild(renderer.domElement);
    const scene = new THREE.Scene();
    scene.add(new THREE.HemisphereLight(0xffffff, 0x222222, 0.35));
    const camera = new THREE.PerspectiveCamera(50, 1, 0.03, 200);
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.maxPolarAngle = rad(88);
    controls.minDistance = 0.6;
    controls.maxDistance = 40;
    controls.screenSpacePanning = false;
    const grid = new THREE.GridHelper(24, 24, 0x333333, 0x1c1c1c);
    scene.add(grid);
    const room = new THREE.Group(), items = new THREE.Group();
    scene.add(room, items);
    api.current = { renderer, scene, camera, controls, room, items, walls: [], centre: v(0, 1, 0), span: 6 };

    const resize = () => {
      const w = el.clientWidth, h = el.clientHeight;
      renderer.setSize(w, h, false);
      renderer.domElement.style.width = '100%'; renderer.domElement.style.height = '100%';
      camera.aspect = w / Math.max(h, 1); camera.updateProjectionMatrix();
    };
    const ro = new ResizeObserver(resize); ro.observe(el); resize();

    let frame = 0;
    const tick = () => {
      frame = requestAnimationFrame(tick);
      controls.update();
      const a = api.current!;
      // Cut away the walls between the camera and the room.
      for (const w of a.walls) {
        const out = v(w.mid.x - a.centre.x, 0, w.mid.z - a.centre.z);
        const toCam = v(camera.position.x - w.mid.x, 0, camera.position.z - w.mid.z);
        const outside = Math.hypot(camera.position.x - a.centre.x, camera.position.z - a.centre.z) > out.length();
        const cut = out.dot(toCam) > 0 && outside;
        (w.mesh.material as THREE.MeshStandardMaterial).opacity = cut ? 0.08 : 1;
        (w.mesh.material as THREE.MeshStandardMaterial).depthWrite = !cut;
      }
      renderer.render(scene, camera);
    };
    tick();

    // Click (not drag) selects.
    let down: { x: number; y: number } | undefined;
    const pd = (e: PointerEvent) => { down = { x: e.clientX, y: e.clientY }; };
    const pu = (e: PointerEvent) => {
      if (!down || Math.hypot(e.clientX - down.x, e.clientY - down.y) > 4) return;
      const r = renderer.domElement.getBoundingClientRect();
      const ray = new THREE.Raycaster();
      ray.setFromCamera(new THREE.Vector2(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1), camera);
      for (const h of ray.intersectObjects(items.children, true)) {
        let o: THREE.Object3D | null = h.object;
        while (o && !o.userData.sel) o = o.parent;
        if (o) { onSelect.current(o.userData.sel); return; }
      }
      onSelect.current(undefined);
    };
    renderer.domElement.addEventListener('pointerdown', pd);
    renderer.domElement.addEventListener('pointerup', pu);
    return () => {
      cancelAnimationFrame(frame); ro.disconnect(); controls.dispose(); renderer.dispose();
      renderer.domElement.remove();
    };
  }, []);

  // The room, from the floor plan.
  useEffect(() => {
    const a = api.current!;
    a.room.clear(); a.walls = [];
    const plan = p.plan;
    const b = plan?.bounds ?? { minX: -3, minZ: -3, maxX: 3, maxZ: 3 };
    a.centre = v((b.minX + b.maxX) / 2, 1, (b.minZ + b.maxZ) / 2);
    a.span = Math.max(b.maxX - b.minX, b.maxZ - b.minZ, 3);
    const floorMat = mat(0x3a3530, { roughness: 0.9 });
    const polys = plan?.floorPolygons.length ? plan.floorPolygons : [[{ x: b.minX, z: b.minZ }, { x: b.maxX, z: b.minZ }, { x: b.maxX, z: b.maxZ }, { x: b.minX, z: b.maxZ }]];
    for (const poly of polys) {
      if (poly.length < 3) continue;
      const shape = new THREE.Shape(poly.map(q => new THREE.Vector2(q.x, -q.z)));
      const m = new THREE.Mesh(new THREE.ShapeGeometry(shape), floorMat);
      m.rotation.x = -Math.PI / 2; m.userData.surface = true;
      a.room.add(m);
    }
    const seg = (s: FloorPlan['walls'][number], m: THREE.Material, thick: number) => {
      const len = Math.hypot(s.b.x - s.a.x, s.b.z - s.a.z);
      const h = Math.max(s.height, 0.05);
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(len, h, thick), m);
      mesh.position.set((s.a.x + s.b.x) / 2, s.bottom + h / 2, (s.a.z + s.b.z) / 2);
      mesh.rotation.y = -Math.atan2(s.b.z - s.a.z, s.b.x - s.a.x);
      mesh.userData.surface = true;
      a.room.add(mesh);
      return mesh;
    };
    for (const w of plan?.walls ?? []) {
      const mesh = seg(w, mat(0xb9b4ac, { roughness: 0.85, transparent: true }), 0.1);
      a.walls.push({ mesh, mid: v((w.a.x + w.b.x) / 2, 0, (w.a.z + w.b.z) / 2) });
    }
    for (const w of plan?.windows ?? []) seg(w, mat(0x8fb4d6, { transparent: true, opacity: 0.35 }), 0.12);
    for (const w of plan?.doors ?? []) if (!w.isOpen) seg(w, mat(0x6b5a48), 0.12);
    for (const o of plan?.objects ?? []) {
      const m = new THREE.Mesh(new THREE.BoxGeometry(o.width, o.height, o.depth), mat(0x6a6a6a, { roughness: 0.8 }));
      m.position.set(o.center.x, o.height / 2, o.center.z);
      m.rotation.y = -o.rotation;
      m.userData.surface = true;
      a.room.add(m);
    }
    resetView();
  }, [p.plan]); // eslint-disable-line react-hooks/exhaustive-deps

  // Everything placed on the plan; rebuilt on every change (cheap at this size).
  useEffect(() => {
    const a = api.current!;
    a.items.traverse(o => { if ((o as THREE.Mesh).geometry) (o as THREE.Mesh).geometry.dispose(); });
    a.items.clear();
    const { location: loc, scanID, selection } = p;
    const inScan = (id?: string) => !id || !scanID || id.toUpperCase() === scanID.toUpperCase();
    const isSel = (kind: string, id: string) => selection?.kind === kind && selection.id === id;
    const hidden = new Set(loc.display?.hiddenGroups ?? []);
    a.room.updateMatrixWorld(true);
    const surfaces = a.room.children;
    let shadows = 0;

    for (const l of p.lights) {
      const info = KIND_INFO[l.kind];
      if (info.emits ? hidden.has('lights') : hidden.has('grip')) continue;
      const pan = new THREE.Group();
      pan.position.set(l.position.x, l.height, l.position.z);
      pan.rotation.y = -rad(l.pan);
      pan.userData.sel = { kind: 'light', id: l.id } satisfies Selection;
      const tilt = new THREE.Group();
      tilt.rotation.x = rad(l.tilt);
      pan.add(tilt);
      const support = lightSupport(l);
      if (info.emits) {
        const pm = photometrics(l);
        const color = new THREE.Color(pm.color.r, pm.color.g, pm.color.b);
        const size = head(l, color, l.isOn, tilt);
        // Lift the selected head a little. Materials are shared between units, so give it its own copies.
        if (isSel('light', l.id)) tilt.traverse(c => {
          const mesh = c as THREE.Mesh, m = mesh.material as THREE.MeshStandardMaterial | undefined;
          if (!mesh.isMesh || !m || !(m instanceof THREE.MeshStandardMaterial) || m === BLACK) return;
          mesh.material = m.clone(); (mesh.material as THREE.MeshStandardMaterial).emissive.set(0x333333);
        });
        if (fixtureProfile(l).category === 'practical') {
          bar(v(0, -0.05, 0), v(0, -l.height + 0.02, 0), 0.008, DARK, pan);
        } else if (support !== 'none') {
          const stud = yoke(size.half, size.below, support === 'overhead' || support === 'megaBoom', pan);
          stand(support, l.height, stud, pan);
        }
        if (l.isOn && pm.peakIntensity > 0) {
          const spot = pm.distribution === 'omni' || pm.distribution === 'tube' ? new THREE.PointLight(color, 1, 14, 2) : new THREE.SpotLight(color, 1, 14, rad(Math.min(pm.distribution === 'beam' ? pm.beamAngle * 0.68 : 80, 85)), 0.5, 2);
          spot.intensity = 3 + 12 * Math.log10(1 + pm.flux / 500);
          spot.position.set(0, 0, -0.14);
          if (spot instanceof THREE.SpotLight) {
            spot.target.position.set(0, 0, -2);
            tilt.add(spot.target);
            if (shadows < 3) { spot.castShadow = true; shadows++; }
          }
          tilt.add(spot);
          pan.updateMatrixWorld(true);
          const origin = new THREE.Vector3(0, 0, -0.1).applyMatrix4(tilt.matrixWorld);
          const q = new THREE.Quaternion(); tilt.getWorldQuaternion(q);
          // Like the plan: only the selected unit's beam unless the Beams layer is on. The lit room shows the rest.
          const b = p.beams || isSel('light', l.id) ? beam(l, origin, q, color, surfaces) : undefined;
          if (b) { b.position.set(0, 0, -0.1); tilt.add(b); }
        }
      } else {
        const h = l.boardHeight ?? (l.kind === 'flag' ? Math.min(l.width, 0.9) : l.width);
        const face = l.kind === 'bounce' ? 0xffffff : l.kind === 'negative' ? 0x0a0a0a : l.kind === 'diffusion' ? 0xeeeeee : 0x3a3a3a;
        tilt.add(new THREE.Mesh(new THREE.PlaneGeometry(l.width, h), mat(face, { side: THREE.DoubleSide, transparent: l.kind === 'diffusion', opacity: l.kind === 'diffusion' ? 0.55 : 1, emissive: isSel('light', l.id) ? 0x333333 : 0x000000 })));
        if (support !== 'none') { bar(v(0, -h / 2, 0), v(0, -h / 2 - 0.05, 0), 0.008, STEEL, pan); stand(support, l.height, -h / 2 - 0.05, pan); }
      }
      a.items.add(pan);
    }

    if (!hidden.has('people')) for (const c of loc.characters ?? []) {
      if (!inScan(c.scanID)) continue;
      const g = new THREE.Group();
      g.position.set(c.position.x, 0, c.position.z);
      g.rotation.y = -rad(c.facing);
      g.userData.sel = { kind: 'character', id: c.id } satisfies Selection;
      const sitting = c.posture === 'sitting';
      const h = c.height * (sitting ? 0.72 : 1);
      const cloth = mat(isSel('character', c.id) ? 0x9a9a9a : 0x707070, { roughness: 0.9 });
      const skin = mat(skinRGB[Math.min(Math.max(c.skinTone, 1), 6) - 1], { roughness: 0.55 });
      const w = 0.2 * c.build + 0.18;
      const body = new THREE.Mesh(new THREE.CapsuleGeometry(w / 2, h * 0.62, 4, 12), cloth);
      body.position.y = h * 0.43; body.scale.z = 0.6; g.add(body);
      const headM = new THREE.Mesh(new THREE.SphereGeometry(c.height * 0.065, 16, 12), skin);
      headM.position.y = h - c.height * 0.07; g.add(headM);
      const nose = new THREE.Mesh(new THREE.ConeGeometry(0.02, 0.05, 8), skin);
      nose.rotation.x = -Math.PI / 2; nose.position.set(0, h - c.height * 0.075, -c.height * 0.065); g.add(nose);
      a.items.add(g);
    }

    if (!hidden.has('cameras')) {
      for (const cam of loc.cameraPositions) if (inScan(cam.scanID)) { const g = cameraModel(cam.rig, isSel('camera', cam.id)); g.userData.sel = { kind: 'camera', id: cam.id } satisfies Selection; a.items.add(g); }
      for (const s of loc.shots) if (inScan(s.scanID)) { const g = cameraModel(s.rig, isSel('shot', s.id)); g.userData.sel = { kind: 'shot', id: s.id } satisfies Selection; a.items.add(g); }
    }
    if (!hidden.has('meters')) for (const m of loc.meters ?? []) {
      if (!inScan(m.scanID)) continue;
      const dome = new THREE.Mesh(new THREE.SphereGeometry(0.06, 12, 8), new THREE.MeshBasicMaterial({ color: isSel('meter', m.id) ? 0xffffff : 0xcccccc }));
      dome.position.set(m.position.x, m.height, m.position.z);
      dome.userData.sel = { kind: 'meter', id: m.id } satisfies Selection;
      bar(v(0, 0, 0), v(0, -m.height, 0), 0.006, STEEL, dome);
      a.items.add(dome);
    }
    a.renderer.shadowMap.enabled = true;
    a.room.traverse(o => { o.receiveShadow = true; o.castShadow = true; });
    a.items.traverse(o => { o.castShadow = true; });
  }, [p.location, p.lights, p.selection, p.plan, p.scanID, p.beams]);

  const moveTo = (pos: THREE.Vector3, target: THREE.Vector3) => {
    const a = api.current!;
    a.camera.position.copy(pos); a.controls.target.copy(target); a.controls.update();
  };
  const resetView = () => { const a = api.current!; moveTo(a.centre.clone().add(v(a.span * 0.75, a.span * 1.0, a.span * 0.95)), a.centre); };
  const topView = () => { const a = api.current!; moveTo(a.centre.clone().add(v(0, a.span * 1.6, 0.01)), a.centre); };
  // Eye: look through the selected camera (or the first one), else stand at the room's edge at eye height.
  const eyeLevel = () => {
    const a = api.current!;
    const { location: loc, selection: sel, scanID } = p;
    const inScan = (id?: string) => !id || !scanID || id.toUpperCase() === scanID.toUpperCase();
    const cams = [...loc.cameraPositions.filter(c => inScan(c.scanID)).map(c => ({ kind: 'camera', id: c.id, rig: c.rig })),
      ...loc.shots.filter(s => inScan(s.scanID)).map(s => ({ kind: 'shot', id: s.id, rig: s.rig }))];
    const cam = cams.find(c => sel?.kind === c.kind && sel.id === c.id) ?? cams[0];
    if (cam) {
      const { position, height, pan, tilt } = cam.rig;
      const dir = v(Math.sin(rad(pan)) * Math.cos(rad(tilt)), Math.sin(rad(tilt)), -Math.cos(rad(pan)) * Math.cos(rad(tilt)));
      const eye = v(position.x, height, position.z).add(dir.clone().multiplyScalar(0.5)); // just past the lens and matte box
      moveTo(eye, eye.clone().add(dir.multiplyScalar(2)));
      return;
    }
    const t = v(a.centre.x, 1.4, a.centre.z); moveTo(t.clone().add(v(0, 0.2, a.span * 0.45)), t);
  };

  return (
    <div className="scene3d" ref={host}>
      <div className="scene3d-hint">Drag to look round · right-drag or two fingers to slide · scroll to zoom · click to select</div>
      <div className="scene3d-buttons">
        <button className="tool" onClick={resetView} title="Reset view" aria-label="Reset view"><Icon name="undo" /></button>
        <button className="tool" onClick={topView} title="View from above">Top</button>
        <button className="tool" onClick={eyeLevel} title="Look through the selected camera, or the first one">Eye</button>
      </div>
    </div>
  );
}
