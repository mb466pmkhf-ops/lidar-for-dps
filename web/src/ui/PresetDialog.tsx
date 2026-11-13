// "My presets": save the lights you placed as your own setup, and tune or share the ones you have.
// Same fields and labels as the phone (FrameScout/Features/Plan/LightingPresetViews.swift).
import { useState } from 'react';
import { LengthStepper } from './LengthStepper';
import type { ExposureSettings, FloorPlan, LightFixture, PlanPoint, PlanSegment, PrevisCharacter } from '../model/types';
import { ANCHOR_LABEL, capturePersonPreset, captureWindowPreset, decodePresets, encodePresets, nearestWindow, presetSummary, type LightingPreset, type PresetAnchor, type PresetUnit } from '../model/presets';
import { planDist } from '../model/calculator';
import { KIND_INFO, fixtureProfile } from '../model/photometrics';
import { addPreset, removePreset, savePresets, updatePreset, usePresets } from './presetStore';

function Step({ label, value, step, min, max, unit, onChange }: { label: string; value: number; step: number; min: number; max: number; unit: string; onChange(v: number): void }) {
  const set = (v: number) => onChange(Math.round(Math.min(max, Math.max(min, v)) * 100) / 100);
  return (
    <div className="stepper compact">
      <span>{label}</span>
      <span className="ctl">
        <button type="button" aria-label={`Less ${label.toLowerCase()}`} onClick={() => set(value - step)}>−</button>
        <input type="text" inputMode="decimal" aria-label={`${label} in ${unit}`} value={String(value)} onChange={e => { const n = parseFloat(e.target.value.replace(',', '.')); if (Number.isFinite(n)) onChange(n); }} onBlur={() => set(value)} />
        <span className="unit" aria-hidden="true">{unit}</span>
        <button type="button" aria-label={`More ${label.toLowerCase()}`} onClick={() => set(value + step)}>+</button>
      </span>
    </div>
  );
}

const unitLabel = (l: LightFixture) => (KIND_INFO[l.kind].emits ? fixtureProfile(l).name.split(' · ')[0] : KIND_INFO[l.kind].label);
const centre = (w: PlanSegment): PlanPoint => ({ x: (w.a.x + w.b.x) / 2, z: (w.a.z + w.b.z) / 2 });

