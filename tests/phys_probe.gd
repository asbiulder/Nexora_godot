extends SceneTree
## Headless physics probe: measures shot travel distance / time / peak speed for discs and the ball.
## Run: godot --headless --path . -s res://tests/phys_probe.gd

const D := preload("res://src/core/data.gd")
const EngineS := preload("res://src/game/engine.gd")

func _mk_engine():
	var e = EngineS.new({"seed": 1, "turn_time": 0, "forms": [0, 0]})
	return e

func _clear_except(e, keep: Array) -> void:
	var nb: Array = []
	for b in e.bodies:
		if keep.has(b): nb.append(b)
	e.bodies = nb

func _run_until_stop(e, watch: Array, max_t := 12.0) -> Dictionary:
	var t := 0.0
	var peak := {}
	var start := {}
	var stop_t := {}
	var path := {}
	for b in watch:
		peak[b] = 0.0; start[b] = Vector2(b.x, b.y); stop_t[b] = -1.0; path[b] = 0.0
	var last := {}
	for b in watch: last[b] = Vector2(b.x, b.y)
	var max_step := 0.0
	while t < max_t:
		e.update(1.0 / 60.0); t += 1.0 / 60.0
		var all_stop := true
		for b in watch:
			var sp := sqrt(b.vx * b.vx + b.vy * b.vy)
			peak[b] = maxf(peak[b], sp)
			var p := Vector2(b.x, b.y)
			var stepd: float = p.distance_to(last[b])
			path[b] += stepd
			if b == e.ball: max_step = maxf(max_step, stepd)
			last[b] = p
			if sp > 0: all_stop = false; stop_t[b] = -1.0
			elif stop_t[b] < 0: stop_t[b] = t
		if all_stop and t > 0.1: break
	var out := {}
	for b in watch:
		out[b] = {"path": snappedf(path[b], 0.1), "disp": snappedf(start[b].distance_to(Vector2(b.x, b.y)), 0.1), "t": snappedf(stop_t[b], 0.01), "peak": snappedf(peak[b], 0.1)}
	out["ball_max_px_per_frame"] = snappedf(max_step, 0.1)
	return out

func _initialize() -> void:
	var e0 = _mk_engine()
	print("PR=", EngineS.PR, " BR=", EngineS.BR, " pitch W=", e0.Fr - e0.Fl, " L=", e0.Fb - e0.Ft)
	_kickoff_check()
	# A: free disc shot, full and half power, straight up the left channel
	for pw in [1.0, 0.5, 0.25]:
		var e = _mk_engine()
		var d = null
		for b in e.bodies:
			if b != e.ball and b.team == 0: d = b; break
		_clear_except(e, [d, e.ball])
		e.ball.x = e.Fr - 60; e.ball.y = e.Ft + 300
		d.x = e.Fl + 120; d.y = e.Fb - 150; d.px = d.x; d.py = d.y
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -1.0 * pw * e.LMAX, pw * e.LMAX, true)
		var r := _run_until_stop(e, [d])
		print("FREE_DISC p=", pw, " ", r[d])
	# B: disc hits ball head-on at full and half power
	for pw in [1.0, 0.5, 0.25]:
		var e = _mk_engine()
		var d = null
		for b in e.bodies:
			if b != e.ball and b.team == 0: d = b; break
		_clear_except(e, [d, e.ball])
		var bx: float = e.Fl + 200.0
		d.x = bx; d.y = e.Fb - 120; d.px = d.x; d.py = d.y
		e.ball.x = bx; e.ball.y = d.y - d.r - e.ball.r - 60; e.ball.px = e.ball.x; e.ball.py = e.ball.y
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -pw * e.LMAX, pw * e.LMAX, true)
		var r := _run_until_stop(e, [d, e.ball])
		var walls := 0
		for ev in e.events:
			if ev.t == "wall": walls += 1
		print("DISC->BALL p=", pw, " ball_walls=", walls, " disc ", r[d], " ball ", r[e.ball], " maxstep ", r["ball_max_px_per_frame"])
	for gapk in [0.7, 0.4]:
		_gap_case(gapk)
	_open_case()
	_aim_case()
	quit(0)

func _open(e) -> void:
	# remove the walls (pitch "infinitely" large) to measure pure glide distance / time
	e.Fl = -1e6; e.Fr = 1e6; e.Ft = -1e6; e.Fb = 1e6
	for g in e.goals: g.y = 1e6 * (-1 if g.d < 0 else 1); g.x1 = -10.0; g.x2 = 10.0

