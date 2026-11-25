import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portal/main.dart';
import 'package:portal/servisler/api_istemcisi.dart';
import 'package:portal/servisler/sunucu_kimlik_servisi.dart';
import 'package:portal/servisler/sunucu_senkronu.dart';

/// Sunucu sözleşmesini taklit eden sahte API: backend/sunucu uçlarıyla aynı JSON.
class SahteSunucu {
  final istekler = <String>[];
  var sureDurumu = 'teyitBekliyor';
  var ikiKurum = false;

  http.Response _json(Object? o, [int d = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(o)), d, headers: {'content-type': 'application/json'});

  Future<http.Response> yanit(http.Request r) async {
    istekler.add('${r.method} ${r.url.path}');
    final yetkili = r.headers['authorization'] == 'Bearer tkn';
    switch ('${r.method} ${r.url.path}') {
      case 'POST /giris':
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (j['sifre'] != 'Dogru-Sifre-2026') {
          return _json({'hata': 'giris_hatali', 'mesaj': 'E-posta veya şifre hatalı ya da hesap geçici olarak kilitli.'}, 401);
        }
        if (ikiKurum && j['kiraciId'] == null) {
          return _json({
            'kurumSecin': [
              {'kiraciId': 'k1', 'ad': 'Yılmaz Hukuk'},
              {'kiraciId': 'k2', 'ad': 'ABC Gıda Hukuk'},
            ],
          });
        }
        return _json({'token': 'tkn', 'kullaniciId': 'u1', 'kiraciId': j['kiraciId'] ?? 'k1', 'gecerlilikSaniye': 28800});
      case 'GET /ben':
        if (!yetkili) return _json({'hata': 'yetkisiz', 'mesaj': 'Oturum açmanız gerekiyor.'}, 401);
        return _json({
          'kullaniciId': 'u1',
          'kiraciId': 'k1',
          'adSoyad': 'Av. Ayşe Yılmaz',
          'eposta': 'ayse@yilmaz.av.tr',
          'kurumAdi': 'Yılmaz Hukuk',
          'hesapTuru': 'hukukBurosu',
          'roller': ['yoneticiOrtak', 'bilinmeyenRol'],
        });
      case 'GET /kullanicilar':
        return _json([
          {'id': 'u1', 'adSoyad': 'Av. Ayşe Yılmaz', 'aktif': true, 'roller': ['yoneticiOrtak']},
          {'id': 'u2', 'adSoyad': 'Av. Mert Şahin', 'aktif': true, 'roller': ['avukat']},
        ]);
      case 'GET /dosyalar':
        return _json([
          {
            'id': 'd1', 'icNo': '2026/0001', 'tur': 'hukuk', 'baslik': 'Sunucudaki dosya', 'sorumlu': 'u2',
            'yedekSorumlu': 'u1', 'gizli': false, 'asama': 'ilkDerece', 'acilis': '2026-11-01',
          },
        ]);
      case 'GET /dosyalar/d1/sureler':
        return _json([
          {
            'id': 's1', 'aciklama': 'İstinaf', 'kuralKodu': 'HMK_ISTINAF', 'sonGun': '2026-12-09', 'durum': sureDurumu,
            'olusturan': 'u2', 'asilSorumlu': 'u2', 'yedekSorumlu': 'u1', 'teyitEden': null, 'baslangic': '2026-11-25',
            'adimlar': [
              {'tarih': '2026-11-25', 'aciklama': 'Başlangıç'},
            ],
            'kanit': null,
          },
        ]);
      case 'POST /sureler/s1/teyit':
        sureDurumu = 'teyitli';
        return _json({'durum': 'teyitli'});
      case 'POST /cikis':
        return _json({'durum': 'kapatildi'});
    }
    return _json({'hata': 'bulunamadi', 'mesaj': 'Kayıt bulunamadı.'}, 404);
  }
}

