use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::{fs, path::Path, sync::Mutex};
use tauri::{Emitter, Manager};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Record {
    pub id: String, pub level: String, pub mode: Option<String>,
    pub started_at: u64, pub ended_at: u64, pub seconds: u64, pub result: String,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Library {
    pub revision: u64, pub history: Vec<Record>, pub best: Map<String, Value>, pub settings: Map<String, Value>,
}
pub struct LibraryLock(pub Mutex<()>);
fn valid_record(record: &Record) -> bool {
    !record.id.is_empty() && record.id.len() <= 100 && ["easy","medium","hard"].contains(&record.level.as_str())
        && record.mode.as_deref().map(|s| ["classic","logical"].contains(&s)).unwrap_or(true)
        && ["won","lost","abandoned"].contains(&record.result.as_str())
}
fn merge_settings(settings: &mut Map<String, Value>, patch: &Value) {
    if let Some(values) = patch.as_object() { for key in ["press","rounded","triangle","small","mask","result"] {
        if let Some(value) = values.get(key).filter(|v| v.is_boolean()) { settings.insert(key.into(), value.clone()); }
    } }
}
fn save(path: &Path, data: &Library) -> Result<(), String> {
    fs::create_dir_all(path.parent().ok_or("无法保存战绩")?).map_err(|_| "无法保存战绩")?;
    let staging = path.with_extension("tmp");
    fs::write(&staging, serde_json::to_vec(data).map_err(|_| "无法保存战绩")?).map_err(|_| "无法保存战绩")?;
    fs::rename(staging, path).map_err(|_| "无法保存战绩".into())
}
fn transact(path: &Path, operation: &str, payload: Value) -> Result<Library, String> {
    let exists = path.exists();
    let mut data: Library = if exists {
        serde_json::from_slice(&fs::read(path).map_err(|_| "无法读取战绩")?).map_err(|_| "无法读取战绩")?
    } else {
        let mut data = Library::default();
        if let Some(records) = payload.get("history").and_then(Value::as_array) {
            for value in records { if let Ok(record) = serde_json::from_value::<Record>(value.clone()) {
                if valid_record(&record) && !data.history.iter().any(|r| r.id == record.id) { data.history.push(record); }
            } }
        }
        if let Some(best) = payload.get("best").and_then(Value::as_object) { for (key, value) in best {
            if value.as_u64().is_some() { data.best.insert(key.clone(), value.clone()); }
        } }
        merge_settings(&mut data.settings, &payload["settings"]); data
    };
    match operation {
        "load" => {},
        "record" => {
            let record: Record = serde_json::from_value(payload).map_err(|_| "无效的对局记录")?;
            if !valid_record(&record) { return Err("无效的对局记录".into()); }
            if !data.history.iter().any(|r| r.id == record.id) {
                if record.result == "won" {
                    let key = if record.mode.as_deref() == Some("classic") { format!("classic:{}",record.level) } else { record.level.clone() };
                    if data.best.get(&key).and_then(Value::as_u64).map(|n| record.seconds < n).unwrap_or(true) { data.best.insert(key, record.seconds.into()); }
                }
                data.history.push(record);
            }
        },
        "clear" => { data.history.clear(); data.best.clear(); },
        "settings" => merge_settings(&mut data.settings, &payload),
        _ => return Err("无效的保存操作".into()),
    }
    data.history.sort_by(|a,b| b.ended_at.cmp(&a.ended_at).then_with(|| a.id.cmp(&b.id)));
    if operation != "load" || !exists { data.revision += 1; save(path, &data)?; }
    Ok(data)
}
#[tauri::command]
pub async fn shared_data(app: tauri::AppHandle, state: tauri::State<'_, LibraryLock>, operation: String, payload: Value) -> Result<Library, String> {
    let _guard = state.0.lock().map_err(|_| "无法保存战绩")?;
    let path = app.path().app_data_dir().map_err(|_| "无法保存战绩")?.join("shared-library-v1.json");
    let data = transact(&path, &operation, payload)?;
    if operation != "load" { let _ = app.emit("shared-data-changed", &data); }
    Ok(data)
}
#[cfg(test)] mod tests {
    use super::*;
    use serde_json::json;
    #[test] fn shared_records_and_settings_merge_without_overwriting() {
        let dir = std::env::temp_dir().join(format!("minesweeper-library-{}",std::process::id()));
        let _ = fs::remove_dir_all(&dir); let path = dir.join("library.json");
        transact(&path,"load",json!({"history":[],"best":{"easy":60},"settings":{"press":true}})).unwrap();
        for (id,seconds) in [("one",30),("two",10),("one",30)] {
            transact(&path,"record",json!({"id":id,"level":"easy","mode":"classic","startedAt":1,"endedAt":2,"seconds":seconds,"result":"won"})).unwrap();
        }
        transact(&path,"settings",json!({"rounded":false})).unwrap();
        let data = transact(&path,"settings",json!({"mask":false})).unwrap();
        assert_eq!(data.history.len(),2); assert_eq!(data.best["classic:easy"],10); assert_eq!(data.best["easy"],60);
        assert_eq!(data.settings["press"],true); assert_eq!(data.settings["rounded"],false); assert_eq!(data.settings["mask"],false);
        let data = transact(&path,"clear",Value::Null).unwrap(); assert!(data.history.is_empty() && data.best.is_empty()); assert!(data.settings.contains_key("mask"));
        fs::write(&path,b"damaged").unwrap(); assert!(transact(&path,"record",json!({})).is_err());
        fs::remove_dir_all(dir).unwrap();
    }
    #[test] fn concurrent_sessions_are_serialized_before_persistence() {
        use std::sync::Arc;
        let dir = std::env::temp_dir().join(format!("minesweeper-concurrent-{}",std::process::id()));
        let _ = fs::remove_dir_all(&dir); let path = dir.join("library.json");
        let lock = Arc::new(Mutex::new(())); let mut threads = Vec::new();
        for window in 0..2 { let lock = lock.clone(); let path = path.clone(); threads.push(std::thread::spawn(move || {
            for session in 0..30 { let _guard = lock.lock().unwrap();
                transact(&path,"record",json!({"id":format!("{window}-{session}"),"level":"easy","mode":"classic","startedAt":1,"endedAt":2,"seconds":session+1,"result":"won"})).unwrap();
            }
        })); }
        for thread in threads { thread.join().unwrap(); }
        let data = transact(&path,"load",Value::Null).unwrap(); assert_eq!(data.history.len(),60); assert_eq!(data.best["classic:easy"],1);
        fs::remove_dir_all(dir).unwrap();
    }

}
