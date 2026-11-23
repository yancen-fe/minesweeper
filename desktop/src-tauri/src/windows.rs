use std::sync::atomic::{AtomicU64, Ordering};
use tauri::{WebviewUrl, WebviewWindowBuilder};
static NEXT_WINDOW: AtomicU64 = AtomicU64::new(1);
#[tauri::command]
pub async fn open_game_window(app: tauri::AppHandle, level: String, mode: String) -> Result<String, String> {
    if !["easy","medium","hard"].contains(&level.as_str()) || !["classic","logical"].contains(&mode.as_str()) { return Err("无效的对局选项".into()); }
    create_window(app, Some((level, mode)))
}
pub async fn open_default_window(app: tauri::AppHandle) -> Result<String, String> { create_window(app, None) }
fn create_window(app: tauri::AppHandle, options: Option<(String, String)>) -> Result<String, String> {
    let (url, level) = options.map(|(level,mode)| (format!("index.html?level={level}&mode={mode}"),level)).unwrap_or(("index.html".into(),"easy".into()));
    let label = format!("game-{}", NEXT_WINDOW.fetch_add(1, Ordering::Relaxed));
    let (width,height) = match level.as_str() { "medium" => (550.,650.), "hard" => (960.,650.), _ => (430.,550.) };
    WebviewWindowBuilder::new(&app, &label, WebviewUrl::App(url.into()))
        .title("扫雷").inner_size(width,height).min_inner_size(width,height).max_inner_size(width,height)
        .resizable(false).maximizable(false).disable_drag_drop_handler().center().build().map_err(|_| "暂时无法打开新窗口")?;
    crate::icons::restore_app_icon(&app);
    Ok(label)
}