Future<void> _bas(WidgetTester tester, String anahtar) async {
  await tester.ensureVisible(find.byKey(Key(anahtar)));
  await tester.tap(find.byKey(Key(anahtar)));
  await tester.pumpAndSettle();
}

Future<(SahteSunucu, ApiIstemcisi)> _uygulama(WidgetTester tester, {bool ikiKurum = false}) async {
  tester.view.physicalSize = const Size(1500, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final sunucu = SahteSunucu()..ikiKurum = ikiKurum;
  final api = ApiIstemcisi(Uri.parse('https://api.ornek.test/'), istemci: MockClient(sunucu.yanit));
  await tester.pumpWidget(PortalUygulamasi(kimlikServisi: SunucuKimlikServisi(api), api: api));
  await tester.pumpAndSettle();
  return (sunucu, api);
}

void main() {
  testWidgets('Hatalı şifrede sunucunun iletisi gösterilir', (tester) async {
    await _uygulama(tester);
    await tester.enterText(find.byKey(const Key('giris-eposta')), 'ayse@yilmaz.av.tr');
    await tester.enterText(find.byKey(const Key('giris-sifre')), 'Yanlis-Sifre-1');
    await _bas(tester, 'giris-yap');
    expect(find.textContaining('hesap geçici olarak kilitli'), findsOneWidget);
  });

  testWidgets('Sunucuyla giriş, veri yükleme ve süre teyidi', (tester) async {
    final (sunucu, api) = await _uygulama(tester);
    await tester.enterText(find.byKey(const Key('giris-eposta')), 'ayse@yilmaz.av.tr');
    await tester.enterText(find.byKey(const Key('giris-sifre')), 'Dogru-Sifre-2026');
    await _bas(tester, 'giris-yap');
    expect(api.token, 'tkn');
    expect(sunucu.istekler, containsAll(['GET /ben', 'GET /kullanicilar', 'GET /dosyalar', 'GET /dosyalar/d1/sureler']));

    await _bas(tester, 'menu-dosyalar');
    expect(find.textContaining('Sunucudaki dosya'), findsWidgets);
    await tester.tap(find.textContaining('Sunucudaki dosya').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Av. Mert Şahin'), findsWidgets);

    await _bas(tester, 'teyit-s1');
    expect(sunucu.istekler, contains('POST /sureler/s1/teyit'));
    expect(sunucu.istekler.where((i) => i == 'GET /dosyalar').length, 2);
    expect(find.byKey(const Key('tamamla-s1')), findsOneWidget);
  });

  testWidgets('Birden çok kurumda hesap varsa kurum seçilir', (tester) async {
    final (_, api) = await _uygulama(tester, ikiKurum: true);
    await tester.enterText(find.byKey(const Key('giris-eposta')), 'ayse@yilmaz.av.tr');
    await tester.enterText(find.byKey(const Key('giris-sifre')), 'Dogru-Sifre-2026');
    await _bas(tester, 'giris-yap');
    expect(find.text('ABC Gıda Hukuk'), findsOneWidget);
    await _bas(tester, 'kurum-k2');
    expect(api.token, 'tkn');
  });

  test('Sunucu JSON\'undan dosya ve süre', () {
    final d = SunucuSenkronu.dosyaJson({
      'id': 'd1', 'icNo': '2026/0001', 'tur': 'hukuk', 'baslik': 'x', 'sorumlu': 'u2', 'yedekSorumlu': null,
      'gizli': false, 'asama': 'bilinmeyen', 'acilis': '2026-11-01',
    }, 'k1');
    expect(d.tur, DosyaTuru.hukuk);
    expect(d.asama, DosyaAsamasi.onDegerlendirme);
    expect(d.acilisTarihi, Tarih(2026, 11, 1));
    final s = SunucuSenkronu.sureJson({
      'id': 's1', 'aciklama': 'x', 'kuralKodu': 'YOK', 'sonGun': '2026-12-09', 'durum': 'teyitli',
      'olusturan': 'u2', 'asilSorumlu': 'u2',
    }, 'd1');
    expect(s, isNull);
  });
}
