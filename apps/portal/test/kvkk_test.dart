import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
import 'package:portal/servisler/kimlik_servisi.dart';
import 'package:portal/servisler/veri_deposu.dart';
import 'package:portal/tema/tema.dart';

const _oturum = Oturum(
  kullaniciId: 'av1',
  kiraciId: 'k1',
  adSoyad: 'Av. Ayşe Yılmaz',
  eposta: 'ayse@buro.com.tr',
  kurumAdi: 'Yılmaz Hukuk',
  hesapTuru: HesapTuru.hukukBurosu,
  roller: {Rol.yoneticiOrtak},
);

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('KVKK: imhaya hazır kayıt için tutanak, ikinci kişinin onayı ve imha', (tester) async {
    tester.view.physicalSize = const Size(1500, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1');
    await tester.pumpWidget(MaterialApp(theme: acikTema(), home: AnaKabuk(oturum: _oturum, cikisYap: () {}, depo: depo)));
    await tester.pumpAndSettle();
    await _bas(tester, 'menu-ayarlar');
    await _bas(tester, 'ayar-kvkk');

    expect(find.text('Gecikti'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('kvkk-ar2'))).onChanged, isNull);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('kvkk-ar5'))).onChanged, isNull);

    await _bas(tester, 'kvkk-ar1');
    await _bas(tester, 'kvkk-ar4');
    await _bas(tester, 'kvkk-tutanak');
    final t = depo.saklama.tutanaklar.single;
    expect(t.kayitIdleri, unorderedEquals(['ar1', 'ar4']));
    expect(find.text('İkinci onay bekliyor'), findsOneWidget);

    depo.aktifKullanici = 'demo-av2';
    depo.portalPaylas('d1', true);
    await tester.pumpAndSettle();
    await _bas(tester, 'kvkk-onayla-${t.no}');
    expect(t.onaylayan, 'demo-av2');
    expect(find.byKey(const Key('kvkk-ar1')), findsNothing);
    expect(find.text('Zamanında'), findsOneWidget);
    expect(depo.denetim.olaylar.last.islem, DenetimIslemi.silme);
  });
}
