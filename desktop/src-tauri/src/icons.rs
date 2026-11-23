use base64::{engine::general_purpose::STANDARD, Engine};
use image::{imageops::FilterType, DynamicImage, ImageDecoder, ImageFormat, ImageReader};
use std::{fs, io::Cursor, path::{Path, PathBuf}};
use tauri::Manager;
use tauri_plugin_dialog::DialogExt;

const INVALID: &str = "请选择 8 MB 以内的 PNG、JPG 或 ICO 图片";
const LIMIT: u64 = 8 * 1024 * 1024;
fn checked_kind(kind: &str) -> Result<&str, String> {
    match kind { "app" | "flag" | "mine" => Ok(kind), _ => Err("无效图标类型".into()) }
}
fn directory(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    app.path().app_data_dir().map(|p| p.join("Icons")).map_err(|_| "暂时无法保存图标".into())
}
fn normalize(data: &[u8], kind: &str) -> Result<Vec<u8>, String> {
    checked_kind(kind)?;
    if data.is_empty() || data.len() as u64 > LIMIT { return Err(INVALID.into()); }
    let reader = || ImageReader::new(Cursor::new(data)).with_guessed_format().map_err(|_| INVALID.to_owned());
    let r = reader()?;
    if !matches!(r.format(), Some(ImageFormat::Png | ImageFormat::Jpeg | ImageFormat::Ico)) { return Err(INVALID.into()); }
    let (w, h) = r.into_dimensions().map_err(|_| INVALID)?;
    if w == 0 || h == 0 || w > 4096 || h > 4096 { return Err(INVALID.into()); }
    let mut decoder = reader()?.into_decoder().map_err(|_| INVALID)?;
    let orientation = decoder.orientation().map_err(|_| INVALID)?;
    let mut image = DynamicImage::from_decoder(decoder).map_err(|_| INVALID)?;
    image.apply_orientation(orientation);
    let size = if kind == "app" { 512 } else { 128 };
    let mut png = Cursor::new(Vec::new());
    image.resize(size, size, FilterType::Lanczos3).write_to(&mut png, ImageFormat::Png).map_err(|_| INVALID)?;
    Ok(png.into_inner())
}
fn data_url(data: &[u8]) -> String { format!("data:image/png;base64,{}", STANDARD.encode(data)) }
fn icon_image(data: &[u8]) -> Result<tauri::image::Image<'static>, String> {
    let rgba = image::load_from_memory(data).map_err(|_| INVALID)?.to_rgba8();
    let (w, h) = rgba.dimensions();
    Ok(tauri::image::Image::new_owned(rgba.into_raw(), w, h))
}
fn apply(app: &tauri::AppHandle, data: Option<&[u8]>) -> Result<(), String> {
    let icon = match data {
        Some(bytes) => icon_image(bytes)?,
        None => app.default_window_icon().cloned().ok_or("暂时无法恢复图标")?,
    };
    for window in app.webview_windows().values() { window.set_icon(icon.clone()).map_err(|_| "暂时无法更换图标")?; }
    Ok(())
}
fn persist(dir: &Path, kind: &str, data: &[u8]) -> Result<(), String> {
    checked_kind(kind)?;
    fs::create_dir_all(dir).map_err(|_| "暂时无法保存图标")?;
    let staging = dir.join(format!("{kind}.tmp"));
    fs::write(&staging, data).map_err(|_| "暂时无法保存图标")?;
    fs::rename(staging, dir.join(format!("{kind}.png"))).map_err(|_| "暂时无法保存图标".into())
}
fn saved(dir: &Path, kind: &str) -> Option<Vec<u8>> {
    let path = dir.join(format!("{kind}.png"));
    if fs::metadata(&path).ok()?.len() > LIMIT { return None; }
    normalize(&fs::read(path).ok()?, kind).ok()
}
pub fn restore_app_icon(app: &tauri::AppHandle) {
    if let Ok(dir) = directory(app) { if let Some(data) = saved(&dir, "app") { let _ = apply(app, Some(&data)); } }
}
#[tauri::command]
pub fn load_custom_icons(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    let dir = directory(&app)?;
    let mut icons = serde_json::Map::new();
    for kind in ["app", "flag", "mine"] {
        if let Some(png) = saved(&dir, kind) { icons.insert(kind.into(), data_url(&png).into()); }
    }
    Ok(icons.into())
}
#[tauri::command]
pub async fn choose_custom_icon(app: tauri::AppHandle, kind: String) -> Result<Option<String>, String> {
    checked_kind(&kind)?;
    tauri::async_runtime::spawn_blocking(move || {
        let Some(file) = app.dialog().file().set_title("选择图标").add_filter("图像", &["png", "jpg", "jpeg", "ico"]).blocking_pick_file() else { return Ok(None); };
        let path = file.into_path().map_err(|_| INVALID)?;
        if fs::metadata(&path).map_err(|_| "暂时无法读取这张图片")?.len() > LIMIT { return Err(INVALID.into()); }
        let png = normalize(&fs::read(path).map_err(|_| "暂时无法读取这张图片")?, &kind)?;
        let dir = directory(&app)?;
        if kind == "app" { apply(&app, Some(&png))?; }
        if let Err(error) = persist(&dir, &kind, &png) {
            if kind == "app" { let previous = saved(&dir, "app"); let _ = apply(&app, previous.as_deref()); }
            return Err(error);
        }
        Ok(Some(data_url(&png)))
    }).await.map_err(|_| "暂时无法读取这张图片")?
}
#[tauri::command]
pub fn reset_custom_icon(app: tauri::AppHandle, kind: String) -> Result<(), String> {
    checked_kind(&kind)?;
    let dir = directory(&app)?;
    let previous = saved(&dir, &kind);
    if kind == "app" { apply(&app, None)?; }
    let path = dir.join(format!("{kind}.png"));
    if path.exists() && fs::remove_file(path).is_err() {
        if kind == "app" { let _ = apply(&app, previous.as_deref()); }
        return Err("暂时无法恢复图标".into());
    }
    Ok(())
}