/** Save the lights round a person as a preset, kept relative to them or to the nearest window. */
export function SavePresetDialog({ person, lights, camera, exposure, plan, windowTransmission, onClose }: {
  person: PrevisCharacter; lights: LightFixture[]; camera?: PlanPoint; exposure: ExposureSettings; plan?: FloorPlan;
  windowTransmission: number; onClose(saved?: LightingPreset): void;
}) {
  const presets = usePresets();
  const win = plan && nearestWindow(person.position, plan);
  const [name, setName] = useState(`My setup ${presets.length + 1}`);
  const [anchor, setAnchor] = useState<PresetAnchor>('person');
  const [keepSides, setKeepSides] = useState(false);
  const near = (a: PresetAnchor) => new Set(lights.filter(l => planDist(l.position, a === 'window' && win ? centre(win) : person.position) <= 4).map(l => l.id));
  const [picked, setPicked] = useState(() => near('person'));
  const chosen = lights.filter(l => picked.has(l.id));
  const save = () => {
    if (!chosen.length) return;
    const p = anchor === 'window' && win && plan
      ? captureWindowPreset(name.trim() || 'My setup', chosen, win, plan)
      : { ...capturePersonPreset(name.trim() || 'My setup', chosen, person, camera, exposure, plan, windowTransmission), keepSides };
    addPreset(p);
    onClose(p);
  };
  return (
    <div className="scrim" onClick={() => onClose()}>
      <form className="dialog" role="dialog" aria-modal="true" aria-label="Save as my preset" onClick={e => e.stopPropagation()} onSubmit={e => { e.preventDefault(); save(); }}>
        <h2>Save as my preset</h2>
        <p>Keeps the units you tick, where they stand and how bright they are, so you can drop the same setup round anyone with one click.</p>
        <div className="stack">
          <input type="text" value={name} onChange={e => setName(e.target.value)} aria-label="Preset name" placeholder="Preset name" />
          <div className="segmented" role="group" aria-label="Keep the units relative to">
            <button type="button" className={anchor === 'person' ? 'on' : ''} aria-pressed={anchor === 'person'} onClick={() => { setAnchor('person'); setPicked(near('person')); }}>{person.name} and the camera</button>
            <button type="button" className={anchor === 'window' ? 'on' : ''} aria-pressed={anchor === 'window'} disabled={!win} onClick={() => { setAnchor('window'); setPicked(near('window')); }}>The nearest window</button>
          </div>
          <p className="note" style={{ margin: 0 }}>{anchor === 'person'
            ? 'Used again, the units go round the person you pick, turned to their camera, and are levelled for the stop.'
            : win ? 'Used again, the units go to the same place at a window, at the same dimmer levels. Good for a sun through the glass.' : 'This plan has no window.'}</p>
          <div role="group" aria-label="Units to keep">
            {lights.length ? lights.map(l => (
              <label key={l.id} className="toggle" style={{ display: 'flex', padding: '6px 0' }}>
                <input type="checkbox" checked={picked.has(l.id)} onChange={e => { const n = new Set(picked); if (e.target.checked) n.add(l.id); else n.delete(l.id); setPicked(n); }} />
                <span style={{ flex: 1 }}>{l.name}</span><span className="muted" style={{ fontSize: 12 }}>{unitLabel(l)}</span>
              </label>
            )) : <p className="note">Place some lights first.</p>}
          </div>
          {anchor === 'person' && (
            <label className="toggle"><input type="checkbox" checked={keepSides} onChange={e => setKeepSides(e.target.checked)} /> Always keep the key on this side (otherwise it goes where there is more room)</label>
          )}
        </div>
        <div className="actions" style={{ justifyContent: 'flex-end', marginTop: 16 }}>
          <button type="button" className="btn ghost" onClick={() => onClose()}>Cancel</button>
          <button type="submit" className="btn primary" disabled={!chosen.length}>Save {chosen.length} unit{chosen.length === 1 ? '' : 's'}</button>
        </div>
      </form>
    </div>
  );
}

