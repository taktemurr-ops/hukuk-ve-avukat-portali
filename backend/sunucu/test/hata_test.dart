import 'dart:convert';

import 'package:hukuk_sunucu/hukuk_sunucu.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  Handler sar(Handler h) => const Pipeline().addMiddleware(hataVeGuvenlik()).addHandler(h);
  final istek = Request('GET', Uri.parse('http://yerel/x'));

  test('ApiHatasi JSON ve doğru durum koduna çevrilir', () async {
    final y = await sar((_) => throw ApiHatasi.yetkisiz)(istek);
    expect(y.statusCode, 401);
    expect(jsonDecode(await y.readAsString()), {'hata': 'yetkisiz', 'mesaj': 'Oturum açmanız gerekiyor.'});
    expect(y.headers['x-content-type-options'], 'nosniff');
    expect(y.headers['cache-control'], 'no-store');
  });

  test('beklenmeyen hata ayrıntısı istemciye gitmez', () async {
    Object? kaydedilen;
    final h = const Pipeline()
        .addMiddleware(hataVeGuvenlik(kaydet: (e, _) => kaydedilen = e))
        .addHandler((_) => throw StateError('gizli iç ayrıntı'));
    final y = await h(istek);
    expect(y.statusCode, 500);
    expect(await y.readAsString(), isNot(contains('gizli')));
    expect(kaydedilen, isA<StateError>());
  });

  test('CORS yalnızca izinli kökene', () async {
    final h = const Pipeline().addMiddleware(cors({'https://app.ornek.com.tr'})).addHandler((_) => Response.ok('x'));
    final izinli = await h(Request('GET', Uri.parse('http://yerel/x'), headers: {'origin': 'https://app.ornek.com.tr'}));
    expect(izinli.headers['access-control-allow-origin'], 'https://app.ornek.com.tr');
    final yabanci = await h(Request('OPTIONS', Uri.parse('http://yerel/x'), headers: {'origin': 'https://kotu.com'}));
    expect(yabanci.statusCode, 403);
  });

  test('oturumsuz istek reddedilir (veritabanına gitmeden)', () async {
    final h = const Pipeline()
        .addMiddleware(hataVeGuvenlik())
        .addMiddleware(oturumDogrula(Veritabani.ortamdan(const {})))
        .addHandler((_) => Response.ok('gizli'));
    final y = await h(Request('GET', Uri.parse('http://yerel/dosyalar')));
    expect(y.statusCode, 401);
    final saglik = await h(Request('GET', Uri.parse('http://yerel/saglik')));
    expect(saglik.statusCode, 200);
  });
}
