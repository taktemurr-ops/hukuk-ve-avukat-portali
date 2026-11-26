import 'dart:convert';

import 'package:hukuk_sunucu/hukuk_sunucu.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _istek(String yol, {String yontem = 'POST', Object? govde, Map<String, String>? basliklar}) =>
    Request(yontem, Uri.parse('http://yerel/$yol'), body: govde, headers: basliklar);

void main() {
  group('Hız sınırı', () {
    test('kimlik uçlarında 10 dakikada 30 istekten sonra 429', () async {
      var saat = DateTime(2026, 11, 26, 9);
      final h = HizSiniri(saat: () => saat).middleware((_) => Response.ok('ok'));
      for (var i = 0; i < 30; i++) {
        expect((await h(_istek('giris'))).statusCode, 200);
      }
      final r = await h(_istek('giris'));
      expect(r.statusCode, 429);
      expect(int.parse(r.headers['retry-after']!), greaterThan(0));
      // Aynı gruptaki diğer uç da sınırlı; oturumlu uçlar sınırsız.
      expect((await h(_istek('acik/sifre-sifirla'))).statusCode, 429);
      expect((await h(_istek('dosyalar', yontem: 'GET'))).statusCode, 200);
      // Pencere geçince yeniden açılır.
      saat = saat.add(const Duration(minutes: 11));
      expect((await h(_istek('giris'))).statusCode, 200);
    });

    test('açık uçlarda dakikada 60 istek', () async {
      final h = HizSiniri().middleware((_) => Response.ok('ok'));
      for (var i = 0; i < 60; i++) {
        await h(_istek('acik/ihbar-durumu'));
      }
      expect((await h(_istek('acik/ihbar-durumu'))).statusCode, 429);
    });

    test('güvenilir vekil yokken X-Forwarded-For dikkate alınmaz', () {
      final r = _istek('giris', basliklar: {'x-forwarded-for': '1.2.3.4'});
      expect(istemciIp(r), isNot('1.2.3.4'));
      expect(istemciIp(_istek('giris', basliklar: {'x-forwarded-for': '9.9.9.9, 5.6.7.8'}), guvenilirVekil: true),
          '5.6.7.8');
    });
  });

  group('İstek gövdesi', () {
    test('1 MB üzerindeki JSON belleğe alınmadan reddedilir', () async {
      final buyuk = Stream<List<int>>.fromIterable(List.generate(2048, (_) => List.filled(1024, 0x20)));
      final r = Request('POST', Uri.parse('http://yerel/dosyalar'), body: buyuk);
      expect(() => jsonGovde(r), throwsA(isA<ApiHatasi>().having((e) => e.durum, 'durum', 413)));
    });

    test('beyan edilen büyük boyut hemen reddedilir', () async {
      final r = Request('POST', Uri.parse('http://yerel/dosyalar'),
          body: Stream<List<int>>.fromIterable([utf8.encode('{}')]), headers: {'content-length': '99999999'});
      await expectLater(govdeBaytlari(r, 1024), throwsA(isA<ApiHatasi>().having((e) => e.durum, 'durum', 413)));
    });

    test('UTF-8 olmayan gövde 400', () async {
      final r = Request('POST', Uri.parse('http://yerel/dosyalar'), body: [0xFF, 0xFE, 0x00]);
      expect(() => jsonGovde(r), throwsA(isA<ApiHatasi>().having((e) => e.durum, 'durum', 400)));
    });
  });

  group('Başlık değerleri', () {
    test('bozuk yüzde kodlaması ve satır sonu reddedilir', () {
      expect(basliktanCoz('dilek%C3%A7e.pdf'), 'dilekçe.pdf');
      expect(() => basliktanCoz('%E0%A4%A'), throwsA(isA<ApiHatasi>()));
      expect(() => basliktanCoz('a%0D%0Aset-cookie:x'), throwsA(isA<ApiHatasi>()));
      expect(() => basliktanCoz('a%00.pdf'), throwsA(isA<ApiHatasi>()));
    });
  });

  group('Güvenlik başlıkları', () {
    test('her yanıtta (hata dahil) eklenir; iç hata ayrıntısı dönmez', () async {
      final h = hataVeGuvenlik()((_) => throw StateError('gizli ayrıntı: /etc/passwd'));
      final r = await h(_istek('dosyalar', yontem: 'GET'));
      expect(r.statusCode, 500);
      final govde = await r.readAsString();
      expect(govde, isNot(contains('passwd')));
      expect(jsonDecode(govde)['hata'], 'sunucu');
      for (final b in ['x-content-type-options', 'x-frame-options', 'strict-transport-security', 'content-security-policy',
        'referrer-policy', 'cache-control']) {
        expect(r.headers[b], isNotNull, reason: b);
      }
      expect(r.headers['content-security-policy'], contains("frame-ancestors 'none'"));
    });
  });

  group('CORS', () {
    test('izinsiz köken için izin başlığı yok, ön uçuş 403', () async {
      final h = cors({'https://app.hukukportali.com.tr'})((_) => Response.ok('ok'));
      final kotu = await h(_istek('dosyalar', yontem: 'GET', basliklar: {'origin': 'https://saldirgan.example'}));
      expect(kotu.headers['access-control-allow-origin'], isNull);
      final ucus = await h(_istek('dosyalar', yontem: 'OPTIONS', basliklar: {'origin': 'https://saldirgan.example'}));
      expect(ucus.statusCode, 403);
      final iyi = await h(_istek('dosyalar', yontem: 'GET', basliklar: {'origin': 'https://app.hukukportali.com.tr'}));
      expect(iyi.headers['access-control-allow-origin'], 'https://app.hukukportali.com.tr');
    });
  });

  group('Oturum', () {
    test('token yoksa veya Bearer değilse 401 (veritabanına gidilmez)', () async {
      final h = oturumDogrula(_SahteVt())((_) => Response.ok('ok'));
      expect(() => h(_istek('dosyalar', yontem: 'GET')), throwsA(isA<ApiHatasi>().having((e) => e.durum, 'durum', 401)));
      expect(() => h(_istek('dosyalar', yontem: 'GET', basliklar: {'authorization': 'Basic eDp5'})),
          throwsA(isA<ApiHatasi>().having((e) => e.durum, 'durum', 401)));
    });
  });
}

/// Hiç çağrılmaması gereken veritabanı: çağrılırsa test başarısız olur.
class _SahteVt implements Veritabani {
  @override
  dynamic noSuchMethod(Invocation invocation) => fail('Veritabanına gidilmemeliydi: ${invocation.memberName}');
}
