// Right-hand panel. Simple things first (output, colour, where it's aimed, what it gives at each
// meter), the rest under "More". Same labels as the phone so a crew sees one tool.
import { CAMERA_SUPPORTS, LIGHT_SUPPORTS, automaticCameraSupport, automaticLightSupport, cameraSupportInfo, cameraSupportWarning, lightSupportInfo, lightSupportWarning } from '../model/rigging';
import { useState, type ReactNode } from 'react';
import type { CameraRig, ExposureSettings, FloorPlan, LightFixture, LightMeter, LightRole, Location, PlanObject, PlanSegment, PrevisCharacter, CharacterType } from '../model/types';
import {
  FURNITURE_PRESETS, SIZE_LIMITS, addObject, addSegment, backOntoWall, clampSize, findSegment, openingLabel, removeObject, removeSegment,
  replaceObject, replaceSegment, resizeOpening, setOpeningHeight, setPieceName, turnObject,
} from '../model/setPieces';
import { uuid } from '../model/factory';
import {
  KIND_INFO, applyProfile, categoryLabel, filters, fixtureModifier, fixtureProfile, isAdjustable, modifiersFor, photometrics, profiles,
  illuminanceOnAxis, distanceForLux, type FixtureCategory,
} from '../model/photometrics';
import { exposureTime, fStop, frameRates, isoPresets, keyLux, shutterAngles, speedLabel, stopLabel, stopsDelta, stopsForLux, tStops, trim } from '../model/exposure';
import { cameraSeeing, meterCameras, solveOutput, type MeterPoint, type Scene, reading as calcReading } from '../model/calculator';
import { LIGHTING_SETUPS, buildSetup, type LightingSetup } from '../model/setups';
import { kelvinPresets } from '../model/kelvin';
import { characterDefaults, skinRGB, skinTones, skinStopsFromGrey } from '../model/characters';
import { sensorPresets, horizontalFOV } from '../model/camera';
import { deg, lux as fmtLux, metres, pct, reading as fmtReading, READING_UNITS, readingText, readingUnit, setReadingUnit, signedDeg, watts } from './format';
import type { ReadingUnit } from './format';
import { Icon } from './icons';
import type { Selection } from './PlanCanvas';

function Slider({ label, value, min, max, step, format, onChange }: { label: string; value: number; min: number; max: number; step: number; format: (v: number) => string; onChange(v: number): void }) {
  return (
    <label className="field">
      <span>{label}</span>
      <input type="range" min={min} max={max} step={step} value={value} onChange={e => onChange(Number(e.target.value))} aria-label={label} />
      <span className="val">{format(value)}</span>
    </label>
  );
}

function Panel({ title, children, collapsible, open: initial = true }: { title: string; children: ReactNode; collapsible?: boolean; open?: boolean }) {
  const [open, setOpen] = useState(initial);
  return (
    <section className="panel">
      {collapsible
        ? <button className="btn ghost small" style={{ padding: 0, marginBottom: open ? 8 : 0 }} onClick={() => setOpen(!open)} aria-expanded={open}><span className="label">{open ? '▾' : '▸'} {title}</span></button>
        : <h3>{title}</h3>}
      {(!collapsible || open) && children}
    </section>
  );
}

const Badge = ({ text = 'Estimated' }: { text?: string }) => <span className="badge" title="Derived by the app. Check on set before relying on it.">≈ {text}</span>;

export interface InspectorProps {
  location: Location;
  plan?: FloorPlan;
  lights: LightFixture[];
  scene: Scene;
  meters: MeterPoint[];
  readings: Map<string, number>;
  exposure: ExposureSettings;
  selection?: Selection;
  windowTransmission: number;
  edit(fn: (loc: Location) => Location, undo?: boolean): void;
  /** Changes the scan's 2D plan (doors, windows, set pieces). */
  editPlan(fn: (plan: FloorPlan) => FloorPlan, undo?: boolean): void;
  select(s?: Selection): void;
  aimMode(on: boolean): void;
}

export function Inspector(p: InspectorProps) {
  const s = p.selection;
  if (s?.kind === 'light') { const l = p.lights.find(x => x.id === s.id); if (l) return <LightInspector {...p} light={l} />; }
  if (s?.kind === 'character') { const c = p.location.characters?.find(x => x.id === s.id); if (c) return <CharacterInspector {...p} character={c} />; }
  if (s?.kind === 'meter') { const m = p.location.meters?.find(x => x.id === s.id); if (m) return <MeterInspector {...p} meter={m} />; }
  if (s?.kind === 'shot' || s?.kind === 'camera') return <CameraInspector {...p} />;
  if (s?.kind === 'object') { const o = p.plan?.objects.find(x => x.id === s.id); if (o) return <SetPieceInspector {...p} object={o} />; }
  if (s?.kind === 'opening') { const seg = findSegment(p.plan, s.id); if (seg) return <OpeningInspector {...p} segment={seg} />; }
  return <Overview {...p} />;
}

// MARK: Set pieces

