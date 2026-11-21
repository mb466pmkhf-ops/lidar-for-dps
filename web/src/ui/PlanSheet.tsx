// The hand-off sheet: the plan as framed on screen, every unit with its settings, the readings,
// the kit list and the estimated power, on one printable page. Print saves it as a PDF too.
import { useMemo, useState } from 'react';
import type { ExposureSettings, FloorPlan, LightFixture, Location, Project } from '../model/types';
import type { MeterPoint } from '../model/calculator';
import { KIND_INFO, filters, fixtureModifier, fixtureProfile, photometrics } from '../model/photometrics';
import { exposureTime, speedLabel, stopLabel, stopsDelta, stopsForLux, trim } from '../model/exposure';
import { gripLabel, isGrip } from '../model/grip';
import { lightSupport, lightSupportInfo } from '../model/rigging';
import { BATTERY_SIZES, SUPPLIES, amps, circuitPlan, emptyRates, kitCost, kitList, kitText, money, parseRates, ratesJSON, runTimeLabel, supplyByID, type KitLine, type Rates } from '../model/kit';
import { metres, pct, reading as fmtReading, watts } from './format';
import { Icon } from './icons';
import { activeLook, looksOf } from '../model/looks';
import { horizontalFOV, sensorFor } from '../model/camera';
import { focalNumber } from '../model/lenses';
import { planDist } from '../model/calculator';
import { inFrameSentence, unitsInFrame } from '../model/frameCheck';
import { useModal } from './useModal';

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
function RatesEditor({ lines, rates, onChange }: { lines: KitLine[]; rates: Rates; onChange(r: Rates): void }) {
  const [note, setNote] = useState('');
  // Bumped on paste so the typed-in fields show the pasted rates.
  const [ver, setVer] = useState(0);
  const set = (item: string, text: string) => {
    const items = { ...rates.items };
    const v = Number(text.replace(/,/g, ''));
    if (text.trim() === '' || !(v >= 0) || !Number.isFinite(v)) delete items[item]; else items[item] = v;
    onChange({ ...rates, items });
  };
  const copy = () => { void navigator.clipboard?.writeText(ratesJSON(rates)).then(() => setNote('Rates copied')).catch(() => setNote("Couldn't copy")); };
  const paste = () => {
    void navigator.clipboard?.readText().then(t => {
      const r = parseRates(t);
      if (r) { onChange({ currency: r.currency, items: { ...rates.items, ...r.items } }); setVer(v => v + 1); setNote('Rates pasted'); } else setNote('Nothing to paste: copy rates from FrameScan first');
    }).catch(() => setNote("Couldn't read the clipboard"));
  };
  return (
    <details className="sheet-rates-edit">
      <summary>Type your day rates</summary>
      <p className="faint">Type what you pay a day for each item, from your rental house or your own kit. They stay on this computer and are only used on this sheet and the copied kit list.</p>
      <label className="sheet-rate-row"><span>Currency</span><input value={rates.currency} maxLength={4} onChange={ev => onChange({ ...rates, currency: ev.target.value })} aria-label="Currency symbol" /></label>
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

export function PlanSheet({ project, location, lights, meters, readings, exposure: e, plan, floorPlan, scanID, onClose }: {
  project: Project; location: Location; lights: LightFixture[]; meters: MeterPoint[]; readings: Map<string, number>;
  exposure: ExposureSettings; plan?: { url: string; w: number; h: number }; floorPlan?: FloorPlan; scanID?: string; onClose(): void;
}) {
  const kit = useMemo(() => kitList(lights), [lights]);
  const scan = scanID ?? location.primaryScanID ?? location.scans[location.scans.length - 1]?.id;
  const look = activeLook(location, scan);
  const looks = looksOf(location, scan);
  const inScan = (id?: string) => !id || !scan || id.toUpperCase() === scan.toUpperCase();
  const shots = location.shots.filter(x => inScan(x.scanID)).sort((a, b) => a.number - b.number);
  const title = `${project.name} — ${location.name}${look ? ` · ${look.name}` : ''}`;
  const [copied, setCopied] = useState(false);
  const camera = [stopLabel(e.tStop), `ISO ${e.iso}`, `${trim(e.frameRate)} fps`, e.shutterSeconds !== undefined ? speedLabel(e.shutterSeconds) : `${trim(e.shutterAngle)}° (${speedLabel(exposureTime(e))})`, e.ndStops ? `ND ${(e.ndStops * 0.3).toFixed(1)}` : ''].filter(Boolean).join(' · ');
  const savePNG = () => {
    if (!plan) return;
    const img = new Image();
    img.onload = () => {
      const c = document.createElement('canvas'); c.width = plan.w * 2; c.height = plan.h * 2;
      const g = c.getContext('2d')!; g.scale(2, 2); g.drawImage(img, 0, 0);
      const a = document.createElement('a'); a.href = c.toDataURL('image/png'); a.download = `${title.replace(/[^\w\- ]+/g, '')} plan.png`; a.click();
    };
    img.src = plan.url;
  };
  const [supplyID, setSupplyID] = useState(() => supplyByID(stored(SUPPLY_KEY) ?? undefined).id);
  const [pack, setPack] = useState(() => { const v = Number(stored(PACK_KEY)); return BATTERY_SIZES.includes(v) ? v : BATTERY_SIZES[0]; });
  const [rates, setRatesState] = useState<Rates>(() => parseRates(stored(RATES_KEY)) ?? emptyRates());
  const setRates = (r: Rates) => { setRatesState(r); store(RATES_KEY, ratesJSON(r)); };
  const circuits = useMemo(() => circuitPlan(lights, supplyByID(supplyID)), [lights, supplyID]);
  const cost = kitCost(kit, rates);
  const kitLines = [...kit.units, ...kit.modifiers, ...kit.gels, ...kit.grip, ...kit.stands];
  const copy = () => { void navigator.clipboard?.writeText(kitText(kit, title, lights, rates)).then(() => setCopied(true)).catch(() => setCopied(false)); };
  const dialogRef = useModal<HTMLElement>(onClose);
  return (
    <div className="scrim sheet-scrim" onClick={onClose}>
      <article className="sheet" role="dialog" aria-modal="true" ref={dialogRef} aria-label="Lighting plan sheet" onClick={ev => ev.stopPropagation()}>
        <div className="sheet-actions">
          <button className="btn primary small" onClick={() => window.print()}><Icon name="download" /> Print or save PDF</button>
          <button className="btn small" onClick={savePNG} disabled={!plan}>Plan as PNG</button>
          <button className="btn small" onClick={copy}>{copied ? 'Copied' : 'Copy kit list'}</button>
          <span className="spacer" />
          <button className="btn ghost small" onClick={onClose}>Close</button>
        </div>
        <header className="sheet-head">
          <h2>{title}</h2>
          <p className="mono">{camera}</p>
          <p className="faint">{new Date().toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' })}{project.client ? ` · ${project.client}` : ''}</p>
        </header>
        {plan && <img className="sheet-plan" src={plan.url} alt="Lighting plan" />}
        {shots.length > 0 && <>
          <h3>Shots</h3>
          <table className="sheet-table">
            <thead><tr><th>Shot</th><th>Lens</th><th>Lens height</th><th>To subject</th><th>Lit with</th><th>In frame</th><th>Notes</th></tr></thead>
            <tbody>{shots.map(x => {
              // A shot lit with another saved look is checked against that look's units; the active look
              // (or none) uses the live units so unsaved changes show.
              const shotLook = x.lookID ? looks.find(l => l.id.toUpperCase() === x.lookID!.toUpperCase()) : undefined;
              const units = shotLook && shotLook !== look ? shotLook.lights.filter(l => inScan(l.scanID)) : lights;
              const seen = inFrameSentence(unitsInFrame(x.rig, units, floorPlan));
              const lit = shotLook?.name ?? (look && !x.lookID ? look.name : '');
              return <tr key={x.id}>
                <td>{`Shot ${String(x.number).padStart(2, '0')}`}{x.title ? ` · ${x.title}` : ''}</td>
                <td className="mono">{focalNumber(x.rig.focalLength)}mm · {Math.round(horizontalFOV(x.rig))}° · {sensorFor(x.rig).name}</td>
                <td className="mono">{metres(x.rig.height)}{x.rig.tilt ? ` · tilt ${x.rig.tilt > 0 ? '+' : ''}${Math.round(x.rig.tilt)}°` : ''}</td>
                <td className="mono">{x.subject ? metres(planDist(x.rig.position, x.subject)) : ''}</td>
                <td>{lit}</td>
                <td>{seen || 'Clear'}</td>
                <td>{x.notes}</td>
              </tr>;
            })}</tbody>
          </table>
        </>}
        <h3>Units</h3>
        <table className="sheet-table">
          <thead><tr><th>Name</th><th>Unit</th><th>Modifier and gels</th><th>Output</th><th>Colour</th><th>Height</th><th>Stand</th><th>On a {pack} Wh pack</th></tr></thead>
          <tbody>{lights.map(l => { const r = unitRow(l); return <tr key={l.id}><td>{r.name}</td><td>{r.unit}</td><td>{r.shaping}</td><td className="mono">{r.output}</td><td className="mono">{r.colour}</td><td className="mono">{r.height}</td><td>{r.stand}</td><td className="mono">{packTime(l, pack)}</td></tr>; })}</tbody>
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
      </article>
    </div>
  );
}
