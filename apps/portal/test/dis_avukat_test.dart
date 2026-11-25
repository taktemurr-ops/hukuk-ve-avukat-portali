import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
import 'package:portal/servisler/kimlik_servisi.dart';
import 'package:portal/servisler/kurumsal_depo.dart';
import 'package:portal/servisler/veri_deposu.dart';
import 'package:portal/tema/tema.dart';

const _oturum = Oturum(
  kullaniciId: 'av1',
  kiraciId: 'k1',
  adSoyad: 'Av. Ayşe Yılmaz',
  eposta: 'ayse@abcgida.com.tr',
  kurumAdi: 'ABC Gıda',
  hesapTuru: HesapTuru.kurumsal,
  roller: {Rol.hukukDirektoru},
);

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Dış avukat: bütçe aşan fatura engellenir, artışla onaylanır, finansa gider', (tester) async {
    tester.view.physicalSize = const Size(1500, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1');
    final k = KurumsalDepo.demo(depo: depo, kullaniciId: 'av1', bugun: () => Tarih(2026, 11, 25));
    await tester.pumpWidget(MaterialApp(
        theme: acikTema(), home: AnaKabuk(oturum: _oturum, cikisYap: () {}, depo: depo, kurumsal: k)));
    await tester.pumpAndSettle();
    await _bas(tester, 'menu-disAvukatlar');

    final is1 = k.disAvukatIsleri.first;
    expect(is1.butceDurumu, ButceDurumu.uyari);
    expect(find.text('Bütçenin %80\'i aşıldı'), findsOneWidget);

    await _bas(tester, 'fatura-onayla-df3');
    expect(find.textContaining('önce bütçe artışı onaylanmalı'), findsOneWidget);
    expect(is1.faturalar.last.durum, FaturaDurumu.bekliyor);

    await _bas(tester, 'is-butce-${is1.id}');
    await tester.enterText(find.byKey(const Key('butce-tutar')), '20000');
    await tester.enterText(find.byKey(const Key('butce-gerekce')), 'İstinaf aşaması işe eklendi');
    await _bas(tester, 'butce-kaydet');
    expect(is1.butce, Para.tl(170000));

    await _bas(tester, 'fatura-onayla-df3');
    expect(is1.faturalar.last.durum, FaturaDurumu.onaylandi);
    await _bas(tester, 'fatura-finans-df3');
    expect(is1.faturalar.last.durum, FaturaDurumu.finansaGonderildi);

    await _bas(tester, 'fatura-reddet-df4');
    await tester.enterText(find.byKey(const Key('ret-gerekce')), 'Harç makbuzu eklenmemiş');
    await _bas(tester, 'ret-onay');
    expect(k.disAvukatIsleri[1].faturalar.single.durum, FaturaDurumu.reddedildi);

    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await _bas(tester, 'dis-is-yeni');
    await _bas(tester, 'dis-is-avukat');
    await tester.tap(find.text('Ege Ortak Avukatlık').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('dis-is-konu')), 'Marka itiraz süreci');
    await tester.enterText(find.byKey(const Key('dis-is-butce')), '35.000');
    await _bas(tester, 'dis-is-kaydet');
    expect(k.disAvukatIsleri.last.konu, 'Marka itiraz süreci');
    expect(k.disAvukatIsleri.last.butce, Para.tl(35000));
  });
}
