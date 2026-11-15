// v9: online pitch/ball sync (host's choice in every snapshot as s.fb) and the online rematch state machine.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/data.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/net/supabase.dart';
import 'package:nexora/online/netcode.dart';
import 'package:nexora/online/online_match.dart';
import 'package:nexora/online/rematch.dart';

class _Port implements NetPort {
  final List<Map<String, dynamic>> sent = [];
  @override
  String get me => 'H';
  @override
  bool get allFlutter => true;
  @override
  List<Player> get players => const [];
  @override
  void send(Map<String, dynamic> m) => sent.add(jsonDecode(jsonEncode(m)) as Map<String, dynamic>);
  @override
  bool isOnline(String uid) => true;
  @override
  int get peers => 1;
  @override
  DiscStats statsFor(String disc) => const DiscStats(6, 6);
}

Rec _p(String u, int team, bool ready) => Rec({'user_id': u, 'role': 'player', 'team': team, 'slot': 0, 'ready': ready});

void main() {
  test('retuned physics uses protocol version 11', () => expect(kProtoVersion, 11));

  group('host pitch/ball', () {
    test('custom room: room pitch, host ball', () {
      final r = Rec({'kind': 'casual', 'settings': {'field': 3, 'ball': 0}});
      expect(hostFieldBall(r, 7, 12), (3, 12));
    });
    test('matchmade room: host equipped pitch and ball (server default ignored)', () {
      for (final k in ['quick', 'arena', 'duel', 'tournament']) {
        final r = Rec({'kind': k, 'settings': {'field': 29}});
        expect(hostFieldBall(r, 5, 9), (5, 9), reason: k);
      }
    });
    test('tournament uses shared assets only after the host selects them', () {
      final r = Rec({'kind': 'tournament', 'settings': {'field': 3, 'ball': 12, 'shared_assets': true}});
      expect(hostFieldBall(r, 5, 9), (3, 12));
    });
    test('custom room without a pitch setting -> host equipped pitch; values clamped', () {
      expect(hostFieldBall(Rec({'kind': 'social', 'settings': {}}), 4, 2), (4, 2));
      expect(hostFieldBall(Rec({'settings': {'field': 999}}), 0, 99), (kFields.length - 1, 35));
    });
    test('client parses s.fb (and rejects junk)', () {
      expect(snapFieldBall({'fb': [6, 11]}), (6, 11));
      expect(snapFieldBall({'fb': [-3, 500]}), (0, 35));
      expect(snapFieldBall({}), isNull);
      expect(snapFieldBall({'fb': [1]}), isNull);
      expect(snapFieldBall({'fb': ['x', 2]}), isNull);
    });
    test('host snapshot carries fb = [field, ball] and the current physics version', () {
      final eng = Engine(MatchCfg(field: 8, ball: 14, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0, vip: [false, false], first: 0, stats: [const DiscStats(6, 6), const DiscStats(6, 6)]));
      final port = _Port();
      final host = NetMatch(eng: eng, isHost: true, port: port, onEvent: (_, _) {});
      for (var t = 16; t < 3000 && port.sent.isEmpty; t += 16) {
        host.tick(1 / 60, t);
      }
      final s = port.sent.firstWhere((m) => m['k'] == 's')['s'] as Map;
      expect(s['fb'], [8, 14]);
      expect(s['pv'], kProtoVersion);
      expect(snapFieldBall(s), (8, 14));
    });
  });

  group('rematch', () {
    final room = Rec({'id': 'r', 'host': 'A', 'kind': 'casual', 'status': 'waiting'});
    test('states', () {
      expect(rematchState(room, [_p('A', 0, false), _p('B', 1, false)], 'A'), Rematch.idle);
      expect(rematchState(room, [_p('A', 0, true), _p('B', 1, false)], 'A'), Rematch.asked);
      expect(rematchState(room, [_p('A', 0, false), _p('B', 1, true)], 'A'), Rematch.offered);
      expect(rematchState(room, [_p('A', 0, true), _p('B', 1, true)], 'A'), Rematch.starting);
      expect(rematchState(room, [_p('A', 0, true)], 'A'), Rematch.oppLeft);
      expect(rematchState(room, [_p('A', 0, false), _p('B', 1, false)], 'S'), Rematch.off, reason: 'spectator');
      expect(rematchState(room.merge({'status': 'playing'}), [_p('A', 0, false), _p('B', 1, false)], 'A'), Rematch.wait);
      expect(rematchState(room.merge({'tournament_match_id': 'tm'}), [_p('A', 0, false), _p('B', 1, false)], 'A'), Rematch.off);
      expect(rematchState(null, const [], 'A'), Rematch.off);
    });
    test('starter: host at once; others only in matchmade rooms after the grace period', () {
      expect(rematchStarter(isHost: true, kind: 'casual', waited: Duration.zero), isTrue);
      expect(rematchStarter(isHost: false, kind: 'casual', waited: const Duration(seconds: 30)), isFalse);
      expect(rematchStarter(isHost: false, kind: 'quick', waited: const Duration(seconds: 1)), isFalse);
      expect(rematchStarter(isHost: false, kind: 'quick', waited: const Duration(seconds: 5)), isTrue);
    });
  });
}
