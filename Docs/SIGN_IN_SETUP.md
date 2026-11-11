# Sign-in setup (Supabase, Google, Apple)

The apps already have the buttons and the code. These steps switch the providers on for the FrameScan
Supabase project (`framescan`, ref `nuprvuipspqmhsczdqrk`). They need the owner's accounts, so they
are done by hand in the dashboards. Until a provider is switched on, its button says so in plain words.

## 1. Supabase: email confirmation and redirect addresses (free, ~5 min)

Dashboard → project **framescan** → **Authentication**.

1. **Sign In / Providers → Email**: turn **Confirm email** on. Set **Minimum password length** to 8.
   Optional but recommended: turn on **Leaked password protection**.
2. **URL Configuration**
   - **Site URL**: `https://mb466pmkhf-ops.github.io/lidar-for-dps/` (the web planner, once GitHub Pages
     is on). The link in the confirmation email lands here.
   - **Redirect URLs**, add each of these:
     - `framescan://auth-callback` (iPhone)
     - `http://127.0.0.1:53682/auth-callback`, `http://127.0.0.1:53683/auth-callback`,
       `http://127.0.0.1:53684/auth-callback` (desktop app)
     - `https://mb466pmkhf-ops.github.io/lidar-for-dps/` (web planner)
     - `http://localhost:5173/` (only for local development)
3. **Emails → Confirm signup** template: add the code so people can type it in the app instead of
   tapping the link, for example:
   `<p>Or type this code in FrameScan: <strong>{{ .Token }}</strong></p>`
4. **Emails → SMTP Settings**: Supabase's built-in mailer only sends a few emails an hour and only to
   addresses in your Supabase team. For anyone else to get the confirmation email, add your own SMTP
   (Resend, Postmark, Brevo… several have free tiers).

## 2. Google (free, ~10 min)

1. <https://console.cloud.google.com> → create (or pick) a project.
2. **APIs & Services → OAuth consent screen** (Google Auth Platform → Branding/Audience): External,
   app name *FrameScan*, your support email. Add yourself as a test user, or publish the app.
3. **Credentials → Create credentials → OAuth client ID → Web application**.
   **Authorized redirect URIs**: `https://nuprvuipspqmhsczdqrk.supabase.co/auth/v1/callback`
4. Copy the **Client ID** and **Client secret** into Supabase → Authentication → Sign In / Providers →
   **Google**, switch it on and save.

One Google client covers the iPhone, web and desktop: they all go through Supabase's web sign-in.

## 3. Apple (needs the paid Apple Developer Program, $99/year)

A free Personal Team can't create the Services ID and key Apple requires, so this step waits until
the account is upgraded. The iPhone app itself does **not** need the Sign in with Apple capability:
it uses the same web sign-in as Google, so a free-team build keeps working.

1. developer.apple.com → **Certificates, IDs & Profiles → Identifiers**: make sure an App ID exists
   with **Sign in with Apple** ticked (e.g. `com.norbertvarjasi.framescout.app`).
2. **Identifiers → + → Services IDs**: e.g. `com.norbertvarjasi.framescan.signin`. Tick **Sign in with
   Apple → Configure**: primary App ID as above, **Domains** `nuprvuipspqmhsczdqrk.supabase.co`,
   **Return URLs** `https://nuprvuipspqmhsczdqrk.supabase.co/auth/v1/callback`.
3. **Keys → +**: tick **Sign in with Apple**, download the `.p8` file, note the Key ID and your Team ID.
4. Supabase → Authentication → Sign In / Providers → **Apple**: switch on, **Client IDs** = the Services
   ID, and the **Secret Key** generated from the `.p8` (Supabase's Apple page links a generator).
   Apple makes this secret expire after at most 6 months: put a reminder in the calendar to renew it.

## How it works (for maintainers)

- Email: `signup` → confirmation email → link, or the code via `POST /auth/v1/verify` (`type: signup`).
  `POST /auth/v1/resend` sends it again.
- Apple / Google: PKCE through `/auth/v1/authorize`, then `POST /auth/v1/token?grant_type=pkce`.
  - iPhone: `ASWebAuthenticationSession` catches `framescan://auth-callback` (no Info.plist entry needed).
  - Web: the page redirects to the provider and back to itself with `?code=`.
  - Desktop (Tauri): Google and Apple block embedded web views, so the app opens the system browser and
    listens once on `127.0.0.1:53682–53684` for the redirect (`web/src-tauri/src/oauth.rs`).
- Before opening a provider, the apps read `/auth/v1/settings` and stop with a plain message when the
  provider is off.
