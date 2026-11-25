import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:portal/ekranlar/ana_kabuk.dart';
import 'package:portal/servisler/kimlik_servisi.dart';
import 'package:portal/servisler/veri_deposu.dart';
import 'package:portal/tema/tema.dart';

Oturum _oturum(Set<Rol> roller) => Oturum(
      kullaniciId: 'av1',
      kiraciId: 'buro1',
      adSoyad: 'Av. Deneme Kullanıcı',
      eposta: 'deneme@buro.com.tr',
      kurumAdi: 'Deneme Hukuk',
      hesapTuru: HesapTuru.hukukBurosu,
      roller: roller,
    );

Future<BellekVeriDeposu> _ac(WidgetTester tester, {Set<Rol> roller = const {Rol.yoneticiOrtak}, String? menu}) async {
  tester.view.physicalSize = const Size(1500, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final depo = BellekVeriDeposu.demo(kiraciId: 'buro1', avukatId: 'av1');
  await tester.pumpWidget(MaterialApp(
    theme: acikTema(),
    home: AnaKabuk(oturum: _oturum(roller), cikisYap: () {}, depo: depo),
  ));
  await tester.pumpAndSettle();
  if (menu != null) {
    await tester.tap(find.byKey(Key('menu-$menu')));
    await tester.pumpAndSettle();
  }
  return depo;
}

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Genel Bakış: göstergeler, kritik işler ve duruşma çakışması', (tester) async {
    await _ac(tester);
    expect(find.text('Genel Bakış'), findsWidgets);
    expect(find.text('Açık Dosya'), findsOneWidget);
    expect(find.text('İş Kuyruğu'), findsOneWidget);
    expect(find.text('Teyit bekliyor'), findsWidgets);
    expect(find.text('Gecikti'), findsWidgets);
    expect(find.byKey(const Key('cakisma-rozeti')), findsWidgets);

    await _bas(tester, 'sekme-tum');
    expect(find.text('Devam ediyor'), findsWidgets);
  });

  testWidgets('Dosyada süre teyit edilir ve kanıtla tamamlanır', (tester) async {
    final depo = await _ac(tester, menu: 'dosyalar');
    await _bas(tester, 'dosya-d2');
    await _bas(tester, 'teyit-s2');
    expect(depo.sureler.firstWhere((s) => s.id == 's2').durum, SureDurumu.teyitli);

    await _bas(tester, 'tamamla-s2');
    await tester.enterText(find.byKey(const Key('kanit-alani')), 'UYAP gönderim 2026-445566');
    await _bas(tester, 'kanit-onayla');
    final s2 = depo.sureler.firstWhere((s) => s.id == 's2');
    expect(s2.durum, SureDurumu.tamamlandi);
    expect(s2.tamamlanmaKaniti, 'UYAP gönderim 2026-445566');
  });

  testWidgets('Avukat rolü gizli dosyayı görmez', (tester) async {
    await _ac(tester, roller: const {Rol.avukat}, menu: 'dosyalar');
    expect(find.text('3 dosya'), findsOneWidget);
    expect(find.byKey(const Key('dosya-d4')), findsNothing);
  });

  testWidgets('Kuyruktaki tebligat dosyaya bağlanır ve süre başlatılır', (tester) async {
    final depo = await _ac(tester, menu: 'tebligatlar');
    await _bas(tester, 'bagla-t2-d2');
    await _bas(tester, 'kural-HMK_CEVAP_DILEKCESI');
    expect(depo.tebligatlar.firstWhere((t) => t.id == 't2').dosyaId, 'd2');
    final yeni = depo.sureler.last;
    expect(yeni.tetikleyenTebligatId, 't2');
    expect(yeni.durum, SureDurumu.teyitBekliyor);
    expect(yeni.asilSorumlu, 'av1');
  });

  testWidgets('Yeni tebligat esas no ve mahkemeyle otomatik eşleşir, ikinci kayıt çoğalmaz', (tester) async {
    final depo = await _ac(tester, menu: 'tebligatlar');
    Future<void> kaydet() async {
      // Önceki kaydın bildirimi (SnackBar) yeni tebligat düğmesinin üstünde kalmasın.
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await _bas(tester, 'yeni-tebligat');
      await tester.enterText(find.byKey(const Key('tebligat-gonderen')), 'İstanbul 5. Asliye Ticaret Mahkemesi');
      await tester.enterText(find.byKey(const Key('tebligat-konu')), 'Ara karar');
      await tester.enterText(find.byKey(const Key('tebligat-esas')), '2026/123');
      await _bas(tester, 'tebligat-kaydet');
    }

    final once = depo.tebligatlar.length;
    await kaydet();
    expect(depo.tebligatlar.length, once + 1);
    expect(depo.tebligatlar.last.dosyaId, 'd1');
    await tester.tap(find.text('Şimdi değil'));
    await tester.pumpAndSettle();

    await kaydet();
    expect(depo.tebligatlar.length, once + 1);
  });

  testWidgets('Genel arama dosya bulur ve açar', (tester) async {
    await _ac(tester);
    await _bas(tester, 'genel-arama');
    await tester.enterText(find.byKey(const Key('arama-alani')), 'ise iade');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kara - İşe iade').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Kara - İşe iade'), findsWidgets);
    expect(find.text('Süreler'), findsOneWidget);
  });
}
