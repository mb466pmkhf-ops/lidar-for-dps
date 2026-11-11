// The desktop app is the web planner in a native window. All data handling (local storage,
// Supabase sync) lives in the web code, so web and desktop behave the same.
//
// The one native piece is Apple / Google sign-in: both refuse to sign in inside an embedded web
// view, so the planner asks for a loopback port (`oauth_listen`), then `oauth_wait` opens the
// provider page in the system browser and waits for the redirect to
// http://127.0.0.1:<port>/auth-callback. The query string goes back to the web code, which swaps the
// code for a session with its PKCE verifier (src/sync/oauth.ts). Only 127.0.0.1 is bound.
mod oauth;

use std::sync::Mutex;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(oauth::Pending(Mutex::new(None)))
        .invoke_handler(tauri::generate_handler![oauth::oauth_listen, oauth::oauth_wait])
        .run(tauri::generate_context!())
        .expect("error while running FrameScan Planner");
}
