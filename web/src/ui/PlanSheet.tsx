// The hand-off sheet: the plan as framed on screen, every unit with its settings, the readings,
// the kit list and the estimated power, on one printable page. Print saves it as a PDF too.
import { useEffect, useMemo, useState } from 'react';
import type { CameraRig, ExposureSettings, FloorPlan, LightFixture, Location, Project } from '../model/types';
import type { MeterPoint } from '../model/calculator';
import { KIND_INFO, filters, fixtureModifier, fixtureProfile, photometrics } from '../model/photometrics';
import { colourSummary } from '../model/colour';
import { cameraExposure, DEFAULT_WHITE_BALANCE, exposureTime, speedLabel, stopLabel, stopsDelta, stopsForLux, trim } from '../model/exposure';
import { gripLabel, isGrip } from '../model/grip';
import { lightSupport, lightSupportInfo } from '../model/rigging';
import { BATTERY_SIZES, SUPPLIES, amps, circuitPlan, emptyRates, kitCost, kitList, kitText, money, parseRate, parseRates, ratesJSON, runTimeLabel, supplyByID, type KitLine, type Rates } from '../model/kit';
import { metres, pct, reading as fmtReading, watts } from './format';
import { Icon } from './icons';
import { activeLook, looksOf } from '../model/looks';
import { horizontalFOV, sensorFor } from '../model/camera';
import { focalNumber } from '../model/lenses';
import { planDist } from '../model/calculator';
import { inFrameSentence, unitsInFrame } from '../model/frameCheck';
import { useModal } from './useModal';
import { shotFrames } from '../sync/shotFrames';

/** The on-screen plan as a standalone SVG, with the day-theme colours written in so it prints light. */
export function planSnapshot(svg: SVGSVGElement): { url: string; w: number; h: number } {
  const root = document.documentElement;
  const theme = root.dataset.theme;
  root.dataset.theme = 'day';
  const css = getComputedStyle(root);
  const resolve = (v: string) => v.replace(/var\((--[\w-]+)(?:,\s*([^)]+))?\)/g, (_, name: string, fb?: string) => css.getPropertyValue(name).trim() || fb || 'currentColor');
  const clone = svg.cloneNode(true) as SVGSVGElement;
  for (const el of [clone, ...clone.querySelectorAll('*')]) {
    for (const a of [...el.attributes]) if (a.value.includes('var(')) el.setAttribute(a.name, resolve(a.value));
  }
  root.dataset.theme = theme;
  const w = Number(svg.getAttribute('width')) || svg.clientWidth, h = Number(svg.getAttribute('height')) || svg.clientHeight;
  clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
  clone.setAttribute('viewBox', `0 0 ${w} ${h}`);
  const bg = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
  bg.setAttribute('width', String(w)); bg.setAttribute('height', String(h)); bg.setAttribute('fill', '#ffffff');
  clone.insertBefore(bg, clone.firstChild);
  return { url: 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(new XMLSerializer().serializeToString(clone)), w, h };
}

function unitRow(l: LightFixture) {
  const support = lightSupportInfo(lightSupport(l)).label;
  if (isGrip(l.kind)) return { name: l.name, unit: gripLabel(l) || KIND_INFO[l.kind].label, shaping: '', output: '', colour: '', height: metres(l.height), stand: support };
  const p = fixtureProfile(l), mod = fixtureModifier(l), pm = photometrics(l);
  const gels = (l.filterIDs ?? []).map(id => filters.find(f => f.id === id)?.name).filter(Boolean);
  return {
    name: l.name,
    unit: p.name,
    shaping: [mod && mod.id !== p.defaultModifierID ? mod.name : '', ...gels].filter(Boolean).join(', '),
    output: l.isOn ? pct(l.dimmer) : 'off',
    colour: p.color.rgb && l.colorMode === 'rgb' ? `Colour, hue ${Math.round(l.hue ?? 0)}°` : `${Math.round(pm.kelvin)} K`,
    height: metres(l.height),
    stand: support,
  };
}

