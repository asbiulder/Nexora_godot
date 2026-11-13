extends Node
## Sound + haptics — port of src/sound.ts. Autoload name: Sfx.
## Sfx.play(key, vol) one-shots (pooled, 45 ms rate limit except goal), Sfx.play_goal() goal stinger,
## Sfx.crowd(on) loop, Sfx.haptic(kind), Sfx.apply_prefs() (reads Store.p).
##
## Background music (the main-menu track) policy:
##  - plays ONLY in the main-menu shell (scene "menu": home/team/play/shop/profile tabs and the offline
##    screens opened from them);
##  - fully STOPPED (player.stop(), not paused/ducked) in every online screen (hub, lobby, rooms,
##    online match/result, tournaments, social…), in matches and the intro, and while voice chat is
##    connected / the mic is on / anyone is speaking;
##  - resumes (from where it stopped) only when the user is back in the main menu.
## The scene follows Nav.screen_changed automatically; screens never need to manage it. The legacy
## calls music(on) / menu_music(on) / set_scene(s) still work (menu_music(false) = user/intro mute).

# key: [file, volume, pool size]
const MAP := {
	"ui": ["select.wav", 0.55, 2], "hitb": ["hit_ball.wav", 0.9, 3], "hitp": ["hit_piece.mp3", 0.7, 3], "goal": ["goal.wav", 1.0, 2],
	"post": ["ballHitsThePost.mp3", 0.8, 1], "roar": ["goalHappened-01.mp3", 0.7, 1], "whistle": ["startWistle.mp3", 0.8, 1],
	"final": ["gameIsFinishedWistle.mp3", 0.8, 1], "wall": ["BallHit-01.mp3", 0.55, 2], "crowd": ["crowd-03.mp3", 0.25, 1],
	"music": ["music.mp3", 0.35, 1], "ready": ["nx_ready.mp3", 0.7, 1], "chat": ["nx_chat.mp3", 0.55, 2], "join": ["nx_join.mp3", 0.6, 1],
	"leave": ["nx_leave.mp3", 0.5, 1], "win": ["nx_win.mp3", 0.8, 1], "lose": ["nx_lose.mp3", 0.75, 1], "tick": ["nx_tick.mp3", 0.45, 2],
	# main-menu background track (user-provided menu_music.mp3; falls back to music.mp3 when absent)
	"menu": ["menu_music.mp3", 0.35, 1],
}
const LOOPS := ["music", "crowd", "menu"]
const DIR := "res://assets/g/sfx/"
## screens where music is allowed (main-menu shell); online / match screens always stop it
const MENU_SCREENS := ["home", "team", "play", "shop", "profile", "settings", "setup", "daily", "chest", "result", "account"]
const ONLINE_SCREENS := ["hub", "lobby", "ranks", "tournaments", "challenges", "online_result", "arena", "online_match",
	"social", "chat", "club", "public_profile", "oracle"]
const SILENT_SCREENS := ["match", "online_match", "intro"]
const GOAL_DUCK_S := 2.2

var enabled := {"sound": true, "music": true, "haptics": true, "volume": 1.0}
var scene := "menu"           # menu | room (= online) | match
var screen := ""              # last Nav screen
var menu_on := true           # menu_music(on): false while the intro / user switched it off for a screen
var _pools := {}              # key -> {list:[AudioStreamPlayer], i:int}
var _last := {}               # key -> msec
var _voices := {}             # voice ids active (livekit session, speaking, external)
var _music_pos := 0.0         # resume position of the menu track
var _crowd_duck_until := 0    # msec: crowd lowered while the goal stinger plays

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in MAP:
		var file: String = MAP[k][0]
		var path := DIR + file
		if k == "menu" and not ResourceLoader.exists(path): path = DIR + "music.mp3"
		if not ResourceLoader.exists(path):
			push_warning("Sfx: missing " + path)
			continue
		var st = load(path)
		if st == null:
			push_warning("Sfx: cannot load " + path)
			continue
		if k in LOOPS:
			st = st.duplicate()
			if "loop" in st: st.loop = true
			if st is AudioStreamWAV: st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var list: Array = []
		for i in int(MAP[k][2]):
			var pl := AudioStreamPlayer.new()
			pl.name = "%s_%d" % [k, i]
			pl.stream = st
			pl.bus = &"Master"
			pl.volume_db = linear_to_db(float(MAP[k][1]))
			pl.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(pl)
			list.append(pl)
		_pools[k] = {"list": list, "i": 0}
	var st_node = get_node_or_null("/root/Store")
	if st_node and st_node.has_signal("changed"): st_node.changed.connect(apply_prefs)
	call_deferred("_hook_voice")
	call_deferred("_hook_nav")
	call_deferred("apply_prefs")

func _process(_dt: float) -> void:
	if _crowd_duck_until > 0 and Time.get_ticks_msec() >= _crowd_duck_until:
		_crowd_duck_until = 0
		_crowd_volume()

# ---------------------------------------------------------------- hooks
func _hook_voice() -> void:
	var v = get_node_or_null("/root/Voice")
	if v == null: return
	if v.has_signal("state_changed") and not v.state_changed.is_connected(_on_voice_state):
		v.state_changed.connect(_on_voice_state)
	elif v.has_signal("active"):
		v.active.connect(func(on: bool): set_voice_active("livekit", on))
	if v.get("state") is Dictionary: _on_voice_state(v.state)

## Voice.state → music off while connecting/connected, mic on, or anybody speaking
func _on_voice_state(st: Dictionary) -> void:
	var s := str(st.get("status", "off"))
	set_voice_active("livekit", s == "on" or s == "connecting" or bool(st.get("mic", false)))
	var sp: Variant = st.get("speaking")
	set_speaking(sp is Array and not (sp as Array).is_empty())

