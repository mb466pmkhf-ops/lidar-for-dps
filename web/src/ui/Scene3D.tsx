// 3D view of the lighting plan, built from the synced data (the 2D floor plan, lights, people,
// cameras, meters). Like the phone's 3D view: units on their stands, beams that stop where they
// meet the room, walls between you and the room cut away.
//
// What the picture is, and isn't (Docs/DECISIONS.md D-006, D-011): each unit's brightness, colour,
// beam shape and barn-door cut come from the same photometric model as the readings, and shadows
// are real. It shows direct light only: no light bouncing round the room, no daylight. So it is a
// preview of the look, and the readings stay the figures to work from.
import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/examples/jsm/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import type { CameraRig, ExposureSettings, FloorPlan, LightFixture, Location } from '../model/types';
import { KIND_INFO, barnDoorTransmission, fixtureProfile, illuminanceOnAxis, photometrics, relativeIntensity, type ResolvedPhotometrics } from '../model/photometrics';
import { lightSupport } from '../model/rigging';
import { keyLux, stopLabel } from '../model/exposure';
import { fieldOfView, imageArea } from '../model/camera';
import type { MeterPoint } from '../model/calculator';
import type { Selection } from './PlanCanvas';
import { readingShort } from './format';
import { Icon } from './icons';
import { DARK, backdropTexture, bar, rad, v } from './scene3d/kit';
import { buildRoom, ground, type WallRecord } from './scene3d/room';
import { board, cameraModel, head, meterModel, person, stand, yoke } from './scene3d/models';
import { beam } from './scene3d/beam';

interface Props {
  location: Location;
  plan?: FloorPlan;
  scanID?: string;
  lights: LightFixture[];
  selection?: Selection;
  /** Draw every unit's beam, not just the selected one's (the plan's Beams layer). */
  beams?: boolean;
  /** The calculator's readings, shown as tags over meters and faces (the plan's Readings layer). */
  meters?: MeterPoint[];
  readings?: Map<string, number>;
  showReadings?: boolean;
  exposure: ExposureSettings;
  onSelect(s?: Selection): void;
}

type Quality = 0 | 1 | 2; // 2 = everything on, 1 = no ambient occlusion, 0 = plain
const SHADOW_LIGHTS = 4;
const DEFAULT_FOV = 42;

/** How the unit's light falls off across its cone, and where the barn doors cut it: the calculator's
 *  own curves, baked into a small texture the spotlight projects. `half` is the cone's half-angle. */
function cookie(pm: ResolvedPhotometrics, l: LightFixture, half: number): THREE.DataTexture {
  const N = 128, data = new Uint8Array(N * N * 4), t = Math.tan(rad(half));
  const doors = l.barnDoors && pm.barnDoorsAvailable ? l.barnDoors : undefined;
  for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
    const x = ((i + 0.5) / N * 2 - 1) * t, y = ((j + 0.5) / N * 2 - 1) * t;
    const theta = Math.atan(Math.hypot(x, y)) * 180 / Math.PI;
    let f = relativeIntensity(pm.distribution, theta, pm.beamAngle);
    if (doors) f *= barnDoorTransmission(doors, Math.atan(x) * 180 / Math.PI, Math.atan(y) * 180 / Math.PI);
    f *= 1 - Math.min(1, Math.max(0, (theta - half * 0.92) / (half * 0.08))); // ease out at the cone's rim
    f = Math.max(0, Math.min(1, f));
    const c = Math.round(255 * (f <= 0.0031308 ? f * 12.92 : 1.055 * Math.pow(f, 1 / 2.4) - 0.055)); // sRGB-encoded, so the dim end stays smooth
    data.set([c, c, c, 255], (j * N + i) * 4);
  }
  const tex = new THREE.DataTexture(data, N, N, THREE.RGBAFormat);
  tex.magFilter = tex.minFilter = THREE.LinearFilter;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.needsUpdate = true;
  return tex;
}

/** Free what a removed part of the scene held on the graphics card. */
function dispose(root: THREE.Object3D) {
  root.traverse(o => {
    const m = o as THREE.Mesh;
    if (m.isMesh) { m.geometry.dispose(); const mm = m.material as THREE.Material; if (!mm.userData.shared) mm.dispose(); }
    const s = o as THREE.SpotLight;
    if (s.isSpotLight) { s.map?.dispose(); s.shadow.map?.dispose(); }
  });
}

