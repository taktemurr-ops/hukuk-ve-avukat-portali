import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
import 'package:portal/main.dart';
import 'package:portal/servisler/dosya_secici.dart';
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

const _aktor = Aktor(kullaniciId: 'av1', kiraciId: 'buro1', roller: {Rol.yoneticiOrtak});

void _buyuk(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<BellekVeriDeposu> _ac(WidgetTester tester, String menu) async {
  _buyuk(tester);
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
  testWidgets('Demo hesabıyla Kurumsal giriş; kurumsal menü görünür', (tester) async {
    _buyuk(tester);
    await tester.pumpWidget(PortalUygulamasi(kimlikServisi: BellekKimlikServisi()));
    await tester.pumpAndSettle();
    await _bas(tester, 'demo-giris');
    await _bas(tester, 'demo-kurumsal');
    expect(find.text('Demo Holding A.Ş.'), findsOneWidget);
    expect(find.byKey(const Key('menu-talepler')), findsOneWidget);
    expect(find.byKey(const Key('menu-finans')), findsNothing);
    expect(find.text('Yeni Talep'), findsOneWidget);
  });

  testWidgets('Yeni dosya açılır ve denetim kaydına yazılır', (tester) async {
    final depo = await _ac(tester, 'dosyalar');
    final once = depo.gorunurDosyalar(_aktor).length;
    await _bas(tester, 'yeni-dosya');
    await tester.enterText(find.byKey(const Key('dosya-baslik')), 'Zeytin Turizm - Kira tespiti');
    await _bas(tester, 'dosya-kaydet');
    final dosyalar = depo.gorunurDosyalar(_aktor);
    expect(dosyalar.length, once + 1);
    expect(dosyalar.last.baslik, 'Zeytin Turizm - Kira tespiti');
    expect(dosyalar.last.sorumlu, 'av1');
    expect(depo.denetim.olaylar.last.nesneTuru, 'dosya');
    expect(depo.denetim.dogrula(), isNull);
  });

  testWidgets('Dosyaya duruşma eklenir', (tester) async {
    final depo = await _ac(tester, 'dosyalar');
    final once = depo.durusmalar.length;
    await _bas(tester, 'dosya-d3');
    await _bas(tester, 'durusma-ekle');
    await _bas(tester, 'durusma-kaydet');
    expect(find.text('Yer zorunludur.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('durusma-yer')), 'Çağlayan Adliyesi, 12. kat');
    await _bas(tester, 'durusma-kaydet');
    expect(depo.durusmalar.length, once + 1);
    expect(depo.durusmalar.last.dosyaId, 'd3');
  });

  testWidgets('Vekâletname müvekkil seçilmeden kaydedilmez; özel yetkiyle kaydedilir', (tester) async {
    final depo = await _ac(tester, 'vekaletler');
    final once = depo.vekaletnameler.length;
    await _bas(tester, 'vekalet-yeni');
    await _bas(tester, 'vekalet-kaydet');
    expect(find.text('Müvekkil seçin.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vekalet-muvekkil')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mehmet Demirci').last);
    await tester.pumpAndSettle();
    await _bas(tester, 'yetki-sulh');
    await _bas(tester, 'vekalet-kaydet');

    expect(depo.vekaletnameler.length, once + 1);
    expect(depo.vekaletnameler.last.muvekkilId, 'demirci');
    expect(depo.vekaletnameler.last.ozelYetkiler, {OzelYetki.sulh});
  });

  testWidgets('CSV veri aktarımı önizlenir ve yalnızca geçerli yeni kayıtlar aktarılır', (tester) async {
    final depo = await _ac(tester, 'ayarlar');
    final once = depo.kisiler.length;
    await _bas(tester, 'ayar-aktarim');
    await tester.enterText(
      find.byKey(const Key('aktarim-metin')),
      'Adı Soyadı;TCKN/VKN;E-posta\n'
      'Zeynep Aydın;;zeynep@ornek.com\n'
      'ABC Gıda Sanayi ve Ticaret A.Ş.;1234567890;\n'
      'Hatalı Kişi;10000000147;\n',
    );
    await _bas(tester, 'aktarim-onizle');
    expect(find.text('Aktarılacak 1'), findsOneWidget);
    expect(find.text('Mükerrer 1'), findsOneWidget);
    expect(find.text('Hatalı 1'), findsOneWidget);
    expect(find.text('Sayım mutabık'), findsOneWidget);

    await _bas(tester, 'aktarim-aktar');
    expect(depo.kisiler.length, once + 1);
    expect(depo.kisiler.last.ad, 'Zeynep Aydın');
    expect(depo.denetim.olaylar.last.islem, DenetimIslemi.aktarim);
  });

  testWidgets('Windows-1254 CSV dosyası seçilince Türkçe harfler doğru okunur ve önizlenir', (tester) async {
    final depo = await _ac(tester, 'ayarlar');
    final once = depo.kisiler.length;
    // "Adı Soyadı;E-posta\nŞükrü Doğan;s@ornek.com" Windows-1254 ile kodlanmış.
    final b = <int>[
      ...'Ad'.codeUnits, 0xFD, ...' Soyad'.codeUnits, 0xFD, ...';E-posta\n'.codeUnits, //
      0xDE, 0xFC, ...'kr'.codeUnits, 0xFC, ...' Do'.codeUnits, 0xF0, ...'an;s@ornek.com\n'.codeUnits,
    ];
    final eski = dosyaSecici;
    addTearDown(() => dosyaSecici = eski);
    dosyaSecici = (_) async => (ad: 'liste.csv', icerik: Uint8List.fromList(b));
    await _bas(tester, 'ayar-aktarim');
    await _bas(tester, 'aktarim-dosya');
    expect(find.text('Aktarılacak 1'), findsOneWidget);
    await _bas(tester, 'aktarim-aktar');
    expect(depo.kisiler.length, once + 1);
    expect(depo.kisiler.last.ad, 'Şükrü Doğan');
  });

  test('CSV yazımı ayraç ve tırnak içeren hücreleri tırnaklar; geçerli UTF-8 olduğu gibi okunur', () {
    expect(csvYaz([['Ad', 'Adres'], ['A;B', 'Çarşı "Merkez"']]), 'Ad;Adres\n"A;B";"Çarşı ""Merkez"""');
    expect(csvCoz([0xC5, 0x9E]), 'Ş');
  });

  testWidgets('Görev şablonu oluşturulur ve dosya açma formunda seçilebilir', (tester) async {
    final depo = await _ac(tester, 'ayarlar');
    await _bas(tester, 'ayar-sablonlar');
    await _bas(tester, 'sablon-yeni');
    await tester.enterText(find.byKey(const Key('sablon-ad')), 'Kira tahliye');
    await tester.enterText(find.byKey(const Key('adim-baslik-0')), 'İhtarname gönder');
    await _bas(tester, 'adim-ekle');
    await tester.enterText(find.byKey(const Key('adim-baslik-1')), 'Tahliye davası aç');
    await tester.enterText(find.byKey(const Key('adim-gun-1')), 'otuz');
    await _bas(tester, 'sablon-kaydet');
    expect(find.textContaining('gün 0–3650'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('adim-gun-1')), '30');
    await _bas(tester, 'sablon-kaydet');
    expect(depo.gorevSablonlari.map((s) => s.$2.ad), contains('Kira tahliye'));
    expect(depo.gorevSablonlari.last.$2.adimlar.last.gunSonra, 30);
  });

  testWidgets('UYAP dosya listesi önizlenir, mükerrer atlanır, geçerli satırlar dosya olarak açılır', (tester) async {
    final depo = await _ac(tester, 'ayarlar');
    final once = depo.tumDosyalar.length;
    final mevcut = depo.tumDosyalar.firstWhere((d) => d.mahkeme != null && d.esasNo != null);
    await _bas(tester, 'ayar-dosya-aktarim');
    await tester.enterText(
      find.byKey(const Key('dosya-aktarim-metin')),
      'Birim Adı;Dosya No;Davacı;Davalı\n'
      'İstanbul 3. İş Mahkemesi;2026/210;Zeynep Aydın;Mavi Lojistik A.Ş.\n'
      '${mevcut.mahkeme};${mevcut.esasNo!.split(' ').first};X;Y\n'
      ';2026/5;A;B\n',
    );
    await _bas(tester, 'dosya-aktarim-onizle');
    expect(find.text('Açılacak 1'), findsOneWidget);
    expect(find.text('Mükerrer 1'), findsOneWidget);
    expect(find.text('Hatalı 1'), findsOneWidget);
    await _bas(tester, 'dosya-aktarim-aktar');
    expect(depo.tumDosyalar.length, once + 1);
    final yeni = depo.tumDosyalar.firstWhere((d) => d.esasNo == '2026/210 E.');
    expect(yeni.baslik, 'Zeynep Aydın - Mavi Lojistik A.Ş.');
  });

  testWidgets('Belgelerde arama: Türkçe karaktersiz yazılan sözcük bulunur, ekrandan dosyaya gidilir', (tester) async {
    final depo = await _ac(tester, 'dosyalar');
    final d = depo.tumDosyalar.first;
    depo.belgeOlustur(dosyaId: d.id, ad: 'Hesap notu', metin: 'Davacının kıdem tazminatı 245.000 TL.', yukleyen: 'av1');
    await _bas(tester, 'belge-ara');
    await tester.enterText(find.byKey(const Key('belge-ara-metin')), 'kidem tazminati');
    await _bas(tester, 'belge-ara-dugme');
    expect(find.textContaining('Hesap notu'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('belge-ara-metin')), 'ihtiyati haciz');
    await _bas(tester, 'belge-ara-dugme');
    expect(find.text('0 belge'), findsOneWidget);
  });

  testWidgets('Ekip: yönetici başkasının rolünü değiştirir ve gerekçeyle pasifleştirir; kendine dokunamaz', (tester) async {
    final depo = await _ac(tester, 'ayarlar');
    await _bas(tester, 'ayar-ekip');
    // Kendi satırı tıklanamaz.
    expect(tester.widget<ListTile>(find.byKey(const Key('ekip-av1'))).onTap, isNull);
    await _bas(tester, 'ekip-demo-stj');
    await _bas(tester, 'ekip-rol-avukat');
    await _bas(tester, 'ekip-rol-kaydet');
    expect(depo.ekip.firstWhere((k) => k.id == 'demo-stj').roller, contains(Rol.avukat));
    await _bas(tester, 'ekip-demo-stj');
    await _bas(tester, 'ekip-pasif');
    expect(find.text('Gerekçe yazılmalıdır.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ekip-gerekce')), 'Staj bitti');
    await _bas(tester, 'ekip-pasif');
    expect(depo.ekip.firstWhere((k) => k.id == 'demo-stj').aktif, isFalse);
    expect(find.text('Pasif'), findsOneWidget);
  });

  testWidgets('Denetim kaydı ekranı zincirin sağlam olduğunu gösterir', (tester) async {
    await _ac(tester, 'ayarlar');
    await _bas(tester, 'ayar-denetim');
    expect(find.textContaining('Kayıt zinciri sağlam'), findsOneWidget);
  });
}
