// The first screen: a few big, labelled things to do, then the rooms worked on most recently.
import type { FloorPlan, Location, Project } from '../model/types';
import { Icon } from './icons';

export interface HomeProps {
  projects: Project[];
  plansFor(projectID: string): Record<string, FloorPlan> | undefined;
  last?: { projectID: string; locationID: string };
  loaded: boolean;
  synced: boolean;
  onOpen(projectID: string, locationID: string): void;
  onDraw(): void;
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

function summary(l: Location) {
  const s = l.scans.find(x => x.id === l.primaryScanID) ?? l.scans[l.scans.length - 1];
  const parts: string[] = [];
  if (s?.stats.width && s.stats.length) parts.push(`${s.stats.width.toFixed(1)} × ${s.stats.length.toFixed(1)} m`);
  const lights = (l.lights ?? []).length;
  parts.push(`${l.shots.length} shot${l.shots.length === 1 ? '' : 's'}`, `${lights} light${lights === 1 ? '' : 's'}`);
  return parts.join(' · ');
}

export function Home(p: HomeProps) {
  const all = p.projects.flatMap(pr => pr.locations.map(l => ({ pr, l })));
  const lastHit = p.last && all.find(x => x.pr.id === p.last!.projectID && x.l.id === p.last!.locationID);
  const cont = lastHit ?? all[0];
  // Most recently edited projects first; the sync layer stamps modifiedAt on every change.
  const recent = [...all].sort((a, b) => (b.pr.modifiedAt ?? '').localeCompare(a.pr.modifiedAt ?? '')).slice(0, 6);
  return (
    <main className="home">
      <div className="home-inner">
        <h1>What do you want to do?</h1>
        <div className="tiles">
          {cont ? (
            <button className="tile primary" onClick={() => p.onOpen(cont.pr.id, cont.l.id)}>
              <Icon name="planmap" />
              <span><span className="t">Continue last plan</span><span className="s">{cont.l.name}</span></span>
            </button>
          ) : (
            <button className="tile primary" onClick={p.onDemo}>
              <Icon name="planmap" />
              <span><span className="t">Try the sample room</span><span className="s">A lit living room to play with</span></span>
            </button>
          )}
          <button className="tile" onClick={p.onDraw}>
            <Icon name="pencil" />
            <span><span className="t">Draw a room</span><span className="s">Pick a shape, type the sizes, get 2D and 3D</span></span>
          </button>
          <button className="tile" onClick={p.onImport}>
            <Icon name="download" />
            <span><span className="t">Open a file</span><span className="s">A project backup from the phone, or a saved copy</span></span>
          </button>
          <button className="tile" onClick={p.onSync}>
            <Icon name="phone" />
            <span><span className="t">{p.synced ? 'iPhone sync' : 'Sync with my iPhone'}</span><span className="s">{p.synced ? 'Signed in. Rooms you scan appear here.' : 'Sign in once and scans appear here'}</span></span>
          </button>
        </div>
        <div className="banner"><Icon name="phone" /><span>Scanning, measuring and the viewfinder need the iPhone app. Anything you scan there shows up here by itself once sync is on.</span></div>
        {p.loaded && recent.length > 0 && (
          <section style={{ display: 'grid', gap: 14 }}>
            <h2>Recent locations</h2>
            <div className="recent">
              {recent.map(({ pr, l }) => (
                <button key={l.id} className="recent-card" onClick={() => p.onOpen(pr.id, l.id)}>
                  <Thumb plan={planOf(l, p.plansFor(pr.id))} />
                  <span><span className="t">{l.name}</span><span className="s">{summary(l)}</span><span className="s">{pr.name}</span></span>
                </button>
              ))}
            </div>
          </section>
        )}
      </div>
    </main>
  );
}