/** A size in metres: − and + step by 5 cm (one undo step each), typing is one step per focus. */
function SizeRow({ label, value, min = SIZE_LIMITS.min, max = SIZE_LIMITS.max, step = 0.05, onChange }: { label: string; value: number; min?: number; max?: number; step?: number; onChange(v: number, undo: boolean): void }) {
  const [text, setText] = useState<string>();
  const clampV = (v: number) => Math.round(Math.min(max, Math.max(min, v)) * 1000) / 1000;
  return (
    <div className="field size-row">
      <span>{label}</span>
      <span className="ctl">
        <button type="button" aria-label={`Less ${label.toLowerCase()}`} onClick={() => onChange(clampV(value - step), true)}>−</button>
        <input type="text" inputMode="decimal" aria-label={`${label} in metres`} value={text ?? value.toFixed(2)}
          onChange={e => { setText(e.target.value); const n = parseFloat(e.target.value.replace(',', '.')); if (Number.isFinite(n) && n >= min) onChange(clampV(n), false); }}
          onBlur={() => setText(undefined)} />
        <button type="button" aria-label={`More ${label.toLowerCase()}`} onClick={() => onChange(clampV(value + step), true)}>+</button>
      </span>
      <span className="unit">m</span>
    </div>
  );
}

const ByHandNote = ({ byHand, what }: { byHand?: boolean; what: string }) => (
  <p className="note">{byHand
    ? <><span className="badge" title="Typed or picked from a list, not measured">Entered by hand</span> Sizes are typical ones or typed in, not measured. Check them on the recce.</>
    : <>From the scan. Changing the {what} here marks it as entered by hand.</>}</p>
);

function SetPieceInspector(p: InspectorProps & { object: PlanObject }) {
  const o = p.object;
  const set = (patch: Partial<PlanObject>, undo = true) => p.editPlan(pl => replaceObject(pl, { ...o, ...patch, byHand: true }), undo);
  const preset = FURNITURE_PRESETS.find(f => f.category === o.category && Math.abs(f.width - o.width) < 1e-6 && Math.abs(f.depth - o.depth) < 1e-6);
  const wall = backOntoWall(p.plan, o.center, o.depth, 1.5);
  // Offered only when it would move or turn the piece.
  const againstWall = wall && (Math.hypot(wall.center.x - o.center.x, wall.center.z - o.center.z) > 0.01 || Math.abs(Math.sin(wall.rotation - o.rotation)) > 0.01) ? wall : undefined;
  const duplicate = () => {
    const copy: PlanObject = { ...o, id: uuid(), center: { x: o.center.x + 0.3, z: o.center.z + 0.3 }, byHand: true };
    p.editPlan(pl => addObject(pl, copy));
    p.select({ kind: 'object', id: copy.id });
  };
  const remove = () => { p.editPlan(pl => removeObject(pl, o.id)); p.select(undefined); };
  return (
    <div>
      <Panel title="Set piece">
        <div style={{ fontSize: 18, fontWeight: 400, marginBottom: 4 }}>{setPieceName(o)}</div>
        <label className="field"><span>Swap for</span>
          <select value={preset?.id ?? ''} onChange={e => {
            const f = FURNITURE_PRESETS.find(x => x.id === e.target.value);
            if (f) set({ category: f.category, width: f.width, depth: f.depth, height: f.height });
          }}>
            {!preset && <option value="">{o.category} (as it is)</option>}
            {FURNITURE_PRESETS.map(f => <option key={f.id} value={f.id}>{f.label}</option>)}
          </select><span />
        </label>
        <SizeRow label="Width" value={o.width} onChange={(v, u) => set({ width: clampSize(v) }, u)} />
        <SizeRow label="Depth" value={o.depth} onChange={(v, u) => set({ depth: clampSize(v) }, u)} />
        <SizeRow label="Height" value={o.height} max={SIZE_LIMITS.heightMax} onChange={(v, u) => set({ height: clampSize(v, SIZE_LIMITS.heightMax) }, u)} />
        <div className="actions" style={{ marginTop: 12 }}>
          <button className="btn small" onClick={() => p.editPlan(pl => replaceObject(pl, turnObject(o, -Math.PI / 2)))} title="Turn a quarter left ([ turns 15°)"><Icon name="turnLeft" /> Turn</button>
          <button className="btn small" onClick={() => p.editPlan(pl => replaceObject(pl, turnObject(o, Math.PI / 2)))} title="Turn a quarter right (] turns 15°)"><Icon name="turnRight" /> Turn</button>
          {againstWall && <button className="btn small" onClick={() => set(againstWall)} title="Turn it to back onto the nearest wall">Back to wall</button>}
        </div>
        <div className="actions" style={{ marginTop: 8 }}>
          <button className="btn small" onClick={duplicate}><Icon name="copy" /> Duplicate</button>
          <button className="btn small danger" onClick={remove}><Icon name="trash" /> Delete</button>
        </div>
        <p className="note">Drag it on the plan to move it, or the round handle to turn it. Arrow keys nudge it 5 cm.</p>
        <ByHandNote byHand={o.byHand} what="piece" />
      </Panel>
    </div>
  );
}

