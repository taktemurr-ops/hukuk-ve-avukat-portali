import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portal/ekranlar/sunucu_abonelik_ekrani.dart';
import 'package:portal/main.dart';
import 'package:portal/servisler/api_istemcisi.dart';
import 'package:portal/servisler/kimlik_servisi.dart';
import 'package:portal/servisler/kurumsal_senkronu.dart';
import 'package:portal/servisler/sunucu_kimlik_servisi.dart';
import 'package:portal/servisler/sunucu_senkronu.dart';
import 'package:portal/servisler/veri_deposu.dart';

/// Sunucu sözleşmesini taklit eden sahte API: backend/sunucu uçlarıyla aynı JSON.
class SahteSunucu {
  final istekler = <String>[];
  var sureDurumu = 'teyitBekliyor';
  var ikiKurum = false;
  var kurumsal = false;
  var muvekkil = false;
  var ikiAdimli = false;
  final portalMesajlari = <Map<String, Object?>>[];
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
        if (j['eposta'] == 'yeni@buro.com.tr') {
          return _json({'hata': 'eposta_dogrulanmadi', 'mesaj': 'E-posta adresiniz henüz doğrulanmadı.'}, 403);
        }
        if (ikiAdimli) {
          if (j['ikiAdimliKod'] == null) return _json({'ikiAdimliGerekli': true});
          if (j['ikiAdimliKod'] != '123456') {
            return _json({'hata': 'iki_adimli_hatali', 'mesaj': 'Doğrulama kodu hatalı veya daha önce kullanılmış.'}, 401);
          }
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
        if (muvekkil) {
          return _json({
            'kullaniciId': 'mu1', 'kiraciId': 'k1', 'adSoyad': 'Ali Veli', 'eposta': 'ali@abc.com.tr',
            'kurumAdi': 'Yılmaz Hukuk', 'hesapTuru': 'hukukBurosu', 'roller': ['muvekkil'],
            'portalKisiId': 'm1', 'portalKisiAdi': 'ABC Gıda A.Ş.',
          });
        }
        return _json({
          'kullaniciId': 'u1',
          'kiraciId': 'k1',
          'adSoyad': 'Av. Ayşe Yılmaz',
          'eposta': 'ayse@yilmaz.av.tr',
          'kurumAdi': 'Yılmaz Hukuk',
          'hesapTuru': kurumsal ? 'kurumsal' : 'hukukBurosu',
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
      case 'GET /kisi-iliskileri':
        return _json([]);
      case 'PUT /kisiler/m1':
        return _json({'unvanGecmisi': []});
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
      case 'POST /acik/davet-kabul':
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (j['kod'] != 'abc123') {
          return _json({'hata': 'kural_ihlali', 'mesaj': 'Davet geçersiz, süresi dolmuş veya bu e-posta için değil'}, 409);
        }
        return _json({'kiraciId': 'k1', 'kullaniciId': 'u7'}, 201);
      case 'POST /acik/sifre-sifirlama':
        return _json({'durum': 'Adres kayıtlıysa şifre sıfırlama bağlantısı gönderildi.'}, 202);
      case 'POST /acik/sifre-sifirla':
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (j['kod'] != 'k0d') {
          return _json({'hata': 'gecersiz_istek', 'mesaj': 'Bağlantı geçersiz ya da süresi dolmuş.'}, 400);
        }
        return _json({'hesapSayisi': 1});
      case 'POST /acik/dogrulama-yeniden':
        return _json({'durum': 'gönderildi'}, 202);
      case 'POST /acik/eposta-dogrula':
        return _json({'hesapSayisi': 1});
      case 'POST /aktarim/tablo':
        return _json({
          'sayfa': 'Liste',
          'satirlar': [
            ['Adı Soyadı', 'TCKN/VKN'],
            ['Zeynep Aydın', ''],
          ],
          'uyarilar': [],
        });
      case 'POST /kisiler/toplu':
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return _json({'eklenen': (j['kisiler'] as List).length, 'atlanan': 0}, 201);
      case 'GET /belgeler/ara':
        return _json({
          'sonuclar': [
            {'belgeId': 'b1', 'ad': 'Bilirkişi raporu', 'dosyaId': 'd1', 'dosyaNo': '2026/0001', 'dosyaBaslik': 'x',
              'ocr': true, 'ozet': '… davacının «kıdem» «tazminatı» …'},
          ],
          'bekleyen': 2,
          'okunamayan': 0,
        });
      case 'GET /ben/takvim':
        return _json({'var': false});
      case 'POST /ben/takvim':
        return _json({'adres': 'https://api.ornek.test/acik/takvim/abc.ics', 'webcal': 'webcal://api.ornek.test/acik/takvim/abc.ics'}, 201);
      case 'GET /abonelik':
        return _json({
          'durum': 'deneme', 'etkinDurum': 'deneme', 'etkinDurumAdi': 'Deneme', 'donem': 'aylik',
          'donemBasi': '2026-11-20', 'donemSonu': '2026-12-04', 'ucretliKoltuk': 1, 'kullanilanKoltuk': 3,
          'donemSonundaIptal': false, 'yazilabilir': true,
          'paket': {'hesapTuru': 'hukukBurosu', 'fiyatTuru': 'koltukBasi', 'aylikFiyatKurus': 150000},
          'fiyatlar': [
            {'donem': 'aylik', 'koltuk': 3, 'matrahKurus': 450000, 'kdvKurus': 90000, 'toplamKurus': 540000},
            {'donem': 'yillik', 'koltuk': 3, 'matrahKurus': 4500000, 'kdvKurus': 900000, 'toplamKurus': 5400000},
          ],
          'odemeAltyapisi': true, 'odemeler': [],
        });
      case 'POST /abonelik/odeme':
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return _json({'referans': 'r' * 32, 'toplamKurus': j['donem'] == 'yillik' ? 5400000 : 540000,
          'odemeAdresi': 'https://odeme.ornek.test/sayfa/${j['donem']}'}, 201);
      case 'GET /portal/dosyalar':
        return _json([
          {
            'id': 'pd1', 'icNo': '2026/0007', 'tur': 'hukuk', 'baslik': 'Portaldaki alacak davası', 'asama': 'ilkDerece',
            'asamaAdi': 'İlk derece', 'acilis': '2026-10-01', 'kapali': false, 'sorumluAvukat': 'Av. Mert Şahin',
            'sonrakiDurusma': '2026-12-03T07:30:00.000Z', 'sonrakiDurusmaYeri': 'İstanbul 3. Asliye Ticaret',
            'okunmamisMesaj': 0,
          },
        ]);
      case 'GET /portal/dosyalar/pd1/belgeler':
        return _json([
          {'id': 'pb1', 'ad': 'Dava dilekçesi', 'tur': 'dilekce', 'surum': 1, 'sha256': 'a' * 64, 'boyut': 10,
            'dosyaAdi': 'dilekce.pdf', 'zaman': '2026-10-02T09:00:00.000Z'},
        ]);
      case 'GET /portal/dosyalar/pd1/mesajlar':
        return _json(portalMesajlari);
      case 'POST /portal/dosyalar/pd1/mesajlar':
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        portalMesajlari.add({'id': portalMesajlari.length + 1, 'muvekkilden': true, 'gonderen': 'Ali Veli',
          'metin': j['metin'], 'zaman': '2026-11-25T10:00:00.000Z', 'okundu': null});
        return _json({'id': portalMesajlari.length}, 201);
      case 'GET /portal-paylasimlari':
        return _json({'dosyalar': [], 'belgeler': []});
      case 'GET /gorev-sablonlari':
        return _json([]);
      case 'GET /taraflar':
        return _json([
          {'dosyaId': 'd1', 'kisiId': 'm1', 'sifat': 'muvekkil', 'dosyaAdi': '2026/0001 · Sunucudaki dosya', 'gizli': false, 'kapali': false},
        ]);
      case 'GET /gorevler':
        return _json([
          {
            'id': 'g1', 'baslik': 'Sunucudaki görev', 'atanan': 'u2', 'dosyaId': 'd1', 'yedek': null, 'sonTarih': '2026-12-01',
            'oncelik': 'yuksek', 'durum': 'acik', 'kaynakSureId': 's1', 'kanitGerekir': true, 'kapanisKaniti': null,
          },
        ]);
      case 'GET /durusmalar':
        return _json([
          {'id': 'du1', 'dosyaId': 'd1', 'baslangic': '2026-12-03T07:30:00.000Z', 'yer': 'İstanbul 3. Asliye Ticaret',
            'katilan': 'u2', 'sureDakika': 60, 'tur': 'Duruşma'},
        ]);
      case 'GET /tebligatlar':
        return _json([
          {'id': 'tb1', 'kanal': 'uets', 'ulasmaTarihi': '2026-11-20', 'tebligTarihi': '2026-11-25', 'gonderen': 'X Mahkemesi',
            'konu': 'Bilirkişi raporu', 'esasNo': null, 'taraflar': [], 'belgeOzeti': null, 'dosyaId': null},
        ]);
      case 'GET /vekaletnameler':
      case 'GET /etik-duvarlar':
      case 'GET /dosyalar/d1/belgeler':
        return _json([]);
      case 'GET /sirketler':
        return _json([
          {'id': 'sr1', 'unvan': 'ABC Holding A.Ş.', 'kisaAd': 'ABC Holding', 'vkn': null, 'anaSirketId': null},
        ]);
      case 'GET /sozlesmeler':
        return _json([
          {
            'id': 'sz1', 'no': 'SZ-2026-0001', 'sirketId': 'sr1', 'baslik': 'Sunucudaki bakım sözleşmesi', 'tur': 'hizmet',
            'karsiTaraf': 'Bakım Ltd.', 'sorumlu': 'u1', 'birim': 'Satın alma', 'durum': 'onayda', 'baslangic': null,
            'bitis': null, 'otomatikYenileme': false, 'yenilemeSuresiAy': 12, 'ihbarSuresiGun': null, 'bedelKurus': 150000000,
            'paraBirimi': 'TRY', 'onayTuru': 1, 'tarama': null, 'uyarilar': [],
          },
        ]);
      case 'GET /sozlesmeler/sz1/onay':
        return _json({
          'tur': 1, 'durum': 'devam', 'siradaki': 'direktor', 'onaylayabilir': true,
          'adimlar': [
            {'kod': 'hukuk', 'ad': 'Hukuk incelemesi', 'neden': 'Her sözleşme', 'onaycilar': ['u2']},
            {'kod': 'direktor', 'ad': 'Hukuk direktörü', 'neden': 'Sözleşme taranmadı', 'onaycilar': ['u1']},
            {'kod': 'finans', 'ad': 'Finans', 'neden': 'Bedel', 'onaycilar': ['u3']},
          ],
          'kararlar': [
            {'adimKodu': 'hukuk', 'kullanici': 'u2', 'karar': 'onay', 'not': '', 'zaman': '2026-11-24T10:00:00.000Z'},
          ],
        });
      case 'GET /talepler':
        return _json([
          {
            'id': 'tl1', 'no': 'HT-2026-0001', 'sirketId': 'sr1', 'baslik': 'NDA incelemesi', 'aciklama': '',
            'tur': 'sozlesmeInceleme', 'oncelik': 'normal', 'talepEden': 'Satış Md.', 'birim': 'Satış', 'atanan': 'u2',
            'durum': 'atandi', 'slaSonGun': '2026-11-27', 'slaDurumu': 'zamaninda', 'olusturma': '2026-11-24',
            'kapanis': null, 'sozlesmeId': null, 'beklemeBaslangici': null,
            'gecmis': [
              {'tarih': '2026-11-24', 'kullanici': 'u1', 'aciklama': 'Talep oluşturuldu'},
            ],
          },
        ]);
      case 'GET /dis-avukatlar':
        return _json({'avukatlar': [], 'isler': []});
      case 'GET /ihbarlar':
        return _json([
          {
            'id': 'ih1', 'zaman': '2026-11-20T09:00:00.000Z', 'kanal': 'web', 'kategori': 'rusvetYolsuzluk',
            'aciklama': 'Satın almada hediye alındığı iddiası', 'anonim': true, 'iletisim': null, 'ilgiliKisiler': ['u9'],
            'sirketId': null,
            'sorusturma': {
              'id': 'so1', 'sorumlu': 'u1', 'ekip': ['u2'], 'durum': 'sorusturma', 'sonuc': null, 'sonucOzeti': null,
              'acilis': '2026-11-21T09:00:00.000Z', 'ilkGeriBildirim': null,
              'notlar': [
                {'kullanici': 'u1', 'metin': 'Belgeler istendi', 'zaman': '2026-11-22T10:00:00.000Z'},
              ],
            },
          },
        ]);
      case 'GET /veri-ihlalleri':
        return _json([
          {
            'id': 'vi1', 'ogrenilme': '2026-11-24T08:00:00.000Z', 'aciklama': 'Yanlış alıcıya e-posta gitti',
            'etkilenenKisiSayisi': 3, 'kurulaBildirim': null, 'ilgililereBildirim': null,
          },
        ]);
      case 'GET /denetim':
        return _json([
          {'sira': 7, 'zaman': '2026-11-25T10:00:00.000Z', 'kullanici': 'u1', 'islem': 'disaAktarma', 'nesneTuru': 'rapor',
            'nesneId': 'İş yükü', 'aciklama': '', 'ozet': 'abcdef0123456789'},
          {'sira': 6, 'zaman': '2026-11-25T09:00:00.000Z', 'kullanici': '', 'islem': 'hesapAcma', 'nesneTuru': 'kiraci',
            'nesneId': 'k1', 'aciklama': '', 'ozet': '0123456789abcdef'},
        ]);
      case 'GET /denetim/dogrula':
        return _json({'saglam': true, 'bozukSira': null});
      case 'POST /denetim/kayit':
        return _json({'kaydedildi': true}, 201);
      case 'GET /kvkk/saklama':
        return _json({
          'sonPeriyodikImha': '2026-05-01',
          'kayitlar': [
            {'id': 'd9', 'ad': '2010/0003 · Eski dava', 'kategori': 'davaDosyasi', 'kapanis': '2010-02-01', 'saklamaEngeli': null},
          ],
          'tutanaklar': [
            {'id': 't1', 'no': 'IT-2026-001', 'tarih': '2026-11-20', 'dosyalar': ['d9'], 'yontem': 'yokEtme',
              'hazirlayan': 'u1', 'onaylayan': null, 'onayTarihi': null},
          ],
        });
      case 'POST /kvkk/imha-tutanagi/t1/onay':
        return _json({'onaylandi': true});
      case 'POST /sozlesmeler/sz1/onay':
        return _json({'tur': 1, 'durum': 'devam'});
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

Future<(SahteSunucu, ApiIstemcisi)> _uygulama(WidgetTester tester,
    {bool ikiKurum = false, bool kurumsal = false, bool muvekkil = false}) async {
  tester.view.physicalSize = const Size(1500, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final sunucu = SahteSunucu()
    ..ikiKurum = ikiKurum
    ..kurumsal = kurumsal
    ..muvekkil = muvekkil;
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
      'GET /kisiler', 'GET /cari', 'GET /emanet', 'GET /zaman', 'GET /icra', 'GET /taraflar', 'GET /gorevler',
      'GET /durusmalar', 'GET /tebligatlar', 'GET /vekaletnameler']));

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

  testWidgets('Kurumsal hesapta sözleşme ve onay zinciri sunucudan gelir', (tester) async {
    final (sunucu, _) = await _uygulama(tester, kurumsal: true);
    await tester.enterText(find.byKey(const Key('giris-eposta')), 'ayse@yilmaz.av.tr');
    await tester.enterText(find.byKey(const Key('giris-sifre')), 'Dogru-Sifre-2026');
    await _bas(tester, 'giris-yap');
    expect(sunucu.istekler, containsAll(['GET /sirketler', 'GET /sozlesmeler', 'GET /talepler', 'GET /sozlesmeler/sz1/onay',
      'GET /ihbarlar', 'GET /veri-ihlalleri', 'GET /dis-avukatlar']));
    await _bas(tester, 'menu-sozlesmeler');
    expect(find.textContaining('Sunucudaki bakım sözleşmesi'), findsWidgets);
    // Demo verisi kullanılmaz.
    expect(find.textContaining('SZ-2026-0002'), findsNothing);
  });

  test('Sunucu JSON\'undan sözleşme, onay süreci ve talep', () {
    final s = KurumsalSenkronu.sozlesmeJson({
      'id': 'sz1', 'no': 'SZ-2026-0001', 'baslik': 'X', 'tur': 'bilinmeyen', 'sorumlu': 'u1', 'durum': 'onayda',
      'bedelKurus': 150000000, 'paraBirimi': 'TRY',
      'tarama': {'otomatikYenileme': true, 'bulgular': [
        {'kod': 'ceza', 'baslik': 'Ceza şartı', 'seviye': 'yuksek', 'aciklama': 'Sınırsız'},
      ]},
    });
    expect(s.tur, SozlesmeTuru.diger);
    expect(s.bedel!.kurus, 150000000);
    expect(s.tarama!.genelSeviye, SozlesmeRiski.yuksek);
    final p = KurumsalSenkronu.surecJson('sz1', 'u1', {
      'tur': 1, 'durum': 'devam',
      'adimlar': [
        {'kod': 'hukuk', 'ad': 'Hukuk', 'neden': '', 'onaycilar': ['u2']},
        {'kod': 'direktor', 'ad': 'Direktör', 'neden': '', 'onaycilar': ['u1']},
      ],
      'kararlar': [
        {'adimKodu': 'hukuk', 'kullanici': 'u2', 'karar': 'onay', 'not': '', 'zaman': '2026-11-24T10:00:00.000Z'},
      ],
    })!;
    expect(p.siradaki!.kod, 'direktor');
    expect(p.onaylayabilir('u1'), isTrue);
    expect(p.onaylayabilir('u2'), isFalse);
    expect(KurumsalSenkronu.surecJson('sz1', 'u1', {'tur': 0}), isNull);
    final t = KurumsalSenkronu.talepJson({
      'id': 'tl1', 'no': 'HT-2026-0001', 'baslik': 'NDA', 'tur': 'kvkk', 'oncelik': 'acil', 'talepEden': 'A',
      'birim': 'B', 'durum': 'bilgiBekleniyor', 'slaSonGun': '2026-11-27', 'olusturma': '2026-11-24',
      'beklemeBaslangici': '2026-11-25', 'gecmis': [
        {'tarih': '2026-11-25', 'kullanici': 'u1', 'aciklama': 'Bilgi bekleniyor: imzalı nüsha'},
      ],
    });
    expect(t.beklemeBaslangici, Tarih(2026, 11, 25));
    expect(t.gecmis.single.aciklama, contains('imzalı'));
  });

  test('Sunucu JSON\'undan ihbar, soruşturma ve veri ihlali', () {
    final (i, s) = KurumsalSenkronu.ihbarJson({
      'id': 'ih1', 'zaman': '2026-11-20T09:00:00.000Z', 'kanal': 'telefon', 'kategori': 'tacizMobbing',
      'aciklama': 'x', 'anonim': false, 'iletisim': 'a@b.com', 'ilgiliKisiler': ['u9'],
      'sorusturma': {
        'id': 'so1', 'sorumlu': 'u1', 'ekip': ['u2'], 'durum': 'raporlama', 'acilis': '2026-11-21T09:00:00.000Z',
        'ilkGeriBildirim': '2026-11-22T09:00:00.000Z', 'notlar': [],
      },
    });
    expect(i.takipKodu, isEmpty);
    expect(i.kanal, IhbarKanali.telefon);
    expect(s!.erisebilir('u2'), isTrue);
    expect(s.erisebilir('u9'), isFalse);
    expect(s.durum, SorusturmaDurumu.raporlama);
    expect(s.geriBildirimGecikti(DateTime.utc(2026, 12, 30)), isFalse);
    expect(() => s.ekipEkle('u9', ekleyen: 'u1'), throwsStateError);
    final v = KurumsalSenkronu.ihlalJson({
      'id': 'vi1', 'ogrenilme': '2026-11-24T08:00:00.000Z', 'aciklama': 'x', 'etkilenenKisiSayisi': 3,
    });
    expect(v.kurulSonZaman.toUtc(), DateTime.utc(2026, 11, 27, 8));
    expect(v.gecikti(DateTime.utc(2026, 11, 27, 9)), isTrue);
  });

  test('Sunucu JSON\'undan görev, duruşma, tebligat ve vekâletname', () {
    final g = SunucuSenkronu.gorevJson({
      'id': 'g1', 'baslik': 'İstinaf gönder', 'atanan': 'u2', 'sonTarih': '2026-12-01', 'oncelik': 'kritik',
      'durum': 'acik', 'kaynakSureId': 's1', 'kanitGerekir': true,
    });
    expect(() => g.kapat(), throwsArgumentError);
    expect(g.gecikti(Tarih(2026, 12, 2)), isTrue);
    final du = SunucuSenkronu.durusmaJson({
      'id': 'du1', 'dosyaId': 'd1', 'baslangic': '2026-12-03T07:30:00.000Z', 'yer': 'A', 'katilan': 'u2', 'sureDakika': 90,
    });
    expect(du.bitis.toUtc(), DateTime.utc(2026, 12, 3, 9));
    final t = SunucuSenkronu.tebligatJson({
      'id': 'tb1', 'kanal': 'uets', 'ulasmaTarihi': '2026-11-20', 'tebligTarihi': '2026-11-25', 'gonderen': 'X',
      'konu': 'Y', 'taraflar': ['A'], 'dosyaId': 'd1',
    }, 'k1');
    expect(t.tebligTarihi, Tarih(2026, 11, 25));
    expect(t.eslesmeDurumu, EslesmeDurumu.eslesti);
    final v = SunucuSenkronu.vekaletnameJson({
      'id': 'v1', 'muvekkilId': 'm1', 'avukatlar': ['u1'], 'duzenlemeTarihi': '2026-01-05', 'genel': true,
      'ozelYetkiler': ['sulh', 'bilinmeyen'], 'dosyalar': [], 'durum': 'azil', 'durumTarihi': '2026-11-01',
    }, 'k1');
    expect(v.ozelYetkiler, {OzelYetki.sulh});
    expect(v.durum, VekaletDurumu.azil);
  });

  testWidgets('Müvekkil oturumu yalnızca portal uçlarını kullanır', (tester) async {
    final (sunucu, _) = await _uygulama(tester, muvekkil: true);
    await tester.enterText(find.byKey(const Key('giris-eposta')), 'ali@abc.com.tr');
    await tester.enterText(find.byKey(const Key('giris-sifre')), 'Dogru-Sifre-2026');
    await _bas(tester, 'giris-yap');
    expect(find.textContaining('Portaldaki alacak davası'), findsWidgets);
    expect(sunucu.istekler, contains('GET /portal/dosyalar'));
    // Büro uçlarına hiç gidilmez.
    expect(sunucu.istekler.where((i) => const ['GET /dosyalar', 'GET /kisiler', 'GET /kullanicilar'].contains(i)), isEmpty);
  });

  testWidgets('Davet koduyla hesap açılır; hatalı kodda sunucunun iletisi gösterilir', (tester) async {
    final (sunucu, _) = await _uygulama(tester);
    await _bas(tester, 'davet-kabul');
    await tester.enterText(find.byKey(const Key('davet-kod')), 'yanlis');
    await tester.enterText(find.byKey(const Key('davet-kabul-eposta')), 'selin@yilmaz.av.tr');
    await tester.enterText(find.byKey(const Key('davet-ad')), 'Av. Selin Arslan');
    await tester.enterText(find.byKey(const Key('davet-sifre')), 'Guclu-Sifre-2026');
    await tester.enterText(find.byKey(const Key('davet-sifre2')), 'Guclu-Sifre-2026');
    await _bas(tester, 'davet-kabul-gonder');
    expect(find.textContaining('Davet geçersiz'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('davet-kod')), 'abc123');
    await _bas(tester, 'davet-kabul-gonder');
    expect(find.byKey(const Key('davet-tamam')), findsOneWidget);
    expect(sunucu.istekler.where((i) => i == 'POST /acik/davet-kabul').length, 2);
  });

  testWidgets('İki adımlı doğrulama açık hesapta kod sorulur', (tester) async {
    final (sunucu, api) = await _uygulama(tester);
    sunucu.ikiAdimli = true;
    await tester.enterText(find.byKey(const Key('giris-eposta')), 'ayse@yilmaz.av.tr');
    await tester.enterText(find.byKey(const Key('giris-sifre')), 'Dogru-Sifre-2026');
    await _bas(tester, 'giris-yap');
    await tester.enterText(find.byKey(const Key('giris-iki-adimli-kod')), '000000');
    await _bas(tester, 'giris-iki-adimli-onay');
    expect(find.textContaining('Doğrulama kodu hatalı'), findsOneWidget);
    expect(api.token, isNull);
    await _bas(tester, 'giris-yap');
    await tester.enterText(find.byKey(const Key('giris-iki-adimli-kod')), '123456');
    await _bas(tester, 'giris-iki-adimli-onay');
    expect(api.token, 'tkn');
  });

  testWidgets('Abonelik ödemesi sunucunun hesapladığı tutarla ödeme sayfasını açar', (tester) async {
    final sunucu = SahteSunucu();
    final api = ApiIstemcisi(Uri.parse('https://api.ornek.test/'), istemci: MockClient(sunucu.yanit))..token = 'tkn';
    final senkron = SunucuSenkronu(api, BellekVeriDeposu('k1'));
    Uri? acilan;
    await tester.pumpWidget(MaterialApp(
      home: SunucuAbonelikEkrani(uzak: senkron, sayfaAc: (u) async {
        acilan = u;
        return true;
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('5.400,00'), findsOneWidget);
    await tester.tap(find.text('Yıllık (2 ay hediye)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('54.000,00'), findsOneWidget);
    await _bas(tester, 'sunucu-odeme-yap');
    expect(acilan.toString(), 'https://odeme.ornek.test/sayfa/yillik');
    expect(sunucu.istekler, contains('POST /abonelik/odeme'));
  });

  testWidgets('Doğrulanmamış e-postada açıklama ve yeni bağlantı düğmesi gösterilir', (tester) async {
    final (sunucu, api) = await _uygulama(tester);
    await tester.enterText(find.byKey(const Key('giris-eposta')), 'yeni@buro.com.tr');
    await tester.enterText(find.byKey(const Key('giris-sifre')), 'Dogru-Sifre-2026');
    await _bas(tester, 'giris-yap');
    expect(find.textContaining('henüz doğrulanmadı'), findsOneWidget);
    expect(api.token, isNull);
    await _bas(tester, 'dogrulama-yeniden');
    expect(sunucu.istekler, contains('POST /acik/dogrulama-yeniden'));
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

  test('Sunucu JSON\'undan saklama kaydı', () {
    final k = SunucuSenkronu.saklamaKaydiJson(
        {'id': 'd9', 'ad': 'x', 'kategori': 'danismanlik', 'kapanis': null, 'saklamaEngeli': 'Devam eden dava'});
    expect(k.kategori, VeriKategorisi.danismanlik);
    expect(k.kapanis, isNull);
    expect(k.yasalSaklamaEngeli, 'Devam eden dava');
  });

  test('KVKK saklama verisi sunucudan yüklenir; onay sunucu kimliğiyle gider', () async {
    final sunucu = SahteSunucu();
    final api = ApiIstemcisi(Uri.parse('https://api.ornek.test/'), istemci: MockClient(sunucu.yanit))..token = 'tkn';
    final depo = BellekVeriDeposu('k1');
    final senkron = SunucuSenkronu(api, depo);
    await senkron.yenile();
    expect(depo.saklamaKayitlari.map((k) => k.id), ['d9']);
    expect(depo.saklama.sonPeriyodikImha, Tarih(2026, 5, 1));
    final t = depo.saklama.tutanaklar.single;
    expect(t.no, 'IT-2026-001');
    expect(await depo.imhaTutanagiOnayla(t), isNull);
    expect(sunucu.istekler, contains('POST /kvkk/imha-tutanagi/t1/onay'));
  });

  test('Denetim: okuma olayı sunucuya gider, sunucu zinciri okunur', () async {
    final sunucu = SahteSunucu();
    final api = ApiIstemcisi(Uri.parse('https://api.ornek.test/'), istemci: MockClient(sunucu.yanit))..token = 'tkn';
    final depo = BellekVeriDeposu('k1');
    final senkron = SunucuSenkronu(api, depo);
    depo.okumaKaydet(DenetimIslemi.disaAktarma, 'rapor', 'İş yükü', 'CSV');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sunucu.istekler, contains('POST /denetim/kayit'));
    final (olaylar, bozuk) = await senkron.denetimGetir();
    expect(bozuk, isNull);
    expect(olaylar.map((o) => o.sira), [7, 6]);
    expect(olaylar.first.islemAdi, 'Dışa aktarma');
    expect(olaylar.last.islemAdi, 'hesapAcma');
  });

  test('Şifre sıfırlama: istek her durumda sessiz, geçersiz kodda sunucunun iletisi', () async {
    final sunucu = SahteSunucu();
    final api = ApiIstemcisi(Uri.parse('https://api.ornek.test/'), istemci: MockClient(sunucu.yanit));
    final servis = SunucuKimlikServisi(api);
    await servis.sifreSifirlamaIste('ayse@yilmaz.av.tr');
    expect(sunucu.istekler, contains('POST /acik/sifre-sifirlama'));
    await expectLater(
      servis.sifreSifirla(kod: 'yanlis', yeniSifre: 'Yeni-Sifre-2026'),
      throwsA(isA<KimlikHatasi>().having((e) => e.mesaj, 'mesaj', contains('süresi dolmuş'))),
    );
    await servis.sifreSifirla(kod: 'k0d', yeniSifre: 'Yeni-Sifre-2026');
  });
  test('Excel aktarımı: tablo sunucuda okunur, kayıtlar tek istekte sunucuya yazılır', () async {
    final sunucu = SahteSunucu();
    final api = ApiIstemcisi(Uri.parse('https://api.ornek.test/'), istemci: MockClient(sunucu.yanit))..token = 'tkn';
    final depo = BellekVeriDeposu('k1');
    final senkron = SunucuSenkronu(api, depo);
    final satirlar = await senkron.tabloOku('liste.xlsx', [0x50, 0x4b, 3, 4]);
    expect(satirlar.last, ['Zeynep Aydın', '']);
    final o = KisiAktarimi.onizle(csv: 'Adı Soyadı;TCKN/VKN\nZeynep Aydın;', mevcut: const []);
    final (n, hata) = await depo.kisileriAktar(o);
    expect(hata, isNull);
    expect(n, 1);
    expect(sunucu.istekler, containsAll(['POST /aktarim/tablo', 'POST /kisiler/toplu']));
  });

  test('Belge araması sunucuda yapılır; bekleyen belge sayısı da döner', () async {
    final sunucu = SahteSunucu();
    final api = ApiIstemcisi(Uri.parse('https://api.ornek.test/'), istemci: MockClient(sunucu.yanit))..token = 'tkn';
    final depo = BellekVeriDeposu('k1');
    SunucuSenkronu(api, depo);
    final (s, bekleyen, hata) = await depo.belgeAra('kıdem tazminatı');
    expect(hata, isNull);
    expect(bekleyen, 2);
    expect(s.single.ocr, isTrue);
    expect(s.single.ozet, contains('«kıdem»'));
  });

  test('Takvim aboneliği: durum ve bir kez gösterilen bağlantı', () async {
    final sunucu = SahteSunucu();
    final api = ApiIstemcisi(Uri.parse('https://api.ornek.test/'), istemci: MockClient(sunucu.yanit))..token = 'tkn';
    final senkron = SunucuSenkronu(api, BellekVeriDeposu('k1'));
    expect((await senkron.takvimDurumu())['var'], isFalse);
    final (adres, webcal) = await senkron.takvimBaglantisiOlustur();
    expect(adres, endsWith('.ics'));
    expect(webcal, startsWith('webcal://'));
  });

  test('Sunucu çıkar çatışması raporu: korumalı dosya adı ve kimliği gelmez', () {
    final r = SunucuSenkronu.raporJson({
      'eslesmeler': [
        {
          'aday': {'ad': 'Orman Enerji', 'sifat': 'karsiTaraf', 'kimlikNo': null},
          'kisiAdi': 'Orman Enerji A.Ş.',
          'tur': 'tamIsim',
          'benzerlik': 1,
          'seviye': 'catisma',
          'iliski': null,
          'dosya': {'dosyaId': null, 'dosyaAdi': 'Korumalı dosya', 'sifat': 'muvekkil', 'kapali': false},
        },
      ],
      'enYuksek': 'catisma',
    });
    expect(r.catismaVar, isTrue);
    expect(r.eslesmeler.single.dosya!.dosyaId, isNull);
    expect(r.eslesmeler.single.dosya!.dosyaAdi, DosyaOzeti.korumaliAd);
  });
}
