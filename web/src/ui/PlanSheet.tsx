// The hand-off sheet: the plan as framed on screen, every unit with its settings, the readings,
// the kit list and the estimated power, on one printable page. Print saves it as a PDF too.
import { useMemo, useState } from 'react';
import type { ExposureSettings, FloorPlan, LightFixture, Location, Project } from '../model/types';
import type { MeterPoint } from '../model/calculator';
import { KIND_INFO, filters, fixtureModifier, fixtureProfile, photometrics } from '../model/photometrics';
import { exposureTime, speedLabel, stopLabel, stopsDelta, stopsForLux, trim } from '../model/exposure';
import { gripLabel, isGrip } from '../model/grip';
import { lightSupport, lightSupportInfo } from '../model/rigging';
import { amps, kitList, kitText, type KitLine } from '../model/kit';
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

const Lines = ({ title, lines }: { title: string; lines: KitLine[] }) => lines.length ? (
  <div className="sheet-kit"><h4>{title}</h4><ul>{lines.map(l => <li key={l.item}><span className="mono">{l.qty} ×</span> {l.item}</li>)}</ul></div>
) : null;

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
  const copy = () => { void navigator.clipboard?.writeText(kitText(kit, title)).then(() => setCopied(true)).catch(() => setCopied(false)); };
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
          <thead><tr><th>Name</th><th>Unit</th><th>Modifier and gels</th><th>Output</th><th>Colour</th><th>Height</th><th>Stand</th></tr></thead>
          <tbody>{lights.map(l => { const r = unitRow(l); return <tr key={l.id}><td>{r.name}</td><td>{r.unit}</td><td>{r.shaping}</td><td className="mono">{r.output}</td><td className="mono">{r.colour}</td><td className="mono">{r.height}</td><td>{r.stand}</td></tr>; })}</tbody>
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
        <p className="note">≈ Readings and power are estimates from the plan (direct light, one bounce off boards and one off the room). Check on the day.</p>
      </article>
    </div>
  );
}
