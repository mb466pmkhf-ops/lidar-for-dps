# FrameScan Planner — web and desktop

Continue a FrameScan lighting plan from the iPhone on a computer: move and aim lights, change fixtures,
modifiers, gels and output, place people and meters, set the camera exposure and read the estimated lux and
stops. Everything syncs back to the phone. See `Docs/DECISIONS.md` D-007 for what syncs and why.

## Use it

- **Web**: published to GitHub Pages from the default branch (Settings → Pages → Source: GitHub Actions),
  or run it locally: `cd web && npm install && npm run dev`, then open http://localhost:5173.
- **Desktop**: download *FrameScan-Planner-macOS* (or *-Windows*) from the latest “Web & desktop planner”
  Actions run. The builds aren't signed: on a Mac, right-click the app → Open the first time.
- Without sync it works on its own (projects are kept in the browser / app). *Open file* reads a project
  backup ZIP exported from the phone.

## Sync

Sync is preset to FrameScan's own Supabase project (`nuprvuipspqmhsczdqrk`, region eu-west-2, schema from
[`supabase/schema.sql`](supabase/schema.sql)). Create an account on one device and sign in with it on the
others: web/desktop → *Sync* (top right); iPhone → Home → ⋯ → *Sync with web & desktop…*.

The URL and anon key are in `src/sync/workspace.ts` (`BUILT_IN_SERVER`) and `CloudSync.builtIn` on iOS. The
anon key is public by design; the data is protected by the row-level security in `schema.sql`. Build-time
variables `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` (repository variables `SUPABASE_URL` /
`SUPABASE_ANON_KEY` in CI) override it.

To use your own server instead: create a free project at <https://supabase.com>, run `schema.sql` in its SQL
editor, keep *Confirm email* on (Authentication → Providers → Email) so nobody can sign up with an address
that isn't theirs, then enter the Project URL
and anon key under *Sync → Server…* on each device.

## Develop

```
npm install
npm run dev        # web, hot reload
npm test           # lighting maths, merge rules, Swift parity (parity needs CI or PARITY_READINGS)
npm run tauri dev  # desktop window (needs Rust)
```

`src/model` is the port of the Swift core (keep it in step with `FrameScout/Core/Models`), `src/sync` is
storage, the Supabase client and the merge, `src/ui` is the planner.
