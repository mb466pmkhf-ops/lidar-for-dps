// The kit list a gaffer works from: units, modifiers, gels, grip and stands, counted from the plan,
// plus the estimated power. Same rules as FrameScout/Core/Models/KitList.swift: keep both in step.
import type { LightFixture } from './types';
import { KIND_INFO, filters, fixtureModifier, fixtureProfile, photometrics } from './photometrics';
import { gripLabel, isGrip } from './grip';
import { gripStandCount, lightSupport, lightSupportInfo } from './rigging';

export interface KitLine { qty: number; item: string }
export interface Kit {
  units: KitLine[];
  modifiers: KitLine[];
  gels: KitLine[];
  grip: KitLine[];
  stands: KitLine[];
  /** Estimated draw of the units that are on, at their set output (watts). */
  drawNow: number;
  /** Rated power of every unit on the plan, on or off: what to plan circuits for (watts). */
  drawRated: number;
}

function count(items: string[]): KitLine[] {
  const m = new Map<string, number>();
  for (const i of items) m.set(i, (m.get(i) ?? 0) + 1);
  return [...m].map(([item, qty]) => ({ qty, item })).sort((a, b) => b.qty - a.qty || a.item.localeCompare(b.item));
}

/** Practicals are set dressing, so they count as units only when they carry a rated wattage of their own. */
export function kitList(lights: LightFixture[]): Kit {
  const units: string[] = [], modifiers: string[] = [], gels: string[] = [], grip: string[] = [], stands: string[] = [];
  let drawNow = 0, drawRated = 0;
  for (const l of lights) {
    const support = lightSupport(l);
    if (support !== 'none' && support !== 'floor') for (let i = 0; i < gripStandCount(l); i++) stands.push(lightSupportInfo(support).label);
    if (isGrip(l.kind)) { grip.push(gripLabel(l) || KIND_INFO[l.kind].label); continue; }
    if (!KIND_INFO[l.kind].emits) continue;
    const p = fixtureProfile(l);
    units.push(p.name);
    const mod = fixtureModifier(l);
    if (mod && mod.id !== p.defaultModifierID) modifiers.push(mod.name);
    for (const id of l.filterIDs ?? []) { const f = filters.find(x => x.id === id); if (f) gels.push(f.name); }
    drawRated += p.ratedPower;
    if (l.isOn) drawNow += photometrics(l).drawWatts;
  }
  return { units: count(units), modifiers: count(modifiers), gels: count(gels), grip: count(grip), stands: count(stands), drawNow, drawRated };
}

/** Amps on a supply, for a quick circuit check. */
export const amps = (watts: number, volts: number) => watts / volts;

/** Plain text, for pasting into a message or a call sheet. */
export function kitText(k: Kit, title: string, lights?: LightFixture[], rates?: Rates): string {
  const out = [title, ''];
  const section = (name: string, lines: KitLine[]) => { if (lines.length) out.push(name, ...lines.map(l => `  ${l.qty} × ${l.item}`), ''); };
  section('Units', k.units);
  section('Modifiers', k.modifiers);
  section('Gels and diffusion', k.gels);
  section('Grip', k.grip);
  section('Stands', k.stands);
  if (k.drawRated > 0) {
    out.push('Power (estimated)',
      `  Rated, all units: ${Math.round(k.drawRated)} W (${amps(k.drawRated, 230).toFixed(1)} A at 230 V, ${amps(k.drawRated, 120).toFixed(1)} A at 120 V)`,
      `  As set, units on: ${Math.round(k.drawNow)} W`);
  }
  if (lights?.length) {
    for (const id of ['uk13', 'us15']) {
      const c = circuitPlan(lights, supplyByID(id));
      if (!c.circuits && !c.tooBig.length) continue;
      out.push(`  ${c.supply.label}s: ${c.circuits} separate circuit${c.circuits === 1 ? '' : 's'}${c.tooBig.length ? `; too big for one: ${c.tooBig.join(', ')}` : ''}`);
    }
  }
  if (rates) {
    const c = kitCost(k, rates);
    if (c.lines.length) {
      out.push('', 'Your day rates', ...c.lines.map(l => `  ${l.qty} × ${l.item} at ${money(l.rate, rates.currency)} = ${money(l.total, rates.currency)}`),
        `  Per day: ${money(c.perDay, rates.currency)}${c.missing.length ? ` (no rate for ${c.missing.join(', ')})` : ''}`);
    }
  }
  return out.join('\n').trim() + '\n';
}

// MARK: Supplies and circuits

