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

Future<KurumsalDepo> _ac(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final depo = BellekVeriDeposu.demo(kiraciId: 'k1', avukatId: 'av1');
  final k = KurumsalDepo.demo(depo: depo, kullaniciId: 'av1', bugun: () => Tarih(2026, 11, 25));
  await tester.pumpWidget(MaterialApp(
      theme: acikTema(), home: AnaKabuk(oturum: _oturum, cikisYap: () {}, depo: depo, kurumsal: k)));
  await tester.pumpAndSettle();
  await _bas(tester, 'menu-uyum');
  return k;
}

void main() {
  testWidgets('İhbar kaydı takip kodu üretir; soruşturma açılır', (tester) async {
    final k = await _ac(tester);
    await _bas(tester, 'ihbar-yeni');
    await tester.enterText(find.byKey(const Key('ihbar-aciklama')), 'kısa');
    await _bas(tester, 'ihbar-kaydet');
    expect(find.byKey(const Key('ihbar-hata')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ihbar-aciklama')), 'Muhasebede sahte masraf faturası düzenlendiği iddiası');
    await _bas(tester, 'ihbar-kaydet');
    final kod = tester.widget<SelectableText>(find.byKey(const Key('ihbar-takip-kodu'))).data!;
    expect(kod, hasLength(10));
    expect(k.ihbarlar.last.takipKodu, kod);
    expect(k.depo.denetim.olaylar.last.aciklama, isNot(contains('sahte')));
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();

    final yeni = k.ihbarlar.last;
    // TANI: geçici
    debugPrint('TANI ihbarlar=${k.ihbarlar.map((i) => i.id).toList()} yeni=${yeni.id} '
        'sorusturma=${k.sorusturmaOf(yeni.id)?.id} tamam=${find.text('Tamam').evaluate().length} '
        'anahtarlar=${find.byWidgetPredicate((w) => w.key is ValueKey<String> && '${(w.key! as ValueKey<String>).value}'.startsWith('sorusturma-ac')).evaluate().map((e) => e.widget.key).toList()} '
        'dialog=${find.byType(Dialog).evaluate().length} kart=${find.byType(Card).evaluate().length} '
        'ihbarAnahtar=${find.byWidgetPredicate((w) => w.key is ValueKey<String> && '${(w.key! as ValueKey<String>).value}'.startsWith('ihbar-')).evaluate().map((e) => e.widget.key).toList()} '
        'soruac=${find.text('Soruşturma aç').evaluate().length} sekme=${find.text('İhbarlar').evaluate().length} '
        'baslik=${find.text('Uyum ve iç soruşturma').evaluate().length} '
        'sekmeNo=${DefaultTabController.of(tester.element(find.byType(TabBarView))).index} '
        'kartMetin=${find.descendant(of: find.byType(Card), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).toList()}');
    await _bas(tester, 'sorusturma-ac-${yeni.id}');
    await _bas(tester, 'sorusturma-sorumlu');
    await tester.tap(find.text('Siz').last);
    await tester.pumpAndSettle();
    await _bas(tester, 'sorusturma-kaydet');
    expect(k.sorusturmaOf(yeni.id)!.sorumlu, 'av1');
  });

  testWidgets('Soruşturma: erişim, aşamalar ve sonuç; veri ihlali bildirimi', (tester) async {
    final k = await _ac(tester);
    await _bas(tester, 'uyum-sekme-sorusturma');
    expect(find.byKey(const Key('sorusturma-erisim-yok')), findsOneWidget);
    final s = k.sorusturmalar.first;
    await _bas(tester, 'sorusturma-${s.id}');
    expect(find.textContaining('Takip kodu'), findsOneWidget);

    await _bas(tester, 'sor-not-ekle');
    await tester.enterText(find.byKey(const Key('sor-not')), 'Tedarikçi ile görüşme yapıldı');
    await _bas(tester, 'sor-not-kaydet');
    expect(s.notlar, hasLength(2));

    await _bas(tester, 'sor-raporla');
    await _bas(tester, 'sor-kapat-kismen');
    await tester.enterText(find.byKey(const Key('sor-ozet')), 'Hediye kabulü doğrulandı; ihale yönlendirmesi tespit edilmedi.');
    await _bas(tester, 'sor-ozet-kaydet');
    expect(s.durum, SorusturmaDurumu.kapandi);
    expect(find.byKey(const Key('sor-sonuc')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _bas(tester, 'uyum-sekme-ihlal');
    final v = k.veriIhlalleri.single;
    expect(find.textContaining('saat'), findsWidgets);
    await _bas(tester, 'ihlal-bildir-${v.id}');
    expect(v.kurulaBildirim, isNotNull);
    expect(find.text('Kurul\'a bildirildi'), findsOneWidget);
  });
}
