extends Node
## Sound + haptics — port of src/sound.ts. Autoload name: Sfx.
## Sfx.play(key, vol) one-shots (pooled, 45 ms rate limit except "goal"), Sfx.crowd(on) loop,
## background music manager with scenes ("menu" full, "room" ducked, "match" off) + voice pause,
## Sfx.menu_music(on) / Sfx.music(on), Sfx.haptic(kind), Sfx.apply_prefs() (reads Store.p).

# key: [file, volume, pool size]
const MAP := {
	"ui": ["select.wav", 0.55, 2], "hitb": ["hit_ball.wav", 0.9, 3], "hitp": ["hit_piece.mp3", 0.7, 3], "goal": ["goal.wav", 0.9, 1],
	"post": ["ballHitsThePost.mp3", 0.8, 1], "roar": ["goalHappened-01.mp3", 0.7, 1], "whistle": ["startWistle.mp3", 0.8, 1],
	"final": ["gameIsFinishedWistle.mp3", 0.8, 1], "wall": ["BallHit-01.mp3", 0.55, 2], "crowd": ["crowd-03.mp3", 0.25, 1],
	"music": ["music.mp3", 0.35, 1], "ready": ["nx_ready.mp3", 0.7, 1], "chat": ["nx_chat.mp3", 0.55, 2], "join": ["nx_join.mp3", 0.6, 1],
	"leave": ["nx_leave.mp3", 0.5, 1], "win": ["nx_win.mp3", 0.8, 1], "lose": ["nx_lose.mp3", 0.75, 1], "tick": ["nx_tick.mp3", 0.45, 2],
	# main-menu background track (user-provided menu_music.mp3; falls back to music.mp3 when absent)
	"menu": ["menu_music.mp3", 0.35, 1],
}
const LOOPS := ["music", "crowd", "menu"]
const DIR := "res://assets/g/sfx/"
const DUCK := 0.22

var enabled := {"sound": true, "music": true, "haptics": true, "volume": 1.0}
var scene := "menu"           # menu | room | match
var menu_on := true           # Sfx.menu_music(on)
var _pools := {}              # key -> {list:[AudioStreamPlayer], i:int}
var _last := {}               # key -> msec
var _voices := {}             # voice ids active

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in MAP:
		var file: String = MAP[k][0]
		var path := DIR + file
		if k == "menu" and not ResourceLoader.exists(path): path = DIR + "music.mp3"
		if not ResourceLoader.exists(path): continue
		var st = load(path)
		if st == null: continue
		if k in LOOPS:
			st = st.duplicate()
			if "loop" in st: st.loop = true
		var list: Array = []
		for i in int(MAP[k][2]):
			var pl := AudioStreamPlayer.new()
			pl.stream = st
			pl.volume_db = linear_to_db(float(MAP[k][1]))
			add_child(pl)
			list.append(pl)
		_pools[k] = {"list": list, "i": 0}
	var st_node = get_node_or_null("/root/Store")
	if st_node and st_node.has_signal("changed"): st_node.changed.connect(apply_prefs)
	call_deferred("_hook_voice")
	call_deferred("apply_prefs")

func _hook_voice() -> void:
	var v = get_node_or_null("/root/Voice")
	if v and v.has_signal("active"): v.active.connect(func(on: bool): set_voice_active("livekit", on))

func apply_prefs() -> void:
	var st = get_node_or_null("/root/Store")
	if st == null or not (st.get("p") is Dictionary) or st.p.is_empty(): return
	var p: Dictionary = st.p
	enabled = {"sound": bool(p.get("sound", true)), "music": bool(p.get("music", true)), "haptics": bool(p.get("haptics", true)), "volume": clampf(float(p.get("volume", 1.0)), 0.0, 1.0)}
	var cr = _player("crowd")
	if cr: cr.volume_db = linear_to_db(maxf(0.0001, MAP.crowd[1] * enabled.volume))
	_apply_music()

func _player(k: String) -> AudioStreamPlayer:
	var pool = _pools.get(k)
	if pool == null or pool.list.is_empty(): return null
	return pool.list[0]

func play(k: String, vol := 1.0) -> void:
	if not enabled.sound or enabled.volume <= 0: return
	var pool = _pools.get(k)
	if pool == null or pool.list.is_empty(): return
	var now := Time.get_ticks_msec()
	if k != "goal" and now - int(_last.get(k, -100000)) < 45: return
	_last[k] = now
	var pl: AudioStreamPlayer = pool.list[pool.i]
	pool.i = (pool.i + 1) % pool.list.size()
	pl.volume_db = linear_to_db(maxf(0.0001, minf(1.0, float(MAP[k][1]) * maxf(0.15, vol) * enabled.volume)))
	pl.play(0.0)

# ---------- loops ----------
func crowd(on: bool) -> void:
	var pl := _player("crowd")
	if pl == null: return
	if on:
		if enabled.sound and enabled.volume > 0 and not pl.playing: pl.play()
	else: pl.stop()

## background music on/off (the main-menu track); scene still decides ducking / match silence
func music(on: bool) -> void: menu_music(on)

func menu_music(on: bool) -> void:
	menu_on = on
	_apply_music()

func set_scene(s: String) -> void:
	if scene == s: return
	scene = s
	_apply_music()

func set_voice_active(id: String, on: bool) -> void:
	var had := _voices.has(id)
	if on: _voices[id] = true
	else: _voices.erase(id)
	if had != on: _apply_music()

func _apply_music() -> void:
	var pl := _player("menu")
	if pl == null: return
	var want: bool = menu_on and enabled.sound and enabled.music and enabled.volume > 0 and scene != "match" and _voices.is_empty()
	if not want:
		if pl.playing: pl.stream_paused = true
		return
	pl.volume_db = linear_to_db(maxf(0.0001, float(MAP.menu[1]) * enabled.volume * (DUCK if scene == "room" else 1.0)))
	if pl.stream_paused: pl.stream_paused = false
	if not pl.playing: pl.play()

func audio_state() -> Dictionary: return {"scene": scene, "voice": not _voices.is_empty()}

# ---------- haptics ----------
func haptic(kind := "light") -> void:
	if not enabled.haptics: return
	if not (OS.has_feature("android") or OS.has_feature("ios")): return
	match kind:
		"heavy": Input.vibrate_handheld(55, 1.0)
		"medium": Input.vibrate_handheld(30, 0.7)
		"success": Input.vibrate_handheld(45, 0.8)
		_: Input.vibrate_handheld(15, 0.4)
