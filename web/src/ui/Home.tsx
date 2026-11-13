// The first screen is your work: every room, newest first, with the ways to start a new one as
// plain buttons above it (Docs/LOOK.md). No tile grid, no banner.
import type { FloorPlan, Location, Project } from '../model/types';
import { Icon } from './icons';
import { roomSize } from './format';

export interface HomeProps {
  projects: Project[];
  plansFor(projectID: string): Record<string, FloorPlan> | undefined;
  last?: { projectID: string; locationID: string };
  loaded: boolean;
  synced: boolean;
  onOpen(projectID: string, locationID: string): void;
  onDraw(): void;
  onListing(): void;
  onImport(): void;
  onSync(): void;
  onDemo(): void;
}

function planOf(l: Location, plans?: Record<string, FloorPlan>) {
  const id = l.primaryScanID ?? l.scans[l.scans.length - 1]?.id;
  return id && plans ? plans[id.toUpperCase()] ?? plans[id] ?? plans[id.toLowerCase()] : undefined;
}

function Thumb({ plan }: { plan?: FloorPlan }) {
  if (!plan || !plan.walls.length) return <span className="thumb" aria-hidden="true" />;
  const b = plan.bounds, w = b.maxX - b.minX || 1, d = b.maxZ - b.minZ || 1;
  const k = 56 / Math.max(w, d), ox = 38 - (w * k) / 2, oz = 38 - (d * k) / 2;
  const x = (v: number) => ox + (v - b.minX) * k, z = (v: number) => oz + (v - b.minZ) * k;
  return (
    <svg className="thumb" viewBox="0 0 76 76" aria-hidden="true">
      {plan.walls.map(s => <line key={s.id} x1={x(s.a.x)} y1={z(s.a.z)} x2={x(s.b.x)} y2={z(s.b.z)} stroke="var(--wall)" strokeWidth={2.5} strokeLinecap="square" />)}
      {plan.windows.map(s => <line key={s.id} x1={x(s.a.x)} y1={z(s.a.z)} x2={x(s.b.x)} y2={z(s.b.z)} stroke="var(--accent)" strokeWidth={2.5} />)}
    </svg>
  );
}

function edited(iso?: string) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const days = Math.floor((Date.now() - d.getTime()) / 86_400_000);
  if (days < 1) return 'Today';
  if (days < 2) return 'Yesterday';
  if (days < 7) return `${days} days ago`;
  return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: d.getFullYear() === new Date().getFullYear() ? undefined : 'numeric' });
}

export function Home(p: HomeProps) {
  const all = p.projects.flatMap(pr => pr.locations.map(l => ({ pr, l })));
  const lastHit = p.last && all.find(x => x.pr.id === p.last!.projectID && x.l.id === p.last!.locationID);
  // Most recently edited first; the sync layer stamps modifiedAt on every change. The room you had
  // open last goes to the top whatever its date.
  const rooms = [...all].sort((a, b) => (b.pr.modifiedAt ?? '').localeCompare(a.pr.modifiedAt ?? ''));
  if (lastHit) rooms.splice(0, rooms.length, lastHit, ...rooms.filter(x => x !== lastHit));
  return (
    <main className="home">
      <div className="home-inner">
        <div className="home-head">
          <h1>Rooms</h1>
          <div className="actions">
            <button className="btn primary" onClick={p.onDraw}><Icon name="pencil" /> Draw a room</button>
            <button className="btn" onClick={p.onListing}><Icon name="upload" /> From a listing</button>
            <button className="btn" onClick={p.onImport}><Icon name="download" /> Open a file</button>
          </div>
        </div>
        {!p.loaded ? <p className="muted">Loading…</p> : rooms.length === 0 ? (
          <section className="home-empty">
            <p>No rooms yet. Draw one, build one from a studio listing, or open the sample to see how a lit set reads.</p>
            <div className="actions"><button className="btn" onClick={p.onDemo}><Icon name="planmap" /> Open the sample room</button></div>
          </section>
        ) : (
          <ul className="room-list">
            {rooms.map(({ pr, l }) => {
              const s = l.scans.find(x => x.id === l.primaryScanID) ?? l.scans[l.scans.length - 1];
              const lights = (l.lights ?? []).length;
              return (
                <li key={l.id}>
                  <button className="room-row" onClick={() => p.onOpen(pr.id, l.id)}>
                    <Thumb plan={planOf(l, p.plansFor(pr.id))} />
                    <span className="room-name"><span className="t">{l.name}</span><span className="s">{pr.name}{pr.client ? ' · ' + pr.client : ''}</span></span>
                    <span className="room-fig mono">{s?.stats.width && s.stats.length ? roomSize(s.stats.width, s.stats.length) : '—'}</span>
                    <span className="room-fig">{l.shots.length} shot{l.shots.length === 1 ? '' : 's'}</span>
                    <span className="room-fig">{lights} light{lights === 1 ? '' : 's'}</span>
                    <span className="room-fig faint">{edited(pr.modifiedAt)}</span>
                  </button>
                </li>
              );
            })}
          </ul>
        )}
        <p className="home-foot">
          Scanning, measuring and the viewfinder are in the iPhone app.{' '}
          {p.synced ? 'You\'re signed in, so rooms you scan there show up here.' : <>
            <button className="linkish" onClick={p.onSync}>Sign in</button> on both and rooms you scan show up here.</>}
        </p>
      </div>
    </main>
  );
}
