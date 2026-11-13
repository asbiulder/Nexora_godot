class_name RtChannel
extends RefCounted
## Supabase Realtime channel (Phoenix protocol vsn 1.0.0) + the websocket manager (RtChannel.Socket).
##
##   var ch := Supa.channel("room:" + id, {broadcast = {self = false, ack = false}, presence = {key = uid}})
##   ch.on_postgres("*", "public", "rooms", "id=eq." + id, func(c): ...)   # before subscribe()
##   ch.on_broadcast("chat", func(payload): ...)
##   ch.on_presence(func(state): ...)       # state = {key: [ {presence_ref, ...meta}, ... ]}
##   ch.subscribe(func(status): ...)        # "SUBSCRIBED" | "CHANNEL_ERROR" | "TIMED_OUT" | "CLOSED"
##   ch.send_broadcast("chat", {...}); ch.track({name = "x"}); ch.untrack(); Supa.remove_channel(ch)
##
## Statuses repeat: after a network drop the channel reports CHANNEL_ERROR, then SUBSCRIBED again
## once the socket reconnects and the channel rejoins (like supabase-js).

signal status_changed(status: String)
signal broadcast(event: String, payload: Variant)
signal presence_sync(state: Dictionary)
signal postgres_change(change: Dictionary)
signal system_message(payload: Dictionary)

const JOIN_TIMEOUT := 10.0
const REJOIN_BACKOFF := [1.0, 2.0, 5.0, 10.0]
const BUFFER_MAX := 64
const BUFFER_TTL := 5.0

var name: String
var topic: String
var opts: Dictionary
var status := "CLOSED"      # last reported status
var state := "closed"       # closed | joining | joined | leaving | errored
var last_error := ""
var socket: Socket

var _want := false
var _join_ref := ""
var _join_push_ref := ""
var _join_sent_at := 0.0
var _rejoin_at := 0.0
var _tries := 0
var _status_cb: Callable
var _bcast := {}            # event -> Array[Callable]
var _pg: Array = []         # {event, schema, table, filter, cb, id}
var _pres_cbs: Array = []   # sync callbacks
var _pres_join_cbs: Array = []
var _pres_leave_cbs: Array = []
var _sys_cbs: Array = []
var _pres_raw := {}         # key -> Array of metas (with phx_ref)
var _tracked: Variant = null
var _buf: Array = []        # [time, event, payload] pushes queued while not joined

func _init(sock: Socket, name_: String, opts_: Dictionary) -> void:
	socket = sock
	name = name_
	topic = "realtime:" + name_
	opts = opts_

# ------------------------------------------------------------------ public API
func on_broadcast(event: String, cb: Callable) -> RtChannel:
	if not _bcast.has(event):
		_bcast[event] = []
	_bcast[event].append(cb)
	return self

## event: "*" | "INSERT" | "UPDATE" | "DELETE"; filter like "id=eq.<uuid>" or "" ; cb(change) with
## change = {eventType, schema, table, commit_timestamp, new, old, errors}
func on_postgres(event: String, schema: String, table: String, filter: String, cb: Callable) -> RtChannel:
	_pg.append({"event": event, "schema": schema, "table": table, "filter": filter, "cb": cb, "id": -1})
	if state == "joined" or state == "joining":
		_rejoin_now()   # postgres bindings are part of the join config
	return self

## cb(state) on every presence sync; state = {key: [ {presence_ref, ...meta} ]}
func on_presence(cb: Callable) -> RtChannel:
	_pres_cbs.append(cb)
	return self

## cb(key, current_presences, new_presences)
func on_presence_join(cb: Callable) -> RtChannel:
	_pres_join_cbs.append(cb)
	return self

## cb(key, current_presences, left_presences)
func on_presence_leave(cb: Callable) -> RtChannel:
	_pres_leave_cbs.append(cb)
	return self

func on_system(cb: Callable) -> RtChannel:
	_sys_cbs.append(cb)
	return self

func subscribe(cb: Callable = Callable()) -> RtChannel:
	_status_cb = cb
	if _want:
		return self
	_want = true
	_tries = 0
	socket._add(self)
	if socket.is_open():
		_join()
	return self

