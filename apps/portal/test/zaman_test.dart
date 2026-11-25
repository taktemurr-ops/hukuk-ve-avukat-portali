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

Future<BellekVeriDeposu> _ac(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1');
  await tester.pumpWidget(MaterialApp(theme: acikTema(), home: AnaKabuk(oturum: _oturum, cikisYap: () {}, depo: depo)));
  await tester.pumpAndSettle();
  await _bas(tester, 'menu-zaman');
  return depo;
}

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

Future<void> _dosyaSec(WidgetTester tester, String anahtar, String dosyaBasligi) async {
  await _bas(tester, anahtar);
  // Açılan menüdeki öğeye dokunulur (alanın kendi metnine değil).
  var oge = find.descendant(of: find.byType(MenuItemButton), matching: find.textContaining(dosyaBasligi));
  if (oge.hitTestable().evaluate().isEmpty) {
    // Menü açılmadıysa sağdaki ok düğmesiyle açılır.
    await tester.tap(find.descendant(of: find.byKey(Key(anahtar)), matching: find.byType(IconButton)).first);
    await tester.pumpAndSettle();
    oge = find.descendant(of: find.byType(MenuItemButton), matching: find.textContaining(dosyaBasligi)).hitTestable();
  }
  await tester.tap(oge.evaluate().isNotEmpty ? oge.last : find.textContaining(dosyaBasligi).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Zaman kaydı menüsü yalnızca Hukuk Bürosu paketinde', (tester) async {
    tester.view.physicalSize = const Size(1500, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const tek = Oturum(
        kullaniciId: 'av1',
        kiraciId: 'k1',
        adSoyad: 'A',
        eposta: 'a@b.com',
        kurumAdi: 'B',
        hesapTuru: HesapTuru.avukatlikBurosu,
        roller: {Rol.buroSahibi});
    await tester.pumpWidget(MaterialApp(theme: acikTema(), home: AnaKabuk(oturum: tek, cikisYap: () {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-zaman')), findsNothing);
  });

  testWidgets('Onay, faturalama ve cariye tahakkuk', (tester) async {
    final depo = await _ac(tester);
    expect(find.byKey(const Key('zaman-sil-z1')), findsOneWidget);
    expect(find.byKey(const Key('zaman-onayla-z1')), findsNothing);
    await _bas(tester, 'zaman-onayla-z5');
    expect(depo.zaman.kayit('z5')!.durum, ZamanDurumu.onaylandi);

    expect(depo.zamanFaturaOnizleme('d1').toplam, Para.tl(3200));
    await _bas(tester, 'zaman-fatura-d1');
    await _bas(tester, 'zaman-fatura-onay');
    expect(depo.zaman.kayit('z2')!.durum, ZamanDurumu.faturalandi);
    final tahakkuk = depo.cariHareketler('abc').firstWhere((h) => (h.belge ?? '').startsWith('ZF-'));
    expect(tahakkuk.tutar, Para.tl(3200));
    expect(tahakkuk.tur, CariHareketTuru.ucretTahakkuku);
    expect(find.byKey(const Key('zaman-fatura-d1')), findsNothing);
  });

  testWidgets('Gelir paylaşımı ve elle zaman kaydı', (tester) async {
    final depo = await _ac(tester);
    await _dosyaSec(tester, 'paylasim-dosya', 'ABC Gıda - Tedarik alacağı');
    await tester.enterText(find.byKey(const Key('paylasim-tutar')), '10000');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('paylasim-av1'))).data, '4.435,89 TL');
    expect(tester.widget<Text>(find.byKey(const Key('paylasim-demo-av2'))).data, '1.538,46 TL');
    expect(tester.widget<Text>(find.byKey(const Key('paylasim-büro'))).data, '3.000,01 TL');

    await _bas(tester, 'zaman-elle');
    await _bas(tester, 'zaman-kaydet');
    expect(find.byKey(const Key('zaman-hata')), findsOneWidget);
    await _dosyaSec(tester, 'zaman-dosya', 'Kara - İşe iade');
    await tester.enterText(find.byKey(const Key('zaman-sure')), '1:30');
    await tester.enterText(find.byKey(const Key('zaman-aciklama')), 'Arabuluculuk tutanağı incelemesi');
    await _bas(tester, 'zaman-kaydet');
    final yeni = depo.zaman.kayitlar.last;
    expect(yeni.dosyaId, 'd2');
    expect(yeni.dakika, 90);
    expect(yeni.kullanici, 'av1');
    expect(yeni.saatlikUcret, Para.tl(3000));
  });

  testWidgets('Kronometre başlatılır, bitirilince kayıt oluşur', (tester) async {
    final depo = await _ac(tester);
    final once = depo.zaman.kayitlar.length;
    await _bas(tester, 'kronometre-baslat');
    expect(find.text('Önce dosya seçin.'), findsOneWidget);
    await _dosyaSec(tester, 'kronometre-dosya', 'Kara - İşe iade');
    await tester.tap(find.byKey(const Key('kronometre-baslat')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('kronometre-duraklat')), findsOneWidget);
    await tester.tap(find.byKey(const Key('kronometre-bitir')));
    await tester.pumpAndSettle();
    expect(depo.zaman.kayitlar.length, once + 1);
    expect(depo.zaman.kayitlar.last.aciklama, 'Kronometre ile kaydedilen çalışma');
  });
}
