// Studio pieces and daylight for the 3D view: cyc, chroma screen, paper roll on its stands, LED
// wall, floor finishes, curtains and the sky. What gives light here (sun, sky through the windows,
// LED wall) uses the same levels as the readings (model/stage.ts), on the view's one brightness scale.
import * as THREE from 'three';
import type { BackdropPlacement, SkyKind } from '../../model/stage';
import { DARK, STEEL, bar, canvas, finish, mat, mesh, rng, v } from './kit';

/** A sheet that follows a profile (z out from the wall, y up) and runs `width` along local X. */
function sheet(profile: [number, number][], width: number, m: THREE.Material): THREE.Mesh {
  const cols = 2, pos: number[] = [], uv: number[] = [], idx: number[] = [];
  let run = 0;
  const runs = profile.map((p, i) => (i ? (run += Math.hypot(p[0] - profile[i - 1][0], p[1] - profile[i - 1][1])) : 0));
  profile.forEach(([z, y], i) => {
    for (let c = 0; c < cols; c++) { pos.push((width * c) / (cols - 1), y, z); uv.push(c / (cols - 1), runs[i] / Math.max(run, 1e-6)); }
  });
  for (let i = 0; i < profile.length - 1; i++) {
    const a = i * cols, b = a + cols;
    idx.push(a, a + 1, b, a + 1, b + 1, b);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return new THREE.Mesh(g, m);
}

/** Wall face down to a cove of radius r, then out across the floor. */
function coveProfile(top: number, r: number, sweep: number): [number, number][] {
  const p: [number, number][] = [[0, top], [0, r]];
  for (let i = 1; i < 12; i++) { const a = (i / 12) * Math.PI / 2; p.push([r - r * Math.cos(a), r - r * Math.sin(a)]); }
  p.push([r, 0.002], [Math.max(sweep, r + 0.01), 0.002]);
  return p;
}

/** What an LED wall shows: a soft, generic gradient with cabinet seams every 50 cm. */
function ledContent(width: number, height: number): THREE.Texture {
  const N = 512, { c, g } = canvas(N);
  const grad = g.createLinearGradient(0, 0, 0, N);
  grad.addColorStop(0, '#5b7fae'); grad.addColorStop(0.55, '#c9d3dc'); grad.addColorStop(0.62, '#8b8f86'); grad.addColorStop(1, '#4b4d48');
  g.fillStyle = grad; g.fillRect(0, 0, N, N);
  g.strokeStyle = 'rgba(0,0,0,0.35)'; g.lineWidth = 1;
  const cx = Math.max(1, Math.round(width / 0.5)), cy = Math.max(1, Math.round(height / 0.5));
  for (let i = 1; i < cx; i++) { const x = (i / cx) * N; g.beginPath(); g.moveTo(x, 0); g.lineTo(x, N); g.stroke(); }
  for (let j = 1; j < cy; j++) { const y = (j / cy) * N; g.beginPath(); g.moveTo(0, y); g.lineTo(N, y); g.stroke(); }
  return finish(c, true, false);
}

export interface BackdropBuild {
  group: THREE.Group;
  /** The LED face, whose glow follows the brightness scale. */
  ledFace?: THREE.MeshStandardMaterial;
  ledLight?: THREE.RectAreaLight;
}

/** The backdrop, placed in world space: local X along the backdrop (left to right seen from the room),
 *  Y up, Z into the room. */
export function backdrop(bd: BackdropPlacement, ledColour: THREE.Color, floorY = 0): BackdropBuild {
  const group = new THREE.Group();
  const u = v(bd.b.x - bd.a.x, 0, bd.b.z - bd.a.z).normalize();
  const n = v(bd.inward.x, 0, bd.inward.z);
  group.matrixAutoUpdate = false;
  group.matrix.makeBasis(u, v(0, 1, 0), n).setPosition(bd.a.x, floorY + bd.wall.bottom, bd.a.z);
  group.matrixWorldNeedsUpdate = true;
  const out: BackdropBuild = { group };
  if (bd.info.kind === 'cyc') {
    const paint = mat(bd.colour, { roughness: 0.92, metalness: 0, side: THREE.DoubleSide });
    group.add(sheet(coveProfile(bd.height, 0.5, bd.sweep), bd.width, paint));
  } else if (bd.info.kind === 'paper') {
    const paper = mat(bd.colour, { roughness: 0.85, metalness: 0, side: THREE.DoubleSide });
    const top = bd.height;
    group.add(sheet(coveProfile(top - 0.06, 0.7, bd.sweep), bd.width, paper));
    // The roll, the crossbar and two background stands.
    const roll = mesh(new THREE.CylinderGeometry(0.06, 0.06, bd.width + 0.04, 28), paper, group, v(bd.width / 2, top, 0.02));
    roll.rotation.z = Math.PI / 2;
    bar(v(-0.18, top + 0.08, 0.02), v(bd.width + 0.18, top + 0.08, 0.02), 0.014, STEEL, group);
    for (const x of [-0.18, bd.width + 0.18]) {
      bar(v(x, 0.35, 0.02), v(x, top + 0.12, 0.02), 0.016, DARK, group);
      for (let i = 0; i < 3; i++) {
        const a = (i / 3) * Math.PI * 2 + 0.4;
        bar(v(x, 0.38, 0.02), v(x + Math.cos(a) * 0.42, 0.005, 0.02 + Math.sin(a) * 0.42), 0.011, DARK, group);
      }
    }
  } else {
    // LED wall: cabinets on a frame, a dark face that glows with its content.
    const back = mat(0x121315, { roughness: 0.6, metalness: 0.3 });
    mesh(new THREE.BoxGeometry(bd.width, bd.height, 0.1), back, group, v(bd.width / 2, bd.height / 2, -0.06));
    const face = new THREE.MeshStandardMaterial({ color: 0x050505, roughness: 0.35, metalness: 0, emissive: ledColour, emissiveMap: ledContent(bd.width, bd.height), emissiveIntensity: 0 });
    const f = mesh(new THREE.PlaneGeometry(bd.width, bd.height), face, group, v(bd.width / 2, bd.height / 2, 0.001));
    f.userData.noShadow = true;
    out.ledFace = face;
    const light = new THREE.RectAreaLight(ledColour, 0, bd.width, bd.height);
    light.position.set(bd.width / 2, bd.height / 2, 0.02);
    light.rotation.y = Math.PI; // an area light shines along its local −Z: turn it to face the room
    group.add(light);
    out.ledLight = light;
  }
  return out;
}

/** Concrete: a pale mottled map, tinted by the material colour. */
export function concreteTexture(): THREE.Texture {
  const N = 512, { c, g } = canvas(N), r = rng(7);
  g.fillStyle = '#e4e4e4'; g.fillRect(0, 0, N, N);
  for (let i = 0; i < 2600; i++) {
    const x = r() * N, y = r() * N, s = 2 + r() * 26, k = 200 + Math.floor(r() * 55);
    g.fillStyle = `rgba(${k},${k},${k},${0.05 + r() * 0.12})`;
    g.beginPath(); g.arc(x, y, s, 0, Math.PI * 2); g.fill();
  }
  for (let i = 0; i < 9000; i++) { const k = Math.floor(150 + r() * 105); g.fillStyle = `rgba(${k},${k},${k},0.35)`; g.fillRect(r() * N, r() * N, 1, 1); }
  // Saw-cut joints every 2 m of a 4 m tile.
  g.strokeStyle = 'rgba(90,90,90,0.5)'; g.lineWidth = 2;
  for (const p of [0, N / 2]) { g.beginPath(); g.moveTo(p, 0); g.lineTo(p, N); g.stroke(); g.beginPath(); g.moveTo(0, p); g.lineTo(N, p); g.stroke(); }
  return finish(c, true);
}

/** A curtain across a window: gathered folds, on the room side of the glass (local frame of the wall,
 *  +X along it, `inner` the sign of Z towards the room). */
export function curtain(kind: 'sheer' | 'blackout', u0: number, u1: number, bottom: number, height: number, inner: number, wallTop: number): THREE.Mesh {
  const w = u1 - u0 + 0.3, top = Math.min(wallTop - 0.02, bottom + height + 0.15);
  const low = kind === 'blackout' ? Math.max(0.01, bottom - 0.2) : Math.max(0.01, bottom - 0.05);
  const folds = Math.max(4, Math.round(w / 0.12));
  const g = new THREE.PlaneGeometry(w, top - low, folds * 4, 1);
  const p = g.attributes.position as THREE.BufferAttribute;
  for (let i = 0; i < p.count; i++) p.setZ(i, Math.sin((p.getX(i) / w + 0.5) * folds * Math.PI * 2) * 0.035);
  g.computeVertexNormals();
  const m = kind === 'sheer'
    ? new THREE.MeshStandardMaterial({ color: 0xf4f2ee, roughness: 0.9, metalness: 0, transparent: true, opacity: 0.55, side: THREE.DoubleSide, depthWrite: false, emissive: 0xfffaf0, emissiveIntensity: 0 })
    : new THREE.MeshStandardMaterial({ color: 0x34363a, roughness: 0.95, metalness: 0, side: THREE.DoubleSide });
  const c = new THREE.Mesh(g, m);
  c.position.set((u0 + u1) / 2, (top + low) / 2, inner * (0.05 + 0.09));
  c.userData.curtain = kind;
  if (kind === 'sheer') { c.userData.noAO = true; c.renderOrder = 3; }
  return c;
}

/** Equirectangular sky: gradient to the horizon, the sun's disc, clouds for a hazy sky, flat grey when
 *  overcast, and plain ground below. Values are relative; the view sets the brightness. */
export function skyTexture(sky: SkyKind, toward?: THREE.Vector3): THREE.Texture {
  const W = 1024, H = 512, cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  const g = cv.getContext('2d')!, r = rng(11);
  const grad = g.createLinearGradient(0, 0, 0, H / 2);
  if (sky === 'overcast') { grad.addColorStop(0, '#c9cdd1'); grad.addColorStop(1, '#e3e5e6'); }
  else { grad.addColorStop(0, sky === 'clear' ? '#3f72b8' : '#7d9cc2'); grad.addColorStop(1, sky === 'clear' ? '#c6dbef' : '#dde5ec'); }
  g.fillStyle = grad; g.fillRect(0, 0, W, H / 2);
  const ground = g.createLinearGradient(0, H / 2, 0, H);
  ground.addColorStop(0, '#8d8a82'); ground.addColorStop(1, '#55534e');
  g.fillStyle = ground; g.fillRect(0, H / 2, W, H / 2);
  if (sky !== 'clear') {
    for (let i = 0; i < (sky === 'hazy' ? 70 : 140); i++) {
      const x = r() * W, y = H * (0.08 + r() * 0.38), s = 20 + r() * 70;
      const k = sky === 'hazy' ? 250 : 215 + Math.floor(r() * 25);
      const cg = g.createRadialGradient(x, y, 0, x, y, s);
      cg.addColorStop(0, `rgba(${k},${k},${k},${sky === 'hazy' ? 0.85 : 0.5})`); cg.addColorStop(1, `rgba(${k},${k},${k},0)`);
      g.fillStyle = cg; g.beginPath(); g.ellipse(x, y, s * 1.8, s * 0.7, 0, 0, Math.PI * 2); g.fill();
    }
  }
  if (toward && toward.y > -0.05 && sky !== 'overcast') {
    // three's equirect mapping: u from atan2(z, x), v from asin(y).
    const uu = Math.atan2(toward.z, toward.x) / (2 * Math.PI) + 0.5, vv = Math.asin(Math.max(-1, Math.min(1, toward.y))) / Math.PI + 0.5;
    const x = uu * W, y = (1 - vv) * H;
    const sg = g.createRadialGradient(x, y, 0, x, y, 60);
    sg.addColorStop(0, 'rgba(255,255,250,1)'); sg.addColorStop(0.12, 'rgba(255,253,240,1)'); sg.addColorStop(1, 'rgba(255,250,235,0)');
    g.fillStyle = sg; g.beginPath(); g.arc(x, y, 60, 0, Math.PI * 2); g.fill();
  }
  const t = new THREE.CanvasTexture(cv);
  t.mapping = THREE.EquirectangularReflectionMapping;
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