func unsubscribe() -> void:
	if not _want and state == "closed":
		return
	_want = false
	if socket.is_open() and (state == "joined" or state == "joining"):
		socket._push(topic, "phx_leave", {}, socket._make_ref(), _join_ref)
	state = "closed"
	_pres_raw.clear()
	_buf.clear()
	_set_status("CLOSED")
	socket._remove(self)

## Send a broadcast. Returns false when it could not be sent or queued.
func send_broadcast(event: String, payload: Variant) -> bool:
	return _send({"type": "broadcast", "event": event, "payload": payload})

func track(meta: Dictionary) -> bool:
	_tracked = meta
	return _send({"type": "presence", "event": "track", "payload": meta})

func untrack() -> bool:
	_tracked = null
	return _send({"type": "presence", "event": "untrack"})

## supabase-js presenceState(): {key: [ {presence_ref, ...meta} ]}
func presence_state() -> Dictionary:
	var out := {}
	for k in _pres_raw:
		var arr: Array = []
		for m in _pres_raw[k]:
			arr.append(_strip_meta(m))
		out[k] = arr
	return out

func is_joined() -> bool:
	return state == "joined"

# ------------------------------------------------------------------ internals
func _send(payload: Dictionary) -> bool:
	if not _want:
		return false
	if state == "joined" and socket.is_open():
		return socket._push(topic, payload.type, payload, socket._make_ref(), _join_ref)
	# queue until joined (dropped when stale)
	if _buf.size() >= BUFFER_MAX:
		_buf.pop_front()
	_buf.append([socket.now(), payload])
	return true

func _join_payload() -> Dictionary:
	var b: Dictionary = opts.get("broadcast", {})
	var p: Dictionary = opts.get("presence", {})
	var pgs: Array = []
	for x in _pg:
		var d := {"event": x.event, "schema": x.schema, "table": x.table}
		if x.filter != "":
			d["filter"] = x.filter
		pgs.append(d)
	var cfg := {
		"broadcast": {"ack": bool(b.get("ack", false)), "self": bool(b.get("self", false))},
		"presence": {"key": str(p.get("key", "")), "enabled": p.has("key") or not _pres_cbs.is_empty()},
		"postgres_changes": pgs,
		"private": bool(opts.get("private", false)),
	}
	var out := {"config": cfg}
	var tok := socket.token
	if tok != "":
		out["access_token"] = tok
	return out

func _join() -> void:
	if not _want or not socket.is_open():
		return
	_join_push_ref = socket._make_ref()
	_join_ref = _join_push_ref
	_join_sent_at = socket.now()
	state = "joining"
	socket._push(topic, "phx_join", _join_payload(), _join_push_ref, _join_ref)

func _rejoin_now() -> void:
	if not _want:
		return
	if socket.is_open() and state == "joined":
		socket._push(topic, "phx_leave", {}, socket._make_ref(), _join_ref)
	state = "errored"
	_rejoin_at = socket.now()

func _schedule_rejoin() -> void:
	state = "errored"
	_rejoin_at = socket.now() + REJOIN_BACKOFF[min(_tries, REJOIN_BACKOFF.size() - 1)]
	_tries += 1

func _tick(now: float) -> void:
	if not _want or not socket.is_open():
		return
	if state == "joining" and now - _join_sent_at > JOIN_TIMEOUT:
		last_error = "join timeout"
		_set_status("TIMED_OUT")
		_schedule_rejoin()
	elif (state == "errored" or state == "closed") and now >= _rejoin_at:
		_join()

func _on_socket_open() -> void:
	if _want and state != "joining":
		_join()

func _on_socket_close() -> void:
	if not _want:
		return
	var was := state
	state = "errored"
	_rejoin_at = 0.0
	_pres_raw.clear()
	if was == "joined" or was == "joining":
		last_error = "socket closed"
		_set_status("CHANNEL_ERROR")

func _set_status(s: String) -> void:
	status = s
	if _status_cb.is_valid():
		_status_cb.call(s)
	status_changed.emit(s)

