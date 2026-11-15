extends SceneTree
## physics-v2 headless probe. Measures the numbers asked for in the physics-v2 brief, for any engine model,
## so old (nx8) and new (pv2) can be compared side by side.
## Run: godot --headless --path . -s res://tests/phys_v2_probe.gd -- pv2      (or -- nx8)
## All runs step the engine at exactly 1/240 s (one fixed physics step per update) on field 0.

const EngineS := preload("res://src/game/engine.gd")
var model := "pv2"
var fails := 0

func _initialize() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0: model = ua[0]
	var e0 = _eng()
	print("MODEL=", model, " disc r=", e0.bodies[0].r, " ball r=", e0.ball.r, " disc m=", 1.0 / e0.bodies[0].im, " ball m=", 1.0 / e0.ball.im,
		" pitch W=", e0.Fr - e0.Fl, " L=", e0.Fb - e0.Ft)
	for pw in [1.0, 0.5]: _shot_case(pw, 0.0)
	_shot_case(1.0, 0.5)    # cut shot: ball offset by half a disc radius sideways
	_corner_cases()
	_rest_jitter()
	_spin_case()
	_determinism()
	print("PROBE_DONE fails=", fails)
	quit(1 if fails > 0 else 0)

func _eng(extra := {}):
	var cfg := {"seed": 7, "turn_time": 0, "forms": [0, 0], "field": 0}
	if model != "": cfg["model"] = model
	for k in extra: cfg[k] = extra[k]
	return EngineS.new(cfg)

func _only(e, keep: Array) -> void:
	var nb: Array = []
	for b in e.bodies:
		if keep.has(b): nb.append(b)
	e.bodies = nb

func _place(b, x: float, y: float) -> void:
	b.x = x; b.y = y; b.px = x; b.py = y; b.vx = 0.0; b.vy = 0.0

func _sp(b) -> float: return sqrt(b.vx * b.vx + b.vy * b.vy)

func _step(e) -> void:
	e.update(EngineS.STEP)

## disc full / half shot straight at a resting ball
func _shot_case(pw: float, off: float) -> void:
	var e = _eng()
	var d = e.bodies[0]
	_only(e, [d, e.ball])
	var x: float = e.Fl + 200.0
	_place(e.ball, x + off * d.r, e.CY)
	_place(d, x, e.CY + d.r + e.ball.r + 220.0)
	e.turn = 0; e.phase = "aim"
	e.fire(d, 0.0, -pw * e.LMAX, pw * e.LMAX, false)
	var t := 0.0
	var hit_t := -1.0
	var pre := 0.0
	var post := 0.0
	var dpath := 0.0
	var bpath := 0.0
	var hit_pos := Vector2.ZERO
	var dstop := -1.0
	var bstop := -1.0
	var ball_launch := 0.0
	var walls := 0
	var lastd := Vector2(d.x, d.y)
	var lastb := Vector2(e.ball.x, e.ball.y)
	var maxjump := 0.0     # largest per-step change of the disc's speed after contact (smoothness)
	var prevds := _sp(d)
	while t < 20.0:
		if hit_t < 0: pre = _sp(d)
		_step(e); t += EngineS.STEP
		for ev in e.events:
			if ev.t == "wall": walls += 1
		e.events.clear()
		if hit_t < 0 and _sp(e.ball) > 0:
			hit_t = t; post = _sp(d); hit_pos = Vector2(d.x, d.y); ball_launch = _sp(e.ball)
			lastd = Vector2(d.x, d.y); lastb = Vector2(e.ball.x, e.ball.y); prevds = post
		if hit_t >= 0:
			dpath += Vector2(d.x, d.y).distance_to(lastd); lastd = Vector2(d.x, d.y)
			bpath += Vector2(e.ball.x, e.ball.y).distance_to(lastb); lastb = Vector2(e.ball.x, e.ball.y)
			ball_launch = maxf(ball_launch, _sp(e.ball)) if t - hit_t < 0.02 else ball_launch
			if t - hit_t > 0.02: maxjump = maxf(maxjump, absf(_sp(d) - prevds))
			prevds = _sp(d)
			if dstop < 0 and _sp(d) == 0: dstop = t - hit_t
			if bstop < 0 and _sp(e.ball) == 0: bstop = t - hit_t
			if dstop >= 0 and bstop >= 0: break
		if e.phase == "goal": break
	print("SHOT p=%.1f off=%.1f | disc pre %.0f -> post %.0f px/s (keeps %.0f%%) | disc travel after contact %.1f px (%.2f disc radii), stops %.2fs | ball launch %.0f px/s (%.2fx disc), ball path %.0f px (%.2f pitch L), ball stops %.2fs, wall hits %d | disc max dv/step after contact %.1f px/s%s" % [
		pw, off, pre, post, 100.0 * post / maxf(1, pre), dpath, dpath / d.r, dstop, ball_launch, ball_launch / maxf(1, pre), bpath, bpath / (e.Fb - e.Ft), bstop, walls, maxjump,
		" (goal scored, stopped early)" if e.phase == "goal" else ""])