function OpeningInspector(p: InspectorProps & { segment: PlanSegment }) {
  const seg = p.segment;
  const plan = p.plan;
  if (!plan) return null;
  const width = Math.hypot(seg.b.x - seg.a.x, seg.b.z - seg.a.z);
  const put = (next: PlanSegment, undo = true) => p.editPlan(pl => replaceSegment(pl, { ...next, byHand: true }), undo);
  const remove = () => { p.editPlan(pl => removeSegment(pl, seg.id)); p.select(undefined); };
  const duplicate = () => {
    // A second one beside it on the same wall.
    const dx = (seg.b.x - seg.a.x), dz = (seg.b.z - seg.a.z);
    const shifted = { ...seg, id: uuid(), a: { x: seg.a.x + dx * 1.3, z: seg.a.z + dz * 1.3 }, b: { x: seg.b.x + dx * 1.3, z: seg.b.z + dz * 1.3 }, byHand: true };
    const fitted = resizeOpening(plan, shifted, width);
    p.editPlan(pl => addSegment(pl, fitted));
    p.select({ kind: 'opening', id: fitted.id });
  };
  return (
    <div>
      <Panel title={openingLabel(seg.kind)}>
        <div className="seg" role="group" aria-label="Kind" style={{ marginBottom: 8 }}>
          {(['door', 'window', 'opening'] as const).map(k => (
            <button key={k} className={'tool' + (seg.kind === k ? ' on' : '')} aria-pressed={seg.kind === k}
              onClick={() => put(k === 'window' && seg.kind !== 'window' ? setOpeningHeight(plan, { ...seg, kind: k }, Math.min(seg.height, 1.4), 0.85) : k !== 'window' && seg.kind === 'window' ? setOpeningHeight(plan, { ...seg, kind: k }, 2.05, 0) : { ...seg, kind: k })}>{openingLabel(k)}</button>
          ))}
        </div>
        <SizeRow label="Width" value={width} min={0.3} onChange={(v, u) => put(resizeOpening(plan, seg, v), u)} />
        <SizeRow label="Height" value={seg.height} min={0.3} max={SIZE_LIMITS.heightMax} onChange={(v, u) => put(setOpeningHeight(plan, seg, v, seg.bottom), u)} />
        {seg.kind === 'window' && <SizeRow label="Sill" value={seg.bottom} min={0} max={SIZE_LIMITS.heightMax} onChange={(v, u) => put(setOpeningHeight(plan, seg, seg.height, v), u)} />}
        {seg.kind === 'door' && (
          <label className="toggle" style={{ margin: '8px 0' }}><input type="checkbox" checked={seg.isOpen} onChange={e => put({ ...seg, isOpen: e.target.checked })} /> Open (light passes through it)</label>
        )}
        <div className="actions" style={{ marginTop: 12 }}>
          <button className="btn small" onClick={duplicate}><Icon name="copy" /> Another beside it</button>
          <button className="btn small danger" onClick={remove}><Icon name="trash" /> Delete</button>
        </div>
        <p className="note">Drag it to slide it along the wall or onto another wall.{seg.kind === 'window' ? ' Units outside the room light it through the glass, at the Light through windows setting.' : ''}</p>
        <ByHandNote byHand={seg.byHand} what={openingLabel(seg.kind).toLowerCase()} />
      </Panel>
    </div>
  );
}

// MARK: Lights

const roles: LightRole[] = ['key', 'fill', 'back', 'edge', 'background', 'ambient', 'practical', 'effect'];

