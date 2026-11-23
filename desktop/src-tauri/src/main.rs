#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod icons;
mod library;
mod windows;
fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            let app = app.clone();
            tauri::async_runtime::spawn(async move { let _ = windows::open_default_window(app).await; });
        }))
        .manage(library::LibraryLock(std::sync::Mutex::new(())))
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![icons::load_custom_icons, icons::choose_custom_icon, icons::reset_custom_icon, library::shared_data, windows::open_game_window])
        .setup(|app| { icons::restore_app_icon(app.handle()); Ok(()) })
        .run(tauri::generate_context!())
        .expect("无法启动扫雷");
}
