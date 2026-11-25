import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/bilesenler/bicim.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
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

Future<BellekVeriDeposu> _ac(WidgetTester tester, String menu) async {
  tester.view.physicalSize = const Size(1500, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final depo = BellekVeriDeposu.demo(kiraciId: 'buro1', avukatId: 'av1');
  await tester.pumpWidget(MaterialApp(theme: acikTema(), home: AnaKabuk(oturum: _oturum, cikisYap: () {}, depo: depo)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('menu-$menu')));
  await tester.pumpAndSettle();
  return depo;
}

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

void main() {
  test('Türkçe tutar biçimi çözülür', () {
    expect(tutarCoz('1.234.567,89'), 1234567.89);
    expect(tutarCoz('150.000'), 150000);
    expect(tutarCoz('2500.5'), 2500.5);
    expect(tutarCoz('abc'), isNull);
    expect(tutarCoz(''), isNull);
  });

  testWidgets('Dava harcı hesaplanır', (tester) async {
    await _ac(tester, 'hesaplamalar');
    await _bas(tester, 'sekme-harc');
    await tester.enterText(find.byKey(const Key('harc-deger')), '1.000.000');
    await _bas(tester, 'harc-hesapla');
    expect(find.text('17.077,50 TL'), findsOneWidget);
    expect(find.text('17.809,50 TL'), findsOneWidget);
  });

  testWidgets('Vekâlet ücreti güncel tarifeyle hesaplanır', (tester) async {
    await _ac(tester, 'hesaplamalar');
    await _bas(tester, 'sekme-ucret');
    await tester.enterText(find.byKey(const Key('ucret-deger')), '2.000.000');
    await _bas(tester, 'ucret-hesapla');
    expect(find.byKey(const Key('ucret-sonuc')), findsOneWidget);
    expect(find.text('304.000,00 TL'), findsWidgets);
  });

  testWidgets('Makbuz hesabı', (tester) async {
    await _ac(tester, 'hesaplamalar');
    await _bas(tester, 'sekme-makbuz');
    await tester.enterText(find.byKey(const Key('makbuz-tutar')), '10.000');
    await _bas(tester, 'makbuz-hesapla');
    expect(find.text('8.000,00 TL'), findsOneWidget);
  });

  testWidgets('Faiz hesabı sonuç verir', (tester) async {
    await _ac(tester, 'hesaplamalar');
    await _bas(tester, 'sekme-faiz');
    await tester.enterText(find.byKey(const Key('faiz-anapara')), '100.000');
    await _bas(tester, 'faiz-hesapla');
    expect(find.byKey(const Key('faiz-sonuc')), findsOneWidget);
  });

  testWidgets('İşçilik alacakları hesaplanır (taslak rozetiyle)', (tester) async {
    await _ac(tester, 'hesaplamalar');
    await _bas(tester, 'sekme-iscilik');
    await tester.enterText(find.byKey(const Key('iscilik-giydirilmis')), '30.000');
    await _bas(tester, 'iscilik-hesapla');
    expect(find.byKey(const Key('iscilik-sonuc')), findsOneWidget);
    expect(find.textContaining('Taslak'), findsOneWidget);
  });

  testWidgets('Döviz alacağı TL karşılığı', (tester) async {
    await _ac(tester, 'hesaplamalar');
    await _bas(tester, 'sekme-doviz');
    await tester.enterText(find.byKey(const Key('doviz-tutar')), '1.000');
    await tester.enterText(find.byKey(const Key('doviz-odeme-kuru')), '42');
    await tester.enterText(find.byKey(const Key('doviz-vade-kuru')), '45');
    await _bas(tester, 'doviz-hesapla');
    expect(find.text('45.000,00 TL'), findsOneWidget);
  });

  testWidgets('Finans: avans eksiye düşen müvekkil uyarılır, hareket eklenir, emanet uyarısı görünür', (tester) async {
    final depo = await _ac(tester, 'finans');
    expect(find.byKey(const Key('emanet-uyarisi')), findsOneWidget);
    expect(find.textContaining('Avans tükendi'), findsOneWidget);

    await _bas(tester, 'hareket-ekle-ayse');
    await tester.enterText(find.byKey(const Key('cari-tutar')), '0');
    await _bas(tester, 'cari-kaydet');
    expect(find.text('Geçerli bir tutar girin.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cari-tutar')), '500');
    await _bas(tester, 'cari-kaydet');
    expect(depo.cariOzet('ayse').toplamMasraf, Para.tl(2600));

    await _bas(tester, 'emanet-aktar-abc-d1');
    await _bas(tester, 'emanet-onayla');
    expect(depo.emanet.bakiye('abc'), Para.sifir);
    expect(find.byKey(const Key('emanet-uyarisi')), findsNothing);
  });

  testWidgets('Şablondan belge: eksik alan varken kaydedilmez, tamamlanınca SHA-256 ile kaydedilir', (tester) async {
    final depo = await _ac(tester, 'dosyalar');
    await _bas(tester, 'dosya-d1');
    final once = depo.dosyaBelgeleri('d1').length;
    await _bas(tester, 'sablondan-belge');
    await _bas(tester, 'sablon-IHTARNAME_ALACAK');

    final kaydet = tester.widget<FilledButton>(find.byKey(const Key('belge-kaydet')));
    expect(kaydet.onPressed, isNull);

    final alan = find.byKey(const Key('belge-metni'));
    final metin = tester.widget<TextField>(alan).controller!.text;
    final tamam = metin.replaceAll(RegExp(r'\[EKSİK: [^\]]+\]'), 'X');
    await tester.enterText(alan, tamam);
    await tester.pumpAndSettle();
    await _bas(tester, 'belge-kaydet');

    final belgeler = depo.dosyaBelgeleri('d1');
    expect(belgeler.length, once + 1);
    expect(belgeler.last.ad, 'Alacak ihtarnamesi');
    expect(belgeler.last.orijinal.ozet, metinOzeti(tamam));
    expect(depo.belgeMetni(belgeler.last.id), contains('ABC Gıda Sanayi ve Ticaret A.Ş.'));
  });
}
