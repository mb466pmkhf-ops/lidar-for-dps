// The room shell for the 3D view: boarded floor, walls with real thickness and openings cut for
// windows and doors, glazing, door leaves, skirting, and stand-in furniture sized to the scan.
// Colours are neutral on purpose: the scan knows shapes and sizes, not paint or upholstery.
import * as THREE from 'three';
import type { FloorPlan, PlanObject, PlanPoint, PlanSegment } from '../../model/types';
import { CHROME, DARK, STEEL, WOOD_LEG, cached, fabricBump, floorTextures, mat, mesh, plasterBump, rbox, v, bar } from './kit';

const T = 0.1; // wall thickness, m

export interface WallRecord {
  mid: THREE.Vector3;
  /** Materials that fade when the wall is cut away, with their normal opacity. */
  mats: { m: THREE.Material; base: number }[];
  level: number;
}
export interface RoomBuild { group: THREE.Group; walls: WallRecord[]; centre: THREE.Vector3; span: number }

interface Frame { g: THREE.Group; len: number; inner: number }

/** A group at `a`, with +X running to `b`. `inner` is the sign of local Z that faces the room's centre. */
function frame(a: PlanPoint, b: PlanPoint, centre: THREE.Vector3): Frame {
  const dx = b.x - a.x, dz = b.z - a.z, len = Math.hypot(dx, dz) || 0.001;
  const g = new THREE.Group();
  g.position.set(a.x, 0, a.z);
  g.rotation.y = -Math.atan2(dz, dx);
  const mx = (a.x + b.x) / 2, mz = (a.z + b.z) / 2;
  const inner = (-dz * (centre.x - mx) + dx * (centre.z - mz)) >= 0 ? 1 : -1;
  return { g, len, inner };
}

function windowParts(f: Frame, u0: number, u1: number, s: PlanSegment, rec: WallRecord) {
  const w = u1 - u0, h = s.height, cx = (u0 + u1) / 2, cy = s.bottom + h / 2;
  const frameMat = mat(0xe9e9e6, { roughness: 0.45, metalness: 0, transparent: true });
  const glass = new THREE.MeshPhysicalMaterial({ color: 0xbfd4e2, roughness: 0.04, metalness: 0, transparent: true, opacity: 0.16, envMapIntensity: 2.2, clearcoat: 1, side: THREE.DoubleSide, depthWrite: false });
  rec.mats.push({ m: frameMat, base: 1 }, { m: glass, base: 0.16 });
  const b = 0.045, d = T + 0.03;
  const part = (pw: number, ph: number, x: number, y: number, depth = d) => mesh(new THREE.BoxGeometry(pw, ph, depth), frameMat, f.g, v(x, y, 0));
  part(w, b, cx, s.bottom + b / 2); part(w, b, cx, s.bottom + h - b / 2);
  part(b, h, u0 + b / 2, cy); part(b, h, u1 - b / 2, cy);
  const panes = Math.max(1, Math.round(w / 0.75));
  for (let i = 1; i < panes; i++) part(b * 0.8, h - 2 * b, u0 + (w * i) / panes, cy, d * 0.7);
  if (h > 1.3) part(w - 2 * b, b * 0.8, cx, s.bottom + h * 0.62, d * 0.7);
  const pane = mesh(new THREE.BoxGeometry(w - 2 * b, h - 2 * b, 0.008), glass, f.g, v(cx, cy, 0));
  pane.userData.noShadow = true; pane.userData.noAO = true; pane.renderOrder = 2;
  pane.raycast = () => {}; // beams and clicks pass through glass
  if (s.bottom > 0.2) mesh(rbox(w + 0.12, 0.03, 0.18, 0.008), frameMat, f.g, v(cx, s.bottom - 0.005, f.inner * (T / 2 + 0.05)));
}

