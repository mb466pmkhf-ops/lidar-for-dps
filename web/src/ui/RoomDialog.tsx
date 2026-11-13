// "Draw a room": a starting shape and typed sizes become a floor plan, which the 3D view then
// raises into walls. Sizes are typed, so nothing here is labelled as measured.
import { useState } from 'react';
import type { Project } from '../model/types';
import { LengthStepper } from './LengthStepper';
import { area, useLengthUnits } from './format';
import { ROOM_LIMITS, defaultRoom, normalise, roomArea, roomOutline, buildRoomPlan, type RoomSpec } from '../model/room';

function Stepper({ label, note, value, step, min, max, unit, onChange }: { label: string; note?: string; value: number; step: number; min: number; max: number; unit: string; onChange(v: number): void }) {
  const set = (v: number) => onChange(Math.round(Math.min(max, Math.max(min, v)) * 100) / 100);
  return (
    <div className="stepper">
      <span><span style={{ display: 'block' }}>{label}</span>{note && <span className="note" style={{ margin: 0 }}>{note}</span>}</span>
      <span className="ctl">
        <button type="button" aria-label={`Less ${label.toLowerCase()}`} onClick={() => set(value - step)}>−</button>
        <input type="text" inputMode="decimal" aria-label={`${label} in ${unit}`} value={String(value)} onChange={e => { const n = parseFloat(e.target.value.replace(',', '.')); if (Number.isFinite(n)) onChange(n); }} onBlur={() => set(value)} />
        <span className="unit" aria-hidden="true">{unit === 'metres' ? 'm' : ''}</span>
        <button type="button" aria-label={`More ${label.toLowerCase()}`} onClick={() => set(value + step)}>+</button>
      </span>
    </div>
  );
}

export function RoomDialog({ projects, currentProjectID, onCreate, onClose }: {
  projects: Project[]; currentProjectID?: string;
  onCreate(name: string, spec: RoomSpec, projectID: string | undefined): void; onClose(): void;
}) {
  useLengthUnits();
  const [name, setName] = useState('New room');
  const [spec, setSpec] = useState<RoomSpec>(defaultRoom);
  const [projectID, setProjectID] = useState(currentProjectID ?? projects[0]?.id ?? '');
  const s = normalise(spec);
  const plan = buildRoomPlan(s);
  const outline = roomOutline(s);
  const k = Math.min(300 / s.length, 140 / s.width);
  const x = (v: number) => 180 + v * k, z = (v: number) => 90 + v * k;
  const patch = (p: Partial<RoomSpec>) => setSpec({ ...spec, ...p });
  return (
    <div className="scrim" onClick={onClose}>
      <form className="dialog" role="dialog" aria-modal="true" aria-label="Draw a room" onClick={e => e.stopPropagation()}
        onSubmit={e => { e.preventDefault(); onCreate(name, s, projectID || undefined); }}>
        <h2>Draw a room</h2>
        <p>Pick a starting shape and type the sizes. You get a floor plan and a 3D room to light.</p>
        <div className="stack">
          <input type="text" value={name} onChange={e => setName(e.target.value)} aria-label="Room name" placeholder="Room name" />
          <div className="shape-row" role="group" aria-label="Starting shape">
            <button type="button" className={'shape' + (s.shape === 'box' ? ' on' : '')} aria-pressed={s.shape === 'box'} onClick={() => patch({ shape: 'box' })}>
              <svg width="40" height="28" viewBox="0 0 40 28" fill="none" stroke="currentColor" strokeWidth="2.5" aria-hidden="true"><rect x="4" y="4" width="32" height="20" /></svg>Box
            </button>
            <button type="button" className={'shape' + (s.shape === 'l' ? ' on' : '')} aria-pressed={s.shape === 'l'} onClick={() => patch({ shape: 'l' })}>
              <svg width="40" height="28" viewBox="0 0 40 28" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinejoin="round" aria-hidden="true"><path d="M4 4h32v10H20v10H4z" /></svg>L shape
            </button>
          </div>
          <svg className="room-preview" viewBox="0 0 360 180" role="img" aria-label={`Preview: ${s.length} by ${s.width} metres`}>
            <polygon points={outline.map(p => `${x(p.x)},${z(p.z)}`).join(' ')} fill="var(--floor)" stroke="var(--wall)" strokeWidth={3} strokeLinejoin="miter" />
            {plan.windows.map(w => <line key={w.id} x1={x(w.a.x)} y1={z(w.a.z)} x2={x(w.b.x)} y2={z(w.b.z)} stroke="var(--window)" strokeWidth={4} />)}
            {plan.doors.map(w => <line key={w.id} x1={x(w.a.x)} y1={z(w.a.z)} x2={x(w.b.x)} y2={z(w.b.z)} stroke="var(--door)" strokeWidth={4} />)}
          </svg>
          <LengthStepper label="Length" value={spec.length} min={ROOM_LIMITS.min} max={ROOM_LIMITS.max} onChange={v => patch({ length: v })} />
          <LengthStepper label="Width" value={spec.width} min={ROOM_LIMITS.min} max={ROOM_LIMITS.max} onChange={v => patch({ width: v })} />
          <LengthStepper label="Ceiling height" note="Used to build the 3D room" value={spec.ceiling} min={ROOM_LIMITS.ceilingMin} max={ROOM_LIMITS.ceilingMax} onChange={v => patch({ ceiling: v })} />
          <Stepper label="Windows" note="Along the top wall" value={spec.windows} step={1} min={0} max={4} unit="count" onChange={v => patch({ windows: v })} />
          <label className="toggle"><input type="checkbox" checked={spec.door} onChange={e => patch({ door: e.target.checked })} /> Add a door on the left wall</label>
          {projects.length > 0 && (
            <label style={{ display: 'grid', gap: 4 }}><span className="label">Add it to</span>
              <select value={projectID} onChange={e => setProjectID(e.target.value)}>
                {projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                <option value="">A new project</option>
              </select>
            </label>
          )}
        </div>
        <p className="note">Floor area {area(roomArea(s))}. Sizes you type are saved as entered by hand, not as measurements.</p>
        <div className="actions" style={{ justifyContent: 'flex-end', marginTop: 16 }}>
          <button type="button" className="btn ghost" onClick={onClose}>Cancel</button>
          <button type="submit" className="btn primary">Build the room</button>
        </div>
      </form>
    </div>
  );
}