func _on_message(event: String, payload: Variant, ref: String, join_ref: String) -> void:
	# lifecycle events from an older join are ignored (same rule as supabase-js isMember)
	if event in ["phx_close", "phx_error", "phx_reply"] and join_ref != "" and join_ref != _join_ref:
		return
	match event:
		"phx_reply":
			if ref == _join_push_ref and state == "joining":
				_on_join_reply(payload)
		"phx_close":
			if state != "closed" and _want:
				last_error = "closed by server"
				_pres_raw.clear()
				_set_status("CLOSED")
				_schedule_rejoin()
		"phx_error":
			if _want:
				last_error = "channel error"
				_pres_raw.clear()
				_set_status("CHANNEL_ERROR")
				_schedule_rejoin()
		"broadcast":
			if payload is Dictionary:
				var ev := str(payload.get("event", ""))
				var pl: Variant = payload.get("payload")
				broadcast.emit(ev, pl)
				for k in [ev, "*"]:
					if _bcast.has(k):
						for cb in _bcast[k]:
							if cb.is_valid():
								cb.call(pl)
		"presence_state":
			if payload is Dictionary:
				_presence_state(payload)
		"presence_diff":
			if payload is Dictionary:
				_presence_diff(payload)
		"postgres_changes":
			if payload is Dictionary:
				_postgres(payload)
		"system":
			if payload is Dictionary:
				system_message.emit(payload)
				for cb in _sys_cbs:
					if cb.is_valid():
						cb.call(payload)
				if str(payload.get("status", "")) == "error":
					last_error = str(payload.get("message", "system error"))

func _on_join_reply(payload: Variant) -> void:
	var st := str(payload.get("status", "")) if payload is Dictionary else ""
	if st != "ok":
		var bad: Variant = payload.get("response") if payload is Dictionary else null
		last_error = str(bad.get("reason", bad)) if bad is Dictionary else str(bad)
		_set_status("CHANNEL_ERROR")
		_schedule_rejoin()
		return
	var resp: Dictionary = payload.get("response", {}) if payload.get("response") is Dictionary else {}
	var srv: Array = resp.get("postgres_changes", []) if resp.get("postgres_changes") is Array else []
	for i in _pg.size():
		_pg[i].id = int(srv[i].get("id", -1)) if i < srv.size() and srv[i] is Dictionary else -1
	state = "joined"
	_tries = 0
	last_error = ""
	_set_status("SUBSCRIBED")
	# flush queued pushes (drop stale ones)
	var now := socket.now()
	var q := _buf
	_buf = []
	for it in q:
		if now - float(it[0]) <= BUFFER_TTL and state == "joined":
			socket._push(topic, it[1].type, it[1], socket._make_ref(), _join_ref)

func _postgres(payload: Dictionary) -> void:
	var data: Dictionary = payload.get("data", {}) if payload.get("data") is Dictionary else {}
	var ids: Array = payload.get("ids", []) if payload.get("ids") is Array else []
	var type := str(data.get("type", data.get("eventType", "")))
	var ch := {
		"eventType": type, "schema": data.get("schema", ""), "table": data.get("table", ""),
		"commit_timestamp": data.get("commit_timestamp", ""), "errors": data.get("errors"),
		"new": data.get("record", {}) if data.get("record") is Dictionary else {},
		"old": data.get("old_record", {}) if data.get("old_record") is Dictionary else {},
	}
	postgres_change.emit(ch)
	for b in _pg:
		var hit := false
		if b.id >= 0 and not ids.is_empty():
			for x in ids:
				if int(x) == b.id:
					hit = true
					break
		else:
			hit = (b.event == "*" or b.event == type) and b.schema == str(ch.schema) and b.table == str(ch.table)
		if hit and b.event != "*" and b.event != type:
			hit = false
		if hit and b.cb.is_valid():
			b.cb.call(ch)

func _strip_meta(m: Variant) -> Dictionary:
	var d: Dictionary = (m as Dictionary).duplicate() if m is Dictionary else {}
	if d.has("phx_ref"):
		d["presence_ref"] = d.phx_ref
		d.erase("phx_ref")
	d.erase("phx_ref_prev")
	return d

