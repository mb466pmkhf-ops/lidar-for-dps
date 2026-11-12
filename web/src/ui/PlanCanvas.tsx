// Top-down plan: the scan's walls, openings and set pieces, with cameras, lights, grip, people and
// meters on top. Same coordinates as the phone (x right, z down, bearing 0° = up, clockwise).
import { useEffect, useMemo, useRef, useState, type PointerEvent as RPointerEvent, type ReactElement } from "react";
import type { CameraRig, ExposureSettings, FloorPlan, LightFixture, LightMeter, Location, PlanPoint, PlanRect, PrevisCharacter } from '../model/types';
import { KIND_INFO, distanceForLux, photometrics } from '../model/photometrics';
import { planDist, unitBearing, type Scene, grid, meterNormal, meterCameras, vec } from '../model/calculator';
import { horizontalFOV } from '../model/camera';
import { keyLux } from '../model/exposure';
import { cssRGB } from '../model/kelvin';
import { planReach } from '../model/rigging';
import { skinRGB } from '../model/characters';
import { readingShort, stopColor, stopLegend } from './format';
import { setPieceName } from '../model/setPieces';

export type Selection =
  | { kind: 'light'; id: string }
  | { kind: 'character'; id: string }
  | { kind: 'meter'; id: string }
  | { kind: 'shot'; id: string }
  | { kind: 'camera'; id: string }
  | { kind: 'object'; id: string }
  /** A door, window or opening in a wall. */
  | { kind: 'opening'; id: string };

export type DragTarget = Selection & { part: 'body' | 'rotate' };

interface Props {
  location: Location;
  plan?: FloorPlan;
  scanID?: string;
  lights: LightFixture[];
  scene: Scene;
  readings: Map<string, number>;
  exposure: ExposureSettings;
  selection?: Selection;
  showLuxMap: boolean;
  /** Information layers on top of the essentials: beams, views, readings, dimensions, names. */
  layers: Set<string>;
  placing: boolean;
  hint: string;
  onSelect(s?: Selection): void;
  onPlace(p: PlanPoint): void;
  onDragStart(t: DragTarget): void;
  onDrag(t: DragTarget, p: PlanPoint): void;
  onDragEnd(): void;
}

interface View { cx: number; cz: number; scale: number }

function contentBounds(location: Location, plan: FloorPlan | undefined, lights: LightFixture[]): PlanRect {
  const pts: PlanPoint[] = [];
  if (plan && (plan.walls.length || plan.floorPolygons.length)) {
    pts.push({ x: plan.bounds.minX, z: plan.bounds.minZ }, { x: plan.bounds.maxX, z: plan.bounds.maxZ });
  }
  lights.forEach(l => pts.push(l.position));
  (location.characters ?? []).forEach(c => pts.push(c.position));
  location.shots.forEach(s => pts.push(s.rig.position));
  location.cameraPositions.forEach(c => pts.push(c.rig.position));
  if (!pts.length) return { minX: -3, minZ: -3, maxX: 3, maxZ: 3 };
  const r = { minX: Infinity, minZ: Infinity, maxX: -Infinity, maxZ: -Infinity };
  for (const p of pts) { r.minX = Math.min(r.minX, p.x); r.maxX = Math.max(r.maxX, p.x); r.minZ = Math.min(r.minZ, p.z); r.maxZ = Math.max(r.maxZ, p.z); }
  return { minX: r.minX - 0.5, minZ: r.minZ - 0.5, maxX: r.maxX + 0.5, maxZ: r.maxZ + 0.5 };
}

const sameSel = (a?: Selection, b?: Selection) => !!a && !!b && a.kind === b.kind && a.id === b.id;

