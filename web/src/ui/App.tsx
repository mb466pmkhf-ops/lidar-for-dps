import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { BUILT_IN_SERVER, workspace, type SyncState } from '../sync/workspace';
import { readBackupZip } from '../sync/zip';
import { demoBundle } from '../model/demo';
import { newLocation, newProject, uuid } from '../model/factory';
import type { Location, ProjectBundle } from '../model/types';
import { buildRoom, type RoomSpec } from '../model/room';
import { Planner } from './Planner';
import { Home } from './Home';
import { RoomDialog } from './RoomDialog';
import { ListingDialog, ListingPhotosDialog, type ListingFile } from './ListingDialog';
import { listingPhotos } from '../sync/listingPhotos';
import { Icon } from './icons';

function useWorkspace() {
  return useSyncExternalStore(workspace.subscribe, workspace.getProjects);
}

function syncLabel(s: SyncState): { text: string; dot: string } {
  switch (s.kind) {
    case 'local': return { text: 'On this device only', dot: '' };
    case 'signedOut': return { text: 'Sign in to sync', dot: 'err' };
    case 'syncing': return { text: 'Syncing…', dot: 'busy' };
    case 'synced': return { text: workspace.hasPendingChanges() ? 'Saving…' : 'Synced', dot: workspace.hasPendingChanges() ? 'busy' : 'ok' };
    case 'offline': return { text: 'Offline · saved here', dot: '' };
    case 'error': return { text: 'Sync problem', dot: 'err' };
  }
}