func _metas(v: Variant) -> Array:
	if v is Dictionary and v.get("metas") is Array:
		return v.metas
	return []

func _presence_state(payload: Dictionary) -> void:
	var old := _pres_raw
	_pres_raw = {}
	for k in payload:
		_pres_raw[k] = _metas(payload[k]).duplicate()
	for k in _pres_raw:
		if not old.has(k):
			_emit_pres(_pres_join_cbs, k, _pres_raw[k], _pres_raw[k])
	for k in old:
		if not _pres_raw.has(k):
			_emit_pres(_pres_leave_cbs, k, [], old[k])
	_emit_sync()

func _presence_diff(payload: Dictionary) -> void:
	var joins: Dictionary = payload.get("joins", {}) if payload.get("joins") is Dictionary else {}
	var leaves: Dictionary = payload.get("leaves", {}) if payload.get("leaves") is Dictionary else {}
	for k in joins:
		var nm := _metas(joins[k])
		var cur: Array = _pres_raw.get(k, [])
		var refs := {}
		for m in nm:
			if m is Dictionary:
				refs[str(m.get("phx_ref", ""))] = true
		var kept: Array = []
		for m in cur:
			if m is Dictionary and not refs.has(str(m.get("phx_ref", ""))):
				kept.append(m)
		kept.append_array(nm)
		_pres_raw[k] = kept
		_emit_pres(_pres_join_cbs, k, kept, nm)
	for k in leaves:
		if not _pres_raw.has(k):
			continue
		var lm := _metas(leaves[k])
		var refs := {}
		for m in lm:
			if m is Dictionary:
				refs[str(m.get("phx_ref", ""))] = true
		var kept: Array = []
		for m in _pres_raw[k]:
			if m is Dictionary and not refs.has(str(m.get("phx_ref", ""))):
				kept.append(m)
		if kept.is_empty():
			_pres_raw.erase(k)
		else:
			_pres_raw[k] = kept
		_emit_pres(_pres_leave_cbs, k, kept, lm)
	_emit_sync()

func _emit_pres(cbs: Array, k: String, cur: Array, delta: Array) -> void:
	if cbs.is_empty():
		return
	var c: Array = []
	for m in cur:
		c.append(_strip_meta(m))
	var d: Array = []
	for m in delta:
		d.append(_strip_meta(m))
	for cb in cbs:
		if cb.is_valid():
			cb.call(k, c, d)

func _emit_sync() -> void:
	var st := presence_state()
	presence_sync.emit(st)
	for cb in _pres_cbs:
		if cb.is_valid():
			cb.call(st)