function UnitEditor({ anchor, unit, onChange, onRemove }: { anchor: PresetAnchor; unit: PresetUnit; onChange(u: PresetUnit): void; onRemove(): void }) {
  const set = (patch: Partial<PresetUnit>) => onChange({ ...unit, ...patch });
  const emits = KIND_INFO[unit.light.kind].emits;
  return (
    <div style={{ borderTop: '1px solid var(--hair)', padding: '10px 0' }}>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        <input type="text" value={unit.light.name} aria-label="Unit name" onChange={e => set({ light: { ...unit.light, name: e.target.value } })} style={{ flex: 1 }} />
        <span className="muted" style={{ fontSize: 12 }}>{unitLabel(unit.light)}</span>
        <button type="button" className="btn small ghost danger" onClick={onRemove}>Remove</button>
      </div>
      {anchor === 'person' ? (
        <>
          <Step label="Angle from camera" value={unit.angle} step={5} min={-180} max={180} unit="°" onChange={v => set({ angle: v })} />
          <LengthStepper compact label="Distance" value={unit.distance} min={0.3} max={15} onChange={v => set({ distance: v })} />
          <LengthStepper compact label="Above eyes" value={unit.rise} min={-1.5} max={4} onChange={v => set({ rise: v })} />
          {emits && (unit.stopsUnderKey !== undefined
            ? <Step label="Stops under key (− is over)" value={unit.stopsUnderKey} step={0.5} min={-3} max={6} unit="st" onChange={v => set({ stopsUnderKey: v })} />
            : <p className="note">Keeps its dimmer ({Math.round(unit.light.dimmer * 100)} %), as it didn't light the face when saved.</p>)}
        </>
      ) : (
        <>
          <LengthStepper compact label="Along the window" value={unit.along} min={-10} max={10} onChange={v => set({ along: v })} />
          <LengthStepper compact label="Out from the glass" value={unit.out} min={-10} max={20} onChange={v => set({ out: v })} />
          <LengthStepper compact label="Height" value={unit.height} min={0} max={12} onChange={v => set({ height: v })} />
          {emits && <Step label="Dimmer" value={Math.round(unit.light.dimmer * 100)} step={5} min={0} max={100} unit="%" onChange={v => set({ light: { ...unit.light, dimmer: v / 100 } })} />}
        </>
      )}
    </div>
  );
}

/** Rename, tune, delete, copy and paste your presets. */
export function ManagePresetsDialog({ onClose }: { onClose(): void }) {
  const presets = usePresets();
  const [open, setOpen] = useState<string | undefined>(presets[0]?.id);
  const [message, setMessage] = useState<string>();
  const copy = async () => {
    const text = encodePresets(presets);
    try { await navigator.clipboard.writeText(text); setMessage(`Copied ${presets.length} preset${presets.length === 1 ? '' : 's'}. Paste them on the phone or another computer.`); }
    catch { window.prompt('Copy your presets:', text); }
  };
  const paste = async () => {
    let text: string | null = null;
    try { text = await navigator.clipboard.readText(); } catch { text = window.prompt('Paste presets copied from FrameScan:'); }
    const got = text ? decodePresets(text) : undefined;
    if (!got?.length) { setMessage("That isn't a FrameScan preset."); return; }
    const ids = new Set(presets.map(p => p.id));
    savePresets([...presets.filter(p => !got.some(g => g.id === p.id)), ...got]);
    setMessage(`Added ${got.filter(g => !ids.has(g.id)).length}, updated ${got.filter(g => ids.has(g.id)).length}.`);
  };
  return (
    <div className="scrim" onClick={onClose}>
      <div className="dialog" role="dialog" aria-modal="true" aria-label="My presets" onClick={e => e.stopPropagation()} style={{ width: 'min(600px, 100%)' }}>
        <h2>My presets</h2>
        <p>Tune where each unit goes and how bright it is. Levels are set again for the stop each time you use a preset.</p>
        {presets.length ? presets.map(p => (
          <section key={p.id} className="panel" style={{ padding: '12px 0' }}>
            <button type="button" className="row" style={{ width: '100%', margin: 0 }} aria-expanded={open === p.id} onClick={() => setOpen(open === p.id ? undefined : p.id)}>
              <span className="t">{p.name}</span><span className="s">{ANCHOR_LABEL[p.anchor]} · {presetSummary(p)}</span>
            </button>
            {open === p.id && (
              <div style={{ padding: '8px 4px 0' }}>
                <input type="text" value={p.name} aria-label="Preset name" onChange={e => updatePreset({ ...p, name: e.target.value })} />
                {p.anchor === 'person' && (
                  <label className="toggle" style={{ margin: '10px 0' }}><input type="checkbox" checked={p.keepSides} onChange={e => updatePreset({ ...p, keepSides: e.target.checked })} /> Always keep the key on the saved side</label>
                )}
                {p.units.map((u, i) => (
                  <UnitEditor key={i} anchor={p.anchor} unit={u}
                    onChange={nu => updatePreset({ ...p, units: p.units.map((x, j) => (j === i ? nu : x)) })}
                    onRemove={() => updatePreset({ ...p, units: p.units.filter((_, j) => j !== i) })} />
                ))}
                <div className="actions" style={{ marginTop: 8 }}>
                  <button type="button" className="btn small danger" onClick={() => removePreset(p.id)}>Delete preset</button>
                </div>
              </div>
            )}
          </section>
        )) : <p className="note">No presets yet. Light a person the way you like, then use “Save as my preset” on their panel.</p>}
        {message && <p className="note" role="status">{message}</p>}
        <div className="actions" style={{ justifyContent: 'space-between', marginTop: 16 }}>
          <span className="actions">
            <button type="button" className="btn small" disabled={!presets.length} onClick={copy}>Copy all</button>
            <button type="button" className="btn small" onClick={paste}>Paste</button>
          </span>
          <button type="button" className="btn primary" onClick={onClose}>Done</button>
        </div>
      </div>
    </div>
  );
}
