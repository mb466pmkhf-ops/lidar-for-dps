// The desktop app is the web planner in a native window. All data handling (local storage,
// Supabase sync) lives in the web code, so web and desktop behave the same.
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running FrameScan Planner");
}
