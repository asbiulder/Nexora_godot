// The TypeScript numeric/event traces in parity_ts.json are archival: the
// replacement solver deliberately does not reproduce the legacy trajectory.
// Keep every original input scenario and exercise deterministic replay and
// gameplay invariants instead of manufacturing a new numeric golden trace.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

/// mulberry32, bit-identical to the JS version used by run_ts.ts.
double Function() mulberry32(int seed) {
  var a = seed & 0xffffffff;
  int imul(int x, int y) => ((x & 0xffffffff) * (y & 0xffffffff)) & 0xffffffff;
  return () {
    a = (a + 0x6D2B79F5) & 0xffffffff;
    var t = imul(a ^ (a >> 15), 1 | a);
    t = ((t + imul(t ^ (t >> 7), 61 | t)) & 0xffffffff) ^ t;
    return ((t ^ (t >> 14)) & 0xffffffff) / 4294967296;
  };
}

/// Shared with the Godot fixture replay. Compare independent engines every
/// frame, including events, rather than just comparing their final positions.
class ReplayChecks {
  final Engine a, b;
  late final int bodyCount = a.bodies.length;
  final List<int> previousScore = [0, 0];
  Phase previousPhase = Phase.aim;
  int shotEvents = 0;
  int goalEvents = 0;

  ReplayChecks(this.a, this.b);

  List<Object> _state(Engine e) => [
    e.phase,
    e.turn,
    e.shots,
    ...e.score,
    e.acc,
    e.time,
    e.mleft,
    e.tleft,
    e.idle,
    e.pause,
    e.kick,
    e.slow,
    e.sudden,
    e.aiT,
    e.nParts,
    e.nTrail,
    e.lastPower,
    e.lastUx,
    e.lastUy,
    e.lastV,
    for (final body in e.bodies) ...[
      body.id,
      body.team,
      body.x,
      body.y,
      body.px,
      body.py,
      body.vx,
      body.vy,
      body.r,
      body.im,
      body.spin,
      body.ang,
      body.sq,
      body.fly,
      ...body.R,
    ],
    for (var i = 0; i < e.eventCount; i++) ...[
      e.event(i).t,
      e.event(i).team,
      e.event(i).ball,
      e.event(i).power,
      e.event(i).nogoal,
      e.event(i).s0,
      e.event(i).s1,
    ],
  ];

  void check(int frame, String name) {
    final context = '$name frame $frame';
    expect(
      _state(a),
      _state(b),
      reason: '$context: independent replay diverged',
    );
    expect(a.bodies.length, bodyCount, reason: context);
    expect(a.bodies.where((body) => body.team == 2).length, 1, reason: context);
    expect(a.bodies.contains(a.ball), isTrue, reason: context);
    expect(a.turn, inInclusiveRange(0, 1), reason: context);
    expect(a.nParts, inInclusiveRange(0, Engine.maxParts), reason: context);
    expect(a.nTrail, inInclusiveRange(0, Engine.maxTrail), reason: context);
    for (final value in [
      a.acc,
      a.time,
      a.mleft,
      a.tleft,
      a.idle,
      a.pause,
      a.slow,
      a.aiT,
    ]) {
      expect(
        value.isFinite,
        isTrue,
        reason: '$context: non-finite engine state',
      );
    }
    expect(a.acc, greaterThanOrEqualTo(0), reason: context);
    expect(a.acc, lessThan(a.step + 1e-9), reason: context);

    if (previousPhase == Phase.over) {
      expect(a.phase, Phase.over, reason: '$context: ended match resumed');
    } else if (previousPhase == Phase.goal) {
      expect(
        [Phase.goal, Phase.aim, Phase.over],
        contains(a.phase),
        reason: context,
      );
    } else if (previousPhase == Phase.move) {
      expect(
        [Phase.move, Phase.aim, Phase.goal],
        contains(a.phase),
        reason: context,
      );
    }
    previousPhase = a.phase;

    final goals = [0, 0];
    for (var i = 0; i < a.eventCount; i++) {
      final event = a.event(i);
      expect(
        event.power.isFinite,
        isTrue,
        reason: '$context: non-finite event',
      );
      if (event.t == EvType.goal ||
          event.t == EvType.turn ||
          event.t == EvType.shot) {
        expect(event.team, inInclusiveRange(0, 1), reason: context);
      }
      if (event.t == EvType.shot) shotEvents++;
      if (event.t == EvType.goal) {
        goalEvents++;
        expect(
          event.nogoal,
          a.shots <= 1,
          reason: '$context: first-shot goal rule',
        );
        if (!event.nogoal) goals[event.team]++;
      }
    }
    for (var team = 0; team < 2; team++) {
      expect(
        a.score[team],
        previousScore[team] + goals[team],
        reason: '$context: score must change only for a valid goal event',
      );
      previousScore[team] = a.score[team];
    }

    for (final body in a.bodies) {
      for (final value in [
        body.x,
        body.y,
        body.px,
        body.py,
        body.vx,
        body.vy,
        body.spin,
        body.ang,
        body.sq,
        ...body.R,
      ]) {
        expect(
          value.isFinite,
          isTrue,
          reason: '$context: non-finite body ${body.id}',
        );
      }
      // Goal mouths are open. Bodies may enter the net, but not escape the
      // pitch sides or the back of either net. Radius is included in bounds.
      const epsilon = 1e-5;
      expect(
        body.x,
        inInclusiveRange(a.Fl + body.r - epsilon, a.Fr - body.r + epsilon),
        reason: '$context: body ${body.id} outside side walls',
      );
      expect(
        body.y,
        inInclusiveRange(
          a.Ft - a.DEPTH + body.r - epsilon,
          a.Fb + a.DEPTH - body.r + epsilon,
        ),
        reason: '$context: body ${body.id} beyond goal backs',
      );
      if (body.x <= a.goals[0].x1 || body.x >= a.goals[0].x2) {
        expect(
          body.y,
          inInclusiveRange(a.Ft + body.r - epsilon, a.Fb - body.r + epsilon),
          reason: '$context: body ${body.id} outside closed end rail',
        );
      }
    }
    a.clearEvents();
    b.clearEvents();
  }
}

