import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
import 'package:portal/main.dart';
import 'package:portal/servisler/kimlik_servisi.dart';

const _oturum = Oturum(
  kullaniciId: 'k1',
  kiraciId: 'kiraci1',
  adSoyad: 'Av. Deneme',
  eposta: 'deneme@buro.com.tr',
  kurumAdi: 'Deneme Hukuk',
  hesapTuru: HesapTuru.hukukBurosu,
  roller: {Rol.yoneticiOrtak},
);

Widget _kabuk() => MaterialApp(home: AnaKabuk(oturum: _oturum, cikisYap: () {}));

void _buyukEkran(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _yaz(WidgetTester tester, String anahtar, String metin) =>
    tester.enterText(find.byKey(Key(anahtar)), metin);

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Dar ekranda çekmece menüyle hesaplamalar açılır ve hesap yapar', (tester) async {
    await tester.pumpWidget(_kabuk());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menüyü aç'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hesaplamalar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hesaplamalar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Deneme sürümü'), findsOneWidget);
    await _bas(tester, 'hesapla');

    expect(find.byKey(const Key('son-gun')), findsOneWidget);
    expect(find.text('Hesap adımları'), findsOneWidget);
  });

  testWidgets('Hesap türleri ekranı üç türü gösterir', (tester) async {
    _buyukEkran(tester);
    await tester.pumpWidget(_kabuk());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu-ayarlar')));
    await tester.pumpAndSettle();

    expect(find.text('Avukatlık Bürosu'), findsOneWidget);
    expect(find.text('Hukuk Bürosu'), findsOneWidget);
    expect(find.text('Kurumsal'), findsOneWidget);
  });

  testWidgets('Hatalı giriş hata mesajı gösterir', (tester) async {
    _buyukEkran(tester);
    await tester.pumpWidget(PortalUygulamasi(kimlikServisi: BellekKimlikServisi()));
    await tester.pumpAndSettle();

    await _yaz(tester, 'giris-eposta', 'yok@buro.com.tr');
    await _yaz(tester, 'giris-sifre', 'Yanlis12345');
    await _bas(tester, 'giris-yap');

    expect(find.byKey(const Key('giris-hata')), findsOneWidget);
  });

  testWidgets('Kayıt sihirbazı tamamlanır, ardından giriş yapılır', (tester) async {
    _buyukEkran(tester);
    final servis = BellekKimlikServisi();
    await tester.pumpWidget(PortalUygulamasi(kimlikServisi: servis));
    await tester.pumpAndSettle();

    await _bas(tester, 'kayit-ol');

    // 1. Hesap türü seçilmeden ilerlenemez
    await _bas(tester, 'kayit-ileri');
    expect(find.byKey(const Key('kayit-hata')), findsOneWidget);
    await _bas(tester, 'tur-hukukBurosu');
    await _bas(tester, 'kayit-ileri');

    // 2. Hesap bilgileri
    await _yaz(tester, 'kayit-ad', 'Ayşe Yılmaz');
    await _yaz(tester, 'kayit-kurum', 'Yılmaz Hukuk Bürosu');
    await _yaz(tester, 'kayit-eposta', 'ayse@yilmazhukuk.com.tr');
    await _yaz(tester, 'kayit-telefon', '0532 123 45 67');
    await _yaz(tester, 'kayit-sifre', 'Mavi2026Deniz');
    await _yaz(tester, 'kayit-sifre-tekrar', 'Mavi2026Deniz');
    await _bas(tester, 'kayit-ileri');

    // 3. Fatura: geçersiz vergi numarası reddedilir
    await _yaz(tester, 'kayit-tckn-vkn', '9876543210');
    await _yaz(tester, 'kayit-vergi-dairesi', 'Kadıköy');
    await _yaz(tester, 'kayit-adres', 'Moda Cad. No:1 Kadıköy İstanbul');
    await _bas(tester, 'kayit-ileri');
    expect(find.text('Vergi kimlik numarası geçersiz.'), findsOneWidget);
    await _yaz(tester, 'kayit-tckn-vkn', '1234567890');
    await _bas(tester, 'kayit-ileri');

    // 4. Zorunlu onaylar olmadan deneme başlamaz
    await _bas(tester, 'kayit-ileri');
    expect(find.byKey(const Key('kayit-hata')), findsOneWidget);
    await _bas(tester, 'onay-sozlesme');
    await _bas(tester, 'onay-kvkk');
    await _bas(tester, 'kayit-ileri');

    expect(find.text('Hesabınız oluşturuldu'), findsOneWidget);
    await _bas(tester, 'girise-don');

    // Giriş
    await _yaz(tester, 'giris-eposta', 'ayse@yilmazhukuk.com.tr');
    await _yaz(tester, 'giris-sifre', 'Mavi2026Deniz');
    await _bas(tester, 'giris-yap');

    expect(find.textContaining('Yılmaz Hukuk Bürosu'), findsOneWidget);
    expect(servis.oturum?.hesapTuru, HesapTuru.hukukBurosu);
    expect(servis.oturum?.roller, contains(Rol.yoneticiOrtak));

    await _bas(tester, 'profil-menu');
    await _bas(tester, 'cikis-yap');
    expect(find.byKey(const Key('giris-yap')), findsOneWidget);
  });
}
