// The lighting planner for one location: toolbar, plan and inspector. Edits go straight into the
// project (and so to the phone); undo/redo covers this session.
import { Suspense, lazy, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useReadingUnit } from './format';
import type { FloorPlan, LightKind, Location, PlanPoint, Project } from '../model/types';
import { KIND_INFO, applyProfile, profileByID } from '../model/photometrics';
import { bearingFrom, buildScene, meterPoints, reading, DEFAULT_WINDOW_TRANSMISSION, planDist } from '../model/calculator';
import { withDefaults } from '../model/exposure';
import { environment } from '../model/stage';
import { eyeHeight } from '../model/characters';
import { newCharacter, newLight, newMeter } from '../model/factory';
import {
  FURNITURE_PRESETS, OPENING_PRESETS, addObject, addSegment, findSegment, furniturePreset, openingPreset, placeFurniture, placeOpening,
  removeObject, removeSegment, replaceObject, replaceSegment, slideOpening, turnObject,
} from '../model/setPieces';
import { PlanCanvas, type DragTarget, type Selection } from './PlanCanvas';
import { Inspector } from './Inspector';
import { Icon } from './icons';

// three.js only loads when someone opens the 3D view.
const Scene3D = lazy(() => import('./Scene3D').then(m => ({ default: m.Scene3D })));

type Tool =
  | { kind: 'select' }
  | { kind: 'light'; light: LightKind; profile?: string }
  | { kind: 'person' }
  | { kind: 'meter' }
  | { kind: 'opening'; preset: string }
  | { kind: 'furniture'; preset: string }
  | { kind: 'aim' };

/** One undo step: the location and the scan's plan as they were. */
interface Snapshot { loc: Location; plan?: FloorPlan }

const quickLights: { label: string; kind: LightKind; profile?: string }[] = [
  { label: 'COB + softbox', kind: 'fresnel', profile: 'cob-600-d' },
  { label: 'Fresnel', kind: 'fresnel', profile: 'fresnel-led-200-bi' },
  { label: 'Panel', kind: 'ledPanel', profile: 'panel-1x1-bi' },
  { label: 'Soft mat', kind: 'softbox', profile: 'mat-4x4-bi' },
  { label: 'Tube', kind: 'tube', profile: 'tube-4ft-rgb' },
  { label: 'HMI', kind: 'hmi', profile: 'hmi-1800-par' },
  { label: 'Practical', kind: 'practical', profile: 'bulb-tungsten-100' },
  { label: 'Lantern', kind: 'spaceLight', profile: 'lantern-300-bi' },
];
const gripItems: { label: string; kind: LightKind }[] = [
  { label: 'Bounce', kind: 'bounce' }, { label: 'Neg', kind: 'negative' }, { label: 'Flag', kind: 'flag' }, { label: 'Diffusion', kind: 'diffusion' },
];

const snap = (v: number) => Math.round(v * 20) / 20;

const PLAN_LAYERS = [
  { id: 'beams', label: 'Beams' },
  { id: 'views', label: 'Camera views' },
  { id: 'readings', label: 'Readings' },
  { id: 'dimensions', label: 'Dimensions' },
  { id: 'names', label: 'Set-piece names' },
];

function menuAnchor(el: HTMLElement) {
  const r = el.getBoundingClientRect();
  return { top: r.bottom + 6, left: Math.max(8, Math.min(r.left, window.innerWidth - 308)) };
}

