use std::fs;
use std::path::Path;

// Writes generated Luau to disk. The frontend picks the path via the dialog plugin.
#[tauri::command]
fn save_text(path: String, contents: String) -> Result<(), String> {
    if let Some(parent) = Path::new(&path).parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::write(&path, contents).map_err(|e| e.to_string())
}

// Reads a user-chosen file so Studio can round-trip an existing SkidSS.lua —
// preserving the WHITELIST config when only the CUSTOM sections change.
#[tauri::command]
fn read_text(path: String) -> Result<String, String> {
    fs::read_to_string(&path).map_err(|e| e.to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![save_text, read_text])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
