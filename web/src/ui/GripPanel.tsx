// Size, rag and gels for a flag, frame or bounce. Kept apart from Inspector.tsx so the grip catalogue
// (model/grip.ts) has one place in the UI. Same choices as the phone's light editor.
import type { LightFixture } from '../model/types';
import {
  DRAPES, FRAME_GELS, applyDrape, applyGripSize, drape, drapeByID, frameGels, gripSize, isGrip, setFloppyOpen, sizesFor,
  DEFAULT_DRAPE, type GripKind,
} from '../model/grip';

const RAG_GROUPS: { label: string; kinds: GripKind[] }[] = [
  { label: 'Bounce', kinds: ['bounce'] },
  { label: 'Flags and negative fill', kinds: ['flag', 'negative'] },
  { label: 'Diffusion and nets', kinds: ['diffusion'] },
];

/** Stops of loss for a transmission, to the nearest third: "1⅓ stops". */
export function stopsText(t: number): string {
  if (!(t > 0)) return 'blocks it';
  if (t >= 0.97) return 'no loss';
  const thirds = Math.round((-Math.log2(t)) * 3);
  const whole = Math.floor(thirds / 3), part = ['', '⅓', '⅔'][thirds % 3];
  const n = (whole > 0 ? String(whole) : '') + part;
  return `about ${n} stop${thirds > 3 ? 's' : ''}`;
}

export function GripFields({ light: l, replace }: { light: LightFixture; replace(l: LightFixture): void }) {
  if (!isGrip(l.kind)) return null;
  const kind = l.kind;
  const size = gripSize(l);
  const rag = drape(l);
  const shown = rag ?? drapeByID(DEFAULT_DRAPE[kind])!;
  const gels = frameGels(l).map(g => g.id);
  const t = shown.transmission * frameGels(l).reduce((s, g) => s * g.transmission, 1);
  const toggleGel = (id: string) => {
    const others = ((l.filterIDs ?? []) as string[]).filter(x => x !== id);
    const n = { ...l, filterIDs: gels.includes(id) ? others : [...others, id] };
    if (n.filterIDs.length === 0) delete (n as Partial<LightFixture>).filterIDs;
    replace(n);
  };
  return (
    <>
      <div className="label" style={{ margin: '4px 0 6px' }}>Size</div>
      <div className="chips" style={{ marginBottom: 10 }}>
        {sizesFor(kind).map(s => (
          <button key={s.id} className={'chip' + (size?.id === s.id ? ' on' : '')} onClick={() => replace(applyGripSize(l, s))}>{s.name}</button>
        ))}
      </div>
      {size?.floppy && (
        <div className="chips" style={{ marginBottom: 10 }}>
          <button className={'chip' + (!l.floppyOpen ? ' on' : '')} onClick={() => replace(setFloppyOpen(l, false))}>Closed 4×4</button>
          <button className={'chip' + (l.floppyOpen ? ' on' : '')} onClick={() => replace(setFloppyOpen(l, true))}>Open 4×8</button>
        </div>
      )}
      <label className="field"><span>Rag</span>
        <select value={rag?.id ?? ''} aria-label="Rag" onChange={e => { const d = drapeByID(e.target.value); if (d) replace(applyDrape(l, d)); }}>
          {!rag && <option value="">{shown.name} (standard)</option>}
          {RAG_GROUPS.map(g => (
            <optgroup key={g.label} label={g.label}>
              {DRAPES.filter(d => g.kinds.includes(d.kinds[0])).map(d => <option key={d.id} value={d.id}>{d.name}</option>)}
            </optgroup>
          ))}
        </select><span />
      </label>
      {kind === 'diffusion' && (
        <>
          <div className="label" style={{ margin: '10px 0 6px' }}>Gels on the frame</div>
          <div className="chips" style={{ marginBottom: 10 }}>
            {FRAME_GELS.map(g => <button key={g.id} className={'chip' + (gels.includes(g.id) ? ' on' : '')} onClick={() => toggleGel(g.id)}>{g.name}</button>)}
          </div>
        </>
      )}
      <p className="note">
        {kind === 'bounce'
          ? `Throws back about ${Math.round(shown.reflectance * 100)} % of the light that lands on it.`
          : t > 0 ? `Light through it: ${stopsText(t)}${shown.scatter > 0.5 ? ', softened' : shown.scatter === 0 && t < 1 ? ', not softened' : ''}.`
          : 'Blocks the light that goes through it.'}
        {' '}{shown.note} Estimate.
      </p>
    </>
  );
}
