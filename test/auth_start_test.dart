import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/screens/auth_start.dart';

void main() {
  testWidgets('welcome gate offers account, guest, and offline paths', (tester) async {
    var continued = false;
    await tester.pumpWidget(MaterialApp(home: AuthStartScreen(onContinue: () => continued = true)));
    await tester.pumpAndSettle();

    expect(find.text('به جهان نکسورا خوش آمدی'), findsOneWidget);
    expect(find.text('ثبت‌نام'), findsOneWidget);
    expect(find.text('ادامه به‌عنوان مهمان'), findsOneWidget);
    expect(find.text('فعلاً بدون حساب ادامه بده'), findsOneWidget);

    await tester.tap(find.text('فعلاً بدون حساب ادامه بده'));
    expect(continued, isTrue);
  });
}
