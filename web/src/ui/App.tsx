import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { BUILT_IN_SERVER, workspace, type SyncState } from '../sync/workspace';
import { readBackupZip } from '../sync/zip';
import { demoBundle } from '../model/demo';
import { newLocation, newProject, uuid } from '../model/factory';
import type { ProjectBundle } from '../model/types';
import { Planner } from './Planner';
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

  useEffect(() => { void workspace.load(); }, []);

  // Keep a valid selection as projects arrive or disappear.
  useEffect(() => {
    if (!workspace.loaded) return;
    const p = projects.find(x => x.id === projectID) ?? projects.find(x => x.locations.length) ?? projects[0];
    if (p?.id !== projectID) setProjectID(p?.id);
    const l = p?.locations.find(x => x.id === locationID) ?? p?.locations[0];
    if (l?.id !== locationID) setLocationID(l?.id);
  }, [projects, projectID, locationID]);

  const project = projects.find(p => p.id === projectID);
  const location = project?.locations.find(l => l.id === locationID);
  const bundle = projectID ? workspace.bundle(projectID) : undefined;
  const sync = syncLabel(workspace.state);

  const addDemo = () => { const b = demoBundle(); workspace.add(b); setProjectID(b.project.id); setLocationID(b.project.locations[0].id); };
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
      setProjectID(b.project.id); setLocationID(b.project.locations[0]?.id);
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
        <button className="btn ghost small menu-btn" onClick={() => setDrawer(!drawer)} aria-label="Projects"><Icon name="menu" /></button>
        <span className="brand">FrameScan</span>
        <span className="crumbs">{project ? `${project.name}${location ? ' — ' + location.name : ''}` : 'Lighting planner'}</span>
        <button className="sync" onClick={() => setSyncOpen(true)} title={workspace.state.kind === 'error' ? workspace.state.message : 'Sync settings'}>
          <span className={'dot ' + sync.dot} /> {sync.text}
        </button>
      </header>
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
                <button key={l.id} className={'row indent' + (l.id === locationID ? ' on' : '')} onClick={() => { setLocationID(l.id); setDrawer(false); }}>
                  <span className="t">{l.name}</span>
                  <span className="s">{(l.lights ?? []).length} lights · {l.scans.length ? 'scanned' : 'no scan'}</span>
                </button>
              ))}
              {p.id === projectID && <button className="row indent faint" onClick={addLocation}>+ Add location</button>}
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
          <Planner key={location.id} project={project} location={location} plans={bundle.plans} commit={p => workspace.commit(p)} />
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
      {syncOpen && <SyncDialog onClose={() => setSyncOpen(false)} />}
    </div>
  );
}

function SyncDialog({ onClose }: { onClose(): void }) {
  const client = workspace.client;
  const [url, setUrl] = useState(client?.config.url ?? '');
  const [key, setKey] = useState(client?.config.anonKey ?? '');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [editServer, setEditServer] = useState(!client);
  useWorkspace();

  const run = async (fn: () => Promise<void>) => {
    setBusy(true); setError(undefined);
    try { await fn(); } catch (e) { setError(e instanceof Error ? e.message : String(e)); } finally { setBusy(false); }
  };

  const session = workspace.client?.session;
  return (
    <div className="scrim" onClick={onClose}>
      <div className="dialog" role="dialog" aria-modal="true" aria-label="Sync" onClick={e => e.stopPropagation()}>
        <h2>Sync</h2>
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
            </div>
          </>
        ) : (
          <>
            <div className="stack">
              <input type="email" placeholder="Email" autoComplete="email" value={email} onChange={e => setEmail(e.target.value)} aria-label="Email" />
              <input type="password" placeholder="Password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} aria-label="Password"
                onKeyDown={e => { if (e.key === 'Enter') void run(() => workspace.signIn(email, password, false)); }} />
            </div>
            <div className="actions">
              <button className="btn primary" disabled={busy || !email || !password} onClick={() => run(() => workspace.signIn(email, password, false))}>Sign in</button>
              <button className="btn" disabled={busy || !email || password.length < 6} onClick={() => run(() => workspace.signIn(email, password, true))}>Create account</button>
              <button className="btn ghost" onClick={() => setEditServer(true)}>Server…</button>
            </div>
            <p className="note">Use the same account in the iPhone app (Home → ⋯ → Sync with web &amp; desktop…).</p>
          </>
        )}
        {error && <p className="error">{error}</p>}
        <div style={{ marginTop: 16, textAlign: 'right' }}><button className="btn ghost" onClick={onClose}>Close</button></div>
      </div>
    </div>
  );
}
