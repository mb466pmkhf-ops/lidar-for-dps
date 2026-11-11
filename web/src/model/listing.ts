// "Build from a listing": read room sizes out of text copied from a studio or location website
// ("Studio 2: 15m x 10m x 6m to grid, 1,600 sq ft, two windows, loading door 3m x 4m") and turn
// them into a drawn room. Mirrors FrameScout/Core/Models/ListingReader.swift line for line; both
// run the cases in web/tests/fixtures/listings.json. Nothing here is measured: every figure is
// copied from someone else's description, so the room is saved as entered by hand.
import { defaultRoom, normalise, type RoomSpec } from './room';

export type FindingKind = 'size' | 'ceiling' | 'area' | 'windows' | 'door' | 'skipped';
export interface ListingFinding {
  kind: FindingKind;
  /** Plain words, e.g. "Room 15 × 10 m". */
  text: string;
  /** The part of the listing it came from. */
  quote: string;
}
export interface ListingSize { length: number; width: number; ceiling?: number; quote: string }
export type SizeSource = 'listed' | 'fromArea' | 'squareFromArea' | 'none';
export interface ListingReading {
  /** Longer side (m). */
  length?: number;
  /** Shorter side (m). */
  width?: number;
  ceiling?: number;
  /** Floor area (m²) when the listing gives one. */
  area?: number;
  windows?: number;
  door?: boolean;
  sizeSource: SizeSource;
  findings: ListingFinding[];
  /** Other room sizes in the listing (another studio, a second stage), largest first. */
  alternatives: ListingSize[];
}

const FOOT = 0.3048, INCH = 0.0254;
const LENGTH_UNITS: Record<string, number> = {
  m: 1, metre: 1, metres: 1, meter: 1, meters: 1, mtr: 1, mtrs: 1, cm: 0.01, mm: 0.001,
  ft: FOOT, feet: FOOT, foot: FOOT, "'": FOOT, in: INCH, inch: INCH, inches: INCH, '"': INCH,
};
const AREA_UNITS: Record<string, number> = { sqm: 1, sqft: FOOT * FOOT };
const NUMBER_WORDS: Record<string, number> = {
  no: 0, zero: 0, a: 1, an: 1, one: 1, single: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
};
// Words that label the figure after them ("ceiling height 6m") or before them ("6m high").
const BEFORE_WORDS: Record<string, Role> = {
  ceiling: 'ceiling', ceilings: 'ceiling', height: 'ceiling', headroom: 'ceiling', grid: 'ceiling', clearance: 'ceiling',
  length: 'length', width: 'width', depth: 'width',
};
const AFTER_WORDS: Record<string, Role> = {
  high: 'ceiling', tall: 'ceiling', grid: 'ceiling', ceiling: 'ceiling', ceilings: 'ceiling', headroom: 'ceiling', clear: 'ceiling',
  long: 'length', wide: 'width', deep: 'width',
};
const ROOM_WORDS = ['studio', 'stage', 'room', 'floor', 'space', 'dimensions', 'dimension', 'size', 'overall', 'shooting', 'area', 'hall', 'footprint', 'internal', 'set'];
// A size in a clause with one of these is a door, a cyc or a side room, not the shooting space.
const FEATURE_WORDS = ['door', 'doors', 'doorway', 'entrance', 'access', 'shutter', 'cyc', 'cyclorama', 'cove', 'infinity', 'screen',
  'dressing', 'makeup', 'kitchen', 'office', 'lounge', 'parking', 'car', 'lift', 'elevator', 'window', 'windows', 'table', 'backdrop', 'green', 'production', 'toilet', 'toilets', 'bathroom'];
const DOOR_WORDS = ['door', 'doors', 'doorway', 'shutter', 'entrance'];
const NO_WINDOW_PHRASES = ['no windows', 'no window', 'windowless', 'blackout', 'no natural light', 'no daylight'];

type Role = 'ceiling' | 'length' | 'width';
/** Own keys only, so a word like "constructor" never reads as a unit. */
const look = <T>(table: Record<string, T>, key: string): T | undefined => Object.prototype.hasOwnProperty.call(table, key) ? table[key] : undefined;
type Token = { t: 'num'; v: number } | { t: 'word'; v: string };
interface Quantity { value: number; unit?: string; area: boolean; start: number; end: number }

