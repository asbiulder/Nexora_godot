// Real-contact regressions for the default stars profile. Run with:
//   flutter test --no-pub test/impact_boost_test.dart
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
  e.slave = true; // Keep real physics, but suppress turn/goal resets.
  _place(e.ball, e.CX, e.Ft + 160);
  _place(puck, e.CX, e.CY);
  e.clearEvents();
  return e;
}

void _place(Body b, double x, double y) {
  b.x = b.px = x;
  b.y = b.py = y;
  b.vx = b.vy = 0;
}

double _speed(Body b) => math.sqrt(b.vx * b.vx + b.vy * b.vy);

// Advance exactly one physics step, independent of playback speed.
void _step(Engine e) {
  e.acc = e.step;
  e.update(0);
}

void main() {
  group('real boosted impacts', () {
    test('full-power puck leaves each rail faster than its incoming speed', () {
      for (var rail = 0; rail < 4; rail++) {
        final e = _world(), puck = e.bodies.first;
        var ux = 0.0, uy = 0.0;
        switch (rail) {
          case 0: // left
            _place(puck, e.Fl + puck.r + .1, e.CY);
            ux = -1;
          case 1: // right
            _place(puck, e.Fr - puck.r - .1, e.CY);
            ux = 1;
          case 2: // top, outside the goal mouth
            _place(puck, e.Fl + puck.r + 80, e.Ft + puck.r + .1);
            uy = -1;
          case 3: // bottom, outside the goal mouth
            _place(puck, e.Fl + puck.r + 80, e.Fb - puck.r - .1);
            uy = 1;
        }
        e.fireVec(puck, ux, uy, 1);
        final beforeX = puck.vx, beforeY = puck.vy, incoming = _speed(puck);
        _step(e);
        final outgoing = _speed(puck);
        expect(
          beforeX * puck.vx + beforeY * puck.vy,
          lessThan(0),
          reason: 'rail $rail must actually reverse the normal velocity',
        );
        expect(outgoing, greaterThan(incoming), reason: 'rail $rail');
        // Friction applies throughout the entire step, even after contact.
        final expected =
            incoming *
            math.exp(-PHYSICS_CONFIG.puckK * e.step) *
            PHYSICS_CONFIG.maxContactRestitution;
        expect(outgoing, closeTo(expected, 1e-5), reason: 'rail $rail');
        expect(
          puck.x,
          inInclusiveRange(e.Fl + puck.r - 1e-6, e.Fr - puck.r + 1e-6),
        );
        expect(
          puck.y,
          inInclusiveRange(e.Ft + puck.r - 1e-6, e.Fb - puck.r + 1e-6),
        );
      }
    });

    test(
      'an oblique boosted rail impact preserves normal and tangent physics',
      () {
        final e = _world(), puck = e.bodies.first;
        _place(puck, e.Fr - puck.r - .1, e.CY);
        e.fireVec(puck, .8, .6, 1);
        final incomingX = puck.vx, incomingY = puck.vy;
        final incoming = _speed(puck);
        _step(e);
        final decay = math.exp(-PHYSICS_CONFIG.puckK * e.step);
        expect(puck.vx, lessThan(0));
        expect(puck.vy, greaterThan(0));
        expect(
          puck.vx,
          closeTo(
            -incomingX * PHYSICS_CONFIG.maxContactRestitution * decay,
            1e-5,
          ),
        );
        expect(
          puck.vy,
          closeTo(incomingY * PHYSICS_CONFIG.tPuckWall * decay, 1e-5),
        );
        expect(_speed(puck), greaterThan(incoming));
      },
    );

    test('full-power puck leaves each circular goal post faster', () {
      for (var goal = 0; goal < 2; goal++) {
        for (final left in [true, false]) {
          final e = _world(), puck = e.bodies.first, g = e.goals[goal];
          final postX = left ? g.x1 : g.x2;
          final side = left ? 1.0 : -1.0; // Approach from inside the mouth.
          final contactRadius = puck.r + e.tu.postR;
          _place(puck, postX + side * (contactRadius + .1), g.y);
          // Raw replay uses the same full-power velocity as a regular shot.
          e.fireRaw(puck, -side, 0, e.tu.shotMax, 1);
          final incoming = _speed(puck);
          expect(puck.vx * side, lessThan(0));
          _step(e);
          final outgoing = _speed(puck);
          expect(
            puck.vx * side,
            greaterThan(0),
            reason: 'goal $goal left=$left must reflect off the post',
          );
          expect(puck.vy, closeTo(0, 1e-8));
          expect(
            outgoing,
            greaterThan(incoming),
            reason: 'goal $goal left=$left',
          );
          expect(
            outgoing,
            closeTo(
              incoming *
                  math.exp(-PHYSICS_CONFIG.puckK * e.step) *
                  PHYSICS_CONFIG.maxContactRestitution,
              1e-5,
            ),
          );
          final dx = puck.x - postX, dy = puck.y - g.y;
          expect(
            math.sqrt(dx * dx + dy * dy),
            greaterThanOrEqualTo(contactRadius - 1e-6),
          );
          // The puck remains on the open-mouth side, not bounced by an end rail.
          expect(dx * side, greaterThan(puck.r));
        }
      }
    });

    test('full-power puck reverses and damps predictably in all four square corners', () {
      for (var corner = 0; corner < 4; corner++) {
        final e = _world(), puck = e.bodies.first;
        final sx = corner.isEven ? -1.0 : 1.0;
        final sy = corner < 2 ? -1.0 : 1.0;
        final x = sx < 0 ? e.Fl + puck.r : e.Fr - puck.r;
        final y = sy < 0 ? e.Ft + puck.r : e.Fb - puck.r;
        _place(puck, x - sx * .1, y - sy * .1);
        final diagonal = 1 / math.sqrt(2);
        e.fireVec(puck, sx * diagonal, sy * diagonal, 1);
        final incoming = _speed(puck);
        expect(puck.vx * sx, greaterThan(0));
        expect(puck.vy * sy, greaterThan(0));
        _step(e);
        expect(puck.vx * sx, lessThan(0), reason: 'corner $corner x normal');
        expect(puck.vy * sy, lessThan(0), reason: 'corner $corner y normal');
        // Two orthogonal contacts combine the 1.25 normal restitution with
        // the 0.765 tangential retention: 1.25 * 0.765 < 1, so total speed
        // correctly falls even though each normal component reverses.
        expect(_speed(puck), lessThan(incoming), reason: 'corner $corner');
        // Each of the two wall contacts damps the other (tangent) component.
        final expected =
            incoming *
            math.exp(-PHYSICS_CONFIG.puckK * e.step) *
            PHYSICS_CONFIG.maxContactRestitution *
            PHYSICS_CONFIG.tPuckWall;
        expect(_speed(puck), closeTo(expected, 1e-5), reason: 'corner $corner');
        expect(puck.vx.abs(), closeTo(puck.vy.abs(), 1e-5));
        expect(
          puck.x,
          inInclusiveRange(e.Fl + puck.r - 1e-6, e.Fr - puck.r + 1e-6),
        );
        expect(
          puck.y,
          inInclusiveRange(e.Ft + puck.r - 1e-6, e.Fb - puck.r + 1e-6),
        );
      }
    });

    test('the hard puck and ball caps survive a boosting impact', () {
      for (final isBall in [false, true]) {
        final e = _world(), b = isBall ? e.ball : e.bodies.first;
        final cap = isBall ? e.tu.ballVmax : e.tu.vSafe;
        final k = isBall ? PHYSICS_CONFIG.ballK : PHYSICS_CONFIG.puckK;
        _place(b, e.Fr - b.r - .1, e.CY);
        e.fireRaw(b, 1, 0, cap, 1);
        final incoming = _speed(b);
        _step(e);
        expect(b.vx, lessThan(0), reason: 'ball=$isBall must hit the rail');
        // Without the cap, the tuned contact would clearly exceed it.
        expect(
          incoming *
              math.exp(-k * e.step) *
              PHYSICS_CONFIG.maxContactRestitution,
          greaterThan(cap),
        );
        expect(_speed(b), lessThanOrEqualTo(cap + 1e-7));
        // The cap was reached at contact, then the remaining step has friction.
        expect(
          _speed(b),
          greaterThanOrEqualTo(cap * math.exp(-k * e.step) - 1e-5),
        );
      }
    });

    test('weaker pulls and lower power get smaller, natural rebounds', () {
      (double, double) rebound({double power = 10, double pull = 1}) {
        final e = _world(power: power), puck = e.bodies.first;
        _place(puck, e.Fr - puck.r - .1, e.CY);
        e.fireVec(puck, 1, 0, pull);
        final incoming = _speed(puck);
        _step(e);
        expect(puck.vx, lessThan(0)); // The low shot must actually contact too.
        return (incoming, _speed(puck));
      }

      final full = rebound();
      final lowPull = rebound(pull: .2);
      final lowStat = rebound(power: 1);
      expect(full.$1, greaterThan(lowStat.$1));
      expect(lowStat.$1, greaterThan(lowPull.$1));
      expect(full.$2, greaterThan(lowStat.$2));
      expect(lowStat.$2, greaterThan(lowPull.$2));
      expect(full.$2 / full.$1, greaterThan(1));
      expect(lowPull.$2 / lowPull.$1, lessThan(.42));
      expect(lowPull.$2 / lowPull.$1, greaterThan(.30));
      expect(lowStat.$2 / lowStat.$1, lessThan(full.$2 / full.$1));
    });

    test('a full shot that decays before impact also rebounds naturally', () {
      final e = _world(), puck = e.bodies.first;
      // ~1260 px of free travel lets the strong shot decay below one tenth
      // before the end rail under the current exponential puck drag.
      _place(puck, e.Fl + puck.r + 130, e.Fb - puck.r - 1260);
      e.fireVec(puck, 0, 1, 1);
      final launch = _speed(puck);
      var incoming = 0.0;
      var hit = false;
      for (var i = 0; i < 1000 && _speed(puck) > 0; i++) {
        final before = _speed(puck);
        _step(e);
        if (puck.vy < 0) {
          incoming = before;
          hit = true;
          break;
        }
      }
      expect(
        hit,
        isTrue,
        reason: 'the slow shot must really reach the end rail',
      );
      expect(incoming, lessThan(launch * .1));
      expect(_speed(puck) / incoming, inInclusiveRange(.30, .50));
    });
  });

  group('finite budget and settling', () {
    test('one shot spends a bounded budget over repeated real rail contacts', () {
      final e = _world(), puck = e.bodies.first;
      _place(puck, e.Fr - puck.r - .1, e.CY);
      e.fireVec(puck, 1, 0, 1);
      final launch = _speed(puck);
      final decay = math.exp(-PHYSICS_CONFIG.puckK * e.step);
      var totalExtraAtStepStart = 0.0;
      var contacts = 0;
      for (var i = 0; i < 6; i++) {
        // Bring the next rail close without changing velocity or firing again.
        // This isolates budget consumption from the pitch crossing distance.
        final towardsRight = puck.vx > 0;
        puck.x = puck.px = towardsRight
            ? e.Fr - puck.r - .1
            : e.Fl + puck.r + .1;
        puck.y = puck.py = e.CY;
        final beforeVx = puck.vx, incoming = _speed(puck);
        _step(e);
        expect(puck.vx * beforeVx, lessThan(0), reason: 'contact $i');
        expect(_speed(puck), lessThanOrEqualTo(e.tu.vSafe + 1e-7));
        final extra =
            _speed(puck) / decay - PHYSICS_CONFIG.ePuckWall * incoming;
        totalExtraAtStepStart += math.max(0, extra);
        if (i == 0) expect(_speed(puck), greaterThan(incoming));
        if (i >= 2) {
          // By the third hit the finite per-body budget is exhausted.
          expect(
            _speed(puck),
            closeTo(incoming * decay * PHYSICS_CONFIG.ePuckWall, 1e-5),
          );
        }
        contacts++;
      }
      expect(contacts, 6);
      final budget = launch * PHYSICS_CONFIG.boostBudgetFraction;
      // Converting impulses to start-of-step speed overstates them by at most
      // one full step of friction, giving a public-observable budget bound.
      expect(totalExtraAtStepStart, lessThanOrEqualTo(budget / decay + 1e-5));
      expect(totalExtraAtStepStart, greaterThan(budget * .95));
      expect(e.shots, 1);
      for (var i = 0; i < 600 && _speed(puck) > 0; i++) {
        _step(e);
      }
      expect(_speed(puck), 0);
    });

    test(
      'an unassisted shot hits multiple rails, stays bounded and settles',
      () {
        final e = _world(), puck = e.bodies.first;
        _place(puck, e.Fr - puck.r - .1, e.CY);
        e.fireVec(puck, 1, 0, 1);
        var contacts = 0;
        for (var i = 0; i < 1200 && _speed(puck) > 0; i++) {
          final previous = puck.vx;
          _step(e);
          if (previous * puck.vx < 0) contacts++;
          expect(
            puck.x.isFinite &&
                puck.y.isFinite &&
                puck.vx.isFinite &&
                puck.vy.isFinite,
            isTrue,
          );
          expect(_speed(puck), lessThanOrEqualTo(e.tu.vSafe + 1e-7));
        }
        expect(contacts, greaterThanOrEqualTo(2));
        expect(contacts, lessThan(10));
        expect(
          _speed(puck),
          0,
          reason: 'motion must settle without further shots',
        );
        final x = puck.x, y = puck.y;
        for (var i = 0; i < 120; i++) {
          _step(e);
        }
        expect([puck.x, puck.y, puck.vx, puck.vy], [x, y, 0.0, 0.0]);
        expect(e.shots, 1);
      },
    );
  });
}