#[cfg(test)] mod tests {
    use super::*;
    fn fixture(w: u32, h: u32) -> Vec<u8> {
        let mut out = Cursor::new(Vec::new());
        DynamicImage::new_rgba8(w, h).write_to(&mut out, ImageFormat::Png).unwrap(); out.into_inner()
    }
    #[test] fn normalization_keeps_aspect_and_alpha() {
        let bytes = normalize(&fixture(900, 450), "flag").unwrap();
        let rgba = image::load_from_memory(&bytes).unwrap().to_rgba8();
        assert_eq!(rgba.dimensions(), (128, 64)); assert_eq!(rgba.get_pixel(0, 0).0[3], 0);
        assert_eq!(image::load_from_memory(&normalize(&fixture(900, 450), "app").unwrap()).unwrap().width(), 512);
    }
    #[test] fn rejects_invalid_oversized_and_traversal_inputs() {
        assert!(normalize(b"<svg/>", "flag").is_err());
        assert!(normalize(&vec![0; LIMIT as usize + 1], "app").is_err());
        assert!(normalize(&fixture(4097, 1), "mine").is_err());
        assert!(checked_kind("../app").is_err());
    }
    #[test] fn copies_survive_reload_and_replace_independently() {
        let dir = std::env::temp_dir().join(format!("minesweeper-icons-{}-{}", std::process::id(), std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
        let a = normalize(&fixture(20, 10), "flag").unwrap();
        let b = normalize(&fixture(10, 20), "mine").unwrap();
        persist(&dir, "flag", &a).unwrap(); persist(&dir, "mine", &b).unwrap();
        assert_eq!(saved(&dir, "flag").unwrap(), a); assert_eq!(saved(&dir, "mine").unwrap(), b);
        persist(&dir, "flag", &b).unwrap(); assert_eq!(saved(&dir, "flag").unwrap(), b);
        fs::remove_file(dir.join("flag.png")).unwrap(); assert!(saved(&dir, "flag").is_none()); assert!(saved(&dir, "mine").is_some());
        fs::remove_dir_all(dir).unwrap();
    }
}
