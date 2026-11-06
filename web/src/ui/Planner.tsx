// The lighting planner for one location: toolbar, plan and inspector. Edits go straight into the
// project (and so to the phone); undo/redo covers this session.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { FloorPlan, LightKind, Location, PlanPoint, Project } from '../model/types';
import { KIND_INFO, applyProfile, profileByID } from '../model/photometrics';
import { bearingFrom, buildScene, meterPoints, reading, DEFAULT_WINDOW_TRANSMISSION, planDist } from '../model/calculator';
import { withDefaults } from '../model/exposure';
import { eyeHeight } from '../model/characters';
import { newCharacter, newLight, newMeter } from '../model/factory';
import { PlanCanvas, type DragTarget, type Selection } from './PlanCanvas';
import { Inspector } from './Inspector';
import { Icon } from './icons';

type Tool =
  | { kind: 'select' }
  | { kind: 'light'; light: LightKind; profile?: string }
  | { kind: 'person' }
  | { kind: 'meter' }
  | { kind: 'aim' };

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

export function Planner({ project, location, plans, commit }: { project: Project; location: Location; plans: Record<string, FloorPlan>; commit(p: Project): void }) {
  const scanID = location.primaryScanID ?? location.scans[location.scans.length - 1]?.id;
  const plan = scanID ? plans[scanID.toUpperCase()] ?? plans[scanID] : undefined;
  const calcPlan = plan && (plan.walls.length || plan.floorPolygons.length) ? plan : undefined;
  const [selection, setSelection] = useState<Selection>();
  const [tool, setTool] = useState<Tool>({ kind: 'select' });
  const [lightMenu, setLightMenu] = useState(false);
  const history = useRef<{ past: Location[]; future: Location[] }>({ past: [], future: [] });
  const [, force] = useState(0);
  const locRef = useRef(location);
  locRef.current = location;

  useEffect(() => { history.current = { past: [], future: [] }; setSelection(undefined); setTool({ kind: 'select' }); }, [location.id]);

  const write = useCallback((next: Location) => {
    commit({ ...project, locations: project.locations.map(l => (l.id === next.id ? next : l)) });
  }, [project, commit]);

  const edit = useCallback((fn: (loc: Location) => Location, undo = true) => {
    const before = locRef.current;
    const next = fn(before);
    if (undo) { history.current.past.push(before); history.current.future = []; if (history.current.past.length > 200) history.current.past.shift(); force(x => x + 1); }
    locRef.current = next;
    write(next);
  }, [write]);

  const beginChange = () => { history.current.past.push(locRef.current); history.current.future = []; force(x => x + 1); };
  const undo = () => { const h = history.current; const prev = h.past.pop(); if (!prev) return; h.future.push(locRef.current); write(prev); force(x => x + 1); };
  const redo = () => { const h = history.current; const next = h.future.pop(); if (!next) return; h.past.push(locRef.current); write(next); force(x => x + 1); };

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
  const scene = useMemo(() => buildScene(lights, calcPlan, windowTransmission), [lights, calcPlan, windowTransmission]);
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
    } else if (tool.kind === 'aim' && selection?.kind === 'light') {
      aimLightAt(selection.id, raw);
    }
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
      if (e.key === 'Escape') { setTool({ kind: 'select' }); setLightMenu(false); if (tool.kind === 'select') setSelection(undefined); }
      if ((e.key === 'Delete' || e.key === 'Backspace') && selection) {
        e.preventDefault();
        const id = selection.id;
        if (selection.kind === 'light') edit(loc => ({ ...loc, lights: (loc.lights ?? []).filter(x => x.id !== id) }));
        if (selection.kind === 'character') edit(loc => ({ ...loc, characters: (loc.characters ?? []).filter(x => x.id !== id) }));
        if (selection.kind === 'meter') edit(loc => ({ ...loc, meters: (loc.meters ?? []).filter(x => x.id !== id) }));
        setSelection(undefined);
      }
      if (e.key === 'l') setLightMenu(true);
      if (e.key === 'p') setTool({ kind: 'person' });
      if (e.key === 'm') setTool({ kind: 'meter' });
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
  // Menus open below their button, outside the toolbar (which scrolls sideways and would clip them).
  const [anchor, setAnchor] = useState<{ top: number; left: number }>({ top: 0, left: 0 });
  const toggleLayer = (id: string) => setLayers(prev => {
    const next = new Set(prev);
    if (next.has(id)) next.delete(id); else next.add(id);
    try { localStorage.setItem('framescan.plan.layers', [...next].join(',')); } catch { /* private mode */ }
    return next;
  });
  const toggleLuxMap = () => edit(loc => ({ ...loc, display: { ...(loc.display ?? {}), showLuxMap: !showLuxMap } }));

  const hint = tool.kind === 'light' ? 'Click the plan to place the unit. It starts aimed at the nearest person. Esc cancels.'
    : tool.kind === 'person' ? 'Click where the person stands. They face the first camera.'
    : tool.kind === 'meter' ? 'Click where you want a reading.'
    : tool.kind === 'aim' ? 'Click a person or a spot to aim the selected light at it.'
    : !calcPlan && lights.length === 0 ? 'No scan plan for this location yet: scan on the phone, or place lights on the grid.'
    : '';

  const isOn = (k: Tool['kind']) => tool.kind === k;

  return (
    <>
      <div className="stage">
        <div className="toolbar" role="toolbar" aria-label="Plan tools">
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
        <PlanCanvas
          location={location} plan={plan} scanID={scanID} lights={lights} scene={scene} readings={readings} exposure={exposure}
          selection={selection} showLuxMap={showLuxMap} layers={layers} placing={tool.kind !== 'select'} hint={hint}
          onSelect={s => setSelection(s)} onPlace={place}
          onDragStart={() => { dragPending.current = true; }} onDrag={drag} onDragEnd={() => { dragPending.current = false; }}
        />
      </div>
      <aside className="inspector" aria-label="Details">
        <Inspector location={location} plan={calcPlan} lights={lights} scene={scene} meters={meters} readings={readings} exposure={exposure}
          selection={selection} windowTransmission={windowTransmission} edit={edit} select={setSelection}
          aimMode={on => setTool(on ? { kind: 'aim' } : { kind: 'select' })} />
      </aside>
    </>
  );
}
