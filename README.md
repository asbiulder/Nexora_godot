# NEXORA — Godot 4.5

بازنویسی NEXORA (بازی آنلاین موبایل) با **Godot 4.5.1** و GDScript.
A rewrite of NEXORA (online mobile game) in **Godot 4.5.1** / GDScript. The binding design contract for every part of the code is [`SPEC.md`](SPEC.md).

---

## فارسی

### اجرا روی کامپیوتر
1. Godot **4.5.1** (نسخه‌ی معمولی، نه Mono) را نصب کنید.
2. پوشه‌ی پروژه را در Godot باز کنید (`project.godot`) و F5 بزنید.
   یا از خط فرمان: `godot --path . ` ‏(بار اول: `godot --headless --import`).
3. چت صوتی روی کامپیوتر غیرفعال است («چت صوتی فقط روی اندروید»)؛ بقیه‌ی بازی، آفلاین و آنلاین، کار می‌کند.

### ساخت APK اندروید (پیشنهادی: GitHub Actions)
- هر push روی شاخه‌ی `main` (یا اجرای دستی «Run workflow») فایل `.github/workflows/android.yml` را اجرا می‌کند که:
  1. پلاگین اندروید LiveKit را از `plugin_src/livekit` با Gradle می‌سازد (AAR) و در `android/plugins/nexora_livekit/` کپی می‌کند؛
  2. Godot 4.5.1 و قالب‌های خروجی را دانلود می‌کند، قالب ساخت اندروید (gradle) را نصب می‌کند؛
  3. یک keystore دیباگ می‌سازد و APK نسخه‌ی release (فقط arm64-v8a) را خروجی می‌گیرد؛
  4. APK را به‌صورت Artifact و یک GitHub Release با برچسب `build-<شماره>` منتشر می‌کند.
- برای امضای واقعی، این Secretها را در مخزن تعریف کنید (اختیاری): `ANDROID_KEYSTORE_BASE64` (فایل keystore به base64)، `ANDROID_KEYSTORE_USER` (alias)، `ANDROID_KEYSTORE_PASSWORD`. بدون آن‌ها APK با keystore دیباگ امضا می‌شود (فقط برای تست).
- نصب روی گوشی: APK را از بخش Releases دانلود کنید و «نصب برنامه‌های ناشناس» را مجاز کنید.

### ساخت APK روی کامپیوتر خودتان
1. JDK 17، Android SDK (platform 35، build-tools 35.0.0) و Gradle 8.7 به بالا.
2. ساخت پلاگین: `cd plugin_src/livekit && gradle assembleRelease` و کپی
   `build/outputs/aar/nexora-livekit-release.aar` به `android/plugins/nexora_livekit/`.
3. در Godot: Editor Settings → Export → Android: مسیر SDK و Java را تنظیم کنید؛ Project → Install Android Build Template؛
   Project Settings → Plugins: افزونه‌ی **NexoraLiveKit** را فعال کنید؛ سپس Project → Export → Android.

### چت صوتی
- سرور صدا LiveKit است؛ توکن از تابع Supabase به نام `livekit-token` گرفته می‌شود (Secretهای `LIVEKIT_URL` و `LIVEKIT_KEYS` در Supabase).
- خطاها: «چت صوتی هنوز فعال نشده» (سرور تنظیم نشده/503)، «برای چت صوتی باید داخل اتاق باشی» (403)، «اتصال به سرور صدا ناموفق بود».
- مجوز میکروفون هنگام ورود به چت صوتی درخواست می‌شود؛ اگر رد شود، کاربر فقط شنونده است.

---

## English

### Run on desktop
1. Install Godot **4.5.1** (standard, not .NET).
2. Open `project.godot` in the editor and press F5, or `godot --path .` (first time: `godot --headless --import`).
3. Voice chat is Android-only; on desktop `Voice.supported()` is `false` and the UI shows the Persian reason. Everything else works.

### Android APK via GitHub Actions (recommended)
`.github/workflows/android.yml` runs on every push to `main` and on manual dispatch:
1. builds the LiveKit plugin AAR from `plugin_src/livekit` (Gradle, AGP 8.6.1, Kotlin 2.1.20) and copies it to `android/plugins/nexora_livekit/`;
2. downloads Godot 4.5.1 (linux x86_64) + the Android parts of the export templates (cached), writes `~/.config/godot/editor_settings-4.5.tres` (SDK, Java, debug keystore);
3. enables the `NexoraLiveKit` editor plugin if `project.godot` doesn't already, stamps `version/code` with the run number, imports, runs headless tests (non-blocking), then `godot --headless --install-android-build-template --export-release "Android" build/NEXORA.apk`;
4. uploads the APK as an artifact and publishes a GitHub Release `build-<run_number>`.