/** Run time at full output on one pack, for units small enough to run on one. Estimated. */
function packTime(l: LightFixture, wh: number): string {
  if (isGrip(l.kind) || !KIND_INFO[l.kind].emits) return '';
  return runTimeLabel(fixtureProfile(l).ratedPower, wh);
}

const Lines = ({ title, lines }: { title: string; lines: KitLine[] }) => lines.length ? (
  <div className="sheet-kit"><h4>{title}</h4><ul>{lines.map(l => <li key={l.item}><span className="mono">{l.qty} ×</span> {l.item}</li>)}</ul></div>
) : null;

const SUPPLY_KEY = 'framescan.power.supply', PACK_KEY = 'framescan.power.pack', RATES_KEY = 'framescan.rates';
function stored(key: string): string | null { try { return localStorage.getItem(key); } catch { return null; } }
function store(key: string, v: string) { try { localStorage.setItem(key, v); } catch { /* private window: kept for this visit only */ } }

/** Day rates the user types in for each kit line. FrameScan has no prices of its own; lines left blank
 *  are listed as having no rate rather than guessed. */
function RatesEditor({ lines, rates, onChange }: { lines: KitLine[]; rates: Rates; onChange(update: (r: Rates) => Rates): void }) {
  const [note, setNote] = useState('');
  // Bumped on paste so the typed-in fields show the pasted rates.
  const [ver, setVer] = useState(0);
  const set = (item: string, text: string) => onChange(cur => {
    const items = { ...cur.items };
    const v = parseRate(text);
    if (v === undefined) delete items[item]; else items[item] = v;
    return { ...cur, items };
  });
  const copy = () => { void navigator.clipboard?.writeText(ratesJSON(rates)).then(() => setNote('Rates copied')).catch(() => setNote("Couldn't copy")); };
  const paste = () => {
    void navigator.clipboard?.readText().then(t => {
      const r = parseRates(t);
      if (r) { onChange(cur => ({ currency: r.currency, items: { ...cur.items, ...r.items } })); setVer(v => v + 1); setNote('Rates pasted'); } else setNote('Nothing to paste: copy rates from FrameScan first');
    }).catch(() => setNote("Couldn't read the clipboard"));
  };
  return (
    <details className="sheet-rates-edit">
      <summary>Type your day rates</summary>
      <p className="faint">Type what you pay a day for each item, from your rental house or your own kit. They stay on this computer and are only used on this sheet and the copied kit list.</p>
      <label className="sheet-rate-row"><span>Currency</span><input value={rates.currency} maxLength={4} onChange={ev => { const currency = ev.target.value; onChange(cur => ({ ...cur, currency })); }} aria-label="Currency symbol" /></label>
      {lines.map(l => (
        <label key={`${l.item}-${ver}`} className="sheet-rate-row"><span>{l.item}</span>
          <input inputMode="decimal" defaultValue={rates.items[l.item] ?? ''} placeholder="Day rate" onChange={ev => set(l.item, ev.target.value)} aria-label={`Day rate for ${l.item}`} /></label>
      ))}
      <div className="sheet-rate-actions">
        <button className="btn small" onClick={copy}>Copy rates</button>
        <button className="btn small" onClick={paste}>Paste rates</button>
        <span className="faint" role="status">{note}</span>
      </div>
    </details>
  );
}

type Picture = { url: string; w: number; h: number };

