// godot_nx8.json was produced by the historical Godot build. Its recorded
// numeric/event traces are archival and are not a golden for the replacement
// solver. Its fields, formations, shot powers, and frame counts remain inputs.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

import 'parity_test.dart' show ReplayChecks;

Engine _engine(Map<String, dynamic> s) {
  return Engine(
    MatchCfg(
      field: s['field'],
      ball: 0,
      forms: (s['forms'] as List).cast<int>(),
      ai: false,
      aiLvl: 1,
      limit: 99,
      matchTime: 0,
      turnTime: 0,
      vip: [false, false],
      first: 0,
      profile: 'godot',
    ),
    rand: math.Random(1).nextDouble,
  )..clearEvents();
}

void main() {
  final archive = (jsonDecode(
    File('test/fixtures/godot_nx8.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  for (final s in archive) {
    test('godot deterministic fixture replay ${s['name']}', () {
      // Retain the fixture's legacy traces for historical inspection, but do
      // not compare their values with the deliberately changed physics.
      expect(s['cps'], isNotEmpty);
      expect(s['evs'], isNotEmpty);
      final a = _engine(s), b = _engine(s);
      final checks = ReplayChecks(a, b);
      final powers = (s['pw'] as List)
          .map((x) => (x as num).toDouble())
          .toList();
      var shotA = 0, shotB = 0;

      int advance(Engine e, int shot) {
        if (e.phase == Phase.aim && shot < powers.length) {
          Body? best;
          var bestDistance = double.infinity;
          for (final body in e.bodies) {
            if (body.team == e.turn && !identical(body, e.ball)) {
              final dx = body.x - e.ball.x, dy = body.y - e.ball.y;
              final distance = dx * dx + dy * dy;
              if (distance < bestDistance) {
                bestDistance = distance;
                best = body;
              }
            }
          }
          expect(
            best,
            isNotNull,
            reason: 'the active team must have a shooter',
          );
          final dx = e.ball.x - best!.x, dy = e.ball.y - best.y;
          final distance = math.sqrt(dx * dx + dy * dy),
              length = powers[shot] * LMAX;
          expect(
            distance,
            greaterThan(0),
            reason: 'shot direction must be defined',
          );
          e.fire(best, dx / distance * length, dy / distance * length, length);
          shot++;
        }
        e.update(1 / 60);
        return shot;
      }

      for (var frame = 0; frame < (s['frames'] as int); frame++) {
        shotA = advance(a, shotA);
        shotB = advance(b, shotB);
        expect(shotA, shotB, reason: '${s['name']} shot count at frame $frame');
        checks.check(frame, s['name'] as String);
      }
      expect(
        shotA,
        greaterThan(0),
        reason: 'fixture must actually exercise shots',
      );
      expect(
        shotA,
        lessThanOrEqualTo(powers.length),
        reason: 'fixture shot inputs are bounded',
      );
      expect(
        checks.shotEvents,
        shotA,
        reason: 'each fired shot must be recorded',
      );
    });
  }
}