export function PlanCanvas(props: Props) {
  const { location, plan, lights, scene, readings, exposure, selection, showLuxMap, scanID, layers } = props;
  const wrap = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 800, h: 600 });
  const [view, setView] = useState<View | null>(null);
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const gesture = useRef<{ kind: 'pan'; start: View; x: number; y: number; moved: boolean; tap?: Selection } | { kind: 'drag'; target: DragTarget } | { kind: 'pinch'; start: View; dist: number; mid: { x: number; y: number } } | null>(null);

  const bounds = useMemo(() => contentBounds(location, plan, lights), [location.id, plan]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setSize({ w: el.clientWidth, h: el.clientHeight }));
    ro.observe(el);
    setSize({ w: el.clientWidth, h: el.clientHeight });
    return () => ro.disconnect();
  }, []);

  const fit = () => {
    const w = bounds.maxX - bounds.minX, d = bounds.maxZ - bounds.minZ;
    setView({ cx: (bounds.minX + bounds.maxX) / 2, cz: (bounds.minZ + bounds.maxZ) / 2, scale: Math.max(20, Math.min((size.w - 80) / w, (size.h - 80) / d)) });
  };
  // Fit the room on open and whenever the window resizes, until the user pans or zooms.
  const userMoved = useRef(false);
  useEffect(() => { userMoved.current = false; }, [location.id, plan]);
  useEffect(() => { if (size.w > 0 && !userMoved.current) fit(); }, [location.id, plan, size.w, size.h]); // eslint-disable-line react-hooks/exhaustive-deps

  const v = view ?? { cx: 0, cz: 0, scale: 60 };
  const sx = (x: number) => (x - v.cx) * v.scale + size.w / 2;
  const sy = (z: number) => (z - v.cz) * v.scale + size.h / 2;
  const toPlan = (clientX: number, clientY: number): PlanPoint => {
    const r = wrap.current!.getBoundingClientRect();
    return { x: (clientX - r.left - size.w / 2) / v.scale + v.cx, z: (clientY - r.top - size.h / 2) / v.scale + v.cz };
  };
  const pt = (p: PlanPoint) => `${sx(p.x)},${sy(p.z)}`;

  const zoomAt = (factor: number, clientX?: number, clientY?: number) => {
    userMoved.current = true;
    setView(cur => {
      const c = cur ?? v;
      const scale = Math.min(600, Math.max(8, c.scale * factor));
      if (clientX === undefined || clientY === undefined || !wrap.current) return { ...c, scale };
      const r = wrap.current.getBoundingClientRect();
      const px = (clientX - r.left - size.w / 2), py = (clientY - r.top - size.h / 2);
      const wx = px / c.scale + c.cx, wz = py / c.scale + c.cz;
      return { scale, cx: wx - px / scale, cz: wz - py / scale };
    });
  };

  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      // Trackpad pinch arrives as ctrl+wheel; a mouse wheel moves in big whole steps. Both zoom.
      // Two-finger trackpad scrolling pans.
      const mouseWheel = e.deltaMode !== 0 || (e.deltaX === 0 && Number.isInteger(e.deltaY) && Math.abs(e.deltaY) >= 50);
      if (e.ctrlKey) zoomAt(Math.exp(-e.deltaY * 0.01), e.clientX, e.clientY);
      else if (mouseWheel) zoomAt(Math.exp(-Math.sign(e.deltaY) * 0.15), e.clientX, e.clientY);
      else { userMoved.current = true; setView(c => { const b = c ?? v; return { ...b, cx: b.cx + e.deltaX / b.scale, cz: b.cz + e.deltaY / b.scale }; }); }
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  });

  // MARK: Pointer handling

  /** `tap`: what a click (no drag) selects, for set pieces that only move once selected. */
  const down = (e: RPointerEvent, target?: DragTarget, tap?: Selection) => {
    (e.currentTarget as Element).setPointerCapture?.(e.pointerId);
    wrap.current?.setPointerCapture(e.pointerId);
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    e.stopPropagation();
    if (pointers.current.size === 2) {
      const [a, b] = [...pointers.current.values()];
      if (gesture.current?.kind === 'drag') props.onDragEnd();
      gesture.current = { kind: 'pinch', start: v, dist: Math.hypot(a.x - b.x, a.y - b.y), mid: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 } };
      return;
    }
    if (target && !props.placing) {
      props.onSelect(target);
      props.onDragStart(target);
      gesture.current = { kind: 'drag', target };
    } else {
      gesture.current = { kind: 'pan', start: v, x: e.clientX, y: e.clientY, moved: false, tap };
    }
  };

  const move = (e: RPointerEvent) => {
    if (!pointers.current.has(e.pointerId)) return;
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    const g = gesture.current;
    if (!g) return;
    if (g.kind === 'pinch' && pointers.current.size >= 2) {
      const [a, b] = [...pointers.current.values()];
      const dist = Math.hypot(a.x - b.x, a.y - b.y);
      const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      const scale = Math.min(600, Math.max(8, g.start.scale * dist / g.dist));
      setView({ scale, cx: g.start.cx - (mid.x - g.mid.x) / scale, cz: g.start.cz - (mid.y - g.mid.y) / scale });
    } else if (g.kind === 'pan') {
      const dx = e.clientX - g.x, dy = e.clientY - g.y;
      if (Math.hypot(dx, dy) > 4) g.moved = true;
      if (g.moved) { userMoved.current = true; setView({ ...g.start, cx: g.start.cx - dx / g.start.scale, cz: g.start.cz - dy / g.start.scale }); }
    } else if (g.kind === 'drag') {
      props.onDrag(g.target, toPlan(e.clientX, e.clientY));
    }
  };

  const up = (e: RPointerEvent) => {
    pointers.current.delete(e.pointerId);
    const g = gesture.current;
    if (pointers.current.size > 0) return;
    gesture.current = null;
    if (g?.kind === 'drag') props.onDragEnd();
    if (g?.kind === 'pan' && !g.moved) {
      if (props.placing) props.onPlace(toPlan(e.clientX, e.clientY));
      else props.onSelect(g.tap);
    }
  };

  // MARK: Lux map

  const luxMap = useMemo(() => {
    if (!showLuxMap || !lights.length) return undefined;
    const b = plan && plan.walls.length ? plan.bounds : bounds;
    const w = b.maxX - b.minX, d = b.maxZ - b.minZ;
    const cell = Math.max(0.15, Math.max(w, d) / 48);
    const cols = Math.max(4, Math.ceil(w / cell)), rows = Math.max(4, Math.ceil(d / cell));
    const cams = meterCameras(location);
    const key = keyLux(exposure);
    const values = grid(b, cols, rows, 1.5, scene, p => (cams.length ? meterNormal('camera', 0, p, cams) : vec(0, 1, 0)));
    const canvas = document.createElement('canvas');
    canvas.width = cols; canvas.height = rows;
    const ctx = canvas.getContext('2d')!;
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
      const val = values[r * cols + c];
      const color = stopColor(val > 0 ? Math.log2(val / key) : -10);
      if (!color) continue;
      ctx.fillStyle = color;
      ctx.fillRect(c, r, 1, 1);
    }
    return { href: canvas.toDataURL(), b };
  }, [showLuxMap, scene, exposure, plan, bounds, location, lights.length]);

  // MARK: Drawing helpers

  const inScan = (id?: string) => !id || !scanID || id === scanID;
  const key = keyLux(exposure);
  // Labels are collected while the items draw, then placed together on top (placedLabels) so two
  // names never print over each other: a label that would collide moves up or down a line, and a
  // minor one that still can't fit is left out. Selected items and readings always show.
  const labels: { text: string; x: number; y: number; strong: boolean }[] = [];
  // Labels set off from their item (lights, cameras, people) also keep clear of every item's glyph.
  const glyphs: { x: number; y: number }[] = [];
  const labelFor = (text: string, p: PlanPoint, dy = -16, strong = false) => {
    labels.push({ text, x: sx(p.x), y: sy(p.z) + dy, strong });
    if (Math.abs(dy) >= 10 && !glyphs.some(g => g.x === sx(p.x) && g.y === sy(p.z))) glyphs.push({ x: sx(p.x), y: sy(p.z) });
    return null;
  };
  const placedLabels = () => {
    const boxes: { x0: number; x1: number; y0: number; y1: number }[] = glyphs.map(g => ({ x0: g.x - 13, x1: g.x + 13, y0: g.y - 13, y1: g.y + 13 }));
    const hits = (b: typeof boxes[number]) => boxes.some(o => b.x0 < o.x1 && b.x1 > o.x0 && b.y0 < o.y1 && b.y1 > o.y0);
    const out: ReactElement[] = [];
    [...labels].sort((a, b) => Number(b.strong) - Number(a.strong)).forEach((l, i) => {
      const w = l.text.length * 6.6 + 8;
      const boxAt = (y: number) => ({ x0: l.x - w / 2, x1: l.x + w / 2, y0: y - 12, y1: y + 4 });
      const y = [0, -15, 15, -30, 30].map(d => l.y + d).find(c => !hits(boxAt(c))) ?? (l.strong ? l.y : undefined);
      if (y === undefined) return;
      boxes.push(boxAt(y));
      out.push(<text key={i} x={l.x} y={y} textAnchor="middle" className="plan-label" fontSize={12} fill={l.strong ? 'var(--ink)' : 'var(--ink2)'} stroke="var(--paper)" strokeWidth={4} paintOrder="stroke" fontFamily="Poppins, system-ui" fontWeight={400}>{l.text}</text>);
    });
    return <g pointerEvents="none">{out}</g>;
  };

  const rotateHandle = (s: Selection, p: PlanPoint, bearing: number, r = 1.0) => {
    const h = { x: p.x + unitBearing(bearing).x * r, z: p.z + unitBearing(bearing).z * r };
    return (
      <g>
        <line x1={sx(p.x)} y1={sy(p.z)} x2={sx(h.x)} y2={sy(h.z)} stroke="var(--accent)" strokeWidth={1} strokeDasharray="3 3" pointerEvents="none" />
        <circle cx={sx(h.x)} cy={sy(h.z)} r={9} fill="var(--accent)" stroke="var(--paper)" strokeWidth={2} style={{ cursor: 'grab' }}
          onPointerDown={e => down(e, { ...s, part: 'rotate' })} aria-label="Rotate" />
      </g>
    );
  };

  const drawRig = (s: Selection, rig: CameraRig, label: string) => {
    const sel = sameSel(selection, s);
    const fov = horizontalFOV(rig);
    const reach = 3.2;
    // The view stops at the walls, like the beams, so frames don't spill outside the room.
    const wedge = [pt(rig.position)];
    for (let i = 0; i <= 16; i++) {
      const bb = rig.pan - fov / 2 + (fov * i) / 16;
      const r = planReach(rig.position, bb, reach, plan);
      wedge.push(pt({ x: rig.position.x + unitBearing(bb).x * r, z: rig.position.z + unitBearing(bb).z * r }));
    }
    const body = 10;
    return (
      <g key={s.kind + s.id}>
        {(layers.has('views') || sel) && <polygon points={wedge.join(' ')} fill="var(--floor)" stroke="var(--ink3)" strokeWidth={1} pointerEvents="none" />}
        <g transform={`translate(${sx(rig.position.x)},${sy(rig.position.z)}) rotate(${rig.pan})`} style={{ cursor: 'move' }} onPointerDown={e => down(e, { ...s, part: 'body' })}>
          {/* Tripod legs, battery, body with top handle, lens and matte box. Forward is up (−y). */}
          <path d="M0,0 L-13,13 M0,0 L13,13 M0,0 L0,-17" stroke="var(--ink3)" strokeWidth={2} strokeLinecap="round" />
          <circle cx={-13} cy={13} r={2} fill="var(--ink3)" /><circle cx={13} cy={13} r={2} fill="var(--ink3)" />
          <rect x={-5} y={body * 0.9} width={10} height={6} rx={1.5} fill="var(--ink2)" />
          <rect x={-body * 0.8} y={-body * 0.9} width={body * 1.6} height={body * 1.8} rx={3} fill={sel ? 'var(--accent)' : 'var(--ink)'} stroke="var(--paper)" strokeWidth={1.5} />
          <rect x={body * 0.8} y={-5} width={3} height={10} rx={1.5} fill={sel ? 'var(--accent)' : 'var(--ink)'} />
          <rect x={-5} y={-body * 0.9 - 8} width={10} height={8} fill={sel ? 'var(--accent)' : 'var(--ink)'} stroke="var(--paper)" strokeWidth={1} />
          <polygon points={`-5,${-body * 0.9 - 8} 5,${-body * 0.9 - 8} 9,${-body * 0.9 - 14} -9,${-body * 0.9 - 14}`} fill={sel ? 'var(--accent)' : 'var(--ink)'} stroke="var(--paper)" strokeWidth={1} />
          <circle r={3} fill="none" stroke="var(--paper)" strokeWidth={1.5} />
          <circle r={body * 1.6} fill="transparent" />
        </g>
        {labelFor(label, rig.position, 26, sel)}
        {sel && rotateHandle(s, rig.position, rig.pan, 1.2)}
      </g>
    );
  };

  const drawLight = (l: LightFixture) => {
    const s: Selection = { kind: 'light', id: l.id };
    const sel = sameSel(selection, s);
    const info = KIND_INFO[l.kind];
    const g: ReactElement[] = [];
    const cx = sx(l.position.x), cy = sy(l.position.z);
    if (info.emits) {
      const pm = photometrics(l);
      const col = cssRGB(pm.color, 1);
      if (l.isOn && pm.peakIntensity > 0 && (layers.has('beams') || sel)) {
        const throwM = Math.min(9, Math.max(0.8, distanceForLux(pm, key / 2) ?? 0.8));
        const spread = Math.min(pm.distribution === 'beam' ? pm.beamAngle : 150, 340);
        if (spread >= 300) {
          g.push(<circle key="beam" cx={cx} cy={cy} r={throwM * v.scale} fill={cssRGB(pm.color, 0.07)} stroke={cssRGB(pm.color, 0.35)} strokeDasharray="4 4" pointerEvents="none" />);
        } else {
          // Each ray stops at the first wall, window or closed door, so beams stay in the room.
          const steps = 24, pts = [pt(l.position)];
          for (let i = 0; i <= steps; i++) {
            const bb = l.pan - spread / 2 + (spread * i) / steps;
            const r = planReach(l.position, bb, throwM, plan);
            pts.push(pt({ x: l.position.x + unitBearing(bb).x * r, z: l.position.z + unitBearing(bb).z * r }));
          }
          g.push(<polygon key="beam" points={pts.join(' ')} fill={cssRGB(pm.color, 0.10)} stroke={cssRGB(pm.color, 0.45)} strokeWidth={1} pointerEvents="none" />);
        }
      }
      const r = Math.max(11, (l.width / 2) * v.scale);
      const face = l.isOn ? col : 'var(--off)';
      const edge = sel ? 'var(--accent)' : 'var(--paper)';
      const edgeW = sel ? 2.5 : 1.5;
      g.push(
        <g key="body" transform={`translate(${cx},${cy}) rotate(${l.pan})`} style={{ cursor: 'move' }} onPointerDown={e => down(e, { ...s, part: 'body' })}>
          {/* Stand legs under the unit; the face of the unit points up (−y). */}
          {l.kind !== 'practical' && <>
            <path d="M0,4 L-11,15 M0,4 L11,15 M0,4 L0,-10" stroke="var(--ink3)" strokeWidth={2} strokeLinecap="round" />
            <circle cx={-11} cy={15} r={2} fill="var(--ink3)" /><circle cx={11} cy={15} r={2} fill="var(--ink3)" />
          </>}
          {l.kind === 'tube'
            ? <rect x={-r} y={-4} width={r * 2} height={6} rx={3} fill={face} stroke={edge} strokeWidth={edgeW} />
            : l.kind === 'softbox'
              ? <>
                  <rect x={-6} y={2} width={12} height={10} rx={2} fill="var(--ink)" />
                  <polygon points={`${-r},-8 ${r},-8 6,2 -6,2`} fill={face} stroke={edge} strokeWidth={edgeW} strokeLinejoin="round" />
                  <path d={`M${-r * 0.5},-8 L-3,2 M0,-8 L0,2 M${r * 0.5},-8 L3,2`} stroke="var(--paper)" strokeWidth={1} opacity={0.7} />
                  <line x1={-r} y1={-9} x2={r} y2={-9} stroke="var(--ink)" strokeWidth={2.5} strokeLinecap="round" />
                </>
              : l.kind === 'ledPanel'
                ? <>
                    <rect x={-r} y={-6} width={r * 2} height={10} rx={2} fill="var(--ink)" stroke={edge} strokeWidth={edgeW} />
                    <rect x={-r + 2} y={-6} width={r * 2 - 4} height={4} fill={face} />
                    <path d={`M${-r},-6 L${-r - 5},-12 M${r},-6 L${r + 5},-12`} stroke="var(--ink)" strokeWidth={2} strokeLinecap="round" />
                  </>
                : l.kind === 'spaceLight' || l.kind === 'practical'
                  ? <><circle r={10} fill={face} stroke={edge} strokeWidth={edgeW} /><circle r={4} fill="none" stroke="var(--paper)" strokeWidth={1} opacity={0.7} /></>
                  : <>
                      <rect x={-8} y={-6} width={16} height={15} rx={3} fill="var(--ink)" stroke={edge} strokeWidth={edgeW} />
                      <path d="M-8,0 H8 M-8,4 H8" stroke="var(--ink3)" strokeWidth={1} />
                      <path d="M-7,-6 A8,6 0 0 1 7,-6 Z" fill={face} stroke="var(--paper)" strokeWidth={1} />
                      <path d="M-8,-6 L-13,-14 M8,-6 L13,-14" stroke="var(--ink)" strokeWidth={2.5} strokeLinecap="round" />
                    </>}
          <circle r={Math.max(r, 14)} fill="transparent" />
        </g>,
      );
    } else {
      const half = (l.width / 2) * v.scale;
      const fill = l.kind === 'bounce' ? 'var(--paper)' : l.kind === 'negative' ? '#000' : l.kind === 'flag' ? 'var(--ink2)' : 'var(--occ)';
      g.push(
        <g key="body" transform={`translate(${cx},${cy}) rotate(${l.pan})`} style={{ cursor: 'move' }} onPointerDown={e => down(e, { ...s, part: 'body' })}>
          <rect x={-Math.max(half, 8)} y={-3} width={Math.max(half, 8) * 2} height={6} fill={fill} stroke={sel ? 'var(--accent)' : 'var(--ink3)'} strokeWidth={sel ? 2 : 1} strokeDasharray={l.kind === 'diffusion' ? '4 3' : undefined} />
          <line x1={0} y1={-3} x2={0} y2={-12} stroke={sel ? 'var(--accent)' : 'var(--ink3)'} strokeWidth={1.5} />
          <rect x={-Math.max(half, 14)} y={-12} width={Math.max(half, 14) * 2} height={24} fill="transparent" />
        </g>,
      );
    }
    g.push(<g key="label">{labelFor(l.name, l.position, -16, sel)}</g>);
    if (sel) g.push(<g key="rot">{rotateHandle(s, l.position, l.pan)}</g>);
    return <g key={l.id} opacity={info.emits && !l.isOn ? 0.55 : 1}>{g}</g>;
  };

  const drawCharacter = (c: PrevisCharacter) => {
    const s: Selection = { kind: 'character', id: c.id };
    const sel = sameSel(selection, s);
    const r = Math.max(10, 0.22 * (0.8 + c.build * 0.5) * v.scale);
    const reading = readings.get('c:' + c.id);
    return (
      <g key={c.id}>
        <g transform={`translate(${sx(c.position.x)},${sy(c.position.z)}) rotate(${c.facing})`} style={{ cursor: 'move' }} onPointerDown={e => down(e, { ...s, part: 'body' })}>
          <ellipse rx={r} ry={r * 0.62} fill={skinRGB[c.skinTone - 1] ?? skinRGB[2]} stroke={sel ? 'var(--accent)' : 'var(--paper)'} strokeWidth={sel ? 2.5 : 1.5} />
          <polygon points={`-5,${-r * 0.55} 5,${-r * 0.55} 0,${-r * 0.55 - 9}`} fill={sel ? 'var(--accent)' : 'var(--ink2)'} />
        </g>
        {labelFor(c.name, c.position, -r - 6, sel)}
        {reading !== undefined && lights.length > 0 && (layers.has('readings') || sel) && labelFor(readingShort(reading, exposure), c.position, r + 18, true)}
        {sel && rotateHandle(s, c.position, c.facing, 0.9)}
      </g>
    );
  };

  const drawMeter = (m: LightMeter) => {
    const s: Selection = { kind: 'meter', id: m.id };
    const sel = sameSel(selection, s);
    const reading = readings.get('m:' + m.id);
    return (
      <g key={m.id}>
        <g transform={`translate(${sx(m.position.x)},${sy(m.position.z)})`} style={{ cursor: 'move' }} onPointerDown={e => down(e, { ...s, part: 'body' })}>
          <rect x={-7} y={-7} width={14} height={14} transform="rotate(45)" fill={sel ? 'var(--accent)' : 'var(--paper)'} stroke="var(--ink)" strokeWidth={1.5} />
          <circle r={14} fill="transparent" />
        </g>
        {labelFor(m.name, m.position, -14, sel)}
        {reading !== undefined && lights.length > 0 && (layers.has('readings') || sel) && labelFor(readingShort(reading, exposure), m.position, 24, true)}
      </g>
    );
  };

  // MARK: Scale bar & grid

  const gridStep = v.scale > 120 ? 0.5 : v.scale > 30 ? 1 : 5;
  const gridLines: ReactElement[] = [];
  const x0 = Math.floor((v.cx - size.w / 2 / v.scale) / gridStep) * gridStep;
  const z0 = Math.floor((v.cz - size.h / 2 / v.scale) / gridStep) * gridStep;
  for (let x = x0; x < v.cx + size.w / 2 / v.scale; x += gridStep) gridLines.push(<line key={'x' + x} x1={sx(x)} y1={0} x2={sx(x)} y2={size.h} stroke="var(--grid)" />);
  for (let z = z0; z < v.cz + size.h / 2 / v.scale; z += gridStep) gridLines.push(<line key={'z' + z} x1={0} y1={sy(z)} x2={size.w} y2={sy(z)} stroke="var(--grid)" />);

  const hidden = new Set(location.display?.hiddenGroups ?? []);
  const scan = location.scans.find(s => s.id === scanID);

  return (
    <div className="plan-wrap" ref={wrap} onPointerDown={e => down(e)} onPointerMove={move} onPointerUp={up} onPointerCancel={up}
      style={{ cursor: props.placing ? 'crosshair' : 'default' }}>
      <svg width={size.w} height={size.h} role="img" aria-label="Lighting plan">
        {gridLines}
        {luxMap && (
          <image href={luxMap.href} x={sx(luxMap.b.minX)} y={sy(luxMap.b.minZ)} width={(luxMap.b.maxX - luxMap.b.minX) * v.scale} height={(luxMap.b.maxZ - luxMap.b.minZ) * v.scale}
            opacity={0.55} preserveAspectRatio="none" style={{ imageRendering: 'auto' }} pointerEvents="none" />
        )}
        {plan && !hidden.has('floors') && plan.floorPolygons.map((poly, i) => <polygon key={'f' + i} points={poly.map(pt).join(' ')} fill="var(--floor)" pointerEvents="none" />)}
        {plan && plan.occupancy.length > 0 && plan.occupancy.map((p, i) => <rect key={'o' + i} x={sx(p.x)} y={sy(p.z)} width={plan.occupancyCellSize * v.scale} height={plan.occupancyCellSize * v.scale} fill="var(--occ)" pointerEvents="none" />)}
        {plan && !hidden.has('furniture') && plan.objects.map(o => {
          const s: Selection = { kind: 'object', id: o.id };
          const sel = sameSel(selection, s);
          // A set piece is selected by a click and moved once selected, so dragging across a
          // room full of furniture still pans the plan.
          return (
            <g key={o.id} transform={`translate(${sx(o.center.x)},${sy(o.center.z)}) rotate(${o.rotation * 180 / Math.PI})`}
              style={{ cursor: sel ? 'move' : 'pointer' }} onPointerDown={e => down(e, sel ? { ...s, part: 'body' } : undefined, s)}>
              <rect x={-o.width / 2 * v.scale} y={-o.depth / 2 * v.scale} width={o.width * v.scale} height={o.depth * v.scale} fill="var(--floor)"
                stroke={sel ? 'var(--accent)' : 'var(--ink3)'} strokeWidth={sel ? 2 : 1} strokeDasharray={o.byHand && !sel ? '5 3' : undefined} />
            </g>
          );
        })}
        {plan && !hidden.has('furniture') && plan.objects.map(o => (layers.has('names') || sameSel(selection, { kind: 'object', id: o.id })) && <g key={'ol' + o.id}>{labelFor(setPieceName(o), o.center, 4, sameSel(selection, { kind: 'object', id: o.id }))}</g>)}
        {plan && !hidden.has('walls') && plan.walls.map(w => <line key={w.id} x1={sx(w.a.x)} y1={sy(w.a.z)} x2={sx(w.b.x)} y2={sy(w.b.z)} stroke="var(--wall)" strokeWidth={Math.max(3, 0.1 * v.scale)} strokeLinecap="square" pointerEvents="none" />)}
        {plan && !hidden.has('windows') && plan.windows.map(w => <line key={w.id} x1={sx(w.a.x)} y1={sy(w.a.z)} x2={sx(w.b.x)} y2={sy(w.b.z)} stroke="var(--window)" strokeWidth={Math.max(4, 0.1 * v.scale)} pointerEvents="none" />)}
        {plan && !hidden.has('doors') && [...plan.doors, ...plan.openings].map(w => <line key={w.id} x1={sx(w.a.x)} y1={sy(w.a.z)} x2={sx(w.b.x)} y2={sy(w.b.z)} stroke={w.kind === 'door' ? 'var(--door)' : 'var(--paper)'} strokeWidth={Math.max(4, 0.1 * v.scale)} pointerEvents="none" />)}
        {plan && [...(hidden.has('windows') ? [] : plan.windows), ...(hidden.has('doors') ? [] : [...plan.doors, ...plan.openings])].map(w => {
          // A wide invisible stroke to click; selected, it gets an accent outline and moves along the walls.
          const s: Selection = { kind: 'opening', id: w.id };
          const sel = sameSel(selection, s);
          return (
            <g key={'hit' + w.id}>
              {sel && <line x1={sx(w.a.x)} y1={sy(w.a.z)} x2={sx(w.b.x)} y2={sy(w.b.z)} stroke="var(--accent)" strokeWidth={Math.max(4, 0.1 * v.scale) + 6} strokeOpacity={0.45} strokeLinecap="round" pointerEvents="none" />}
              <line x1={sx(w.a.x)} y1={sy(w.a.z)} x2={sx(w.b.x)} y2={sy(w.b.z)} stroke="transparent" strokeWidth={16}
                style={{ cursor: sel ? 'move' : 'pointer' }} onPointerDown={e => down(e, sel ? { ...s, part: 'body' } : undefined, s)} />
            </g>
          );
        })}
        {plan && layers.has('dimensions') && plan.walls.map(w => {
          const len = Math.hypot(w.b.x - w.a.x, w.b.z - w.a.z);
          if (len < 1 || v.scale < 40) return null;
          const mid = { x: (w.a.x + w.b.x) / 2, z: (w.a.z + w.b.z) / 2 };
          return <g key={'d' + w.id}>{labelFor(`${len.toFixed(2)} m`, mid, 4)}</g>;
        })}
        {plan && selection?.kind === 'object' && (() => {
          const o = plan.objects.find(x => x.id === selection.id);
          if (!o) return null;
          // Handle on the piece's long axis (its width), a little past the end.
          const bearing = 90 + o.rotation * 180 / Math.PI;
          return rotateHandle(selection, o.center, bearing, o.width / 2 + 0.35);
        })()}
        {!hidden.has('cameras') && location.cameraPositions.filter(c => inScan(c.scanID) && !location.shots.some(s => planDist(c.rig.position, s.rig.position) < 0.05 && Math.abs(c.rig.pan - s.rig.pan) < 1)).map(c => drawRig({ kind: 'camera', id: c.id }, c.rig, `${c.name} · ${Math.round(c.rig.focalLength)}mm`))}
        {!hidden.has('cameras') && location.shots.filter(s => inScan(s.scanID)).map(s => {
          // A shot taken from a saved camera position is drawn once, with both names.
          const pos = location.cameraPositions.find(c => planDist(c.rig.position, s.rig.position) < 0.05 && Math.abs(c.rig.pan - s.rig.pan) < 1);
          const label = `S${String(s.number).padStart(2, '0')}${pos ? ' · ' + pos.name : ''} · ${Math.round(s.rig.focalLength)}mm`;
          return drawRig({ kind: 'shot', id: s.id }, s.rig, label);
        })}
        {lights.filter(l => KIND_INFO[l.kind].emits ? !hidden.has('lights') : !hidden.has('grip')).map(drawLight)}
        {!hidden.has('people') && (location.characters ?? []).filter(c => inScan(c.scanID)).map(drawCharacter)}
        {!hidden.has('meters') && (location.meters ?? []).filter(m => inScan(m.scanID)).map(drawMeter)}
        {placedLabels()}
        {scan?.northOffset !== undefined && (
          <g transform={`translate(${size.w - 70},${size.h - 100}) rotate(${-scan.northOffset})`} pointerEvents="none" opacity={0.8}>
            <polygon points="0,-18 6,6 0,2 -6,6" fill="var(--danger)" />
            <text y={-24} textAnchor="middle" fill="var(--ink)" fontSize={11} transform={`rotate(${scan.northOffset} 0 -28)`}>N</text>
          </g>
        )}
        <g transform={`translate(16,${size.h - 24})`} pointerEvents="none">
          <line x1={0} y1={0} x2={v.scale * (v.scale > 60 ? 1 : 2)} y2={0} stroke="var(--ink)" />
          <line x1={0} y1={-5} x2={0} y2={5} stroke="var(--ink)" /><line x1={v.scale * (v.scale > 60 ? 1 : 2)} y1={-5} x2={v.scale * (v.scale > 60 ? 1 : 2)} y2={5} stroke="var(--ink)" />
          <text x={v.scale * (v.scale > 60 ? 0.5 : 1)} y={-8} textAnchor="middle" fill="var(--ink)" fontSize={11} fontFamily="ui-monospace, monospace">{v.scale > 60 ? '1 m' : '2 m'}</text>
        </g>
      </svg>
      {props.hint && <div className="plan-hint">{props.hint}</div>}
      <div className="zoom" onPointerDown={e => e.stopPropagation()}>
        <button title="Zoom in" aria-label="Zoom in" onClick={() => zoomAt(1.25)}>+</button>
        <button title="Zoom out" aria-label="Zoom out" onClick={() => zoomAt(0.8)}>−</button>
        <button title="Fit to room" aria-label="Fit to room" onClick={() => { userMoved.current = false; fit(); }} style={{ fontSize: 12 }}>FIT</button>
      </div>
      {luxMap && (
        <div className="plan-legend" onPointerDown={e => e.stopPropagation()}>
          <span className="label">Stops against key · face height · estimated</span>
          <div className="bar">{stopLegend.map(([, s]) => <span key={s} style={{ flex: 1, background: stopColor(s) }} />)}</div>
          <div className="ticks">{stopLegend.map(([t]) => <span key={t}>{t}</span>)}</div>
        </div>
      )}
    </div>
  );
}
