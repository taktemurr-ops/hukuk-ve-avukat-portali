import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
import 'package:portal/ekranlar/dosyalar_ekrani.dart';
import 'package:portal/servisler/bildirim_servisi.dart';
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

void _buyuk(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Etik duvar: ekipteki kişi engellenemez; engellenen dosyayı göremez; kaldırma gerekçeli', (tester) async {
    _buyuk(tester);
    final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1')..aktifKullanici = 'av1';
    final d = depo.dosyaAc(tur: DosyaTuru.danismanlik, baslik: 'Yeni birleşme danışmanlığı', sorumlu: 'av1');
    await tester.pumpWidget(MaterialApp(theme: acikTema(), home: DosyaDetayEkrani(depo: depo, oturum: _oturum, dosyaId: d.id)));
    await tester.pumpAndSettle();

    await _bas(tester, 'etik-duvar-ekle');
    await _bas(tester, 'etik-kullanici');
    await tester.tap(find.text('Av. Mert Şahin').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('etik-gerekce')), 'kısa');
    await _bas(tester, 'etik-kaydet');
    expect(find.byKey(const Key('etik-hata')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('etik-gerekce')), 'Karşı tarafa önceki büroda danışmanlık verdi');
    await _bas(tester, 'etik-kaydet');

    expect(depo.etikDuvar.engelliler(d.id), {'demo-av2'});
    const mert = Aktor(kullaniciId: 'demo-av2', kiraciId: 'k1', roller: {Rol.ortak});
    expect(depo.gorunurDosyalar(mert).map((x) => x.id), isNot(contains(d.id)));
    expect(depo.denetim.olaylar.last.nesneTuru, 'etik_duvar');

    await _bas(tester, 'etik-duvar-kaldir-demo-av2');
    await tester.enterText(find.byKey(const Key('etik-kaldir-gerekce')), 'Çatışma ortadan kalktı, onay alındı');
    await _bas(tester, 'etik-kaldir-onay');
    expect(depo.etikDuvar.engelliler(d.id), isEmpty);
    expect(depo.gorunurDosyalar(mert).map((x) => x.id), contains(d.id));
    expect(find.textContaining('Kaldırıldı:'), findsOneWidget);

    expect(
        depo.etikDuvarKur('d1', 'demo-av2', 'Ekipteki kişiyi engelleme denemesi'),
        'Kullanıcı dosya ekibinde; önce ekipten çıkarılmalı.');
  });

  testWidgets('Bildirim paneli: müvekkil mesajı bildirimi dosyayı açar ve okunur', (tester) async {
    _buyuk(tester);
    final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1');
    await tester.pumpWidget(MaterialApp(theme: acikTema(), home: AnaKabuk(oturum: _oturum, cikisYap: () {}, depo: depo)));
    await tester.pumpAndSettle();

    final servis = BildirimServisi(depo: depo, oturum: _oturum);
    final once = servis.okunmamis();
    expect(once, greaterThan(0));

    await _bas(tester, 'bildirimler');
    expect(find.text('Bildirimler'), findsOneWidget);
    await tester.ensureVisible(find.text('1 yeni müvekkil mesajı'));
    await tester.tap(find.text('1 yeni müvekkil mesajı'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portal-paylas')), findsOneWidget);
  });

  test('Bildirim servisi: etik duvarlı dosyanın bildirimi üretilmez', () {
    final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1')..aktifKullanici = 'av1';
    final d = depo.dosyaAc(tur: DosyaTuru.hukuk, baslik: 'Duvarlı dosya', sorumlu: 'demo-av2');
    depo.durusmaEkle(
        dosyaId: d.id,
        baslangic: DateTime.now().add(const Duration(hours: 3)),
        yer: 'Çağlayan',
        katilan: 'av1',
        tur: 'Duruşma');
    final servis = BildirimServisi(depo: depo, oturum: _oturum);
    expect(servis.topla().any((h) => h.bildirim.hedefId == d.id), isTrue);
    depo.etikDuvarKur(d.id, 'av1', 'Engelleme denemesi; test için gerekçe');
    expect(depo.etikDuvar.engelliler(d.id), isEmpty, reason: 'Kişi kendine duvar kuramaz');
    depo.aktifKullanici = 'demo-av2';
    expect(depo.etikDuvarKur(d.id, 'av1', 'Önceki büroda karşı tarafı temsil etti'), isNull);
    expect(servis.topla().any((h) => h.bildirim.hedefId == d.id), isFalse);
  });
}