function doorParts(f: Frame, u0: number, u1: number, s: PlanSegment, rec: WallRecord) {
  const w = u1 - u0, h = s.height;
  const frameMat = mat(0xe4e3df, { roughness: 0.5, metalness: 0, transparent: true });
  const leafMat = mat(0xd3d0c9, { roughness: 0.55, metalness: 0, transparent: true });
  rec.mats.push({ m: frameMat, base: 1 }, { m: leafMat, base: 1 });
  const b = 0.05, d = T + 0.03;
  mesh(new THREE.BoxGeometry(b, h, d), frameMat, f.g, v(u0 + b / 2, s.bottom + h / 2, 0));
  mesh(new THREE.BoxGeometry(b, h, d), frameMat, f.g, v(u1 - b / 2, s.bottom + h / 2, 0));
  mesh(new THREE.BoxGeometry(w, b, d), frameMat, f.g, v((u0 + u1) / 2, s.bottom + h - b / 2, 0));
  // The leaf hangs from the u0 side; an open door swings into the room.
  const hinge = new THREE.Group();
  hinge.position.set(u0 + b, s.bottom, 0);
  if (s.isOpen) hinge.rotation.y = -f.inner * 1.4;
  f.g.add(hinge);
  const lw = w - 2 * b, lh = h - b - 0.01;
  mesh(rbox(lw, lh, 0.04, 0.004, 1), leafMat, hinge, v(lw / 2, lh / 2 + 0.005, 0));
  // Two recessed panels and a lever handle on each face.
  for (const side of [-1, 1]) {
    for (const [py, ph] of [[lh * 0.28, lh * 0.42], [lh * 0.74, lh * 0.36]] as const)
      mesh(new THREE.BoxGeometry(lw * 0.7, ph, 0.004), frameMat, hinge, v(lw / 2, py, side * 0.021));
    bar(v(lw - 0.07, 1.0, side * 0.02), v(lw - 0.07, 1.0, side * 0.06), 0.009, CHROME, hinge);
    bar(v(lw - 0.07, 1.0, side * 0.058), v(lw - 0.19, 1.0, side * 0.058), 0.008, CHROME, hinge);
  }
}

function distToWalls(p: PlanPoint, walls: PlanSegment[]): number {
  let best = Infinity;
  for (const w of walls) {
    const dx = w.b.x - w.a.x, dz = w.b.z - w.a.z, l2 = dx * dx + dz * dz || 1e-6;
    const t = Math.min(1, Math.max(0, ((p.x - w.a.x) * dx + (p.z - w.a.z) * dz) / l2));
    best = Math.min(best, Math.hypot(p.x - (w.a.x + dx * t), p.z - (w.a.z + dz * t)));
  }
  return best;
}

