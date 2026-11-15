import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'cup_logic.dart';

/// Device-local reminder for cups the signed-in player has joined. The server's realtime
/// notifications remain the fallback while the app is open; no FCM credentials are required.
class CupReminderService {
  CupReminderService._();
  static final i = CupReminderService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Map<String, int> _scheduled = {};
  bool _ready = false, _requestedPermission = false;
  void Function(String cupId)? _open;

  Future<void> init(void Function(String cupId) open) async {
    if (_ready) {
      _open = open;
      return;
    }
    _open = open;
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null && id.isNotEmpty) _open?.call(id);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final launchCup = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && launchCup != null && launchCup.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open?.call(launchCup));
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'cup_reminders',
      'یادآور تورنمنت',
      description: 'یادآوری ده دقیقه پیش از شروع و اعلام حضور',
      importance: Importance.high,
    ));
    _ready = true;
  }

  int _id(String value) {
    var h = 0x811c9dc5;
    for (final c in value.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h == 0 ? 1 : h;
  }

  Future<void> sync({required String cupId, required String name, required DateTime startsAt, required bool eligible}) async {
    if (!_ready || cupId.isEmpty) return;
    final at = startsAt.toUtc().subtract(const Duration(minutes: kCupReminderMinutes));
    if (!eligible || !at.isAfter(DateTime.now().toUtc())) {
      await cancel(cupId);
      return;
    }
    final epoch = at.millisecondsSinceEpoch;
    if (_scheduled[cupId] == epoch) return;
    if (!_requestedPermission) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final allowed = await android?.requestNotificationsPermission();
      _requestedPermission = true;
      if (allowed == false) return;
    }
    await _plugin.zonedSchedule(
      _id(cupId),
      '۱۰ دقیقه تا شروع تورنمنت',
      '«$name» نزدیک است؛ وارد صفحه شو و اعلام حضور کن.',
      tz.TZDateTime.from(at, tz.UTC),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'cup_reminders',
          'یادآور تورنمنت',
          channelDescription: 'یادآوری ده دقیقه پیش از شروع و اعلام حضور',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: cupId,
    );
    _scheduled[cupId] = epoch;
  }

  Future<void> cancel(String cupId) async {
    if (!_ready || cupId.isEmpty) return;
    _scheduled.remove(cupId);
    await _plugin.cancel(_id(cupId));
  }
}
