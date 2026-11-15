// NEXORA physics constants for the default 'stars' profile, all in pitch-width units.
//
// W = 825 world px = the inner pitch width between the cushions (v0.7 play area fitted to the pitch art's drawn field
// edges). Cross-check: the v0.6.2 puck (r 49 px) and ball (r 21.6 px) measure 98/825 = 0.119 W and 43.2/825 = 0.052 W,
// matching the owner's "current 0.118 / 0.050".
//
// speeds W/s, accelerations W/s^2, friction rates 1/s, lengths W. Change a value here and kTuneStars follows.
// Confidence tags: [measured] from the reference video (+-30%), [guess] owner's starting guess, [kept] unchanged
// v0.6.2 value converted to W.

class PhysicsConfig {
  /// world px per W (the engine itself runs in world px; every value below is multiplied by this).
  final double wPx;

  // ---- sizes (collision radius == drawn radius) ----
  final double puckDiameter, ballDiameter;
  /// Multiplier for spin imparted to the ball by puck and wall impacts.
  final double ballSpinMultiplier;

  // ---- exponential friction v *= exp(-k dt) ----
  final double ballK, puckK;

  /// Legacy compatibility value. All discs use puckK from launch to rest.
  final double puckFlightK;

  /// Legacy compatibility value; there is no separate flight phase.
  final double puckFlightMin;

  /// below this speed a body stops dead (W/s).
  final double stopSpeed;

  // ---- masses: only the ratio matters ----
  final double massPuck, massBall;

  // ---- restitution (normal) and tangential keep factor ----
  final double eBallPuck, ePuckPuck, eBallWall, ePuckWall;
  final double tBallWall, tPuckWall;

  // ---- shot / kick ----
  /// full-pull launch speed (W/s) before the power stat; launch speed = shotMax * shotCurve(pull) * statMul(power).
  final double shotMax;

  /// Legacy compatibility values. Body contacts now use mass and restitution
  /// exclusively; no additional striker impulse is injected.
  final double ballKickSpeed, puckShotRef;

  /// hard cap on ball speed (reference peak) and numerical safety cap on any body.
  final double ballMaxSpeed, maxSpeed;

  final double postR;

  // ---- integration ----
  /// fixed physics step (s); each step is split into substeps so that no body travels more than subTravel and the
  /// ball never more than subBallFrac x its radius per substep.
  final double fixedStep, subTravel, subBallFrac;

  /// playback speed of the whole simulation (1 = original pace). Slows the match like playing a fast-forwarded film
  /// at normal speed: identical paths/collisions (fixed steps), only wall-clock pace changes. Owner 2026-11-15.
  final double playbackSpeed;

  /// disc stats 1..10 really applied to every shot (owner 2026-11-15):
  /// launch speed x (powerMulAt1 + (1 - powerMulAt1) * (power - 1) / 9)  -> power 1 = 0.55x, power 10 = 1.0x
  /// aim deviation = (10 - accuracy) / 9 * accDevAt1Deg degrees          -> accuracy 10 = exact, accuracy 1 = 8 deg
  final bool useDiscStats;
  final double powerMulAt1, accDevAt1Deg;
  final int subMax, stepCap;

  /// Extra restitution applied only to the incoming normal component of a
  /// moving contact. It scales with actual launch speed and impact speed.
  /// These parameters are dimensionless except [boostImpactSpeed] (W/s).
  /// Zero disables the corresponding boost. The total restitution is capped
  /// by [maxContactRestitution], and body speed remains subject to its cap.
  /// Each body gets a finite per-shot budget of extra normal speed equal to
  /// [boostBudgetFraction] times the launch speed capped at full shot speed.
  /// The defaults allow a full-power puck to rebound faster than it arrived:
  /// its .35 wall restitution can reach 1.25, and a square corner needs
  /// enough budget for both normal impulses and their tangential damping.
  /// Weak shots and slow impacts receive proportionally less extra impulse.
  final double railBoost, postBoost, cornerBoost;
  final double boostImpactSpeed, maxContactRestitution, boostBudgetFraction;

