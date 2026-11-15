// NEXORA deterministic fixed-step physics engine. All profiles use the same
// solver; profile tuning and pitch/goal geometry remain separate. Public
// legacy constants and tuning fields remain for callers and saved content.
import 'dart:math' as math;
import 'dart:typed_data';

import 'data.dart';
import 'fdlibm.dart';
import 'physics_config.dart';

export 'physics_config.dart';

const double K = 1.27;
const double PR = 49;
const double BR = 25.5;
const double RC = 70;
const double LMAX = 210;
const double STEP = 1 / 240;
const double POST_R = 8;
const double HV = 8, PF1 = 430, PF2 = 1.0, PV0 = 520, EPP = .62, PCAP = 190;
const double BK = 1.9, BF = 175, BFV = 140, BVMAX = 1750, BSTOP = 26;
const double PK = 1.55, PFL = 300, PFV = 230, PSTOP = 20;
const double WALL_VOUT = 820, POST_VOUT = 900;

// Profile tuning values use world px, px/s, px/s^2 and 1/s. All profiles
// share the solver below. Historical fields remain available to callers but
// no longer select a separate solver or add non-physical striker impulses.
class PhysTune {
  final String name;
  // ---- bodies ----
  final double discR, ballR; // radii (disc 0.128 x pitch width, ball ~0.07)
  final double discM,
      ballM; // masses: only the ratio matters (impulse split along the normal)
  final double ballSpinMultiplier;
  // ---- shot ----
  final double
  shotMax; // disc launch speed at full drag (LMAX), linear in drag length
  final double discVmax; // cap after power stat / VIP multiplier
  final bool powerGodot; // power-stat curve: true 0.72..1.44 (Godot), false 0.75..1.25 (TS)
  // ---- rolling / sliding friction ----
  final double discFric,
      discDrag; // disc: constant decel (px/s^2) + linear drag (1/s)
  final double ballFric, ballDrag; // ball: same model, lighter
  final double vStop; // a body whose speed falls below this stops
  final double vSettle,
      settleK; // below vSettle friction x settleK (no creeping / jiggle)
  final double vSafe; // numerical safety clamp on any speed
  // ---- contacts (impulse along the line of centres; tangential velocity untouched) ----
  final double eDiscDisc, eDiscBall; // restitution
  final double discDiscK; // fraction of the disc-disc impulse applied (Godot foosball nudge; 1 = true physics)
  final double eSoft, vSoft; // light contacts (normal speed < vSoft) blend from eSoft up to full e: less jitter
  // ---- cushions (walls, goal frame, posts) ----
  final double eWallBall,
      tWallBall; // ball: normal restitution, tangential speed kept
  final double eWallDisc,
      tWallDisc; // disc: normal restitution, tangential speed kept
  final double postR;
  final double
  cornerNudge; // px/s push out of a sharp corner for a still body jammed in it
  // ---- integration / visuals ----
  final double subPx; // max travel per substep (px) -> adaptive substeps
  final int subMax,
      stepCap; // substep cap per 240 Hz step; physics steps per frame
  final double rollK; // visual ball roll rate (render only)
  // ---- friction parameters and legacy compatibility fields ----
  final bool expFric; // select coefficients, not a separate solver
  final double ballK, discK, discFlightK; // 1/s
  final double discFlightMin; // px/s: flight ends below this speed
  final double
  kickGain; // legacy compatibility only; contacts conserve momentum
  final double ballVmax; // cap on ball speed (px/s)
  final double
  subBallFrac; // ball travel per substep < subBallFrac x ball radius
  const PhysTune({
    required this.name,
    required this.discR,
    required this.ballR,
    required this.discM,
    required this.ballM,
    this.ballSpinMultiplier = 1.0,
    required this.shotMax,
    required this.discVmax,
    required this.powerGodot,
    required this.discFric,
    required this.discDrag,
    required this.ballFric,
    required this.ballDrag,
    required this.vStop,
    required this.vSettle,
    required this.settleK,
    required this.vSafe,
    required this.eDiscDisc,
    required this.eDiscBall,
    required this.discDiscK,
    required this.eSoft,
    required this.vSoft,
    required this.eWallBall,
    required this.tWallBall,
    required this.eWallDisc,
    required this.tWallDisc,
    required this.postR,
    required this.cornerNudge,
    required this.subPx,
    required this.subMax,
    required this.stepCap,
    required this.rollK,
    this.expFric = false,
    this.ballK = 0,
    this.discK = 0,
    this.discFlightK = 0,
    this.discFlightMin = 0,
    this.kickGain = 0,
    this.ballVmax = 1e9,
    this.subBallFrac = 1e9,
  });
}

/// 'godot' profile retains its pitch geometry and approximate material tuning.
const kTuneGodot = PhysTune(
  name: 'godot',
  discR: 49,
  ballR: 27,
  discM: 36,
  ballM: 2, // 18:1 foosball discs
  shotMax: 1900,
  discVmax: 2000,
  powerGodot: true,
  discFric: 360,
  discDrag: 0,
  ballFric: 360,
  ballDrag: 0, // same cloth friction for everything
  vStop: 6,
  vSettle: 80,
  settleK: 2,
  vSafe: 4200,
  eDiscDisc: .95,
  eDiscBall: .70,
  discDiscK: .45,
  eSoft: .55,
  vSoft: 240,
  eWallBall: .85,
  tWallBall: .85,
  eWallDisc: .85,
  tWallDisc: .85, // whole vector x .85 (angle in = out)
  postR: 5,
  cornerNudge: 70,
  subPx: 4,
  subMax: 16,
  stepCap: 14,
  rollK: .6,
);

// Classic's historic geometry, masses and approximate feel, in the same units
// as the other profiles. Legacy parity is intentionally not a physics path.
const _classicTune = PhysTune(
  name: 'classic',
  discR: PR,
  ballR: BR,
  discM: 5,
  ballM: 1.5,
  shotMax: (260 + 1085) * K * 1.32,
  discVmax: (260 + 1085) * K * 1.32,
  powerGodot: false,
  discFric: PFL * K,
  discDrag: PK,
  ballFric: BF * K,
  ballDrag: BK,
  vStop: PSTOP * K,
  vSettle: 0,
  settleK: 1,
  vSafe: 4200,
  eDiscDisc: EPP,
  eDiscBall: .62,
  discDiscK: 1,
  eSoft: 0,
  vSoft: 0,
  eWallBall: .60,
  tWallBall: 1,
  eWallDisc: .72,
  tWallDisc: 1,
  postR: POST_R,
  cornerNudge: 0,
  subPx: 4,
  subMax: 24,
  stepCap: 16,
  rollK: .95,
  ballVmax: BVMAX * K,
);

/// 'stars' (DEFAULT): v0.7 - every value comes from PHYSICS_CONFIG (lib/game/physics_config.dart, units of W) and
/// is converted to world px here. History of the v0.6.x values: /workspace/work/godot_vs_flutter_physics.md.
const _C = PHYSICS_CONFIG;
final _W = PHYSICS_CONFIG.wPx;
final kTuneStars = PhysTune(
  name: 'stars',
  discR: _C.puckDiameter / 2 * _W,
  ballR: _C.ballDiameter / 2 * _W,
  discM: _C.massPuck,
  ballM: _C.massBall,
  ballSpinMultiplier: _C.ballSpinMultiplier,
  shotMax: _C.shotMax * _W,
  discVmax: _C.shotMax * _W,
  powerGodot: false,
  discFric: 0,
  discDrag: _C.puckK,
  ballFric: 0,
  ballDrag: _C.ballK, // (legacy fields, informational)
  vStop: _C.stopSpeed * _W,
  vSettle: 0,
  settleK: 1,
  vSafe: _C.maxSpeed * _W,
  eDiscDisc: _C.ePuckPuck,
  eDiscBall: _C.eBallPuck,
  discDiscK: 1,
  eSoft: 1,
  vSoft: 0, // no soft-contact blending: the plain impulse rule (only while approaching, vrel < 0)
  eWallBall: _C.eBallWall,
  tWallBall: _C.tBallWall,
  eWallDisc: _C.ePuckWall,
  tWallDisc: _C.tPuckWall,
  postR: _C.postR * _W,
  cornerNudge:
      0, // v0.7: no corner nudge (it kept pinned bodies moving forever)
  subPx: _C.subTravel * _W,
  subMax: _C.subMax,
  stepCap: _C.stepCap,
  rollK: .75, // calmer visual roll; independent of velocity and collision strength
  expFric: true,
  ballK: _C.ballK,
  discK: _C.puckK,
  discFlightK: _C.puckFlightK,
  discFlightMin: _C.puckFlightMin * _W,
  kickGain: _C.ballKickSpeed / _C.puckShotRef,
  ballVmax: _C.ballMaxSpeed * _W,
  subBallFrac: _C.subBallFrac,
);