interface Api {
  renderer: THREE.WebGLRenderer; composer: EffectComposer; gtao: GTAOPass; bloom: UnrealBloomPass;
  scene: THREE.Scene; camera: THREE.PerspectiveCamera; controls: OrbitControls;
  room: THREE.Group; items: THREE.Group; marks: THREE.Group; walls: WallRecord[]; wallGroups: THREE.Object3D[];
  ambient: THREE.HemisphereLight; grid: THREE.Mesh;
  centre: THREE.Vector3; span: number;
  tags: { el: HTMLElement; at: THREE.Vector3 }[];
  invalidate(frames?: number): void;
}

export function Scene3D(p: Props) {
  const host = useRef<HTMLDivElement>(null);
  const tagHost = useRef<HTMLDivElement>(null);
  const api = useRef<Api>(undefined);
  const onSelect = useRef(p.onSelect);
  onSelect.current = p.onSelect;
  // "Balanced" fits the brightness to the screen; "set stop" shows it as the camera would expose it.
  const [atStop, setAtStop] = useState(() => { try { return localStorage.getItem('framescan.3d.look') === 'stop'; } catch { return false; } });
  // Looking through a camera: its frame lines are drawn over the view.
  const [eye, setEye] = useState<{ key: string; x: number; z: number; ratio: number; label: string }>();
  const eyeRef = useRef(eye);
  eyeRef.current = eye;
  const [noLight, setNoLight] = useState(false);
  // What is already built, by item: a change to one light leaves the others (and their shadow maps) alone.
  const built = useRef(new Map<string, { key: string; obj: THREE.Object3D }>());
  const roomGen = useRef(0);

  // Renderer, camera, controls: once.
  useEffect(() => {
    const el = host.current!;
    const renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance' });
    renderer.setClearColor(0x070707);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFShadowMap; // honours each light's shadow radius: soft sources, soft shadows
    renderer.shadowMap.autoUpdate = false; // shadows are redrawn when the plan changes, not on every frame of an orbit
    renderer.toneMapping = THREE.NeutralToneMapping; // keeps the colour of the light honest in the highlights
    renderer.toneMappingExposure = 1;
    el.appendChild(renderer.domElement);

    const scene = new THREE.Scene();
    scene.background = backdropTexture();
    // A soft studio surround, used only for reflections in metal and glass.
    const pmrem = new THREE.PMREMGenerator(renderer);
    const envScene = new RoomEnvironment();
    scene.environment = pmrem.fromScene(envScene, 0.04).texture;
    scene.environmentIntensity = 0.05;
    pmrem.dispose();
    const ambient = new THREE.HemisphereLight(0xffffff, 0x8a8580, 0.08);
    scene.add(ambient);

    const camera = new THREE.PerspectiveCamera(DEFAULT_FOV, 1, 0.05, 200);
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.09;
    controls.maxPolarAngle = rad(88);
    controls.minDistance = 0.6;
    controls.maxDistance = 40;
    controls.screenSpacePanning = false;
    const grid = ground();
    scene.add(grid);
    const room = new THREE.Group(), items = new THREE.Group(), marks = new THREE.Group();
    scene.add(room, items, marks);
    built.current = new Map();

    // Picture pipeline: multisampled HDR target → contact shading → glow round bright faces → tone map.
    const target = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, samples: 4 });
    const composer = new EffectComposer(renderer, target);
    composer.addPass(new RenderPass(scene, camera));
    const gtao = new GTAOPass(scene, camera, 4, 4);
    gtao.updateGtaoMaterial({ radius: 0.35, distanceExponent: 1.4, thickness: 1.2, scale: 1.15, samples: 16, screenSpaceRadius: false });
    gtao.updatePdMaterial({ lumaPhi: 10, depthPhi: 2, normalPhi: 3, radius: 6, rings: 2, samples: 16 });
    gtao.blendIntensity = 0.85;
    // Haze, glass, the ground grid and cut-away walls must not darken what is behind them.
    const baseOverride = gtao.overrideVisibility.bind(gtao);
    gtao.overrideVisibility = () => {
      baseOverride();
      scene.traverse(o => { if (o.userData.noAO || o.userData.cut) o.visible = false; });
    };
    composer.addPass(gtao);
    const bloom = new UnrealBloomPass(new THREE.Vector2(4, 4), 0.32, 0.55, 1.15);
    composer.addPass(bloom);
    composer.addPass(new OutputPass());

    let quality: Quality = 2;
    try { const q = localStorage.getItem('framescan.3d.quality'); if (q === 'fast') quality = 0; } catch { /* private mode */ }
    const locked = (() => { try { return !!localStorage.getItem('framescan.3d.quality'); } catch { return false; } })();
    const applyQuality = () => {
      gtao.enabled = quality === 2;
      bloom.enabled = quality >= 1;
      const ratio = Math.min(window.devicePixelRatio, quality === 2 ? 2 : quality === 1 ? 1.5 : 1);
      renderer.setPixelRatio(ratio); composer.setPixelRatio(ratio);
      resize();
    };

    let pending = 3;
    const invalidate = (frames = 2) => { pending = Math.max(pending, frames); };
    const resize = () => {
      const w = Math.max(el.clientWidth, 1), h = Math.max(el.clientHeight, 1);
      renderer.setSize(w, h, false); composer.setSize(w, h);
      renderer.domElement.style.width = '100%'; renderer.domElement.style.height = '100%';
      camera.aspect = w / h; camera.updateProjectionMatrix();
      invalidate();
    };
    api.current = { renderer, composer, gtao, bloom, scene, camera, controls, room, items, marks, walls: [], wallGroups: [], ambient, grid, centre: v(0, 1, 0), span: 6, tags: [], invalidate };
    applyQuality();
    if (import.meta.env.DEV) (window as unknown as { __scene3d?: Api }).__scene3d = api.current; // for screenshots while developing
    const ro = new ResizeObserver(resize); ro.observe(el);
    controls.addEventListener('change', () => invalidate());
    // Orbiting away from a camera leaves its viewfinder.
    controls.addEventListener('start', () => {
      if (!eyeRef.current) return;
      setEye(undefined);
      camera.fov = DEFAULT_FOV; camera.updateProjectionMatrix();
    });

    let frame = 0, last = 0, slow = 0, streak = 0;
    const tmp = new THREE.Vector3();
    const tick = (now: number) => {
      frame = requestAnimationFrame(tick);
      controls.update();
      const a = api.current!;
      // Cut away the walls between the camera and the room, easing them in and out.
      let fading = false;
      a.walls.forEach((w, i) => {
        const ox = w.mid.x - a.centre.x, oz = w.mid.z - a.centre.z;
        const outside = Math.hypot(camera.position.x - a.centre.x, camera.position.z - a.centre.z) > Math.hypot(ox, oz);
        const cut = ox * (camera.position.x - w.mid.x) + oz * (camera.position.z - w.mid.z) > 0 && outside;
        const goal = cut ? 0 : 1;
        if (w.level === goal) return;
        w.level = Math.abs(w.level - goal) < 0.04 ? goal : w.level + (goal - w.level) * 0.22;
        fading = true;
        for (const { m, base } of w.mats) { m.opacity = base * (0.05 + 0.95 * w.level); m.depthWrite = w.level > 0.6 && base > 0.5; }
        a.wallGroups[i]?.traverse(o => { o.userData.cut = w.level < 0.5; });
      });
      if (fading) invalidate();
      if (pending <= 0) { streak = 0; return; }
      pending--;
      composer.render();
      // Reading tags follow their points.
      const w = el.clientWidth, h = el.clientHeight;
      for (const t of a.tags) {
        tmp.copy(t.at).project(camera);
        const visible = tmp.z < 1 && Math.abs(tmp.x) < 1.05 && Math.abs(tmp.y) < 1.05;
        t.el.style.display = visible ? '' : 'none';
        if (visible) t.el.style.transform = `translate(-50%, -100%) translate(${((tmp.x + 1) / 2) * w}px, ${((1 - tmp.y) / 2) * h}px)`;
      }
      // If the machine can't keep up while the view is moving, drop the costliest effects first.
      if (!locked && streak++ > 2 && last) {
        slow = slow * 0.9 + (now - last > 42 ? 1 : 0) * 0.1;
        if (slow > 0.6 && quality > 0) { quality = (quality - 1) as Quality; slow = 0; applyQuality(); }
      }
      last = now;
    };
    frame = requestAnimationFrame(tick);

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
      cancelAnimationFrame(frame); ro.disconnect(); controls.dispose();
      composer.dispose(); target.dispose(); renderer.dispose();
      renderer.domElement.remove();
    };
  }, []);

  // The room, from the floor plan.
  useEffect(() => {
    const a = api.current!;
    dispose(a.room);
    a.room.clear();
    roomGen.current++;
    a.renderer.shadowMap.needsUpdate = true;
    const built = buildRoom(p.plan);
    a.room.add(built.group);
    a.walls = built.walls; a.centre = built.centre; a.span = built.span;
    // Wall records are in the order their groups were added, after the floor pieces.
    a.wallGroups = built.group.children.filter(c => (c as THREE.Group).isGroup).slice(0, built.walls.length);
    (a.grid.material as THREE.ShaderMaterial).uniforms.centre.value.set(built.centre.x, built.centre.z);
    (a.grid.material as THREE.ShaderMaterial).uniforms.reach.value = built.span * 2.2 + 4;
    resetView();
  }, [p.plan]); // eslint-disable-line react-hooks/exhaustive-deps

  // Everything placed on the plan. Only what changed is rebuilt; the rest keeps its meshes, beam and shadow map.
  useEffect(() => {
    const a = api.current!;
    const old = built.current, next = new Map<string, { key: string; obj: THREE.Object3D }>();
    const keep = (id: string, key: string, make: () => THREE.Object3D) => {
      const had = old.get(id);
      let obj = had?.key === key ? had.obj : undefined;
      if (!obj) {
        obj = make();
        obj.traverse(o => { const m = o as THREE.Mesh; if (m.isMesh) { m.castShadow = !m.userData.noShadow; m.receiveShadow = !m.userData.noShadow; } });
        a.items.add(obj);
      }
      next.set(id, { key, obj });
      return obj;
    };
    dispose(a.marks);
    a.marks.clear();
    const { location: loc, scanID, selection } = p;
    const inScan = (id?: string) => !id || !scanID || id.toUpperCase() === scanID.toUpperCase();
    const isSel = (kind: string, id: string) => selection?.kind === kind && selection.id === id;
    const hidden = new Set(loc.display?.hiddenGroups ?? []);
    a.room.updateMatrixWorld(true);
    const surfaces = a.room.children;
    const accent = new THREE.Color(getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#1f5fd1');

    /** A ring on the floor under whatever is selected. */
    const ring = (x: number, z: number, r: number) => {
      const m = new THREE.Mesh(new THREE.RingGeometry(r, r + 0.035, 64), new THREE.MeshBasicMaterial({ color: accent.clone().multiplyScalar(1.6), transparent: true, opacity: 0.95, depthWrite: false }));
      m.rotation.x = -Math.PI / 2; m.position.set(x, 0.012, z);
      m.userData.noShadow = true; m.userData.noAO = true; m.raycast = () => {};
      a.marks.add(m);
    };

    // One scale for every unit turns the calculator's candela into screen brightness: an incident
    // reading of `reference` lux puts a mid-grey card at mid-grey.
    const pms = new Map(p.lights.filter(l => KIND_INFO[l.kind].emits).map(l => [l.id, photometrics(l)]));
    const lit = p.lights.filter(l => l.isOn && !hidden.has('lights') && (pms.get(l.id)?.peakIntensity ?? 0) > 0).map(l => ({ l, pm: pms.get(l.id)! }));
    const measured = [...(p.readings?.values() ?? [])].filter(x => x > 0);
    const brightest = measured.length ? Math.max(...measured) : Math.max(0, ...lit.map(x => illuminanceOnAxis(x.pm, 3)));
    // Fitted to the screen, the brightest reading sits a little over mid-grey.
    const reference = atStop ? keyLux(p.exposure) : brightest / 1.25;
    const scale = reference > 0 ? Math.PI / reference : 0;
    setNoLight(lit.length === 0);
    // With nothing switched on the room gets a plain work light; otherwise only a trace, so shadows keep some shape.
    a.ambient.intensity = lit.length === 0 ? 2.2 : 0.11;
    a.scene.environmentIntensity = lit.length === 0 ? 0.5 : 0.07;
    const shadowed = new Set([...lit].filter(x => x.pm.distribution === 'beam' || x.pm.distribution === 'lambertian')
      .sort((x, y) => illuminanceOnAxis(y.pm, 3) - illuminanceOnAxis(x.pm, 3)).slice(0, SHADOW_LIGHTS).map(x => x.l.id));

    for (const l of p.lights) {
      const info = KIND_INFO[l.kind];
      if (info.emits ? hidden.has('lights') : hidden.has('grip')) continue;
      const selected = isSel('light', l.id);
      if (selected) ring(l.position.x, l.position.z, 0.5);
      const pm = pms.get(l.id);
      // Like the plan: only the selected unit's beam unless the Beams layer is on. The lit room shows the rest.
      const showBeam = !!p.beams || selected;
      const hasMap = shadowed.has(l.id);
      const pan = keep(`light:${l.id}`, `${JSON.stringify(l)}|${hasMap}|${showBeam ? roomGen.current : ''}`, () => {
        const pan = new THREE.Group();
        pan.position.set(l.position.x, l.height, l.position.z);
        pan.rotation.y = -rad(l.pan);
        pan.userData.sel = { kind: 'light', id: l.id } satisfies Selection;
        const tilt = new THREE.Group();
        tilt.rotation.x = rad(l.tilt);
        pan.add(tilt);
        const support = lightSupport(l);
        if (!pm) {
          const h = board(l, tilt);
          if (support !== 'none') { bar(v(0, -h / 2, 0), v(0, -h / 2 - 0.05, 0), 0.008, DARK, pan); stand(support, l.height, -h / 2 - 0.05, pan); }
          return pan;
        }
        const color = new THREE.Color(pm.color.r, pm.color.g, pm.color.b);
        const size = head(l, pm, color, tilt);
        if (fixtureProfile(l).category === 'practical') {
          bar(v(0, -0.05, 0), v(0, -l.height + 0.02, 0), 0.008, DARK, pan);
          const base = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.12, 0.025, 28), DARK); base.position.y = -l.height + 0.0125; pan.add(base);
        } else if (support !== 'none') {
          const stud = yoke(size.half, size.below, support === 'overhead' || support === 'megaBoom', pan);
          stand(support, l.height, stud, pan);
        }
        if (!l.isOn || pm.peakIntensity <= 0) return pan;
        const z = -(size.front + 0.02);
        if (pm.distribution === 'beam' || pm.distribution === 'lambertian') {
          // With the calculator's falloff projected, the cone only needs to be wide enough to hold it.
          const half = pm.distribution === 'beam' ? Math.min(pm.beamAngle * 0.82, 80) : 78;
          const spot = new THREE.SpotLight(color, 0, 0, rad(hasMap ? half : pm.distribution === 'beam' ? Math.min(pm.beamAngle * 0.66, 80) : 80), hasMap ? 0 : pm.distribution === 'beam' ? 0.7 : 1, 2);
          spot.position.set(0, 0, z);
          spot.target.position.set(0, 0, z - 2);
          tilt.add(spot.target);
          if (hasMap) {
            spot.map = cookie(pm, l, half);
            spot.castShadow = true;
            const soft = Math.min(1, pm.emitterRadius / 0.5); // 0 = a point, 1 = a big soft source
            const res = soft > 0.5 ? 1024 : 2048;
            spot.shadow.mapSize.set(res, res);
            spot.shadow.camera.near = 0.12; spot.shadow.camera.far = 18;
            spot.shadow.bias = -0.0006; spot.shadow.normalBias = 0.025;
            spot.shadow.radius = 1.2 + soft * 3.2;
          }
          tilt.add(spot);
          pan.userData.lamp = spot;
        } else {
          const point = new THREE.PointLight(color, 0, 0, 2);
          tilt.add(point);
          pan.userData.lamp = point;
        }
        if (showBeam) {
          pan.updateMatrixWorld(true);
          const origin = new THREE.Vector3(0, 0, z).applyMatrix4(tilt.matrixWorld);
          const q = new THREE.Quaternion(); tilt.getWorldQuaternion(q);
          const b = beam(l, pm, origin, q, color, surfaces);
          if (b) { b.position.set(0, 0, z); tilt.add(b); }
        }
        return pan;
      });
      // Brightness follows the shared scale without rebuilding the unit.
      const lamp = pan.userData.lamp as THREE.Light | undefined;
      if (lamp && pm) lamp.intensity = pm.peakIntensity * scale;
    }

    if (!hidden.has('people')) for (const c of loc.characters ?? []) {
      if (!inScan(c.scanID)) continue;
      keep(`character:${c.id}`, JSON.stringify(c), () => { const g = person(c); g.userData.sel = { kind: 'character', id: c.id } satisfies Selection; return g; });
      if (isSel('character', c.id)) ring(c.position.x, c.position.z, 0.42);
    }

    if (!hidden.has('cameras')) {
      const add = (kind: 'camera' | 'shot', id: string, rig: CameraRig) => {
        const g = keep(`${kind}:${id}`, JSON.stringify(rig), () => { const g = cameraModel(rig); g.userData.sel = { kind, id } satisfies Selection; return g; });
        // You don't see the camera you are looking through (nor a shot set up on the very same spot).
        const e = eyeRef.current;
        g.visible = !e || Math.hypot(rig.position.x - e.x, rig.position.z - e.z) > 0.08;
        if (isSel(kind, id)) ring(rig.position.x, rig.position.z, 0.48);
      };
      for (const cam of loc.cameraPositions) if (inScan(cam.scanID)) add('camera', cam.id, cam.rig);
      for (const s of loc.shots) if (inScan(s.scanID)) add('shot', s.id, s.rig);
    }
    if (!hidden.has('meters')) for (const m of loc.meters ?? []) {
      if (!inScan(m.scanID)) continue;
      keep(`meter:${m.id}`, JSON.stringify(m), () => { const g = meterModel(m); g.userData.sel = { kind: 'meter', id: m.id } satisfies Selection; return g; });
      if (isSel('meter', m.id)) ring(m.position.x, m.position.z, 0.22);
    }
    for (const [id, e] of old) if (next.get(id)?.obj !== e.obj) { a.items.remove(e.obj); dispose(e.obj); }
    built.current = next;
    a.renderer.shadowMap.needsUpdate = true;

    // Reading tags: the calculator's figures, in the unit chosen in the panel.
    const tagEl = tagHost.current!;
    tagEl.replaceChildren();
    a.tags = [];
    if (lit.length) for (const m of p.meters ?? []) {
      const lux = p.readings?.get(m.key);
      const sel = 'meter' in m.source ? isSel('meter', m.source.meter) : isSel('character', m.source.character);
      if (lux === undefined || !(p.showReadings || sel)) continue;
      const el = document.createElement('div');
      el.className = 'scene3d-tag';
      const name = document.createElement('span'); name.textContent = m.name;
      const val = document.createElement('b'); val.textContent = readingShort(lux, p.exposure);
      el.append(name, val);
      tagEl.appendChild(el);
      a.tags.push({ el, at: v(m.point.x, m.point.y + ('meter' in m.source ? 0.1 : 0.2), m.point.z) });
    }
    a.invalidate(3);
  }, [p.location, p.lights, p.selection, p.plan, p.scanID, p.beams, p.readings, p.meters, p.showReadings, p.exposure, atStop, eye?.key]); // eslint-disable-line react-hooks/exhaustive-deps

  // Night mode changes the accent colour; redraw so the selection ring follows.
  useEffect(() => {
    const mo = new MutationObserver(() => api.current?.invalidate());
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    return () => mo.disconnect();
  }, []);

  const moveTo = (pos: THREE.Vector3, target: THREE.Vector3, fov = DEFAULT_FOV) => {
    const a = api.current!;
    a.camera.fov = fov; a.camera.updateProjectionMatrix();
    a.camera.position.copy(pos); a.controls.target.copy(target); a.controls.update();
    a.invalidate(4);
  };
  const resetView = () => { setEye(undefined); const a = api.current!; moveTo(a.centre.clone().add(v(a.span * 0.72, a.span * 0.86, a.span * 0.98)), a.centre.clone().setY(0.7)); };
  const topView = () => { setEye(undefined); const a = api.current!; moveTo(a.centre.clone().add(v(0, a.span * 1.75, 0.01)), a.centre); };
  // Eye: look through the selected camera (or the first one) with its lens and frame; else stand at the room's edge.
  const eyeLevel = () => {
    const a = api.current!;
    const { location: loc, selection: sel, scanID } = p;
    const inScan = (id?: string) => !id || !scanID || id.toUpperCase() === scanID.toUpperCase();
    const cams = [...loc.cameraPositions.filter(c => inScan(c.scanID)).map(c => ({ kind: 'camera', id: c.id, rig: c.rig, name: c.name })),
      ...loc.shots.filter(s => inScan(s.scanID)).map(s => ({ kind: 'shot', id: s.id, rig: s.rig, name: `Shot ${s.number}` }))];
    const cam = cams.find(c => sel?.kind === c.kind && sel.id === c.id) ?? cams[0];
    if (cam) {
      const { position, height, pan, tilt } = cam.rig;
      const dir = v(Math.sin(rad(pan)) * Math.cos(rad(tilt)), Math.sin(rad(tilt)), -Math.cos(rad(pan)) * Math.cos(rad(tilt)));
      const at = v(position.x, height, position.z);
      // Fit the camera's frame inside the view: match the lens across whichever side is tighter.
      const area = imageArea(cam.rig), ratio = area.width / area.height, view = a.camera.aspect;
      const lensV = fieldOfView(area.height, cam.rig.focalLength);
      const fov = view >= ratio ? lensV : 2 * Math.atan(Math.tan(rad(fieldOfView(area.width, cam.rig.focalLength)) / 2) / view) * 180 / Math.PI;
      setEye({ key: `${cam.kind}:${cam.id}`, x: position.x, z: position.z, ratio, label: `${cam.name} · ${Math.round(cam.rig.focalLength)} mm` });
      moveTo(at, at.clone().add(dir.multiplyScalar(2)), fov / 0.92); // a little air round the frame lines
      return;
    }
    setEye(undefined);
    const t = v(a.centre.x, 1.4, a.centre.z); moveTo(t.clone().add(v(0, 0.2, a.span * 0.45)), t);
  };
  const toggleLook = () => setAtStop(on => { try { localStorage.setItem('framescan.3d.look', on ? 'fit' : 'stop'); } catch { /* private mode */ } return !on; });

  const note = noLight ? 'No lights on: the room is shown under a plain work light.'
    : atStop ? `Preview at ${stopLabel(p.exposure.tStop)}, ISO ${p.exposure.iso}. Direct light only, no bounce or daylight. Estimate.`
    : 'Preview: brightness fitted to the screen. Direct light only, no bounce or daylight. Use the readings for exposure.';

  return (
    <div className="scene3d" ref={host}>
      <div className="scene3d-tags" ref={tagHost} aria-hidden="true" />
      {eye && (
        <div className="scene3d-frame" aria-hidden="true">
          <div className="lines" style={{ aspectRatio: String(eye.ratio), ...(eye.ratio >= (api.current?.camera.aspect ?? 1.6) ? { width: '92%' } : { height: '92%' }) }}>
            <span>{eye.label}</span>
          </div>
        </div>
      )}
      <div className="scene3d-hint"><span className="what">{note}</span><span className="how">Drag to look round · right-drag or two fingers to slide · scroll to zoom · click to select</span></div>
      <div className="scene3d-buttons">
        <button className={'tool' + (atStop ? ' on' : '')} aria-pressed={atStop} onClick={toggleLook} title="Show the brightness as the camera would expose it at the set stop, instead of fitting it to the screen">At {stopLabel(p.exposure.tStop)}</button>
        <button className="tool" onClick={resetView} title="Reset view" aria-label="Reset view"><Icon name="undo" /></button>
        <button className="tool" onClick={topView} title="View from above">Top</button>
        <button className={'tool' + (eye ? ' on' : '')} onClick={eyeLevel} title="Look through the selected camera, or the first one, with its lens and frame">Eye</button>
      </div>
    </div>
  );
}