func _hook_nav() -> void:
	var n = get_node_or_null("/root/Nav")
	if n and n.has_signal("screen_changed") and not n.screen_changed.is_connected(on_screen):
		n.screen_changed.connect(on_screen)
		if str(n.get("current")) != "": on_screen(str(n.current))

## Called on every Nav screen change (also callable directly).
func on_screen(name: String) -> void:
	screen = name
	if name in SILENT_SCREENS: scene = "match" if name != "intro" else "intro"
	elif name in ONLINE_SCREENS: scene = "room"
	elif name in ["home", "team", "play", "shop", "profile"]: scene = "menu"
	# other screens (result, account, sheets, modals) keep the scene they were opened from
	_apply_music()

func apply_prefs() -> void:
	var st = get_node_or_null("/root/Store")
	if st == null or not (st.get("p") is Dictionary) or st.p.is_empty(): return
	var p: Dictionary = st.p
	enabled = {"sound": bool(p.get("sound", true)), "music": bool(p.get("music", true)), "haptics": bool(p.get("haptics", true)), "volume": clampf(float(p.get("volume", 1.0)), 0.0, 1.0)}
	_crowd_volume()
	_apply_music()

func _player(k: String) -> AudioStreamPlayer:
	var pool = _pools.get(k)
	if pool == null or pool.list.is_empty(): return null
	return pool.list[0]

# ---------------------------------------------------------------- one-shots
func play(k: String, vol := 1.0) -> void:
	if k == "goal":
		play_goal()
		return
	if k == "roar" and Time.get_ticks_msec() - int(_last.get("roar_skip", -100000)) < 150:
		return   # the goal stinger plays its own roar
	_play(k, vol)

func _play(k: String, vol := 1.0) -> bool:
	if not enabled.sound or enabled.volume <= 0: return false
	var pool = _pools.get(k)
	if pool == null or pool.list.is_empty(): return false
	var now := Time.get_ticks_msec()
	if k != "goal" and now - int(_last.get(k, -100000)) < 45: return false
	_last[k] = now
	var pl: AudioStreamPlayer = pool.list[pool.i]
	pool.i = (pool.i + 1) % pool.list.size()
	pl.volume_db = linear_to_db(maxf(0.0001, minf(1.0, float(MAP[k][1]) * maxf(0.15, vol) * enabled.volume)))
	pl.stop()
	pl.play(0.0)
	return true

## Goal stinger: goal horn at full level + crowd roar a beat later, crowd loop ducked so it is heard.
## Safe to call twice for the same goal within 150 ms (second call ignored). Old code that also calls
## play("roar") right after play("goal") is handled (that roar is skipped, the stinger plays its own).
func play_goal() -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last.get("goal", -100000)) < 150: return
	if not _play("goal", 1.0): return
	_last["roar_skip"] = now
	_crowd_duck_until = now + int(GOAL_DUCK_S * 1000)
	_crowd_volume()
	get_tree().create_timer(0.12, true, false, true).timeout.connect(func() -> void:
		_last.erase("roar")
		_play("roar", 1.0))

# ---------------------------------------------------------------- loops
func crowd(on: bool) -> void:
	var pl := _player("crowd")
	if pl == null: return
	if on:
		_crowd_volume()
		if enabled.sound and enabled.volume > 0 and not pl.playing: pl.play()
	else: pl.stop()

func _crowd_volume() -> void:
	var cr := _player("crowd")
	if cr == null: return
	var duck := 0.35 if _crowd_duck_until > 0 else 1.0
	cr.volume_db = linear_to_db(maxf(0.0001, float(MAP.crowd[1]) * enabled.volume * duck))

## legacy: background music on/off. It never starts music outside the main menu.
func music(on: bool) -> void: menu_music(on)

func menu_music(on: bool) -> void:
	menu_on = on
	_apply_music()

func set_scene(s: String) -> void:
	if s == "ui": s = "menu"
	if scene == s: return
	scene = s
	_apply_music()

## true while voice is active for `id` (Voice is hooked automatically; others may add their own ids)
func set_voice_active(id: String, on: bool) -> void:
	var had := _voices.has(id)
	if on: _voices[id] = true
	else: _voices.erase(id)
	if had != on: _apply_music()

## anybody speaking in voice chat (Voice.state.speaking non-empty) → music off
func set_speaking(on: bool) -> void:
	set_voice_active("speaking", on)

func music_allowed() -> bool:
	return menu_on and enabled.sound and enabled.music and enabled.volume > 0 and scene == "menu" and _voices.is_empty()

func _apply_music() -> void:
	var pl := _player("menu")
	if pl == null: return
	if not music_allowed():
		if pl.playing:
			_music_pos = pl.get_playback_position()
			pl.stop()
		pl.stream_paused = false
		return
	pl.volume_db = linear_to_db(maxf(0.0001, float(MAP.menu[1]) * enabled.volume))
	pl.stream_paused = false
	if not pl.playing:
		var len_s: float = pl.stream.get_length() if pl.stream else 0.0
		pl.play(_music_pos if _music_pos < len_s - 1.0 else 0.0)

func music_playing() -> bool:
	var pl := _player("menu")
	return pl != null and pl.playing

func audio_state() -> Dictionary: return {"scene": scene, "screen": screen, "voice": not _voices.is_empty(), "music": music_playing()}

# ---------------------------------------------------------------- haptics
func haptic(kind := "light") -> void:
	if not enabled.haptics: return
	if not (OS.has_feature("android") or OS.has_feature("ios")): return
	match kind:
		"heavy": Input.vibrate_handheld(55, 1.0)
		"medium": Input.vibrate_handheld(30, 0.7)
		"success": Input.vibrate_handheld(45, 0.8)
		_: Input.vibrate_handheld(15, 0.4)