/** Whether a shot's camera has moved, changed lens or changed its own settings since a frame of it was saved. */
function rigChanged(a: CameraRig, b: CameraRig): boolean {
  const near = (x: number, y: number, tol: number) => Math.abs(x - y) <= tol;
  return !(near(a.position.x, b.position.x, 0.02) && near(a.position.z, b.position.z, 0.02) && near(a.height, b.height, 0.02)
    && near(a.pan, b.pan, 0.5) && near(a.tilt, b.tilt, 0.5) && near(a.focalLength, b.focalLength, 0.5)
    && a.sensorID === b.sensorID && a.aspect === b.aspect
    && (a.sensorID !== 'custom' || JSON.stringify(a.customSensor) === JSON.stringify(b.customSensor))
    && JSON.stringify(a.exposure ?? null) === JSON.stringify(b.exposure ?? null));
}
const PICTURE_KEY = 'framescan.sheet.picture';
/** "T2.8 · ISO 800 · 24 fps · 180° (1/48) · 5600 K": the camera settings in one line. */
const cameraLine = (e: ExposureSettings) => [stopLabel(e.tStop), `ISO ${e.iso}`, `${trim(e.frameRate)} fps`,
  e.shutterSeconds !== undefined ? speedLabel(e.shutterSeconds) : `${trim(e.shutterAngle)}° (${speedLabel(exposureTime(e))})`,
  e.ndStops ? `ND ${(e.ndStops * 0.3).toFixed(1)}` : '', e.whiteBalance ? `${Math.round(e.whiteBalance)} K` : ''].filter(Boolean).join(' · ');

