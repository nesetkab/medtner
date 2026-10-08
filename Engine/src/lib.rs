use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, Once};
use std::time::Duration;

use librespot_connect::{ConnectConfig, LoadRequest, LoadRequestOptions, Spirc};
use librespot_core::authentication::Credentials;
use librespot_core::cache::Cache;
use librespot_core::config::{DeviceType, SessionConfig};
use librespot_core::Error;
use librespot_core::session::Session;
use librespot_oauth::OAuthClientBuilder;
use librespot_playback::audio_backend::{Sink, SinkResult};
use librespot_playback::config::{Bitrate, PlayerConfig, VolumeCtrl};
use librespot_playback::convert::Converter;
use librespot_playback::decoder::AudioPacket;
use librespot_playback::mixer::softmixer::SoftMixer;
use librespot_playback::mixer::{Mixer, MixerConfig, NoOpVolume};
use librespot_metadata::audio::{AudioItem, UniqueFields};
use librespot_playback::player::{Player, PlayerEvent};
use sha1::{Digest, Sha1};
use tokio::sync::oneshot;

pub type AudioCallback = extern "C" fn(context: *mut c_void, samples: *const f32, count: usize);
pub type EventCallback = extern "C" fn(context: *mut c_void, event: *const c_char, value: i64);

#[repr(C)]
pub struct MedtnerEngineConfig {
    pub name: *const c_char,
    pub log_path: *const c_char,
    pub system_cache: *const c_char,
    pub audio_cache: *const c_char,
    pub audio_cache_limit: u64,
    pub bitrate: u32,
    pub normalize: bool,
    pub initial_volume: u32,
    pub autoplay: bool,
    pub audio: AudioCallback,
    pub event: EventCallback,
    pub context: *mut c_void,
}

#[derive(Clone, Copy)]
struct Bridge {
    audio: AudioCallback,
    event: EventCallback,
    context: *mut c_void,
}

unsafe impl Send for Bridge {}
unsafe impl Sync for Bridge {}

impl Bridge {
    fn emit(&self, name: &str, value: i64) {
        if let Ok(text) = CString::new(name) {
            (self.event)(self.context, text.as_ptr(), value);
        }
    }
}

struct BridgeSink {
    bridge: Bridge,
    scratch: Vec<f32>,
}

impl Sink for BridgeSink {
    fn start(&mut self) -> SinkResult<()> {
        self.bridge.emit("sink_started", 0);
        Ok(())
    }

    fn stop(&mut self) -> SinkResult<()> {
        self.bridge.emit("sink_stopped", 0);
        Ok(())
    }

    fn write(&mut self, packet: AudioPacket, _converter: &mut Converter) -> SinkResult<()> {
        if let AudioPacket::Samples(samples) = packet {
            self.scratch.clear();
            self.scratch.extend(samples.iter().map(|sample| *sample as f32));
            (self.bridge.audio)(self.bridge.context, self.scratch.as_ptr(), self.scratch.len());
        }
        Ok(())
    }
}

struct FileLog {
    file: Mutex<std::fs::File>,
}

impl log::Log for FileLog {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        let target = metadata.target();
        target.starts_with("librespot")
            && (metadata.level() <= log::Level::Info || target.starts_with("librespot_connect"))
    }

    fn log(&self, record: &log::Record) {
        if !self.enabled(record.metadata()) {
            return;
        }
        let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0);
        if let Ok(mut file) = self.file.lock() {
            use std::io::Write;
            let _ = writeln!(file, "{stamp:.3} {} {}: {}", record.level(), record.target(), record.args());
        }
    }

    fn flush(&self) {}
}

static LOG: Once = Once::new();

fn start_log(path: &str) {
    if path.is_empty() {
        return;
    }
    LOG.call_once(|| {
        if let Some(parent) = std::path::Path::new(path).parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(file) = std::fs::File::create(path) {
            if log::set_boxed_logger(Box::new(FileLog { file: Mutex::new(file) })).is_ok() {
                log::set_max_level(log::LevelFilter::Debug);
            }
        }
    });
}

struct Settings {
    name: String,
    system_cache: String,
    audio_cache: String,
    audio_cache_limit: u64,
    bitrate: Bitrate,
    normalize: bool,
    initial_volume: u16,
    autoplay: bool,
}

static RUNNING: Mutex<Option<oneshot::Sender<()>>> = Mutex::new(None);
static ALIVE: AtomicBool = AtomicBool::new(false);
static SPIRC: Mutex<Option<Arc<Spirc>>> = Mutex::new(None);

fn publish(spirc: Option<Arc<Spirc>>) {
    *SPIRC.lock().unwrap_or_else(|e| e.into_inner()) = spirc;
}

fn with_spirc(action: impl FnOnce(&Spirc) -> Result<(), Error>) -> bool {
    let Some(spirc) = SPIRC.lock().unwrap_or_else(|e| e.into_inner()).clone() else {
        return false;
    };
    action(&spirc).is_ok()
}