Release signing: set repo secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_USER`, `ANDROID_KEYSTORE_PASSWORD`. Without them the release APK is signed with a CI-generated debug keystore (testing only; a new key each run, so uninstall before installing a newer build).

### Local Android export
JDK 17, Android SDK (platform 35, build-tools 35.0.0), Gradle ≥ 8.7. Build the AAR (`cd plugin_src/livekit && gradle assembleRelease`), copy it into `android/plugins/nexora_livekit/`, set the SDK/Java paths in Editor Settings → Export → Android, Project → Install Android Build Template, enable the **NexoraLiveKit** plugin in Project Settings → Plugins, then export the "Android" preset (Gradle build is on — it is required for the plugin).

### Tests
- `godot --headless -s res://tests/bot_match.gd` — 20 AI-vs-AI matches.
- `godot --headless -s res://tests/voice_smoke.gd` — Voice autoload off-Android behaviour.

---

## What's where / ساختار پروژه

| Path | What |
|---|---|
| `SPEC.md` | Shared contract (autoloads, APIs, owners) |
| `project.godot`, `export_presets.cfg` | Project settings; Android preset `com.nexora.game`, min SDK 24, target 35, arm64-v8a, gradle build |
| `assets/` | Fonts (Orbitron, Exo2, Vazirmatn) and game art (`assets/g/**`, same names as the RN app) |
| `src/core/` | Autoloads `Data`, `Store`, `Sfx`, `Nav` |
| `src/game/` | `NxEngine` physics/AI port, `MatchView` renderer |
| `src/screens/`, `src/ui/` | Offline screens, UI kit (`Kit`, `NX` theme), main shell |
| `src/net/` | `Supa` (Supabase REST/Auth/Realtime), `RoomLink`, `Voice` (`voice.gd`) |
| `src/online/`, `src/social/`, `src/oracle/` | Online screens, social, oracle |
| `addons/nexora_livekit/` | Editor/export plugin: adds the AAR, `io.livekit:livekit-android` + coroutines, and the JitPack repo to Gradle exports |
| `android/plugins/nexora_livekit/` | Where the built `nexora-livekit-release.aar` goes (git-ignored, CI builds it) |
| `plugin_src/livekit/` | Kotlin Android library: Godot v2 plugin `NexoraLiveKit` wrapping LiveKit |
| `tests/` | Headless tests (excluded from export) |
| `.github/workflows/android.yml` | CI: AAR → Godot export → APK artifact + Release |

### Voice plugin interface
`Engine.get_singleton("NexoraLiveKit")` — methods `connect(url, token, publish)` (alias `connectRoom`), `setMic(on)`, `setSpeaker(on)`, `disconnect()` (alias `disconnectRoom`); signals `state(String)` (`connecting|on|off|error`), `speakers(String)` (JSON array of identities), `error(String)` (`mic:` prefix = only the microphone failed).
GDScript must not call `plugin.connect(...)` / `plugin.disconnect()` directly (they collide with `Object.connect/disconnect`); `voice.gd` uses `callv("connectRoom", ...)` and `Signal(plugin, "state").connect(...)`.

Pinned versions: Godot 4.5.1, `org.godotengine:godot:4.5.1.stable` (compileOnly), `io.livekit:livekit-android:2.30.0`, `kotlinx-coroutines-android:1.9.0`, AGP 8.6.1, Kotlin 2.1.20, Gradle 8.11.1, compile/target SDK 35, min SDK 24.

---

## Android signing & CI outputs (updated)
- **Sideload-testing key (committed on purpose):** `android/keys/nexora-release.keystore` (alias `nexora`, password in `.github/workflows/android.yml` → `NX_KEYSTORE_PASSWORD`). Every CI build is signed with this same key, so a newer APK installs over an older one. **This key is public — for sideload testing only.** Before publishing on Google Play, create a private keystore and set the repo secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_USER`, `ANDROID_KEYSTORE_PASSWORD` (they take precedence), and remove the committed key.
- کلید امضای داخل مخزن فقط برای تست (نصب دستی) است؛ قبل از انتشار در گوگل‌پلی، keystore خصوصی بسازید و در Secretهای مخزن بگذارید.
- Each run publishes a Release `v2.0.<run>` with `NEXORA-v2.0.<run>-universal.apk` (armeabi-v7a, arm64-v8a, x86, x86_64), `NEXORA-v2.0.<run>-arm64.apk` and `NEXORA-v2.0.<run>.aab`, after an Android-emulator smoke test (API 30 gating, API 24 best-effort): install, launch, menu, then a quick match via `--nx-start=quickmatch`; logcat + screenshots are uploaded as artifacts.
- CI-only tweaks (`.github/scripts/ci_prepare.py`): lossy WebP textures, compressed native libs, excludes `tests/ shots/ plugin_src/ *.md`.
