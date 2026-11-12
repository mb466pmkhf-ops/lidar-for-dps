// 3D view of the lighting plan, built from the synced data (the 2D floor plan, lights, people,
// cameras, meters). Like the phone's 3D view: units on their stands, beams that stop where they
// meet the room, walls between you and the room cut away.
//
// What the picture is, and isn't (Docs/DECISIONS.md D-006, D-011): each unit's brightness, colour,
// beam shape and barn-door cut come from the same photometric model as the readings, and shadows
// are real. Grip does what the calculator says it does: flags and negs cut the beam and show a faint
// sheen where they are hit, bounce boards throw light back, and a diffusion frame stops the hard beam
// and glows as a soft source on its far side (D-013). Daylight (sun through the windows, the sky as soft
// light from each window) and an LED wall use the readings' levels on the same scale (D-014). No light
// off walls, floor or ceiling. So it is a preview of the look, and the readings stay the figures to work from.
import { useEffect, useRef, useState } from 'react';
import { useTip } from './tips';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/examples/jsm/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import { RectAreaLightUniformsLib } from 'three/examples/jsm/lights/RectAreaLightUniformsLib.js';
import type { CameraRig, ExposureSettings, FloorPlan, LightFixture, Location } from '../model/types';
import { KIND_INFO, barnDoorTransmission, fixtureProfile, illuminanceOnAxis, photometrics, relativeIntensity, type ResolvedPhotometrics } from '../model/photometrics';
import { gripStandCount, lightSupport } from '../model/rigging';
import { keyLux, stopLabel } from '../model/exposure';
import { fieldOfView, imageArea } from '../model/camera';
import { boardOptics, buildScene, type MeterPoint } from '../model/calculator';
import { drapeOptics } from '../model/grip';
import type { Selection } from './PlanCanvas';
import { readingShort } from './format';
import { Icon } from './icons';
import { DARK, backdropTexture, bar, rad, v } from './scene3d/kit';
import { buildRoom, ground, type WallRecord } from './scene3d/room';
import { board, cameraModel, glowLevel, head, meterModel, person, relight, stand, yoke } from './scene3d/models';
import { beam, beamStrength, type ReachCache } from './scene3d/beam';
import { backdrop, skyTexture, type BackdropBuild } from './scene3d/stage';
import { SHEER_TRANSMISSION, backdropPlacement, curtainPass, daylightLevels, environment, floorInfo, inwardNormal, sunPlacement } from '../model/stage';
import { kelvinRGB } from '../model/kelvin';
import { DEFAULT_WINDOW_TRANSMISSION } from '../model/calculator';

RectAreaLightUniformsLib.init();

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
const SHADOW_LIGHTS = 6;
/** The calculator splits each board into this many patches a side (PATCHES in calculator.ts). */
const PATCHES = 3;
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
    if (m.isMesh) { m.geometry.dispose(); const mm = m.material as THREE.Material; if (mm.userData.release) mm.userData.release(); else if (!mm.userData.shared) mm.dispose(); }
    const s = o as THREE.SpotLight;
    if (s.isSpotLight) s.map?.dispose();
    if ((o as THREE.Light).isLight) (o as THREE.Light).shadow?.dispose(); // point lights' shadow maps too
  });
}