func _open_case() -> void:
	var L := 1323.0
	for pw in [1.0, 0.5, 0.25]:
		var e = _mk_engine()
		var d = null
		for b in e.bodies:
			if b != e.ball and b.team == 0: d = b; break
		_clear_except(e, [d])
		_open(e)
		d.x = 0; d.y = 0; d.px = 0; d.py = 0
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -pw * e.LMAX, pw * e.LMAX, true)
		var r := _run_until_stop(e, [d])
		print("OPEN_DISC p=", pw, " ", r[d], " = ", snappedf(r[d].path / L, 0.01), " L")
	for pw in [1.0, 0.5, 0.25]:
		var e = _mk_engine()
		var d = null
		for b in e.bodies:
			if b != e.ball and b.team == 0: d = b; break
		_clear_except(e, [d, e.ball])
		_open(e)
		d.x = 0; d.y = 0; d.px = 0; d.py = 0
		e.ball.x = 0; e.ball.y = -(d.r + e.ball.r + 60); e.ball.px = e.ball.x; e.ball.py = e.ball.y
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -pw * e.LMAX, pw * e.LMAX, true)
		var r := _run_until_stop(e, [d, e.ball])
		print("OPEN_DISC->BALL p=", pw, " ball ", r[e.ball], " = ", snappedf(r[e.ball].path / L, 0.01), " L")

func _kickoff_check() -> void:
	# formations x kickoff: min clearance ball<->disc and disc<->disc (negative = overlap)
	var worst_b := 1e9
	var worst_d := 1e9
	for fi in D.FORMS.size():
		for kt in 2:
			var e = EngineS.new({"seed": 1, "turn_time": 0, "forms": [fi, fi], "first": kt})
			for i in e.bodies.size():
				for j in range(i + 1, e.bodies.size()):
					var a = e.bodies[i]
					var b = e.bodies[j]
					var cl: float = Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) - a.r - b.r
					if a == e.ball or b == e.ball: worst_b = minf(worst_b, cl)
					else: worst_d = minf(worst_d, cl)
	print("KICKOFF forms=", D.FORMS.size(), " min ball-disc clearance=", snappedf(worst_b, 0.1), " min disc-disc clearance=", snappedf(worst_d, 0.1))

func _gap_case(gapk: float) -> void:
	# C: ball driven hard into a 2-disc wall with a gap of 1.2 ball diameters: does it split / pass?
	var e = _mk_engine()
	var mine: Array = []
	var opp: Array = []
	for b in e.bodies:
		if b == e.ball: continue
		if b.team == 0: mine.append(b)
		else: opp.append(b)
	var sh = mine[0]
	var w1 = opp[0]
	var w2 = opp[1]
	_clear_except(e, [sh, w1, w2, e.ball])
	var cx: float = e.Fl + 250.0
	var gap: float = e.ball.r * 2.0 * float(gapk)
	w1.x = cx - gap / 2 - w1.r; w2.x = cx + gap / 2 + w2.r; w1.y = e.CY; w2.y = e.CY
	e.ball.x = cx; e.ball.y = e.CY + 260
	sh.x = cx; sh.y = e.ball.y + sh.r + e.ball.r + 40
	for b in e.bodies: b.px = b.x; b.py = b.y
	e.turn = 0; e.phase = "aim"
	e.fire(sh, 0.0, -e.LMAX, e.LMAX, true)
	var r := _run_until_stop(e, [sh, w1, w2, e.ball])
	print("GAP gap=", snappedf(gap, 0.1), " ball_end_y_rel_wall=", snappedf(e.ball.y - e.CY, 0.1), " passed=", e.ball.y < e.CY - e.ball.r, " w1 moved=", r[w1].disp, " w2 moved=", r[w2].disp, " ball ", r[e.ball])

func _aim_case() -> void:
	# D: aim accuracy: fire at 37 deg with max accuracy stats off/on -> measured direction
	var e2 = EngineS.new({"seed": 7, "turn_time": 0, "forms": [0, 0], "stats": [{"power": 5, "accuracy": 1}, {"power": 5, "accuracy": 1}]})
	var dd = null
	for b in e2.bodies:
		if b != e2.ball and b.team == 0: dd = b; break
	_clear_except(e2, [dd, e2.ball])
	e2.ball.x = e2.Fr - 40; e2.ball.y = e2.Ft + 60
	dd.x = e2.CX; dd.y = e2.CY + 300
	var ang := deg_to_rad(-60.0)
	e2.turn = 0; e2.phase = "aim"
	e2.fire(dd, cos(ang) * 150, sin(ang) * 150, 150, true)
	for i in 3: e2.update(1.0 / 60.0)
	print("AIM requested=-60.0 got=", snappedf(rad_to_deg(atan2(dd.vy, dd.vx)), 0.01))
