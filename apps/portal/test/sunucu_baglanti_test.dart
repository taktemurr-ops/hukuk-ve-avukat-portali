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
  final tahsilatlar = <Map<String, Object?>>[];

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
      case 'GET /kisiler':
        return _json([
          {'id': 'm1', 'tur': 'tuzel', 'ad': 'Sunucu Müvekkil A.Ş.', 'kimlikNo': null, 'eposta': null},
        ]);
      case 'GET /cari':
        return _json([
          {'id': 'c1', 'muvekkilId': 'm1', 'dosyaId': 'd1', 'tur': 'masrafAvansiAlindi', 'tutarKurus': 500000,
            'tarih': '2026-11-02', 'aciklama': 'Avans', 'belgeNo': null},
        ]);
      case 'GET /emanet':
        return _json([
          {'id': 'e1', 'muvekkilId': 'm1', 'dosyaId': 'd1', 'tur': 'giris', 'tutarKurus': 1250000, 'tarih': '2026-11-03',
            'aciklama': 'İcra tahsilatı', 'mahsupOnayi': null},
        ]);
      case 'GET /zaman':
        return _json([
          {'id': 'z1', 'kullanici': 'u2', 'dosyaId': 'd1', 'tarih': '2026-11-20', 'dakika': 90, 'faturaDakikasi': 90,
            'aciklama': 'Sunucudan gelen çalışma', 'saatlikKurus': 200000, 'tutarKurus': 300000, 'faturalanabilir': true,
            'durum': 'taslak', 'onaylayan': null, 'faturaNo': null},
        ]);
      case 'GET /icra':
        return _json([
          {
            'id': 'i1', 'dosyaId': 'd1', 'icraDairesi': 'İstanbul 5. İcra Dairesi', 'esasNo': '2026/123',
            'borclu': 'Sunucu Borçlu Ltd.', 'takipTuru': 'ilamsiz', 'asilKurus': 10000000, 'temerrut': '2026-01-01',
            'takipTarihi': '2026-03-01', 'faizTuru': 'yasal', 'durum': 'haciz', 'vekaletKurus': 0,
            'takipOncesiMasrafKurus': 0, 'takipSonrasiMasrafKurus': 0, 'islemisFaizElleKurus': null,
            'tebligTarihi': null, 'akdiOran': null, 'tahsilatlar': tahsilatlar,
          },
        ]);
      case 'POST /icra/i1/tahsilat':
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        tahsilatlar.add({'id': 't${tahsilatlar.length + 1}', 'tarih': j['tarih'], 'tutarKurus': j['tutarKurus'],
          'aciklama': j['aciklama']});
        return _json({'id': 't${tahsilatlar.length}'}, 201);
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
    expect(sunucu.istekler, containsAll(['GET /ben', 'GET /kullanicilar', 'GET /dosyalar', 'GET /dosyalar/d1/sureler',
      'GET /kisiler', 'GET /cari', 'GET /emanet', 'GET /zaman', 'GET /icra']));

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

  testWidgets('Sunucudaki icra dosyası listelenir', (tester) async {
    final (sunucu, _) = await _uygulama(tester);
    await tester.enterText(find.byKey(const Key('giris-eposta')), 'ayse@yilmaz.av.tr');
    await tester.enterText(find.byKey(const Key('giris-sifre')), 'Dogru-Sifre-2026');
    await _bas(tester, 'giris-yap');
    await _bas(tester, 'menu-icra');
    expect(find.textContaining('Sunucu Borçlu Ltd.'), findsWidgets);
    expect(sunucu.istekler.where((i) => i == 'GET /icra').length, 1);
  });

  test('Sunucu JSON\'undan icra dosyası ve kapak hesabı', () {
    final (i, faiz, oran) = SunucuSenkronu.icraJson({
      'id': 'i1', 'dosyaId': 'd1', 'icraDairesi': 'X', 'esasNo': null, 'borclu': 'B', 'takipTuru': 'ilamsiz',
      'asilKurus': 10000000, 'temerrut': '2026-01-01', 'takipTarihi': '2026-03-01', 'faizTuru': 'akdi', 'durum': 'yeniDurum',
      'vekaletKurus': 0, 'takipOncesiMasrafKurus': 25000, 'takipSonrasiMasrafKurus': 0, 'islemisFaizElleKurus': null,
      'tebligTarihi': null, 'akdiOran': 24.0,
      'tahsilatlar': [
        {'id': 't1', 'tarih': '2026-04-01', 'tutarKurus': 1000000, 'aciklama': 'Maaş haczi'},
      ],
    });
    expect(faiz, FaizTuru.akdi);
    expect(oran, 24.0);
    expect(i.durum, IcraDurumu.takipAcildi);
    expect(i.talep.takipOncesiMasraf.kurus, 25000);
    final h = i.hesap(Tarih(2026, 4, 1), FaizTablosu.sabit(oran!));
    expect(h.tahsilEdilen.kurus, 1000000);
    expect(h.mahsuplar.single.masrafa.kurus, greaterThan(0));
  });

  test('Sunucu JSON\'undan zaman ve emanet', () {
    final z = SunucuSenkronu.zamanJson({
      'id': 'z1', 'kullanici': 'u2', 'dosyaId': 'd1', 'tarih': '2026-11-20', 'dakika': 61, 'aciklama': 'Dilekçe',
      'saatlikKurus': 200000, 'faturalanabilir': true, 'durum': 'onaylandi', 'onaylayan': 'u1', 'faturaNo': null,
    });
    expect(z.faturaDakikasi(), 66);
    expect(z.tutar().kurus, 220000);
    final e = SunucuSenkronu.emanetJson({
      'id': 'e1', 'muvekkilId': 'm1', 'dosyaId': 'd1', 'tur': 'ucretMahsubu', 'tutarKurus': 100, 'tarih': '2026-11-03',
      'aciklama': 'x', 'mahsupOnayi': 'Sözleşme m.5',
    });
    expect(e.tur, EmanetHareketTuru.ucretMahsubu);
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
