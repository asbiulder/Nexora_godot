// Gameplay regressions: real-time response and physically dissipative contacts.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

MatchCfg _config({double power = 10}) => MatchCfg(
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
  stats: [DiscStats(power, 10), const DiscStats(10, 10)],
);

Engine _world({double power = 10}) {
  final e = Engine(_config(power: power), rand: () => .5);
  final puck = e.bodies.firstWhere((b) => b.team == 0);
  e.bodies
    ..clear()
    ..add(puck)
    ..add(e.ball);
  e.slave = true; // Real physics, with turn and goal resets suppressed.
  e.clearEvents();
  return e;
}

void _place(Body b, double x, double y, [double vx = 0, double vy = 0]) {
  b.x = b.px = x;
  b.y = b.py = y;
  b.vx = vx;
  b.vy = vy;
}

double _speed(Body b) => math.sqrt(b.vx * b.vx + b.vy * b.vy);

void main() {
  group('playable real-time physics', () {
    test('preserves requested shot, spin, ball-size and wall-friction tuning', () {
      expect(PHYSICS_CONFIG.shotMax, closeTo((3500 / 825) * 1.35, 1e-9));
      expect(PHYSICS_CONFIG.ballSpinMultiplier, 1.35);
      expect(PHYSICS_CONFIG.tBallWall, closeTo(.85 * .9, 1e-12));
      expect(PHYSICS_CONFIG.tPuckWall, closeTo(.85 * .9, 1e-12));
      expect(PHYSICS_CONFIG.ballDiameter, closeTo(.058 * 1.1, 1e-12));
      expect(PHYSICS_CONFIG.playbackSpeed, 1.0,
          reason: 'visual presentation must not slow the simulation');
      expect(PHYSICS_CONFIG.railBoost, 0);
      expect(PHYSICS_CONFIG.postBoost, 0);
      expect(PHYSICS_CONFIG.cornerBoost, 0);
    });

    test('a short real-time full-power shot visibly travels instead of slow motion', () {
      final e = _world(), puck = e.bodies.first, ball = e.ball;
      _place(puck, e.CX - 200, e.CY);
      _place(ball, e.CX, e.CY + 300);
      final startX = puck.x;
      e.fireVec(puck, 1, 0, 1);
      for (var i = 0; i < 6; i++) {
        e.update(1 / 60);
      }
      expect(puck.x - startX, greaterThan(320),
          reason: 'six 60-fps frames must advance the shot at real-time speed');
      expect(puck.vx, greaterThan(0));
      expect(e.phase, Phase.move);
    });

    test('pull distance gives a strong, monotonic launch', () {
      final speeds = <double>[];
      for (final pull in [.05, .2, .5, 1.0]) {
        final e = _world(), puck = e.bodies.first;
        e.fireVec(puck, 1, 0, pull);
        speeds.add(_speed(puck));
      }
      for (var i = 1; i < speeds.length; i++) {
        expect(speeds[i], greaterThan(speeds[i - 1]));
      }
      expect(speeds.first, greaterThan(0));
      expect(speeds.last, closeTo(PHYSICS_CONFIG.shotMax * PHYSICS_CONFIG.wPx, 1e-6));
    });

    test('puck strike makes both puck and ball move with no artificial energy injection', () {
      final e = _world(), puck = e.bodies.first, ball = e.ball;
      _place(puck, e.CX - 180, e.CY);
      _place(ball, e.CX, e.CY);
      e.fireVec(puck, 1, 0, .75);
      final initialEnergy = .5 * (1 / puck.im) * _speed(puck) * _speed(puck);
      var contacted = false;
      for (var i = 0; i < 120; i++) {
        e.acc = e.step;
        e.update(0);
        if (_speed(ball) > 0) {
          contacted = true;
          break;
        }
      }
      expect(contacted, isTrue);
      expect(ball.vx, greaterThan(0));
      expect(_speed(puck), greaterThan(0));
      final remainingEnergy =
          .5 * (1 / puck.im) * _speed(puck) * _speed(puck) +
          .5 * (1 / ball.im) * _speed(ball) * _speed(ball);
      expect(remainingEnergy, lessThanOrEqualTo(initialEnergy + 1e-6));
      expect(_speed(ball), lessThanOrEqualTo(PHYSICS_CONFIG.ballMaxSpeed * PHYSICS_CONFIG.wPx + 1e-6));
    });

    test('wall impact reverses direction but never creates speed', () {
      final e = _world(), puck = e.bodies.first;
      _place(puck, e.Fr - puck.r - .1, e.CY);
      e.fireVec(puck, 1, 0, 1);
      final incoming = _speed(puck);
      e.acc = e.step;
      e.update(0);
      expect(puck.vx, lessThan(0));
      expect(_speed(puck), lessThan(incoming));
      expect(_speed(puck) / incoming, inInclusiveRange(.75, .82));
    });
  });
}
