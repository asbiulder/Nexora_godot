@tool
extends EditorExportPlugin
## Godot 4.2+ "v2" Android plugin packaging for NexoraLiveKit.
## - ships the plugin AAR built from plugin_src/livekit (CI copies it into AAR_DIR)
## - declares the maven dependencies the AAR needs (a local AAR carries no POM)
## - adds JitPack, where io.livekit:livekit-android resolves com.github.davidliu:audioswitch
## Requires "Use Gradle Build" in the Android export preset.

const PLUGIN_NAME := "NexoraLiveKit"
const AAR_DIR := "res://android/plugins/nexora_livekit/"
const AAR_RELEASE := AAR_DIR + "nexora-livekit-release.aar"
const AAR_DEBUG := AAR_DIR + "nexora-livekit-debug.aar"

# Keep in sync with plugin_src/livekit/build.gradle.kts.
const LIVEKIT_VERSION := "2.30.0"
const COROUTINES_VERSION := "1.9.0"
const DEPENDENCIES: PackedStringArray = [
	"io.livekit:livekit-android:" + LIVEKIT_VERSION,
	"org.jetbrains.kotlinx:kotlinx-coroutines-android:" + COROUTINES_VERSION,
]
const MAVEN_REPOS: PackedStringArray = ["https://jitpack.io"]


func _get_name() -> String:
	return PLUGIN_NAME


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _aar(debug: bool) -> String:
	# A debug AAR is optional; the release AAR works for both variants.
	if debug and FileAccess.file_exists(AAR_DEBUG):
		return AAR_DEBUG
	return AAR_RELEASE


func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	var path := _aar(debug)
	if not FileAccess.file_exists(path):
		push_warning("NexoraLiveKit: %s is missing — build plugin_src/livekit (gradle assembleRelease) and copy the AAR there. Voice chat will be unavailable." % path)
		return PackedStringArray()
	return PackedStringArray([path])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not FileAccess.file_exists(_aar(_debug)):
		return PackedStringArray()
	return DEPENDENCIES


func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return MAVEN_REPOS