export function App() {
  const projects = useWorkspace();
  const [projectID, setProjectID] = useState<string>();
  const [locationID, setLocationID] = useState<string>();
  const [syncOpen, setSyncOpen] = useState(false);
  const [drawer, setDrawer] = useState(false);
  const [message, setMessage] = useState<string>();
  const fileInput = useRef<HTMLInputElement>(null);
  const [view, setView] = useState<'home' | 'plan'>('home');
  const [drawOpen, setDrawOpen] = useState(false);
  const [listingOpen, setListingOpen] = useState(false);
  const [photosOpen, setPhotosOpen] = useState(false);
  const [photoCount, setPhotoCount] = useState(0);
  const [last, setLast] = useState<{ projectID: string; locationID: string } | undefined>(() => {
    try { const [a, b] = (localStorage.getItem('framescan.last') ?? '').split('/'); return a && b ? { projectID: a, locationID: b } : undefined; } catch { return undefined; }
  });
  // Night mode: a dim, near-black screen for a dark set. Remembered on this device.
  const [night, setNight] = useState(() => { try { return localStorage.getItem('framescan.theme') === 'night'; } catch { return false; } });
  useEffect(() => {
    document.documentElement.dataset.theme = night ? 'night' : 'day';
    try { localStorage.setItem('framescan.theme', night ? 'night' : 'day'); } catch { /* private mode */ }
  }, [night]);

  const openLocation = (pid: string, lid: string) => {
    setProjectID(pid); setLocationID(lid); setView('plan'); setDrawer(false);
    setLast({ projectID: pid, locationID: lid });
    try { localStorage.setItem('framescan.last', `${pid}/${lid}`); } catch { /* private mode */ }
  };

  const [authError, setAuthError] = useState<string>();
  useEffect(() => {
    void workspace.load()
      .then(() => workspace.completeRedirect())
      .catch(e => { setAuthError(e instanceof Error ? e.message : String(e)); setSyncOpen(true); });
  }, []);

  // Keep a valid selection as projects arrive or disappear.
  useEffect(() => {
    if (!workspace.loaded) return;
    const p = projects.find(x => x.id === projectID) ?? projects.find(x => x.locations.length) ?? projects[0];
    if (p?.id !== projectID) setProjectID(p?.id);
    const l = p?.locations.find(x => x.id === locationID) ?? p?.locations[0];
    if (l?.id !== locationID) setLocationID(l?.id);
  }, [projects, projectID, locationID]);

  useEffect(() => {
    if (!locationID) { setPhotoCount(0); return; }
    let live = true;
    listingPhotos.forLocation(locationID).then(p => { if (live) setPhotoCount(p.length); }).catch(() => { if (live) setPhotoCount(0); });
    return () => { live = false; };
  }, [locationID]);

  const project = projects.find(p => p.id === projectID);
  const location = project?.locations.find(l => l.id === locationID);
  const bundle = projectID ? workspace.bundle(projectID) : undefined;
  const sync = syncLabel(workspace.state);

  const addDemo = () => { const b = demoBundle(); workspace.add(b); openLocation(b.project.id, b.project.locations[0].id); };
  // Photos stay in this browser, keyed by location; the listing text goes in the location's notes, which sync.
  const createFromListing = (name: string, spec: RoomSpec, intoProject: string | undefined, listing: string, photos: ListingFile[]) => {
    const loc = createRoom(name, spec, intoProject, l => {
      if (listing) l.notes = `From the listing:\n${listing}`;
      const scan = l.scans[l.scans.length - 1];
      if (scan) scan.notes = 'Built from a listing. Sizes were copied from the listing, not measured.';
    });
    setListingOpen(false);
    if (photos.length) void listingPhotos.add(loc.id, photos).then(() => setPhotoCount(photos.length)).catch(e => setMessage(`Couldn't keep the photos: ${e instanceof Error ? e.message : String(e)}`));
  };
  const createRoom = (name: string, spec: RoomSpec, intoProject: string | undefined, adjust?: (l: Location) => void) => {
    const { location: loc, scanID: sid, plan } = buildRoom(name, spec);
    adjust?.(loc);
    const target = intoProject ? workspace.bundle(intoProject) : undefined;
    if (target) {
      workspace.commitBundle({ project: { ...target.project, locations: [...target.project.locations, loc] }, plans: { ...target.plans, [sid]: plan } });
      openLocation(target.project.id, loc.id);
    } else {
      const p = newProject('My rooms');
      p.locations = [loc];
      workspace.add({ project: p, plans: { [sid]: plan } });
      openLocation(p.id, loc.id);
    }
    setDrawOpen(false);
    return loc;
  };
  const addProject = () => {
    const name = prompt('Project name', 'New project');
    if (!name) return;
    const p = newProject(name.trim() || 'Untitled Project');
    const loc = newLocation('Location 1');
    p.locations = [loc];
    workspace.add({ project: p, plans: {} });
    setProjectID(p.id); setLocationID(loc.id);
  };
  const addLocation = () => {
    if (!project) return;
    const name = prompt('Location name', `Location ${project.locations.length + 1}`);
    if (!name) return;
    const loc = newLocation(name.trim() || 'New Location');
    workspace.commit({ ...project, locations: [...project.locations, loc] });
    setLocationID(loc.id);
  };

  const importFile = async (file: File) => {
    try {
      let b: ProjectBundle;
      if (/\.zip$/i.test(file.name)) b = await readBackupZip(file);
      else {
        const j = JSON.parse(await file.text());
        b = j.project ? j : { project: j, plans: {} };
      }
      if (!b.project?.locations) throw new Error('That file is not a FrameScan project.');
      if (projects.some(p => p.id === b.project.id)) {
        if (!confirm(`"${b.project.name}" is already here. Import it as a copy?`)) return;
        b = { ...b, project: { ...b.project, id: uuid(), name: b.project.name + ' (Imported)' } };
      }
      workspace.add(b);
      setProjectID(b.project.id); setLocationID(b.project.locations[0]?.id); setView('plan');
      setMessage(`Imported ${b.project.name}.`);
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    }
  };

  const exportBundle = () => {
    if (!bundle) return;
    const blob = new Blob([JSON.stringify(bundle, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `${bundle.project.name.replace(/[^\w\- ]+/g, '')}.framescan.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  };

  const removeProject = () => {
    if (!project || !confirm(`Delete "${project.name}" on every synced device? Scans on the phone are deleted too.`)) return;
    workspace.remove(project.id);
  };

  return (
    <div className="app">
      <header className="topbar">
        {view === 'plan' && <button className="btn ghost small menu-btn" onClick={() => setDrawer(!drawer)} aria-label="Projects"><Icon name="menu" /></button>}
        {view === 'plan'
          ? <button className="btn small" onClick={() => setView('home')}><Icon name="home" /> Home</button>
          : <span className="brand">FrameScan</span>}
        <span className="crumbs">{view === 'plan' && project ? `${project.name}${location ? ' — ' + location.name : ''}` : ''}</span>
        {view === 'plan' && location && photoCount > 0 && (
          <button className="btn small" onClick={() => setPhotosOpen(true)} title="Photos added with the listing (this browser only)">Photos ({photoCount})</button>
        )}
        <button className="btn small" aria-pressed={night} onClick={() => setNight(!night)} title={night ? 'Back to the bright screen' : 'Dim, dark screen for a dark set'}>
          <Icon name={night ? 'sun' : 'moon'} /> <span className="txt">{night ? 'Day' : 'Night'}</span>
        </button>
        <button className="sync" onClick={() => setSyncOpen(true)} title={workspace.state.kind === 'error' ? workspace.state.message : 'Sync settings'}>
          <span className={'dot ' + sync.dot} /> {sync.text}
        </button>
      </header>
      {view === 'home' ? (
        <>
          <Home projects={projects} plansFor={id => workspace.bundle(id)?.plans} last={last} loaded={workspace.loaded}
            synced={!!workspace.client?.session} onOpen={openLocation} onDraw={() => setDrawOpen(true)} onListing={() => setListingOpen(true)}
            onImport={() => fileInput.current?.click()} onSync={() => setSyncOpen(true)} onDemo={addDemo} />
          <input ref={fileInput} type="file" accept=".zip,.json" hidden onChange={e => { const f = e.target.files?.[0]; if (f) void importFile(f); e.target.value = ''; }} />
        </>
      ) : (
      <div className={'main' + (location ? '' : ' no-inspector')}>
        <nav className={'sidebar' + (drawer ? ' open' : '')} aria-label="Projects">
          <div className="side-h"><span className="label">Projects</span><button className="btn small" onClick={addProject} title="New project"><Icon name="plus" /></button></div>
          {projects.map(p => (
            <div key={p.id}>
              <button className={'row' + (p.id === projectID && !locationID ? ' on' : '')} onClick={() => { setProjectID(p.id); setLocationID(p.locations[0]?.id); }}>
                <span className="t">{p.name}</span>
                <span className="s">{p.locations.length} location{p.locations.length === 1 ? '' : 's'}{p.client ? ' · ' + p.client : ''}</span>
              </button>
              {p.id === projectID && p.locations.map(l => (
                <button key={l.id} className={'row indent' + (l.id === locationID ? ' on' : '')} onClick={() => openLocation(p.id, l.id)}>
                  <span className="t">{l.name}</span>
                  <span className="s">{(l.lights ?? []).length} lights · {!l.scans.length ? 'no scan' : l.scans.every(x => x.name === 'Drawn by hand') ? 'drawn by hand' : 'scanned'}</span>
                </button>
              ))}
              {p.id === projectID && <button className="row indent faint" onClick={addLocation}>+ Add location</button>}
              {p.id === projectID && <button className="row indent faint" onClick={() => setDrawOpen(true)}>+ Draw a room</button>}
              {p.id === projectID && <button className="row indent faint" onClick={() => setListingOpen(true)}>+ From a listing</button>}
            </div>
          ))}
          <div className="panel" style={{ borderBottom: 0 }}>
            <div className="actions">
              <button className="btn small" onClick={() => fileInput.current?.click()} title="Open a project backup ZIP from the phone, or a .framescan.json file"><Icon name="upload" /> Open file</button>
              {bundle && <button className="btn small" onClick={exportBundle}><Icon name="download" /> Save copy</button>}
              {project && <button className="btn small danger" onClick={removeProject}><Icon name="trash" /> Delete</button>}
            </div>
            <input ref={fileInput} type="file" accept=".zip,.json" hidden onChange={e => { const f = e.target.files?.[0]; if (f) void importFile(f); e.target.value = ''; }} />
            {message && <p className="note">{message}</p>}
          </div>
        </nav>
        {project && location && bundle ? (
          <Planner key={location.id} project={project} location={location} plans={bundle.plans} commit={p => workspace.commit(p)} commitPlan={(sid, plan) => workspace.commitPlan(project.id, sid, plan)} />
        ) : (
          <div className="empty">
            <div>
              <h2>{workspace.loaded ? (projects.length ? 'Pick a location' : 'Plan your lighting') : 'Loading…'}</h2>
              {workspace.loaded && !projects.length && (
                <>
                  <p>Continue a lighting plan from the FrameScan app on your iPhone, or start here.</p>
                  <div className="actions" style={{ justifyContent: 'center' }}>
                    <button className="btn primary" onClick={() => setSyncOpen(true)}><Icon name="cloud" /> Sync with my iPhone</button>
                    <button className="btn" onClick={addDemo}>Try the sample room</button>
                    <button className="btn" onClick={() => fileInput.current?.click()}>Open a backup</button>
                  </div>
                </>
              )}
            </div>
          </div>
        )}
      </div>
      )}
      {drawOpen && <RoomDialog projects={projects} currentProjectID={projectID} onCreate={(n, sp, pid) => { createRoom(n, sp, pid); }} onClose={() => setDrawOpen(false)} />}
      {listingOpen && <ListingDialog projects={projects} currentProjectID={projectID} onCreate={createFromListing} onClose={() => setListingOpen(false)} />}
      {photosOpen && locationID && <ListingPhotosDialog locationID={locationID} onChange={setPhotoCount} onClose={() => setPhotosOpen(false)} />}
      {syncOpen && <SyncDialog initialError={authError} onClose={() => { setSyncOpen(false); setAuthError(undefined); }} />}
    </div>
  );
}

const MIN_PASSWORD = 8;

function SyncDialog({ onClose, initialError }: { onClose(): void; initialError?: string }) {
  const client = workspace.client;
  const [url, setUrl] = useState(client?.config.url ?? '');
  const [key, setKey] = useState(client?.config.anonKey ?? '');
  const [mode, setMode] = useState<'signIn' | 'create'>('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [code, setCode] = useState('');
  const [pending, setPending] = useState<string>();   // address waiting for its confirmation email
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | undefined>(initialError);
  const [notice, setNotice] = useState<string>();
  const [editServer, setEditServer] = useState(!client);
  useWorkspace();

  const run = async (fn: () => Promise<void>) => {
    setBusy(true); setError(undefined);
    try { await fn(); } catch (e) { setError(e instanceof Error ? e.message : String(e)); } finally { setBusy(false); }
  };

  const address = email.trim();
  const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address);
  const passwordProblem = password.length < MIN_PASSWORD ? `At least ${MIN_PASSWORD} characters.`
    : !confirm ? 'Type the password again to confirm it.'
    : confirm !== password ? "The passwords don't match." : undefined;

  const signIn = () => run(async () => { await workspace.signIn(address, password); setPassword(''); });
  const create = () => run(async () => {
    const r = await workspace.createAccount(address, password);
    setPassword(''); setConfirm('');
    if (r === 'confirm') { setPending(address); setCode(''); }
  });
  const switchMode = (m: 'signIn' | 'create') => { setMode(m); setConfirm(''); setError(undefined); };

  const session = workspace.client?.session;
  return (
    <div className="scrim" onClick={onClose}>
      <div className="dialog" role="dialog" aria-modal="true" aria-label="Account and sync" onClick={e => e.stopPropagation()}>
        <h2>Account &amp; sync</h2>
        <p>Keeps the lighting plan the same on your iPhone, this browser and the desktop app. Scan meshes and photos stay on the phone; only the plan, lights, people, meters and the 2D floor plan sync.</p>
        {session && !editServer ? (
          <>
            <p>Signed in as <strong>{session.email}</strong>. {workspace.state.kind === 'synced' ? 'Everything is up to date.' : workspace.state.kind === 'error' ? workspace.state.message : ''}</p>
            <div className="actions">
              <button className="btn primary" disabled={busy} onClick={() => run(() => workspace.sync())}>Sync now</button>
              <button className="btn" onClick={() => workspace.signOut()}>Sign out</button>
              <button className="btn ghost" onClick={() => setEditServer(true)}>Server…</button>
            </div>
          </>
        ) : editServer ? (
          <>
            <ol>
              <li>Only needed for your own server. Create a free project at supabase.com.</li>
              <li>In its SQL editor, run <span className="mono">web/supabase/schema.sql</span> from the repository.</li>
              <li>Paste the Project URL and the anon (public) key from Project Settings → API. Use the same two values on the phone.</li>
            </ol>
            <div className="stack">
              <input type="text" placeholder="https://xxxx.supabase.co" value={url} onChange={e => setUrl(e.target.value)} aria-label="Project URL" />
              <input type="text" placeholder="anon public key" value={key} onChange={e => setKey(e.target.value)} aria-label="Anon key" />
            </div>
            <div className="actions">
              <button className="btn primary" disabled={!url || !key} onClick={() => { workspace.connect({ url: url.trim(), anonKey: key.trim() }); setEditServer(false); }}>Save</button>
              <button className="btn" onClick={() => { workspace.connect(BUILT_IN_SERVER); setUrl(BUILT_IN_SERVER.url); setKey(BUILT_IN_SERVER.anonKey); setEditServer(false); }}>Use FrameScan server</button>
              {client && <button className="btn danger" onClick={() => { workspace.disconnect(); }}>Stop syncing</button>}
              {client && <button className="btn ghost" onClick={() => setEditServer(false)}>Back</button>}
            </div>
          </>
        ) : pending ? (
          <>
            <h3 className="auth-h">Confirm your email</h3>
            <p>We sent an email to <strong>{pending}</strong>. Click the link in it, or type the code from it here.</p>
            <div className="stack">
              <input type="text" inputMode="numeric" autoComplete="one-time-code" placeholder="Code from the email" value={code}
                onChange={e => setCode(e.target.value)} aria-label="Code from the email"
                onKeyDown={e => { if (e.key === 'Enter') void run(async () => { await workspace.verifyEmail(pending, code); setPending(undefined); }); }} />
            </div>
            <div className="actions">
              <button className="btn primary" disabled={busy || code.replace(/\D/g, '').length < 6}
                onClick={() => run(async () => { await workspace.verifyEmail(pending, code); setPending(undefined); setNotice(undefined); })}>Confirm</button>
              <button className="btn" onClick={() => { setEmail(pending); setPending(undefined); setMode('signIn'); setNotice(undefined); }}>I clicked the link — sign in</button>
              <button className="btn ghost" disabled={busy} onClick={() => run(async () => { await workspace.resendConfirmation(pending); setNotice('Sent. Use the code from the newest email.'); })}>Send again</button>
            </div>
            <p className="note"><button className="linkish" onClick={() => { setPending(undefined); setNotice(undefined); }}>Use another email</button></p>
          </>
        ) : (
          <>
            <div className="auth-providers">
              <button className="btn provider apple" disabled={busy} onClick={() => run(() => workspace.signInWith('apple'))}>
                Continue with Apple
              </button>
              <button className="btn provider" disabled={busy} onClick={() => run(() => workspace.signInWith('google'))}>
                <span className="g" aria-hidden="true">G</span>
                Continue with Google
              </button>
            </div>
            <div className="auth-or"><span>or use email</span></div>
            <div className="segmented" role="tablist" aria-label="Email account">
              <button role="tab" aria-selected={mode === 'signIn'} className={mode === 'signIn' ? 'on' : ''} onClick={() => switchMode('signIn')}>Sign in</button>
              <button role="tab" aria-selected={mode === 'create'} className={mode === 'create' ? 'on' : ''} onClick={() => switchMode('create')}>Create account</button>
            </div>
            <div className="stack">
              <input type="email" placeholder="Email" autoComplete="email" value={email} onChange={e => setEmail(e.target.value)} aria-label="Email" />
              <input type="password" placeholder="Password" autoComplete={mode === 'create' ? 'new-password' : 'current-password'} value={password}
                onChange={e => setPassword(e.target.value)} aria-label="Password"
                onKeyDown={e => { if (e.key === 'Enter' && mode === 'signIn' && validEmail && password) void signIn(); }} />
              {mode === 'create' && (
                <input type="password" placeholder="Confirm password" autoComplete="new-password" value={confirm}
                  onChange={e => setConfirm(e.target.value)} aria-label="Confirm password"
                  onKeyDown={e => { if (e.key === 'Enter' && validEmail && !passwordProblem) void create(); }} />
              )}
            </div>
            {mode === 'create' && passwordProblem && (password || confirm) && <p className="note">{passwordProblem}</p>}
            <div className="actions">
              {mode === 'signIn'
                ? <button className="btn primary" disabled={busy || !validEmail || !password} onClick={signIn}>Sign in</button>
                : <button className="btn primary" disabled={busy || !validEmail || !!passwordProblem} onClick={create}>Create account</button>}
              <button className="btn ghost" onClick={() => setEditServer(true)}>Server…</button>
            </div>
            <p className="note">{mode === 'create' ? "We'll email you to confirm the address before the account can sync. " : ''}Use the same account in the iPhone app (Home → Sign in to sync).</p>
          </>
        )}
        {notice && <p className="note">{notice}</p>}
        {error && <p className="error">{error}</p>}
        <div style={{ marginTop: 16, textAlign: 'right' }}><button className="btn ghost" onClick={onClose}>Close</button></div>
      </div>
    </div>
  );
}