/** Stand-in furniture from a scanned box: local X is its width, Z its depth, the floor is y = 0. */
function furniture(o: PlanObject, plan: FloorPlan): THREE.Group {
  const g = new THREE.Group();
  g.position.set(o.center.x, 0, o.center.z);
  g.rotation.y = -o.rotation;
  const { width: w, depth: d, height: h } = o;
  const kind = o.category.toLowerCase();
  // Which long side backs onto a wall? Sofas, beds and cupboards turn their back to it.
  const side = (sz: number) => {
    const c = Math.cos(o.rotation), s = Math.sin(o.rotation), z = (sz * d) / 2;
    return distToWalls({ x: o.center.x - z * s, z: o.center.z + z * c }, plan.walls);
  };
  const back = side(1) <= side(-1) ? 1 : -1;
  const cloth = mat(0x8c8a86, { roughness: 0.95, metalness: 0, bumpMap: cached('fabric', fabricBump), bumpScale: 0.6 });
  cloth.bumpMap!.repeat.set(6, 6);
  const wood = mat(0x8a7662, { roughness: 0.5, metalness: 0 });
  const paint = mat(0xc9c7c2, { roughness: 0.6, metalness: 0 });
  const legs = (inset: number, top: number, r: number, m: THREE.Material) => {
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) bar(v(sx * (w / 2 - inset), 0, sz * (d / 2 - inset)), v(sx * (w / 2 - inset), top, sz * (d / 2 - inset)), r * 0.7, m, g, r);
  };
  if (kind.includes('sofa') || kind.includes('couch')) {
    const seat = Math.min(0.44, h * 0.55), arm = Math.min(0.2, w * 0.12), backT = Math.min(0.24, d * 0.3);
    legs(0.07, 0.07, 0.02, WOOD_LEG);
    mesh(rbox(w, seat - 0.2, d, 0.04), cloth, g, v(0, 0.07 + (seat - 0.2) / 2, 0));
    mesh(rbox(w - 2 * arm, h - seat + 0.12, backT, 0.07, 4), cloth, g, v(0, seat - 0.12 + (h - seat + 0.12) / 2, back * (d / 2 - backT / 2)));
    for (const sx of [-1, 1]) mesh(rbox(arm, Math.min(h, seat + 0.2) - 0.07, d, 0.06, 4), cloth, g, v(sx * (w / 2 - arm / 2), 0.07 + (Math.min(h, seat + 0.2) - 0.07) / 2, 0));
    const n = Math.max(1, Math.round((w - 2 * arm) / 0.75)), cw = (w - 2 * arm) / n;
    for (let i = 0; i < n; i++) {
      const x = -w / 2 + arm + cw * (i + 0.5);
      mesh(rbox(cw - 0.015, 0.15, d - backT - 0.02, 0.05, 4), cloth, g, v(x, seat - 0.07, -back * backT / 2));
      const pillow = mesh(rbox(cw - 0.05, h - seat - 0.02, 0.16, 0.07, 4), cloth, g, v(x, seat + (h - seat) / 2 + 0.01, back * (d / 2 - backT - 0.06)));
      pillow.rotation.x = back * 0.16;
    }
  } else if (kind.includes('chair') || kind.includes('stool')) {
    const seat = Math.min(0.46, h * 0.55);
    legs(0.04, seat, 0.017, wood);
    mesh(rbox(w, 0.05, d, 0.02), cloth, g, v(0, seat, 0));
    if (h > seat + 0.15) mesh(rbox(w, h - seat - 0.08, 0.04, 0.02), wood, g, v(0, seat + 0.08 + (h - seat - 0.08) / 2, back * (d / 2 - 0.02)));
  } else if (kind.includes('table') || kind.includes('desk')) {
    legs(0.06, h - 0.03, 0.024, wood);
    mesh(rbox(w, 0.04, d, 0.012), wood, g, v(0, h - 0.02, 0));
  } else if (kind.includes('bed')) {
    const base = Math.min(0.3, h * 0.5);
    mesh(rbox(w, base, d, 0.03), wood, g, v(0, base / 2, 0));
    mesh(rbox(w - 0.06, 0.22, d - 0.06, 0.08, 4), paint, g, v(0, base + 0.11, 0));
    // Headboard and pillows go at whichever short end is against a wall.
    const end = (sx: number) => { const c = Math.cos(o.rotation), s = Math.sin(o.rotation), x = (sx * w) / 2; return distToWalls({ x: o.center.x + x * c, z: o.center.z + x * s }, plan.walls); };
    const head = end(1) <= end(-1) ? 1 : -1;
    mesh(rbox(0.06, Math.max(h, base + 0.6), d, 0.02), wood, g, v(head * (w / 2 - 0.03), Math.max(h, base + 0.6) / 2, 0));
    for (const sz of d > 1.2 ? [-1, 1] : [0]) mesh(rbox(0.42, 0.13, Math.min(0.68, d * 0.44), 0.06, 4), paint, g, v(head * (w / 2 - 0.34), base + 0.26, sz * d * 0.24));
  } else if (kind.includes('tele') || kind === 'tv' || kind.includes('screen')) {
    const screen = new THREE.MeshPhysicalMaterial({ color: 0x050607, roughness: 0.12, metalness: 0.3, clearcoat: 1 });
    mesh(rbox(w, h, Math.min(d, 0.05), 0.008, 1), screen, g, v(0, h / 2, 0));
  } else if (kind.includes('storage') || kind.includes('cabinet') || kind.includes('shelf') || kind.includes('refrigerator') || kind.includes('wardrobe')) {
    mesh(rbox(w, h - 0.06, d, 0.006, 1), paint, g, v(0, 0.06 + (h - 0.06) / 2, 0));
    mesh(new THREE.BoxGeometry(w - 0.04, 0.06, d - 0.04), mat(0x3a3a3a, { roughness: 0.8 }), g, v(0, 0.03, 0));
    // Doors on the long face that looks into the room; the wider of the box's two sides.
    const alongX = w >= d, span = alongX ? w : d;
    const front = alongX ? -back : (distToWalls({ x: o.center.x + (w / 2) * Math.cos(o.rotation), z: o.center.z + (w / 2) * Math.sin(o.rotation) }, plan.walls)
      <= distToWalls({ x: o.center.x - (w / 2) * Math.cos(o.rotation), z: o.center.z - (w / 2) * Math.sin(o.rotation) }, plan.walls) ? -1 : 1);
    const n = Math.max(1, Math.round(span / 0.5));
    for (let i = 0; i < n; i++) {
      const p = -span / 2 + (span / n) * (i + 0.5);
      mesh(rbox(alongX ? span / n - 0.012 : 0.018, h - 0.1, alongX ? 0.018 : span / n - 0.012, 0.004, 1), paint, g,
        alongX ? v(p, 0.06 + (h - 0.08) / 2, front * (d / 2 + 0.006)) : v(front * (w / 2 + 0.006), 0.06 + (h - 0.08) / 2, p));
      const hx = (i % 2 ? -1 : 1) * (span / n / 2 - 0.05), hy = Math.min(h * 0.55, 1.05);
      if (alongX) bar(v(p + hx, hy - 0.06, front * (d / 2 + 0.03)), v(p + hx, hy + 0.06, front * (d / 2 + 0.03)), 0.005, CHROME, g);
      else bar(v(front * (w / 2 + 0.03), hy - 0.06, p + hx), v(front * (w / 2 + 0.03), hy + 0.06, p + hx), 0.005, CHROME, g);
    }
  } else if (/stove|oven|dishwasher|washer|dryer/.test(kind)) {
    // Kitchen and laundry machines: a white box on a plinth with a dark door and a bar handle on the room side.
    const f = -back, dark = mat(0x16181a, { roughness: 0.25, metalness: 0.4 });
    mesh(rbox(w, h - 0.08, d, 0.008, 1), paint, g, v(0, 0.08 + (h - 0.08) / 2, 0));
    mesh(new THREE.BoxGeometry(w - 0.04, 0.08, d - 0.06), DARK, g, v(0, 0.04, 0));
    if (kind.includes('washer') || kind.includes('dryer')) {
      const port = mesh(new THREE.CylinderGeometry(Math.min(w, h) * 0.28, Math.min(w, h) * 0.28, 0.03, 40), dark, g, v(0, h * 0.5, f * (d / 2 + 0.012)));
      port.rotation.x = Math.PI / 2;
    } else {
      mesh(rbox(w - 0.08, h * 0.5, 0.012, 0.004, 1), dark, g, v(0, 0.14 + h * 0.25, f * (d / 2 + 0.006)));
      bar(v(-w / 2 + 0.07, h * 0.5 + 0.2, f * (d / 2 + 0.035)), v(w / 2 - 0.07, h * 0.5 + 0.2, f * (d / 2 + 0.035)), 0.008, STEEL, g);
    }
    if (kind.includes('stove')) {
      mesh(rbox(w - 0.02, 0.008, d - 0.02, 0.003, 1), dark, g, v(0, h + 0.004, 0));
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
        const ring = mesh(new THREE.TorusGeometry(Math.min(w, d) * 0.14, 0.006, 8, 36), STEEL, g, v(sx * w * 0.23, h + 0.01, sz * d * 0.23));
        ring.rotation.x = Math.PI / 2;
      }
    }
  } else if (kind.includes('sink')) {
    // A worktop unit with a steel bowl and a tap at the wall side.
    mesh(rbox(w, h - 0.04, d, 0.006, 1), paint, g, v(0, (h - 0.04) / 2, 0));
    mesh(rbox(w + 0.02, 0.04, d + 0.02, 0.008, 1), mat(0x4a4a4c, { roughness: 0.4 }), g, v(0, h - 0.02, 0));
    mesh(rbox(Math.min(w * 0.7, 0.6), 0.012, d * 0.6, 0.004, 1), STEEL, g, v(0, h + 0.002, -back * d * 0.06));
    bar(v(0, h, back * d * 0.36), v(0, h + 0.24, back * d * 0.36), 0.011, CHROME, g);
    bar(v(0, h + 0.24, back * d * 0.36), v(0, h + 0.2, back * d * 0.12), 0.009, CHROME, g);
  } else if (kind.includes('bath')) {
    const enamel = mat(0xe9e8e4, { roughness: 0.25, metalness: 0 });
    mesh(rbox(w, h, d, 0.06, 4), enamel, g, v(0, h / 2, 0));
    mesh(rbox(w - 0.14, 0.02, d - 0.14, 0.008, 2), mat(0xb9bcbd, { roughness: 0.2, metalness: 0 }), g, v(0, h - 0.004, 0));
    bar(v(w / 2 - 0.09, h, 0), v(w / 2 - 0.09, h + 0.14, 0), 0.012, CHROME, g);
    bar(v(w / 2 - 0.09, h + 0.14, 0), v(w / 2 - 0.2, h + 0.12, 0), 0.01, CHROME, g);
  } else if (kind.includes('toilet')) {
    const enamel = mat(0xe9e8e4, { roughness: 0.25, metalness: 0 });
    const tank = Math.min(0.2, d * 0.3), seat = Math.min(0.42, h * 0.55);
    mesh(rbox(w * 0.9, h - seat * 0.55, tank, 0.03, 3), enamel, g, v(0, seat * 0.55 + (h - seat * 0.55) / 2, back * (d / 2 - tank / 2)));
    const bowl = mesh(new THREE.CylinderGeometry(0.5, 0.36, seat, 36), enamel, g, v(0, seat / 2, -back * tank / 2));
    bowl.scale.set(w * 0.8, 1, d - tank);
    const lid = mesh(new THREE.CylinderGeometry(0.5, 0.5, 0.025, 36), enamel, g, v(0, seat + 0.0125, -back * tank / 2));
    lid.scale.set(w * 0.84, 1, d - tank);
  } else if (kind.includes('fireplace')) {
    // A surround with a dark opening on the room side and a mantel shelf.
    const f = -back, mouth = Math.min(h * 0.6, 0.8);
    mesh(rbox(w, h, d, 0.01, 1), paint, g, v(0, h / 2, 0));
    mesh(new THREE.BoxGeometry(w * 0.6, mouth, 0.02), mat(0x0b0b0b, { roughness: 1, metalness: 0 }), g, v(0, mouth / 2, f * (d / 2 + 0.002)));
    mesh(rbox(w + 0.12, 0.05, d + 0.08, 0.01, 1), wood, g, v(0, h + 0.025, f * 0.04));
  } else if (kind.includes('stair')) {
    // Steps along the longer side, rising to the scanned height. Which end is the top isn't in the scan.
    const alongX = w >= d, run = alongX ? w : d, n = Math.max(2, Math.round(h / 0.18));
    for (let i = 0; i < n; i++) {
      const y = (h / n) * (i + 1), at = -run / 2 + (run / n) * (i + 0.5);
      mesh(new THREE.BoxGeometry(alongX ? run / n : w, y, alongX ? d : run / n), wood, g, alongX ? v(at, y / 2, 0) : v(0, y / 2, at));
    }
  } else {
    mesh(rbox(w, h, d, 0.02), mat(0x8a8a88, { roughness: 0.75, metalness: 0 }), g, v(0, h / 2, 0));
  }
  return g;
}