# ====================================================================== socket manager
## One websocket to Supabase Realtime. Polled by Supa._process(). Connects lazily when a channel
## subscribes, disconnects when the last channel leaves. Heartbeat 25 s, reconnect with backoff.
class Socket extends RefCounted:
	const HEARTBEAT := 25.0
	const RECONNECT := [1.0, 2.0, 5.0, 10.0]
	const CONNECT_TIMEOUT := 12.0

	signal opened
	signal closed(code: int, reason: String)

	var endpoint: String
	var key: String
	var token := ""
	var ws: WebSocketPeer = null
	var channels: Array = []
	var connected := false       # websocket OPEN
	var tries := 0
	var _ref := 0
	var _hb_at := 0.0
	var _hb_ref := ""
	var _retry_at := 0.0
	var _open_started := 0.0

	func _init(url: String, key_: String) -> void:
		key = key_
		endpoint = url.replace("https://", "wss://").replace("http://", "ws://") + "/realtime/v1/websocket?apikey=" + key_ + "&vsn=1.0.0&log_level=error"

	func now() -> float:
		return Time.get_ticks_msec() / 1000.0

	func is_open() -> bool:
		return connected

	func _make_ref() -> String:
		_ref += 1
		return str(_ref)

	## new access token: remember it and push it to every joined channel
	func set_auth(t: String) -> void:
		if t == token:
			return
		token = t
		if connected:
			for ch in channels:
				if ch.state == "joined":
					_push(ch.topic, "access_token", {"access_token": t if t != "" else key}, _make_ref(), ch._join_ref)

	func channel(name_: String, opts: Dictionary = {}) -> RtChannel:
		return RtChannel.new(self, name_, opts)

	## after app resume: reconnect immediately if we are waiting on a backoff
	func wake() -> void:
		if ws == null and not channels.is_empty():
			_retry_at = 0.0
		elif connected:
			_hb_at = 0.0   # heartbeat right away to detect a dead socket

	func _add(ch: RtChannel) -> void:
		if not channels.has(ch):
			channels.append(ch)
		if ws == null:
			_retry_at = 0.0

	func _remove(ch: RtChannel) -> void:
		channels.erase(ch)
		if channels.is_empty():
			disconnect_socket()

	func disconnect_socket() -> void:
		if ws:
			ws.close(1000, "bye")
		ws = null
		connected = false
		_hb_ref = ""

	func _open() -> void:
		ws = WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 21
		ws.outbound_buffer_size = 1 << 20
		ws.max_queued_packets = 4096
		ws.heartbeat_interval = 0.0
		var err := ws.connect_to_url(endpoint)
		_open_started = now()
		if err != OK:
			ws = null
			_retry_at = now() + RECONNECT[min(tries, RECONNECT.size() - 1)]
			tries += 1

	func poll() -> void:
		var t := now()
		if ws == null:
			if not channels.is_empty() and t >= _retry_at:
				_open()
			return
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			if not connected:
				connected = true
				tries = 0
				_hb_ref = ""
				_hb_at = t + HEARTBEAT
				opened.emit()
				for ch in channels.duplicate():
					ch._on_socket_open()
			while ws != null and ws.get_available_packet_count() > 0:
				var pkt := ws.get_packet()
				_on_text(pkt.get_string_from_utf8())
			if ws == null:
				return
			if t >= _hb_at:
				if _hb_ref != "":
					# previous heartbeat never answered → socket is dead
					ws.close(1000, "heartbeat timeout")
					_on_closed(1000, "heartbeat timeout")
					return
				_hb_ref = _make_ref()
				_push("phoenix", "heartbeat", {}, _hb_ref, "")
				_hb_at = t + HEARTBEAT
			for ch in channels.duplicate():
				ch._tick(t)
		elif st == WebSocketPeer.STATE_CONNECTING:
			if t - _open_started > CONNECT_TIMEOUT:
				ws.close()
				_on_closed(-1, "connect timeout")
		elif st == WebSocketPeer.STATE_CLOSED:
			_on_closed(ws.get_close_code(), ws.get_close_reason())

	func _on_closed(code: int, reason: String) -> void:
		var was := connected
		ws = null
		connected = false
		_hb_ref = ""
		_retry_at = now() + RECONNECT[min(tries, RECONNECT.size() - 1)]
		tries += 1
		if was:
			closed.emit(code, reason)
		for ch in channels.duplicate():
			ch._on_socket_close()

	func _push(topic: String, event: String, payload: Variant, ref: String, join_ref: String) -> bool:
		if ws == null or not connected:
			return false
		var msg := {"topic": topic, "event": event, "payload": payload, "ref": ref}
		if join_ref != "":
			msg["join_ref"] = join_ref
		return ws.send_text(JSON.stringify(msg)) == OK

	func _on_text(s: String) -> void:
		var m: Variant = JSON.parse_string(s)
		if not (m is Dictionary):
			return
		var topic := str(m.get("topic", ""))
		var event := str(m.get("event", ""))
		var ref := str(m.get("ref", "")) if m.get("ref") != null else ""
		var jref := str(m.get("join_ref", "")) if m.get("join_ref") != null else ""
		if topic == "phoenix":
			if event == "phx_reply" and ref == _hb_ref:
				_hb_ref = ""
			return
		for ch in channels.duplicate():
			if ch.topic == topic:
				ch._on_message(event, m.get("payload"), ref, jref)