export function Planner({ project, location, plans, commit, commitPlan }: {
  project: Project; location: Location; plans: Record<string, FloorPlan>; commit(p: Project): void;
  /** Saves an edited 2D plan for a scan (doors, windows, set pieces). */
  commitPlan(scanID: string, plan: FloorPlan): void;
}) {
  useReadingUnit(); // redraw the plan and the panels when the readings unit changes
  const scanID = location.primaryScanID ?? location.scans[location.scans.length - 1]?.id;
  const plan = scanID ? plans[scanID.toUpperCase()] ?? plans[scanID] : undefined;
  const calcPlan = plan && (plan.walls.length || plan.floorPolygons.length) ? plan : undefined;
  const [selection, setSelection] = useState<Selection>();
  const [tool, setTool] = useState<Tool>({ kind: 'select' });
  const [lightMenu, setLightMenu] = useState(false);
  const [setMenu, setSetMenu] = useState(false);
  const [missedWall, setMissedWall] = useState(false);
  const history = useRef<{ past: Snapshot[]; future: Snapshot[] }>({ past: [], future: [] });
  const [, force] = useState(0);
  const locRef = useRef(location);
  locRef.current = location;
  const planRef = useRef(plan);
  planRef.current = plan;

  useEffect(() => { history.current = { past: [], future: [] }; setSelection(undefined); setTool({ kind: 'select' }); }, [location.id]);

  const write = useCallback((next: Location) => {
    commit({ ...project, locations: project.locations.map(l => (l.id === next.id ? next : l)) });
  }, [project, commit]);

  const snapshot = (): Snapshot => ({ loc: locRef.current, plan: planRef.current });
  const remember = () => {
    history.current.past.push(snapshot()); history.current.future = [];
    if (history.current.past.length > 200) history.current.past.shift();
    force(x => x + 1);
  };

  const edit = useCallback((fn: (loc: Location) => Location, undo = true) => {
    const next = fn(locRef.current);
    if (undo) remember();
    locRef.current = next;
    write(next);
  }, [write]); // eslint-disable-line react-hooks/exhaustive-deps

  /** Changes the scan's 2D plan: doors, windows and set pieces. */
  const editPlan = useCallback((fn: (plan: FloorPlan) => FloorPlan, undo = true) => {
    const current = planRef.current;
    if (!current || !scanID) return;
    const next = fn(current);
    if (next === current) return;
    if (undo) remember();
    planRef.current = next;
    commitPlan(scanID, next);
  }, [scanID, commitPlan]); // eslint-disable-line react-hooks/exhaustive-deps

  const restore = (s: Snapshot) => {
    if (s.plan && scanID && s.plan !== planRef.current) { planRef.current = s.plan; commitPlan(scanID, s.plan); }
    if (s.loc !== locRef.current) { locRef.current = s.loc; write(s.loc); }
  };
  const beginChange = () => remember();
  const undo = () => { const h = history.current; const prev = h.past.pop(); if (!prev) return; h.future.push(snapshot()); restore(prev); force(x => x + 1); };
  const redo = () => { const h = history.current; const next = h.future.pop(); if (!next) return; h.past.push(snapshot()); restore(next); force(x => x + 1); };

  // Typing in a slider counts as one change: open an undo step when a control is first touched.
  useEffect(() => {
    const onDown = (e: PointerEvent) => { if ((e.target as HTMLElement).closest?.('.inspector input[type=range]')) beginChange(); };
    const onFocus = (e: FocusEvent) => { if ((e.target as HTMLElement).closest?.('.inspector input[type=text], .inspector textarea, .inspector input.name')) beginChange(); };
    window.addEventListener('pointerdown', onDown, true);
    window.addEventListener('focusin', onFocus);
    return () => { window.removeEventListener('pointerdown', onDown, true); window.removeEventListener('focusin', onFocus); };
  });

  const inScan = (id?: string) => !id || !scanID || id === scanID;
  const lights = useMemo(() => (location.lights ?? []).filter(l => inScan(l.scanID)), [location.lights, scanID]); // eslint-disable-line react-hooks/exhaustive-deps
  const exposure = withDefaults(location.exposure);
  const windowTransmission = location.display?.windowTransmission ?? DEFAULT_WINDOW_TRANSMISSION;
  const scan = location.scans.find(s => s.id === scanID);
  // Sun, sky and an LED wall, when the location has them (stage.ts).
  const env = useMemo(() => environment(location, calcPlan, scan), [location.daylight, location.studio, location.coordinate, location.shots, location.cameraPositions, calcPlan, scan]); // eslint-disable-line react-hooks/exhaustive-deps
  const scene = useMemo(() => buildScene(lights, calcPlan, windowTransmission, env), [lights, calcPlan, windowTransmission, env]);
  const meters = useMemo(() => meterPoints(location, scanID), [location, scanID]);
  const readings = useMemo(() => new Map(meters.map(m => [m.key, reading(m.point, m.normal, scene).lux])), [meters, scene]);

  // MARK: Placing

  const nearestFace = (p: PlanPoint) => (location.characters ?? []).reduce<{ position: PlanPoint } | undefined>((m, c) => (!m || planDist(c.position, p) < planDist(m.position, p) ? c : m), undefined);
  const roomCentre = (): PlanPoint => (plan ? { x: (plan.bounds.minX + plan.bounds.maxX) / 2, z: (plan.bounds.minZ + plan.bounds.maxZ) / 2 } : { x: 0, z: 0 });

  const place = (raw: PlanPoint) => {
    const p = { x: snap(raw.x), z: snap(raw.z) };
    if (tool.kind === 'light') {
      const target = nearestFace(p)?.position ?? roomCentre();
      let l = newLight(tool.light, p, bearingFrom(p, target), scanID);
      if (tool.profile) l = applyProfile(l, profileByID(tool.profile)!);
      if (tool.profile === 'cob-600-d') l.modifierID = 'softbox-90';
      const count = (location.lights ?? []).filter(x => x.kind === l.kind).length;
      l.name = `${KIND_INFO[l.kind].label}${count ? ' ' + (count + 1) : ''}`;
      if (!KIND_INFO[l.kind].emits) l.height = 1.5;
      edit(loc => ({ ...loc, lights: [...(loc.lights ?? []), l] }));
      setSelection({ kind: 'light', id: l.id });
    } else if (tool.kind === 'person') {
      const n = (location.characters ?? []).length + 1;
      const c = newCharacter(n % 2 ? 'woman' : 'man', p, `Person ${n}`, scanID);
      const cam = location.shots[0]?.rig ?? location.cameraPositions[0]?.rig;
      if (cam) c.facing = bearingFrom(p, cam.position);
      edit(loc => ({ ...loc, characters: [...(loc.characters ?? []), c] }));
      setSelection({ kind: 'character', id: c.id });
    } else if (tool.kind === 'meter') {
      const m = newMeter(p, `Meter ${(location.meters ?? []).length + 1}`, scanID);
      edit(loc => ({ ...loc, meters: [...(loc.meters ?? []), m] }));
      setSelection({ kind: 'meter', id: m.id });
    } else if (tool.kind === 'opening') {
      const preset = openingPreset(tool.preset);
      const seg = preset && placeOpening(calcPlan, raw, preset);
      // Missed the walls: keep the tool so the next click can try again.
      if (!seg) { setMissedWall(true); return; }
      editPlan(pl => addSegment(pl, seg));
      setSelection({ kind: 'opening', id: seg.id });
    } else if (tool.kind === 'furniture') {
      const preset = furniturePreset(tool.preset);
      if (!preset) return;
      const o = placeFurniture(calcPlan, p, preset);
      editPlan(pl => addObject(pl, o));
      setSelection({ kind: 'object', id: o.id });
    } else if (tool.kind === 'aim' && selection?.kind === 'light') {
      aimLightAt(selection.id, raw);
    }
    setMissedWall(false);
    setTool({ kind: 'select' });
  };

  const aimLightAt = (id: string, target: PlanPoint) => {
    const l = location.lights?.find(x => x.id === id);
    if (!l) return;
    const face = (location.characters ?? []).find(c => planDist(c.position, target) < 0.4);
    const targetHeight = face ? eyeHeight(face) : 1.2;
    const at = face?.position ?? target;
    const d = planDist(l.position, at);
    const tilt = Math.max(-90, Math.min(45, Math.atan2(targetHeight - l.height, Math.max(d, 0.1)) * 180 / Math.PI));
    edit(loc => ({ ...loc, lights: (loc.lights ?? []).map(x => (x.id === id ? { ...x, pan: bearingFrom(x.position, at), tilt: KIND_INFO[x.kind].emits ? Math.round(tilt) : 0 } : x)) }));
  };

  // MARK: Dragging

  const dragPending = useRef(false);
  const drag = (t: DragTarget, raw: PlanPoint) => {
    // One undo step per drag, opened on the first real move (a plain click selects without one).
    if (dragPending.current) { dragPending.current = false; beginChange(); }
    const p = { x: snap(raw.x), z: snap(raw.z) };
    const turn = (from: PlanPoint) => Math.round(bearingFrom(from, raw));
    if (t.kind === 'object') {
      editPlan(pl => {
        const o = pl.objects.find(x => x.id === t.id);
        if (!o) return pl;
        // The handle sits on the piece's long axis; turning snaps to 15° steps.
        const step = Math.PI / 12;
        const next = t.part === 'rotate'
          ? { ...o, rotation: Math.round(Math.atan2(raw.z - o.center.z, raw.x - o.center.x) / step) * step, byHand: true }
          : { ...o, center: p, byHand: true };
        return replaceObject(pl, next);
      }, false);
      return;
    }
    if (t.kind === 'opening') {
      editPlan(pl => { const seg = findSegment(pl, t.id); return seg ? replaceSegment(pl, slideOpening(pl, seg, raw)) : pl; }, false);
      return;
    }
    edit(loc => {
      switch (t.kind) {
        case 'light': return { ...loc, lights: (loc.lights ?? []).map(l => (l.id !== t.id ? l : t.part === 'rotate' ? { ...l, pan: turn(l.position) } : { ...l, position: p })) };
        case 'character': return { ...loc, characters: (loc.characters ?? []).map(c => (c.id !== t.id ? c : t.part === 'rotate' ? { ...c, facing: turn(c.position) } : { ...c, position: p })) };
        case 'meter': return { ...loc, meters: (loc.meters ?? []).map(m => (m.id !== t.id ? m : { ...m, position: p })) };
        case 'shot': return { ...loc, shots: loc.shots.map(s => (s.id !== t.id ? s : { ...s, rig: t.part === 'rotate' ? { ...s.rig, pan: turn(s.rig.position) } : { ...s.rig, position: p } })) };
        case 'camera': return { ...loc, cameraPositions: loc.cameraPositions.map(s => (s.id !== t.id ? s : { ...s, rig: t.part === 'rotate' ? { ...s.rig, pan: turn(s.rig.position) } : { ...s.rig, position: p } })) };
        default: return loc;
      }
    }, false);
  };

  // MARK: Keyboard

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const typing = (e.target as HTMLElement).matches?.('input, textarea, select');
      const mod = e.metaKey || e.ctrlKey;
      if (mod && e.key.toLowerCase() === 'z') { e.preventDefault(); if (e.shiftKey) redo(); else undo(); return; }
      if (mod && e.key.toLowerCase() === 'y') { e.preventDefault(); redo(); return; }
      if (typing) return;
      if (e.key === 'Escape') { setTool({ kind: 'select' }); setLightMenu(false); setSetMenu(false); setMissedWall(false); if (tool.kind === 'select') setSelection(undefined); }
      if ((e.key === 'Delete' || e.key === 'Backspace') && selection) {
        e.preventDefault();
        const id = selection.id;
        if (selection.kind === 'light') edit(loc => ({ ...loc, lights: (loc.lights ?? []).filter(x => x.id !== id) }));
        if (selection.kind === 'character') edit(loc => ({ ...loc, characters: (loc.characters ?? []).filter(x => x.id !== id) }));
        if (selection.kind === 'meter') edit(loc => ({ ...loc, meters: (loc.meters ?? []).filter(x => x.id !== id) }));
        if (selection.kind === 'object') editPlan(pl => removeObject(pl, id));
        if (selection.kind === 'opening') editPlan(pl => removeSegment(pl, id));
        setSelection(undefined);
      }
      if (e.key === 'l') setLightMenu(true);
      if (e.key === 's' && calcPlan) setSetMenu(true);
      if (e.key === 'p') setTool({ kind: 'person' });
      if (e.key === 'm') setTool({ kind: 'meter' });
      if (selection?.kind === 'object' && (e.key === '[' || e.key === ']')) {
        const id = selection.id, step = (e.key === ']' ? 15 : -15) * Math.PI / 180;
        editPlan(pl => { const o = pl.objects.find(x => x.id === id); return o ? replaceObject(pl, turnObject(o, step)) : pl; });
      }
      if (selection?.kind === 'light' && (e.key === '[' || e.key === ']')) {
        const step = e.key === ']' ? 15 : -15;
        edit(loc => ({ ...loc, lights: (loc.lights ?? []).map(x => (x.id === selection.id ? { ...x, pan: (x.pan + step + 360) % 360 } : x)) }));
      }
      if (selection && ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) {
        e.preventDefault();
        const d = e.shiftKey ? 0.5 : 0.05;
        const dx = e.key === 'ArrowLeft' ? -d : e.key === 'ArrowRight' ? d : 0;
        const dz = e.key === 'ArrowUp' ? -d : e.key === 'ArrowDown' ? d : 0;
        const mv = (q: PlanPoint) => ({ x: snap(q.x + dx), z: snap(q.z + dz) });
        const id = selection.id;
        if (selection.kind === 'object') {
          editPlan(pl => { const o = pl.objects.find(x => x.id === id); return o ? replaceObject(pl, { ...o, center: mv(o.center), byHand: true }) : pl; });
          return;
        }
        edit(loc => ({
          ...loc,
          lights: selection.kind === 'light' ? (loc.lights ?? []).map(x => (x.id === id ? { ...x, position: mv(x.position) } : x)) : loc.lights,
          characters: selection.kind === 'character' ? (loc.characters ?? []).map(x => (x.id === id ? { ...x, position: mv(x.position) } : x)) : loc.characters,
          meters: selection.kind === 'meter' ? (loc.meters ?? []).map(x => (x.id === id ? { ...x, position: mv(x.position) } : x)) : loc.meters,
        }));
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const showLuxMap = location.display?.showLuxMap ?? false;
  const [layers, setLayers] = useState<Set<string>>(() => {
    try { return new Set((localStorage.getItem('framescan.plan.layers') ?? '').split(',').filter(Boolean)); } catch { return new Set(); }
  });
  const [showMenu, setShowMenu] = useState(false);
  const [view3D, setView3D] = useState(() => { try { return localStorage.getItem('framescan.plan.view') === '3d'; } catch { return false; } });
  const setView = (on: boolean) => { setView3D(on); try { localStorage.setItem('framescan.plan.view', on ? '3d' : 'plan'); } catch { /* private mode */ } if (on) setTool({ kind: 'select' }); };
  // Menus open below their button, outside the toolbar (which scrolls sideways and would clip them).
  const [anchor, setAnchor] = useState<{ top: number; left: number }>({ top: 0, left: 0 });
  const toggleLayer = (id: string) => setLayers(prev => {
    const next = new Set(prev);
    if (next.has(id)) next.delete(id); else next.add(id);
    try { localStorage.setItem('framescan.plan.layers', [...next].join(',')); } catch { /* private mode */ }
    return next;
  });
  const toggleLuxMap = () => edit(loc => ({ ...loc, display: { ...(loc.display ?? {}), showLuxMap: !showLuxMap } }));

  const hint = tool.kind === 'opening' ? (missedWall ? 'That is too far from a wall. Click on a wall, or within a metre of one.' : `Click a wall to put the ${openingPreset(tool.preset)?.label.toLowerCase() ?? 'opening'} in it. Esc cancels.`)
    : tool.kind === 'furniture' ? `Click where the ${furniturePreset(tool.preset)?.label.toLowerCase() ?? 'piece'} goes. Near a wall it turns to back onto it. Esc cancels.`
    : tool.kind === 'light' ? 'Click the plan to place the unit. It starts aimed at the nearest person. Esc cancels.'
    : tool.kind === 'person' ? 'Click where the person stands. They face the first camera.'
    : tool.kind === 'meter' ? 'Click where you want a reading.'
    : tool.kind === 'aim' ? 'Click a person or a spot to aim the selected light at it.'
    : !calcPlan && lights.length === 0 ? 'No scan plan for this location yet: scan on the phone, or place lights on the grid.'
    : '';

  const isOn = (k: Tool['kind']) => tool.kind === k;
  // Placing happens on the plan, so picking a placing tool goes back to it.
  useEffect(() => { if (view3D && tool.kind !== 'select') setView(false); });

  return (
    <>
      <div className="stage">
        <div className="toolbar" role="toolbar" aria-label="Plan tools">
          <div className="seg" role="group" aria-label="View">
            <button className={'tool' + (!view3D ? ' on' : '')} aria-pressed={!view3D} onClick={() => setView(false)} title="2D lighting plan">Plan</button>
            <button className={'tool' + (view3D ? ' on' : '')} aria-pressed={view3D} onClick={() => setView(true)} title="Walk around the set in 3D">3D</button>
          </div>
          <span className="sep" />
          <button className={'tool' + (isOn('select') ? ' on' : '')} onClick={() => setTool({ kind: 'select' })} title="Select and move (Esc)"><Icon name="select" /><span className="txt">Select</span></button>
          <div style={{ position: 'relative' }}>
            <button className={'tool' + (isOn('light') ? ' on' : '')} onClick={e => { setAnchor(menuAnchor(e.currentTarget)); setLightMenu(!lightMenu); }} aria-expanded={lightMenu} title="Add a light or grip (L)"><Icon name="light" /><span className="txt">+ Light</span></button>
            {lightMenu && (
              <div className="dialog" style={{ position: 'fixed', ...anchor, width: 300, padding: 12, zIndex: 20 }} onMouseLeave={() => setLightMenu(false)}>
                <div className="label" style={{ marginBottom: 8 }}>Lights</div>
                <div className="chips">{quickLights.map(q => <button key={q.label} className="chip" onClick={() => { setTool({ kind: 'light', light: q.kind, profile: q.profile }); setLightMenu(false); }}>{q.label}</button>)}</div>
                <div className="label" style={{ margin: '12px 0 8px' }}>Grip</div>
                <div className="chips">{gripItems.map(q => <button key={q.label} className="chip" onClick={() => { setTool({ kind: 'light', light: q.kind }); setLightMenu(false); }}>{q.label}</button>)}</div>
                <p className="note">Pick any fixture type after placing it.</p>
              </div>
            )}
          </div>
          <div style={{ position: 'relative' }}>
            <button className={'tool' + (isOn('opening') || isOn('furniture') ? ' on' : '')} disabled={!calcPlan}
              onClick={e => { setAnchor(menuAnchor(e.currentTarget)); setSetMenu(!setMenu); setLightMenu(false); }} aria-expanded={setMenu}
              title={calcPlan ? 'Add a door, window or piece of furniture (S)' : 'Draw a room or scan one first'}><Icon name="sofa" /><span className="txt">+ Set</span></button>
            {setMenu && (
              <div className="dialog" style={{ position: 'fixed', ...anchor, width: 320, padding: 12, zIndex: 20 }} onMouseLeave={() => setSetMenu(false)}>
                <div className="label" style={{ marginBottom: 8 }}>In a wall</div>
                <div className="chips">{OPENING_PRESETS.map(q => <button key={q.id} className="chip" onClick={() => { setTool({ kind: 'opening', preset: q.id }); setSetMenu(false); setMissedWall(false); }}>{q.label}</button>)}</div>
                <div className="label" style={{ margin: '12px 0 8px' }}>Furniture</div>
                <div className="chips">{FURNITURE_PRESETS.map(q => <button key={q.id} className="chip" onClick={() => { setTool({ kind: 'furniture', preset: q.id }); setSetMenu(false); }}>{q.label}</button>)}</div>
                <p className="note">Typical sizes to start with. Change them after placing; the plan marks them as typed, not measured.</p>
              </div>
            )}
          </div>
          <button className={'tool' + (isOn('person') ? ' on' : '')} onClick={() => setTool({ kind: 'person' })} title="Add a person (P)"><Icon name="person" /><span className="txt">+ Person</span></button>
          <button className={'tool' + (isOn('meter') ? ' on' : '')} onClick={() => setTool({ kind: 'meter' })} title="Add a light meter (M)"><Icon name="meter" /><span className="txt">+ Meter</span></button>
          <span className="sep" />
          <div style={{ position: 'relative' }}>
            <button className={'tool' + (showMenu ? ' on' : '')} onClick={e => { setAnchor(menuAnchor(e.currentTarget)); setShowMenu(!showMenu); }} aria-expanded={showMenu} title="Add information to the plan, one layer at a time">
              <Icon name="map" /><span className="txt">Show{layers.size + (showLuxMap ? 1 : 0) ? ` +${layers.size + (showLuxMap ? 1 : 0)}` : ''}</span>
            </button>
            {showMenu && (
              <div className="dialog" style={{ position: 'fixed', ...anchor, width: 260, padding: 12, zIndex: 20 }} onMouseLeave={() => setShowMenu(false)}>
                <div className="label" style={{ marginBottom: 8 }}>On the plan</div>
                <div className="chips">
                  {PLAN_LAYERS.map(l => <button key={l.id} className={'chip' + (layers.has(l.id) ? ' on' : '')} aria-pressed={layers.has(l.id)} onClick={() => toggleLayer(l.id)}>{l.label}</button>)}
                  <button className={'chip' + (showLuxMap ? ' on' : '')} aria-pressed={showLuxMap} onClick={toggleLuxMap}>Exposure map</button>
                </div>
                <p className="note">The plan starts with the room, units, people and cameras. The selected item always shows its beam, view and reading.</p>
              </div>
            )}
          </div>
          <span className="spacer" />
          <button className="tool" onClick={undo} disabled={!history.current.past.length} title="Undo (⌘Z)" aria-label="Undo"><Icon name="undo" /></button>
          <button className="tool" onClick={redo} disabled={!history.current.future.length} title="Redo (⇧⌘Z)" aria-label="Redo"><Icon name="redo" /></button>
        </div>
        {view3D ? (
          <Suspense fallback={<div className="scene3d"><div className="scene3d-hint">Loading 3D…</div></div>}>
            <Scene3D location={location} plan={plan} scanID={scanID} lights={lights} selection={selection} beams={layers.has('beams')} meters={meters} readings={readings} showReadings={layers.has('readings')} exposure={exposure} onSelect={s => setSelection(s)} />
          </Suspense>
        ) : (
          <PlanCanvas
            location={location} plan={plan} scanID={scanID} lights={lights} scene={scene} readings={readings} exposure={exposure}
            selection={selection} showLuxMap={showLuxMap} layers={layers} placing={tool.kind !== 'select'} hint={hint}
            onSelect={s => setSelection(s)} onPlace={place}
            onDragStart={() => { dragPending.current = true; }} onDrag={drag} onDragEnd={() => { dragPending.current = false; }}
          />
        )}
      </div>
      <aside className="inspector" aria-label="Details">
        <Inspector location={location} plan={calcPlan} lights={lights} scene={scene} meters={meters} readings={readings} exposure={exposure}
          selection={selection} windowTransmission={windowTransmission} environment={env} scan={scan} edit={edit} editPlan={editPlan} select={setSelection}
          aimMode={on => setTool(on ? { kind: 'aim' } : { kind: 'select' })} />
      </aside>
    </>
  );
}