## ball (no discs) driven into the top-left corner at several angles; also a ball parked in the corner and a disc
## shot that drives the ball into the corner. Reports how it comes out of the corner.
func _corner_cases() -> void:
	for deg in [45.0, 30.0, 60.0, 15.0]:
		var e = _eng()
		_only(e, [e.ball])
		var b = e.ball
		var a := deg_to_rad(deg)    # angle from the goal line (0 = travelling along the goal line toward the side wall)
		var ux := -cos(a)
		var uy := -sin(a)
		# start so the straight path ends exactly in the corner
		var cx: float = e.Fl + b.r
		var cy: float = e.Ft + b.r
		_place(b, cx - ux * 400.0, cy - uy * 400.0)
		b.vx = ux * 1500.0; b.vy = uy * 1500.0
		e.phase = "move"
		_corner_report(e, "CORNER %2.0fdeg v=1500" % deg)
	# parked in the corner, nudged by nothing: must not stay stuck if pushed in by a disc
	var e2 = _eng()
	var d = e2.bodies[0]
	_only(e2, [d, e2.ball])
	var b2 = e2.ball
	_place(b2, e2.Fl + b2.r + 2.0, e2.Ft + b2.r + 2.0)
	var dir := Vector2(-1, -1).normalized()
	_place(d, b2.x - dir.x * (d.r + b2.r + 150.0), b2.y - dir.y * (d.r + b2.r + 150.0))
	e2.turn = 0; e2.phase = "aim"
	e2.fire(d, dir.x * e2.LMAX, dir.y * e2.LMAX, e2.LMAX, false)
	_corner_report(e2, "CORNER disc full shot diagonally into a ball parked in the corner", d)

func _corner_report(e, label: String, disc = null) -> void:
	var b = e.ball
	var t := 0.0
	var touched := false
	var out_v := Vector2.ZERO
	var out_t := -1.0
	var in_speed := 0.0
	var zone_t := 0.0
	while t < 12.0:
		var pre := Vector2(b.vx, b.vy)
		_step(e); t += EngineS.STEP
		e.events.clear()
		var nearx: bool = b.x - b.r < e.Fl + 2.5 * b.r
		var neary: bool = b.y - b.r < e.Ft + 2.5 * b.r
		if nearx and neary: zone_t += EngineS.STEP
		if not touched and ((pre.x < 0.0 and b.vx >= 0.0 and b.x - b.r < e.Fl + 3.0) or (pre.y < 0.0 and b.vy >= 0.0 and b.y - b.r < e.Ft + 3.0)):
			touched = true; in_speed = pre.length()
		if touched and out_t < 0 and not (nearx and neary):
			out_t = t; out_v = Vector2(b.vx, b.vy)
		if out_t >= 0 and t - out_t > 0.05: break
		if _sp(b) == 0 and (disc == null or _sp(disc) == 0) and t > 0.2: break
	var s := out_v.length()
	var ang := rad_to_deg(atan2(absf(out_v.x), absf(out_v.y))) if s > 0 else -1.0   # 0 = straight along the side wall
	var dirn := "none"
	if s > 0:
		if out_v.y > 0 and absf(out_v.x) < absf(out_v.y) * 0.58: dirn = "down along side wall"
		elif out_v.x > 0 and absf(out_v.y) < absf(out_v.x) * 0.58: dirn = "along goal line"
		else: dirn = "diagonal back out"
	var stuck: bool = out_t < 0 and b.x - b.r < e.Fl + 2.5 * b.r and b.y - b.r < e.Ft + 2.5 * b.r
	if stuck: fails += 1
	print("%s | in %.0f px/s -> out %.0f px/s (%.0f%%) %s, %.0f deg off the side wall | time in corner zone %.2fs | end: ball gap to side wall %.0f px, to goal line %.0f px | stuck=%s" % [
		label, in_speed, s, 100.0 * s / maxf(1, in_speed), dirn, ang, zone_t, b.x - b.r - e.Fl, b.y - b.r - e.Ft, str(stuck)])

