import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
import 'package:portal/servisler/kimlik_servisi.dart';
import 'package:portal/servisler/veri_deposu.dart';

const _oturum = Oturum(
  kullaniciId: 'av1',
  kiraciId: 'buro1',
  adSoyad: 'Av. Deneme',
  eposta: 'deneme@buro.com.tr',
  kurumAdi: 'Deneme Hukuk',
  hesapTuru: HesapTuru.hukukBurosu,
  roller: {Rol.yoneticiOrtak},
);

Future<BellekVeriDeposu> _ac(WidgetTester tester, String bolum) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final depo = BellekVeriDeposu.demo(kiraciId: 'buro1', avukatId: 'av1');
  await tester.pumpWidget(MaterialApp(home: AnaKabuk(oturum: _oturum, cikisYap: () {}, depo: depo)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(bolum).last);
  await tester.pumpAndSettle();
  return depo;
}

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Müvekkil araması Türkçe karakterden bağımsız çalışır', (tester) async {
    await _ac(tester, 'Müvekkiller');
    expect(find.text('6 kayıt'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('kisi-ara')), 'abc gida');
    await tester.pumpAndSettle();
    expect(find.text('ABC Gıda Sanayi ve Ticaret A.Ş.'), findsOneWidget);
    expect(find.text('Ayşe Kara'), findsNothing);
  });

  testWidgets('Çatışmasız yeni müvekkil kaydedilir', (tester) async {
    final depo = await _ac(tester, 'Müvekkiller');
    await _bas(tester, 'yeni-kisi');
    await tester.enterText(find.byKey(const Key('kisi-ad')), 'Zeynep Aydın');
    await _bas(tester, 'kisi-kontrol');
    expect(find.byKey(const Key('rapor-temiz')), findsOneWidget);
    await _bas(tester, 'kisi-kaydet');
    expect(depo.kisiler.any((k) => k.ad == 'Zeynep Aydın'), isTrue);
  });

  testWidgets('Mevcut müvekkile karşı kayıt engellenir', (tester) async {
    final depo = await _ac(tester, 'Müvekkiller');
    await _bas(tester, 'yeni-kisi');
    await tester.tap(find.text('Tüzel kişi'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('kisi-ad')), 'ABC GIDA SAN. TİC. AŞ');
    await tester.tap(find.text('Karşı taraf'));
    await tester.pumpAndSettle();
    await _bas(tester, 'kisi-kontrol');
    expect(find.byKey(const Key('kisi-karar-gerekir')), findsOneWidget);
    final kaydet = tester.widget<FilledButton>(find.byKey(const Key('kisi-kaydet')));
    expect(kaydet.onPressed, isNull);
    expect(depo.kisiler, hasLength(6));
  });

  testWidgets('Çıkar çatışması kararı yönetici onayı olmadan kaydedilmez', (tester) async {
    final depo = await _ac(tester, 'Çıkar çatışması');
    // 1. satır müvekkil, 2. satır karşı taraf
    await tester.enterText(find.byKey(const Key('aday-ad-0')), 'Yeni Müvekkil Ltd.');
    await tester.enterText(find.byKey(const Key('aday-ad-1')), 'ABC Gıda A.Ş.');
    await _bas(tester, 'cikar-tara');
    expect(find.textContaining('Çatışma:'), findsWidgets);

    await tester.tap(find.text('Koşullu kabul'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cikar-gerekce')), 'Müvekkil yazılı muvafakat verdi');
    await _bas(tester, 'cikar-karar-kaydet');
    expect(find.byKey(const Key('cikar-hata')), findsOneWidget);
    expect(depo.kararlar, isEmpty);

    await tester.tap(find.text('Ret'));
    await tester.pumpAndSettle();
    await _bas(tester, 'cikar-karar-kaydet');
    expect(depo.kararlar, hasLength(1));
    expect(depo.kararlar.single.karar.tur, KararTuru.ret);
  });

  testWidgets('Vekâletnamede olmayan özel yetki için uyarı verilir', (tester) async {
    await _ac(tester, 'Vekâletler');
    await tester.tap(find.byKey(const Key('vekalet-islem')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Davadan feragat').last);
    await tester.pumpAndSettle();
    await _bas(tester, 'vekalet-kontrol-v1');
    expect(find.text('Uygun değil'), findsOneWidget);
  });

  testWidgets('Kişi kartı: unvan değişince eski unvan geçmişte kalır, ilişki eklenir ve taramada görünür', (tester) async {
    final depo = await _ac(tester, 'Müvekkiller');
    await _bas(tester, 'kisi-delta');
    await _bas(tester, 'kart-duzenle');
    await tester.enterText(find.byKey(const Key('kart-ad')), 'Delta Yapı A.Ş.');
    await tester.enterText(find.byKey(const Key('kart-telefon')), '0212 555 00 00');
    await _bas(tester, 'kart-kaydet');
    expect(depo.kisi('delta')!.ad, 'Delta Yapı A.Ş.');
    expect(depo.kisi('delta')!.unvanGecmisi.single.unvan, 'Delta İnşaat Ltd. Şti.');
    expect(find.text('Eski unvanlar'), findsOneWidget);
    // Eski unvanla tarama hâlâ eşleşir.
    final rapor = depo.tarayici.tara([const AdayTaraf(ad: 'Delta İnşaat Ltd. Şti.', sifat: TarafSifati.muvekkil)]);
    expect(rapor.eslesmeler, isNotEmpty);

    await _bas(tester, 'kart-iliski-ekle');
    await tester.enterText(find.byKey(const Key('iliski-ara')), 'Orman');
    await tester.pumpAndSettle();
    await _bas(tester, 'iliski-aday-orman');
    await _bas(tester, 'iliski-kaydet');
    expect(depo.kisininIliskileri('delta').single.karsiTaraf('delta'), 'orman');
  });
  testWidgets('Yetki belgesi: yalnızca vekâletnamedeki yetkiler devredilir, eksik alan gösterilir', (tester) async {
    await _ac(tester, 'Vekâletler');
    await _bas(tester, 'yetki-belgesi-v1');
    await tester.enterText(find.byKey(const Key('yb-alanAd')), 'Av. Can Demir');
    await tester.enterText(find.byKey(const Key('yb-alanBaro')), 'Ankara');
    await tester.pumpAndSettle();
    expect(find.textContaining('Eksik: alan.sicil'), findsOneWidget);
    await _bas(tester, 'yb-yetki-sulh');
    await tester.enterText(find.byKey(const Key('yb-alanSicil')), '12345');
    await tester.pumpAndSettle();
    final metin = tester.widget<SelectableText>(find.byKey(const Key('yb-metin'))).data!;
    expect(metin, contains('DEVREDİLEN ÖZEL YETKİLER: Sulh olma'));
    expect(metin, contains('Kadıköy 5. Noterliği'));
    expect(find.textContaining('Baro pulunu unutmayın'), findsOneWidget);
  });
}