MatchCfg _scenarioCfg(Map<String, dynamic> s) {
  final stats = s['stats'] as List?;
  return MatchCfg(
    field: s['field'],
    ball: s['ball'],
    forms: (s['forms'] as List).cast<int>(),
    ai: s['ai'],
    aiLvl: s['aiLvl'],
    limit: s['limit'],
    matchTime: (s['matchTime'] as num).toDouble(),
    turnTime: (s['turnTime'] as num).toDouble(),
    vip: (s['vip'] as List).cast<bool>(),
    first: s['first'],
    stats: stats
        ?.map(
          (x) => DiscStats((x[0] as num).toDouble(), (x[1] as num).toDouble()),
        )
        .toList(),
    profile: 'classic',
  );
}

void main() {
  final scenarios = (jsonDecode(
    File('tool/parity/scenarios.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  final archive = (jsonDecode(
    File('test/fixtures/parity_ts.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  test('legacy TypeScript archive covers the original scenario names', () {
    expect(
      archive.map((s) => s['name']).toList(),
      scenarios.map((s) => s['name']).toList(),
    );
    for (final entry in archive) {
      expect(entry['cps'], isNotEmpty);
      expect(entry['evs'], isNotEmpty);
    }
  });

  for (final s in scenarios) {
    test('classic deterministic fixture replay ${s['name']}', () {
      final a = Engine(_scenarioCfg(s), rand: mulberry32(12345));
      final b = Engine(_scenarioCfg(s), rand: mulberry32(12345));
      if (s['aiTeam0'] == true) a.aiTeams[0] = b.aiTeams[0] = true;
      final checks = ReplayChecks(a, b);
      final dts = (s['dt'] as List).map((x) => (x as num).toDouble()).toList();
      final shots = (s['shots'] as List).cast<Map<String, dynamic>>();
      for (var frame = 0; frame < (s['frames'] as int); frame++) {
        for (final e in [a, b]) {
          for (final shot in shots) {
            if (shot['f'] == frame && e.phase == Phase.aim) {
              final mine = e.bodies
                  .where((body) => body.team == e.turn)
                  .toList();
              final idx = (shot['b'] as int) % 5;
              final body = idx < mine.length ? mine[idx] : e.bodies[0];
              final dx = (shot['dx'] as num).toDouble(),
                  dy = (shot['dy'] as num).toDouble();
              e.fire(body, dx, dy, hyp(dx, dy), s['human'] == true);
            }
          }
          e.update(dts[frame % dts.length]);
        }
        checks.check(frame, s['name'] as String);
      }
      expect(
        checks.shotEvents,
        greaterThan(0),
        reason: 'fixture must actually exercise shots',
      );
    });
  }

  test('scoring: both goals and first-shot rejection remain consistent across profiles', () {
    for (final profile in ['classic', 'godot', 'stars']) {
      for (var team = 0; team < 2; team++) {
        for (final shots in [1, 2]) {
          final e = Engine(
            MatchCfg(
              field: 0,
              ball: 0,
              forms: [0, 0],
              ai: false,
              aiLvl: 1,
              limit: 3,
              matchTime: 0,
              turnTime: 0,
              vip: [false, false],
              first: 0,
              profile: profile,
            ),
            rand: math.Random(1).nextDouble,
          );
          final goal = e.goals[team], ball = e.ball;
          ball.x = ball.px = (goal.x1 + goal.x2) / 2;
          ball.y = ball.py = goal.y - goal.d * ball.r;
          ball.vx = 0;
          ball.vy = goal.d * 1200;
          e.shots = shots;
          e.phase = Phase.move;
          e.clearEvents();
          for (var frame = 0; frame < 30 && e.phase != Phase.goal; frame++) {
            e.update(1 / 60);
          }
          final events = [for (var i = 0; i < e.eventCount; i++) e.event(i)];
          final goals = events
              .where((event) => event.t == EvType.goal)
              .toList();
          final why = '$profile goal=$team shots=$shots';
          expect(e.phase, Phase.goal, reason: why);
          expect(goals.length, 1, reason: why);
          expect(goals.single.team, team, reason: why);
          expect(goals.single.nogoal, shots == 1, reason: why);
          expect(e.score, [
            for (var t = 0; t < 2; t++) t == team && shots == 2 ? 1 : 0,
          ], reason: why);
        }
      }
    }
  });
}