export function buildRoom(plan: FloorPlan | undefined): RoomBuild {
  const group = new THREE.Group();
  const walls: WallRecord[] = [];
  const b = plan?.bounds ?? { minX: -3, minZ: -3, maxX: 3, maxZ: 3 };
  const centre = v((b.minX + b.maxX) / 2, 1, (b.minZ + b.maxZ) / 2);
  const span = Math.max(b.maxX - b.minX, b.maxZ - b.minZ, 3);

  // Floor.
  const ft = cached('floor', floorTextures);
  const floorMat = new THREE.MeshStandardMaterial({ map: ft.map, bumpMap: ft.bump, bumpScale: 1.2, roughness: 0.5, metalness: 0 });
  // Shape coordinates are metres, so one texture tile covers `tile` metres.
  ft.map.repeat.set(1 / ft.tile, 1 / ft.tile); ft.bump.repeat.set(1 / ft.tile, 1 / ft.tile);
  const polys = plan?.floorPolygons.length ? plan.floorPolygons : [[{ x: b.minX, z: b.minZ }, { x: b.maxX, z: b.minZ }, { x: b.maxX, z: b.maxZ }, { x: b.minX, z: b.maxZ }]];
  for (const poly of polys) {
    if (poly.length < 3) continue;
    const m = new THREE.Mesh(new THREE.ShapeGeometry(new THREE.Shape(poly.map(q => new THREE.Vector2(q.x, -q.z)))), floorMat);
    m.rotation.x = -Math.PI / 2;
    group.add(m);
  }

  // Walls, cut round their windows and doors.
  const bump = cached('plaster', plasterBump);
  bump.repeat.set(3, 3);
  const openings = [
    ...(plan?.windows ?? []).map(s => ({ s, kind: 'window' as const })),
    ...(plan?.doors ?? []).map(s => ({ s, kind: 'door' as const })),
    ...(plan?.openings ?? []).map(s => ({ s, kind: 'opening' as const })),
  ];
  const used = new Set<string>();
  (plan?.walls ?? []).forEach((w, index) => {
    const f = frame(w.a, w.b, centre);
    const paint = mat(0xcfccc6, { roughness: 0.9, metalness: 0, transparent: true, bumpMap: bump, bumpScale: 0.25 });
    const trim = mat(0xe6e5e1, { roughness: 0.55, metalness: 0, transparent: true });
    const rec: WallRecord = { mid: v((w.a.x + w.b.x) / 2, 0, (w.a.z + w.b.z) / 2), mats: [{ m: paint, base: 1 }, { m: trim, base: 1 }], level: 1 };
    const ux = (w.b.x - w.a.x) / f.len, uz = (w.b.z - w.a.z) / f.len;
    const along = (p: PlanPoint) => (p.x - w.a.x) * ux + (p.z - w.a.z) * uz;
    const off = (p: PlanPoint) => Math.abs(-(p.x - w.a.x) * uz + (p.z - w.a.z) * ux);
    const mine = openings
      .filter(o => !used.has(o.s.id) && off(o.s.a) < 0.25 && off(o.s.b) < 0.25)
      .map(o => ({ ...o, u0: Math.max(0, Math.min(along(o.s.a), along(o.s.b))), u1: Math.min(f.len, Math.max(along(o.s.a), along(o.s.b))) }))
      .filter(o => o.u1 - o.u0 > 0.1)
      .sort((p, q) => p.u0 - q.u0);
    const h = Math.max(w.height, 0.05) + index * 0.0007; // a hair's difference stops corner tops flickering
    const top = w.bottom + h;
    const solid = (u0: number, u1: number, y0: number, y1: number, skirt: boolean) => {
      if (u1 - u0 < 0.005 || y1 - y0 < 0.005) return;
      mesh(new THREE.BoxGeometry(u1 - u0, y1 - y0, T), paint, f.g, v((u0 + u1) / 2, (y0 + y1) / 2, 0));
      if (skirt && w.bottom < 0.05 && y1 - y0 > 0.2) mesh(new THREE.BoxGeometry(u1 - u0, 0.085, 0.014), trim, f.g, v((u0 + u1) / 2, w.bottom + 0.0425, f.inner * (T / 2 + 0.007)));
    };
    let cursor = -T / 2;
    for (const o of mine) {
      if (o.u0 < cursor) continue; // overlapping openings: keep the first
      used.add(o.s.id);
      solid(cursor, o.u0, w.bottom, top, true);
      solid(o.u0, o.u1, w.bottom, Math.min(top, o.s.bottom), o.s.bottom > 0.3);
      solid(o.u0, o.u1, Math.min(top, o.s.bottom + o.s.height), top, false);
      if (o.kind === 'window') windowParts(f, o.u0, o.u1, o.s, rec);
      if (o.kind === 'door') doorParts(f, o.u0, o.u1, o.s, rec);
      cursor = o.u1;
    }
    solid(cursor, f.len + T / 2, w.bottom, top, true);
    group.add(f.g);
    walls.push(rec);
  });
  // Windows and doors the scan didn't tie to a wall still get drawn, standing on their own.
  for (const o of openings) {
    if (used.has(o.s.id) || o.kind === 'opening') continue;
    const f = frame(o.s.a, o.s.b, centre);
    const rec: WallRecord = { mid: v((o.s.a.x + o.s.b.x) / 2, 0, (o.s.a.z + o.s.b.z) / 2), mats: [], level: 1 };
    if (o.kind === 'window') windowParts(f, 0, f.len, o.s, rec); else doorParts(f, 0, f.len, o.s, rec);
    group.add(f.g);
    walls.push(rec);
  }

  for (const o of plan?.objects ?? []) if (plan) group.add(furniture(o, plan));

  group.traverse(o => {
    const m = o as THREE.Mesh;
    if (!m.isMesh) return;
    m.receiveShadow = true;
    m.castShadow = !m.userData.noShadow;
  });
  return { group, walls, centre, span };
}

/** The ground beyond the room: a plain floor tone that fades into the backdrop, so the set has
 *  somewhere to stand without the "3D demo" grid (Docs/LOOK.md). */
export function ground(): THREE.Mesh {
  const m = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false,
    uniforms: { centre: { value: new THREE.Vector2() }, reach: { value: 14 } },
    vertexShader: `varying vec3 w; void main() { vec4 p = modelMatrix * vec4(position, 1.0); w = p.xyz; gl_Position = projectionMatrix * viewMatrix * p; }`,
    fragmentShader: `
      uniform vec2 centre; uniform float reach; varying vec3 w;
      void main() {
        float fade = 1.0 - smoothstep(reach * 0.15, reach * 0.8, distance(w.xz, centre));
        gl_FragColor = vec4(vec3(0.16, 0.165, 0.17), 0.85 * fade);
      }`,
  });
  const g = new THREE.Mesh(new THREE.PlaneGeometry(80, 80), m);
  g.rotation.x = -Math.PI / 2;
  g.position.y = -0.012;
  g.userData.noAO = true;
  g.raycast = () => {};
  return g;
}
