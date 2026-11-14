// "Build from a listing": for a place nobody can recce. Add the studio's photos, paste the sizes from
// its website, check what was read, adjust, and build the room. Mirrors the iPhone's
// BuildFromListingView. The reader is model/listing.ts; nothing it reads is labelled as measured.
import { useEffect, useMemo, useState } from 'react';
import type { Project } from '../model/types';
import { ROOM_LIMITS, buildRoomPlan, defaultRoom, normalise, roomArea, roomOutline, type RoomSpec } from '../model/room';
import { LengthStepper } from './LengthStepper';
import { area } from './format';
import { readListing, roomFromListing, sizeNote, type FindingKind } from '../model/listing';
import { listingPhotos, type ListingPhoto } from '../sync/listingPhotos';
import { useModal } from './useModal';

export interface ListingFile { name: string; blob: Blob }

const fmt = (v: number) => String(Math.round(v * 100) / 100);
const MARK: Record<FindingKind, string> = { size: '▭', ceiling: '↕', area: '▦', windows: '◫', door: '⌂', skipped: '–' };
const EXAMPLE = 'Studio 2: 15m x 10m x 6m to grid. Two large windows. Loading door 3m x 4m.';

function Stepper({ label, note, value, step, min, max, onChange }: { label: string; note?: string; value: number; step: number; min: number; max: number; onChange(v: number): void }) {
  const set = (v: number) => onChange(Math.round(Math.min(max, Math.max(min, v)) * 100) / 100);
  return (
    <div className="stepper">
      <span><span style={{ display: 'block' }}>{label}</span>{note && <span className="note" style={{ margin: 0 }}>{note}</span>}</span>
      <span className="ctl">
        <button type="button" aria-label={`Less ${label.toLowerCase()}`} onClick={() => set(value - step)}>−</button>
        <input type="text" inputMode="decimal" aria-label={label} value={String(value)}
          onChange={e => { const n = parseFloat(e.target.value.replace(',', '.')); if (Number.isFinite(n)) onChange(n); }} onBlur={() => set(value)} />
        <span className="unit" aria-hidden="true">{step < 1 ? 'm' : ''}</span>
        <button type="button" aria-label={`More ${label.toLowerCase()}`} onClick={() => set(value + step)}>+</button>
      </span>
    </div>
  );
}

function useObjectURLs(files: ListingFile[]) {
  const urls = useMemo(() => files.map(f => URL.createObjectURL(f.blob)), [files]);
  useEffect(() => () => urls.forEach(u => URL.revokeObjectURL(u)), [urls]);
  return urls;
}