## kickoff formation left alone for 3 s plus a tight cluster of 3 touching discs: any drift = jitter
func _rest_jitter() -> void:
	var e = _eng()
	var start := []
	for b in e.bodies: start.append(Vector2(b.x, b.y))
	e.phase = "move"
	for i in 720: _step(e)
	var mx := 0.0
	for i in e.bodies.size(): mx = maxf(mx, start[i].distance_to(Vector2(e.bodies[i].x, e.bodies[i].y)))
	# cluster: three discs overlapping by 1.5 px each, at rest
	var e2 = _eng()
	var ds := [e2.bodies[0], e2.bodies[1], e2.bodies[2]]
	_only(e2, ds + [e2.ball])
	_place(e2.ball, e2.Fr - 100, e2.Fb - 100)
	var r: float = ds[0].r
	_place(ds[0], e2.CX, e2.CY)
	_place(ds[1], e2.CX + 2 * r - 1.5, e2.CY)
	_place(ds[2], e2.CX + r - 0.75, e2.CY - (2 * r - 1.5) * 0.866)
	e2.phase = "move"
	var s2 := []
	for b in ds: s2.append(Vector2(b.x, b.y))
	var vmax := 0.0
	var settle := -1.0
	for i in 960:
		_step(e2)
		var m := 0.0
		for b in ds: m = maxf(m, _sp(b))
		vmax = maxf(vmax, m)
		if settle < 0 and m == 0 and i > 2: settle = (i + 1) * EngineS.STEP
	var mv := 0.0
	for i in 3: mv = maxf(mv, s2[i].distance_to(Vector2(ds[i].x, ds[i].y)))
	print("REST kickoff drift over 3s %.3f px | overlapping 3-disc cluster: separation moved %.2f px, peak speed %.1f px/s, at rest after %.3fs" % [mx, mv, vmax, settle])

## visual ball spin: angular rate of the ball's rotation matrix vs its speed
func _spin_case() -> void:
	for v in [300.0, 800.0, 1600.0, 2600.0]:
		var e = _eng()
		_only(e, [e.ball])
		var b = e.ball
		_place(b, e.CX - 250, e.Fb - 60)
		b.vx = 0.0; b.vy = -v
		e.phase = "move"
		var wmax := 0.0
		var spd_at := 0.0
		var prevR: PackedFloat64Array = b.R
		for i in 24:
			_step(e)
			var R: PackedFloat64Array = b.R
			# relative rotation angle between prevR and R: cos th = (trace(R * prevR^T) - 1) / 2
			var tr := 0.0
			for rr in 3:
				for cc in 3: tr += R[rr * 3 + cc] * prevR[rr * 3 + cc]
			var th := acos(clampf((tr - 1.0) / 2.0, -1.0, 1.0))
			var w := th / EngineS.STEP
			if w > wmax: wmax = w; spd_at = _sp(b)
			prevR = R
		print("SPIN ball %.0f px/s: visual roll %.1f rad/s (%.2f rev/s); pure rolling v/r would be %.1f rad/s" % [v, wmax, wmax / TAU, spd_at / b.r])

## same seed, same frame times -> identical state (bitwise) after 40 s of AI vs AI
func _determinism() -> void:
	var hs := []
	for k in 2:
		var e = _eng({"ai": true, "ai_lvl": 2, "seed": 99, "limit": 99})
		e.ai_teams = [true, true]
		for i in 2400: e.update(1.0 / 60.0)
		var h := 0
		var acc := ""
		for b in e.bodies: acc += "%.9f,%.9f,%.9f,%.9f;" % [b.x, b.y, b.vx, b.vy]
		h = acc.hash()
		hs.append([h, e.shots, e.score.duplicate()])
	var same: bool = hs[0][0] == hs[1][0]
	if not same: fails += 1
	print("DETERMINISM two identical 40s AI runs: state hash ", hs[0][0], " vs ", hs[1][0], " identical=", same, " shots=", hs[0][1], " score=", hs[0][2])
