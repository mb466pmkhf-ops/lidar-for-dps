// Loopback redirect for Apple / Google sign-in on the desktop (see lib.rs). No extra crates.
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::process::Command;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use tauri::Manager;

/// Fixed ports so the redirect URLs can be listed in Supabase (Authentication → URL Configuration).
pub const PORTS: [u16; 3] = [53682, 53683, 53684];
const CALLBACK_PATH: &str = "/auth-callback";
const TIMEOUT: Duration = Duration::from_secs(300);

pub struct Pending(pub Mutex<Option<TcpListener>>);

/// Binds the first free loopback port and keeps it until `oauth_wait`.
#[tauri::command]
pub fn oauth_listen(state: tauri::State<'_, Pending>) -> Result<u16, String> {
    for port in PORTS {
        if let Ok(listener) = TcpListener::bind(("127.0.0.1", port)) {
            *state.0.lock().map_err(|e| e.to_string())? = Some(listener);
            return Ok(port);
        }
    }
    Err("Couldn't start sign-in: ports 53682–53684 are all in use. Close other sign-in windows and try again.".into())
}

/// Opens `url` in the system browser and returns the query string of the redirect (code or error).
#[tauri::command]
pub async fn oauth_wait(app: tauri::AppHandle, state: tauri::State<'_, Pending>, url: String) -> Result<String, String> {
    let listener = state.0.lock().map_err(|e| e.to_string())?.take().ok_or("Sign-in wasn't started.")?;
    if !is_sign_in_url(&url) {
        return Err("Sign-in needs the sync server's https sign-in address.".into());
    }
    open_browser(&url)?;
    let query = tauri::async_runtime::spawn_blocking(move || wait_for_callback(listener, TIMEOUT))
        .await
        .map_err(|e| e.to_string())??;
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.set_focus();
    }
    Ok(query)
}

/// The web view may only open a Supabase sign-in page in the system browser, so a page that went
/// wrong can't use this command to open arbitrary sites. The server is configurable, so the host
/// isn't fixed; the scheme and path are.
pub fn is_sign_in_url(url: &str) -> bool {
    let Some(rest) = url.strip_prefix("https://") else { return false };
    let (host, path) = rest.split_once('/').unwrap_or((rest, ""));
    !host.is_empty()
        && host.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | ':'))
        && (path == "auth/v1/authorize" || path.starts_with("auth/v1/authorize?"))
        && !url.chars().any(|c| c.is_control() || c == ' ' || c == '"')
}

fn open_browser(url: &str) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    let mut cmd = {
        let mut c = Command::new("open");
        c.arg(url);
        c
    };
    #[cfg(target_os = "windows")]
    let mut cmd = {
        // Not `cmd /c start`: that would treat & in the URL as a command separator.
        let mut c = Command::new("rundll32");
        c.args(["url.dll,FileProtocolHandler", url]);
        c
    };
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    let mut cmd = {
        let mut c = Command::new("xdg-open");
        c.arg(url);
        c
    };
    cmd.spawn().map(|_| ()).map_err(|e| format!("Couldn't open the browser: {e}"))
}

/// Serves until one request for CALLBACK_PATH arrives (others, like /favicon.ico, get a 404).
pub fn wait_for_callback(listener: TcpListener, timeout: Duration) -> Result<String, String> {
    listener.set_nonblocking(true).map_err(|e| e.to_string())?;
    let deadline = Instant::now() + timeout;
    loop {
        match listener.accept() {
            Ok((stream, _)) => {
                if let Some(query) = handle(stream) {
                    return Ok(query);
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                if Instant::now() > deadline {
                    return Err("Sign-in timed out. Try again.".into());
                }
                std::thread::sleep(Duration::from_millis(100));
            }
            Err(e) => return Err(e.to_string()),
        }
    }
}

fn handle(mut stream: TcpStream) -> Option<String> {
    let _ = stream.set_nonblocking(false);
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let mut buf = Vec::new();
    let mut chunk = [0u8; 2048];
    while !buf.windows(4).any(|w| w == b"\r\n\r\n") && buf.len() < 16 * 1024 {
        match stream.read(&mut chunk) {
            Ok(0) | Err(_) => break,
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
        }
    }
    let head = String::from_utf8_lossy(&buf);
    let target = head.lines().next().and_then(|l| {
        let mut parts = l.split(' ');
        (parts.next() == Some("GET")).then(|| parts.next()).flatten()
    });
    let (path, query) = match target {
        Some(t) => t.split_once('?').unwrap_or((t, "")),
        None => ("", ""),
    };
    if path != CALLBACK_PATH {
        let _ = stream.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        return None;
    }
    let ok = !query.contains("error");
    let body = format!(
        "<!doctype html><meta charset=utf-8><title>FrameScan Planner</title>\
         <body style=\"font:16px -apple-system,Segoe UI,sans-serif;max-width:28em;margin:20vh auto;padding:0 16px;color:#14181a\">\
         <h1 style=\"font-weight:500\">{}</h1><p>You can close this tab and go back to FrameScan Planner.</p>",
        if ok { "Signed in" } else { "Sign-in didn't finish" }
    );
    let _ = stream.write_all(
        format!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n{}",
            body.len(),
            body
        )
        .as_bytes(),
    );
    Some(query.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn returns_the_callback_query_and_skips_other_paths() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        let client = std::thread::spawn(move || {
            for path in ["/favicon.ico", "/auth-callback?code=abc&state=1"] {
                let mut s = TcpStream::connect(("127.0.0.1", port)).unwrap();
                s.write_all(format!("GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n").as_bytes()).unwrap();
                let mut out = String::new();
                let _ = s.read_to_string(&mut out);
            }
        });
        assert_eq!(wait_for_callback(listener, Duration::from_secs(5)).unwrap(), "code=abc&state=1");
        client.join().unwrap();
    }

    #[test]
    fn only_sign_in_pages_open() {
        assert!(is_sign_in_url("https://abc.supabase.co/auth/v1/authorize?provider=google&redirect_to=x"));
        assert!(is_sign_in_url("https://my-server.example.com:8443/auth/v1/authorize?provider=apple"));
        assert!(!is_sign_in_url("http://abc.supabase.co/auth/v1/authorize?provider=google"));
        assert!(!is_sign_in_url("https://evil.example.com/login"));
        assert!(!is_sign_in_url("https://user@evil.example.com/auth/v1/authorize"));
        assert!(!is_sign_in_url("https://abc.supabase.co/auth/v1/authorizeX"));
        assert!(!is_sign_in_url("https:///auth/v1/authorize"));
        assert!(!is_sign_in_url("file:///etc/passwd"));
    }

    #[test]
    fn times_out() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        assert!(wait_for_callback(listener, Duration::from_millis(200)).is_err());
    }
}