/// Nonlinear, monotonic pull response; zero pull has zero launch speed.
double shotCurve(double p) {
  final q = _clamp(p, 0, 1);
  return fpow(q, 1.1); // responsive short flicks; full pull remains exactly 1.0
}

/// Power stat multiplier used by the team screen and all profiles. Values
/// are clamped to 1..10 and share [PhysicsConfig.powerMulAt1].
double statMul(double power) => _starsPowerMul(power);

PhysTune? tuneFor(String profile) => switch (profile) {
  'classic' => null,
  'godot' => kTuneGodot,
  _ => kTuneStars,
};

/// Shot power multiplier from the power stat (1..10): Godot 0.72..1.44, classic 0.75..1.25.
double powerMulGodot(double p) => .72 + (_min(10, _max(1, p)) - 1) / 9 * .72;

/// V8's Math.hypot for two arguments (Kahan-compensated, scaled by the max).
double hyp(double a, double b) {
  if (a.isNaN || b.isNaN) return double.nan;
  final x = a.abs(), y = b.abs();
  final m = x > y ? x : y;
  if (m == double.infinity) return double.infinity;
  if (m == 0) return 0;
  var sum = 0.0, comp = 0.0;
  var n = x / m;
  var summand = n * n - comp;
  var pre = sum + summand;
  comp = (pre - sum) - summand;
  sum = pre;
  n = y / m;
  summand = n * n - comp;
  pre = sum + summand;
  comp = (pre - sum) - summand;
  sum = pre;
  return math.sqrt(sum) * m;
}

/// V8's Math.hypot for three arguments.
double hyp3(double a, double b, double c) {
  final x = a.abs(), y = b.abs(), z = c.abs();
  var m = x > y ? x : y;
  if (z > m) m = z;
  if (m == double.infinity) return double.infinity;
  if (a.isNaN || b.isNaN || c.isNaN) return double.nan;
  if (m == 0) return 0;
  var sum = 0.0, comp = 0.0;
  var n = x / m;
  var summand = n * n - comp;
  var pre = sum + summand;
  comp = (pre - sum) - summand;
  sum = pre;
  n = y / m;
  summand = n * n - comp;
  pre = sum + summand;
  comp = (pre - sum) - summand;
  sum = pre;
  n = z / m;
  summand = n * n - comp;
  pre = sum + summand;
  comp = (pre - sum) - summand;
  sum = pre;
  return math.sqrt(sum) * m;
}

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

/// Math.round semantics of JS (round half up).
int jsRound(double v) => (v + 0.5).floorToDouble().toInt();

class DiscStats {
  final double power, accuracy;
  const DiscStats(this.power, this.accuracy);
  static const def = DiscStats(5, 5);
}

/// Linear power fraction used by the 'stars' profile: stat / 10, clamped to 1..10 (power 1 still moves at 10%).
double powerFrac(double p) => _min(10, _max(1, p)) / 10;

double powerMul(double p) => .75 + (_min(10, _max(1, p)) - 1) / 9 * .5;

/// v0.7 stars: real 1..10 stats from PHYSICS_CONFIG (owner 2026-11-15).
double _starsPowerMul(double p) => !PHYSICS_CONFIG.useDiscStats
    ? 1.0
    : PHYSICS_CONFIG.powerMulAt1 +
          (1 - PHYSICS_CONFIG.powerMulAt1) * (_min(10, _max(1, p)) - 1) / 9;
double _starsAimDevDeg(double a) => !PHYSICS_CONFIG.useDiscStats
    ? 0.0
    : (10 - _min(10, _max(1, a))) / 9 * PHYSICS_CONFIG.accDevAt1Deg;
double aimDevDeg(double a) => (10 - _min(10, _max(1, a))) / 9 * 4;
double aimPreview(double a) => .45 + (_min(10, _max(1, a)) - 1) / 9 * .75;

class MatchCfg {
  int field, ball;
  List<int> forms;
  bool ai;
  int aiLvl;
  int limit;
  double matchTime, turnTime;
  List<bool> vip;
  int first;
  List<DiscStats>? stats;

  /// Gameplay profile: 'stars' (default), 'godot' or 'classic' geometry/tuning.
  String profile;

  MatchCfg({
    required this.field,
    required this.ball,
    required this.forms,
    required this.ai,
    required this.aiLvl,
    required this.limit,
    required this.matchTime,
    required this.turnTime,
    required this.vip,
    required this.first,
    this.stats,
    this.profile = 'stars',
  });
}

class Goal {
  final int team;
  final double y, x1, x2;
  final int d;
  const Goal(this.team, this.y, this.x1, this.x2, this.d);
}

class Body {
  final int id;
  final int team; // 0 | 1 | 2 (ball)
  double x, y, px, py, vx = 0, vy = 0;
  final double r, im;
  double spin = 0, ang = 0;
  final Float64List R = Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]);
  double sq = 0, tvx = 0, tvy = 0, ramp = 0, boost = 0, vox = 0, voy = 0;
  Goal? gout;

  /// v0.7: a flicked puck that has not touched anything yet (low flight friction, see PhysicsConfig.puckFlightK)
  bool fly = false; // retained for snapshot/API compatibility; no flight regime
  // Reset on every shot. Budget limits total extra normal bounce speed, so
  // even restitution slightly above one cannot keep a body moving forever.
  double _bounceBudget = 0;
  double _startX = 0, _startY = 0;
  // per-disc motion trail: ring of at most 13 points (TS keeps <= 12 after shift)
  final Float64List trX = Float64List(16), trY = Float64List(16);
  int trStart = 0, trLen = 0;
  Body(this.x, this.y, this.team, this.r, double m, this.id)
    : px = x,
      py = y,
      im = 1 / m;

  void trPush(double x, double y) {
    final i = (trStart + trLen) & 15;
    trX[i] = x;
    trY[i] = y;
    trLen++;
  }

  void trShift() {
    if (trLen == 0) return;
    trStart = (trStart + 1) & 15;
    trLen--;
  }
}

enum Phase { aim, move, goal, over }

enum EvType { hit, wall, post, goal, turn, shot, end, clock }

class EngineEvent {
  EvType t = EvType.clock;
  bool ball = false;
  double power = 0;
  int team = 0;
  bool nogoal = false;
  int s0 = 0, s1 = 0;
  @override
  String toString() =>
      '${t.name}(team:$team ball:$ball p:${power.toStringAsFixed(3)} ng:$nogoal $s0:$s1)';
}

class Drag {
  Body b;
  double sx, sy, cx, cy;
  bool ai;
  Drag(this.b, this.sx, this.sy, this.cx, this.cy, {this.ai = false});
}

class AiPlan {
  final Body b;
  final double dx, dy, l;
  double t;
  AiPlan(this.b, this.dx, this.dy, this.l, this.t);
}