export function ListingDialog({ projects, currentProjectID, onCreate, onClose }: {
  projects: Project[]; currentProjectID?: string;
  onCreate(name: string, spec: RoomSpec, projectID: string | undefined, listing: string, photos: ListingFile[]): void; onClose(): void;
}) {
  const [name, setName] = useState('Studio');
  const [text, setText] = useState('');
  const [spec, setSpec] = useState<RoomSpec>(defaultRoom);
  const [files, setFiles] = useState<ListingFile[]>([]);
  const [projectID, setProjectID] = useState(currentProjectID ?? projects[0]?.id ?? '');
  const urls = useObjectURLs(files);
  const reading = useMemo(() => readListing(text), [text]);
  const s = normalise(spec);
  const plan = buildRoomPlan(s);
  const outline = roomOutline(s);
  const k = Math.min(300 / s.length, 140 / s.width);
  const x = (v: number) => 180 + v * k, z = (v: number) => 90 + v * k;
  const patch = (p: Partial<RoomSpec>) => setSpec({ ...spec, ...p });
  // New text re-reads the sizes: what the listing says replaces the figures, the rest stays as set.
  const changeText = (t: string) => { setText(t); setSpec(prev => ({ ...roomFromListing(readListing(t), prev), shape: prev.shape })); };
  const addFiles = (list: FileList | null) => {
    if (!list) return;
    const next = [...list].filter(f => f.type.startsWith('image/')).map(f => ({ name: f.name, blob: f as Blob }));
    setFiles(prev => [...prev, ...next].slice(0, 20));
  };

  const dialogRef = useModal<HTMLFormElement>(onClose);
  return (
    <div className="scrim" onClick={onClose}>
      <form className="dialog listing" role="dialog" aria-modal="true" ref={dialogRef} aria-label="Build from a listing" onClick={e => e.stopPropagation()}
        onSubmit={e => { e.preventDefault(); onCreate(name, s, projectID || undefined, text.trim(), files); }}>
        <h2>Build from a listing</h2>
        <p>Can't get to the place? Add the photos and paste the sizes from the studio's website. Check what was found, adjust it, and build the room.</p>
        <div className="stack">
          <input type="text" value={name} onChange={e => setName(e.target.value)} aria-label="Name" placeholder="Name, e.g. Studio 2" />

          <div className="listing-photos"
            onDragOver={e => e.preventDefault()} onDrop={e => { e.preventDefault(); addFiles(e.dataTransfer.files); }}>
            <div className="row-between">
              <span className="label">Photos</span>
              <label className="btn small">Add photos<input type="file" accept="image/*" multiple hidden onChange={e => { addFiles(e.target.files); e.target.value = ''; }} /></label>
            </div>
            {files.length === 0
              ? <p className="note" style={{ margin: 0 }}>Drop pictures or screenshots here. They stay on this computer for reference; type any sizes written on them below. (The iPhone app reads printed sizes out of photos for you.)</p>
              : (
                <div className="thumbs">
                  {files.map((f, i) => (
                    <span key={i} className="thumb-photo">
                      <img src={urls[i]} alt={f.name} />
                      <button type="button" aria-label={`Remove ${f.name}`} onClick={() => setFiles(files.filter((_, j) => j !== i))}>×</button>
                    </span>
                  ))}
                </div>
              )}
          </div>

          <label style={{ display: 'grid', gap: 4 }}><span className="label">Sizes and description</span>
            <textarea rows={5} value={text} onChange={e => changeText(e.target.value)} placeholder={`Paste from the website, e.g.\n${EXAMPLE}`} />
          </label>

          {text.trim() && (
            <div className="listing-found" aria-live="polite">
              <span className="label">Found in the listing</span>
              {reading.findings.length === 0 && <p className="note" style={{ margin: 0 }}>No sizes yet. Try a line like “12 x 8 m, 4 m ceiling”.</p>}
              <ul>
                {reading.findings.map((f, i) => (
                  <li key={i} className={f.kind === 'skipped' ? 'skipped' : ''}>
                    <span className="mark" aria-hidden="true">{MARK[f.kind]}</span>
                    <span><span className="t">{f.text}</span><span className="q">“{f.quote}”</span></span>
                  </li>
                ))}
              </ul>
              {reading.alternatives.length > 0 && <>
                <span className="note" style={{ margin: 0 }}>Other sizes in the listing</span>
                <div className="actions">
                  {reading.alternatives.map((a, i) => (
                    <button key={i} type="button" className="btn small" title={a.quote}
                      onClick={() => patch({ length: a.length, width: a.width, ...(a.ceiling !== undefined ? { ceiling: a.ceiling } : {}) })}>
                      Use {fmt(a.length)} × {fmt(a.width)} m
                    </button>
                  ))}
                </div>
              </>}
            </div>
          )}

          <div className="shape-row" role="group" aria-label="Shape">
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
          <p className="note" style={{ margin: 0 }}>{sizeNote(reading)}</p>
          <LengthStepper label="Length" value={spec.length} min={ROOM_LIMITS.min} max={ROOM_LIMITS.max} onChange={v => patch({ length: v })} />
          <LengthStepper label="Width" value={spec.width} min={ROOM_LIMITS.min} max={ROOM_LIMITS.max} onChange={v => patch({ width: v })} />
          <LengthStepper label="Ceiling height" note={reading.ceiling === undefined ? 'Not in the listing' : 'From the listing'} value={spec.ceiling} min={ROOM_LIMITS.ceilingMin} max={ROOM_LIMITS.ceilingMax} onChange={v => patch({ ceiling: v })} />
          <Stepper label="Windows" note={reading.windows === undefined ? 'Not in the listing' : 'From the listing'} value={spec.windows} step={1} min={0} max={4} onChange={v => patch({ windows: v })} />
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
        <p className="note">Floor area {area(roomArea(s))}. Sizes from a listing are saved as entered by hand, not as measurements. Check them on the day if you can.</p>
        <div className="actions" style={{ justifyContent: 'flex-end', marginTop: 16 }}>
          <button type="button" className="btn ghost" onClick={onClose}>Cancel</button>
          <button type="submit" className="btn primary">Build the room</button>
        </div>
      </form>
    </div>
  );
}

/** The photos kept with a location built from a listing (this browser only). */
export function ListingPhotosDialog({ locationID, onClose, onChange }: { locationID: string; onClose(): void; onChange(count: number): void }) {
  const [photos, setPhotos] = useState<ListingPhoto[]>([]);
  const [open, setOpen] = useState(0);
  useEffect(() => { void listingPhotos.forLocation(locationID).then(setPhotos).catch(() => setPhotos([])); }, [locationID]);
  const urls = useObjectURLs(photos);
  const remove = async (id: string) => {
    await listingPhotos.remove(id);
    const next = photos.filter(p => p.id !== id);
    setPhotos(next); setOpen(o => Math.min(o, Math.max(0, next.length - 1))); onChange(next.length);
  };
  const dialogRef = useModal<HTMLDivElement>(onClose);
  return (
    <div className="scrim" onClick={onClose}>
      <div className="dialog listing wide" role="dialog" aria-modal="true" ref={dialogRef} aria-label="Reference photos" onClick={e => e.stopPropagation()}>
        <h2>Reference photos</h2>
        <p>Kept in this browser with the room. They don't sync to the phone.</p>
        {photos.length === 0 ? <p className="note">No photos.</p> : <>
          <img className="photo-large" src={urls[open]} alt={photos[open]?.name} />
          <div className="thumbs">
            {photos.map((p, i) => (
              <span key={p.id} className={'thumb-photo' + (i === open ? ' on' : '')}>
                <img src={urls[i]} alt={p.name} onClick={() => setOpen(i)} />
                <button type="button" aria-label={`Remove ${p.name}`} onClick={() => void remove(p.id)}>×</button>
              </span>
            ))}
          </div>
        </>}
        <div style={{ marginTop: 16, textAlign: 'right' }}><button className="btn ghost" onClick={onClose}>Close</button></div>
      </div>
    </div>
  );
}
