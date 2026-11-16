// Headless regressions for the default stars physics. Run with:
//   flutter test test/rebuilt_physics_test.dart
// These use the public Engine/Body APIs; no rendering or private methods are needed.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

MatchCfg _config({double power = 10, double accuracy = 10}) => MatchCfg(
      field: 0,
      ball: 0,
      forms: [0, 0],
      ai: false,
      aiLvl: 1,
      limit: 99,
      matchTime: 0,
      turnTime: 0,
      vip: [false, false],
      first: 0,
      stats: [DiscStats(power, accuracy), const DiscStats(10, 10)],
    );

Engine _world({int discs = 1, double power = 10, double accuracy = 10, Rand? rand}) {
  final e = Engine(_config(power: power, accuracy: accuracy), rand: rand ?? () => .5);
  final kept = e.bodies.where((b) => b.team == 0).take(discs).toList();
  e.bodies
    ..clear()
    ..addAll(kept)
    ..add(e.ball);
  // Run physics without goal/turn timers or resetting the test scene.
  e.slave = true;
  for (final b in e.bodies) {
    _place(b, e.CX, e.Ft + 120);
  }
  e.clearEvents();
  return e;
}

void _place(Body b, double x, double y, [double vx = 0, double vy = 0]) {
  b.x = b.px = x;
  b.y = b.py = y;
  b.vx = vx;
  b.vy = vy;
  b.fly = false;
}

double _speed(Body b) => math.sqrt(b.vx * b.vx + b.vy * b.vy);
bool _moving(Engine e) => e.bodies.any((b) => b.vx != 0 || b.vy != 0);

// update(0) with exactly one accumulated step bypasses wall-clock playback
// speed and samples the same fixed-step physics as predictShot.
void _step(Engine e) {
  e.acc = e.step;
  e.update(0);
}

List<Object> _state(Engine e) => [
      e.phase,
      e.turn,
      e.shots,
      e.acc,
      e.eventCount,
      ...e.score,
      for (final b in e.bodies) ...[b.x, b.y, b.vx, b.vy, b.fly],
    ];

bool _hasEvent(Engine e, EvType type) =>
    List.generate(e.eventCount, e.event).any((event) => event.t == type);

