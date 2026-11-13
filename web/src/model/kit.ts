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
export function kitText(k: Kit, title: string): string {
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
  return out.join('\n').trim() + '\n';
}
