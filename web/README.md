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

## Turn on sync (once, about five minutes)

1. Create a free project at <https://supabase.com>.
2. In its **SQL editor**, paste and run [`supabase/schema.sql`](supabase/schema.sql).
3. Optional: in **Authentication → Providers → Email**, turn off *Confirm email* so a new account can sign in
   straight away (otherwise click the link in the confirmation email first).
4. From **Project Settings → API**, copy the *Project URL* and the *anon public* key.
5. Enter both on each device: web/desktop → *Sync* (top right) → *Server…*; iPhone → Home → ⋯ →
   *Sync with web & desktop…* → *Server…*. Then create an account on one device and sign in on the others.

To bake the server into the hosted web app and desktop builds, add repository variables `SUPABASE_URL` and
`SUPABASE_ANON_KEY` (Settings → Secrets and variables → Actions → Variables). The anon key is public by
design; the data is protected by the row-level security in `schema.sql`.

## Develop

```
npm install
npm run dev        # web, hot reload
npm test           # lighting maths, merge rules, Swift parity (parity needs CI or PARITY_READINGS)
npm run tauri dev  # desktop window (needs Rust)
```

`src/model` is the port of the Swift core (keep it in step with `FrameScout/Core/Models`), `src/sync` is
storage, the Supabase client and the merge, `src/ui` is the planner.
