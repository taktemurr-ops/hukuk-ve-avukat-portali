import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/hesap_ekranlari.dart';
import 'package:portal/servisler/kimlik_servisi.dart';
import 'package:portal/servisler/veri_deposu.dart';
import 'package:portal/tema/tema.dart';

const _oturum = Oturum(
  kullaniciId: 'av1',
  kiraciId: 'buro1',
  adSoyad: 'Av. Ayşe Yılmaz',
  eposta: 'ayse@buro.com.tr',
  kurumAdi: 'Yılmaz Hukuk',
  hesapTuru: HesapTuru.hukukBurosu,
  roller: {Rol.yoneticiOrtak},
);

final _an = DateTime.utc(2026, 12, 1, 9);

HesapYonetimi _yonetim() => HesapYonetimi(
      oturum: _oturum,
      depo: BellekVeriDeposu.demo(kiraciId: 'buro1', avukatId: 'av1'),
      bugun: Tarih(2026, 12, 1),
      saat: () => _an,
    );

Future<void> _ac(WidgetTester tester, Widget ekran) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: acikTema(), home: ekran));
  await tester.pumpAndSettle();
}

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

void main() {
  group('HesapYonetimi', () {
    test('davetler lisans koltuğuyla sınırlıdır; ücretsiz roller koltuk tüketmez', () {
      final y = _yonetim();
      expect(y.aktifKoltuk, 3);
      expect(y.davetEt('yanlis', {Rol.avukat}), isNotNull);
      expect(y.davetEt('a@b.com', {}), 'En az bir rol seçilmelidir.');
      expect(y.davetEt('a@b.com', {Rol.avukat}), isNull);
      expect(y.davetEt('A@b.com', {Rol.avukat}), contains('bekleyen'));
      expect(y.davetEt('c@b.com', {Rol.sekreter}), isNull);
      expect(y.davetEt('d@b.com', {Rol.avukat}), contains('5/5'));
      expect(y.davetEt('m@b.com', {Rol.muvekkil}), isNull);
      y.davetIptal(y.davetler.first);
      expect(y.davetEt('d@b.com', {Rol.avukat}), isNull);
      expect(y.depo.denetim.olaylar.last.islem, DenetimIslemi.rolVerme);
    });

    test('koltuk aktif kullanıcının altına inmez', () {
      final y = _yonetim();
      expect(y.koltukGuncelle(2), isNotNull);
      expect(y.koltukGuncelle(4), isNull);
      expect(y.lisansKoltugu, 4);
    });
  });

  testWidgets('Abonelik: koltuk ve dönem değişince fatura güncellenir, ödeme aktif eder', (tester) async {
    final y = _yonetim();
    await _ac(tester, AbonelikEkrani(yonetim: y));
    expect(find.text('Deneme'), findsOneWidget);
    expect(find.text('9.000,00 TL'), findsOneWidget); // 5 koltuk × 1.500 + %20 KDV
    await _bas(tester, 'koltuk-artir');
    expect(find.text('10.800,00 TL'), findsOneWidget);
    await tester.tap(find.text('Yıllık (2 ay hediye)'));
    await tester.pumpAndSettle();
    expect(find.text('108.000,00 TL'), findsOneWidget);
    await _bas(tester, 'odeme-yap');
    await _bas(tester, 'odeme-basarili');
    expect(find.text('Aktif'), findsOneWidget);
    expect(y.abonelik.donemSonu, Tarih(2027, 12, 1));
    await _bas(tester, 'abonelik-iptal');
    await _bas(tester, 'iptal-onay');
    expect(y.abonelik.donemSonundaIptal, isTrue);
    expect(find.textContaining('iptal edilecek'), findsOneWidget);
  });

  testWidgets('İki adımlı doğrulama doğru kodla açılır, yanlış kodla açılmaz', (tester) async {
    final y = _yonetim();
    await _ac(tester, IkiAdimliEkrani(yonetim: y));
    await _bas(tester, 'totp-baslat');
    final anahtar = tester.widget<SelectableText>(find.byKey(const Key('totp-anahtar'))).data!.replaceAll(' ', '');
    final sir = Totp.base32Coz(anahtar);

    await tester.enterText(find.byKey(const Key('totp-kod')), '000000' == Totp.kod(sir, _an) ? '111111' : '000000');
    await _bas(tester, 'totp-onayla');
    expect(y.ikiAdimliAcik, isFalse);
    expect(find.textContaining('doğrulanamadı'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('totp-kod')), Totp.kod(sir, _an));
    await _bas(tester, 'totp-onayla');
    expect(y.ikiAdimliAcik, isTrue);
    expect(find.text('Açık'), findsOneWidget);
  });

  testWidgets('Ekip ekranından davet gönderilir', (tester) async {
    final y = _yonetim();
    await _ac(tester, EkipEkrani(yonetim: y));
    expect(find.text('3 / 5'), findsOneWidget);
    await _bas(tester, 'davet-yeni');
    await tester.enterText(find.byKey(const Key('davet-eposta')), 'yeni@buro.com.tr');
    await _bas(tester, 'davet-gonder');
    expect(find.byKey(const Key('davet-hata')), findsOneWidget);
    await _bas(tester, 'rol-avukat');
    await _bas(tester, 'davet-gonder');
    expect(find.byKey(const Key('davet-yeni@buro.com.tr')), findsOneWidget);
    expect(find.text('4 / 5'), findsOneWidget);
  });
}
