import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
import 'package:portal/servisler/kimlik_servisi.dart';
import 'package:portal/servisler/kurumsal_depo.dart';
import 'package:portal/servisler/veri_deposu.dart';
import 'package:portal/tema/tema.dart';

const _oturum = Oturum(
  kullaniciId: 'av1',
  kiraciId: 'sirket1',
  adSoyad: 'Av. Ayşe Yılmaz',
  eposta: 'ayse@abcgida.com.tr',
  kurumAdi: 'ABC Gıda A.Ş.',
  hesapTuru: HesapTuru.kurumsal,
  roller: {Rol.hukukDirektoru},
);

final _bugun = Tarih(2026, 11, 25);

KurumsalDepo _kurumsal() => KurumsalDepo.demo(
    depo: BellekVeriDeposu.demo(kiraciId: 'sirket1', avukatId: 'av1'), kullaniciId: 'av1', bugun: () => _bugun);

Future<KurumsalDepo> _ac(WidgetTester tester, String menu) async {
  tester.view.physicalSize = const Size(1500, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final k = _kurumsal();
  await tester.pumpWidget(MaterialApp(
      theme: acikTema(), home: AnaKabuk(oturum: _oturum, cikisYap: () {}, depo: k.depo, kurumsal: k)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('menu-$menu')));
  await tester.pumpAndSettle();
  return k;
}

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

void main() {
  group('KurumsalDepo demo', () {
    test('sözleşmeler taranmış, uyarılar ve SLA hesaplanmış', () {
      final k = _kurumsal();
      expect(k.sozlesmeler.map((s) => s.no), ['SZ-2026-0001', 'SZ-2026-0002', 'SZ-2026-0003']);
      final kira = k.sozlesmeler[1];
      expect(kira.tur, SozlesmeTuru.kira);
      expect(kira.bitis, Tarih(2027, 3, 31));
      expect(kira.bedel, Para.tl(480000));
      expect(k.sozlesmeler.where((s) => s.tarama!.genelSeviye == RiskSeviyesi.yuksek).length, 2);
      expect(k.uyarilar().map((u) => u.$2.tur),
          [SozlesmeUyariTuru.yukumlulukYaklasiyor, SozlesmeUyariTuru.ihbarYaklasiyor]);

      final t = k.defter.talepler;
      expect(t.map((x) => x.atanan), ['av1', 'hu2', 'hu3', '']);
      expect(t.map(k.sla), [SlaDurumu.gecikti, SlaDurumu.riskli, SlaDurumu.riskli, SlaDurumu.zamaninda]);
      expect(t.last.durum, TalepDurumu.yeni);
      expect(t.first.sozlesmeId, 'sz3');
    });
  });

  testWidgets('Sözleşme yüklenir, taranır, kaydedilir ve onaya gönderilir', (tester) async {
    final k = await _ac(tester, 'sozlesmeler');
    expect(find.byKey(const Key('sozlesme-uyari-sz1-ihbarYaklasiyor')), findsOneWidget);
    expect(find.byKey(const Key('sozlesme-sz2')), findsOneWidget);

    await _bas(tester, 'sozlesme-filtre-onay');
    expect(find.byKey(const Key('sozlesme-sz3')), findsOneWidget);
    expect(find.byKey(const Key('sozlesme-sz2')), findsNothing);

    await _bas(tester, 'sozlesme-yukle');
    await _bas(tester, 'sozlesme-tara');
    expect(find.byKey(const Key('sozlesme-hata')), findsOneWidget);
    await _bas(tester, 'ornek-metin');
    await tester.tap(find.text('Örnek gizlilik sözleşmesi').last);
    await tester.pumpAndSettle();
    await _bas(tester, 'sozlesme-tara');
    expect(find.byKey(const Key('bulgu-yabanciHukuk')), findsOneWidget);
    expect(find.byKey(const Key('bulgu-yurtdisiTahkim')), findsOneWidget);

    await _bas(tester, 'sozlesme-kaydet');
    expect(find.byKey(const Key('sozlesme-hata')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('sozlesme-baslik')), 'Distribütör gizlilik sözleşmesi');
    await _bas(tester, 'sozlesme-kaydet');

    expect(k.sozlesmeler, hasLength(4));
    final yeni = k.sozlesmeler.last;
    expect(yeni.tur, SozlesmeTuru.gizlilik);
    expect(yeni.durum, SozlesmeDurumu.taslak);
    expect(find.text('Distribütör gizlilik sözleşmesi'), findsWidgets);
    expect(find.byKey(const Key('sozlesme-durum-onayda')), findsNothing);
    await _bas(tester, 'sozlesme-onaya-gonder');
    expect(yeni.durum, SozlesmeDurumu.onayda);
    expect(k.depo.denetim.olaylar.last.aciklama, startsWith('Onaya gönderildi: Hukuk incelemesi → Hukuk direktörü'));
    expect(find.byKey(const Key('onay-bekleniyor')), findsOneWidget);
  });

  testWidgets('Onay zinciri: hukuk direktörü onayıyla sözleşme imzaya geçer', (tester) async {
    final k = await _ac(tester, 'sozlesmeler');
    expect(k.onayimiBekleyenler.map((s) => s.id), ['sz3']);
    await _bas(tester, 'sozlesme-sz3');
    expect(find.byKey(const Key('sozlesme-durum-imzada')), findsNothing);
    expect(find.textContaining('Onaylandı · Av. Selin Arslan'), findsOneWidget);
    await _bas(tester, 'onay-onayla');
    final nda = k.sozlesme('sz3')!;
    expect(nda.durum, SozlesmeDurumu.imzada);
    expect(k.onaySureci('sz3')!.durum, OnaySurecDurumu.onaylandi);
    expect(k.onayimiBekleyenler, isEmpty);
  });

  test('Onay zinciri: revizyon gerekçeyle müzakereye döndürür', () {
    final k = _kurumsal();
    final nda = k.sozlesme('sz3')!;
    expect(k.onayKarari(nda, OnayKarariTuru.revizyon), isNotNull);
    expect(k.onayKarari(nda, OnayKarariTuru.revizyon, not: 'Uygulanacak hukuk Türk hukuku olmalı'), isNull);
    expect(nda.durum, SozlesmeDurumu.muzakere);
    expect(k.onayaGonder(nda), isNull);
    expect(nda.durum, SozlesmeDurumu.onayda);
    expect(k.onaySureci('sz3')!.kararlar, isEmpty);
  });

  testWidgets('Grup şirketi seçimi sözleşme ve talepleri alt şirketleriyle süzer', (tester) async {
    final k = await _ac(tester, 'sozlesmeler');
    await _bas(tester, 'kurum-secici');
    await _bas(tester, 'sirket-abcGida');
    expect(k.aktifSirketId, 'abcGida');
    expect(find.byKey(const Key('sozlesme-sz1')), findsOneWidget);
    expect(find.byKey(const Key('sozlesme-sz2')), findsNothing);
    expect(find.byKey(const Key('sozlesme-sz3')), findsNothing);
    expect(find.text('ABC Gıda'), findsWidgets);

    await _bas(tester, 'menu-talepler');
    expect(find.byKey(const Key('talep-tlp1')), findsNothing);
    expect(find.byKey(const Key('talep-tlp2')), findsOneWidget);
    expect(find.byKey(const Key('talep-tlp4')), findsOneWidget);

    await _bas(tester, 'menu-organizasyon');
    await _bas(tester, 'sirket-yeni');
    await tester.enterText(find.byKey(const Key('sirket-unvan')), 'ABC Enerji A.Ş.');
    await tester.enterText(find.byKey(const Key('sirket-vkn')), '2222222220');
    await _bas(tester, 'sirket-kaydet');
    expect(find.text('Vergi kimlik numarası geçersiz.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('sirket-vkn')), '4840847211');
    await _bas(tester, 'sirket-kaydet');
    expect(k.grup.tumu.map((s) => s.unvan), contains('ABC Enerji A.Ş.'));

    k.sirketSec(null);
    expect(k.gorunurSozlesmeler, hasLength(3));
  });

  testWidgets('Yükümlülük eklenir ve tamamlanır', (tester) async {
    final k = await _ac(tester, 'sozlesmeler');
    await _bas(tester, 'sozlesme-sz2');
    await _bas(tester, 'yukumluluk-ekle');
    await tester.enterText(find.byKey(const Key('yukumluluk-aciklama')), 'Depozito iadesi talebi');
    await _bas(tester, 'yukumluluk-kaydet');
    final s = k.sozlesme('sz2')!;
    expect(s.yukumlulukler.single.sonTarih, _bugun.gunEkle(30));
    await _bas(tester, 'yukumluluk-${s.yukumlulukler.single.id}');
    expect(s.yukumlulukler.single.tamamlandi, isTrue);
  });

  testWidgets('Hukuk talebi açılır, atanır, bilgi beklemeye alınır', (tester) async {
    final k = await _ac(tester, 'talepler');
    expect(find.byKey(const Key('talep-tlp1')), findsOneWidget);
    await _bas(tester, 'talep-gorunum-benim');
    expect(find.byKey(const Key('talep-tlp2')), findsNothing);
    await _bas(tester, 'talep-gorunum-atanmamis');
    expect(find.byKey(const Key('talep-tlp4')), findsOneWidget);
    await _bas(tester, 'talep-gorunum-acik');

    await _bas(tester, 'talep-yeni');
    await _bas(tester, 'talep-gonder');
    expect(find.text('Konu ve birim zorunludur.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('talep-baslik')), 'Kampanya metni hukuki kontrol');
    await tester.enterText(find.byKey(const Key('talep-birim')), 'Pazarlama');
    await _bas(tester, 'talep-gonder');
    final yeni = k.defter.talepler.last;
    expect(yeni.no, 'HT-2026-0005');
    expect(yeni.atanan, 'av1');
    expect(yeni.slaSonGun, Tarih(2026, 11, 30));

    await _bas(tester, 'talep-tlp1');
    await _bas(tester, 'talep-durum-incelemede');
    final t1 = k.defter.talepler.first;
    expect(t1.durum, TalepDurumu.incelemede);
    await _bas(tester, 'talep-durum-bilgiBekleniyor');
    await tester.enterText(find.byKey(const Key('talep-not')), 'Karşı tarafın son taslağı');
    await _bas(tester, 'talep-not-kaydet');
    expect(t1.durum, TalepDurumu.bilgiBekleniyor);
    expect(find.text('Bilgi bekleniyor: Karşı tarafın son taslağı'), findsOneWidget);
  });
}