class AimInfo {
  Body? b;
  double p = 0, ux = 0, uy = 0;
}

class _Cand {
  Body p;
  double dx, dy, sc, dist;
  int atk;
  _Cand(this.p, this.dx, this.dy, this.sc, this.dist, this.atk);
}

typedef Rand = double Function();

class Engine {
  /// Play geometry (kPlayField for the nx8 profiles, the art's own geometry for 'classic').
  late final Field f;

  /// The selected pitch art (its own L/R/T/B/cs in art units); render-only for the nx8 profiles.
  late final Field art;
  double Fl = 0, Fr = 0, Ft = 0, Fb = 0;
  double CX = 0, CY = 0, KY = 0;
  late final List<Goal> goals;
  double GGw = 0, GGh = 0, GGx = 0;
  double DEPTH = 120;
  final List<Body> bodies = [];
  late Body ball;

  // ---- particles (struct of arrays) ----
  static const int maxParts = 640;
  final Float64List pX = Float64List(maxParts),
      pY = Float64List(maxParts),
      pVx = Float64List(maxParts),
      pVy = Float64List(maxParts);
  final Float64List pL = Float64List(maxParts),
      pM = Float64List(maxParts),
      pR = Float64List(maxParts),
      pG = Float64List(maxParts);
  final Int32List pC = Int32List(maxParts), pK = Int32List(maxParts);
  int nParts = 0;

  // ---- ball trail (oldest first) ----
  static const int maxTrail = 56;
  final Float64List tX = Float64List(maxTrail),
      tY = Float64List(maxTrail),
      tA = Float64List(maxTrail);
  int nTrail = 0;

  final List<int> score = [0, 0];
  int turn = 0;
  Phase phase = Phase.aim;
  int shots = 0;
  double idle = 0, pause = 0;
  int kick = 0;
  double acc = 0, slow = 0, flash = 0, cam = 0;
  final Float64List shake = Float64List(2),
      ripple = Float64List(2),
      rippleX = Float64List(2);
  double mleft = 0, tleft = 0;
  bool sudden = false;
  double aiT = 0;
  AiPlan? aiPlan;
  Drag? drag;

  // ---- events (pooled) ----
  final List<EngineEvent> _evPool = [];
  int eventCount = 0;
  EngineEvent event(int i) => _evPool[i];
  void clearEvents() => eventCount = 0;

  final MatchCfg cfg;
  double time = 0;
  int lastWho = 0;
  final List<bool> aiTeams = [false, false];
  double lastPower = 0, lastUx = 0, lastUy = 0, lastV = 0;
  Body? lastShot;
  // A launch starts a motion sequence; subsequent shots in that sequence must
  // not replenish contact energy. The next settled turn (or reset) starts anew.
  bool _bounceSequenceActive = false;

  /// Online lockstep client: run only the physics; phase/turn/score/reset come from the host.
  bool slave = false;
  final Rand rand;
  final Float64List _rs = Float64List(9);
  final AimInfo _aim = AimInfo();

  /// Tuning of the nx8-family profile in use (null for 'classic').
  late final PhysTune? _tune = tuneFor(cfg.profile);
  PhysTune get tu => _tune!;
  double get ballRollRate => _physics.rollK;

  /// true for the nx8-family rendering/geometry profiles; false for 'classic'.
  late final bool godot = _tune != null;

  /// true for the default 'stars' profile (v0.6.1 uniform pitch + shallow goals; 'godot' keeps its parity geometry).
  late final bool stars = identical(_tune, kTuneStars);

  /// All profiles use the same fixed step and collision solver.
  late final double step = PHYSICS_CONFIG.fixedStep;

  // Classic retains its public null tune/profile flag and geometry, but its
  // dynamics are expressed with the same PhysTune consumed by the solver.
  late final PhysTune _physics = _tune ?? _classicTune;

  Engine(this.cfg, {Rand? rand}) : rand = rand ?? math.Random().nextDouble {
    art = (cfg.field >= 0 && cfg.field < kFields.length)
        ? kFields[cfg.field]
        : kFields[0];
    // v0.6.1: every pitch plays on ONE identical rectangle (kPlayField); the art is stretched onto it by the renderer.
    f = stars ? kPlayField : art;
    Fl = f.L + 4.0;
    Fr = f.R - 4.0;
    Ft = f.T + 4.0;
    Fb = f.B - 4.0;
    CX = (Fl + Fr) / 2;
    CY = (Ft + Fb) / 2;
    KY = f.cs.toDouble();
    final gi = kGS[f.gs]!;
    final gw = 2 * f.g / (gi[3] - gi[2]);
    GGw = gw;
    GGh = gw * gi[1] / gi[0] * 1.28;
    GGx = CX - f.g - gi[2] * gw;
    DEPTH = math.max(120, jsRound(GGh * .98)).toDouble();
    if (stars) {
      // v0.6.1 standard shallow goals (render + collision share these numbers)
      DEPTH = kGoalDepth;
      GGh = kGoalDepth + 10;
    }
    goals = [
      Goal(0, Ft, CX - f.g, CX + f.g, -1),
      Goal(1, Fb, CX - f.g, CX + f.g, 1),
    ];
    mleft = cfg.matchTime;
    tleft = cfg.turnTime;
    reset(cfg.first);
  }

  EngineEvent _push(EvType t) {
    if (eventCount == _evPool.length) _evPool.add(EngineEvent());
    final e = _evPool[eventCount++];
    e.t = t;
    e.ball = false;
    e.power = 0;
    e.team = 0;
    e.nogoal = false;
    return e;
  }

  Body _mk(double x, double y, int team, double r, double m, int id) =>
      Body(x, y, team, r, m, id);

  void reset(int kickTeam) {
    final Fw = Fr - Fl, Fh = Fb - Ft;
    bodies.clear();
    nTrail = 0;
    nParts = 0;
    slow = 0;
    cam = 0;
    for (var cm = 0; cm < 2; cm++) {
      final sl = slots(cfg.forms[cm]);
      for (var i = 0; i < sl.length; i++) {
        final nx = sl[i][0], ny = sl[i][1];
        final ins = (godot ? tu.discR : PR) + (godot ? 6 : 10);
        final x = Fl + ins + nx * (Fw - 2 * ins);
        final y = cm != 0 ? Ft + ny * Fh : Fb - ny * Fh;
        bodies.add(
          godot
              ? _mk(x, y, cm, tu.discR, tu.discM, cm * 20 + i)
              : _mk(x, y, cm, PR, 5, cm * 20 + i),
        );
      }
    }
    ball = godot
        ? _mk(CX, KY, 2, tu.ballR, tu.ballM, 99)
        : _mk(CX, KY, 2, BR, 1.5, 99);
    bodies.add(ball);
    turn = kickTeam;
    _bounceSequenceActive = false;
    phase = Phase.aim;
    drag = null;
    pause = 0;
    idle = 0;
    shots = 0;
    tleft = cfg.turnTime;
    aiT = 0;
    aiPlan = null;
    _push(EvType.turn).team = turn;
  }

  /// v0.6.1: a captain changes formation mid-match. Takes effect at the next kick-off / reset (goal, restart); when
  /// nobody has shot since the current kick-off the discs are re-placed at once (still the same kick-off).
  void setFormation(int team, int form) {
    if (team < 0 || team > 1 || form < 0 || form >= kForms.length) return;
    if (cfg.forms.length < 2) {
      cfg.forms = [cfg.forms.isEmpty ? 0 : cfg.forms[0], 0];
    }
    cfg.forms = [for (var i = 0; i < 2; i++) i == team ? form : cfg.forms[i]];
    if (!slave && atKickoff) reset(turn);
  }