function LightInspector(p: InspectorProps & { light: LightFixture }) {
  const l = p.light;
  const info = KIND_INFO[l.kind];
  const set = (patch: Partial<LightFixture>, undo = true) => p.edit(loc => ({ ...loc, lights: (loc.lights ?? []).map(x => (x.id === l.id ? { ...x, ...patch } : x)) }), undo);
  const replace = (n: LightFixture) => p.edit(loc => ({ ...loc, lights: (loc.lights ?? []).map(x => (x.id === l.id ? n : x)) }));
  const remove = () => { p.edit(loc => ({ ...loc, lights: (loc.lights ?? []).filter(x => x.id !== l.id) })); p.select(undefined); };
  const duplicate = () => {
    const copy = { ...structuredClone(l), id: crypto.randomUUID().toUpperCase(), name: l.name + ' 2', position: { x: l.position.x + 0.4, z: l.position.z + 0.4 } };
    p.edit(loc => ({ ...loc, lights: [...(loc.lights ?? []), copy] }));
    p.select({ kind: 'light', id: copy.id });
  };

  const header = (
    <section className="panel">
      <div className="panel-title">
        {info.emits && (
          <button className={'btn small' + (l.isOn ? ' primary' : '')} onClick={() => set({ isOn: !l.isOn })} aria-pressed={l.isOn} title={l.isOn ? 'Switch off' : 'Switch on'}>
            <Icon name="power" /> {l.isOn ? 'On' : 'Off'}
          </button>
        )}
        <input className="name" value={l.name} onChange={e => set({ name: e.target.value }, false)} aria-label="Name" />
      </div>
      <div className="actions" style={{ marginTop: 12 }}>
        <button className="btn small" onClick={() => p.aimMode(true)}><Icon name="aim" /> Aim at…</button>
        <button className="btn small" onClick={duplicate}><Icon name="copy" /> Duplicate</button>
        <button className="btn small danger" onClick={remove}><Icon name="trash" /> Delete</button>
      </div>
    </section>
  );

  if (!info.emits) {
    return (
      <div>
        {header}
        <Panel title={info.label}>
          <div className="chips" style={{ marginBottom: 12 }}>
            {(['bounce', 'negative', 'flag', 'diffusion'] as const).map(k => <button key={k} className={'chip' + (l.kind === k ? ' on' : '')} onClick={() => set({ kind: k })}>{KIND_INFO[k].label}</button>)}
          </div>
          <Slider label="Width" value={l.width} min={0.1} max={6} step={0.05} format={metres} onChange={v => set({ width: v }, false)} />
          <Slider label="Frame height" value={l.boardHeight ?? l.width} min={0.1} max={6} step={0.05} format={metres} onChange={v => set({ boardHeight: v }, false)} />
          <Slider label="Height" value={l.height} min={0.2} max={6} step={0.05} format={metres} onChange={v => set({ height: v }, false)} />
          <Slider label="Facing" value={((l.pan % 360) + 360) % 360} min={0} max={360} step={1} format={deg} onChange={v => set({ pan: v }, false)} />
          <StandField light={l} replace={replace} />
          <p className="note">{l.kind === 'bounce' ? 'Re-emits light that lands on it (one bounce, 80 % white board).' : l.kind === 'diffusion' ? 'Passes half the light that goes through it.' : 'Blocks light that goes through it.'}</p>
        </Panel>
        <NotesPanel value={l.notes} onChange={v => set({ notes: v }, false)} />
      </div>
    );
  }

  const pm = photometrics(l);
  const profile = fixtureProfile(l);
  const mods = modifiersFor(profile);
  const currentMod = fixtureModifier(l);
  const usesRGB = profile.color.rgb && l.colorMode === 'rgb';
  const filterIDs = l.filterIDs ?? [];
  const categories = [...new Set(profiles.map(x => x.category))] as FixtureCategory[];

  const atMeters = p.meters.map(m => {
    const r = calcReading(m.point, m.normal, p.scene);
    const own = r.contributions.filter(c => c.lightID === l.id).reduce((s, c) => s + c.lux, 0);
    return { m, own, total: r.lux };
  }).filter(x => x.own > 0.05);

  const setToKey = (m: MeterPoint) => {
    const target = m.targetLux ?? keyLux(p.exposure);
    const sol = solveOutput(l, target, m.point, m.normal, p.lights, p.plan, p.windowTransmission);
    if (sol.kind === 'output') set({ dimmer: Math.round(sol.output * 100) / 100, isOn: true });
    else alert(sol.kind === 'tooDim' ? `Even at full this unit gives about ${fmtLux(sol.maxLux)} there.${sol.suggestedDistance ? ` Move it to about ${metres(sol.suggestedDistance)} away.` : ''}`
      : sol.kind === 'atMinimum' ? `At its lowest (${Math.round(sol.output * 100)} %) this unit still gives about ${fmtLux(sol.lux)} there. Move it back, or add ND or diffusion.`
      : sol.kind === 'othersTooBright' ? `The other units already give about ${fmtLux(sol.othersLux)} there.` : "This unit doesn't reach that point.");
  };

  return (
    <div>
      {header}
      <Panel title="Unit">
        <label className="field"><span>Fixture</span>
          <select value={profile.id} onChange={e => replace(applyProfile(l, profiles.find(x => x.id === e.target.value)!))} aria-label="Fixture type">
            {categories.map(cat => <optgroup key={cat} label={categoryLabel[cat]}>{profiles.filter(x => x.category === cat).map(x => <option key={x.id} value={x.id}>{x.name}</option>)}</optgroup>)}
          </select><span />
        </label>
        <label className="field"><span>Role</span>
          <select value={l.role ?? ''} onChange={e => { const v = e.target.value as LightRole | ''; const n = { ...l }; if (v) n.role = v; else delete n.role; replace(n); }} aria-label="Role">
            <option value="">None</option>
            {roles.map(r => <option key={r} value={r}>{r[0].toUpperCase() + r.slice(1)}</option>)}
          </select><span />
        </label>
        <Slider label="Output" value={l.dimmer} min={profile.minOutput} max={1} step={0.01} format={pct} onChange={v => set({ dimmer: v }, false)} />
        {profile.color.rgb && (
          <div className="field"><span>Colour</span>
            <div className="chips">
              <button className={'chip' + (!usesRGB ? ' on' : '')} onClick={() => set({ colorMode: 'cct' })}>White</button>
              <button className={'chip' + (usesRGB ? ' on' : '')} onClick={() => set({ colorMode: 'rgb', hue: l.hue ?? 0, saturation: l.saturation ?? 1 })}>Colour</button>
            </div><span />
          </div>
        )}
        {usesRGB ? (
          <>
            <Slider label="Hue" value={l.hue ?? 0} min={0} max={360} step={1} format={deg} onChange={v => set({ hue: v }, false)} />
            <Slider label="Saturation" value={l.saturation ?? 1} min={0} max={1} step={0.01} format={pct} onChange={v => set({ saturation: v }, false)} />
          </>
        ) : isAdjustable(profile.color) ? (
          <>
            <Slider label="Colour temp." value={l.colorTemperature} min={profile.color.minKelvin} max={profile.color.maxKelvin} step={50} format={v => `${Math.round(v)} K`} onChange={v => set({ colorTemperature: v }, false)} />
            <div className="chips" style={{ marginLeft: 122 }}>
              {kelvinPresets.filter(k => k >= profile.color.minKelvin && k <= profile.color.maxKelvin).map(k => <button key={k} className={'chip' + (Math.abs(l.colorTemperature - k) < 1 ? ' on' : '')} onClick={() => set({ colorTemperature: k })}>{k} K</button>)}
            </div>
          </>
        ) : <p className="note">{profile.color.minKelvin} K fixed{filterIDs.length ? ` · gelled to ${Math.round(pm.kelvin)} K` : ''}</p>}
      </Panel>

      <Panel title="At meters and faces">
        {atMeters.length ? atMeters.map(({ m, own, total }) => (
          <div key={m.key} className="meter-row">
            <span className="stack2"><span>{m.name}</span><span className="mono muted" title="This unit's share of the total">{readingUnit() === 'tStop' ? `≈ ${fmtReading(total, p.exposure)} · this light alone ${fmtReading(own, p.exposure)}`
              : readingUnit() === 'stops' ? readingText(total, p.exposure)
              : `≈ ${fmtReading(own, p.exposure)} of ${fmtReading(total, p.exposure)} · ${stopsDelta(stopsForLux(p.exposure, total))}`}</span></span>
            <span />
            <button className="btn small" onClick={() => setToKey(m)} title={`Set output so ${m.name} reads ${m.targetLux ? fmtLux(m.targetLux) : 'key'}`}>Set to {m.targetLux ? 'target' : 'key'}</button>
          </div>
        )) : <p className="note">Doesn't reach any meter or person. Aim it, or add a meter where you want a reading.</p>}
        <p className="note"><Badge /> Direct light and one bounce off boards. Room reflections aren't included, so real interiors read brighter.</p>
      </Panel>

      <Panel title="Placement">
        <Slider label="Height" value={l.height} min={0.2} max={6} step={0.05} format={metres} onChange={v => set({ height: v }, false)} />
        <Slider label="Pan" value={((l.pan % 360) + 360) % 360} min={0} max={360} step={1} format={deg} onChange={v => set({ pan: v }, false)} />
        <Slider label="Tilt" value={l.tilt} min={-90} max={45} step={1} format={signedDeg} onChange={v => set({ tilt: v }, false)} />
        <StandField light={l} replace={replace} />
      </Panel>

      <Panel title="Advanced · beam and shaping" collapsible open={false}>
        <label className="field"><span>Modifier</span>
          <select value={l.modifierID ?? currentMod?.id ?? 'none'} onChange={e => set({ modifierID: e.target.value })} aria-label="Modifier">
            {profile.defaultModifierID === undefined && <option value="none">None</option>}
            {mods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
          </select><span />
        </label>
        {pm.beamIsAdjustable && pm.beamRange && (
          <Slider label="Beam" value={Math.min(Math.max(l.beamAngle, pm.beamRange[0]), pm.beamRange[1])} min={pm.beamRange[0]} max={pm.beamRange[1]} step={1} format={v => `${Math.round(v)}°`} onChange={v => set({ beamAngle: v }, false)} />
        )}
        {!pm.beamIsAdjustable && <p className="note">Beam {pm.distribution === 'beam' ? `${Math.round(pm.beamAngle)}°` : pm.distribution === 'lambertian' ? 'soft (≈120°)' : 'all round'}.</p>}
        <div className="label" style={{ margin: '12px 0 6px' }}>Gels, ND and diffusion</div>
        <div className="chips">
          {filters.map(f => {
            const on = filterIDs.includes(f.id);
            return <button key={f.id} className={'chip' + (on ? ' on' : '')} title={`Passes ${Math.round(f.transmission * 100)} %`}
              onClick={() => set({ filterIDs: on ? filterIDs.filter(x => x !== f.id) : [...filterIDs, f.id] })}>{f.name}</button>;
          })}
        </div>
        {pm.barnDoorsAvailable && (
          <>
            <div className="label" style={{ margin: '14px 0 6px' }}>Barn doors (angle from the beam centre, 90° = open)</div>
            {(['top', 'bottom', 'left', 'right'] as const).map(side => (
              <Slider key={side} label={side[0].toUpperCase() + side.slice(1)} value={(l.barnDoors ?? { top: 90, bottom: 90, left: 90, right: 90 })[side]} min={0} max={90} step={1} format={v => `${Math.round(v)}°`}
                onChange={v => set({ barnDoors: { ...(l.barnDoors ?? { top: 90, bottom: 90, left: 90, right: 90 }), [side]: v } }, false)} />
            ))}
          </>
        )}
      </Panel>

      <Panel title="Advanced · throw and photometric data" collapsible open={false}>
        <div className="readout" style={{ marginBottom: 14 }}>
          <div><div className="label">Draw</div><div className="v">≈ {watts(pm.drawWatts)}</div></div>
          <div><div className="label">At 3 m on axis</div><div className="v">≈ {fmtLux(illuminanceOnAxis(pm, 3))}</div></div>
        </div>
        <ThrowTable light={l} exposure={p.exposure} />
        <OverrideEditor light={l} replace={replace} />
        {pm.notes.map((n, i) => <p key={i} className="note">{n}</p>)}
      </Panel>

      <NotesPanel value={l.notes} onChange={v => set({ notes: v }, false)} />
    </div>
  );
}

function StandField({ light, replace }: { light: LightFixture; replace(l: LightFixture): void }) {
  const warning = lightSupportWarning(light);
  return (
    <>
      <label className="field"><span>Stand</span>
        <select value={(light.support as string | undefined) ?? ''} aria-label="Stand"
          onChange={e => { const n = { ...light }; if (e.target.value) n.support = e.target.value; else delete n.support; replace(n); }}>
          <option value="">Automatic · {lightSupportInfo(automaticLightSupport(light)).label}</option>
          {LIGHT_SUPPORTS.map(x => <option key={x.id} value={x.id}>{x.label}</option>)}
        </select><span />
      </label>
      {warning && <p className="note">{warning}</p>}
    </>
  );
}

function ThrowTable({ light, exposure }: { light: LightFixture; exposure: ExposureSettings }) {
  const pm = photometrics(light);
  const key = keyLux(exposure);
  const reach = distanceForLux(pm, key);
  return (
    <div>
      {[1, 2, 3, 5, 8].map(d => {
        const v = illuminanceOnAxis(pm, d);
        return <div key={d} className="meter-row"><span className="mono">{d} m</span><span className="mono">≈ {fmtLux(v)}</span><span className="mono muted">{stopLabel(Math.sqrt(v * exposure.iso * exposureTime(exposure) / (250 * Math.pow(2, exposure.ndStops))))}</span></div>;
      })}
      <p className="note">On the beam's centre, nothing in the way. {reach ? `Gives key (${fmtLux(key)}) at about ${metres(reach)}.` : `Can't reach key (${fmtLux(key)}) even up close.`}</p>
    </div>
  );
}

function OverrideEditor({ light, replace }: { light: LightFixture; replace(l: LightFixture): void }) {
  const o = light.photometricOverride;
  const [luxV, setLux] = useState(o?.lux ?? 0);
  const [dist, setDist] = useState(o?.distance ?? 3);
  return (
    <div style={{ marginTop: 12 }}>
      <div className="label" style={{ marginBottom: 6 }}>Your own reading for this unit (from the maker's sheet or a meter)</div>
      <div className="field"><span>Lux</span><input type="number" min={0} value={luxV || ''} placeholder="e.g. 4500" onChange={e => setLux(Number(e.target.value))} /><span /></div>
      <div className="field"><span>At distance (m)</span><input type="number" min={0.3} step={0.1} value={dist} onChange={e => setDist(Number(e.target.value))} /><span /></div>
      <div className="actions">
        <button className="btn small" disabled={!(luxV > 0 && dist > 0)} onClick={() => replace({ ...light, photometricOverride: { lux: luxV, distance: dist, provenance: 'manual', note: 'Entered on the web' } })}>Use my reading</button>
        {o && <button className="btn small" onClick={() => { const n = { ...light }; delete n.photometricOverride; replace(n); }}>Back to estimate</button>}
      </div>
      {o && <p className="note">✎ Manual: {Math.round(o.lux)} lx at {o.distance} m.</p>}
    </div>
  );
}

function NotesPanel({ value, onChange }: { value: string; onChange(v: string): void }) {
  return (
    <Panel title="Notes">
      <textarea rows={3} value={value} onChange={e => onChange(e.target.value)} placeholder="Rigging, power, gel cuts…" aria-label="Notes" />
    </Panel>
  );
}

// MARK: People

function CharacterInspector(p: InspectorProps & { character: PrevisCharacter }) {
  const c = p.character;
  const set = (patch: Partial<PrevisCharacter>, undo = true) => p.edit(loc => ({ ...loc, characters: (loc.characters ?? []).map(x => (x.id === c.id ? { ...x, ...patch } : x)) }), undo);
  const remove = () => { p.edit(loc => ({ ...loc, characters: (loc.characters ?? []).filter(x => x.id !== c.id) })); p.select(undefined); };
  const r = p.readings.get('c:' + c.id);
  const [setupNote, setSetupNote] = useState<{ id: string; text: string }>();
  // Places a lighting setup round this person, set for the camera's exposure (one undo step).
  const lightWith = (id: LightingSetup, label: string) => {
    const camera = cameraSeeing(c.position, meterCameras(p.location))?.position;
    const built = buildSetup(id, c, camera, p.exposure, p.plan, p.windowTransmission);
    if (!built.lights.length) return;
    p.edit(loc => ({ ...loc, lights: [...(loc.lights ?? []), ...built.lights] }));
    setSetupNote({ id: c.id, text: `${label}${camera ? '' : ' (no camera yet: lit from where they face)'}. ${built.notes.join(' · ')}. Undo removes it.` });
  };
  return (
    <div>
      <section className="panel">
        <div className="panel-title"><input className="name" value={c.name} onChange={e => set({ name: e.target.value }, false)} aria-label="Name" /></div>
        {r !== undefined && p.lights.length > 0 && (
          <div style={{ marginTop: 10 }}>
            <div className="label">Face</div>
            <div className="mono" style={{ fontSize: 18 }}>{readingText(r, p.exposure)}</div>
            <p className="note">Skin reads {stopsDelta(skinStopsFromGrey(c.skinTone) + stopsForLux(p.exposure, r))} against mid grey (skin reflectance included). <Badge /></p>
          </div>
        )}
        <div className="actions" style={{ marginTop: 12 }}>
          <button className="btn small danger" onClick={remove}><Icon name="trash" /> Delete</button>
        </div>
      </section>
      <Panel title="Light this person">
        <div className="chips">
          {LIGHTING_SETUPS.map(s => <button key={s.id} className="chip" title={s.summary} onClick={() => lightWith(s.id, s.label)}>{s.label}</button>)}
        </div>
        <p className="note">{setupNote?.id === c.id ? <>{setupNote.text} <Badge /></> : 'Adds a starting setup round them, levelled for the set stop. Hover a setup to see what it places.'}</p>
      </Panel>
      <Panel title="Person">
        <div className="chips" style={{ marginBottom: 10 }}>
          {(['man', 'woman', 'girl', 'boy'] as CharacterType[]).map(t => <button key={t} className={'chip' + (c.type === t ? ' on' : '')} onClick={() => set({ type: t, height: characterDefaults[t] })}>{t[0].toUpperCase() + t.slice(1)}</button>)}
        </div>
        <div className="chips" style={{ marginBottom: 10 }}>
          {(['standing', 'sitting'] as const).map(t => <button key={t} className={'chip' + (c.posture === t ? ' on' : '')} onClick={() => set({ posture: t })}>{t[0].toUpperCase() + t.slice(1)}</button>)}
        </div>
        <Slider label="Height" value={c.height} min={c.type === 'girl' || c.type === 'boy' ? 0.8 : 1.4} max={c.type === 'girl' || c.type === 'boy' ? 1.75 : 2.1} step={0.01} format={metres} onChange={v => set({ height: v }, false)} />
        <Slider label="Build" value={c.build} min={0} max={1} step={0.05} format={v => (v < 0.2 ? 'Slim' : v < 0.4 ? 'Lean' : v < 0.6 ? 'Average' : v < 0.8 ? 'Solid' : 'Heavy')} onChange={v => set({ build: v }, false)} />
        <Slider label="Facing" value={((c.facing % 360) + 360) % 360} min={0} max={360} step={1} format={deg} onChange={v => set({ facing: v }, false)} />
        <div className="field"><span>Skin</span>
          <div className="chips">{skinRGB.map((col, i) => <button key={i} className={'swatch' + (c.skinTone === i + 1 ? ' on' : '')} style={{ background: col }} title={skinTones[i]} aria-label={skinTones[i]} onClick={() => set({ skinTone: i + 1 })} />)}</div><span />
        </div>
      </Panel>
    </div>
  );
}

// MARK: Meters

function MeterInspector(p: InspectorProps & { meter: LightMeter }) {
  const m = p.meter;
  const set = (patch: Partial<LightMeter>, undo = true) => p.edit(loc => ({ ...loc, meters: (loc.meters ?? []).map(x => (x.id === m.id ? { ...x, ...patch } : x)) }), undo);
  const remove = () => { p.edit(loc => ({ ...loc, meters: (loc.meters ?? []).filter(x => x.id !== m.id) })); p.select(undefined); };
  const r = p.readings.get('m:' + m.id);
  const mp = p.meters.find(x => x.key === 'm:' + m.id);
  const breakdown = mp ? calcReading(mp.point, mp.normal, p.scene).contributions : [];
  return (
    <div>
      <section className="panel">
        <div className="panel-title"><input className="name" value={m.name} onChange={e => set({ name: e.target.value }, false)} aria-label="Name" /></div>
        {r !== undefined && <div className="mono" style={{ fontSize: 18, marginTop: 10 }}>{readingText(r, p.exposure)}</div>}
        <div className="actions" style={{ marginTop: 12 }}><button className="btn small danger" onClick={remove}><Icon name="trash" /> Delete</button></div>
      </section>
      <Panel title="Meter">
        <Slider label="Height" value={m.height} min={0} max={3} step={0.05} format={metres} onChange={v => set({ height: v }, false)} />
        <div className="field"><span>Facing</span>
          <select value={m.facing} onChange={e => set({ facing: e.target.value as LightMeter['facing'] })}>
            <option value="camera">Towards camera</option><option value="bearing">Fixed direction</option><option value="up">Up (table top)</option>
          </select><span />
        </div>
        {m.facing === 'bearing' && <Slider label="Direction" value={m.bearing} min={0} max={360} step={1} format={deg} onChange={v => set({ bearing: v }, false)} />}
        <div className="field"><span>Target lux</span>
          <input type="number" min={0} value={m.targetLux ?? ''} placeholder={`key ${Math.round(keyLux(p.exposure))}`} onChange={e => { const v = Number(e.target.value); const n = { ...m }; if (v > 0) n.targetLux = v; else delete n.targetLux; p.edit(loc => ({ ...loc, meters: (loc.meters ?? []).map(x => (x.id === m.id ? n : x)) }), false); }} />
          <span />
        </div>
      </Panel>
      {breakdown.length > 0 && (
        <Panel title="Where the light comes from">
          {breakdown.sort((a, b) => b.lux - a.lux).map((c, i) => {
            const l = p.lights.find(x => x.id === c.lightID);
            const via = c.viaBounce ? p.lights.find(x => x.id === c.viaBounce) : undefined;
            return <div key={i} className="meter-row"><span>{l?.name ?? 'Unit'}{via ? ` via ${via.name}` : ''}</span><span className="mono">≈ {fmtLux(c.lux)}</span><span /></div>;
          })}
        </Panel>
      )}
    </div>
  );
}

// MARK: Cameras

function CameraInspector(p: InspectorProps) {
  const s = p.selection!;
  const shot = s.kind === 'shot' ? p.location.shots.find(x => x.id === s.id) : undefined;
  const cam = s.kind === 'camera' ? p.location.cameraPositions.find(x => x.id === s.id) : undefined;
  const rig = shot?.rig ?? cam?.rig;
  if (!rig) return <Overview {...p} />;
  const setRig = (patch: Partial<CameraRig>, undo = true) => p.edit(loc => ({
    ...loc,
    shots: loc.shots.map(x => (x.id === s.id ? { ...x, rig: { ...x.rig, ...patch } } : x)),
    cameraPositions: loc.cameraPositions.map(x => (x.id === s.id ? { ...x, rig: { ...x.rig, ...patch } } : x)),
  }), undo);
  const title = shot ? `SHOT ${String(shot.number).padStart(2, '0')}${shot.title ? ' · ' + shot.title : ''}` : cam!.name;
  return (
    <div>
      <section className="panel"><div style={{ fontSize: 18, fontWeight: 400 }}>{title}</div><p className="mono muted">{Math.round(rig.focalLength)}mm · {Math.round(horizontalFOV(rig))}° horizontal</p></section>
      <Panel title="Camera">
        <Slider label="Focal length" value={rig.focalLength} min={10} max={200} step={1} format={v => `${Math.round(v)}mm`} onChange={v => setRig({ focalLength: v }, false)} />
        <Slider label="Lens height" value={rig.height} min={0.1} max={4} step={0.05} format={metres} onChange={v => setRig({ height: v }, false)} />
        <Slider label="Pan" value={((rig.pan % 360) + 360) % 360} min={0} max={360} step={1} format={deg} onChange={v => setRig({ pan: v }, false)} />
        <label className="field"><span>Support</span>
          <select value={(rig.support as string | undefined) ?? ''} aria-label="Camera support" onChange={e => setRig({ support: e.target.value || undefined })}>
            <option value="">Automatic · {cameraSupportInfo(automaticCameraSupport(rig.height)).label}</option>
            {CAMERA_SUPPORTS.map(x => <option key={x.id} value={x.id}>{x.label}</option>)}
          </select><span />
        </label>
        {cameraSupportWarning(rig) && <p className="note">{cameraSupportWarning(rig)}</p>}
        <label className="field"><span>Sensor</span>
          <select value={rig.sensorID} onChange={e => setRig({ sensorID: e.target.value })}>
            {sensorPresets.map(x => <option key={x.id} value={x.id}>{x.manufacturer ? x.manufacturer + ' ' : ''}{x.name}</option>)}
          </select><span />
        </label>
        <p className="note">Cameras and shots are planned on the phone; moving one here moves it there too.</p>
      </Panel>
    </div>
  );
}

// MARK: Overview (nothing selected)

function Overview(p: InspectorProps) {
  const e = p.exposure;
  const setE = (patch: Partial<ExposureSettings>) => p.edit(loc => ({ ...loc, exposure: { ...e, ...patch } }));
  const emitters = p.lights.filter(l => KIND_INFO[l.kind].emits);
  const totalDraw = emitters.reduce((s, l) => s + photometrics(l).drawWatts, 0);
  return (
    <div>
      <Panel title="Exposure">
        <div className="readout">
          <div><div className="label">Key</div><div className="v">≈ {fmtLux(keyLux(e))}</div></div>
          <div><div className="label">Stop</div><div className="v">{stopLabel(e.tStop)}</div></div>
        </div>
        <div className="field" style={{ marginTop: 12 }}><span>ISO</span><select value={e.iso} onChange={x => setE({ iso: Number(x.target.value) })}>{isoPresets.map(v => <option key={v} value={v}>{v}</option>)}</select><span /></div>
        <div className="field"><span>Frame rate</span><select value={e.frameRate} onChange={x => setE({ frameRate: Number(x.target.value) })}>{frameRates.map(v => <option key={v} value={v}>{trim(v)} fps</option>)}</select><span /></div>
        <div className="field"><span>Shutter</span><select value={e.shutterAngle} onChange={x => setE({ shutterAngle: Number(x.target.value) })}>{shutterAngles.map(v => <option key={v} value={v}>{trim(v)}°</option>)}</select><span className="val">{speedLabel(exposureTime(e))}</span></div>
        <div className="field"><span>T-stop</span><select value={e.tStop} onChange={x => setE({ tStop: Number(x.target.value) })}>{tStops.map(v => <option key={v} value={v}>{stopLabel(v)}</option>)}</select><span className="val" title="Aperture geometry for this lens">f/{fStop(e).toFixed(1)}</span></div>
        <div className="field"><span>ND</span><select value={e.ndStops} onChange={x => setE({ ndStops: Number(x.target.value) })}>{[0, 1, 2, 3, 4, 5, 6].map(v => <option key={v} value={v}>{v === 0 ? 'None' : `ND ${(v * 0.3).toFixed(1)} (${v} stop${v > 1 ? 's' : ''})`}</option>)}</select><span /></div>
        <p className="note">An incident reading of {fmtLux(keyLux(e))} exposes a subject correctly at these settings. T-stops include lens loss; a T-stop is a camera setting, not scene brightness.</p>
      </Panel>
      <Panel title="Readings">
        <div className="field"><span>Show as</span><select value={readingUnit()} onChange={x => setReadingUnit(x.target.value as ReadingUnit)}>{READING_UNITS.map(([v, label]) => <option key={v} value={v}>{label}</option>)}</select><span /></div>
        {p.meters.length ? p.meters.map(m => {
          const r = p.readings.get(m.key) ?? 0;
          return (
            <button key={m.key} className="meter-row row" style={{ display: 'grid', padding: '8px 0' }} onClick={() => p.select('meter' in m.source ? { kind: 'meter', id: m.source.meter } : { kind: 'character', id: m.source.character })}>
              <span>{m.name}</span><span className="mono">≈ {fmtReading(r, e)}</span><span className="mono muted">{readingUnit() === 'lux' || readingUnit() === 'footCandles' ? stopsDelta(stopsForLux(e, r)) : ''}</span>
            </button>
          );
        }) : <p className="note">Add a person or a meter to see readings.</p>}
        {p.meters.length > 0 && <p className="note"><Badge /> Direct light plus one bounce. No room reflections or daylight.</p>}
      </Panel>
      <Panel title="Lights">
        {p.lights.length ? p.lights.map(l => (
          <button key={l.id} className="meter-row row" style={{ display: 'grid', padding: '8px 0' }} onClick={() => p.select({ kind: 'light', id: l.id })}>
            <span>{l.name}</span><span className="muted" style={{ fontSize: 12 }}>{KIND_INFO[l.kind].emits ? fixtureProfile(l).name.split(' · ')[0] : KIND_INFO[l.kind].label}</span>
            <span className="mono muted">{KIND_INFO[l.kind].emits ? (l.isOn ? pct(l.dimmer) : 'off') : ''}</span>
          </button>
        )) : <p className="note">No lights yet. Pick a unit in the toolbar and click the plan.</p>}
        {emitters.length > 0 && <p className="note">Total draw ≈ {watts(totalDraw)} (estimated from rated power and output).</p>}
      </Panel>
      <Panel title="Light through windows" collapsible open={false}>
        <Slider label="Glass passes" value={p.windowTransmission} min={0} max={1} step={0.01} format={pct}
          onChange={v => p.edit(loc => ({ ...loc, display: { ...(loc.display ?? {}), windowTransmission: v } }), false)} />
      </Panel>
    </div>
  );
}

