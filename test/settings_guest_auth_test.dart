import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexora/net/supabase.dart';
import 'package:nexora/screens/settings.dart';
import 'package:nexora/ui/chrome.dart';
import 'package:nexora/ui/kit.dart';

const guestButton = 'ادامه به‌عنوان مهمان';
const success = 'به‌عنوان مهمان وارد شدی';
const failure = 'اتصال برقرار نشد';

void main() {
  final toasts = <(String, String)>[];
  void listen(String message, String kind) => toasts.add((message, kind));

  setUp(() {
    toasts.clear();
    toastListeners.add(listen);
  });
  tearDown(() => toastListeners.remove(listen));

  Future<void> showPanel(WidgetTester tester, {Future<String?> Function()? ensure}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: AccountPanel(ensureGuest: ensure))),
    ));
    await tester.pump();
  }

  Future<void> tapGuest(WidgetTester tester) async {
    await tester.tap(find.text(guestButton));
    await tester.pump();
  }

  testWidgets('real ensure with Supabase unavailable reports failure', (tester) async {
    final previous = supaReady;
    supaReady = false;
    addTearDown(() => supaReady = previous);
    await showPanel(tester);
    await tapGuest(tester);
    expect(toasts, [(failure, 'err')]);
    expect(toasts.any((t) => t.$1 == success), isFalse);
  });

  testWidgets('a non-null ID reports success', (tester) async {
    await showPanel(tester, ensure: () async => 'local-test-user');
    await tapGuest(tester);
    expect(toasts, [(success, 'ok')]);
  });

  testWidgets('an exception reports failure', (tester) async {
    await showPanel(tester, ensure: () async => throw StateError('offline'));
    await tapGuest(tester);
    expect(toasts, [(failure, 'err')]);
  });

  testWidgets('pending guest sign-in disables the button and is not duplicated', (tester) async {
    final result = Completer<String?>();
    var calls = 0;
    await showPanel(tester, ensure: () {
      calls++;
      return result.future;
    });
    await tapGuest(tester);
    final button = tester.widget<Btn>(find.ancestor(of: find.text(guestButton), matching: find.byType(Btn)));
    expect(button.disabled, isTrue);
    await tapGuest(tester);
    expect(calls, 1);
    result.complete(null);
    await tester.pump();
    expect(toasts, [(failure, 'err')]);
  });

  testWidgets('disposed panel does not show a stale result', (tester) async {
    final result = Completer<String?>();
    await showPanel(tester, ensure: () => result.future);
    await tapGuest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    result.complete('local-test-user');
    await tester.pump();
    expect(toasts, isEmpty);
  });
}