  /// true while the discs still stand in their kick-off places (no shot fired since the last reset).
  bool get atKickoff => phase == Phase.aim && shots == 0 && drag == null;

  bool isAiTurn() => (cfg.ai && turn == 1) || aiTeams[turn];
  bool canControl() => phase == Phase.aim && !isAiTurn();

  // ---------- input ----------
  bool pick(double x, double y) {
    if (!canControl()) return false;
    Body? f;
    var bd = 1e9;
    for (final b in bodies) {
      if (b.team == turn && !identical(b, ball)) {
        final d = hyp(x - b.x, y - b.y);
        if (d < b.r + (godot ? 30 : 34) && d < bd) {
          f = b;
          bd = d;
        }
      }
    }
    if (f == null) return false;
    drag = Drag(f, f.x, f.y, x, y);
    return true;
  }

  void move(double x, double y) {
    final d = drag;
    if (d != null && !d.ai) {
      d.cx = x;
      d.cy = y;
    }
  }

  void release() {
    final d = drag;
    if (d == null || d.ai) return;
    drag = null;
    final dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy);
    if (l > 18 && phase == Phase.aim) fire(d.b, dx, dy, l, true);
  }

  void cancel() {
    if (drag != null && !drag!.ai) drag = null;
  }

  /// Aim info for the renderer; returns a shared (reused) object, or null when not dragging.
  AimInfo? aimInfo() {
    final d = drag;
    if (d == null) return null;
    final dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy);
    _aim.b = d.b;
    if (l < 18) {
      _aim.p = 0;
      _aim.ux = 0;
      _aim.uy = 0;
      return _aim;
    }
    _aim.p = _min(l, LMAX) / LMAX;
    _aim.ux = dx / l;
    _aim.uy = dy / l;
    return _aim;
  }

  DiscStats statsOf(int team) => cfg.stats?[team] ?? DiscStats.def;

  void fire(Body b, double dx, double dy, double l, [bool human = false]) {
    final p = _min(l, LMAX) / LMAX;
    final team = b.team;
    lastPower = p;
    final v = _shotSpeed(team, p);
    var ux = dx / l, uy = dy / l;
    if (human && cfg.stats != null) {
      final dev =
          (stars
              ? _starsAimDevDeg(statsOf(team).accuracy)
              : aimDevDeg(statsOf(team).accuracy)) *
          math.pi /
          180;
      if (dev > 0) {
        final a = fatan2(uy, ux) + (rand() + rand() - 1) * dev;
        ux = fcos(a);
        uy = fsin(a);
      }
    }
    lastUx = ux;
    lastUy = uy;
    lastV = v;
    _launch(b, ux, uy, v);
  }

  /// Pull changes velocity, independently of mass and surface friction.
  /// Every stat level 1..10 has a distinct monotonic full-pull launch speed.
  double _shotSpeed(int team, double p) {
    final stat = cfg.stats != null
        ? _starsPowerMul(statsOf(team).power)
        : (cfg.vip[team] ? 1.16 : 1.0);
    return _min(_physics.vSafe, _physics.shotMax * shotCurve(p) * stat);
  }

  /// Online lockstep client: replay a shot exactly as the host launched it (direction, speed, power).
  void fireRaw(Body b, double ux, double uy, double v, double p) {
    lastPower = p;
    lastUx = ux;
    lastUy = uy;
    lastV = v;
    _launch(b, ux, uy, v);
  }

  /// Online lockstep: apply a shot whose final direction (after the shooter's accuracy deviation) and power
  /// were decided elsewhere. Same arithmetic as [fire] without randomness, so every peer gets identical motion.
  void fireVec(Body b, double ux, double uy, double p) {
    final team = b.team;
    lastPower = p;
    final v = _shotSpeed(team, p);
    lastUx = ux;
    lastUy = uy;
    lastV = v;
    _launch(b, ux, uy, v);
  }

  /// Direction a human flick will actually take (accuracy deviation applied), for client-side prediction.
  (double, double) deviate(int team, double dx, double dy, double l) {
    var ux = dx / l, uy = dy / l;
    if (cfg.stats != null) {
      final dev =
          (stars
              ? _starsAimDevDeg(statsOf(team).accuracy)
              : aimDevDeg(statsOf(team).accuracy)) *
          math.pi /
          180;
      if (dev > 0) {
        final a = fatan2(uy, ux) + (rand() + rand() - 1) * dev;
        ux = fcos(a);
        uy = fsin(a);
      }
    }
    return (ux, uy);
  }

  void _launch(Body b, double ux, double uy, double v) {
    lastShot = b;
    // This is derived from the exact speed already carried by the network
    // shot message, not local team stats or a hidden random value.
    final intensity = _clamp(v.abs() / _physics.shotMax, 0, 1);
    if (!_bounceSequenceActive) {
      final budget =
          _physics.shotMax * PHYSICS_CONFIG.boostBudgetFraction * intensity;
      for (final other in bodies) {
        other._bounceBudget = budget;
      }
      _bounceSequenceActive = true;
    }
    for (final other in bodies) {
      other.fly = false;
      other.gout = null;
    }
    b.vx = ux * v;
    b.vy = uy * v;
    b.ramp = b.boost = b.tvx = b.tvy = 0;
    b.spin = 0;
    if (!godot) cam = _max(cam, .18);
    if (b.team != turn) turn = b.team;
    phase = Phase.move;
    idle = 0;
    shots++;
    drag = null;
    lastWho = b.team;
    _push(EvType.shot).team = b.team;
  }

  /// Simulates an isolated copy using the same fixed-step solver and raw
  /// launch speed as play. Returns shooter/ball coordinates after each step,
  /// ending at rest, the first goal, or [maxT]. This API does not draw a UI.
  List<double> predictShot(
    int shooter,
    double ux,
    double uy,
    double v, {
    double maxT = 4,
  }) {
    final copy = MatchCfg(
      field: cfg.field,
      ball: cfg.ball,
      forms: List<int>.of(cfg.forms),
      ai: cfg.ai,
      aiLvl: cfg.aiLvl,
      limit: cfg.limit,
      matchTime: cfg.matchTime,
      turnTime: cfg.turnTime,
      vip: List<bool>.of(cfg.vip),
      first: cfg.first,
      stats: cfg.stats == null ? null : List<DiscStats>.of(cfg.stats!),
      profile: cfg.profile,
    );
    final sim = Engine(copy, rand: () => .5);
    sim.bodies.clear();
    for (final b in bodies) {
      final c = Body(b.x, b.y, b.team, b.r, 1 / b.im, b.id)
        ..px = b.px
        ..py = b.py
        ..vx = b.vx
        ..vy = b.vy
        ..spin = b.spin
        ..ang = b.ang
        ..sq = b.sq
        ..tvx = b.tvx
        ..tvy = b.tvy
        ..ramp = b.ramp
        ..boost = b.boost
        ..vox = b.vox
        ..voy = b.voy
        ..fly = b.fly
        .._bounceBudget = b._bounceBudget
        ..gout = b.gout == null
            ? null
            : sim.goals[identical(b.gout, goals[0]) ? 0 : 1];
      c.R.setAll(0, b.R);
      sim.bodies.add(c);
      if (identical(b, ball)) sim.ball = c;
    }
    sim.turn = turn;
    sim.phase = phase;
    sim._bounceSequenceActive = _bounceSequenceActive;
    sim.shots = shots;
    sim.score[0] = score[0];
    sim.score[1] = score[1];
    final s = sim.bodies[shooter];
    sim.lastV = v;
    sim._launch(s, ux, uy, v);
    final out = <double>[];
    for (var t = 0.0; t < maxT; t += sim.step) {
      sim._sim(sim.step);
      out
        ..add(s.x)
        ..add(s.y)
        ..add(sim.ball.x)
        ..add(sim.ball.y);
      if (sim.phase == Phase.goal ||
          !sim.bodies.any((b) => b.vx != 0 || b.vy != 0)) {
        break;
      }
    }
    return out;
  }

  // ---------- unified fixed-step simulation ----------
  static const _hitCols = [0xffffffff, 0xff9fe8ff, 0xff5cb6ff];
  static const _goalCols = [
    0xffffd23a,
    0xffffffff,
    0xff3bd0ff,
    0xffff4a7a,
    0xff7bff5a,
  ];

  void _rotate(Float64List R, double wx, double wy, double wz, double dt) {
    final w = hyp3(wx, wy, wz), th = w * dt;
    if (th < 1e-7) return;
    final ax = wx / w,
        ay = wy / w,
        az = wz / w,
        c = fcos(th),
        s = fsin(th),
        t = 1 - c;
    final m0 = t * ax * ax + c,
        m1 = t * ax * ay - s * az,
        m2 = t * ax * az + s * ay;
    final m3 = t * ax * ay + s * az,
        m4 = t * ay * ay + c,
        m5 = t * ay * az - s * ax;
    final m6 = t * ax * az - s * ay,
        m7 = t * ay * az + s * ax,
        m8 = t * az * az + c;
    final r = _rs;
    for (var i = 0; i < 9; i++) {
      r[i] = R[i];
    }
    R[0] = m0 * r[0] + m1 * r[3] + m2 * r[6];
    R[1] = m0 * r[1] + m1 * r[4] + m2 * r[7];
    R[2] = m0 * r[2] + m1 * r[5] + m2 * r[8];
    R[3] = m3 * r[0] + m4 * r[3] + m5 * r[6];
    R[4] = m3 * r[1] + m4 * r[4] + m5 * r[7];
    R[5] = m3 * r[2] + m4 * r[5] + m5 * r[8];
    R[6] = m6 * r[0] + m7 * r[3] + m8 * r[6];
    R[7] = m6 * r[1] + m7 * r[4] + m8 * r[7];
    R[8] = m6 * r[2] + m7 * r[5] + m8 * r[8];
    final l0 = hyp3(R[0], R[1], R[2]);
    R[0] /= l0;
    R[1] /= l0;
    R[2] /= l0;
  }

  /// Limit all bodies after a launch/contact. Injected extreme velocities are
  /// also capped before choosing substeps, so the bound is meaningful.
  void _cap(Body b) {
    final t = _physics;
    final cap = identical(b, ball) ? _min(t.vSafe, t.ballVmax) : t.vSafe;
    final s2 = b.vx * b.vx + b.vy * b.vy;
    if (s2 > cap * cap) {
      final k = cap / math.sqrt(s2);
      b.vx *= k;
      b.vy *= k;
    }
  }

  // Inward normal, including curved corners and circular posts. Only a body
  // moving into a surface receives an impulse. Boost affects only the normal
  // component, scales with launch and impact speed, and spends finite budget.
  void _surface(Body b, double nx, double ny, double boost, EvType type) {
    final vn = b.vx * nx + b.vy * ny;
    if (vn >= 0) return;
    final t = _physics, bl = identical(b, ball), incoming = -vn;
    final en = bl ? t.eWallBall : t.eWallDisc;
    final et = bl ? t.tWallBall : t.tWallDisc;
    final intensity = _clamp(lastV.abs() / t.shotMax, 0, 1);
    final impact = _clamp(
      incoming / (PHYSICS_CONFIG.boostImpactSpeed * PHYSICS_CONFIG.wPx),
      0,
      1,
    );
    final restitutionRoom = _max(0, PHYSICS_CONFIG.maxContactRestitution - en);
    final extra = _min(
      b._bounceBudget,
      incoming * _min(restitutionRoom, boost * intensity * impact),
    );
    b._bounceBudget -= extra;
    final tx = b.vx - vn * nx, ty = b.vy - vn * ny;
    // Spin affects rendering only; it never changes collision trajectories.
    if (bl && !godot && type == EvType.wall) {
      b.spin += (nx * b.vy - ny * b.vx) / b.r * .05 * t.ballSpinMultiplier;
    }
    b.vx = tx * et + (incoming * en + extra) * nx;
    b.vy = ty * et + (incoming * en + extra) * ny;
    b.fly = false;
    _cap(b);
    if (bl && (type == EvType.post || incoming > 200)) {
      _push(type).power = incoming / 1800;
    }
  }

  void _wallX(Body b, double wall, double side, double boost) {
    if ((b.x - wall) * side >= 0) return;
    b.x = wall;
    _surface(b, side, 0, boost, EvType.wall);
  }

  void _wallY(Body b, double wall, double side, double boost) {
    if ((b.y - wall) * side >= 0) return;
    b.y = wall;
    _surface(b, 0, side, boost, EvType.wall);
  }

  // Classic has rounded field corners; stars/godot have square corners.
  void _roundedCorner(Body b, double cx, double cy, double sx, double sy) {
    if ((b.x - cx) * sx >= 0 || (b.y - cy) * sy >= 0) return;
    final dx = b.x - cx, dy = b.y - cy;
    final d = math.sqrt(dx * dx + dy * dy), limit = RC - b.r;
    if (d <= limit || d == 0) return;
    final nx = dx / d, ny = dy / d;
    b.x = cx + nx * limit;
    b.y = cy + ny * limit;
    _surface(b, -nx, -ny, PHYSICS_CONFIG.cornerBoost, EvType.wall);
  }

  void _walls(Body b) {
    final r = b.r, bl = identical(b, ball);
    // Detect a simultaneous square-corner contact before projecting either
    // axis; each axis uses its own inward normal, never a resting nudge.
    final atSide = b.x <= Fl + r || b.x >= Fr - r;
    final atEnd =
        (b.y <= Ft + r && (b.x < goals[0].x1 || b.x > goals[0].x2)) ||
        (b.y >= Fb - r && (b.x < goals[1].x1 || b.x > goals[1].x2));
    final wallBoost = atSide && atEnd
        ? PHYSICS_CONFIG.cornerBoost
        : PHYSICS_CONFIG.railBoost;
    _wallX(b, Fl + r, 1, wallBoost);
    _wallX(b, Fr - r, -1, wallBoost);
    for (final g in goals) {
      final dp = g.d * (b.y - g.y);
      if (dp <= -r) continue;
      // Preserve open goal mouths, net depth, and profile scoring threshold.
      final inside = bl
          ? b.x > g.x1 && b.x < g.x2
          : (dp > 0
                ? b.x > g.x1 && b.x < g.x2
                : b.x >= g.x1 + r && b.x <= g.x2 - r);
      if (inside) {
        final back = g.y + g.d * (DEPTH - r);
        _wallY(b, back, -g.d.toDouble(), PHYSICS_CONFIG.railBoost);
        if (dp > (bl ? r * .6 : 0)) {
          _wallX(b, g.x1 + r, 1, PHYSICS_CONFIG.railBoost);
          _wallX(b, g.x2 - r, -1, PHYSICS_CONFIG.railBoost);
        }
      } else {
        _wallY(b, g.y - g.d * r, -g.d.toDouble(), wallBoost);
      }
    }
    if (!godot) {
      _roundedCorner(b, Fl + RC, Ft + RC, 1, 1);
      _roundedCorner(b, Fr - RC, Ft + RC, -1, 1);
      _roundedCorner(b, Fl + RC, Fb - RC, 1, -1);
      _roundedCorner(b, Fr - RC, Fb - RC, -1, -1);
    }
  }

  void _post(Body b, double x, double y, {bool sweep = false}) {
    var dx = b.x - x, dy = b.y - y;
    final m = b.r + _physics.postR, m2 = m * m;
    var d2 = dx * dx + dy * dy;
    var fraction = 1.0;
    var swept = false;
    if (sweep) {
      final sx = b._startX - x, sy = b._startY - y;
      final mx = dx - sx, my = dy - sy;
      final c = sx * sx + sy * sy - m2;
      final av = mx * mx + my * my, bv = sx * mx + sy * my;
      final disc = bv * bv - av * c;
      if (c >= 0 && av > 1e-12 && bv < 0 && disc >= 0) {
        final f = (-bv - math.sqrt(disc)) / av;
        if (f >= 0 && f <= 1) {
          fraction = f;
          dx = sx + mx * f;
          dy = sy + my * f;
          d2 = dx * dx + dy * dy;
          swept = true;
        }
      }
    }
    if (!swept && d2 >= m2) return;
    final d = math.sqrt(d2);
    if (d < 1e-9) {
      // Deterministic normal even for a malformed centre-on-post placement.
      final speed = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      dx = speed > 0 ? -b.vx / speed : 0;
      dy = speed > 0 ? -b.vy / speed : (y == Ft ? 1 : -1);
    } else {
      dx /= d;
      dy /= d;
    }
    if (swept && b.vx * dx + b.vy * dy >= 0) return;
    b.x = x + dx * m;
    b.y = y + dy * m;
    _surface(b, dx, dy, PHYSICS_CONFIG.postBoost, EvType.post);
    if (swept) {
      final remaining = (1 - fraction) * _substepDuration;
      b.x += b.vx * remaining;
      b.y += b.vy * remaining;
    }
  }

  /// Circle collision: detect swept crossings on the first pass and solve the
  /// mass-weighted normal impulse. The remaining passes resolve any overlap
  /// from neighbouring contacts; they never replay a sweep or add energy.
  void _pair(Body a, Body b, bool sweep) {
    var dx = b.x - a.x, dy = b.y - a.y;
    final m = a.r + b.r, m2 = m * m;
    var d2 = dx * dx + dy * dy;
    var nx = 0.0, ny = 0.0;
    var hitSweep = false;
    var fraction = 1.0;
    if (sweep) {
      final sx = b._startX - a._startX, sy = b._startY - a._startY;
      final mx = dx - sx, my = dy - sy;
      final c = sx * sx + sy * sy - m2;
      final av = mx * mx + my * my;
      final bv = sx * mx + sy * my;
      final disc = bv * bv - av * c;
      if (c >= 0 && av > 1e-12 && bv < 0 && disc >= 0) {
        final f = (-bv - math.sqrt(disc)) / av;
        if (f >= 0 && f <= 1) {
          fraction = f;
          nx = (sx + mx * f) / m;
          ny = (sy + my * f) / m;
          hitSweep = true;
        }
      }
    }
    if (!hitSweep && d2 >= m2) return;
    if (!hitSweep) {
      final d = math.sqrt(d2);
      if (d > 1e-9) {
        nx = dx / d;
        ny = dy / d;
      } else {
        // Stable, deterministic fallback for exactly coincident centres.
        nx = 1;
        ny = 0;
      }
    }
    final inv = a.im + b.im;
    if (inv <= 0) return;
    final vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
    if (hitSweep && vn < 0) {
      // Move to the impact point, then integrate the post-impact portion.
      a.x = a._startX + (a.x - a._startX) * fraction;
      a.y = a._startY + (a.y - a._startY) * fraction;
      b.x = b._startX + (b.x - b._startX) * fraction;
      b.y = b._startY + (b.y - b._startY) * fraction;
    }
    if (vn < 0) {
      final isBall = identical(a, ball) || identical(b, ball);
      final restitution = isBall ? _physics.eDiscBall : _physics.eDiscDisc;
      final j = -(1 + restitution) * vn / inv;
      a.vx -= j * a.im * nx;
      a.vy -= j * a.im * ny;
      b.vx += j * b.im * nx;
      b.vy += j * b.im * ny;
      a.fly = b.fly = false;
      _cap(a);
      _cap(b);
      if (isBall && !godot) {
        final tangent = -ny * (b.vx - a.vx) + nx * (b.vy - a.vy);
        ball.spin = _clamp(
          ball.spin +
              (identical(ball, b) ? 1 : -1) *
                  tangent /
                  ball.r *
                  .3 *
                  _physics.ballSpinMultiplier,
          -34 * _physics.ballSpinMultiplier,
          34 * _physics.ballSpinMultiplier,
        );
      }
      if (vn < -150) {
        final ev = _push(EvType.hit);
        ev.ball = isBall;
        ev.power = -vn / 1900;
        final pw = _min(1, -vn / 2100);
        if (isBall && pw > .2) {
          final other = identical(a, ball) ? b : a;
          ball.sq = _max(ball.sq, pw * .6);
          other.sq = _max(other.sq, pw * .25);
          if (pw > .45) {
            burst(
              (a.x + b.x) / 2,
              (a.y + b.y) / 2,
              jsRound(4 + pw * 8),
              200 + pw * 260,
              _hitCols,
              .3,
              2,
            );
          }
        } else if (!isBall && vn < -520) {
          a.sq = _max(a.sq, pw * .5);
          b.sq = _max(b.sq, pw * .5);
        }
      }
      if (hitSweep) {
        final remaining = (1 - fraction) * _substepDuration;
        a.x += a.vx * remaining;
        a.y += a.vy * remaining;
        b.x += b.vx * remaining;
        b.y += b.vy * remaining;
      }
    }
    // Mass-weighted positional correction (no velocity injection at rest).
    dx = b.x - a.x;
    dy = b.y - a.y;
    d2 = dx * dx + dy * dy;
    if (d2 < m2) {
      final d = math.sqrt(d2);
      if (d > 1e-9) {
        nx = dx / d;
        ny = dy / d;
      }
      final pen = m - d;
      a.x -= nx * pen * a.im / inv;
      a.y -= ny * pen * a.im / inv;
      b.x += nx * pen * b.im / inv;
      b.y += ny * pen * b.im / inv;
    }
  }

  double _substepDuration = 0;

  void _sim(double dt) {
    final t = _physics;
    var energy = 0.0, minMass = double.infinity;
    for (final b in bodies) {
      _cap(b);
      final mass = 1 / b.im;
      energy += mass * (b.vx * b.vx + b.vy * b.vy);
      minMass = _min(minMass, mass);
    }
    // The energy bound covers velocity transferred to a lighter body; each
    // body is also capped. Bounded work is guaranteed even for bad inputs.
    final possible = energy == 0
        ? 0.0
        : _min(
            t.vSafe,
            math.sqrt(energy / minMass) * PHYSICS_CONFIG.maxContactRestitution,
          );
    final travel = _min(t.subPx, ball.r * PHYSICS_CONFIG.subBallFrac);
    final n = (possible * dt / travel).ceil().clamp(1, PHYSICS_CONFIG.subMax);
    final h = dt / n;
    _substepDuration = h;
    for (var sub = 0; sub < n; sub++) {
      for (final b in bodies) {
        b._startX = b.x;
        b._startY = b.y;
        b.x += b.vx * h;
        b.y += b.vy * h;
        final bl = identical(b, ball);
        final sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
        if (sp > 0) {
          // Exact decay for dv/dt = -friction - drag*v. The exponential
          // model is the same formula with zero constant friction.
          final drag = t.expFric
              ? (bl ? t.ballK : t.discK)
              : (bl ? t.ballDrag : t.discDrag);
          final fric = t.expFric ? 0.0 : (bl ? t.ballFric : t.discFric);
          final decay = drag > 0 ? fexp(-drag * h) : 1.0;
          final ns = drag > 0
              ? (sp + fric / drag) * decay - fric / drag
              : sp - fric * h;
          if (ns < t.vStop) {
            b.vx = b.vy = 0;
            b.fly = false;
          } else {
            final k = ns / sp;
            b.vx *= k;
            b.vy *= k;
          }
        }
        if (b.vox != 0 || b.voy != 0) {
          final k = 1 - _min(1, h * 15);
          b.vox *= k;
          b.voy *= k;
          if (b.vox.abs() < .04) b.vox = 0;
          if (b.voy.abs() < .04) b.voy = 0;
        }
        if (bl) {
          b.spin *= 1 - _min(1, h * 1.05);
          if (b.spin.abs() < .02) b.spin = 0;
          b.ang += b.spin * h;
          if (b.vx != 0 || b.vy != 0 || b.spin != 0) {
            final roll = t.rollK / b.r;
            _rotate(b.R, -b.vy * roll, b.vx * roll, b.spin * .55, h);
          }
        } else {
          b.spin *= 1 - _min(1, h * 2.6);
          b.ang += b.spin * h;
        }
        b.sq *= 1 - _min(1, 9 * h);
        // Posts first, then walls, so a grazing post cannot project a body
        // through the goal line. All bodies collide with posts.
        for (final g in goals) {
          _post(b, g.x1, g.y, sweep: true);
          _post(b, g.x2, g.y, sweep: true);
        }
        _walls(b);
      }
      final count = bodies.length;
      for (var it = 0; it < 4; it++) {
        for (var i = 0; i < count; i++) {
          final a = bodies[i];
          for (var j = i + 1; j < count; j++) {
            final b = bodies[j], m = a.r + b.r;
            if (it > 0 && ((b.x - a.x).abs() >= m || (b.y - a.y).abs() >= m)) {
              continue;
            }
            _pair(a, b, it == 0);
          }
        }
        // Reapply static constraints during positional solving for clusters.
        for (final b in bodies) {
          for (final g in goals) {
            _post(b, g.x1, g.y);
            _post(b, g.x2, g.y);
          }
          _walls(b);
        }
      }
      // Pair correction and wall projection can move a body onto/through a
      // post after the initial swept pass. Reproject posts from the resulting
      // point and reapply walls; repeat in a fixed order for deterministic
      // corner/post intersections.
      for (var pass = 0; pass < 2; pass++) {
        for (final b in bodies) {
          for (final g in goals) {
            _post(b, g.x1, g.y);
            _post(b, g.x2, g.y);
          }
          _walls(b);
        }
      }
      if (phase == Phase.move && !slave) {
        for (final g in goals) {
          final gr = ball.r * (stars ? 1.0 : .8);
          if (ball.x > g.x1 && ball.x < g.x2 && g.d * (ball.y - g.y) > gr) {
            _scored(g.team);
            break;
          }
        }
      }
    }
  }

  void _scored(int t) {
    final nogoal = shots <= 1;
    final ev = _push(EvType.goal);
    ev.team = t;
    ev.nogoal = nogoal;
    if (nogoal) {
      phase = Phase.goal;
      pause = 1.4;
      kick = turn;
      return;
    }
    ripple[t] = 1;
    rippleX[t] = ball.x;
    score[t]++;
    pause = godot ? 1.8 : 2.0;
    flash = 1;
    shake[t] = .6;
    phase = Phase.goal;
    kick = 1 - t;
    slow = 1.1;
    cam = 1.4;
    final g = goals[t];
    burst(ball.x, g.y, 80, 760, _goalCols, 1.4, 1);
    burst(ball.x, g.y, 50, 520, _goalCols, 1.8, 3);
  }

  void burst(
    double x,
    double y,
    int n,
    double sp,
    List<int> cols,
    double life, [
    int k = 0,
  ]) {
    if (nParts > 420) return;
    for (var i = 0; i < n; i++) {
      final a = rand() * math.pi * 2, v = sp * (.3 + rand());
      final l = life * (.6 + rand() * .6);
      final r = 2 + rand() * 3.5;
      if (nParts >= maxParts) continue;
      final j = nParts++;
      pX[j] = x;
      pY[j] = y;
      pVx[j] = fcos(a) * v;
      pVy[j] = fsin(a) * v;
      pL[j] = l;
      pM[j] = life;
      pC[j] = cols[i % cols.length];
      pR[j] = r;
      pK[j] = k;
      pG[j] = k == 3 ? 600 : 0;
    }
  }

  void _finishTurn() {
    _bounceSequenceActive = false;
    turn = 1 - turn;
    phase = Phase.aim;
    tleft = cfg.turnTime;
    aiT = 0;
    aiPlan = null;
    _push(EvType.turn).team = turn;
  }

  void _end() {
    phase = Phase.over;
    final e = _push(EvType.end);
    e.s0 = score[0];
    e.s1 = score[1];
  }

  // ---------- main step (call once per frame) ----------
  void update(double rdt) {
    final dt = _min(rdt, .05);
    time += dt;
    if (phase == Phase.over) {
      tickFx(dt);
      return;
    }
    if (cfg.matchTime > 0 && !sudden && mleft > 0 && !slave) {
      mleft = _max(0, mleft - dt);
    }
    var ts = 1.0;
    if (slow > 0) {
      slow -= dt;
      ts = godot
          ? .32 + .68 * fpow(1 - _max(0, slow) / 1.1, 2)
          : .3 + .7 * fpow(1 - _max(0, slow) / 1.1, 2);
    }
    acc += dt * ts * (stars ? PHYSICS_CONFIG.playbackSpeed : 1.0);
    var n = 0;
    final stepCap = _physics.stepCap;
    while (acc >= step && n < stepCap) {
      n++;
      for (final b in bodies) {
        b.px = b.x;
        b.py = b.y;
      }
      _sim(step);
      acc -= step;
    }
    if (acc >= step && n >= stepCap) acc = 0;
    if (slave) {
      tickFx(dt);
      return;
    }
    if (phase == Phase.move) {
      var moving = false;
      for (final b in bodies) {
        if (b.vx != 0 || b.vy != 0) {
          moving = true;
          break;
        }
      }
      idle = moving ? 0 : idle + dt;
      if (idle > (godot ? .25 : .15)) _finishTurn();
    } else if (phase == Phase.aim) {
      if (cfg.matchTime > 0 && !sudden && mleft <= 0) {
        if (score[0] != score[1]) {
          _end();
          return;
        }
        sudden = true;
        _push(EvType.clock);
      }
      if (cfg.turnTime > 0) {
        tleft -= dt;
        if (tleft <= 0) {
          drag = null;
          aiPlan = null;
          _finishTurn();
          if (godot) {
            tickFx(dt);
            return;
          }
        }
      }
      if (isAiTurn()) _aiTick(dt);
    } else if (phase == Phase.goal) {
      pause -= dt;
      if (pause <= 0) {
        if (cfg.matchTime > 0) {
          if (sudden || (mleft <= 0 && score[0] != score[1])) {
            _end();
          } else {
            if (mleft <= 0) sudden = true;
            reset(kick);
          }
        } else if (score[0] >= cfg.limit || score[1] >= cfg.limit) {
          _end();
        } else {
          reset(kick);
        }
      }
    }
    tickFx(dt);
  }

  /// online clients: visual-only goal feedback (the host owns the score)
  void fxGoal(int t) {
    ripple[t] = 1;
    rippleX[t] = ball.x;
    flash = 1;
    shake[t] = .6;
    cam = 1.4;
    final g = goals[t];
    burst(ball.x, g.y, 80, 760, _goalCols, 1.4, 1);
    burst(ball.x, g.y, 50, 520, _goalCols, 1.8, 3);
  }

  void tickFx(double dt) {
    flash = _max(0, flash - dt * 2);
    cam = _max(0, cam - dt * 3.2);
    shake[0] = _max(0, shake[0] - dt);
    ripple[0] = _max(0, ripple[0] - dt * .8);
    ripple[1] = _max(0, ripple[1] - dt * .8);
    shake[1] = _max(0, shake[1] - dt);
    final ball = this.ball;
    final sp = hyp(ball.vx, ball.vy);
    if (sp > 60) {
      if (nTrail == maxTrail) _trailDrop(1);
      tX[nTrail] = ball.x;
      tY[nTrail] = ball.y;
      tA[nTrail] = _min(1, sp / 900);
      nTrail++;
    }
    var k = 0;
    for (var i = 0; i < nTrail; i++) {
      final a = tA[i] - dt * (godot ? 3.0 : 3.2);
      if (a > 0) {
        tX[k] = tX[i];
        tY[k] = tY[i];
        tA[k] = a;
        k++;
      }
    }
    nTrail = k;
    final tmax = godot ? 54 : 40;
    if (nTrail > tmax) _trailDrop(nTrail - tmax);
    for (final b in bodies) {
      if (!identical(b, ball)) {
        if (godot && b.sq != 0) b.sq = b.sq > .02 ? b.sq - dt * 5 : 0;
        final s = hyp(b.vx, b.vy);
        if (s > 140 * K) {
          b.trPush(b.x, b.y);
        } else if (b.trLen > 0) {
          b.trShift();
        }
        if (b.trLen > 12) b.trShift();
      }
    }
    k = 0;
    for (var i = 0; i < nParts; i++) {
      pX[i] += pVx[i] * dt;
      pY[i] += pVy[i] * dt;
      pVx[i] *= .965;
      pVy[i] = pVy[i] * .965 + pG[i] * dt;
      pL[i] -= dt;
      if (pL[i] > 0) {
        if (k != i) {
          pX[k] = pX[i];
          pY[k] = pY[i];
          pVx[k] = pVx[i];
          pVy[k] = pVy[i];
          pL[k] = pL[i];
          pM[k] = pM[i];
          pR[k] = pR[i];
          pG[k] = pG[i];
          pC[k] = pC[i];
          pK[k] = pK[i];
        }
        k++;
      }
    }
    nParts = k;
  }

  void _trailDrop(int c) {
    for (var i = c; i < nTrail; i++) {
      tX[i - c] = tX[i];
      tY[i - c] = tY[i];
      tA[i - c] = tA[i];
    }
    nTrail -= c;
  }

  /// interpolation factor for rendering between physics steps
  double alpha() => _clamp(acc / step, 0, 1);

  // ---------- AI ----------
  void _aiTick(double dt) {
    if (aiPlan == null) {
      aiT += dt;
      if (aiT < .7 + rand() * (godot ? .7 : .5)) return;
      final p = _aiDecide();
      if (p == null) return;
      aiPlan = p;
      drag = Drag(p.b, p.b.x, p.b.y, p.b.x, p.b.y, ai: true);
      return;
    }
    final pl = aiPlan!;
    pl.t += dt;
    final k = _min(1, pl.t / .75), e = k * k * (3 - 2 * k);
    final d = drag;
    if (d != null) {
      d.cx = pl.b.x - pl.dx * pl.l * e;
      d.cy = pl.b.y - pl.dy * pl.l * e;
    }
    if (k >= 1) {
      drag = null;
      aiPlan = null;
      fire(pl.b, pl.dx * pl.l, pl.dy * pl.l, pl.l);
    }
  }

  static double _segDist(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final vx = bx - ax, vy = by - ay;
    var l2 = vx * vx + vy * vy;
    if (l2 == 0) l2 = 1;
    var t = ((px - ax) * vx + (py - ay) * vy) / l2;
    t = _clamp(t, 0, 1);
    return hyp(px - (ax + vx * t), py - (ay + vy * t));
  }

  bool _clear(Body p, double x, double y) {
    for (final o in bodies) {
      if (identical(o, p) || identical(o, ball)) continue;
      if (_segDist(o.x, o.y, p.x, p.y, x, y) < p.r + o.r - 6) return false;
    }
    return true;
  }

  static const _offs = [-.55, 0.0, .55];

  AiPlan? _aiDecide() {
    final me = turn, ball = this.ball, B = bodies;
    final mine = <Body>[
      for (final b in B)
        if (b.team == me && !identical(b, ball)) b,
    ];
    final og = goals[1 - me];
    final target = goals[me == 1 ? 1 : 0];
    final lvl = cfg.aiLvl;
    final sg = const [.14, .06, .016][lvl];
    final gw = (target.x2 - target.x1) / 2;
    final cands = <_Cand>[];
    for (final p in mine) {
      for (final ox in _offs) {
        final tx = CX + ox * gw, ty = target.y;
        var ux = tx - ball.x, uy = ty - ball.y;
        var ul = hyp(ux, uy);
        if (ul == 0) ul = 1;
        ux /= ul;
        uy /= ul;
        final cx = ball.x - ux * (p.r + ball.r + 1),
            cy = ball.y - uy * (p.r + ball.r + 1);
        var vx = cx - p.x, vy = cy - p.y;
        final dist = hyp(vx, vy);
        if (dist < 8) continue;
        vx /= dist;
        vy /= dist;
        final al = vx * ux + vy * uy;
        if (al < .2 || !_clear(p, cx, cy)) continue;
        var blk = 0;
        for (final o in B) {
          if (o.team == me || identical(o, ball)) continue;
          if (_segDist(o.x, o.y, ball.x, ball.y, tx, ty) < ball.r + o.r + 6) {
            blk++;
          }
        }
        cands.add(
          _Cand(
            p,
            vx,
            vy,
            100 * al -
                dist * .03 -
                blk * 28 +
                ((ball.y - ty).abs() < 420 ? 25 : 0),
            dist,
            1,
          ),
        );
      }
      var vx = ball.x - p.x, vy = ball.y - p.y;
      final dist = hyp(vx, vy);
      if (dist > 8) {
        vx /= dist;
        vy /= dist;
        if (_clear(p, ball.x, ball.y)) {
          final toOwn = (vy * (og.y - ball.y) > 0) ? vy.abs() : 0.0;
          cands.add(_Cand(p, vx, vy, 10 - dist * .04 - toOwn * 55, dist, 0));
        }
      }
    }
    if (cands.isEmpty) {
      final sorted = List<Body>.of(mine);
      _stableSort<Body>(
        sorted,
        (a, b) =>
            hyp(a.x - ball.x, a.y - ball.y) - hyp(b.x - ball.x, b.y - ball.y),
      );
      if (sorted.isEmpty) return null;
      final p = sorted[0];
      final vx = ball.x - p.x, vy = ball.y - p.y;
      var d = hyp(vx, vy);
      if (d == 0) d = 1;
      cands.add(_Cand(p, vx / d, vy / d, 0, d, 0));
    }
    _stableSort<_Cand>(cands, (a, b) => b.sc - a.sc);
    final take = const [4, 2, 1][lvl];
    final poolN = cands.length < take ? cands.length : take;
    final c = cands[(rand() * poolN).floor()];
    double gauss() => (rand() + rand() + rand() - 1.5) * 1.15;
    final ang = fatan2(c.dy, c.dx) + gauss() * sg;
    var pw = lvl == 2
        ? _min(1, .66 + c.dist / 1000)
        : _min(1, .5 + c.dist / 1100);
    if (lvl == 0) pw *= .7 + rand() * .3;
    if (c.atk != 0 && lvl > 0) pw = _max(pw, .78);
    return AiPlan(c.p, fcos(ang), fsin(ang), _max(.3, pw) * LMAX, 0);
  }

  /// Stable sort with a JS-style numeric comparator (V8's Array.prototype.sort is stable).
  static void _stableSort<T>(List<T> a, double Function(T, T) cmp) {
    for (var i = 1; i < a.length; i++) {
      final x = a[i];
      var j = i - 1;
      while (j >= 0 && cmp(a[j], x) > 0) {
        a[j + 1] = a[j];
        j--;
      }
      a[j + 1] = x;
    }
  }
}
