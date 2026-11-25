import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
import 'package:portal/servisler/kimlik_servisi.dart';
import 'package:portal/servisler/veri_deposu.dart';
import 'package:portal/tema/tema.dart';

Oturum _oturum(HesapTuru tur) => Oturum(
      kullaniciId: 'av1',
      kiraciId: 'k1',
      adSoyad: 'Av. Ayşe Yılmaz',
      eposta: 'ayse@buro.com.tr',
      kurumAdi: 'Yılmaz Hukuk',
      hesapTuru: tur,
      roller: {tur == HesapTuru.avukatlikBurosu ? Rol.buroSahibi : Rol.yoneticiOrtak},
    );

Future<BellekVeriDeposu> _ac(WidgetTester tester, {HesapTuru tur = HesapTuru.hukukBurosu}) async {
  tester.view.physicalSize = const Size(1500, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1');
  await tester.pumpWidget(MaterialApp(theme: acikTema(), home: AnaKabuk(oturum: _oturum(tur), cikisYap: () {}, depo: depo)));
  await tester.pumpAndSettle();
  await _bas(tester, 'menu-icra');
  return depo;
}

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

Future<void> _sec(WidgetTester tester, String anahtar, String metin) async {
  await _bas(tester, anahtar);
  await tester.tap(find.textContaining(metin).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('İcra dosya hesabı ve tahsilat', (tester) async {
    final depo = await _ac(tester);
    final i = depo.icraDosyalari.single;
    await _bas(tester, 'icra-${i.id}');

    final bugun = Tarih.from(DateTime.now());
    final beklenen = i.hesap(bugun, FaizTablosu.avans);
    expect(tester.widget<Text>(find.byKey(const Key('icra-kalan'))).data, beklenen.kalanBorc.bicimli);
    expect(find.textContaining('Masrafa'), findsOneWidget);

    await _bas(tester, 'tahsilat-ekle');
    await tester.enterText(find.byKey(const Key('tahsilat-tutar')), '10.000');
    await tester.enterText(find.byKey(const Key('tahsilat-tarih')), bugun.gunEkle(5).turkceBicim);
    await _bas(tester, 'tahsilat-kaydet');
    expect(find.byKey(const Key('tahsilat-hata')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tahsilat-tarih')), bugun.turkceBicim);
    await _bas(tester, 'tahsilat-kaydet');
    expect(i.tahsilatlar, hasLength(2));
    expect(i.tahsilatlar.last.tutar, Para.tl(10000));
    expect(depo.denetim.olaylar.last.nesneTuru, 'icra_tahsilat');
  });

  testWidgets('Yeni icra takibi formu', (tester) async {
    final depo = await _ac(tester);
    await _bas(tester, 'icra-yeni');
    await _bas(tester, 'icra-kaydet');
    expect(find.byKey(const Key('icra-hata')), findsOneWidget);

    await _sec(tester, 'icra-dosya', 'Kara - İşe iade');
    await tester.enterText(find.byKey(const Key('icra-borclu')), 'Mehmet Demirci');
    await tester.enterText(find.byKey(const Key('icra-daire')), 'İstanbul 12. İcra Dairesi');
    await tester.enterText(find.byKey(const Key('icra-alacak')), '85.000');
    await tester.pumpAndSettle();
    expect(find.textContaining('AAÜT nispi öneri'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('icra-temerrut')), '01.09.2026');
    await _bas(tester, 'icra-kaydet');

    expect(depo.icraDosyalari, hasLength(2));
    final yeni = depo.icraDosyalari.last;
    expect(yeni.dosyaId, 'd2');
    expect(yeni.talep.asilAlacak, Para.tl(85000));
    expect(yeni.talep.temerrutTarihi, Tarih(2026, 9, 1));
    expect(find.byKey(const Key('icra-kalan')), findsOneWidget);
  });

  testWidgets('Toplu takip: geçerli satırlar için dosya ve takip açılır', (tester) async {
    final depo = await _ac(tester);
    final dosyaSayisi = depo.tumDosyalar.length;
    await _bas(tester, 'icra-toplu');
    await _sec(tester, 'toplu-muvekkil', 'ABC Gıda Sanayi');
    await tester.enterText(find.byKey(const Key('toplu-daire')), 'İstanbul 3. İcra Dairesi');
    await tester.enterText(
        find.byKey(const Key('toplu-metin')),
        'Borçlu;Kimlik No;Alacak;Temerrüt\n'
        'Ayşe Kara;10000000146;12.500,00;01.10.2026\n'
        ';;0;1.1.2026');
    await _bas(tester, 'toplu-onizle');
    expect(find.text('1 / 2 satır takibe hazır'), findsOneWidget);
    await _bas(tester, 'toplu-ac');

    expect(depo.icraDosyalari, hasLength(2));
    expect(depo.tumDosyalar.length, dosyaSayisi + 1);
    final d = depo.tumDosyalar.last;
    expect(d.tur, DosyaTuru.icra);
    expect(depo.dosyaMuvekkili(d.id), 'abc');
    expect(depo.icraDosyalari.last.talep.asilAlacak, Para.tl(12500));
  });

  testWidgets('Toplu takip yalnızca Hukuk Bürosu paketinde', (tester) async {
    await _ac(tester, tur: HesapTuru.avukatlikBurosu);
    expect(find.byKey(const Key('icra-toplu')), findsNothing);
  });
}
