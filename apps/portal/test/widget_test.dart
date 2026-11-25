import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/main.dart';

void main() {
  testWidgets('Uygulama açılır ve süre hesaplanır', (tester) async {
    await tester.pumpWidget(const PortalUygulamasi());
    await tester.pumpAndSettle();

    expect(find.textContaining('Deneme sürümü'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hesapla')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('son-gun')), findsOneWidget);
    expect(find.text('Hesap adımları'), findsOneWidget);
  });

  testWidgets('Hesap türleri ekranı üç türü gösterir', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PortalUygulamasi());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hesap türleri').last);
    await tester.pumpAndSettle();

    expect(find.text('Avukatlık Bürosu'), findsOneWidget);
    expect(find.text('Hukuk Bürosu'), findsOneWidget);
    expect(find.text('Kurumsal'), findsOneWidget);
  });
}
