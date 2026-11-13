# Security

## Re-audit, 13 November 2026 (before the App Store release)

This covers everything since the first audit (PR #13, 10 Nov): sign-in on all three apps, sync and
merge, building a room from a listing, plan hand-off export, the 3D work, account deletion and the
release pipeline (PR #39).

| Area | Result |
| --- | --- |
| iPhone sign-in | Tokens in the Keychain (`AfterFirstUnlockThisDeviceOnly`), PKCE through `ASWebAuthenticationSession`, no tokens logged. No App Transport Security exceptions. |
| Web sign-in | PKCE verifier in `sessionStorage`, code removed from the address bar, no server address taken from the URL. |
| Desktop sign-in | Loopback only on 127.0.0.1, replies never echo input, injected codes fail without the PKCE verifier. **Fixed:** the native "open in browser" command took any https address; it now only opens the sync server's `/auth/v1/authorize` page. Tested in `oauth.rs`. |
| Web page safety | No `innerHTML`, `eval` or `dangerouslySetInnerHTML`. CSP on web and desktop (`connect-src https:` stays open on purpose so people can point the app at their own server). |
| Project import (iPhone ZIP) | Paths are standardized and kept inside the project folder (from PR #13). |
| Listing import | Text and photos are read locally. Nothing is fetched from listing links. |
| Database | Row-level security on every row, anon has no access, size caps. The new `delete_my_account()` runs with owner rights, an empty `search_path` and fully qualified names, and only `authenticated` can call it. |
| Dependencies | `npm audit` (shipped packages): 0 issues. `cargo audit`: 0 vulnerabilities. There are two warnings, both in Linux-only GTK crates that aren't in the Mac or Windows builds. Both now run on every push (Release gates). |
| Supabase advisors | One warning: leaked-password protection is off. **Owner:** Authentication → Settings → turn it on. |

## Reporting a problem

Email [contact email] with the steps to reproduce. Please don't open a public issue.