interface Api {
  renderer: THREE.WebGLRenderer; composer: EffectComposer; gtao: GTAOPass; bloom: UnrealBloomPass;
  scene: THREE.Scene; camera: THREE.PerspectiveCamera; controls: OrbitControls;
  room: THREE.Group; items: THREE.Group; marks: THREE.Group; walls: WallRecord[]; wallGroups: THREE.Object3D[];
  ambient: THREE.HemisphereLight; grid: THREE.Mesh;
  /** The sun, when daylight is on. */
  sun: THREE.DirectionalLight;
  sheers: { m: THREE.MeshStandardMaterial; window: import('../model/types').PlanSegment }[];
  night: THREE.Texture; sky?: { key: string; tex: THREE.Texture };
  centre: THREE.Vector3; span: number;
  tags: { el: HTMLElement; at: THREE.Vector3 }[];
  invalidate(frames?: number): void;
  /** Parts taken out of the scene, freed after the next frame is drawn. Freeing them first would let
   *  the graphics card drop shaders the replacement parts are about to use, and build them again. */
  trash: THREE.Object3D[];
  /** Shaders are being prepared off the main thread where the browser can; nothing is drawn till then. */
  warming?: boolean; warmed?: boolean;
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
  const [tipSeen, hideTip] = useTip('3d-gestures');
  const [eye, setEye] = useState<{ key: string; x: number; z: number; ratio: number; label: string }>();
  const eyeRef = useRef(eye);
  eyeRef.current = eye;
  const [noLight, setNoLight] = useState(false);
  const [warming, setWarming] = useState(false);
  // What is already built, by item: a change to one light leaves the others (and their shadow maps) alone.
  const built = useRef(new Map<string, { key: string; obj: THREE.Object3D }>());
  const roomGen = useRef(0);
  // Beam reach maps already traced, so switching a unit off and on doesn't trace its beam again.
  const reachCache = useRef<ReachCache>(new Map());
  const viewPlan = useRef<FloorPlan | undefined | null>(null);

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
    const sun = new THREE.DirectionalLight(0xfff4e6, 0);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.03; sun.shadow.radius = 1.5;
    sun.visible = false;
    scene.add(sun, sun.target);

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
    viewPlan.current = null; // a new camera needs placing

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
    api.current = { renderer, composer, gtao, bloom, scene, camera, controls, room, items, marks, walls: [], wallGroups: [], ambient, grid, sun, sheers: [], night: scene.background as THREE.Texture, centre: v(0, 1, 0), span: 6, tags: [], trash: [], invalidate };
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
      if (a.warming || pending <= 0) { streak = 0; return; }
      pending--;
      composer.render();
      for (const o of a.trash) dispose(o);
      a.trash.length = 0;
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
      for (const o of api.current?.trash ?? []) dispose(o);
      composer.dispose(); target.dispose(); renderer.dispose();
      renderer.domElement.remove();
    };
  }, []);

  // The room, from the floor plan.
  useEffect(() => {
    const a = api.current!;
    if (a.room.children.length) { const old = new THREE.Group(); old.add(...a.room.children); a.trash.push(old); }
    roomGen.current++;
    a.renderer.shadowMap.needsUpdate = true;
    const fl = floorInfo(p.location.studio?.floor);
    const built = buildRoom(p.plan, {
      floor: fl ? { colour: fl.pickColour && p.location.studio?.floorColour ? p.location.studio.floorColour : fl.colour, roughness: fl.roughness, concrete: fl.id.startsWith('concrete') } : undefined,
      lid: !!p.location.daylight?.isOn,
    });
    a.room.add(built.group);
    a.walls = built.walls; a.centre = built.centre; a.span = built.span; a.sheers = built.sheers;
    // Wall records are in the order their groups were added, after the floor pieces.
    a.wallGroups = built.group.children.filter(c => (c as THREE.Group).isGroup).slice(0, built.walls.length);
    (a.grid.material as THREE.ShaderMaterial).uniforms.centre.value.set(built.centre.x, built.centre.z);
    (a.grid.material as THREE.ShaderMaterial).uniforms.reach.value = built.span * 2.2 + 4;
    // A new room resets the view; a new floor finish or daylight switched on keeps it.
    if (viewPlan.current !== p.plan) { viewPlan.current = p.plan; resetView(); }
  }, [p.plan, p.location.studio?.floor, p.location.studio?.floorColour, !!p.location.daylight?.isOn]); // eslint-disable-line react-hooks/exhaustive-deps

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
    if (a.marks.children.length) { const old = new THREE.Group(); old.add(...a.marks.children); a.trash.push(old); }
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
    const scan = loc.scans.find(s => s.id === scanID);
    const env = environment(loc, p.plan, scan);
    const daylight = loc.daylight?.isOn ? { sun: sunPlacement(loc, scan), levels: daylightLevels(loc.daylight.sky ?? 'clear', sunPlacement(loc, scan).elevation) } : undefined;
    // Fitted to the screen, the brightest unit at full output, 3 m off, sits a little over mid-grey
    // (or the daylight or LED wall when they are brighter). It depends on the sources alone: moving a
    // person, a flag or a frame, or dimming a unit, never changes how bright the other units look.
    const brightest = Math.max(0, ...lit.map(x => illuminanceOnAxis(photometrics({ ...x.l, dimmer: 1 }), 3)),
      (daylight?.levels.skyHorizontal ?? 0) * 0.1, (env?.ledWall?.luminance ?? 0) * 1.5);
    const reference = atStop ? keyLux(p.exposure) : brightest / 1.25;
    const scale = reference > 0 ? Math.PI / reference : 0;
    const dark = lit.length === 0 && !(daylight && daylight.levels.skyHorizontal > 0) && !env?.ledWall;
    setNoLight(dark);
    // With nothing switched on the room gets a plain work light; otherwise only a trace, so shadows keep some shape.
    a.ambient.intensity = dark ? 2.2 : 0.11;
    a.scene.environmentIntensity = dark ? 0.5 : 0.07;

    // Daylight: the sun as a beam (walls, the lid and curtains shadow it), the sky as soft light from
    // each window, at the readings' levels on the same scale.
    const glass = loc.display?.windowTransmission ?? DEFAULT_WINDOW_TRANSMISSION;
    if (env?.sun) {
      const toward = v(Math.sin(rad(env.sun.bearing)) * Math.cos(rad(env.sun.elevation)), Math.sin(rad(env.sun.elevation)), -Math.cos(rad(env.sun.bearing)) * Math.cos(rad(env.sun.elevation)));
      a.sun.visible = true;
      a.sun.position.copy(a.centre).addScaledVector(toward, 30);
      a.sun.target.position.copy(a.centre).setY(0);
      // Sun patches are usually stops over the key: past about 1.5 stops they are white either way, and
      // brighter only spreads glow over the whole frame.
      a.sun.intensity = Math.min(env.sun.directNormal * glass * scale, 3 * Math.PI);
      const r = a.span * 0.9 + 2, cam = a.sun.shadow.camera;
      cam.left = -r; cam.right = r; cam.top = r; cam.bottom = -r; cam.near = 5; cam.far = 60; cam.updateProjectionMatrix();
    } else { a.sun.visible = false; a.sun.intensity = 0; }
    if (daylight) {
      const toward = v(Math.sin(rad(daylight.sun.bearing)) * Math.cos(rad(daylight.sun.elevation)), Math.sin(rad(daylight.sun.elevation)), -Math.cos(rad(daylight.sun.bearing)) * Math.cos(rad(daylight.sun.elevation)));
      const key = `${loc.daylight?.sky ?? 'clear'}|${Math.round(daylight.sun.bearing)}|${Math.round(daylight.sun.elevation)}`;
      if (a.sky?.key !== key) { a.sky?.tex.dispose(); a.sky = { key, tex: skyTexture(loc.daylight?.sky ?? 'clear', toward) }; }
      a.scene.background = a.sky.tex;
      // The sky is far brighter than any interior; past white it would only bloom over the whole picture.
      a.scene.backgroundIntensity = Math.min(0.9, Math.max(0.02, daylight.levels.skyHorizontal / Math.PI * scale));
      if (p.plan && env) for (const w of p.plan.windows) {
        const width = Math.hypot(w.b.x - w.a.x, w.b.z - w.a.z);
        if (width < 0.05) continue;
        const n = inwardNormal(w, p.plan);
        const onGlass = env.sun ? Math.max(0, -(toward.x * n.x + toward.z * n.z)) : 0;
        const glow = w.curtain === 'sheer' ? (env.sun?.directNormal ?? 0) * onGlass / Math.PI : 0;
        const lum = (env.windowLuminance + glow) * glass * curtainPass(w.curtain);
        if (!(lum > 0)) continue;
        const area = new THREE.RectAreaLight(0xf2f6ff, Math.min(lum * scale, 3 * Math.PI), width, w.height);
        area.position.set((w.a.x + w.b.x) / 2 + n.x * 0.16, w.bottom + w.height / 2, (w.a.z + w.b.z) / 2 + n.z * 0.16);
        area.lookAt(area.position.x + n.x, area.position.y, area.position.z + n.z);
        a.marks.add(area);
      }
    } else {
      a.scene.background = a.night; a.scene.backgroundIntensity = 1;
    }
    for (const sh of a.sheers) {
      const w = sh.window;
      let lum = 0;
      if (env && p.plan && daylight) {
        const n = inwardNormal(w, p.plan);
        const t = env.sun ? v(Math.sin(rad(env.sun.bearing)) * Math.cos(rad(env.sun.elevation)), 0, -Math.cos(rad(env.sun.bearing)) * Math.cos(rad(env.sun.elevation))) : v(0, 0, 0);
        lum = (env.windowLuminance + (env.sun?.directNormal ?? 0) * Math.max(0, -(t.x * n.x + t.z * n.z)) / Math.PI) * glass * SHEER_TRANSMISSION;
      }
      sh.m.emissiveIntensity = Math.min(lum * scale, 3);
    }

    // The studio backdrop.
    const bd = backdropPlacement(loc, p.plan);
    if (bd) {
      const ledColour = new THREE.Color(...Object.values(kelvinRGB(loc.studio?.kelvin ?? 6500)) as [number, number, number]);
      const holder = keep('stage:backdrop', JSON.stringify([bd, loc.studio?.kelvin]), () => {
        const g = new THREE.Group();
        const b = backdrop(bd, ledColour);
        g.add(b.group);
        g.userData.build = b;
        return g;
      });
      const b = holder.userData.build as BackdropBuild;
      const nits = env?.ledWall?.luminance ?? 0;
      if (b.ledFace) b.ledFace.emissiveIntensity = nits * scale * 1.6; // the content map averages about 0.6
      if (b.ledLight) b.ledLight.intensity = nits * scale;
    }
    // Every unit that can cast a shadow does, up to the budget, so grip blocks it (point-like units too).
    // Ranked at full output whether on or off, so switching or dimming one never moves a shadow to
    // another unit: the number of lights and shadows stays the same, and the graphics card doesn't
    // have to rebuild every surface's shader (that pause was most of a switch's delay).
    const full = (l: LightFixture) => illuminanceOnAxis(photometrics({ ...l, isOn: true, dimmer: 1 }), 3);
    const shadowed = new Set(hidden.has('lights') ? [] : p.lights.filter(l => KIND_INFO[l.kind].emits)
      .map(l => ({ id: l.id, e: full(l) })).filter(x => x.e > 0)
      .sort((x, y) => y.e - x.e).slice(0, SHADOW_LIGHTS).map(x => x.id));

    const beams: { l: LightFixture; pm: ResolvedPhotometrics; pan: THREE.Object3D }[] = [];
    for (const l of p.lights) {
      const info = KIND_INFO[l.kind];
      if (info.emits ? hidden.has('lights') : hidden.has('grip')) continue;
      const selected = isSel('light', l.id);
      if (selected) ring(l.position.x, l.position.z, 0.5);
      const pm = pms.get(l.id);
      // Like the plan: only the selected unit's beam unless the Beams layer is on. The lit room shows the rest.
      const showBeam = !!p.beams || selected;
      const hasMap = shadowed.has(l.id);
      // Switching and dimming don't rebuild the unit (nor re-trace its beam): see `relight` below.
      const shape = JSON.stringify({ ...l, isOn: undefined, dimmer: undefined });
      const pan = keep(`light:${l.id}`, `${shape}|${hasMap}`, () => {
        const pan = new THREE.Group();
        pan.position.set(l.position.x, l.height, l.position.z);
        pan.rotation.y = -rad(l.pan);
        pan.userData.sel = { kind: 'light', id: l.id } satisfies Selection;
        const tilt = new THREE.Group();
        tilt.rotation.x = rad(l.tilt);
        pan.add(tilt);
        const support = lightSupport(l);
        if (!pm) {
          pan.userData.blocks = true; // the haze of a beam stops at it
          const { lowest } = board(l, tilt, (drapeOptics(l) ?? boardOptics(l.kind)).reflectance, l.tilt);
          if (support !== 'none' && gripStandCount(l) === 2) {
            // Big frames sit on their ears between two stands and pivot there.
            for (const s of [-1, 1]) {
              const side = new THREE.Group(); side.position.x = s * (l.width / 2 + 0.07); pan.add(side);
              stand(support, l.height, -0.02, side);
            }
          } else if (support !== 'none') { bar(v(0, -lowest, 0), v(0, -lowest - 0.05, 0), 0.008, DARK, pan); stand(support, l.height, -lowest - 0.05, pan); }
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
        // An unit that is off keeps its lamp at zero, for the same reason as the shadow ranking above.
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
          point.position.set(0, 0, z);
          if (hasMap) {
            point.castShadow = true;
            point.shadow.mapSize.set(512, 512);
            point.shadow.camera.near = 0.12; point.shadow.camera.far = 18;
            point.shadow.bias = -0.0008; point.shadow.normalBias = 0.025;
            point.shadow.radius = 2.5;
          }
          tilt.add(point);
          pan.userData.lamp = point;
        }
        pan.userData.tilt = tilt; pan.userData.front = z; pan.userData.color = color; pan.userData.level = glowLevel(pm);
        return pan;
      });
      pan.userData.shape = shape;
      if (pm && l.isOn && pm.peakIntensity > 0 && showBeam) beams.push({ l, pm, pan });
      else if (pan.userData.beam) { pan.userData.tilt.remove(pan.userData.beam); a.trash.push(pan.userData.beam); pan.userData.beam = undefined; pan.userData.beamKey = undefined; }
      // On or off, output, colour and brightness on the shared scale follow without rebuilding the unit.
      const lamp = pan.userData.lamp as THREE.Light | undefined;
      if (pm && pan.userData.level !== undefined) {
        const color = new THREE.Color(pm.color.r, pm.color.g, pm.color.b);
        relight(pan, color, l.isOn, glowLevel(pm), pan.userData.level);
        pan.userData.color = color;
        if (lamp) { lamp.color.copy(color); lamp.intensity = pm.peakIntensity * scale; }
      }
    }

    // Grip as a second source, from the calculator's own patches: each lit face of a board becomes
    // a soft spot facing out of it, and the far face of a diffusion glows with what it passes.
    if (!hidden.has('grip')) {
      const optical = buildScene([...lit.map(x => x.l), ...p.lights.filter(l => !KIND_INFO[l.kind].emits)], p.plan);
      for (const b of optical.boards) {
        const obj = next.get(`light:${b.id}`)?.obj;
        // Per face, how bright each of the calculator's patches glows with light passed through it
        // (cd/m²), so a frame lit by a narrow beam shows a hot spot, not an even sheet.
        const glow: Record<number, Float32Array> = { 1: new Float32Array(PATCHES * PATCHES), [-1]: new Float32Array(PATCHES * PATCHES) };
        const patchArea = b.area / (PATCHES * PATCHES);
        for (const side of [1, -1]) {
          const mine = optical.patches.filter(q => q.board === b.id && Math.sign(q.normal.x * b.normal.x + q.normal.y * b.normal.y + q.normal.z * b.normal.z) === side);
          const total = mine.reduce((s, q) => s + q.intensity, 0);
          for (const q of total > 0 ? mine : []) {
            // A patch facing away from its unit is light that came through the frame; what is
            // reflected shows through the face's own albedo instead.
            const e = optical.emitters.find(x => x.id === q.lightID);
            if (!e || (e.position.x - q.centre.x) * q.normal.x + (e.position.y - q.centre.y) * q.normal.y + (e.position.z - q.centre.z) * q.normal.z >= 0) continue;
            const d = { x: q.centre.x - b.centre.x, y: q.centre.y - b.centre.y, z: q.centre.z - b.centre.z };
            const along = d.x * b.right.x + d.y * b.right.y + d.z * b.right.z, up = d.x * b.up.x + d.y * b.up.y + d.z * b.up.z;
            const i = Math.max(0, Math.min(PATCHES - 1, Math.floor((along + b.halfWidth) / Math.max(1e-6, 2 * b.halfWidth) * PATCHES)));
            const j = Math.max(0, Math.min(PATCHES - 1, Math.floor((up - b.lo) / Math.max(1e-6, b.hi - b.lo) * PATCHES)));
            glow[side][j * PATCHES + i] += q.intensity / patchArea;
          }
          // Every face keeps its soft spot, dark when nothing reaches it, so the count of lights in
          // the scene doesn't change when a unit is switched (see the shadow ranking above).
          const lit = total * scale >= 1e-4;
          const c = lit ? mine.reduce((s, q) => s.add(v(q.centre.x, q.centre.y, q.centre.z).multiplyScalar(q.intensity / total)), v(0, 0, 0)) : v(b.centre.x, b.centre.y, b.centre.z);
          const n = v(b.normal.x, b.normal.y, b.normal.z).multiplyScalar(side);
          const spot = new THREE.SpotLight(0xffffff, lit ? total * scale : 0, 0, rad(84), 1, 2);
          spot.position.copy(c).addScaledVector(n, 0.03);
          spot.target.position.copy(c).addScaledVector(n, 1);
          a.marks.add(spot, spot.target);
        }
        obj?.traverse(o => {
          const m = o as THREE.Mesh;
          if (!m.isMesh || !m.userData.face) return;
          const side = m.userData.face as number;
          const mm = m.material as THREE.MeshStandardMaterial;
          const peak = Math.max(...glow[side]);
          mm.emissiveMap?.dispose();
          mm.emissiveMap = null;
          mm.emissiveIntensity = 0;
          if (peak * scale > 1e-4) {
            // Face +1 is turned round, so its texture runs the other way along the board.
            const data = new Uint8Array(PATCHES * PATCHES * 4);
            for (let j = 0; j < PATCHES; j++) for (let i = 0; i < PATCHES; i++) {
              const g = glow[side][j * PATCHES + (side > 0 ? PATCHES - 1 - i : i)] / peak;
              const c = Math.round(255 * g);
              data.set([c, c, c, 255], (j * PATCHES + i) * 4);
            }
            const tex = new THREE.DataTexture(data, PATCHES, PATCHES, THREE.RGBAFormat);
            tex.magFilter = tex.minFilter = THREE.LinearFilter;
            tex.needsUpdate = true;
            mm.emissive.setScalar(1);
            mm.emissiveMap = tex;
            mm.emissiveIntensity = peak * scale;
          }
          mm.needsUpdate = true;
        });
      }
    }

    if (!hidden.has('people')) for (const c of loc.characters ?? []) {
      if (!inScan(c.scanID)) continue;
      keep(`character:${c.id}`, JSON.stringify(c), () => { const g = person(c); g.userData.sel = { kind: 'character', id: c.id } satisfies Selection; g.userData.blocks = true; return g; });
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
    for (const [id, e] of old) if (next.get(id)?.obj !== e.obj) { a.items.remove(e.obj); a.trash.push(e.obj); }
    built.current = next;

    // Beams last, once everything that can stand in one is built: the haze stops at the room, at
    // flags, frames and boards, and at people, so a flagged beam shows nothing past the flag.
    // A beam is redrawn when its unit, the room or anything in the way changes.
    const blockers = [...surfaces, ...[...next.values()].map(e => e.obj).filter(o => o.userData.blocks)];
    const inTheWay = `${roomGen.current}|${JSON.stringify(p.lights.filter(l => !KIND_INFO[l.kind].emits))}|${JSON.stringify((loc.characters ?? []).map(c => [c.position, c.height, c.posture, c.facing]))}`;
    for (const { l, pm, pan } of beams) {
      const key = `${pan.userData.shape}|${inTheWay}`;
      if (pan.userData.beamKey === key) {
        const u = pan.userData.beam?.userData.uniforms;
        if (u) { u.color.value.copy(pan.userData.color); u.strength.value = beamStrength(pm); }
        continue;
      }
      const tilt = pan.userData.tilt as THREE.Object3D;
      if (pan.userData.beam) { tilt.remove(pan.userData.beam); a.trash.push(pan.userData.beam); }
      a.items.updateMatrixWorld(true);
      const origin = new THREE.Vector3(0, 0, pan.userData.front).applyMatrix4(tilt.matrixWorld);
      const q = new THREE.Quaternion(); tilt.getWorldQuaternion(q);
      const b = beam(l, pm, origin, q, pan.userData.color, blockers.filter(o => o !== pan), { store: reachCache.current, key: inTheWay });
      if (b) { b.position.set(0, 0, pan.userData.front); tilt.add(b); }
      pan.userData.beam = b; pan.userData.beamKey = key;
    }
    a.renderer.shadowMap.needsUpdate = true;
    // The first time round, prepare every surface's shader before drawing. Where the browser can
    // compile in the background (KHR_parallel_shader_compile) the window stays responsive meanwhile
    // instead of freezing on the first frame.
    if (!a.warmed) {
      a.warmed = true; a.warming = true; setWarming(true);
      const done = () => { if (!a.warming) return; a.warming = false; setWarming(false); a.invalidate(3); };
      a.renderer.compileAsync(a.scene, a.camera).then(done, done);
      setTimeout(done, 5000); // never wait longer than this: drawing compiles whatever is left
    }

    // Reading tags: the calculator's figures, in the unit chosen in the panel.
    const tagEl = tagHost.current!;
    tagEl.replaceChildren();
    a.tags = [];
    if (!dark) for (const m of p.meters ?? []) {
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

  const what = p.location.daylight?.isOn ? 'Units and grip, sun and sky through the windows; no light off the walls.' : 'Units and grip only, no light off the walls, no daylight.';
  const note = warming ? 'Preparing the 3D view…' : noLight ? 'No lights on: the room is shown under a plain work light.'
    : atStop ? `Preview at ${stopLabel(p.exposure.tStop)}, ISO ${p.exposure.iso}. ${what} Estimate.`
    : `Preview: brightness fitted to the strongest source. ${what} Use the readings for exposure.`;

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
      <div className="scene3d-hint">
        <span className="what">{note}</span>
        {!tipSeen && <span className="how">Drag to look round · right-drag or two fingers to slide · scroll to zoom · click to select <button className="linkish" onClick={hideTip}>Got it</button></span>}
      </div>
      <div className="scene3d-buttons">
        <button className={'tool' + (atStop ? ' on' : '')} aria-pressed={atStop} onClick={toggleLook} title="Show the brightness as the camera would expose it at the set stop, instead of fitting it to the screen">At {stopLabel(p.exposure.tStop)}</button>
        <button className="tool" onClick={resetView} title="Reset view" aria-label="Reset view"><Icon name="undo" /></button>
        <button className="tool" onClick={topView} title="View from above">Top</button>
        <button className={'tool' + (eye ? ' on' : '')} onClick={eyeLevel} title="Look through the selected camera, or the first one, with its lens and frame">Eye</button>
      </div>
    </div>
  );
}