  const PhysicsConfig({
    required this.wPx,
    this.playbackSpeed = 1.0,
    this.useDiscStats = true,
    this.powerMulAt1 = .55,
    this.accDevAt1Deg = 8,
    this.ballSpinMultiplier = 1.35,
    this.railBoost = .90,
    this.postBoost = .95,
    this.cornerBoost = 1.00,
    this.boostImpactSpeed = 2,
    this.maxContactRestitution = 1.25,
    this.boostBudgetFraction = 1.20,
    required this.puckDiameter,
    required this.ballDiameter,
    required this.ballK,
    required this.puckK,
    required this.puckFlightK,
    required this.puckFlightMin,
    required this.stopSpeed,
    required this.massPuck,
    required this.massBall,
    required this.eBallPuck,
    required this.ePuckPuck,
    required this.eBallWall,
    required this.ePuckWall,
    required this.tBallWall,
    required this.tPuckWall,
    required this.shotMax,
    required this.ballKickSpeed,
    required this.puckShotRef,
    required this.ballMaxSpeed,
    required this.maxSpeed,
    required this.postR,
    required this.fixedStep,
    required this.subTravel,
    required this.subBallFrac,
    required this.subMax,
    required this.stepCap,
  });

  double get kickGain => ballKickSpeed / puckShotRef;
}

// ignore: constant_identifier_names
const PHYSICS_CONFIG = PhysicsConfig(
  wPx: 825,
  puckDiameter: .134, // [measured] was .117 (98 px)
  ballDiameter: .0638, // +10% from .058 W per owner request
  ballK: 2.6, // owner 11-15 heavier; was 2.1
  // [measured, medium] tau .48 s; was 270 px/s^2 + 1.45/s (owner fit ~3.5/s)
  puckK: 3.6, // owner 11-15 heavier; was 2.9
  // [measured, low] tau .34 s; was 300 px/s^2 + 2.0/s (owner fit ~3.9/s)
  puckFlightK: 1.2, // owner 11-15 heavier; was .5
  // [guess] "almost constant speed until the first hit"; new
  puckFlightMin: 1, // [guess] new
  stopSpeed: .02, // [measured] was 2 px/s = .0024 W/s
  massPuck: 1, // [guess] ball 3x puck; was ball 1 : puck 4
  massBall: 3,
  eBallPuck: .4, // owner 11-15; was .5
  // [guess] was .84
  ePuckPuck: .55, // owner 11-15 less scatter; was .8
  // [guess] was .84
  eBallWall: .5, // owner 11-15 wall absorbs more; was .8
  // [guess] was .85
  ePuckWall: .35, // owner 11-15; was .6
  // [guess] was .90
  tBallWall: .765, // +10% wall friction: 10% less tangential speed kept
  // [kept]
  tPuckWall: .765, // +10% wall friction: 10% less tangential speed kept
  // [kept]
  shotMax: (3500 / 825) * 1.35, // +35% puck launch power per owner request
  ballKickSpeed: 3.8, // owner 11-15 heavier ball; was 5
  // [guess, low] owner: reference ~6.5, start at 5
  puckShotRef: 2, // [measured] reference flick ~2 W/s
  ballMaxSpeed: 5, // owner 11-15; was 6.5
  // [measured, low] reference peak ball speed
  maxSpeed: 7, // safety clamp; was 4200 px/s = 5.03 W/s
  postR: 5 / 825, // [kept]
  playbackSpeed: .6, // calm presentation pace; does not reduce the actual shot-power curve
  useDiscStats: true, // owner: real 1..10 power/accuracy on every disc
  powerMulAt1: .55, // was .62 (statMul)
  accDevAt1Deg: 8, // was 4 (aimDevDeg)
  fixedStep: 1 / 120, // was 1/240 (brief: 1/120 + substeps)
  subTravel: 4 / 825, // [kept] 4 px
  subBallFrac: .5, // spec: ball moves < half its radius per substep
  subMax: 24, // was 16 (1/120 step: 7 W/s needs 18 substeps of 4 px)
  stepCap: 14, // [kept]
);
