#!/bin/bash
# Install + launch the APK on the running emulator, collect logcat + screenshots, fail on a crash.
# usage: emu_test.sh <apk> <outdir>
set -u
APK="$1"; OUT="$2"; PKG=com.nexora.game
mkdir -p "$OUT"
adb wait-for-device
adb shell getprop ro.build.version.sdk | tee "$OUT/sdk.txt"
adb shell getprop ro.product.cpu.abilist | tee -a "$OUT/sdk.txt"
adb logcat -c || true
echo "== install"
adb install -r "$APK" 2>&1 | tee "$OUT/install.txt"
if ! grep -q Success "$OUT/install.txt"; then echo "::error::adb install failed"; adb logcat -d > "$OUT/logcat.txt"; exit 1; fi
adb shell dumpsys package $PKG | grep -E "versionCode|versionName|primaryCpuAbi|flags=" | tee "$OUT/package.txt"
echo "== launch"
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1
sleep 4;  adb exec-out screencap -p > "$OUT/screen_04s.png" || true
sleep 6;  adb exec-out screencap -p > "$OUT/screen_10s.png" || true
P1=$(adb shell pidof $PKG | tr -d '\r'); echo "pid@10s=$P1"
# tap the centre once (intro screens often wait for a tap), then wait
adb shell input tap 540 1600 || true
sleep 8;  adb exec-out screencap -p > "$OUT/screen_18s.png" || true
sleep 10; adb exec-out screencap -p > "$OUT/screen_28s.png" || true
P2=$(adb shell pidof $PKG | tr -d '\r'); echo "pid@28s=$P2"
adb shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity|ResumedActivity" | tee "$OUT/activity.txt" || true
adb logcat -d -v threadtime > "$OUT/logcat.txt"
adb logcat -d -b crash > "$OUT/logcat_crash.txt" 2>/dev/null || true
echo "================ filtered logcat ================"
grep -E -i "godot|nexora|AndroidRuntime|FATAL|DEBUG +:|libc +:|SIGSEGV|SIGABRT|livekit|ActivityManager.*(nexora|Process)|SCRIPT ERROR|USER ERROR|Parse Error|OpenGL|GLES|vulkan|crash" "$OUT/logcat.txt" | grep -v -E "chatty" | tail -n 600
echo "================ crash buffer ================"
cat "$OUT/logcat_crash.txt" | tail -n 200
fail=0
[ -z "$P2" ] && { echo "::error::process $PKG is not running after 28 s"; fail=1; }
grep -q "FATAL EXCEPTION" "$OUT/logcat.txt" && { echo "::error::FATAL EXCEPTION in logcat"; fail=1; }
grep -E -q "Fatal signal|SIGSEGV|SIGABRT" "$OUT/logcat.txt" && { echo "::error::native crash signal in logcat"; fail=1; }
grep -E -q "SCRIPT ERROR|Parse Error|USER ERROR" "$OUT/logcat.txt" && { echo "::error::Godot script/user errors in logcat (see above)"; fail=1; }
exit $fail
