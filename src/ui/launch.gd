class_name Launch
extends RefCounted
## Game modes + MatchCfg builder (port of src/screens/Setup.tsx MODES / buildLaunch / pickOpp).
## Launch dict passed to Nav.go("match", launch):
##   {cfg: MatchCfg, teams: [teamDict, teamDict], names: [String, String], mode: String, stage: int}
## MatchCfg keys (SPEC): field, ball, forms[2], ai, ai_lvl, limit, match_time, turn_time, vip[2], first,
##   stats[2] ({power, accuracy}), teams[2] (team ids).
## Result screen (GAME) can rebuild with Launch.build(mode, Store.p, {lvl, rule, tt, opp, stage}).

static func modes() -> Array:
	return [
		{"k": "quick", "img": "portal_gamepad", "name": "بازی سریع", "en": "QUICK MATCH", "desc": "یک مسابقه‌ی فوری مقابل هوش مصنوعی", "reward": "سکه، XP و جام", "color": Color("#4fe3ff"), "grad": "primary"},
		{"k": "cup", "img": "portal_globe", "name": "جام نکسورا", "en": "NEXORA CUP", "desc": "سه حریف پشت سر هم تا فینال؛ هر مرحله سخت‌تر", "reward": "۲ برابر جایزه + ۲۰ الماس قهرمانی", "color": NX.GOLD, "grad": "gold"},
		{"k": "galaxy", "img": "portal_galaxy", "name": "چالش کهکشانی", "en": "GALAXY CHALLENGE", "desc": "دو دقیقه مقابل ربات افسانه‌ای", "reward": "۳ برابر جایزه", "color": NX.VIOLET, "grad": "violet"},
		{"k": "local", "img": "portal_friends", "name": "دو نفره", "en": "LOCAL 2 PLAYER", "desc": "با دوستت روی یک گوشی بازی کن", "reward": "فقط برای افتخار", "color": Color("#3dffa8"), "grad": "green"},
		{"k": "train", "img": "portal_brain", "name": "تمرین", "en": "TRAINING", "desc": "بدون تایمر، ربات آسان، برای گرم کردن دست", "reward": "XP کم، بدون جام", "color": NX.SKY, "grad": "primary"},
	]

static func mode(k: String) -> Dictionary:
	for m in modes():
		if m["k"] == k:
			return m
	return modes()[0]

static func pool() -> Array:
	return UD.teams().filter(func(t): return t["cat"] in ["club", "nat", "elite"])

static func pick_opp() -> Dictionary:
	var p := pool()
	return p[randi() % p.size()]

static func boosted(t: Dictionary) -> bool:
	return t["cat"] == "vip" or t["cat"] == "leg"

## opt: {lvl: 0..2, rule: "g3"|"g5"|"t3", tt: int, opp: teamDict, stage: int}
static func build(mode_k: String, p: Dictionary, opt: Dictionary) -> Dictionary:
	if UD.has("Data", "build_launch"):
		var r = UD.node("Data").build_launch(mode_k, p, opt)
		if r is Dictionary and r.has("cfg"):
			return r
	var me := UD.team_by_id(str(p.get("team", "club0")))
	var opp: Dictionary = opt.get("opp", pick_opp())
	var opp_form := randi() % UD.forms().size()
	var ai := mode_k != "local"
	var lvl := int(opt.get("lvl", 1))
	var rule := str(opt.get("rule", "g3"))
	var limit := 5 if rule == "g5" else 3
	var match_time := 180 if rule == "t3" else 0
	var tt := int(opt.get("tt", 15))
	var stage := int(opt.get("stage", 0))
	if mode_k == "cup":
		lvl = mini(2, stage)
		limit = 3
		match_time = 0
	if mode_k == "galaxy":
		lvl = 2
		match_time = 120
		limit = 99
	if mode_k == "train":
		lvl = 0
		tt = 0
	var form := int(p.get("form", 0))
	var cfg := {
		"field": int(p.get("field", 0)), "ball": int(p.get("ball", 0)),
		"forms": [form, opp_form if ai else form],
		"ai": ai, "ai_lvl": lvl, "limit": limit, "match_time": match_time, "turn_time": tt,
		"vip": [boosted(me), boosted(opp)], "first": 0,
		"stats": [UD.disc_stats(me["id"]), UD.disc_stats(opp["id"])],
		"teams": [me["id"], opp["id"]],
	}
	return {"cfg": cfg, "teams": [me, opp], "names": [str(p.get("name", "Pilot")), opp["name"] if ai else "بازیکن ۲"], "mode": mode_k, "stage": stage}