#[no_mangle]
pub extern "C" fn medtner_engine_radio(track_uri: *const c_char) -> bool {
    let uri = string(track_uri);
    if uri.is_empty() {
        return false;
    }
    let options = LoadRequestOptions {
        start_playing: true,
        seek_to: 0,
        context_options: None,
        playing_track: None,
    };
    with_spirc(|spirc| {
        spirc.activate()?;
        spirc.load(LoadRequest::from_context_uri(uri, options))
    })
}

#[no_mangle]
pub extern "C" fn medtner_engine_next() -> bool {
    with_spirc(Spirc::next)
}

#[no_mangle]
pub extern "C" fn medtner_engine_previous() -> bool {
    with_spirc(Spirc::prev)
}

#[no_mangle]
pub extern "C" fn medtner_engine_seek(position_ms: u32) -> bool {
    with_spirc(|spirc| spirc.set_position_ms(position_ms))
}

const SCOPES: &[&str] = &[
    "streaming",
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-currently-playing",
    "user-read-private",
];

fn string(pointer: *const c_char) -> String {
    if pointer.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(pointer) }.to_string_lossy().into_owned()
}

fn quote(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn track_json(item: &AudioItem) -> String {
    let (artists, album) = match &item.unique_fields {
        UniqueFields::Track { artists, album, .. } => (artists.iter().map(|a| a.name.clone()).collect::<Vec<_>>(), album.clone()),
        UniqueFields::Episode { show_name, .. } => (vec![show_name.clone()], show_name.clone()),
        UniqueFields::Local { artists, album, .. } => (artists.iter().cloned().collect(), album.clone().unwrap_or_default()),
    };
    let cover = item.covers.iter().max_by_key(|c| c.width).map(|c| c.url.clone()).unwrap_or_default();
    let artists = artists.iter().map(|a| quote(a)).collect::<Vec<_>>().join(",");
    format!(
        "{{\"uri\":{},\"name\":{},\"artists\":[{}],\"album\":{},\"duration_ms\":{},\"cover\":{}}}",
        quote(&item.uri),
        quote(&item.name),
        artists,
        quote(&album),
        item.duration_ms,
        quote(&cover)
    )
}

fn device_id(name: &str) -> String {
    Sha1::digest(name.as_bytes()).iter().map(|byte| format!("{byte:02x}")).collect()
}

#[no_mangle]
pub extern "C" fn medtner_engine_start(config: *const MedtnerEngineConfig) -> bool {
    if config.is_null() {
        return false;
    }
    let config = unsafe { &*config };
    start_log(&string(config.log_path));
    let bridge = Bridge { audio: config.audio, event: config.event, context: config.context };
    let settings = Settings {
        name: string(config.name),
        system_cache: string(config.system_cache),
        audio_cache: string(config.audio_cache),
        audio_cache_limit: config.audio_cache_limit,
        bitrate: match config.bitrate {
            96 => Bitrate::Bitrate96,
            160 => Bitrate::Bitrate160,
            _ => Bitrate::Bitrate320,
        },
        normalize: config.normalize,
        initial_volume: (config.initial_volume.min(100) * u16::MAX as u32 / 100) as u16,
        autoplay: config.autoplay,
    };

    if ALIVE.swap(true, Ordering::SeqCst) {
        return false;
    }
    let (stop_tx, stop_rx) = oneshot::channel();
    *RUNNING.lock().unwrap_or_else(|e| e.into_inner()) = Some(stop_tx);

    let spawned = std::thread::Builder::new().name("medtner.engine".into()).spawn(move || {
        let runtime = match tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("medtner.engine.worker")
            .enable_all()
            .build()
        {
            Ok(runtime) => runtime,
            Err(_) => {
                bridge.emit("failed", 0);
                finish(bridge);
                return;
            }
        };
        runtime.block_on(run(settings, bridge, stop_rx));
        runtime.shutdown_timeout(Duration::from_secs(2));
        finish(bridge);
    });
    if spawned.is_err() {
        RUNNING.lock().unwrap_or_else(|e| e.into_inner()).take();
        ALIVE.store(false, Ordering::SeqCst);
        return false;
    }
    true
}

fn finish(bridge: Bridge) {
    publish(None);
    RUNNING.lock().unwrap_or_else(|e| e.into_inner()).take();
    ALIVE.store(false, Ordering::SeqCst);
    bridge.emit("exited", 0);
}

#[no_mangle]
pub extern "C" fn medtner_engine_stop() {
    let sender = RUNNING.lock().unwrap_or_else(|e| e.into_inner()).take();
    if let Some(sender) = sender {
        let _ = sender.send(());
    }
}

async fn run(settings: Settings, bridge: Bridge, mut stop: oneshot::Receiver<()>) {
    let cache = Cache::new(
        Some(settings.system_cache.as_str()),
        Some(settings.system_cache.as_str()),
        Some(settings.audio_cache.as_str()),
        Some(settings.audio_cache_limit),
    )
    .ok();

    let session_config = SessionConfig {
        device_id: device_id(&settings.name),
        autoplay: Some(settings.autoplay),
        ..SessionConfig::default()
    };

    let credentials = match cache.as_ref().and_then(Cache::credentials) {
        Some(credentials) => credentials,
        None => {
            bridge.emit("needs_login", 0);
            let client_id = session_config.client_id.clone();
            let login = tokio::task::spawn_blocking(move || {
                OAuthClientBuilder::new(&client_id, "http://127.0.0.1:5588/login", SCOPES.to_vec())
                    .open_in_browser()
                    .build()
                    .ok()?
                    .get_access_token()
                    .ok()
            });
            let token = tokio::select! {
                token = login => token.ok().flatten(),
                _ = &mut stop => return,
            };
            match token {
                Some(token) => Credentials::with_access_token(token.access_token),
                None => {
                    bridge.emit("failed", 0);
                    return;
                }
            }
        }
    };

    let mixer: Arc<dyn Mixer> = match SoftMixer::open(MixerConfig { volume_ctrl: VolumeCtrl::Fixed, ..MixerConfig::default() }) {
        Ok(mixer) => Arc::new(mixer),
        Err(_) => {
            bridge.emit("failed", 0);
            return;
        }
    };

    let player_config = PlayerConfig {
        bitrate: settings.bitrate,
        normalisation: settings.normalize,
        ditherer: None,
        ..PlayerConfig::default()
    };

    let mut session = Session::new(session_config.clone(), cache.clone());
    let sink_bridge = bridge;
    let player = Player::new(player_config, session.clone(), Box::new(NoOpVolume), move || {
        Box::new(BridgeSink { bridge: sink_bridge, scratch: Vec::with_capacity(8192) })
    });

    let mut events = player.get_player_event_channel();
    let event_bridge = bridge;
    tokio::spawn(async move {
        while let Some(event) = events.recv().await {
            match event {
                PlayerEvent::Playing { position_ms, .. } => event_bridge.emit("playing", position_ms as i64),
                PlayerEvent::Paused { position_ms, .. } => event_bridge.emit("paused", position_ms as i64),
                PlayerEvent::Seeked { position_ms, .. } => event_bridge.emit("seeked", position_ms as i64),
                PlayerEvent::Stopped { .. } => event_bridge.emit("stopped", 0),
                PlayerEvent::TrackChanged { audio_item } => {
                    event_bridge.emit(&format!("track_info:{}", track_json(&audio_item)), 0);
                    event_bridge.emit("track_changed", 0);
                }
                PlayerEvent::VolumeChanged { volume } => event_bridge.emit("volume_changed", volume as i64),
                PlayerEvent::ShuffleChanged { .. } => event_bridge.emit("shuffle_changed", 0),
                PlayerEvent::RepeatChanged { .. } => event_bridge.emit("repeat_changed", 0),
                PlayerEvent::SessionConnected { .. } => event_bridge.emit("session_connected", 0),
                _ => {}
            }
        }
    });

    let connect_config = ConnectConfig {
        name: settings.name.clone(),
        device_type: DeviceType::Computer,
        initial_volume: settings.initial_volume,
        ..ConnectConfig::default()
    };

    let mut failures = 0u32;
    loop {
        if session.is_invalid() {
            session = Session::new(session_config.clone(), cache.clone());
            player.set_session(session.clone());
        }
        let started = tokio::select! {
            started = Spirc::new(connect_config.clone(), session.clone(), credentials.clone(), player.clone(), mixer.clone()) => started,
            _ = &mut stop => return,
        };
        let (spirc, task) = match started {
            Ok(pair) => pair,
            Err(_) => {
                failures += 1;
                bridge.emit("reconnecting", failures as i64);
                if failures > 6 {
                    bridge.emit("failed", 0);
                    return;
                }
                tokio::select! {
                    _ = tokio::time::sleep(Duration::from_secs(2u64.pow(failures.min(5)))) => continue,
                    _ = &mut stop => return,
                }
            }
        };
        failures = 0;
        let spirc = Arc::new(spirc);
        publish(Some(spirc.clone()));
        bridge.emit("running", 0);
        tokio::pin!(task);
        tokio::select! {
            _ = &mut task => {
                publish(None);
                bridge.emit("reconnecting", 0);
                if !session.is_invalid() {
                    session.shutdown();
                }
                tokio::select! {
                    _ = tokio::time::sleep(Duration::from_secs(1)) => {}
                    _ = &mut stop => return,
                }
            }
            _ = &mut stop => {
                publish(None);
                let _ = spirc.shutdown();
                let _ = tokio::time::timeout(Duration::from_secs(2), &mut task).await;
                return;
            }
        }
    }
}