void main() {
  group('ratings and shots', () {
    test('owner-requested feel tuning is applied to the stars profile', () {
      expect(PHYSICS_CONFIG.shotMax, closeTo((3500 / 825) * 1.35, 1e-9));
      expect(PHYSICS_CONFIG.ballSpinMultiplier, 1.35);
      expect(PHYSICS_CONFIG.tBallWall, closeTo(.85 * .9, 1e-12));
      expect(PHYSICS_CONFIG.tPuckWall, closeTo(.85 * .9, 1e-12));
      expect(PHYSICS_CONFIG.ballDiameter, closeTo(.058 * 1.1, 1e-12));
      expect(PHYSICS_CONFIG.playbackSpeed, 1.0);
      expect(kTuneStars.ballR, closeTo(.0638 / 2 * PHYSICS_CONFIG.wPx, 1e-9));
      expect(kTuneStars.rollK, .75);
      expect(shotCurve(.05), greaterThan(.03), reason: 'a short flick should not be reduced to a nearly imperceptible nudge');
      expect(shotCurve(1), 1, reason: 'full-pull power remains standard');
    });

    test('all ten power ratings scale launch speed and clamp at the endpoints', () {
      expect(PHYSICS_CONFIG.useDiscStats, isTrue);
      double launch(double rating) {
        final e = _world(power: rating);
        e.fireVec(e.bodies.first, 1, 0, 1);
        return _speed(e.bodies.first);
      }

      final top = launch(10);
      var previous = 0.0;
      for (var rating = 1; rating <= 10; rating++) {
        final actual = launch(rating.toDouble());
        final multiplier = PHYSICS_CONFIG.powerMulAt1 +
            (1 - PHYSICS_CONFIG.powerMulAt1) * (rating - 1) / 9;
        expect(actual, closeTo(top * multiplier, 1e-7), reason: 'power $rating');
        expect(actual, greaterThan(previous), reason: 'power $rating is not monotonic');
        previous = actual;
      }
      expect(launch(-5), closeTo(launch(1), 1e-7));
      expect(launch(15), closeTo(top, 1e-7));
    });

    test('all accuracy ratings bound human aim and match preview direction', () {
      expect(PHYSICS_CONFIG.useDiscStats, isTrue);
      for (var rating = 1; rating <= 10; rating++) {
        // A valid RNG value of 0 gives the largest negative deviation.
        final e = _world(accuracy: rating.toDouble(), rand: () => 0);
        final direction = e.deviate(0, 1, 0, 1);
        final expected = -(10 - rating) / 9 * PHYSICS_CONFIG.accDevAt1Deg * math.pi / 180;
        final angle = math.atan2(direction.$2, direction.$1);
        expect(angle, closeTo(expected, 1e-9), reason: 'accuracy $rating');
        expect(math.sqrt(direction.$1 * direction.$1 + direction.$2 * direction.$2), closeTo(1, 1e-9));
        final shooter = e.bodies.first;
        e.fire(shooter, LMAX, 0, LMAX, true);
        expect(math.atan2(shooter.vy, shooter.vx), closeTo(angle, 1e-9), reason: 'human shot $rating');
      }
      final below = _world(accuracy: -4, rand: () => 0).deviate(0, 1, 0, 1);
      final above = _world(accuracy: 14, rand: () => 0).deviate(0, 1, 0, 1);
      expect(math.atan2(below.$2, below.$1), closeTo(-PHYSICS_CONFIG.accDevAt1Deg * math.pi / 180, 1e-9));
      expect(math.atan2(above.$2, above.$1), closeTo(0, 1e-9));
    });

    test('short, medium and full pulls launch increasingly fast; fire and fireVec agree', () {
      var previous = 0.0;
      for (final pull in [.2, .5, 1.0]) {
        final human = _world(), vector = _world();
        final a = human.bodies.first, b = vector.bodies.first;
        final length = LMAX * pull;
        human.fire(a, .6 * length, .8 * length, length, true);
        vector.fireVec(b, .6, .8, pull);
        expect(a.vx, closeTo(b.vx, 1e-8));
        expect(a.vy, closeTo(b.vy, 1e-8));
        expect(_speed(a), greaterThan(previous));
        expect(human.phase, Phase.move);
        expect(_hasEvent(human, EvType.shot), isTrue);
        previous = _speed(a);
      }
    });

    test('a zero drag does not shoot and a deliberate drag launches away from the pointer', () {
      final e = _world(), shooter = e.bodies.first;
      _place(shooter, e.CX, e.CY);
      expect(e.pick(shooter.x, shooter.y), isTrue);
      e.move(shooter.x, shooter.y);
      e.release();
      expect(e.shots, 0);
      expect(_speed(shooter), 0);
      expect(e.pick(shooter.x, shooter.y), isTrue);
      e.move(shooter.x - LMAX, shooter.y);
      e.release();
      expect(e.shots, 1);
      expect(e.phase, Phase.move);
      expect(shooter.vx, greaterThan(0));
      expect(shooter.vy, closeTo(0, 1e-9));
    });
  });

  group('collisions', () {
    test('ball and disc reflect at every rail with configured normal and tangent losses', () {
      for (final isBall in [true, false]) {
        for (var wall = 0; wall < 4; wall++) {
          final e = _world(discs: isBall ? 0 : 1);
          final b = isBall ? e.ball : e.bodies.first;
          const normal = 900.0, tangent = 240.0;
          // End rails are tested outside the goal mouth, not across an opening.
          switch (wall) {
            case 0:
              _place(b, e.Fl + b.r + 2, e.CY, -normal, tangent);
            case 1:
              _place(b, e.Fr - b.r - 2, e.CY, normal, tangent);
            case 2:
              _place(b, e.Fl + b.r + 50, e.Ft + b.r + 2, tangent, -normal);
            case 3:
              _place(b, e.Fl + b.r + 50, e.Fb - b.r - 2, tangent, normal);
          }
          _step(e);
          final vn = wall < 2 ? b.vx : b.vy;
          final vt = wall < 2 ? b.vy : b.vx;
          final sign = wall == 0 || wall == 2 ? 1 : -1;
          final friction = math.exp(-(isBall ? e.tu.ballK : e.tu.discK) * e.step);
          final en = isBall ? e.tu.eWallBall : e.tu.eWallDisc;
          final et = isBall ? e.tu.tWallBall : e.tu.tWallDisc;
          expect(vn * sign, closeTo(normal * en * friction, 1e-5), reason: 'ball=$isBall rail=$wall');
          expect(vt, closeTo(tangent * et * friction, 1e-5), reason: 'ball=$isBall rail=$wall');
        }
      }
    });

    test('ball hits all four goal posts rather than tunnelling through them', () {
      for (var goalIndex = 0; goalIndex < 2; goalIndex++) {
        for (final leftPost in [true, false]) {
          final e = _world(discs: 0), b = e.ball, g = e.goals[goalIndex];
          final postX = leftPost ? g.x1 : g.x2;
          final radius = b.r + e.tu.postR;
          // Approach from the field just inside the mouth so the line rail
          // does not mask the circular post contact.
          _place(b, postX + (leftPost ? 1 : -1) * radius * .35,
              g.y - g.d * (radius + 4), 0, g.d * 900.0);
          for (var i = 0; i < 15 && !_hasEvent(e, EvType.post); i++) {
            _step(e);
          }
          final dx = b.x - postX, dy = b.y - g.y;
          expect(_hasEvent(e, EvType.post), isTrue, reason: 'goal=$goalIndex left=$leftPost');
          expect(math.sqrt(dx * dx + dy * dy), greaterThanOrEqualTo(radius - 1e-6));
          expect(b.vx * dx + b.vy * dy, greaterThan(0), reason: 'post should repel the ball');
        }
      }
    });

    test('disc grazing each goal post is deflected without overlapping it', () {
      for (var goalIndex = 0; goalIndex < 2; goalIndex++) {
        for (final leftPost in [true, false]) {
          final e = _world(), disc = e.bodies.first, g = e.goals[goalIndex];
          final postX = leftPost ? g.x1 : g.x2;
          final outward = leftPost ? 1.0 : -1.0;
          final radius = disc.r + e.tu.postR;
          // Inside the mouth by slightly more than the puck radius: the goal
          // line does not act as a rail, but the post's circular radius does.
          _place(disc, postX + outward * (disc.r + .5),
              g.y - g.d * (radius + 4), 0, g.d * 900.0);
          var bounced = false;
          for (var i = 0; i < 60 && !bounced; i++) {
            _step(e);
            final dx = disc.x - postX, dy = disc.y - g.y;
            final distance = math.sqrt(dx * dx + dy * dy);
            expect(distance, greaterThanOrEqualTo(radius - 1e-6),
                reason: 'disc crossed goal=$goalIndex left=$leftPost post');
            bounced = disc.vx * outward > 0;
          }
          expect(bounced, isTrue, reason: 'disc missed goal=$goalIndex left=$leftPost post');
        }
      }
    });

    test('ball and disc rebound from all four corners and stay inside the field', () {
      for (final isBall in [true, false]) {
        for (var corner = 0; corner < 4; corner++) {
          final e = _world(discs: isBall ? 0 : 1);
          final b = isBall ? e.ball : e.bodies.first;
          final sx = corner.isEven ? -1.0 : 1.0;
          final sy = corner < 2 ? -1.0 : 1.0;
          final x = sx < 0 ? e.Fl + b.r : e.Fr - b.r;
          final y = sy < 0 ? e.Ft + b.r : e.Fb - b.r;
          _place(b, x - sx * 45, y - sy * 45, sx * 1000, sy * 1000);
          var bouncedX = false, bouncedY = false;
          for (var i = 0; i < 180 && !(bouncedX && bouncedY); i++) {
            _step(e);
            bouncedX |= b.vx * sx < 0;
            bouncedY |= b.vy * sy < 0;
            expect(b.x, inInclusiveRange(e.Fl + b.r - 1e-6, e.Fr - b.r + 1e-6));
            expect(b.y, inInclusiveRange(e.Ft + b.r - 1e-6, e.Fb - b.r + 1e-6));
          }
          expect(bouncedX && bouncedY, isTrue, reason: 'ball=$isBall corner=$corner');
        }
      }
    });

    test('a body already at rest in a corner is not nudged or made to jitter', () {
      for (final isBall in [true, false]) {
        for (var corner = 0; corner < 4; corner++) {
          final e = _world(discs: isBall ? 0 : 1);
          final b = isBall ? e.ball : e.bodies.first;
          final x = corner.isEven ? e.Fl + b.r : e.Fr - b.r;
          final y = corner < 2 ? e.Ft + b.r : e.Fb - b.r;
          _place(b, x, y);
          for (var i = 0; i < 120; i++) {
            _step(e);
          }
          expect([b.x, b.y, b.vx, b.vy], [x, y, 0.0, 0.0], reason: 'ball=$isBall corner=$corner');
        }
      }
    });

    test('fast ball-disc contacts at several offsets are not missed and remain finite', () {
      final w = PHYSICS_CONFIG.wPx;
      for (final speed in [2.0, 5.0, 6.5]) {
        for (final offset in [-.8, -.4, 0.0, .4, .8]) {
          final e = _world(), disc = e.bodies.first, ball = e.ball;
          final radius = disc.r + ball.r;
          _place(disc, e.CX, e.CY);
          _place(ball, e.CX - radius - 100, e.CY + radius * offset, speed * w, 0);
          var hit = false;
          for (var i = 0; i < 180; i++) {
            _step(e);
            hit |= _speed(disc) > 0;
            for (final b in [disc, ball]) {
              expect(b.x.isFinite && b.y.isFinite && b.vx.isFinite && b.vy.isFinite, isTrue);
              final cap = identical(b, ball) ? e.tu.ballVmax : e.tu.vSafe;
              expect(_speed(b), lessThanOrEqualTo(cap + 1e-6));
            }
          }
          expect(hit, isTrue, reason: 'speed=$speed W/s offset=$offset');
        }
      }
    });
  });

  group('simulation and prediction', () {
    test('free ball and disc slow to rest and remain at rest', () {
      for (final isBall in [true, false]) {
        final e = _world(discs: isBall ? 0 : 1);
        final b = isBall ? e.ball : e.bodies.first;
        _place(b, e.CX, e.CY, 0, 400);
        var previous = _speed(b);
        for (var i = 0; i < 1800 && _speed(b) > 0; i++) {
          _step(e);
          expect(_speed(b), lessThanOrEqualTo(previous + 1e-8));
          previous = _speed(b);
        }
        expect(_speed(b), 0, reason: 'ball=$isBall did not settle');
        final x = b.x, y = b.y;
        for (var i = 0; i < 120; i++) {
          _step(e);
        }
        expect([b.x, b.y, b.vx, b.vy], [x, y, 0.0, 0.0]);
      }
    });

    test('30, 60, 120 and 144 fps reach the same rest state after a real shot', () {
      List<double> run(double dt) {
        final e = _world(), disc = e.bodies.first, ball = e.ball;
        _place(disc, e.CX - 210, e.CY);
        _place(ball, e.CX, e.CY);
        e.fireVec(disc, 1, 0, 1);
        var hit = false;
        for (var i = 0; i < (20 / dt).ceil() && _moving(e); i++) {
          e.update(dt);
          hit |= _speed(ball) > 0;
        }
        expect(hit, isTrue, reason: 'no ball contact at dt=$dt');
        expect(_moving(e), isFalse, reason: 'did not stop at dt=$dt');
        return [for (final b in e.bodies) ...[b.x, b.y, b.vx, b.vy]];
      }

      final reference = run(1 / 60);
      for (final fps in [30, 120, 144]) {
        final actual = run(1 / fps);
        for (var i = 0; i < reference.length; i++) {
          expect(actual[i], closeTo(reference[i], 1e-7), reason: '$fps fps state index $i');
        }
      }
    });

    test('prediction is isolated and matches every fixed step, including contacts', () {
      for (final scenario in ['free', 'rail', 'ball', 'post']) {
        final e = _world(), disc = e.bodies.first, ball = e.ball;
        var ux = 1.0, uy = 0.0;
        _place(disc, e.CX - 180, e.CY);
        _place(ball, e.Fr - 100, e.Fb - 100);
        switch (scenario) {
          case 'rail':
            _place(disc, e.Fr - disc.r - 50, e.CY);
          case 'ball':
            _place(ball, e.CX, e.CY);
          case 'post':
            final g = e.goals[0], radius = ball.r + e.tu.postR;
            _place(ball, g.x1 + radius * .35, g.y + radius + 4, 0, -900);
          case 'free':
            ux = 0;
            uy = 1;
        }
        final before = _state(e);
        const launchSpeed = 1800.0;
        final path = e.predictShot(0, ux, uy, launchSpeed, maxT: 1.5);
        expect(_state(e), before, reason: 'prediction changed live state: $scenario');
        expect(path.length % 4, 0);
        expect(path.length, greaterThan(40));
        e.fireRaw(disc, ux, uy, launchSpeed, .5);
        for (var i = 0; i < path.length; i += 4) {
          _step(e);
          expect(disc.x, closeTo(path[i], 1e-7), reason: '$scenario step ${i ~/ 4} disc x');
          expect(disc.y, closeTo(path[i + 1], 1e-7), reason: '$scenario step ${i ~/ 4} disc y');
          expect(ball.x, closeTo(path[i + 2], 1e-7), reason: '$scenario step ${i ~/ 4} ball x');
          expect(ball.y, closeTo(path[i + 3], 1e-7), reason: '$scenario step ${i ~/ 4} ball y');
        }
        if (scenario == 'ball') expect(_hasEvent(e, EvType.hit), isTrue);
        if (scenario == 'post') expect(_hasEvent(e, EvType.post), isTrue);
        if (scenario == 'rail') expect(disc.vx, lessThanOrEqualTo(0));
      }
    });
  });
}
