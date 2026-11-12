// Studio build, daylight and curtain controls for the inspector. Same labels and rules as the
// phone (model/stage.ts ↔ Stage.swift).
import type { Location } from '../model/types';
import {
  BACKDROPS, CURTAIN_LABEL, FLOORS, LED_DEFAULT_NITS, LED_NITS_RANGE, SKY, backdropInfo, backdropPlacement, clockProblem, daylightLevels,
  floorInfo, sunPlacement, type CurtainKind, type DaylightSetup, type SkyKind, type StudioSetup,
} from '../model/stage';
import { Badge, Panel, Slider, type InspectorProps } from './Inspector';
import { deg, lux as fmtLux, metres, pct } from './format';

const segLen = (s: { a: { x: number; z: number }; b: { x: number; z: number } }) => Math.hypot(s.b.x - s.a.x, s.b.z - s.a.z);

// MARK: Time in the location's time zone

/** Minutes the zone is ahead of UTC at `ms`. */
function zoneOffset(ms: number, zone?: string): number {
  if (!zone) return -new Date(ms).getTimezoneOffset();
  try {
    const parts = new Intl.DateTimeFormat('en-GB', { timeZone: zone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' }).formatToParts(new Date(ms));
    const n = (t: string) => Number(parts.find(p => p.type === t)?.value);
    return Math.round((Date.UTC(n('year'), n('month') - 1, n('day'), n('hour'), n('minute'), n('second')) - ms) / 60000);
  } catch { return -new Date(ms).getTimezoneOffset(); }
}
/** "2026-06-21T15:30" in the zone, for a datetime-local field. */
function toLocalInput(secs: number, zone?: string): string {
  const ms = secs * 1000 + zoneOffset(secs * 1000, zone) * 60000;
  return new Date(ms).toISOString().slice(0, 16);
}
function fromLocalInput(value: string, zone?: string): number | undefined {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(value);
  if (!m) return undefined;
  const wall = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
  const first = wall - zoneOffset(wall, zone) * 60000;
  return (wall - zoneOffset(first, zone) * 60000) / 1000;
}

// MARK: Daylight

export function DaylightPanel(p: InspectorProps) {
  const d: DaylightSetup = p.location.daylight ?? {};
  const set = (patch: Partial<DaylightSetup>, undo = true) => p.edit(loc => ({ ...loc, daylight: { ...(loc.daylight ?? {}), ...patch } }), undo);
  const hasWindows = (p.plan?.windows.length ?? 0) > 0 || (p.plan?.doors.some(x => x.isOpen) ?? false);
  const problem = clockProblem(p.location, p.scan);
  const sun = sunPlacement(p.location, p.scan);
  const levels = daylightLevels(d.sky ?? 'clear', sun.elevation);
  const zone = p.location.timeZoneIdentifier;
  const time = d.time ?? Math.round(Date.now() / 1000 / 900) * 900;
  return (
    <Panel title="Daylight" collapsible open={!!d.isOn}>
      <label className="toggle" style={{ margin: '4px 0 8px' }}>
        <input type="checkbox" checked={!!d.isOn} onChange={e => set({ isOn: e.target.checked })} /> Sun and sky outside the windows
      </label>
      {d.isOn && (
        <>
          <div className="seg" role="group" aria-label="Sky" style={{ marginBottom: 8, flexWrap: 'wrap' }}>
            {(Object.keys(SKY) as SkyKind[]).map(k => (
              <button key={k} className={'tool' + ((d.sky ?? 'clear') === k ? ' on' : '')} aria-pressed={(d.sky ?? 'clear') === k} onClick={() => set({ sky: k })}>{SKY[k].label}</button>
            ))}
          </div>
          <div className="seg" role="group" aria-label="Where the sun is" style={{ marginBottom: 4 }}>
            <button className={'tool' + (!d.fromClock ? ' on' : '')} aria-pressed={!d.fromClock} onClick={() => set({ fromClock: false })}>Place by hand</button>
            <button className={'tool' + (d.fromClock ? ' on' : '')} aria-pressed={!!d.fromClock} onClick={() => set({ fromClock: true, time })}>From date and time</button>
          </div>
          {d.fromClock ? (
            <>
              <div className="field"><span>Date and time</span>
                <input type="datetime-local" value={toLocalInput(time, zone)} onChange={e => { const t = fromLocalInput(e.target.value, zone); if (t !== undefined) set({ time: t }); }} />
                <span />
              </div>
              <Slider label="Time of day" value={((((time + zoneOffset(time * 1000, zone) * 60) % 86400) + 86400) % 86400) / 60}
                min={0} max={1435} step={5} format={v => `${String(Math.floor(v / 60)).padStart(2, '0')}:${String(Math.round(v % 60)).padStart(2, '0')}`}
                onChange={v => { const local = time + zoneOffset(time * 1000, zone) * 60; const day = Math.floor(local / 86400) * 86400; set({ time: day + v * 60 - zoneOffset(time * 1000, zone) * 60 }, false); }} />
              {problem
                ? <p className="note">{problem}</p>
                : <p className="note">Times are {zone ? `in ${zone}` : 'in this computer\'s time zone'}. Sun at {Math.round(sun.azimuth ?? 0)}° from north, {Math.round(sun.elevation)}° up.</p>}
            </>
          ) : (
            <>
              <Slider label="Sun from" value={sun.bearing} min={0} max={359} step={1} format={deg} onChange={v => set({ sunBearing: v }, false)} />
              <Slider label="Sun height" value={sun.elevation} min={0} max={90} step={1} format={deg} onChange={v => set({ sunElevation: v }, false)} />
              <p className="note">Direction on the plan, clockwise from its top. Height above the horizon.</p>
            </>
          )}
          <div className="readout" style={{ marginTop: 8 }}>
            <div><div className="label">Sun, square-on</div><div className="v">{levels.directNormal > 0 ? `≈ ${fmtLux(levels.directNormal)}` : sun.elevation > 0 ? 'Behind cloud' : 'Below horizon'}</div></div>
            <div><div className="label">Sky, outdoors</div><div className="v">≈ {fmtLux(levels.skyHorizontal)}</div></div>
          </div>
          <p className="note"><Badge /> IES daylight model. Assumes nothing outside blocks the sky or the sun (buildings, trees), and a sky of even brightness.
            {hasWindows ? ' Sun comes in as a beam through bare glass; a sheer turns it into a glow; blackout stops it.' : ' This room has no windows or open doors yet, so no daylight gets in.'}</p>
        </>
      )}
    </Panel>
  );
}

// MARK: Curtains

export function CurtainField({ value, onChange }: { value?: CurtainKind; onChange(c?: CurtainKind): void }) {
  return (
    <>
      <div className="field"><span>Curtains</span>
        <select value={value ?? ''} onChange={e => onChange((e.target.value || undefined) as CurtainKind | undefined)}>
          <option value="">None (bare glass)</option>
          {(Object.keys(CURTAIN_LABEL) as CurtainKind[]).map(k => <option key={k} value={k}>{CURTAIN_LABEL[k]}</option>)}
        </select><span />
      </div>
      {value && <p className="note">{value === 'sheer' ? 'Drawn sheers pass about half the light and spread it: sun on them glows instead of throwing a beam.' : 'Drawn blackout passes no light either way. The window side catches the light; the room side stays dark.'} <Badge /></p>}
    </>
  );
}

// MARK: Studio

export function StudioPanel(p: InspectorProps) {
  const st: StudioSetup = p.location.studio ?? {};
  const set = (patch: Partial<StudioSetup>, undo = true) => p.edit((loc: Location) => {
    const next: StudioSetup = { ...(loc.studio ?? {}), ...patch };
    for (const k of Object.keys(next) as (keyof StudioSetup)[]) if (next[k] === undefined) delete next[k];
    return { ...loc, studio: next };
  }, undo);
  const info = backdropInfo(st.backdrop);
  const placed = backdropPlacement(p.location, p.plan);
  const walls = (p.plan?.walls ?? []).filter(w => segLen(w) > 0.5);
  const floor = floorInfo(st.floor);
  const wallLen = placed ? segLen(placed.wall) : 0;
  const wallTop = placed ? placed.wall.bottom + placed.wall.height : 3;
  return (
    <Panel title="Studio set" collapsible open={!!(st.backdrop || st.floor)}>
      {!p.plan ? <p className="note">Draw a room or scan one first; the backdrop stands against one of its walls.</p> : (
        <>
          <div className="field"><span>Backdrop</span>
            <select value={st.backdrop ?? ''} onChange={e => set({ backdrop: e.target.value || undefined, width: undefined, height: undefined, offset: undefined })}>
              <option value="">None</option>
              <optgroup label="Cyc and screens">{BACKDROPS.filter(b => b.kind === 'cyc').map(b => <option key={b.id} value={b.id}>{b.label}</option>)}</optgroup>
              <optgroup label="LED">{BACKDROPS.filter(b => b.kind === 'led').map(b => <option key={b.id} value={b.id}>{b.label}</option>)}</optgroup>
              <optgroup label="Photography paper">{BACKDROPS.filter(b => b.kind === 'paper').map(b => <option key={b.id} value={b.id}>{b.label}</option>)}</optgroup>
            </select><span />
          </div>
          {info && placed && (
            <>
              <div className="field"><span>On the wall</span>
                <select value={st.wallID ?? ''} onChange={e => set({ wallID: e.target.value || undefined, offset: undefined })}>
                  <option value="">The one the camera faces</option>
                  {walls.map((w, i) => <option key={w.id} value={w.id}>Wall {i + 1} ({metres(segLen(w))})</option>)}
                </select><span />
              </div>
              {info.pickColour && (
                <div className="field"><span>Colour</span><input type="color" value={st.colour ?? info.colour} onChange={e => set({ colour: e.target.value }, false)} aria-label="Backdrop colour" /><span /></div>
              )}
              <Slider label="Width" value={placed.width} min={0.5} max={Math.max(0.5, wallLen)} step={0.05} format={metres} onChange={v => set({ width: v }, false)} />
              <Slider label="Height" value={placed.height} min={0.5} max={Math.max(0.5, wallTop)} step={0.05} format={metres} onChange={v => set({ height: v }, false)} />
              {placed.width < wallLen - 0.05 && (
                <Slider label="Along the wall" value={st.offset ?? 0} min={-(wallLen - placed.width) / 2} max={(wallLen - placed.width) / 2} step={0.05}
                  format={v => (Math.abs(v) < 0.025 ? 'Centred' : `${metres(Math.abs(v))} ${v < 0 ? 'left' : 'right'}`)} onChange={v => set({ offset: v }, false)} />
              )}
              {info.kind === 'led' && (
                <>
                  <Slider label="Brightness" value={st.nits ?? LED_DEFAULT_NITS} min={LED_NITS_RANGE.min} max={LED_NITS_RANGE.max} step={10} format={v => `${Math.round(v)} nits`} onChange={v => set({ nits: v }, false)} />
                  <Slider label="White point" value={st.kelvin ?? 6500} min={2700} max={10000} step={100} format={v => `${Math.round(v)} K`} onChange={v => set({ kelvin: v }, false)} />
                  <p className="note">Brightness is the average of what the wall shows, not its maximum. It lights the set and counts in the readings. <Badge /></p>
                </>
              )}
              <p className="note">{info.note} {info.kind !== 'led' && <>Reflects about {pct(info.reflectance)} of the light on it; the readings don't add that bounce.</>}</p>
            </>
          )}
          <div className="field"><span>Floor</span>
            <select value={st.floor ?? ''} onChange={e => set({ floor: e.target.value || undefined })}>
              <option value="">As scanned or drawn</option>
              {FLOORS.map(f => <option key={f.id} value={f.id}>{f.label}</option>)}
            </select><span />
          </div>
          {floor?.pickColour && (
            <div className="field"><span>Floor colour</span><input type="color" value={st.floorColour ?? floor.colour} onChange={e => set({ floorColour: e.target.value }, false)} aria-label="Floor colour" /><span /></div>
          )}
          {floor && <p className="note">Reflects about {pct(floor.reflectance)}. Shown in 3D; not added to the readings.</p>}
        </>
      )}
    </Panel>
  );
}