/** Lower case, one spelling for units and the "by" sign, so the tokeniser stays simple. */
export function normaliseListing(text: string): string {
  let s = text.toLowerCase();
  s = s.replace(/[×✕✖]/g, ' x ').replace(/[’′‘`]/g, "'").replace(/[”″“]/g, '"');
  s = s.replace(/square\s+(?:metres|meters|metre|meter|m)\b/g, ' sqm ').replace(/square\s+(?:feet|foot|ft)\b/g, ' sqft ');
  s = s.replace(/sq\.?\s*(?:metres|meters|m)\b\.?/g, ' sqm ').replace(/sq\.?\s*(?:feet|ft)\b\.?/g, ' sqft ');
  s = s.replace(/m²|m2\b/g, ' sqm ').replace(/ft²|ft2\b/g, ' sqft ');
  // "12x8m", "12mx8m", "40'x30'": space out an x that sits between two sizes.
  s = s.replace(/([0-9'"]|m|t)\s*x(?=\s*\d)/g, '$1 x ');
  return s;
}

function tokenise(clause: string): Token[] {
  const out: Token[] = [];
  let i = 0;
  const isDigit = (c: string) => c >= '0' && c <= '9';
  const isLetter = (c: string) => c >= 'a' && c <= 'z';
  while (i < clause.length) {
    const c = clause[i];
    if (isDigit(c)) {
      let j = i;
      while (j < clause.length && isDigit(clause[j])) j++;
      let digits = clause.slice(i, j);
      let value = Number(digits);
      // "1,600" is sixteen hundred; "4,5" and "4.5" are four and a half.
      while (j + 1 < clause.length && (clause[j] === ',' || clause[j] === '.') && isDigit(clause[j + 1])) {
        let k = j + 1;
        while (k < clause.length && isDigit(clause[k])) k++;
        const frac = clause.slice(j + 1, k);
        if (clause[j] === ',' && frac.length === 3) { digits += frac; value = Number(digits); }
        else { value = Number(digits + '.' + frac); j = k; break; }
        j = k;
      }
      out.push({ t: 'num', v: value });
      i = j;
    } else if (isLetter(c)) {
      let j = i;
      while (j < clause.length && isLetter(clause[j])) j++;
      out.push({ t: 'word', v: clause.slice(i, j) });
      i = j;
    } else {
      if (c === "'" || c === '"') out.push({ t: 'word', v: c });
      i++;
    }
  }
  return out;
}

/** Numbers with their units, joining 12' 6" into one length. Values are metres or square metres. */
function quantities(tokens: Token[]): Quantity[] {
  const out: Quantity[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const tok = tokens[i];
    if (tok.t !== 'num') continue;
    const next = tokens[i + 1];
    const unit = next && next.t === 'word' ? next.v : undefined;
    const areaScale = unit === undefined ? undefined : look(AREA_UNITS, unit);
    const lengthScale = unit === undefined ? undefined : look(LENGTH_UNITS, unit);
    if (areaScale !== undefined) {
      out.push({ value: tok.v * areaScale, unit, area: true, start: i, end: i + 1 });
      i++;
      continue;
    }
    if (lengthScale !== undefined) {
      let value = tok.v * lengthScale, end = i + 1;
      const n2 = tokens[i + 2], u2 = tokens[i + 3];
      if (lengthScale === FOOT && n2 && n2.t === 'num' && u2 && u2.t === 'word' && look(LENGTH_UNITS, u2.v) === INCH && n2.v < 12) {
        value += n2.v * INCH; end = i + 3;
      }
      out.push({ value, unit, area: false, start: i, end });
      i = end;
      continue;
    }
    out.push({ value: tok.v, area: false, start: i, end: i });
  }
  return out;
}

/** The label words next to a figure: before it (nearest first, up to 4) and after it (up to 3), never reaching past another number. */
function contextOf(tokens: Token[], start: number, end: number): { before: string[]; after: string[] } {
  const before: string[] = [], after: string[] = [];
  for (let k = start - 1; k >= 0 && k >= start - 4; k--) {
    const t = tokens[k];
    if (t.t === 'num') break;
    before.push(t.v);
  }
  for (let k = end + 1; k < tokens.length && k <= end + 3; k++) {
    const t = tokens[k];
    if (t.t === 'num') break;
    after.push(t.v);
  }
  return { before, after };
}

/** What a lone figure is: "6m high" and "40 ft long" read the word after it first, then "ceiling height 6m" the word before. */
function roleOf(ctx: { before: string[]; after: string[] }): Role | undefined {
  for (const w of ctx.after) { const r = look(AFTER_WORDS, w); if (r) return r; }
  for (const w of ctx.before) { const r = look(BEFORE_WORDS, w); if (r) return r; }
  return undefined;
}

const wordAt = (tokens: Token[], i: number) => { const t = tokens[i]; return t && t.t === 'word' ? t.v : undefined; };
const round2 = (v: number) => Math.round(v * 100) / 100;
const fmt = (v: number) => String(round2(v));

/** Lines and sentences of the original text, so a quote reads as the listing wrote it. */
function clauses(text: string): string[] {
  return text.split(/\n|;|•|\||\.(?=\s|$)/).map(c => c.replace(/\s+/g, ' ').trim()).filter(c => c.length > 0);
}

function quoteOf(clause: string) {
  return clause.length > 90 ? clause.slice(0, 87) + '…' : clause;
}

/** Reads room sizes, ceiling, area, windows and doors out of free text. */
export function readListing(text: string): ListingReading {
  const findings: ListingFinding[] = [];
  const groups: { length: number; width: number; ceiling?: number; quote: string; roomy: boolean }[] = [];
  let length: number | undefined, width: number | undefined, ceiling: number | undefined, area: number | undefined;
  let windows: number | undefined, door: boolean | undefined;
  const drop = (kind: FindingKind) => { const i = findings.findIndex(f => f.kind === kind); if (i >= 0) findings.splice(i, 1); };

  const whole = normaliseListing(text);
  if (NO_WINDOW_PHRASES.some(p => whole.includes(p))) windows = 0;

  for (const original of clauses(text)) {
    const clause = normaliseListing(original);
    const tokens = tokenise(clause);
    const words = new Set(tokens.filter(t => t.t === 'word').map(t => t.v as string));
    const clauseFeature = FEATURE_WORDS.some(w => words.has(w));
    const clauseRoomy = ROOM_WORDS.some(w => words.has(w));
    const quote = quoteOf(original);
    const qs = quantities(tokens);
    const used = new Set<number>();

    if (door === undefined && DOOR_WORDS.some(w => words.has(w))) {
      door = true;
      findings.push({ kind: 'door', text: 'A door', quote });
    }
    // "two windows", "3 large windows", "a single window".
    for (let i = 0; i < tokens.length; i++) {
      const w = wordAt(tokens, i);
      if (w !== 'window' && w !== 'windows') continue;
      for (let back = 1; back <= 2 && i - back >= 0; back++) {
        const t = tokens[i - back];
        const n = t.t === 'num' ? t.v : look(NUMBER_WORDS, t.v);
        if (n === undefined || !Number.isInteger(n) || n > 20) continue;
        if (windows === undefined || (windows === 0 && n > 0)) {
          windows = n;
          drop('windows');
          findings.push({ kind: 'windows', text: n === 1 ? '1 window' : `${n} windows`, quote });
        }
        break;
      }
    }

    // Sizes written as A x B (x C), with the unit on each number or only on the last.
    for (let i = 0; i < qs.length; i++) {
      if (qs[i].area) continue;
      let j = i;
      while (j + 1 < qs.length && j - i < 2) {
        const sep = wordAt(tokens, qs[j].end + 1);
        if ((sep === 'x' || sep === 'by') && qs[j + 1].start === qs[j].end + 2 && !qs[j + 1].area) j++; else break;
      }
      if (j === i) continue;
      const run = qs.slice(i, j + 1);
      const first = i;
      i = j;
      let unit: string | undefined;
      for (const q of run) if (q.unit) unit = q.unit;
      if (unit === undefined) continue;
      const scale = look(LENGTH_UNITS, unit) ?? 1;
      const vals = run.map(q => q.unit !== undefined ? q.value : q.value * scale);
      for (let k = first; k <= j; k++) used.add(k);
      const a = Math.max(vals[0], vals[1]), b = Math.min(vals[0], vals[1]);
      const h = vals.length === 3 ? vals[2] : undefined;
      const label = `${fmt(vals[0])} × ${fmt(vals[1])}${h !== undefined ? ' × ' + fmt(h) : ''} m`;
      const ctx = contextOf(tokens, run[0].start, run[run.length - 1].end);
      const localFeature = ctx.before.some(w => FEATURE_WORDS.includes(w));
      const localRoomy = ctx.before.some(w => ROOM_WORDS.includes(w));
      if (localFeature || (clauseFeature && !clauseRoomy && !localRoomy)) { findings.push({ kind: 'skipped', text: `Not the room: ${label}`, quote }); continue; }
      if (b < 1.5 || a > 300) { findings.push({ kind: 'skipped', text: `Too small or large for a room: ${label}`, quote }); continue; }
      groups.push({ length: a, width: b, ceiling: h !== undefined && h >= 1.8 && h <= 40 ? h : undefined, quote, roomy: localRoomy || clauseRoomy });
    }

    // Single labelled figures: "ceiling height 6m", "7 m to grid", "length 20m", "1,600 sq ft".
    for (let i = 0; i < qs.length; i++) {
      const q = qs[i];
      if (used.has(i) || q.unit === undefined) continue;
      const ctx = contextOf(tokens, q.start, q.end);
      // "Loading door 4m high" is the door. An area's unit already says what it is, so only the words before count.
      if (ctx.before.some(w => FEATURE_WORDS.includes(w)) || (!q.area && ctx.after.some(w => FEATURE_WORDS.includes(w)))) continue;
      if (q.area) {
        if (area === undefined || q.value > area) {
          area = q.value;
          drop('area');
          findings.push({ kind: 'area', text: `Floor area ${fmt(q.value)} m²`, quote });
        }
        continue;
      }
      const role = roleOf(ctx);
      if (role === 'ceiling' && ceiling === undefined && q.value >= 1.8 && q.value <= 40) {
        ceiling = q.value;
        findings.push({ kind: 'ceiling', text: `Ceiling ${fmt(q.value)} m`, quote });
      } else if (role === 'length' && length === undefined && q.value >= 1.5) {
        length = q.value;
        findings.push({ kind: 'size', text: `Length ${fmt(q.value)} m`, quote });
      } else if (role === 'width' && width === undefined && q.value >= 1.5) {
        width = q.value;
        findings.push({ kind: 'size', text: `Width ${fmt(q.value)} m`, quote });
      }
    }
  }

  // The room is the biggest size named as the studio or space; otherwise the biggest size at all.
  const roomy = groups.filter(g => g.roomy);
  const ranked = (roomy.length > 0 ? roomy : groups).slice().sort((x, y) => y.length * y.width - x.length * x.width);
  const best = ranked[0];
  let sizeSource: SizeSource = 'none';
  if (best) {
    length = best.length; width = best.width; sizeSource = 'listed';
    if (best.ceiling !== undefined) { ceiling = best.ceiling; drop('ceiling'); }
    findings.unshift({ kind: 'size', text: `Room ${fmt(best.length)} × ${fmt(best.width)} m${best.ceiling !== undefined ? `, ${fmt(best.ceiling)} m high` : ''}`, quote: best.quote });
  } else if (length !== undefined && width !== undefined) {
    sizeSource = 'listed';
  } else if (area !== undefined && (length !== undefined || width !== undefined)) {
    const known = length ?? width ?? 0;
    const other = area / known;
    length = Math.max(known, other); width = Math.min(known, other); sizeSource = 'fromArea';
  } else if (area !== undefined && area >= 2.25) {
    length = Math.sqrt(area); width = length; sizeSource = 'squareFromArea';
  } else {
    length = undefined; width = undefined;
  }
  if (length !== undefined && width !== undefined && width > length) [length, width] = [width, length];

  const r2 = (v: number | undefined) => v === undefined ? undefined : round2(v);
  const out: ListingReading = { sizeSource, findings, alternatives: ranked.slice(1, 5).map(g => ({ length: round2(g.length), width: round2(g.width), ceiling: r2(g.ceiling), quote: g.quote })) };
  if (length !== undefined) out.length = round2(length);
  if (width !== undefined) out.width = round2(width);
  if (ceiling !== undefined) out.ceiling = round2(ceiling);
  if (area !== undefined) out.area = round2(area);
  if (windows !== undefined) out.windows = windows;
  if (door !== undefined) out.door = door;
  return out;
}

/** The drawn room the listing describes. Anything the listing doesn't say keeps `base`. */
export function roomFromListing(r: ListingReading, base: RoomSpec = defaultRoom): RoomSpec {
  return normalise({
    ...base,
    length: r.length ?? base.length,
    width: r.width ?? base.width,
    ceiling: r.ceiling ?? base.ceiling,
    windows: r.windows ?? base.windows,
    door: r.door ?? base.door,
  });
}

/** One line on where the size came from, for under the preview. */
export function sizeNote(r: ListingReading): string {
  switch (r.sizeSource) {
    case 'listed': return 'Sizes copied from the listing, not measured.';
    case 'fromArea': return 'One side is worked out from the floor area in the listing.';
    case 'squareFromArea': return 'The listing only gives a floor area, so this is a square of that area. Check the photos and set the real shape.';
    case 'none': return 'No room size found in the text. Set the sizes yourself.';
  }
}