/** A wall supply. Planned at 80 % of the rating, the usual allowance for a load left on for hours. */
export interface Supply { id: string; label: string; volts: number; amps: number }
export const SUPPLIES: Supply[] = [
  { id: 'uk13', label: 'UK 13 A socket', volts: 230, amps: 13 },
  { id: 'eu16', label: 'EU 16 A socket', volts: 230, amps: 16 },
  { id: 'us15', label: 'US 15 A circuit', volts: 120, amps: 15 },
  { id: 'us20', label: 'US 20 A circuit', volts: 120, amps: 20 },
];
export const CONTINUOUS_LOAD = 0.8;
export const supplyByID = (id?: string) => SUPPLIES.find(s => s.id === id) ?? SUPPLIES[0];
/** Watts one circuit of this supply carries for hours. */
export const circuitWatts = (s: Supply) => s.volts * s.amps * CONTINUOUS_LOAD;

export interface CircuitPlan {
  supply: Supply;
  /** Separate circuits the rated load needs, at least one. */
  circuits: number;
  /** Units too big for one of these circuits on their own: they need a bigger supply or a generator. */
  tooBig: string[];
}

/** Circuits for every unit on the plan at its rating (on or off), packed largest first so no unit is
 *  split across two circuits. An estimate: the venue's wiring decides what is really on each circuit. */
export function circuitPlan(lights: LightFixture[], supply: Supply): CircuitPlan {
  const cap = circuitWatts(supply);
  const loads: { name: string; w: number }[] = [];
  for (const l of lights) {
    if (!KIND_INFO[l.kind].emits || isGrip(l.kind)) continue;
    const p = fixtureProfile(l);
    if (p.ratedPower > 0) loads.push({ name: p.name, w: p.ratedPower });
  }
  const tooBig = [...new Set(loads.filter(x => x.w > cap).map(x => x.name))];
  const bins: number[] = [];
  for (const x of loads.filter(x => x.w <= cap).sort((a, b) => b.w - a.w)) {
    const i = bins.findIndex(b => b + x.w <= cap);
    if (i >= 0) bins[i] += x.w; else bins.push(x.w);
  }
  return { supply, circuits: Math.max(bins.length, loads.length ? 1 : 0), tooBig };
}

// MARK: Batteries

/** Common V-mount and block sizes (Wh). 98 Wh packs stay under the 100 Wh airline carry-on limit. */
export const BATTERY_SIZES = [98, 150, 290];
/** Share of a pack's rating a unit really gets (converter losses, the cut-off before empty). */
export const BATTERY_USABLE = 0.85;
/** Minutes a pack runs a unit drawing `watts`. Estimated. */
export const batteryMinutes = (watts: number, wh: number) => (watts > 0 ? (wh * BATTERY_USABLE / watts) * 60 : Infinity);
/** "1 h 10 min", "25 min". Units above a few hundred watts aren't run on packs: they get no figure. */
export function runTimeLabel(watts: number, wh: number): string {
  if (!(watts > 0)) return '';
  if (watts > 400) return 'mains';
  const m = Math.round(batteryMinutes(watts, wh));
  return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min`;
}

// MARK: Your day rates

/** Day rates the user types in, per kit item, in their own currency. FrameScan has no prices of its own.
 *  Kept on this device (localStorage `framescan.rates`, the iPhone's UserDefaults) like My presets. */
export interface Rates { currency: string; items: Record<string, number> }
export const emptyRates = (): Rates => ({ currency: '£', items: {} });

export interface CostLine { qty: number; item: string; rate: number; total: number }
export interface Cost { lines: CostLine[]; perDay: number; missing: string[] }

/** Each kit line priced at the user's rate. Lines without a rate are listed as missing, never guessed. */
export function kitCost(k: Kit, rates: Rates): Cost {
  const all = [...k.units, ...k.modifiers, ...k.gels, ...k.grip, ...k.stands];
  const lines: CostLine[] = [], missing: string[] = [];
  for (const l of all) {
    const r = rates.items[l.item];
    if (r === undefined || !(r >= 0)) { missing.push(l.item); continue; }
    lines.push({ qty: l.qty, item: l.item, rate: r, total: r * l.qty });
  }
  return { lines, perDay: lines.reduce((s, l) => s + l.total, 0), missing };
}

export const money = (v: number, currency: string) => `${currency}${v.toLocaleString('en-GB', { minimumFractionDigits: Number.isInteger(v) ? 0 : 2, maximumFractionDigits: 2 })}`;

/** JSON as stored and as Copy / Paste moves it between devices: {"framescanRates":1,"currency":"£","items":{…}}. */
export function ratesJSON(r: Rates): string { return JSON.stringify({ framescanRates: 1, currency: r.currency, items: r.items }); }
export function parseRates(text: string | null | undefined): Rates | undefined {
  if (!text) return undefined;
  try {
    const o = JSON.parse(text) as { framescanRates?: number; currency?: unknown; items?: unknown };
    if (o.framescanRates !== 1 || typeof o.items !== 'object' || !o.items) return undefined;
    const items: Record<string, number> = {};
    for (const [k, v] of Object.entries(o.items as Record<string, unknown>)) if (typeof v === 'number' && v >= 0 && Number.isFinite(v)) items[k] = v;
    return { currency: typeof o.currency === 'string' && o.currency.length <= 4 ? o.currency : '£', items };
  } catch { return undefined; }
}
