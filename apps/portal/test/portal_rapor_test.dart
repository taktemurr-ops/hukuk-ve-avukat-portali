import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
import 'package:portal/ekranlar/dosyalar_ekrani.dart';
import 'package:portal/main.dart';
import 'package:portal/servisler/kimlik_servisi.dart';
import 'package:portal/servisler/kurumsal_depo.dart';
import 'package:portal/servisler/veri_deposu.dart';
import 'package:portal/tema/tema.dart';

Oturum _oturum(HesapTuru tur) => Oturum(
      kullaniciId: 'av1',
      kiraciId: 'k1',
      adSoyad: 'Av. Ayşe Yılmaz',
      eposta: 'ayse@buro.com.tr',
      kurumAdi: 'Yılmaz Hukuk',
      hesapTuru: tur,
      roller: {tur == HesapTuru.kurumsal ? Rol.hukukDirektoru : Rol.yoneticiOrtak},
    );

void _buyuk(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Müvekkil demo girişi: yalnızca paylaşılan dosya ve belge görünür, mesaj gönderilir', (tester) async {
    _buyuk(tester);
    await tester.pumpWidget(PortalUygulamasi(kimlikServisi: BellekKimlikServisi()));
    await tester.pumpAndSettle();
    await _bas(tester, 'demo-giris');
    await _bas(tester, 'demo-muvekkil');

    expect(find.text('Dosyalarım'), findsOneWidget);
    expect(find.byKey(const Key('portal-dosya-d1')), findsOneWidget);
    expect(find.byKey(const Key('portal-dosya-d3')), findsNothing);
    expect(find.byKey(const Key('menu-finans')), findsNothing);

    await _bas(tester, 'portal-dosya-d1');
    expect(find.text('Dava dilekçesi'), findsOneWidget);
    expect(find.text('Gerekçeli karar'), findsNothing);
    expect(find.textContaining('Sonraki duruşma'), findsOneWidget);
    expect(find.textContaining('Tedarikçiyle yapılan yazışmaları'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('portal-mesaj')), 'Yazışmaları e-postayla gönderdim.');
    await _bas(tester, 'portal-gonder');
    expect(find.text('Yazışmaları e-postayla gönderdim.'), findsOneWidget);

    await _bas(tester, 'portal-gonder');
    expect(find.text('Mesaj boş olamaz.'), findsOneWidget);
  });

  testWidgets('Büro: portal paylaşımı, belge paylaşımı ve müvekkile yanıt', (tester) async {
    _buyuk(tester);
    final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1');
    await tester.pumpWidget(MaterialApp(
        theme: acikTema(),
        home: DosyaDetayEkrani(depo: depo, oturum: _oturum(HesapTuru.hukukBurosu), dosyaId: 'd1')));
    await tester.pumpAndSettle();

    expect(depo.okunmamisMuvekkilMesaji('d1'), 1);
    expect(find.text('1 yeni mesaj'), findsOneWidget);
    await _bas(tester, 'portal-okundu');
    expect(depo.okunmamisMuvekkilMesaji('d1'), 0);

    await tester.enterText(find.byKey(const Key('buro-mesaj')), 'Evet, lütfen iletin.');
    await _bas(tester, 'buro-gonder');
    expect(depo.dosyaMesajlari('d1').last.metin, 'Evet, lütfen iletin.');
    expect(depo.dosyaMesajlari('d1').last.muvekkildenMi, isFalse);

    final karar = depo.dosyaBelgeleri('d1').firstWhere((b) => b.ad == 'Gerekçeli karar');
    expect(depo.belgePaylasildiMi(karar.id), isFalse);
    await _bas(tester, 'belge-paylas-${karar.id}');
    expect(depo.belgePaylasildiMi(karar.id), isTrue);
    expect(depo.muvekkilOzetleri('abc').single.belgeler, hasLength(2));

    await _bas(tester, 'portal-paylas');
    expect(depo.portaldaMi('d1'), isFalse);
    expect(depo.muvekkilOzetleri('abc'), isEmpty);
    expect(depo.denetim.olaylar.last.islem, DenetimIslemi.paylasim);

    expect(depo.mesajGonder(dosyaId: 'd2', metin: 'x', muvekkildenMi: true, muvekkilKisiId: 'ayse'),
        'Bu dosyaya mesaj gönderme yetkiniz yok.');
  });

  testWidgets('Raporlar: iş yükü, süre dağılımı, alacak yaşlandırma ve CSV', (tester) async {
    _buyuk(tester);
    final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1');
    await tester.pumpWidget(MaterialApp(
        theme: acikTema(), home: AnaKabuk(oturum: _oturum(HesapTuru.hukukBurosu), cikisYap: () {}, depo: depo)));
    await tester.pumpAndSettle();
    await _bas(tester, 'menu-raporlar');

    expect(find.byKey(const Key('rapor-is-yuku')), findsOneWidget);
    expect(find.byKey(const Key('rapor-sure')), findsOneWidget);
    expect(find.byKey(const Key('rapor-alacak')), findsOneWidget);
    expect(find.text('Mehmet Demirci'), findsNothing);
    expect(find.text('60.000,00 TL'), findsWidgets);

    await _bas(tester, 'csv-is-yuku');
    expect(depo.denetim.olaylar.last.islem, DenetimIslemi.disaAktarma);
  });

  testWidgets('Kurumsal raporlar: talep performansı ve sözleşme bitişleri', (tester) async {
    _buyuk(tester);
    final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1');
    final k = KurumsalDepo.demo(depo: depo, kullaniciId: 'av1', bugun: () => Tarih(2026, 11, 25));
    await tester.pumpWidget(MaterialApp(
        theme: acikTema(),
        home: AnaKabuk(oturum: _oturum(HesapTuru.kurumsal), cikisYap: () {}, depo: depo, kurumsal: k)));
    await tester.pumpAndSettle();
    await _bas(tester, 'menu-raporlar');

    expect(find.byKey(const Key('rapor-talep-tur')), findsOneWidget);
    expect(find.byKey(const Key('rapor-sozlesme-bitis')), findsOneWidget);
    expect(find.text('2027-02'), findsOneWidget);
    expect(find.text('2027-03'), findsOneWidget);
    expect(find.byKey(const Key('rapor-alacak')), findsNothing);
  });
}