export function PlanSheet({ project, location, lights, meters, readings, exposure: e, plan: framed, diagram, floorPlan, scanID, settingsFor, onClose }: {
  project: Project; location: Location; lights: LightFixture[]; meters: MeterPoint[]; readings: Map<string, number>;
  exposure: ExposureSettings; plan?: Picture; diagram?: Picture; floorPlan?: FloorPlan; scanID?: string;
  /** Whose settings `exposure` is, when a camera's own (the plan picture's readings use the same). */
  settingsFor?: string; onClose(): void;
}) {
  const kit = useMemo(() => kitList(lights), [lights]);
  const scan = scanID ?? location.primaryScanID ?? location.scans[location.scans.length - 1]?.id;
  const look = activeLook(location, scan);
  const looks = looksOf(location, scan);
  const inScan = (id?: string) => !id || !scan || id.toUpperCase() === scan.toUpperCase();
  const shots = location.shots.filter(x => inScan(x.scanID)).sort((a, b) => a.number - b.number);
  const title = `${project.name} — ${location.name}${look ? ` · ${look.name}` : ''}`;
  const [copied, setCopied] = useState(false);
  const camera = cameraLine(e);
  const colour = useMemo(() => new Map(colourSummary(lights, e.whiteBalance ?? DEFAULT_WHITE_BALANCE).rows.map(r => [r.id, r])), [lights, e.whiteBalance]);
  // Which plan picture the sheet shows: the plan as framed on screen, or the clean overhead diagram.
  const [picture, setPicture] = useState<'framed' | 'diagram'>(() => (stored(PICTURE_KEY) === 'diagram' && diagram ? 'diagram' : 'framed'));
  const plan = picture === 'diagram' && diagram ? diagram : framed ?? diagram;
  const choosePicture = (v: 'framed' | 'diagram') => { setPicture(v); store(PICTURE_KEY, v); };
  const savePNG = () => {
    if (!plan) return;
    const img = new Image();
    img.onload = () => {
      const c = document.createElement('canvas'); c.width = plan.w * 2; c.height = plan.h * 2;
      const g = c.getContext('2d')!; g.scale(2, 2); g.drawImage(img, 0, 0);
      const a = document.createElement('a'); a.href = c.toDataURL('image/png'); a.download = `${title.replace(/[^\w\- ]+/g, '')} ${picture === 'diagram' ? 'diagram' : 'plan'}.png`; a.click();
    };
    img.src = plan.url;
  };
  const [supplyID, setSupplyID] = useState(() => supplyByID(stored(SUPPLY_KEY) ?? undefined).id);
  const [pack, setPack] = useState(() => { const v = Number(stored(PACK_KEY)); return BATTERY_SIZES.includes(v) ? v : BATTERY_SIZES[0]; });
  const [rates, setRatesState] = useState<Rates>(() => parseRates(stored(RATES_KEY)) ?? emptyRates());
  // Updates go through the latest rates, so a paste that lands after an edit keeps the edit.
  const setRates = (update: (r: Rates) => Rates) => setRatesState(cur => { const next = update(cur); store(RATES_KEY, ratesJSON(next)); return next; });
  const circuits = useMemo(() => circuitPlan(lights, supplyByID(supplyID)), [lights, supplyID]);
  const cost = kitCost(kit, rates);
  const kitLines = [...kit.units, ...kit.modifiers, ...kit.gels, ...kit.grip, ...kit.stands];
  const copy = () => { void navigator.clipboard?.writeText(kitText(kit, title, lights, rates)).then(() => setCopied(true)).catch(() => setCopied(false)); };
  const dialogRef = useModal<HTMLElement>(onClose);
  // Previs frames saved from the 3D look-through. They live in this browser only.
  const shotKey = shots.map(x => x.id).join(',');
  const [frames, setFrames] = useState<Map<string, { url: string; lens: string; rig?: CameraRig; createdAt: string }>>(new Map());
  // Print waits for the first read, so a quick print doesn't leave the frame pages out.
  const [framesRead, setFramesRead] = useState(false);
  useEffect(() => {
    let urls: string[] = [], alive = true;
    const load = () => shotFrames.forShots(shotKey ? shotKey.split(',') : []).then(found => {
      if (!alive) return;
      urls.forEach(u => URL.revokeObjectURL(u));
      const next = new Map<string, { url: string; lens: string; rig?: CameraRig; createdAt: string }>();
      for (const [id, f] of found) next.set(id, { url: URL.createObjectURL(f.blob), lens: f.lens, rig: f.rig, createdAt: f.createdAt });
      urls = [...next.values()].map(f => f.url);
      setFrames(next);
    }).catch(() => undefined).finally(() => { if (alive) setFramesRead(true); });
    void load();
    const off = shotFrames.subscribe(() => { void load(); });
    return () => { alive = false; off(); urls.forEach(u => URL.revokeObjectURL(u)); };
  }, [shotKey]);
  const shotRows = shots.map(x => {
    // A shot lit with another saved look is checked against that look's units; the active look
    // (or none) uses the live units so unsaved changes show.
    const shotLook = x.lookID ? looks.find(l => l.id.toUpperCase() === x.lookID!.toUpperCase()) : undefined;
    const units = shotLook && shotLook !== look ? shotLook.lights.filter(l => inScan(l.scanID)) : lights;
    return {
      shot: x,
      name: `Shot ${String(x.number).padStart(2, '0')}${x.title ? ` · ${x.title}` : ''}`,
      lens: `${focalNumber(x.rig.focalLength)}mm · ${Math.round(horizontalFOV(x.rig))}° · ${sensorFor(x.rig).name}`,
      height: `${metres(x.rig.height)}${x.rig.tilt ? ` · tilt ${x.rig.tilt > 0 ? '+' : ''}${Math.round(x.rig.tilt)}°` : ''}`,
      toSubject: x.subject ? metres(planDist(x.rig.position, x.subject)) : '',
      seen: inFrameSentence(unitsInFrame(x.rig, units, floorPlan)),
      lit: shotLook?.name ?? (look && !x.lookID ? look.name : ''),
      settings: x.rig.exposure ? cameraLine(cameraExposure(location, x.rig)) : '',
    };
  });
  return (
    <div className="scrim sheet-scrim" onClick={onClose}>
      <article className="sheet" role="dialog" aria-modal="true" ref={dialogRef} aria-label="Lighting plan sheet" onClick={ev => ev.stopPropagation()}>
        <div className="sheet-actions">
          <button className="btn primary small" onClick={() => window.print()} disabled={!framesRead} title={framesRead ? undefined : 'Loading the shot frames…'}><Icon name="download" /> Print or save PDF</button>
          {framed && diagram && (
            <select className="sheet-inline-select" value={picture} onChange={ev => choosePicture(ev.target.value as 'framed' | 'diagram')} aria-label="Plan picture">
              <option value="framed">Plan as framed</option>
              <option value="diagram">Clean diagram</option>
            </select>
          )}
          <button className="btn small" onClick={savePNG} disabled={!plan}>{picture === 'diagram' && diagram ? 'Diagram' : 'Plan'} as PNG</button>
          <button className="btn small" onClick={copy}>{copied ? 'Copied' : 'Copy kit list'}</button>
          <span className="spacer" />
          <button className="btn ghost small" onClick={onClose}>Close</button>
        </div>
        <header className="sheet-head">
          <h2>{title}</h2>
          <p className="mono">{settingsFor ? `${settingsFor}: ` : shots.some(x => x.rig.exposure) ? 'Location settings: ' : ''}{camera}</p>
          {settingsFor && shots.some(x => !x.rig.exposure) && <p className="mono">Location settings (shots without their own): {cameraLine(cameraExposure(location))}</p>}
          <p className="faint">{new Date().toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' })}{project.client ? ` · ${project.client}` : ''}</p>
        </header>
        {plan && <img className="sheet-plan" src={plan.url} alt={picture === 'diagram' ? 'Overhead lighting diagram' : 'Lighting plan'} />}
        {shots.length > 0 && <>
          <h3>Shots</h3>
          <table className="sheet-table">
            <thead><tr><th>Shot</th><th>Lens</th><th>Lens height</th><th>To subject</th><th>Lit with</th><th>In frame</th><th>Notes</th></tr></thead>
            <tbody>{shotRows.map(r => <tr key={r.shot.id}>
              <td>{r.name}</td><td className="mono">{r.lens}</td><td className="mono">{r.height}</td><td className="mono">{r.toSubject}</td>
              <td>{r.lit}</td><td>{r.seen || 'Clear'}</td><td>{[r.settings, r.shot.notes].filter(Boolean).join(' · ')}</td>
            </tr>)}</tbody>
          </table>
        </>}
        {shots.length > 0 && !framesRead && <p className="faint sheet-print-hide">Loading the shot frames…</p>}
        {shots.length > 0 && framesRead && !shotRows.some(r => frames.has(r.shot.id)) && <p className="faint sheet-print-hide">Look through a shot in 3D and press Save frame to add its picture here, one page per shot.</p>}
        <h3>Units</h3>
        {colour.size > 0 && <p className="faint">Colour shows how each unit reads on a camera balanced to {Math.round(e.whiteBalance ?? DEFAULT_WHITE_BALANCE)} K{e.whiteBalance ? '' : ' (no white balance set, so daylight is assumed)'}. Worked out from the settings, not measured.</p>}
        <table className="sheet-table">
          <thead><tr><th>Name</th><th>Unit</th><th>Modifier and gels</th><th>Output</th><th>Colour</th><th>Height</th><th>Stand</th><th>On a {pack} Wh pack</th></tr></thead>
          <tbody>{lights.map(l => { const r = unitRow(l); return <tr key={l.id}><td>{r.name}</td><td>{r.unit}</td><td>{r.shaping}</td><td className="mono">{r.output}</td><td className="mono">{r.colour}{colour.get(l.id)?.shift && <span className="sheet-sub">{colour.get(l.id)!.shift!.label}</span>}</td><td className="mono">{r.height}</td><td>{r.stand}</td><td className="mono">{packTime(l, pack)}</td></tr>; })}</tbody>
        </table>
        {meters.length > 0 && <>
          <h3>Readings at {stopLabel(e.tStop)}</h3>
          <table className="sheet-table narrow">
            <tbody>{meters.map(m => { const v = readings.get(m.key) ?? 0; return <tr key={m.key}><td>{m.name}</td><td className="mono">≈ {fmtReading(v, e)}</td><td className="mono">{stopsDelta(stopsForLux(e, v))}</td></tr>; })}</tbody>
          </table>
        </>}
        <h3>Kit</h3>
        <div className="sheet-kits">
          <Lines title="Units" lines={kit.units} />
          <Lines title="Modifiers" lines={kit.modifiers} />
          <Lines title="Gels and diffusion" lines={kit.gels} />
          <Lines title="Grip" lines={kit.grip} />
          <Lines title="Stands" lines={kit.stands} />
        </div>
        {kit.drawRated > 0 && (
          <p className="sheet-power"><strong>Power</strong> · rated, all units {watts(kit.drawRated)} ({amps(kit.drawRated, 230).toFixed(1)} A at 230 V, {amps(kit.drawRated, 120).toFixed(1)} A at 120 V) · as set, units on ≈ {watts(kit.drawNow)}</p>
        )}
        {kit.drawRated > 0 && (
          <p className="sheet-power">
            <strong>Circuits</strong> · on{' '}
            <select className="sheet-inline-select" value={supplyID} onChange={ev => { setSupplyID(ev.target.value); store(SUPPLY_KEY, ev.target.value); }} aria-label="Wall supply">
              {SUPPLIES.map(x => <option key={x.id} value={x.id}>{x.label}s</option>)}
            </select>{' '}
            ≈ {circuits.circuits} separate circuit{circuits.circuits === 1 ? '' : 's'}, every unit at full, each circuit loaded to 80 %
            {circuits.tooBig.length > 0 && <> · too big for one: {circuits.tooBig.join(', ')} (needs a bigger supply or a generator)</>}
            <span className="sheet-print-hide"> · packs{' '}
              <select className="sheet-inline-select" value={pack} onChange={ev => { const v = Number(ev.target.value); setPack(v); store(PACK_KEY, String(v)); }} aria-label="Battery pack size">
                {BATTERY_SIZES.map(w => <option key={w} value={w}>{w} Wh</option>)}
              </select>
            </span>
          </p>
        )}
        {cost.lines.length > 0 && <>
          <h3>Your day rates</h3>
          <table className="sheet-table narrow">
            <tbody>
              {cost.lines.map(l => <tr key={l.item}><td>{l.qty} × {l.item}</td><td className="mono">{money(l.rate, rates.currency)}</td><td className="mono">{money(l.total, rates.currency)}</td></tr>)}
              <tr><td><strong>Per day</strong></td><td /><td className="mono"><strong>{money(cost.perDay, rates.currency)}</strong></td></tr>
            </tbody>
          </table>
          {cost.missing.length > 0 && <p className="faint">No rate yet for {cost.missing.join(', ')}.</p>}
        </>}
        {kitLines.length > 0 && <RatesEditor lines={kitLines} rates={rates} onChange={setRates} />}
        <p className="note">≈ Readings, power, circuits and pack times are estimates from the plan (direct light, one bounce off boards and one off the room; packs at full output with 85 % of the rating usable). The venue's wiring decides what is really on each circuit. Check on the day. Day rates are yours, as typed.</p>
        {shotRows.some(r => frames.has(r.shot.id)) && <section className="sheet-frames">
          {shotRows.filter(r => frames.has(r.shot.id)).map(r => { const f = frames.get(r.shot.id)!; return (
            <figure key={r.shot.id} className="sheet-frame">
              <h3>{r.name}</h3>
              <img src={f.url} alt={`Previs render of ${r.name}`} />
              <figcaption>
                <span className="mono">Previs render, not a photograph · {f.lens} · saved {new Date(f.createdAt).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}</span>
                {f.rig && rigChanged(f.rig, r.shot.rig) && <span><strong>The shot has changed since this frame was saved.</strong> The details below are the shot as it is now; save the frame again to match.</span>}
                <span className="mono">{r.lens} · lens at {r.height}{r.toSubject ? ` · ${r.toSubject} to subject` : ''}</span>
                {r.lit && <span>Lit with {r.lit}</span>}
                <span>{r.seen || 'No units or grip in frame (estimate).'}</span>
                {r.shot.notes && <span>{r.shot.notes}</span>}
              </figcaption>
            </figure>
          ); })}
        </section>}
      </article>
    </div>
  );
}
